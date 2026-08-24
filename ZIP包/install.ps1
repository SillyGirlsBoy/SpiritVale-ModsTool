# SpiritVale 繁中翻譯 一鍵安裝(ZIP 版)
param([string]$GamePath = "", [string]$Mode = "", [string]$Font = "")

$ErrorActionPreference = "Stop"
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$Payload = Join-Path $Here "payload"

# 安裝過程全程記錄到安裝包旁邊的「安裝紀錄.txt」——放安裝包這邊而不是遊戲資料夾,
# 是因為出問題時遊戲資料夾可能整個是空的(沒複製進去/被防毒清掉),紀錄就跟著不見了。
$LogLines = New-Object System.Collections.ArrayList
$LogFile = Join-Path $Here "安裝紀錄.txt"
function Log([string]$s) {
    [void]$LogLines.Add($s)
    Write-Host $s
    try { $LogLines -join [Environment]::NewLine | Out-File -LiteralPath $LogFile -Encoding utf8 } catch {}
}
# 任何未攔截的錯誤都先寫進紀錄再結束,否則黑窗一關就查不到死因
trap {
    Log ""
    Log ("[致命錯誤] " + $_.Exception.Message)
    Log ("  發生位置:" + $_.InvocationInfo.PositionMessage)
    Log ""
    Log "安裝未完成。請把本資料夾內的「安裝紀錄.txt」貼給作者。"
    break
}
Log ("SpiritVale 繁中翻譯 安裝紀錄  " + (Get-Date -Format "yyyy-MM-dd HH:mm:ss"))
Log ("安裝包位置:" + $Here)
Log ""

Log "===================================================="
Log "  SpiritVale 繁體中文翻譯  一鍵安裝"
Log "===================================================="
Log "即時翻譯層:進遊戲後英文自動換成繁中(含伺服器文字)。"
Log "不修改任何遊戲檔案;線上遊戲使用外掛有其風險,請自行斟酌。"
Log ""

if (-not (Test-Path -LiteralPath (Join-Path $Payload "BepInEx"))) {
    Log "[錯誤] 找不到 payload 資料夾,請確認 ZIP 已完整解壓縮後再執行。"
    exit 1
}

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

# ---- 找遊戲資料夾 ----
# 注意:不能用 Join-Path 探測候選路徑——PS 5.1 的 Join-Path 會驗證磁碟機,掃到不存在的槽(D:/E:...)會直接丟例外
function Test-Game([string]$p) {
    if ([string]::IsNullOrWhiteSpace($p)) { return $false }
    try { return (Test-Path ($p.TrimEnd('\') + "\SpiritVale.exe")) } catch { return $false }
}
# Steam 安裝路徑(登錄檔)
function Find-SteamPath {
    foreach ($k in @("HKCU:\Software\Valve\Steam", "HKLM:\SOFTWARE\WOW6432Node\Valve\Steam", "HKLM:\SOFTWARE\Valve\Steam")) {
        foreach ($n in @("SteamPath", "InstallPath")) {
            try { $v = (Get-ItemProperty -Path $k -ErrorAction Stop).$n; if ($v) { return ($v -replace "/", "\") } } catch {}
        }
    }
    return $null
}
# 所有 Steam 遊戲庫路徑(讀 libraryfolders.vdf,任何磁碟/資料夾名都抓得到)
function Get-SteamLibraries {
    $libs = @()
    $steam = Find-SteamPath
    if ($steam) { $libs += $steam }
    foreach ($rel in @("steamapps\libraryfolders.vdf", "config\libraryfolders.vdf")) {
        if (-not $steam) { break }
        $vdf = $steam.TrimEnd('\') + "\" + $rel
        try {
            if (Test-Path $vdf) {
                $txt = Get-Content $vdf -Raw -ErrorAction Stop
                foreach ($m in [regex]::Matches($txt, '"path"\s*"([^"]+)"')) {
                    $libs += ($m.Groups[1].Value -replace "\\\\", "\")
                }
            }
        } catch {}
    }
    return ($libs | Select-Object -Unique)
}

if (-not (Test-Game $GamePath)) {
    $cands = @()
    foreach ($lib in (Get-SteamLibraries)) { $cands += ($lib.TrimEnd('\') + "\steamapps\common\SpiritVale") }
    foreach ($d in @("C", "D", "E", "F", "G", "H")) {   # 後備:常見固定路徑
        $cands += "$($d):\SteamLibrary\steamapps\common\SpiritVale"
        $cands += "$($d):\Program Files (x86)\Steam\steamapps\common\SpiritVale"
        $cands += "$($d):\Steam\steamapps\common\SpiritVale"
        $cands += "$($d):\Games\Steam\steamapps\common\SpiritVale"
    }
    foreach ($c in $cands) { if (Test-Game $c) { $GamePath = $c; break } }
}
if (-not (Test-Game $GamePath)) {
    Log "自動找不到遊戲,請貼上 SpiritVale 資料夾路徑"
    Log "(Steam 右鍵遊戲 > 管理 > 瀏覽本機檔案,複製網址列路徑):"
    $GamePath = (Read-Host "路徑").Trim('"').Trim()
}
if (-not (Test-Game $GamePath)) {
    Log "[錯誤] 路徑無效,找不到 SpiritVale.exe。"
    exit 1
}
Log "找到遊戲:$GamePath"
Log ""

# ---- 智慧型應用程式控制檢查(必須在安裝前提醒:裝了也不會動) ----
$sac = Get-SacState
Log "[智慧型應用程式控制] 狀態代碼:$sac (0=關閉 1=開啟 2=評估中 -1=無此功能)"
if ($sac -eq 1 -or $sac -eq 2) {
    Log ""
    Log "===================================================="
    Log "  ！重要:偵測到「智慧型應用程式控制」是開啟的"
    Log "===================================================="
    Log "這是 Windows 11 的一項安全功能,它會封鎖『沒有數位簽章』的程式碼。"
    Log "本翻譯外掛(以及所有同類的遊戲模組)每次啟動都會產生沒有簽章的組件,"
    Log "因此【會被它擋下來】,遊戲啟動時會出現:"
    Log "    「應用程式控制原則已封鎖此檔案 (0x800711C7)」"
    Log ""
    Log "重點:它和防毒軟體是兩套獨立的系統 —— 加防毒排除【不會】讓它放行。"
    Log ""
    Log "唯一的解法是關閉它:"
    Log "  Windows 安全性 → 應用程式與瀏覽器控制 → 智慧型應用程式控制設定 → 關閉"
    Log ""
    Log "但請務必先知道這件事再決定:"
    Log "  ※ 智慧型應用程式控制一旦關閉,【就無法再開啟】,"
    Log "    要重新啟用必須重新安裝 Windows。這是微軟的設計,不是本程式造成的。"
    Log "  ※ 關閉後你的電腦就少了這一層對未簽章程式的防護。"
    Log ""
    Log "這是你自己的取捨,我不會替你決定,本安裝器也不會去動這個設定。"
    Log "若你不想關閉它,那就無法使用本翻譯外掛 —— 這完全合理,請直接關閉本視窗。"
    Log ""
    $ans = (Read-Host "了解上述說明,仍要繼續安裝嗎?(輸入 Y 繼續,其他鍵離開)").Trim()
    if ($ans -ne "Y" -and $ans -ne "y") {
        Log "已取消安裝,未變更任何檔案。"
        exit 0
    }
    Log ""
}

# ---- 顯示模式 ----
if ($Mode -ne "1" -and $Mode -ne "2" -and $Mode -ne "3" -and $Mode -ne "4") {
    Log "請選擇顯示模式:"
    Log ""
    Log "  [1] 全部雙語      所有遊戲名詞都顯示「中文 English」——"
    Log "                    物品、技能、職業、屬性、狀態、NPC、地圖、怪物"
    Log "                    (例:水龍卡片 Aqua Drake Card / 風車斬 Whirlwind)"
    Log "                    適合想對照英文攻略、跟外國玩家溝通的人。"
    Log ""
    Log "  [2] 物品名雙語    只有物品名顯示「中文 English」,技能等其他名詞純中文"
    Log "                    (例:水龍卡片 Aqua Drake Card / 風車斬)"
    Log ""
    Log "  [3] 物品名純中文  物品名也只顯示中文,畫面最乾淨"
    Log "                    (例:水龍卡片 / 風車斬)"
    Log ""
    Log "  [4] 原文          完全不翻譯——給只想用掉寶音效/隱藏玩家等功能的人"
    Log ""
    Log "  ※模式 1/2 的地圖名與怪物名會雙語(隊伍搜尋要打英文,方便對照);"
    Log "    模式 3 徹底全中文。技能敘述等『句子』任何模式都純中文;"
    Log "    市場都能打中文搜尋。裝完可隨時用設定工具換模式。"
    Log ""
    $Mode = (Read-Host "請選擇 1-4(直接 Enter 預設 2)").Trim()
}
$ModeText = "bilingual"; $ModeLabel = "物品名雙語(中文 English)"
if ($Mode -eq "1") { $ModeText = "full";    $ModeLabel = "全部雙語(中文 English)" }
if ($Mode -eq "3") { $ModeText = "chinese"; $ModeLabel = "物品名純中文" }
if ($Mode -eq "4") { $ModeText = "off";     $ModeLabel = "原文(不翻譯,只用音效/隱藏功能)" }

# ---- 中文字型(實驗性,選錯不影響翻譯) ----
if ($Font -ne "") {
    # 由設定工具帶入:0/default=預設,其他=字型名稱
    $FontPick = "x"   # 略過互動選單
    if ($Font -eq "0" -or $Font -eq "default") { $FontName = "" } else { $FontName = $Font }
} else {
Log ""
Log "要更換遊戲的中文字型嗎?(實驗性功能;隨時可重跑本安裝更換)"
Log "  [0] 遊戲預設字型(不更換)"
Log "  [1] 微軟正黑體 (Microsoft JhengHei)"
Log "  [2] 標楷體     (DFKai-SB)"
Log "  [3] 新細明體   (PMingLiU)"
Log "  [4] 思源黑體   (Noto Sans TC)——需已自行安裝此字型"
Log "  或直接輸入任何已安裝在 Windows 的字型名稱"
$FontPick = (Read-Host "請選擇(直接 Enter 預設 0)").Trim()
$FontName = ""
if ($FontPick -eq "1") { $FontName = "Microsoft JhengHei" }
elseif ($FontPick -eq "2") { $FontName = "DFKai-SB" }
elseif ($FontPick -eq "3") { $FontName = "PMingLiU" }
elseif ($FontPick -eq "4") { $FontName = "Noto Sans TC" }
elseif ($FontPick -ne "" -and $FontPick -ne "0") { $FontName = $FontPick }
}

# ---- 防毒排除(必須在「複製之前」:否則檔案在複製當下就可能被 Defender 吃掉) ----
Log ""
Log "----------------------------------------------------"
Log "為避免防毒軟體(Windows Defender)在『遊戲更新後』誤刪外掛需要重新產生的組件"
Log "(那會造成啟動時出現紅字、翻譯失效),建議把遊戲資料夾加入防毒的排除清單。"
Log ""
Log "接下來『可能』會跳出一次『系統管理員授權(UAC)』視窗——"
Log "用途『僅為』把遊戲資料夾加入防毒排除,不會做任何其他事,也不會連網。"
Log "若你不想授權,在該視窗按『否』即可,安裝仍會完成(但日後遊戲更新可能要手動處理)。"
Log "※ 沒跳出來也是正常的:排除清單已經有了、你用第三方防毒、或系統 UAC 設為不通知,"
Log "   都不會顯示這個視窗。看到最後的『安裝完成』就是成功了。"
Log "----------------------------------------------------"
$excluded = $false
try {
    $cur = @()
    $mpOk = $true
    try { $cur = (Get-MpPreference -ErrorAction Stop).ExclusionPath } catch { $mpOk = $false }
    if (-not $mpOk) {
        # 讀不到 Defender 設定 = 這台機器用第三方防毒(或 Defender 被停用)。
        # 明講原因,否則使用者會以為「說明寫會跳 UAC,怎麼沒跳」= 安裝失敗(v3.65 網友回報)。
        Log "[防毒] 這台電腦讀不到 Windows Defender 設定(可能使用第三方防毒),"
        Log "       略過排除清單設定 —— 不會跳出 UAC 視窗,這是正常的。"
        Log "       若日後遊戲更新後出現紅字,請手動把遊戲資料夾加入你的防毒排除清單。"
    }
    elseif ($cur -and ($cur -contains $GamePath)) {
        Log "[防毒] 排除清單已包含遊戲資料夾,略過(不會跳 UAC,這是正常的)。"
        $excluded = $true
    } else {
        # 只用提權的子行程做這一件事:加入排除清單
        $cmd = "Add-MpPreference -ExclusionPath '" + ($GamePath -replace "'", "''") + "'"
        Start-Process powershell -Verb RunAs -WindowStyle Hidden -Wait -ErrorAction Stop `
            -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", $cmd)
        Start-Sleep -Milliseconds 400
        $cur2 = @(); try { $cur2 = (Get-MpPreference -ErrorAction Stop).ExclusionPath } catch {}
        if ($cur2 -and ($cur2 -contains $GamePath)) { Log "[防毒] 已加入排除清單。"; $excluded = $true }
        else { Log "[防毒] 未加入(可能取消了授權,或此機非使用 Defender)。" }
    }
} catch {
    Log "[防毒] 未加入(取消授權或無 Defender)——日後若遇紅字,請手動加排除,詳見安裝說明.txt。"
}

# ---- 先備份玩家自己的設定 ----
# payload 裡放的是「預設值」設定檔,底下的 Copy-Item -Force 會把它蓋回去。
# 沒有這段的話:玩家按「套用設定」設好音效/隱藏/光柱 → 按「安裝 / 更新翻譯」
# → 設定悄悄變回預設,而且從畫面上完全看不出來發生過什麼事。
# (字典/名稱/術語那些是翻譯資料,必須跟著更新,所以不在保留名單內。)
$KeepCfg = @("SpiritZh_view.txt", "SpiritZh_audio.txt", "SpiritZh_filter.txt",
             "SpiritZh_beam.txt", "SpiritZh_gui.txt", "SpiritZh_keep.txt",
             # v3.66 安全掃描補:這三個也是玩家自己的設定,漏掉的話「更新翻譯」
             # 會用範本把玩家調好的品質門檻/撿起音效/自訂翻譯規則/地圖音樂全蓋掉。
             "SpiritZh_quality.txt", "SpiritZh_custom.txt", "SpiritZh_music.txt",
             # v3.72 補:游標設定漏了的話,玩家設好 128px 游標、下次按「更新翻譯」
             # 就會被 payload 的範本(enabled=0)蓋回去 —— 而且畫面上完全看不出來,
             # 正是上面那段註解在警告的同一種災情。
             "SpiritZh_cursor.txt", "SpiritZh_font.txt")
$SavedCfg = @{}
foreach ($cf in $KeepCfg) {
    $cp = Join-Path $GamePath ("BepInEx\plugins\" + $cf)
    try { if (Test-Path -LiteralPath $cp) { $SavedCfg[$cf] = [System.IO.File]::ReadAllBytes($cp) } } catch {}
}
if ($SavedCfg.Count -gt 0) { Log "  已保留你原本的設定檔 $($SavedCfg.Count) 個(音效/畫面/過濾/光柱)。" }

# 保留玩家設定有個副作用:新版新增的設定鍵會被舊檔整個蓋掉,玩家永遠不會知道有新功能,
# 連手動改都沒得改(v3.61 的效能模式就是這樣——舊玩家更新後 view.txt 裡根本沒那幾行)。
# 解法:還原玩家的檔案之後,把 payload 裡有、玩家檔裡沒有的鍵補到檔尾。只加不改,
# 玩家原本設好的值一律不動。
function Merge-NewKeys([string]$restoredPath, [string]$defaultPath) {
    try {
        if (-not (Test-Path -LiteralPath $restoredPath) -or -not (Test-Path -LiteralPath $defaultPath)) { return 0 }
        $have = @{}
        foreach ($l in (Get-Content -LiteralPath $restoredPath -Encoding UTF8)) {
            $s = $l.Trim()
            if ($s.Length -eq 0 -or $s.StartsWith("//")) { continue }
            $i = $s.IndexOf("=")
            if ($i -gt 0) { $have[$s.Substring(0, $i).Trim().ToLower()] = $true }
        }
        $add = @()
        foreach ($l in (Get-Content -LiteralPath $defaultPath -Encoding UTF8)) {
            $s = $l.Trim()
            if ($s.Length -eq 0 -or $s.StartsWith("//")) { continue }
            $i = $s.IndexOf("=")
            if ($i -le 0) { continue }
            if (-not $have.ContainsKey($s.Substring(0, $i).Trim().ToLower())) { $add += $l }
        }
        if ($add.Count -eq 0) { return 0 }
        Add-Content -LiteralPath $restoredPath -Encoding UTF8 `
            -Value ("`r`n// ── 本次更新新增的選項(你原本的設定都沒有變動)──`r`n" + ($add -join "`r`n"))
        return $add.Count
    } catch { return 0 }
}

# ---- 複製(在排除之後才複製,檔案不會在複製當下被吃掉) ----
Log ""
Log "安裝中..."
# 先解除「從網路下載」的封鎖標記,否則 Windows 會拒絕載入這些 DLL → Failed to start BepInEx
try { Get-ChildItem -LiteralPath $Payload -Recurse -File -ErrorAction SilentlyContinue | Unblock-File -ErrorAction SilentlyContinue } catch {}
# 逐項 -LiteralPath 複製:絕不能用 "payload\*" 這種萬用字元路徑——
# 解壓縮資料夾名稱只要含 [ 或 ](瀏覽器重複下載常見),PowerShell 會把它當字元類別,
# 結果一個檔案都複製不到。實際災情:防毒排除加成功、檔案卻全部沒進去。
$copied = 0
foreach ($item in (Get-ChildItem -LiteralPath $Payload -Force)) {
    try {
        Copy-Item -LiteralPath $item.FullName -Destination $GamePath -Recurse -Force -ErrorAction Stop
        $copied++
    } catch {
        Log "[錯誤] 複製失敗:$($item.Name) — $($_.Exception.Message)"
    }
}
Log "  已複製 $copied 個項目到遊戲資料夾。"
# 安裝包位置寫進遊戲端(v3.68):遊戲內按熱鍵(預設 F6)叫出設定工具要靠它找到本資料夾。
# 放在複製【之後】—— 首次安裝時 BepInEx\plugins 是複製才生出來的。每次安裝都重寫,搬家後重裝即更新。
try { Set-Content -LiteralPath (Join-Path $GamePath "BepInEx\plugins\SpiritZh_toolpath.txt") -Value $Here -Encoding UTF8 } catch {}
if ($copied -eq 0) {
    Log ""
    Log "[錯誤] 一個檔案都沒複製成功!安裝未完成。"
    Log "       最常見原因:安裝包所在的資料夾名稱含有特殊字元。"
    Log "       請把整個安裝包資料夾搬到簡單的路徑再試一次,例如 C:\SpiritZh"
    Log "       (資料夾名稱請只用英文字母與數字,不要有 [ ] 或其他符號)"
    Log ""
    Log "本次紀錄已存到:$LogFile"
    exit 1
}
# 複製後再解一次(保險:ADS 封鎖旗標會跟著檔案被複製過去)
try { Get-ChildItem -Path $GamePath -Recurse -File -Include *.dll,*.exe,*.ini,*.json,*.config -ErrorAction SilentlyContinue | Unblock-File -ErrorAction SilentlyContinue } catch {}
$pluginDir = Join-Path $GamePath "BepInEx\plugins"
if (Test-Path -LiteralPath $pluginDir) {
    Set-Content -LiteralPath (Join-Path $pluginDir "SpiritZh_mode.txt") -Value $ModeText -Encoding utf8 -NoNewline
    if ($FontName -ne "") {
        $fc = "// SpiritZh 自訂字型設定(由安裝器產生)`r`n// 想換字型:重跑「一鍵安裝.bat」再選一次,或直接改下面這行`r`n" + $FontName
        Set-Content -LiteralPath (Join-Path $pluginDir "SpiritZh_font.txt") -Value $fc -Encoding UTF8
        Log "  中文字型:$FontName(重開遊戲生效;若系統沒有此字型會自動退回預設)"
    } else {
        Log "  中文字型:遊戲預設"
    }
    # 把玩家原本的設定放回去(payload 的預設值只用於「第一次安裝」)
    $restored = 0
    foreach ($cf in $KeepCfg) {
        if (-not $SavedCfg.ContainsKey($cf)) { continue }
        try { [System.IO.File]::WriteAllBytes((Join-Path $pluginDir $cf), $SavedCfg[$cf]); $restored++ } catch {}
    }
    if ($restored -gt 0) { Log "  已還原你原本的設定檔 $restored 個。" }
    $merged = 0
    foreach ($cf in $KeepCfg) {
        if (-not $SavedCfg.ContainsKey($cf)) { continue }
        $merged += (Merge-NewKeys (Join-Path $pluginDir $cf) (Join-Path $Payload ("BepInEx\plugins\" + $cf)))
    }
    if ($merged -gt 0) { Log "  本次更新新增了 $merged 個設定選項,已補進你的設定檔(你原本的設定沒有變動)。" }
} else {
    # 這裡若不擋,Set-Content 會直接丟例外中斷腳本,下面的完整性檢查就永遠跑不到,
    # 使用者只會看到一句看不懂的紅字,不知道真正的問題是「檔案根本沒複製進去」。
    Log "[錯誤] 找不到 $pluginDir —— 檔案並未成功複製到遊戲資料夾。"
}

# ---- 安裝完整性檢查(檔案若被防毒吃掉,這裡就會抓到,不用等進遊戲才發現) ----
function Test-Missing {
    $m = @()
    foreach ($f in @("winhttp.dll", "doorstop_config.ini", "dotnet\coreclr.dll",
                     "BepInEx\core\BepInEx.Unity.IL2CPP.dll", "BepInEx\plugins\SpiritZh.dll",
                     "BepInEx\plugins\SpiritZh_dict.txt", "BepInEx\plugins\SpiritZh_terms.txt")) {
        if (-not (Test-Path ($GamePath.TrimEnd('\') + "\" + $f))) { $m += $f }
    }
    return $m
}
$missing = Test-Missing
# 有缺檔又不是被防毒吃掉時,最常見是遊戲裝在受保護位置(Program Files)需要系統管理員權限才能寫入。
# 用一次提權子行程重跑複製(含 mode/font 設定檔),避免網友卡在「安裝似乎未完成」。
if ($missing.Count -gt 0) {
    Log ""
    Log "[提示] 偵測到部分檔案未成功複製(常見於遊戲裝在 Program Files),"
    Log "       嘗試以系統管理員權限重新複製一次——若跳出 UAC 請按「是」。"
    $q1 = $Payload -replace "'", "''"
    $q2 = $GamePath -replace "'", "''"
    $mf2 = $ModeText -replace "'", "''"
    $inner = "Get-ChildItem -LiteralPath '$q1' -Force | ForEach-Object { Copy-Item -LiteralPath `$_.FullName -Destination '$q2' -Recurse -Force }; " +
             "Set-Content -LiteralPath '$q2\BepInEx\plugins\SpiritZh_mode.txt' -Value '$mf2' -Encoding utf8 -NoNewline"
    if ($FontName -ne "") {
        $ff2 = $FontName -replace "'", "''"
        $inner += "; Set-Content -LiteralPath '$q2\BepInEx\plugins\SpiritZh_font.txt' -Value ('// SpiritZh font' + [char]10 + '$ff2') -Encoding utf8"
    }
    try {
        Start-Process powershell -Verb RunAs -WindowStyle Hidden -Wait -ErrorAction Stop `
            -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", $inner)
        Start-Sleep -Milliseconds 400
        # 提權複製同樣會蓋掉設定檔,這裡再還原一次
        foreach ($cf in $KeepCfg) {
            if (-not $SavedCfg.ContainsKey($cf)) { continue }
            try { [System.IO.File]::WriteAllBytes((Join-Path $GamePath ("BepInEx\plugins\" + $cf)), $SavedCfg[$cf]) } catch {}
            [void](Merge-NewKeys (Join-Path $GamePath ("BepInEx\plugins\" + $cf)) (Join-Path $Payload ("BepInEx\plugins\" + $cf)))
        }
        $missing = Test-Missing
        if ($missing.Count -eq 0) { Log "  已用系統管理員權限補齊,安裝完成。" }
    } catch {
        Log "  (未取得系統管理員權限,略過提權複製)"
    }
}
if ($missing.Count -gt 0) {
    Log ""
    Log "[警告] 安裝後發現下列檔案不見了(極可能被防毒刪除):"
    foreach ($m in $missing) { Log "        - $m" }
    Log "        可能原因(依機率):"
    Log "        1. 被防毒刪除 → 加防毒排除後重跑本安裝"
    Log "           (Windows 安全性 → 病毒與威脅防護 → 管理設定 → 排除項目)"
    Log "        2. 安裝包資料夾名稱有特殊字元 → 搬到 C:\SpiritZh 之類的簡單路徑重試"
    Log "        本次紀錄已存到:$LogFile —— 求助時請附上這個檔案。"
} else {
    Log "  檔案完整性檢查:通過。"
}

Log ""
Log "[OK] 安裝完成!顯示模式:$ModeLabel"
Log ""
Log "  ‧用 Steam 正常啟動遊戲即可。"
Log "  ‧啟動時會出現黑色載入視窗顯示進度(首次 1~3 分鐘,之後數秒),"
Log "    載入完成會自動消失 —— 請耐心等它跑完,不要關閉它。"
Log "  ‧首次啟動若伺服器列表是空的(連線逾時),重開一次遊戲即可。"
Log "  ‧想改顯示模式或字型:雙擊「設定工具.bat」——圖形介面直接選,不用重裝;"
Log "    字型可從你電腦全部已安裝字型挑選、附即時預覽,遊戲開著也能換。"
Log "  ‧回報問題請附:本資料夾的「安裝紀錄.txt」,或跑「一鍵診斷.bat」產生的桌面報告。"
