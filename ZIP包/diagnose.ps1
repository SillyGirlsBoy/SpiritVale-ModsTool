# SpiritVale 繁中翻譯 — 一鍵診斷(只讀取資訊,不修改任何東西)
param([string]$GamePath = "", [string]$OutFile = "", [switch]$Quiet)
$ErrorActionPreference = "SilentlyContinue"
$R = New-Object System.Collections.ArrayList
function W([string]$s) { [void]$R.Add($s); Write-Host $s }
function Q([string]$s) { return '"' + $s + '"' }

W "===================================================="
W " SpiritVale 繁中翻譯 診斷報告"
W " 產生時間:$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
W "===================================================="
W ""

# ---- 系統 ----
W "[系統]"
try {
    $os = Get-CimInstance Win32_OperatingSystem
    W "  Windows      : $($os.Caption) ($($os.Version))"
} catch { W "  Windows      : (讀取失敗)" }
W "  PowerShell   : $($PSVersionTable.PSVersion)"
W "  64 位元行程  : $([Environment]::Is64BitProcess)"
try {
    Add-Type -AssemblyName System.Drawing -ErrorAction Stop
    $bm9 = New-Object System.Drawing.Bitmap 1, 1
    $gg9 = [System.Drawing.Graphics]::FromImage($bm9)
    $dpi9 = [int]$gg9.DpiX
    $gg9.Dispose(); $bm9.Dispose()
    W ("  螢幕縮放     : " + [int]($dpi9 / 96 * 100) + "%  (" + $dpi9 + " DPI)")
    if ($dpi9 -gt 96) { W "                 ※ 非 100% 縮放 —— 設定工具版面若有重疊請更新到 v3.56 以上" }
} catch {}
W ""

# 智慧型應用程式控制(Smart App Control):Windows 11 的核心層程式碼管制。
# 它會擋掉「沒有簽章又沒有信譽」的 DLL —— BepInEx 每次生成的 interop 組件正是如此。
# 注意:它和防毒是兩套獨立系統,加防毒排除【完全不會】讓它放行。
# 回傳:0=關閉 1=強制執行(會擋) 2=評估中 -1=無此功能/讀不到
function Get-SacState {
    try {
        $k = "HKLM:\SYSTEM\CurrentControlSet\Control\CI\Policy"
        if (-not (Test-Path $k)) { return -1 }
        $v = (Get-ItemProperty -Path $k -ErrorAction Stop).VerifiedAndReputablePolicyState
        if ($null -eq $v) { return -1 }
        return [int]$v
    } catch { return -1 }
}

# ---- 找遊戲 ----
function Test-Game([string]$p) {
    if ([string]::IsNullOrWhiteSpace($p)) { return $false }
    try { return (Test-Path ($p.TrimEnd('\') + "\SpiritVale.exe")) } catch { return $false }
}
function Find-SteamPath {
    foreach ($k in @("HKCU:\Software\Valve\Steam", "HKLM:\SOFTWARE\WOW6432Node\Valve\Steam", "HKLM:\SOFTWARE\Valve\Steam")) {
        foreach ($n in @("SteamPath", "InstallPath")) {
            try { $v = (Get-ItemProperty -Path $k -ErrorAction Stop).$n; if ($v) { return ($v -replace "/", "\") } } catch {}
        }
    }
    return $null
}
function Get-SteamLibraries {
    $libs = @(); $steam = Find-SteamPath
    if ($steam) { $libs += $steam }
    foreach ($rel in @("steamapps\libraryfolders.vdf", "config\libraryfolders.vdf")) {
        if (-not $steam) { break }
        $vdf = $steam.TrimEnd('\') + "\" + $rel
        try {
            if (Test-Path $vdf) {
                $txt = Get-Content $vdf -Raw -ErrorAction Stop
                foreach ($m in [regex]::Matches($txt, '"path"\s*"([^"]+)"')) { $libs += ($m.Groups[1].Value -replace "\\\\", "\") }
            }
        } catch {}
    }
    return ($libs | Select-Object -Unique)
}
if (-not (Test-Game $GamePath)) {
    $cands = @()
    foreach ($lib in (Get-SteamLibraries)) { $cands += ($lib.TrimEnd('\') + "\steamapps\common\SpiritVale") }
    foreach ($d in @("C", "D", "E", "F", "G", "H")) {
        $cands += "$($d):\SteamLibrary\steamapps\common\SpiritVale"
        $cands += "$($d):\Program Files (x86)\Steam\steamapps\common\SpiritVale"
        $cands += "$($d):\Steam\steamapps\common\SpiritVale"
        $cands += "$($d):\Games\Steam\steamapps\common\SpiritVale"
    }
    foreach ($c in $cands) { if (Test-Game $c) { $GamePath = $c; break } }
}
W "[遊戲位置]"
if (Test-Game $GamePath) {
    W "  找到:$GamePath"
    $ascii = $true
    foreach ($ch in $GamePath.ToCharArray()) { if ([int]$ch -gt 127) { $ascii = $false } }
    if (-not $ascii) { W "  ！路徑含非英文字元,可能造成外掛啟動失敗" }
} else {
    W "  ！找不到遊戲(Steam 登錄檔與常見路徑都掃過了)"
    W "  → 請把 SpiritVale 資料夾路徑貼給作者"
}
W ""

# ---- 檔案完整性 ----
W "[外掛檔案]"
if (Test-Game $GamePath) {
    $need = @("winhttp.dll", "doorstop_config.ini", ".doorstop_version",
              "dotnet\coreclr.dll", "dotnet\System.Private.CoreLib.dll",
              "BepInEx\core\BepInEx.Unity.IL2CPP.dll", "BepInEx\core\BepInEx.Core.dll",
              "BepInEx\plugins\SpiritZh.dll", "BepInEx\plugins\SpiritZh_dict.txt",
              "BepInEx\plugins\SpiritZh_terms.txt", "BepInEx\plugins\SpiritZh_mode.txt",
              # names.txt 原本不在清單裡 —— 但設定工具的「指定物品」2400 項就是靠它,
              # 少了它清單會變空的,而報告卻一切正常。網友實際踩過,補進來。
              "BepInEx\plugins\SpiritZh_names.txt", "BepInEx\plugins\SpiritZh_monsters.txt",
              "BepInEx\plugins\SpiritZh_maps.txt")
    $miss = 0
    foreach ($f in $need) {
        $p = $GamePath.TrimEnd('\') + "\" + $f
        if (Test-Path $p) {
            $sz = (Get-Item $p).Length
            $blocked = ""
            try { if (Get-Item -Path $p -Stream Zone.Identifier -ErrorAction Stop) { $blocked = "  ！被「網路下載」標記封鎖" } } catch {}
            W ("  OK   {0,-46} {1,10} bytes{2}" -f $f, $sz, $blocked)
        } else {
            $miss++
            W ("  缺!  {0}" -f $f)
        }
    }
    if ($miss -gt 0) { W "  → 有 $miss 個檔案不見了,極可能被防毒刪除;請加防毒排除後重跑安裝" }
    foreach ($d in @("dotnet", "BepInEx\core", "BepInEx\unity-libs", "BepInEx\interop", "BepInEx\cache")) {
        $p = $GamePath.TrimEnd('\') + "\" + $d
        if (Test-Path $p) {
            $n = (Get-ChildItem $p -Recurse -File -ErrorAction SilentlyContinue | Measure-Object).Count
            W ("  資料夾 {0,-24} {1} 個檔案" -f $d, $n)
        } else { W ("  資料夾 {0,-24} 不存在" -f $d) }
    }
} else { W "  (略過:未找到遊戲)" }
W ""

# ---- 防毒排除 ----
W "[防毒排除]"
try {
    $ex = (Get-MpPreference -ErrorAction Stop).ExclusionPath
    # 非管理員身分時 Defender 不回傳清單,而是回一句 "N/A: Must be an administrator..." — 別把它當成清單內容
    $denied = $false
    foreach ($e in @($ex)) { if ("$e" -like "N/A:*") { $denied = $true } }
    if ($denied) { W "  無法查看(需要系統管理員權限才能讀排除清單)— 此項無法判定" }
    elseif ($ex -and ($ex -contains $GamePath)) { W "  已包含遊戲資料夾 — 正常" }
    # ★★ v3.76.12:【絕對不要】把整份排除清單倒進報告。
    #   那裡面是使用者所有其他遊戲/工具/私人資料夾的路徑 —— 是不折不扣的個資,
    #   而這份報告是要公開貼給作者、甚至貼在論壇的。報告結尾還寫著「不含個人資料」,
    #   等於自己打自己的臉。只回報「有沒有含遊戲資料夾」這一個事實就夠診斷了。
    elseif ($ex) { W ("  未包含遊戲資料夾(清單裡有 " + @($ex).Count + " 筆其他項目,為保護隱私不列出)") }
    else { W "  排除清單是空的 — 未加入遊戲資料夾" }
} catch { W "  無法讀取(可能未使用 Windows Defender,或用第三方防毒)" }
W ""

# ---- 智慧型應用程式控制 ----
W "[智慧型應用程式控制 Smart App Control]"
$sac = Get-SacState
if ($sac -eq 1) {
    W "  開啟(強制執行)—— ！這會封鎖外掛,且防毒排除無法繞過"
    W "    症狀:遊戲啟動時出現「應用程式控制原則已封鎖此檔案 (0x800711C7)」"
    W "    解法:Windows 安全性 → 應用程式與瀏覽器控制 → 智慧型應用程式控制設定 → 關閉"
    W "    ※注意:關閉後無法再開啟(需重灌 Windows 才能恢復),請自行斟酌"
} elseif ($sac -eq 2) {
    W "  評估中 —— 隨時可能自動轉為強制執行,屆時會封鎖外掛"
} elseif ($sac -eq 0) {
    W "  已關閉 — 不會影響外掛"
} else {
    W "  此系統無此功能(或讀取不到)"
}
W ""

# ---- VC++ 執行階段 ----
W "[Visual C++ 執行階段 x64]"
$vc = $false
foreach ($k in @("HKLM:\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64",
                 "HKLM:\SOFTWARE\WOW6432Node\Microsoft\VisualStudio\14.0\VC\Runtimes\x64")) {
    try {
        $v = Get-ItemProperty -Path $k -ErrorAction Stop
        if ($v.Installed -eq 1) { W "  已安裝:$($v.Major).$($v.Minor).$($v.Bld).$($v.Rbld)"; $vc = $true; break }
    } catch {}
}
if (-not $vc) { W "  ！未偵測到 — 請安裝 https://aka.ms/vs/17/release/vc_redist.x64.exe" }
W ""

# ---- 外掛狀態 ----
W "[外掛狀態]"
if (Test-Game $GamePath) {
    # 音效/畫面設定與音效檔(排查「音效沒播」)
    # ★ quality.txt 一定要在清單裡:它管【進階濾鏡面板位移/查市價/DPS 面板/詞條品質】——
    #   v3.70 有網友回報「面板不能移動、最低價沒出現」,而那次的報告剛好沒有這個檔,
    #   等於報告裡完全沒有能判斷的資訊,白跑一輪。
    foreach ($cf in @("SpiritZh_audio.txt", "SpiritZh_filter.txt", "SpiritZh_view.txt", "SpiritZh_beam.txt", "SpiritZh_gui.txt", "SpiritZh_quality.txt", "SpiritZh_font.txt", "SpiritZh_cursor.txt")) {
        $p9 = Join-Path $GamePath ("BepInEx\plugins\" + $cf)
        if (Test-Path -LiteralPath $p9) {
            W ("  [設定] " + $cf + ":")
            # 註解行不列(quality.txt 的說明很長),只列真正生效的設定行
            $keep9 = @()
            foreach ($l9 in (Get-Content -LiteralPath $p9 -Encoding UTF8)) {
                $t9 = $l9.Trim()
                if ($t9.Length -eq 0) { continue }
                if ($t9.StartsWith("//") -or $t9.StartsWith("#")) { continue }
                $keep9 += $t9
            }
            if ($keep9.Count -eq 0) { W "      (全部是註解,等於全用預設值)" }
            else { foreach ($l9 in ($keep9 | Select-Object -First 40)) { W ("      " + $l9) } }
        } else { W ("  [設定] " + $cf + ":(不存在)") }
    }
    $sd9 = Join-Path $GamePath "BepInEx\plugins\SpiritZh_sounds"
    if (Test-Path -LiteralPath $sd9) {
        W "  [音效檔] SpiritZh_sounds:"
        foreach ($f9 in (Get-ChildItem -LiteralPath $sd9 -File | Select-Object -First 12)) { W ("      " + $f9.Name + "(" + [int]($f9.Length/1kb) + " KB)") }
    } else { W "  [音效檔] SpiritZh_sounds 資料夾不存在" }
    # 開場音樂(工具資料夾的同名檔優先於隨包附帶的)
    $intro9 = ""
    foreach ($d9 in @($PSScriptRoot, (Join-Path $PSScriptRoot "payload\BepInEx\plugins"), (Join-Path $GamePath "BepInEx\plugins"))) {
        foreach ($x9 in @("wav", "mp3", "mp4", "m4a", "wma", "ogg", "flac")) {
            $c9 = Join-Path $d9 ("SpiritZh_intro." + $x9)
            try { if ((Test-Path -LiteralPath $c9) -and $intro9 -eq "") { $intro9 = $c9 } } catch {}
        }
    }
    if ($intro9 -ne "") { W ("  [開場音樂] " + $intro9 + "(" + [int]((Get-Item -LiteralPath $intro9).Length/1kb) + " KB)") }
    else { W "  [開場音樂] 找不到 SpiritZh_intro.*(開場畫面會只跑動畫、不出聲)" }
    try {
        $pd9 = Join-Path $PSScriptRoot "payload\BepInEx\plugins\SpiritZh.dll"
        $gd9 = Join-Path $GamePath "BepInEx\plugins\SpiritZh.dll"
        if ((Test-Path -LiteralPath $pd9) -and (Test-Path -LiteralPath $gd9)) {
            $same9 = ((Get-FileHash -LiteralPath $pd9 -Algorithm SHA256).Hash -eq (Get-FileHash -LiteralPath $gd9 -Algorithm SHA256).Hash)
            W ("  [版本] 安裝包外掛與遊戲內外掛" + $(if ($same9) { "一致" } else { "不一致!請按「安裝 / 更新翻譯」更新" }))
            # ★ 狀態檔是【上次跑遊戲的那個版本】寫的:剛安裝完還沒開過遊戲就跑診斷,底下那些狀態全是舊版的。
            #   網友實例:status.txt 寫 v3.73、DLL 已是 v3.75,報告裡看不到任何 3.75 的東西,白跑一趟。
            try {
                $dv9 = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($gd9).ProductVersion
                $sp9 = Join-Path $GamePath "BepInEx\plugins\SpiritZh_status.txt"
                if ($dv9 -and (Test-Path -LiteralPath $sp9)) {
                    $sl9 = (Get-Content -LiteralPath $sp9 -Encoding UTF8 -TotalCount 1)
                    if ($sl9 -match 'SpiritZh v([0-9.]+)' -and $Matches[1] -ne $dv9) {
                        W ("  [注意] 狀態檔是 v" + $Matches[1] + " 寫的,但遊戲裡的外掛已是 v" + $dv9 + " —— 你還沒用新版開過遊戲。")
                        W ("         請先開一次遊戲、進到角色、等 10 秒,再跑一次診斷,下面的狀態才是新版的。")
                    }
                }
            } catch {}
        }
    } catch {}
    foreach ($f in @("BepInEx\plugins\SpiritZh_mode.txt", "BepInEx\plugins\SpiritZh_status.txt")) {
        $p = $GamePath.TrimEnd('\') + "\" + $f
        W "  --- $f ---"
        if (Test-Path $p) { foreach ($l in (Get-Content $p -Encoding UTF8)) { W "    $l" } }
        else { W "    (不存在 — status.txt 要遊戲跑過一次才會產生)" }
    }
}
W ""

# ---- BepInEx 日誌 ----
# ── 效能指標:HarmonyX 的組件掃描警告 ──
# 每一次未快取的 AccessTools.TypeByName 都會掃全部 interop 組件、撞上壞組件丟例外,
# HarmonyX 再把整段含堆疊的警告同步寫進 console 與磁碟 —— 這是最直接的卡頓來源。
# v3.55 之前這個數字動輒上千;修好之後應該是個位數(只有啟動時的少數幾次)。
W "[效能指標]"
try {
    $lp9 = Join-Path $GamePath "BepInEx\LogOutput.log"
    if (Test-Path -LiteralPath $lp9) {
        $li9 = Get-Content -LiteralPath $lp9 -Encoding UTF8 -ErrorAction Stop
        $warn9 = 0
        foreach ($l9 in $li9) { if ($l9 -like "*AccessTools.GetTypesFromAssembly*") { $warn9++ } }
        $kb9 = [int]((Get-Item -LiteralPath $lp9).Length / 1kb)
        W ("  組件掃描警告 : " + $warn9 + " 次(log 共 " + $li9.Count + " 行 / " + $kb9 + " KB)")
        # ★ 門檻與說明修正(v3.70.1):啟動時解析一批「可有可無」的型別,找不到就會各噴一次
        #   完整堆疊,累積三四百次是【正常的】,而且每個型別只會發生一次(失敗結果有快取)。
        #   舊版寫「超過 200 就叫使用者更新到 v3.55」——v3.70 的使用者看到只會困惑。
        #   真正該擔心的是「數字隨著遊玩時間一直長」,那才是高頻路徑上有未快取的查找。
        if ($warn9 -gt 1500) {
            W "  ⚠ 這個數字過高 = 可能有未快取的型別查找在高頻路徑上。"
            W "     請把這份報告回報給作者(附上 LogOutput.log)。"
        } elseif ($warn9 -gt 0) {
            W "  正常(啟動時的少數幾次不影響效能)"
        } else {
            W "  正常"
        }
    } else { W "  找不到 LogOutput.log" }
} catch { W ("  無法讀取:" + $_.Exception.Message) }
W ""

# ── 功能掛載結果(v3.70.1)────────────────────────────────────────────────
# ★ 為什麼要單獨一段:各功能「掛上了沒」是在【啟動時】印的,而下面只取最後 40 行,
#   永遠截不到。網友回報「面板不能移動/最低價沒出現」時,最該看的就是這幾行,
#   結果報告裡完全沒有 —— 白跑一輪。這裡把整份 log 撈過一遍只挑掛載結論。
W "[功能掛載結果]"
$log = $GamePath.TrimEnd('\') + "\BepInEx\LogOutput.log"
if (Test-Path $log) {
    try {
        $all9 = Get-Content $log -Encoding UTF8
        $pat9 = @('[price]','[market]','[dps]','已掛','掛載','失敗','找不到','停用','[err]')
        $hit9 = @()
        foreach ($l9 in $all9) {
            if ($l9 -notlike '*SpiritZh*') { continue }
            foreach ($p9 in $pat9) { if ($l9.Contains($p9)) { $hit9 += $l9; break } }
        }
        if ($hit9.Count -eq 0) { W "  (沒有任何掛載訊息 — 外掛可能根本沒載入)" }
        else { foreach ($l9 in ($hit9 | Select-Object -First 60)) { W ("  " + $l9) } }
        if ($hit9.Count -gt 60) { W ("  …(另有 " + ($hit9.Count - 60) + " 行,完整內容請附 LogOutput.log)") }
    } catch { W ("  無法讀取:" + $_.Exception.Message) }
} else { W "  (LogOutput.log 不存在)" }
W ""

# ── 掉落音效證據:診斷報告以前只帶最後 40 行 log,掉寶那一刻的紀錄永遠不在裡面,
#    網友回報「音效沒換」就得再跑一趟要 LogOutput.log。把關鍵行直接抽進報告。
W "[掉落音效紀錄(傳說優先)]"
try {
    if (Test-Path $log) {
        # ★ 傳說(金/紫光)優先(v3.76.3):第一份報告的「最後 20 筆」被同一顆白光雜物重複洗版 20 次,
        #   真正要查的金光掉落根本擠不進來 —— 先把傳說那幾筆單獨撈出來,再補其他最近的。
        $all9 = @(Select-String -LiteralPath $log -Pattern "\[audio\] 掉落:|\[dropinfo\]" -Encoding UTF8)
        if ($all9.Count -gt 0) {
            $leg9 = @($all9 | Where-Object { $_.Line -match "稀有=Legendary" } | Select-Object -Last 12)
            $oth9 = @($all9 | Where-Object { $_.Line -notmatch "稀有=Legendary" } | Select-Object -Last 10)
            if ($leg9.Count -gt 0) {
                W ("  ── 傳說(金/紫光)" + $leg9.Count + " 筆 ──")
                foreach ($x9 in $leg9) { W ("  " + $x9.Line) }
            } else {
                W "  ── 這一場【沒有任何傳說(金/紫光)掉落】——要查金光音效,請打到一件金光物品後再跑診斷 ──"
            }
            if ($oth9.Count -gt 0) {
                W ("  ── 其他最近 " + $oth9.Count + " 筆 ──")
                foreach ($x9 in $oth9) { W ("  " + $x9.Line) }
            }
        }
        else { W "  (這一場沒有掉落紀錄 —— 要驗證音效,打幾隻怪讓東西掉出來再跑一次診斷)" }
    }
} catch { W ("  無法讀取:" + $_.Exception.Message) }
W ""
# ── 公會 / 序號判定紀錄 ──
#   ★ 這幾行是【開場就印完】的,玩一陣子後早就被推出下面那「最後 40 行」之外 ——
#     跟掉落音效當初一模一樣的坑。而「功能沒開 / 序號貼了沒反應」是最常見的客訴,
#     判定過程不在報告裡的話,每次都得再跑一趟跟對方要完整的 LogOutput.log。
#   一整場的判定行不多(每次狀態變化才印一行),全帶也不會把報告灌爆,上限 40 行保險。
W "[公會 / 序號判定紀錄]"
try {
    if (Test-Path $log) {
        $g9 = @(Select-String -LiteralPath $log -Pattern "\[guild\]|\[serial\]|\[edition\]" -Encoding UTF8)
        if ($g9.Count -gt 0) {
            $show9 = @($g9 | Select-Object -Last 40)
            # ★★ v3.76.11(深度審查 H17):公會名要【遮蔽】才能寫進報告。
            #   診斷報告是拿來公開貼給作者/在論壇回報的,而 log 裡的
            #   「讀到自己的公會名:「xxx」」是明文 —— 貼出去等於公開白名單,
            #   任何人只要把自己的公會改成同名就能白嫖 NT$3000 的方案。
            #   只留頭尾各一個字,足夠作者比對、又不足以讓別人照抄。
            foreach ($x9 in $show9) {
                $line9 = $x9.Line
                $line9 = [regex]::Replace($line9, '(公會名[::]\s*「)([^」]+)(」)', {
                    param($m)
                    $g = $m.Groups[2].Value
                    $mask = if ($g.Length -le 2) { "**" } else { $g.Substring(0,1) + ("*" * [Math]::Min(6, $g.Length - 2)) + $g.Substring($g.Length - 1) }
                    $m.Groups[1].Value + $mask + $m.Groups[3].Value
                })
                W ("  " + $line9)
            }
            if ($g9.Count -gt 40) { W ("  …(另有 " + ($g9.Count - 40) + " 行較早的判定,完整內容請附 LogOutput.log)") }
            W ""
            W "  ── 怎麼看這一段 ──"
            W "    「公會驗證: 通過」那行結尾會寫【是靠哪一條過的】:"
            W "      公會名命中允許名單            = 你的公會在白名單裡"
            W "      序號                          = 靠序號開的"
            W "      Steam 帳號白名單              = 指定帳號"
            W "      同帳號其他角色已通過公會驗證  = 小號沿用大號的憑證"
            W "    沒有任何 [guild] 行 = BepInEx 有起來但外掛沒判定到,或裝的是純翻譯包(序號在純翻譯包上無效)。"
        }
        else { W "  (這一場沒有任何公會/序號判定紀錄 —— 裝的可能是純翻譯包,或這一場沒真的進到遊戲世界)" }
    }
    else { W "  (LogOutput.log 不存在)" }
} catch { W ("  無法讀取:" + $_.Exception.Message) }
W ""
# ── 傳說(金/紫光)掉落永久紀錄 ──
#   ★ 這個檔【跨場保留、重開遊戲不清】,所以就算金光是好幾場之前掉的,原因也還留著 ——
#     這正是解「金光打到了卻沒響」唯一有意義的證據。最後一欄就是【為什麼沒響】。
W "[傳說(金/紫光)掉落永久紀錄]"
try {
    $gp = Join-Path $GamePath "BepInEx\plugins\SpiritZh_golddrop.txt"
    if (Test-Path -LiteralPath $gp) {
        $gl = @(Get-Content -LiteralPath $gp -Encoding UTF8 | Where-Object { $_.Trim() -ne "" -and -not $_.Trim().StartsWith("#") })
        if ($gl.Count -gt 0) {
            $showg = @($gl | Select-Object -Last 30)
            foreach ($x in $showg) { W ("  " + $x) }
            if ($gl.Count -gt 30) { W ("  …(另有 " + ($gl.Count - 30) + " 筆較早的,完整內容請直接附這個 SpiritZh_golddrop.txt)") }
            W ""
            W "  ── 看最後一欄的原因 ──"
            W "    已播放(有響)              = 正常"
            W "    不是你的掉落→ownonly 擋下  = 王掉落的鎖定跟一般掉落不同;把 audio.txt 的 ownonly 設 0 再打一次就能確認"
            W "    這個稀有度沒有設定音效檔    = audio.txt 的 Legendary= 沒填,或金光的稀有度字串不是 Legendary"
            W "    過濾器沒放行                = filter.txt 的稀有度/分類把它擋掉了"
        } else { W "  (檔案存在但還沒有任何傳說掉落 —— 打到一件金光/紫光物品後就會記錄)" }
    } else {
        W "  (還沒有這個檔 —— 需要 v3.76.7 以上,而且打到過至少一件傳說掉落才會產生)"
    }
} catch { W ("  無法讀取:" + $_.Exception.Message) }
W ""
W "[BepInEx 日誌(最後 40 行)]"
if (Test-Path $log) { foreach ($l in (Get-Content $log -Tail 40 -Encoding UTF8)) { W "  $l" } }
else { W "  (LogOutput.log 不存在 — 表示 BepInEx 從未成功啟動過)" }
W ""
# ── 漏翻清單:外掛翻完後仍有英文殘留的字串(補翻的直接依據)──
# ★ 這一段必須在錯誤日誌【之外】:舊版把它巢狀在 if (Test-Path $err) 裡面,
#   而「沒有錯誤日誌」才是正常狀態 → 一切正常的玩家永遠看不到漏翻清單,
#   等於這個功能平常是關著的。
W "[漏翻殘留(最後 25 條)]"
try {
    $rp9 = Join-Path $GamePath "BepInEx\plugins\SpiritZh_residual.txt"
    if (Test-Path -LiteralPath $rp9) {
        $rl9 = Get-Content -LiteralPath $rp9 -Encoding UTF8 -ErrorAction Stop
        W ("  共 " + $rl9.Count + " 條;以下是最後 25 條:")
        foreach ($x9 in ($rl9 | Select-Object -Last 25)) { W ("    " + $x9) }
    } else { W "  (沒有殘留檔 — 表示沒抓到漏翻,或還沒進遊戲逛過)" }
} catch { W ("  無法讀取:" + $_.Exception.Message) }
W ""

$err = $GamePath.TrimEnd('\') + "\BepInEx\plugins\SpiritZh_error.log"
if (Test-Path $err) {
    # 只顯示「目前安裝版本」的錯誤;舊版錯誤留著會讓人誤以為現在還在出問題
    $curVer = ""
    try {
        $st = $GamePath.TrimEnd('\') + "\BepInEx\plugins\SpiritZh_status.txt"
        if (Test-Path -LiteralPath $st) {
            $l1 = (Get-Content -LiteralPath $st -TotalCount 1 -Encoding UTF8)
            if ($l1 -match "v(\d+\.\d+\.\d+)") { $curVer = "v" + $Matches[1] }
        }
    } catch {}
    $lines = @(Get-Content $err -Encoding UTF8)
    $cur = @(); $old = 0
    if ($curVer -ne "") {
        $keep = $false
        foreach ($l in $lines) {
            if ($l -match "^\[\d{4}-") { $keep = ($l -match [regex]::Escape($curVer)); if (-not $keep) { $old++ } }
            if ($keep) { $cur += $l }
        }
    } else { $cur = $lines }
    W "[翻譯外掛錯誤日誌]"
    if ($cur.Count -eq 0) {
        W "  目前版本 $curVer 沒有任何錯誤紀錄 — 一切正常。"
        if ($old -gt 0) { W "  (檔案裡另有 $old 筆舊版本的紀錄,已自動略過:那些是更新前的問題,與現在無關)" }
    } else {
        W "  以下是目前版本 $curVer 的錯誤(最後 30 行):"
        $tail = $cur | Select-Object -Last 30
        foreach ($l in $tail) { W "  $l" }
    }
    W ""
}

# ---- 安裝紀錄(install.ps1 產生,與本檔同資料夾)----
$il = Join-Path $PSScriptRoot "安裝紀錄.txt"
W "[上次安裝紀錄]"
if (Test-Path -LiteralPath $il) {
    W "  來源:$il"
    foreach ($l in (Get-Content -LiteralPath $il -Encoding UTF8)) { W "  $l" }
} else {
    W "  (找不到安裝紀錄.txt — 表示安裝器從未在這個資料夾執行過,"
    W "   或你是從別的資料夾執行安裝的)"
}
W ""

# ---- 安裝包自身路徑檢查 ----
W "[安裝包位置]"
W "  $PSScriptRoot"
$bad = @()
foreach ($ch in "[]".ToCharArray()) { if ($PSScriptRoot.Contains($ch)) { $bad += $ch } }
if ($bad.Count -gt 0) {
    W "  ！路徑含 $($bad -join ' ') —— PowerShell 會把它當萬用字元,"
    W "    舊版安裝器在這種路徑下會『不報錯但一個檔案都複製不到』。"
    W "    請把安裝包整個搬到簡單路徑(例:C:\SpiritZh)後重跑安裝。"
} else {
    W "  路徑字元正常"
}
W ""

# ---- 輸出:多個候選位置依序嘗試,避免桌面被 OneDrive 重導/無權限時靜默消失 ----
$content = $R -join "`r`n"
$candidates = @()
if ($OutFile -ne "") { $candidates += $OutFile }              # GUI 指定(安裝包資料夾,最可靠)
$candidates += ($PSScriptRoot + "\SpiritZh_診斷報告.txt")      # 安裝包旁邊
try { $candidates += ([Environment]::GetFolderPath("Desktop") + "\SpiritZh_診斷報告.txt") } catch {}
$candidates += ($env:TEMP + "\SpiritZh_診斷報告.txt")          # 最後保底
$saved = ""
foreach ($c in $candidates) {
    if ([string]::IsNullOrWhiteSpace($c)) { continue }
    try {
        $content | Out-File -LiteralPath $c -Encoding utf8 -ErrorAction Stop
        if (Test-Path -LiteralPath $c) { $saved = $c; break }
    } catch {}
}
Write-Host ""
Write-Host "===================================================="
if ($saved -ne "") {
    Write-Host "報告已存到:$saved"
    Write-Host "請把這個檔案(或內容)貼給作者,就能直接看出問題在哪。"
    Write-Host "※報告只含檔案清單與系統版本,不含任何個人資料。"
    try { Start-Process notepad.exe (Q $saved) } catch { try { Start-Process notepad.exe $saved } catch {} }
} else {
    Write-Host "[警告] 找不到可寫入的位置,請直接複製上面的畫面內容貼給作者。"
}
Write-Host "===================================================="
if (-not $Quiet) { Write-Host ""; Write-Host "按 Enter 鍵關閉本視窗..."; try { Read-Host } catch {} }
