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
foreach ($kv in @(@{k="pure"; n="一鍵安裝包"}, @{k="guild"; n="公會專用版"})) {
    $file = "SpiritVale_繁中翻譯_$($kv.n)_v$Version.zip"
    $path = Join-Path $Root $file
    if (-not (Test-Path -LiteralPath $path)) { Die "找不到安裝包:$file`n     先跑 pack.ps1 打包" }
    $h = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToUpperInvariant()
    $sz = (Get-Item -LiteralPath $path).Length
    $pkgs[$kv.k] = [ordered]@{
        file   = $file
        url    = "https://github.com/$Owner/$Repo/releases/download/v$Version/$file"
        size   = $sz
        sha256 = $h
    }
    Ok "$($kv.n)  $([math]::Round($sz/1MB,2)) MB  $($h.Substring(0,16))…"
}

# ── 2. 組 version.json ──
#   ★ min_tool:舊版設定工具若低於這個版本就只提示「請手動下載」不自動更新
#     (將來若更新流程改格式,舊工具不會誤解新格式)
$obj = [ordered]@{
    schema   = 1
    version  = $Version
    released = (Get-Date -Format "yyyy-MM-dd")
    notes    = "https://github.com/$Owner/$Repo/releases/tag/v$Version"
    min_tool = "3.76.4"
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
