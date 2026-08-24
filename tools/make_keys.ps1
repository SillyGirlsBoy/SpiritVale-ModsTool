# ══════════════════════════════════════════════════════════════════════
#  make_keys.ps1 —— 產生更新簽章用的金鑰對(一輩子只跑一次)
#
#  ★ 為什麼需要簽章:自動更新只驗 SHA256 是不夠的 —— 雜湊值跟 ZIP 都放在
#    GitHub 上,帳號一旦被盜,對方【兩個一起改】就通過驗證了,你的使用者
#    會自動下載到惡意檔案。加上簽章之後,偽造更新檔需要【你的私鑰】,
#    而私鑰只在你自己的電腦上。
#
#  產出兩個檔:
#    私鑰 → G:\SpiritZh_簽章金鑰\private.xml   ← 【絕對不能外流、不能進 repo】
#    公鑰 → 本專案 tools\public_key.xml        ← 要進 repo、要嵌進設定工具
#
#  ⚠ 私鑰弄丟 = 以後發不出使用者信得過的更新(只能重發新公鑰、要求大家重裝)。
#    產完請【立刻備份到隨身碟或雲端】,並確認備份處只有你能看到。
# ══════════════════════════════════════════════════════════════════════
$ErrorActionPreference = "Stop"

$KeyDir  = "G:\SpiritZh_簽章金鑰"          # 刻意放在專案【外面】:git add -A 手滑也碰不到
$PrivPath = Join-Path $KeyDir "private.xml"
$PubPath  = Join-Path $PSScriptRoot "public_key.xml"

Write-Host ""
Write-Host "  SpiritZh 更新簽章 —— 金鑰產生器" -ForegroundColor Cyan
Write-Host "  ────────────────────────────────────────" -ForegroundColor DarkGray

if (Test-Path -LiteralPath $PrivPath) {
    Write-Host "  ⚠ 私鑰已經存在:$PrivPath" -ForegroundColor Yellow
    Write-Host "    重新產生會讓【所有已發佈版本的簽章失效】,舊版工具將無法驗證新的更新。" -ForegroundColor Yellow
    $a = Read-Host "    確定要覆蓋嗎?請完整輸入「確認 重新產生金鑰」"
    if ($a -ne "確認 重新產生金鑰") { Write-Host "  已取消,沒有動任何檔案。" -ForegroundColor Green; exit }
}

New-Item -ItemType Directory -Force -Path $KeyDir | Out-Null

# RSA-3072:.NET 內建、Windows PowerShell 5.1 直接可用,強度到 2030 年以後都夠
$rsa = [System.Security.Cryptography.RSA]::Create(3072)
try {
    $priv = $rsa.ToXmlString($true)    # 含私鑰
    $pub  = $rsa.ToXmlString($false)   # 只有公鑰
    Set-Content -LiteralPath $PrivPath -Value $priv -Encoding UTF8 -NoNewline
    Set-Content -LiteralPath $PubPath  -Value $pub  -Encoding UTF8 -NoNewline
}
finally { $rsa.Dispose() }

# 私鑰檔權限收緊:只有目前這個使用者讀得到
try {
    $acl = Get-Acl -LiteralPath $PrivPath
    $acl.SetAccessRuleProtection($true, $false)   # 斷開繼承
    $me = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    $acl.SetAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($me, "FullControl", "Allow")))
    Set-Acl -LiteralPath $PrivPath -AclObject $acl
    Write-Host "  ✔ 私鑰權限已收緊(只有 $me 讀得到)" -ForegroundColor Green
} catch { Write-Host "  (權限收緊失敗,不影響功能:$($_.Exception.Message))" -ForegroundColor DarkYellow }

Write-Host ""
Write-Host "  ✔ 私鑰:$PrivPath" -ForegroundColor Green
Write-Host "  ✔ 公鑰:$PubPath" -ForegroundColor Green
Write-Host ""
Write-Host "  接下來要做的事:" -ForegroundColor Cyan
Write-Host "   1. 【現在就做】把私鑰備份到隨身碟或私人雲端 —— 弄丟就發不出可信的更新了"
Write-Host "   2. 公鑰(public_key.xml)會進 repo、嵌進設定工具 —— 那是公開的,沒關係"
Write-Host "   3. 之後每次發佈跑 tools\sign_release.ps1 產生並簽署 version.json"
Write-Host ""
