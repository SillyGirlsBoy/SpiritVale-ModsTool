# SpiritVale 繁中翻譯 一鍵移除(ZIP 版)
param([string]$GamePath = "")

$ErrorActionPreference = "SilentlyContinue"
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
    $libs = @()
    $steam = Find-SteamPath
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
if (-not (Test-Game $GamePath)) {
    Write-Host "自動找不到遊戲,請貼上 SpiritVale 資料夾路徑:"
    $GamePath = (Read-Host "路徑").Trim('"').Trim()
}
if (-not (Test-Game $GamePath)) { Write-Host "[錯誤] 路徑無效。"; exit 1 }

# ---- 移除前先備份玩家設定(v3.66 安全掃描補)----
# 以前直接刪整個 BepInEx,玩家調好的音效/光柱/品質/自訂翻譯/地圖音樂全部跟著蒸發,
# 之後重裝還得全部重設一次(實際發生過)。改成:設定檔與玩家自己放的音樂/音效先搬出來。
$pluginDir = Join-Path $GamePath "BepInEx\plugins"
$backup = Join-Path $GamePath "SpiritZh_設定備份"
if (Test-Path -LiteralPath $backup) {
    $backup = $backup + "_" + (Get-Date -Format "MMdd_HHmmss")   # 不蓋掉上一次的備份
}
$saved = 0
if (Test-Path -LiteralPath $pluginDir) {
    try {
        New-Item -ItemType Directory -Path $backup -Force | Out-Null
        # ★ 在備份資料夾裡放一張說明。沒有這個的話,玩家過幾個月看到那個資料夾
        #   完全不知道它是哪一天、哪個版本存的 —— 而安裝說明又教他「複製回 plugins」,
        #   拿一份舊版快照蓋掉現行設定,會默默退回舊行為而且少掉後來新增的鍵。
        try {
            $ver = ""
            try {
                $dp = Join-Path $pluginDir "SpiritZh.dll"
                if (Test-Path -LiteralPath $dp) { $ver = " v" + (Get-Item -LiteralPath $dp).VersionInfo.FileVersion }
            } catch {}
            $note = @(
                "這個資料夾是「移除翻譯」時自動存的設定快照。",
                "",
                ("  存檔時間:" + (Get-Date -Format "yyyy-MM-dd HH:mm:ss") + $ver),
                "",
                "※ 重裝之後【不一定要】把這些檔案複製回去 ——",
                "   新版可能加了新的設定項,拿舊快照蓋回去會少掉那些鍵,",
                "   等於默默退回舊版的行為。",
                "",
                "   建議做法:重裝後先照新版預設用用看,只有真的想找回某個",
                "   自己調過的值,再打開對應的檔案把那一行【單獨】抄回去。",
                "",
                "   例外:自訂翻譯 SpiritZh_custom.txt、不翻譯清單 SpiritZh_keep.txt、",
                "   以及你自己放的音樂/音效/游標圖,整個複製回去都沒問題。"
            )
            Set-Content -LiteralPath (Join-Path $backup "這是什麼_請先讀我.txt") -Value $note -Encoding UTF8
        } catch {}
        # 設定檔(小,用複製):玩家的偏好都在這些檔裡;字典/名稱表是翻譯資料,重裝就有,不備份
        foreach ($cf in @("SpiritZh_view.txt", "SpiritZh_audio.txt", "SpiritZh_filter.txt",
                          "SpiritZh_beam.txt", "SpiritZh_gui.txt", "SpiritZh_keep.txt",
                          "SpiritZh_quality.txt", "SpiritZh_custom.txt", "SpiritZh_music.txt",
                          "SpiritZh_cursor.txt", "SpiritZh_font.txt")) {
            $cp = Join-Path $pluginDir $cf
            if (Test-Path -LiteralPath $cp) { Copy-Item -LiteralPath $cp -Destination $backup -Force; $saved++ }
        }
        # 玩家自己畫的游標圖(v3.72)。★ 只搬【不是我們出貨的】那些 ——
        #   SpiritZh_ui 裡混著 payload 自己的素材(cursor_*/panel/bar_*/logbox/avatar),
        #   那些重裝就有,不用備份;玩家自己丟進去的圖沒備份就會被下面的整包刪永久刪掉。
        try {
            $uiSrc = Join-Path $pluginDir "SpiritZh_ui"
            if (Test-Path -LiteralPath $uiSrc) {
                $ours = @("panel.png", "bar_bg.png", "bar_fill.png", "logbox.png", "avatar.png",
                          "cursor_32.png", "cursor_48.png", "cursor_64.png", "cursor_96.png", "cursor_128.png")
                $mine = @(Get-ChildItem -LiteralPath $uiSrc -File -ErrorAction SilentlyContinue |
                          Where-Object { $ours -notcontains $_.Name })
                if ($mine.Count -gt 0) {
                    $uiDst = Join-Path $backup "SpiritZh_ui"
                    New-Item -ItemType Directory -Path $uiDst -Force | Out-Null
                    foreach ($f in $mine) { Copy-Item -LiteralPath $f.FullName -Destination $uiDst -Force }
                    $saved++
                }
            }
        } catch {}
        # 玩家自己匯入的字型。★ 跟游標圖同一個道理:安裝說明教玩家把 .ttf 匯進來,
        #   也把「移除→重裝」列為官方除錯步驟 —— 沒備份的話那一步會把他匯的字型全刪掉。
        #   只搬【不是我們出貨的】,jf-openhuninn 與授權說明重裝就有。
        try {
            $ftSrc = Join-Path $pluginDir "SpiritZh_fonts"
            if (Test-Path -LiteralPath $ftSrc) {
                $ftOurs = @("jf-openhuninn-2.1.ttf", "字型授權說明.txt")
                $ftMine = @(Get-ChildItem -LiteralPath $ftSrc -File -ErrorAction SilentlyContinue |
                            Where-Object { $ftOurs -notcontains $_.Name })
                if ($ftMine.Count -gt 0) {
                    $ftDst = Join-Path $backup "SpiritZh_fonts"
                    New-Item -ItemType Directory -Path $ftDst -Force | Out-Null
                    foreach ($f in $ftMine) { Copy-Item -LiteralPath $f.FullName -Destination $ftDst -Force }
                    $saved++
                }
            }
        } catch {}
        # 玩家自己放的音樂/音效檔(可能很大,用搬移——同磁碟搬移是瞬間完成的)
        foreach ($fd in @("SpiritZh_sounds", "SpiritZh_music")) {
            $fp = Join-Path $pluginDir $fd
            if (Test-Path -LiteralPath $fp) { Move-Item -LiteralPath $fp -Destination (Join-Path $backup $fd) -Force; $saved++ }
        }
    } catch {}
}
if ($saved -gt 0) {
    Write-Host "[備份] 你的設定與音樂已備份到:$backup"
    Write-Host "       之後重新安裝的話,把裡面的檔案複製回 BepInEx\plugins\ 即可全部找回。"
} else {
    try { Remove-Item -LiteralPath $backup -Force -ErrorAction SilentlyContinue } catch {}
}

foreach ($f in @("winhttp.dll", "doorstop_config.ini", ".doorstop_version")) {
    Remove-Item -LiteralPath (Join-Path $GamePath $f) -Force
}
foreach ($d in @("BepInEx", "dotnet")) {
    Remove-Item -LiteralPath (Join-Path $GamePath $d) -Recurse -Force
}
Write-Host "[OK] 已移除翻譯外掛,遊戲恢復原版(遊戲本體檔案未受任何影響)。"
