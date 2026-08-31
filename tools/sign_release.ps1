# ══════════════════════════════════════════════════════════════════════
#  sign_release.ps1 —— 產生並簽署 version.json(每次發佈跑一次)
#
#  用法:  .\tools\sign_release.ps1 -Version 3.76.4
#         .\tools\sign_release.ps1 -Version 3.76.4 -Owner SillyGirlsBoy -Repo SpiritVale-ModsTool
#
#  它會做的事:
#   1. 找到兩個 ZIP(純翻譯包 / 公會專用版)並算 SHA256 與大小
#   2. 組出 version.json(版本、下載網址、雜湊、公告連結)
#   3. 用私鑰簽出 version.json.sig
#   4. 用公鑰【自己先驗一次】—— 驗不過就不產出檔案(免得發出去才發現壞的)
#
#  發佈時把這三個東西上傳到 GitHub Release:
#     兩個 ZIP + version.json + version.json.sig
#  另外把 version.json / version.json.sig 也放進 repo 根目錄(工具讀 raw 連結,
#  不吃 GitHub API 的速率限制)。
# ══════════════════════════════════════════════════════════════════════
param(
    [Parameter(Mandatory = $true)][string]$Version,
    [string]$Owner = "SillyGirlsBoy",
    [string]$Repo  = "SpiritVale-ModsTool",
    [string]$Root  = "",
    [string]$PrivPath = "G:\SpiritZh_簽章金鑰\private.xml"
)
$ErrorActionPreference = "Stop"
if ($Root -eq "") { $Root = Split-Path -Parent $PSScriptRoot }

function Die([string]$m) { Write-Host "  ✘ $m" -ForegroundColor Red; exit 1 }
function Ok([string]$m)  { Write-Host "  ✔ $m" -ForegroundColor Green }

Write-Host ""
Write-Host "  SpiritZh 發佈簽署 —— v$Version" -ForegroundColor Cyan
Write-Host "  ────────────────────────────────────────" -ForegroundColor DarkGray

if (-not (Test-Path -LiteralPath $PrivPath)) { Die "找不到私鑰:$PrivPath`n     還沒產生過的話請先跑 tools\make_keys.ps1" }
$pubPath = Join-Path $PSScriptRoot "public_key.xml"
if (-not (Test-Path -LiteralPath $pubPath)) { Die "找不到公鑰:$pubPath" }

# ── 1. 找 ZIP、算雜湊 ──
$pkgs = @{}
# ★ GitHub Release 的附件檔名不接受非 ASCII:它會把中文整段換成「.」,
#   兩個版本會撞成同一個 SpiritVale_._._vX.Y.Z.zip(第二個直接被拒),
#   而且 version.json 的下載連結會指到不存在的檔名 → 自動更新按了必失敗。
#   所以:本機 ZIP 名稱維持中文(巴哈發佈照舊),另外複製一份 ASCII 名上傳 GitHub,
#   version.json 的 file/url 一律用 ASCII 名。
foreach ($kv in @(@{k="pure"; n="一鍵安裝包"; a="Pure"}, @{k="guild"; n="公會專用版"; a="Guild"})) {
    $file = "SpiritVale_繁中翻譯_$($kv.n)_v$Version.zip"
    $path = Join-Path $Root $file
    if (-not (Test-Path -LiteralPath $path)) { Die "找不到安裝包:$file`n     先跑 pack.ps1 打包" }
    $asset = "SpiritVale_zhTW_$($kv.a)_v$Version.zip"          # 上傳用的 ASCII 檔名
    $apath = Join-Path $Root $asset
    Copy-Item -LiteralPath $path -Destination $apath -Force
    $h = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToUpperInvariant()
    $sz = (Get-Item -LiteralPath $path).Length
    $pkgs[$kv.k] = [ordered]@{
        file   = $asset
        url    = "https://github.com/$Owner/$Repo/releases/download/v$Version/$asset"
        size   = $sz
        sha256 = $h
    }
    Ok "$($kv.n)  $([math]::Round($sz/1MB,2)) MB  $($h.Substring(0,16))…  → $asset"
}

# ── 2. 組 version.json ──
#   ★ min_tool:舊版設定工具若低於這個版本就只提示「請手動下載」不自動更新
#     (將來若更新流程改格式,舊工具不會誤解新格式)
# ── 更新摘要 ──
#   放在 更新摘要_v<版本>.txt(一行一條,# 開頭是註解)。
#   ★ 它會【跟其他欄位一起被簽】—— 中途被人改過就驗不過,不可能被拿來塞廣告或釣魚連結。
#   沒有這個檔也不會怎樣,只是更新提示不會列出改了什麼。
$chgPath = Join-Path $Root ("更新摘要_v" + $Version + ".txt")
$changes = @()
if (Test-Path -LiteralPath $chgPath) {
    $changes = @(Get-Content -LiteralPath $chgPath -Encoding UTF8 |
                 ForEach-Object { $_.Trim() } |
                 Where-Object { $_ -ne "" -and -not $_.StartsWith("#") })
    Ok ("更新摘要 " + $changes.Count + " 條")
} else {
    Write-Host ("   [!] 沒有 " + (Split-Path -Leaf $chgPath) + " —— 更新提示不會列出改了什麼") -ForegroundColor Yellow
}

# ── 公會白名單(v3.76.6)──
#   讀 tools\公會名單.txt,算雜湊,【獨立簽一段】放進 version.json。
#   ★ 為什麼要獨立簽:外掛端讀的是設定工具落下來的 SpiritZh_guilds.dat,
#     那個檔離開 version.json 之後就沒有整包簽章保護了,所以它必須自己帶簽章。
#   ★ 網域前綴 SVZH-GLD1:同一把金鑰已經在簽 version.json 與序號(SVZH-LIC1),
#     沒有前綴的話三者可能互相冒用。
#   payload = "SVZH-GLD1|<清單序號>|<簽發日 yyyyMMdd>|<雜湊:到期日,...>"
$guildsPath = Join-Path $PSScriptRoot "公會名單.txt"
$guildsSigned = ""
$gEntries = @()
$gNames   = @()

# ── 撤銷名單(v3.76.12;2026-08-31 大修)────────────────────────────
#   tools\撤銷序號.txt:一行一個【序號編號】(發序號時印出來的 8 碼,也記在 序號發放紀錄.txt 第 6 欄)。
#   # 或 // 開頭是註解。編號後面【空一格】再寫備註。沒有這個檔就是「沒有撤銷任何東西」。
#   ★ 搭公會清單同一段簽章走,不新增任何通道;舊版外掛會直接忽略第 5 欄(向後相容)。
#
#   ⚠⚠ 這一段以前有一個【無回饋的失效迴路】,2026-08-31 稽核才抓到,四層同時失效:
#      (1) 解析不出來的行【靜默略過】(沒有 else);
#      (2) 訊息只在 $revIds.Count -gt 0 才印 —— 全部解析失敗時一個字都不印;
#      (3) 撤銷序號.txt 叫你用 檢查公會名單.ps1 複查,但那支根本不讀第 5 欄;
#      (4) 管理器那邊的規則沒有結尾錨點,對同一行會說「已撤銷」。
#      合起來:你寫「3de737d8-外流到Discord」,管理器跟你說殺掉了,這裡整行丟掉,
#      對方照用,而且沒有任何管道會告訴你。實測重現過。
#      ⇒ 現在改成【解析不出來就 Die,擋下整個發布】。撤銷是低頻高風險操作,
#        寧可擋下發布,也絕不能靜默略過。
#   ⚠ 規則必須跟 SpiritZh_Serial.ps1 的 Read-RevokeList 逐字相同:
#     空白切第一段、必須【正好 8 碼】hex(make_serial.ps1 L149 是 4 bytes)。
$revPath = Join-Path $PSScriptRoot "撤銷序號.txt"
$revIds = @()
if (Test-Path -LiteralPath $revPath) {
    foreach ($ln in (Get-Content -LiteralPath $revPath -Encoding UTF8)) {
        $s = $ln.Trim().TrimStart([char]0xFEFF)
        if ($s.Length -eq 0 -or $s.StartsWith("//") -or $s.StartsWith("#")) { continue }
        $id = ($s -split '\s+')[0].Trim()
        if ($id -match '^[0-9a-fA-F]{8}$') { $revIds += $id.ToLowerInvariant() }
        else {
            Die ("撤銷序號.txt 這行看不懂:「" + $s + "」" + [Environment]::NewLine +
                 "       格式是【8 碼十六進位編號】+ 一個空格 + 備註,例如:" + [Environment]::NewLine +
                 "           3de737d8 外流到 Discord" + [Environment]::NewLine +
                 "       不能用 - 或 : 直接接備註(那樣編號會被讀成「3de737d8-外流到」)。" + [Environment]::NewLine +
                 "       編號在 序號發放紀錄.txt 最後一欄。")
        }
    }
    $revIds = @($revIds | Select-Object -Unique)
}
# ★ 無條件出聲,0 組也要印 —— 讓「這次沒撤銷任何東西」是【看得見的事實】,
#   而不是靠沒有訊息去推論。並且把編號列出來給你目視核對。
if ($revIds.Count -gt 0) { Ok ("撤銷名單 " + $revIds.Count + " 組:" + ($revIds -join ", ")) }
else { Ok "撤銷名單 0 組(這一版不撤銷任何序號)" }

if (Test-Path -LiteralPath $guildsPath) {
    foreach ($ln in (Get-Content -LiteralPath $guildsPath -Encoding UTF8)) {
        $t = $ln.Trim().TrimStart([char]0xFEFF)
        if ($t.Length -eq 0 -or $t.StartsWith("//") -or $t.StartsWith("#")) { continue }
        $eq = $t.IndexOf("=")
        if ($eq -le 0) { Die ("公會名單.txt 這行看不懂(要 公會名=到期日):" + $t) }
        $gName = $t.Substring(0, $eq).Trim()
        $gExp  = $t.Substring($eq + 1).Trim()
        if ($gName.Length -eq 0) { Die ("公會名單.txt 有一行公會名是空的:" + $t) }
        # 到期日:0 = 永久;yyyy-MM-dd = 年費
        if ($gExp -eq "0") { $gNum = "0" }
        else {
            $gd = [datetime]::MinValue
            if (-not [datetime]::TryParseExact($gExp, "yyyy-MM-dd", [Globalization.CultureInfo]::InvariantCulture,
                                               [Globalization.DateTimeStyles]::None, [ref]$gd)) {
                Die ("公會「" + $gName + "」的到期日要是 0 或 yyyy-MM-dd,收到的是「" + $gExp + "」")
            }
            if ($gd.Date -lt (Get-Date).Date) {
                Write-Host ("   [!] 公會「" + $gName + "」的到期日 " + $gExp + " 已經過去了 —— 簽出去等於沒有效果") -ForegroundColor Yellow
            }
            $gNum = $gd.ToString("yyyyMMdd")
        }
        # ★ 正規化必須跟外掛的 NormGuild 一模一樣:剝 <標籤> → NFKC → Trim → 小寫
        $gNorm = ([regex]::Replace($gName, '<[^>]*>', '')).Normalize([Text.NormalizationForm]::FormKC).Trim().ToLowerInvariant()
        if ($gNorm.Length -eq 0) { Die ("公會「" + $gName + "」剝掉 <...> 之後變成空的,不能簽") }
        $gh = New-Object System.Security.Cryptography.SHA256Managed
        try { $gHex = (($gh.ComputeHash([Text.Encoding]::UTF8.GetBytes($gNorm)) | ForEach-Object { $_.ToString("x2") }) -join "") }
        finally { $gh.Dispose() }
        if ($gNames -contains $gNorm) { Die ("公會名單.txt 裡「" + $gName + "」重複了") }
        $gNames   += $gNorm
        $gEntries += ($gHex + ":" + $gNum)
    }
} else {
    Write-Host "   [!] 沒有 tools\公會名單.txt —— 這一版不帶外部公會清單(只有內建名單生效)" -ForegroundColor Yellow
}

# ★ 簽章條件是「有公會【或】有撤銷」。
#   舊版是 if ($gEntries.Count -gt 0),而且整段撤銷讀取被包在【那個 if 裡面】——
#   意思是哪天你把公會名單清空或全部註解掉,撤銷通道會【整條無聲消失】,
#   version.json 裡不再帶第 5 欄,已經撤銷的序號全部復活,而且沒有任何訊息。
#   兩件事本來就無關,不該綁在一起。
if ($gEntries.Count -gt 0 -or $revIds.Count -gt 0) {
        # 清單序號:用簽發日 + 當天序號,單調遞增,方便日後排查「他手上是哪一版」
        $gSerial = (Get-Date -Format "yyyyMMddHHmm")
        $gPayload = "SVZH-GLD1|" + $gSerial + "|" + (Get-Date -Format "yyyyMMdd" -ErrorAction SilentlyContinue) + "|" + ($gEntries -join ",") + "|" + ($revIds -join ",")
        $gBytes = [Text.Encoding]::UTF8.GetBytes($gPayload)
        $gRsa = [System.Security.Cryptography.RSA]::Create()
        try {
            $gRsa.FromXmlString((Get-Content -LiteralPath $PrivPath -Raw -Encoding UTF8))
            $gSig = $gRsa.SignData($gBytes, [System.Security.Cryptography.HashAlgorithmName]::SHA256,
                                   [System.Security.Cryptography.RSASignaturePadding]::Pkcs1)
        } finally { $gRsa.Dispose() }
        # 自我驗證:驗不過就不輸出(寧可不發,也不能發一份沒人驗得過的清單)
        $gVer = [System.Security.Cryptography.RSA]::Create()
        try {
            $gVer.FromXmlString((Get-Content -LiteralPath $pubPath -Raw -Encoding UTF8))
            $gOk = $gVer.VerifyData($gBytes, $gSig, [System.Security.Cryptography.HashAlgorithmName]::SHA256,
                                    [System.Security.Cryptography.RSASignaturePadding]::Pkcs1)
        } finally { $gVer.Dispose() }
        if (-not $gOk) { Die "公會清單自我驗證沒過 —— 公私鑰可能不是同一對" }
        function B64UrlG([byte[]]$x) { ([Convert]::ToBase64String($x)).TrimEnd('=').Replace('+','-').Replace('/','_') }
        $guildsSigned = (B64UrlG $gBytes) + "." + (B64UrlG $gSig)
        # 只有撤銷、沒有公會時不要印「公會清單 0 個」—— 那會讓人以為公會名單被吃掉了
        if ($gEntries.Count -gt 0) {
            Ok ("公會清單 " + $gEntries.Count + " 個(已簽章,第 " + $gSerial + " 版)")
        } else {
            Ok ("只帶撤銷名單,不帶公會清單(已簽章,第 " + $gSerial + " 版)")
        }
}

$obj = [ordered]@{
    schema   = 1
    version  = $Version
    released = (Get-Date -Format "yyyy-MM-dd")
    changes  = $changes
    notes    = "https://github.com/$Owner/$Repo/releases/tag/v$Version"
    min_tool = "3.76.4"
    guilds   = $guildsSigned
    packages = $pkgs
}
$json = ($obj | ConvertTo-Json -Depth 6)
# 統一成 UTF-8 無 BOM + LF:簽章是對【位元組】做的,換行或 BOM 差一個位元就驗不過
$json = $json -replace "`r`n", "`n"
$bytes = [System.Text.Encoding]::UTF8.GetBytes($json)

# ── 3. 簽章 ──
$rsa = [System.Security.Cryptography.RSA]::Create()
try {
    $rsa.FromXmlString((Get-Content -LiteralPath $PrivPath -Raw -Encoding UTF8))
    $sig = $rsa.SignData($bytes, [System.Security.Cryptography.HashAlgorithmName]::SHA256,
                         [System.Security.Cryptography.RSASignaturePadding]::Pkcs1)
} finally { $rsa.Dispose() }
$sigB64 = [Convert]::ToBase64String($sig)

# ── 4. 自我驗證(驗不過就不寫檔)──
$ver = [System.Security.Cryptography.RSA]::Create()
try {
    $ver.FromXmlString((Get-Content -LiteralPath $pubPath -Raw -Encoding UTF8))
    $okSig = $ver.VerifyData($bytes, [Convert]::FromBase64String($sigB64),
                             [System.Security.Cryptography.HashAlgorithmName]::SHA256,
                             [System.Security.Cryptography.RSASignaturePadding]::Pkcs1)
} finally { $ver.Dispose() }
if (-not $okSig) { Die "自我驗證沒過 —— 公私鑰不是一對?先確認 tools\public_key.xml 是用同一次 make_keys 產的" }
Ok "自我驗證通過(公鑰驗得過自己簽的章)"

# ── 5. 寫檔 ──
$jsonPath = Join-Path $Root "version.json"
$sigPath  = Join-Path $Root "version.json.sig"
[System.IO.File]::WriteAllBytes($jsonPath, $bytes)                      # 無 BOM、LF
[System.IO.File]::WriteAllText($sigPath, $sigB64, [System.Text.UTF8Encoding]::new($false))

Write-Host ""
Ok "version.json      $jsonPath"
Ok "version.json.sig  $sigPath"
Write-Host ""
Write-Host "  發佈步驟:" -ForegroundColor Cyan
Write-Host "   1. GitHub → Releases → Draft a new release,tag 填  v$Version"
Write-Host "   2. 上傳 4 個檔:兩個 ZIP + version.json + version.json.sig"
Write-Host "   3. 把 version.json / version.json.sig 一起 commit 進 repo 根目錄"
Write-Host "      (設定工具讀的是 raw 連結,不吃 GitHub API 的速率限制)"
Write-Host "   4. 公告內容用 巴哈更新公告_v$Version.md"
Write-Host ""
