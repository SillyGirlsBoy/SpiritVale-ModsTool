@echo off
rem 用 VBScript 轉一手啟動 —— 為什麼不直接 start powershell:
rem   .bat 本身就是由 cmd.exe 執行的,cmd 視窗會先閃出來(網友回報的「黑窗」)。
rem   -WindowStyle Hidden 只能藏 PowerShell 自己的視窗,藏不掉這個 cmd 宿主。
rem   VBScript 的 WScript.Shell.Run 第二參數 0 = 完全不顯示視窗,才真的沒有黑窗。
rem   找不到 wscript(極少數精簡版系統)時退回原本的做法,功能照常。
if exist "%~dp0設定工具.vbs" (
  start "" wscript.exe "%~dp0設定工具.vbs"
) else (
  start "" powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0shell.ps1"
)
