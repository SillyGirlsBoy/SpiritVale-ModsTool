# ═══════════════════════════════════════════════════════════════════════════
#  SpiritVale 繁體中文化 — 設定工具(WPF 新殼 v2,v3.71)     開發:源
#  ─ 依源的第二版 mockup:圖示分頁列 + 功能自選卡片流 + 右側自訂參數 + 底部安裝列。
#  ─ 分頁遷移進度:八個分頁全部原生化(功能自選 / 翻譯與字型 / 掉落音效 / 掉落光柱 /
#    詞條品質 / 傷害統計與熱鍵 / 自訂 / 關於)。舊工具 settings.ps1 只留給
#    「分享設定檔、匯入、移除翻譯」這些不常用的功能(右上角「進階設定」)。
#  ─ 設定檔格式與舊工具完全相同(key=value,熱重載 5 秒生效),兩邊可交替使用。
# ═══════════════════════════════════════════════════════════════════════════
$ErrorActionPreference = "SilentlyContinue"
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms, System.Drawing

$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
# ★★ 我是不是【更新用的暫存副本】?(2026-08-27 鬼打牆事件的最後一塊)
#   自動更新會把整包解到 %TEMP%\SpiritZh_update_xxx\,那裡面有一份可以雙擊的設定工具。
#   從那裡開的話,它永遠停在「當時那一版」→ 每次開都比對到有新版 → 無限跳更新。
#   實測源的機器上 %TEMP% 累積了 13 個舊暫存包,每一個都是潛在的鬼打牆來源。
$script:IsTempCopy = $false
try {
    $tmpRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
    if ([IO.Path]::GetFullPath($Here).TrimEnd('\').StartsWith($tmpRoot, [StringComparison]::OrdinalIgnoreCase)) {
        $script:IsTempCopy = $true
    }
} catch { }

function Get-DllVer([string]$path) {
    try {
        if (-not (Test-Path -LiteralPath $path)) { return $null }
        $v = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($path).ProductVersion
        if ([string]::IsNullOrWhiteSpace($v)) { return $null }
        $v = $v.Trim()
        if ($v -eq "1.0.0.0" -or $v -eq "1.0.0") { return $null }
        return "v" + $v
    } catch { return $null }
}
$ToolVer = Get-DllVer (Join-Path $Here "payload\BepInEx\plugins\SpiritZh.dll")
if (-not $ToolVer) { $ToolVer = "v3.76.12" }
# ── 版本辨識(公會專用版 / 純翻譯包):讀 DLL 的 Comments = csproj <Description>(edition=guild / edition=pure)。
#    跟 Get-DllVer 讀同一個 FileVersionInfo 物件,零成本;「決定功能開不開的 DLL」與「決定 UI 長怎樣的旗標」
#    是同一個檔,打包時不可能湊錯(旗標檔 edition.txt 會有漏放/放錯/被手改的問題,不採用)。
#    讀不到(payload 不完整)就當純翻譯包 —— 寧可少顯示。
function Get-DllEdition([string]$path) {
    try {
        if (-not (Test-Path -LiteralPath $path)) { return $null }
        $c = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($path).Comments
        if ($c -and $c -match 'edition=([A-Za-z]+)') { return $Matches[1].ToLowerInvariant() }
        return $null
    } catch { return $null }
}
$ToolEdition = Get-DllEdition (Join-Path $Here "payload\BepInEx\plugins\SpiritZh.dll")
$script:IsPure = ($ToolEdition -ne "guild")
function Edition-Name([string]$ed) { if ($ed -eq "guild") { "公會專用版" } else { "純翻譯包" } }

function Test-Game([string]$p) { $p -and (Test-Path -LiteralPath (Join-Path $p "SpiritVale.exe")) }
function Find-Game {
    $libs = @()
    foreach ($rk in @("HKCU:\Software\Valve\Steam", "HKLM:\SOFTWARE\WOW6432Node\Valve\Steam")) {
        try {
            $sp = (Get-ItemProperty -Path $rk -ErrorAction Stop).SteamPath
            if (-not $sp) { $sp = (Get-ItemProperty -Path $rk -ErrorAction Stop).InstallPath }
            if ($sp) {
                $sp = $sp -replace "/", "\"
                $libs += $sp
                $vdf = Join-Path $sp "steamapps\libraryfolders.vdf"
                if (Test-Path $vdf) {
                    $txt = Get-Content $vdf -Raw
                    foreach ($m in [regex]::Matches($txt, '"path"\s*"([^"]+)"')) { $libs += ($m.Groups[1].Value -replace "\\\\", "\") }
                }
            }
        } catch {}
    }
    $cands = @()
    foreach ($lib in ($libs | Select-Object -Unique)) { $cands += ($lib.TrimEnd('\') + "\steamapps\common\SpiritVale") }
    foreach ($d in @("C", "D", "E", "F", "G", "H")) {
        $cands += "$($d):\SteamLibrary\steamapps\common\SpiritVale"
        $cands += "$($d):\Program Files (x86)\Steam\steamapps\common\SpiritVale"
        $cands += "$($d):\Steam\steamapps\common\SpiritVale"
    }
    foreach ($c in $cands) { if (Test-Game $c) { return $c } }
    return ""
}
$script:GamePath = Find-Game
function PluginDir { if ($script:GamePath) { Join-Path $script:GamePath "BepInEx\plugins" } else { "" } }

function Read-KV([string]$file) {
    $h = @{}
    if (-not (Test-Path -LiteralPath $file)) { return $h }
    # 檔案存在但讀不到(被防毒/其他程式鎖住)→ 回 $null,呼叫端要「什麼都不動」。
    # 以前這裡讀失敗會靜默回空表,Load-* 就把整頁 UI 設成預設,再按一次套用等於把預設值寫回檔案 —— 這是會弄丟設定的路徑。
    $raw = $null
    try { $raw = @(Get-Content -LiteralPath $file -Encoding UTF8 -ErrorAction Stop) } catch { return $null }
    if ($raw.Count -eq 0 -and (Get-Item -LiteralPath $file).Length -gt 3) { return $null }   # 0 行但不是空檔(>3 bytes:純 BOM 檔算空檔)
    foreach ($l in $raw) {
        $s = $l.Trim().TrimStart([char]0xFEFF)
        if ($s.Length -eq 0 -or $s.StartsWith("//") -or $s.StartsWith("#")) { continue }
        $i = $s.IndexOf('=')
        if ($i -le 0) { continue }
        $k = $s.Substring(0, $i).Trim().ToLowerInvariant()
        $v = $s.Substring($i + 1)
        $c = $v.IndexOf("//"); if ($c -ge 0) { $v = $v.Substring(0, $c) }
        $h[$k] = $v.Trim()
    }
    return $h
}
# 寫檔錯誤集中記在這裡:$ErrorActionPreference=SilentlyContinue 會把 Set-Content 的失敗(唯讀/防毒鎖檔/被遊戲佔住)
# 整個吞掉,以前狀態列照樣寫「已套用」—— 使用者以為存了其實沒存。套用流程結束時看這個變數決定要不要跳警告。
$script:saveErr = @()
# 哪些設定檔【成功讀進 UI 過】。沒讀成功就代表畫面上是空的/預設的,這時候寫檔會把使用者的設定
# 覆蓋成空白 —— 所以 Save-* 一律先看這個表。(audio 與 filter 是同一頁但兩個檔,要分開記。)
$script:cfgLoaded = @{}
function Save-KV([string]$file, [hashtable]$kv) {
    $lines = @()
    if (Test-Path -LiteralPath $file) {
        try { $lines = @(Get-Content -LiteralPath $file -Encoding UTF8 -ErrorAction Stop) }
        catch { $script:saveErr += ((Split-Path $file -Leaf) + ":讀取失敗(" + $_.Exception.Message + ")"); return $false }
        # 讀到 0 行但檔案不是空的 = 讀失敗(被鎖):這時候寫下去會把整檔截成只剩本次的鍵,寧可不寫
        if ($lines.Count -eq 0 -and (Get-Item -LiteralPath $file).Length -gt 3) { $script:saveErr += ((Split-Path $file -Leaf) + ":檔案被佔用,讀不到內容"); return $false }   # >3:只剩 BOM 的檔算空檔
    }
    $done = @{}
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $s = $lines[$i].Trim().TrimStart([char]0xFEFF)
        if ($s.StartsWith("//") -or $s.StartsWith("#")) { continue }
        $eq = $s.IndexOf('=')
        if ($eq -le 0) { continue }
        $orig = $s.Substring(0, $eq).Trim()            # 原本的大小寫要留著(audio.txt 的 clip 名是大小寫敏感的)
        $k = $orig.ToLowerInvariant()
        if ($kv.ContainsKey($k)) {
            # 保留同一行後面的「// 說明」(view.txt 範本是這種寫法;外掛端解析本來就會把 // 之後剝掉)
            $tail = ""; $ci = $lines[$i].IndexOf("//")
            if ($ci -ge 0) { $pre = $lines[$i].Substring(0, $ci); $tail = $pre.Substring($pre.TrimEnd().Length) + $lines[$i].Substring($ci) }
            $lines[$i] = "$orig=$($kv[$k])$tail"; $done[$k] = $true
        }
    }
    foreach ($k in $kv.Keys) { if (-not $done.ContainsKey($k)) { $lines += "$k=$($kv[$k])" } }
    try { Set-Content -LiteralPath $file -Value $lines -Encoding UTF8 -ErrorAction Stop; return $true }
    catch { $script:saveErr += ((Split-Path $file -Leaf) + ":寫入失敗(" + $_.Exception.Message + ")"); return $false }
}

# ── XAML ─────────────────────────────────────────────────────────────────────
$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="SpiritVale 繁中化 設定工具" Width="1100" Height="1040"
        WindowStartupLocation="CenterScreen" Background="#050B14"
        FontFamily="Microsoft JhengHei UI" FontSize="14" Foreground="#E6EBF2">
  <Window.Resources>
    <!-- ═══ 配色:深藍黑底 + 青色發光外框(v3.72 換皮;源的第三版 mockup)═══ -->
    <SolidColorBrush x:Key="Card" Color="#0A1626"/>
    <SolidColorBrush x:Key="Line" Color="#1D5F8A"/>
    <SolidColorBrush x:Key="Sub" Color="#7C93AD"/>
    <SolidColorBrush x:Key="Accent" Color="#22C9F0"/>
    <SolidColorBrush x:Key="AccentDim" Color="#14526E"/>
    <SolidColorBrush x:Key="Panel" Color="#08111E"/>

    <!-- 群組框:半透明底 + 青色邊 + 外發光。全部分頁共用這一個樣式,所以改這裡就是整套換皮 -->
    <Style x:Key="CardBox" TargetType="Border">
      <Setter Property="Background" Value="#0A1626"/>
      <Setter Property="BorderBrush" Value="{StaticResource Line}"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="CornerRadius" Value="8"/>
      <Setter Property="Padding" Value="16,13"/>
      <Setter Property="Margin" Value="0,0,0,14"/>
      <Setter Property="Effect">
        <Setter.Value>
          <DropShadowEffect Color="#1FA8D8" BlurRadius="12" ShadowDepth="0" Opacity="0.30"/>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="H1" TargetType="TextBlock">
      <Setter Property="FontSize" Value="16"/>
      <Setter Property="FontWeight" Value="Bold"/>
      <Setter Property="Foreground" Value="#5FE0FF"/>
      <Setter Property="VerticalAlignment" Value="Center"/>
    </Style>
    <Style x:Key="Hint" TargetType="TextBlock">
      <Setter Property="Foreground" Value="{StaticResource Sub}"/>
      <Setter Property="FontSize" Value="12.5"/>
      <Setter Property="TextWrapping" Value="Wrap"/>
      <Setter Property="VerticalAlignment" Value="Center"/>
    </Style>
    <Style x:Key="Ico" TargetType="TextBlock">
      <Setter Property="FontFamily" Value="Segoe MDL2 Assets"/>
      <Setter Property="FontSize" Value="17"/>
      <Setter Property="Foreground" Value="{StaticResource Accent}"/>
      <Setter Property="Margin" Value="0,0,8,0"/>
      <Setter Property="VerticalAlignment" Value="Center"/>
    </Style>

    <Style TargetType="CheckBox">
      <Setter Property="Foreground" Value="#E6EBF2"/>
      <Setter Property="Margin" Value="0,5,0,5"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="CheckBox">
            <StackPanel Orientation="Horizontal" Background="Transparent">
              <Border x:Name="box" Width="19" Height="19" CornerRadius="4" Margin="0,1,9,0"
                      Background="#071220" BorderBrush="#2E6C92" BorderThickness="1.4" VerticalAlignment="Center">
                <Path x:Name="tick" Data="M3,9 L7.5,13.5 L15,4.5" Stroke="#04121C" StrokeThickness="2.4"
                      Visibility="Collapsed" SnapsToDevicePixels="False"/>
              </Border>
              <ContentPresenter VerticalAlignment="Center"/>
            </StackPanel>
            <ControlTemplate.Triggers>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="box" Property="Background" Value="{StaticResource Accent}"/>
                <Setter TargetName="box" Property="BorderBrush" Value="{StaticResource Accent}"/>
                <Setter TargetName="tick" Property="Visibility" Value="Visible"/>
              </Trigger>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="box" Property="BorderBrush" Value="#5FE0FF"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style TargetType="RadioButton">
      <Setter Property="Foreground" Value="#E6EBF2"/>
      <Setter Property="Margin" Value="0,6,0,6"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="RadioButton">
            <StackPanel Orientation="Horizontal" Background="Transparent">
              <Border x:Name="dot" Width="19" Height="19" CornerRadius="10" Margin="0,1,9,0"
                      Background="#071220" BorderBrush="#2E6C92" BorderThickness="1.4" VerticalAlignment="Center">
                <Ellipse x:Name="inner" Width="9" Height="9" Fill="#04121C" Visibility="Collapsed"/>
              </Border>
              <ContentPresenter VerticalAlignment="Center"/>
            </StackPanel>
            <ControlTemplate.Triggers>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="dot" Property="Background" Value="{StaticResource Accent}"/>
                <Setter TargetName="dot" Property="BorderBrush" Value="{StaticResource Accent}"/>
                <Setter TargetName="inner" Property="Visibility" Value="Visible"/>
              </Trigger>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="dot" Property="BorderBrush" Value="#5FE0FF"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style TargetType="Button">
      <Setter Property="Foreground" Value="#CDE9F7"/>
      <Setter Property="Background" Value="#0C1E31"/>
      <Setter Property="BorderBrush" Value="#2A6C93"/>
      <Setter Property="Padding" Value="14,7"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}"
                    BorderThickness="1" CornerRadius="8" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="bd" Property="Background" Value="#123A56"/>
                <Setter TargetName="bd" Property="BorderBrush" Value="#5FE0FF"/>
              </Trigger>
              <Trigger Property="IsPressed" Value="True"><Setter TargetName="bd" Property="Background" Value="#0A2438"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="AccentBtn" TargetType="Button" BasedOn="{StaticResource {x:Type Button}}">
      <Setter Property="Background" Value="#0E4C6E"/>
      <Setter Property="BorderBrush" Value="#3FC9F0"/>
      <Setter Property="Foreground" Value="#EAF9FF"/>
      <Setter Property="FontWeight" Value="Bold"/>
      <Setter Property="Effect">
        <Setter.Value><DropShadowEffect Color="#22C9F0" BlurRadius="14" ShadowDepth="0" Opacity="0.5"/></Setter.Value>
      </Setter>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}"
                    BorderThickness="1" CornerRadius="10" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="bd" Property="Background" Value="#14688F"/></Trigger>
              <Trigger Property="IsPressed" Value="True"><Setter TargetName="bd" Property="Background" Value="#0A3B57"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="Chip" TargetType="ToggleButton">
      <Setter Property="Foreground" Value="#B9C2D4"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ToggleButton">
            <Border x:Name="bd" Background="#0A1626" BorderBrush="#1D5F8A" BorderThickness="1"
                    CornerRadius="6" Padding="14,6" Margin="0,0,8,0">
              <ContentPresenter/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="bd" Property="Background" Value="#0E4C6E"/>
                <Setter TargetName="bd" Property="BorderBrush" Value="#3FC9F0"/>
                <Setter Property="Foreground" Value="#EAF9FF"/>
              </Trigger>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="bd" Property="BorderBrush" Value="#5FE0FF"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style TargetType="TextBox">
      <Setter Property="Background" Value="#071220"/>
      <Setter Property="Foreground" Value="#DCF2FC"/>
      <Setter Property="BorderBrush" Value="#2A6C93"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Padding" Value="8,5"/>
      <Setter Property="CaretBrush" Value="#E6EBF2"/>
      <Setter Property="VerticalContentAlignment" Value="Center"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="TextBox">
            <Border Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}"
                    BorderThickness="1" CornerRadius="5">
              <ScrollViewer x:Name="PART_ContentHost" Margin="{TemplateBinding Padding}"/>
            </Border>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <!-- ComboBox:WPF 預設樣板會無視 Background(會變白條),整個自繪 -->
    <Style TargetType="ComboBoxItem">
      <Setter Property="Foreground" Value="#E6EBF2"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ComboBoxItem">
            <Border x:Name="bd" Background="Transparent" Padding="10,6" CornerRadius="5" Margin="3,1">
              <ContentPresenter/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsHighlighted" Value="True"><Setter TargetName="bd" Property="Background" Value="#123A56"/></Trigger>
              <Trigger Property="IsSelected" Value="True"><Setter TargetName="bd" Property="Background" Value="#0E4C6E"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style TargetType="ComboBox">
      <Setter Property="Foreground" Value="#E6EBF2"/>
      <Setter Property="Height" Value="34"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ComboBox">
            <Grid>
              <ToggleButton Focusable="False" ClickMode="Press"
                            IsChecked="{Binding IsDropDownOpen, Mode=TwoWay, RelativeSource={RelativeSource TemplatedParent}}">
                <ToggleButton.Template>
                  <ControlTemplate TargetType="ToggleButton">
                    <Border x:Name="bd" Background="#071220" BorderBrush="#2A6C93" BorderThickness="1" CornerRadius="5">
                      <TextBlock Text="&#xE70D;" FontFamily="Segoe MDL2 Assets" FontSize="11" Foreground="#4FB8DD"
                                 HorizontalAlignment="Right" VerticalAlignment="Center" Margin="0,0,10,0"/>
                    </Border>
                    <ControlTemplate.Triggers>
                      <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="bd" Property="BorderBrush" Value="#5FE0FF"/></Trigger>
                    </ControlTemplate.Triggers>
                  </ControlTemplate>
                </ToggleButton.Template>
              </ToggleButton>
              <ContentPresenter Margin="11,0,30,0" VerticalAlignment="Center" IsHitTestVisible="False"
                                Content="{TemplateBinding SelectionBoxItem}"
                                ContentTemplate="{TemplateBinding SelectionBoxItemTemplate}"/>
              <Popup IsOpen="{TemplateBinding IsDropDownOpen}" AllowsTransparency="True" Placement="Bottom" StaysOpen="False">
                <Border Background="#08131F" BorderBrush="#2A6C93" BorderThickness="1" CornerRadius="6"
                        MinWidth="{TemplateBinding ActualWidth}" MaxHeight="300" Margin="0,4,0,0">
                  <ScrollViewer VerticalScrollBarVisibility="Auto">
                    <StackPanel IsItemsHost="True" Margin="0,4"/>
                  </ScrollViewer>
                </Border>
              </Popup>
            </Grid>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <!-- 分頁列:深色 + 底線指示 -->
    <Style TargetType="TabControl">
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Padding" Value="0"/>
    </Style>
    <Style TargetType="TabItem">
      <Setter Property="Foreground" Value="#8A94A8"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="TabItem">
            <Border x:Name="bd" Background="Transparent" Padding="14,9" CornerRadius="6"
                    BorderThickness="1" BorderBrush="Transparent" Margin="0,0,4,0">
              <ContentPresenter ContentSource="Header"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsSelected" Value="True">
                <Setter TargetName="bd" Property="Background" Value="#0B2C42"/>
                <Setter TargetName="bd" Property="BorderBrush" Value="#3FC9F0"/>
                <Setter Property="Foreground" Value="#7FEAFF"/>
                <Setter TargetName="bd" Property="Effect">
                  <Setter.Value><DropShadowEffect Color="#22C9F0" BlurRadius="10" ShadowDepth="0" Opacity="0.55"/></Setter.Value>
                </Setter>
              </Trigger>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="bd" Property="Background" Value="#0A2032"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Window.Resources>

  <DockPanel LastChildFill="True">
    <!-- 狀態列 -->
    <Border DockPanel.Dock="Bottom" Background="#071220" BorderBrush="{StaticResource Line}" BorderThickness="0,1,0,0" Padding="14,6">
      <DockPanel>
        <TextBlock x:Name="LblStatus" Text="狀態:就緒" Foreground="{StaticResource Sub}"/>
        <TextBlock Text="開發人員:源" Foreground="{StaticResource Sub}" HorizontalAlignment="Right"/>
      </DockPanel>
    </Border>

    <!-- ═ 設定健檢(v3.72):真的去掃遊戲資料夾與設定檔,不是跑動畫 ═ -->
    <Border DockPanel.Dock="Bottom" Padding="18,0,18,10" Background="#050B14">
      <Border Style="{StaticResource CardBox}" Margin="0" MaxWidth="1380">
        <Grid>
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/><ColumnDefinition Width="330"/>
          </Grid.ColumnDefinitions>
          <!-- 健檢頭像:用向量畫的,不需要額外圖檔(圖檔會被防毒當附件、也會讓安裝包變大) -->
          <Border Grid.Column="0" Width="78" Height="78" CornerRadius="8" Margin="0,0,14,0"
                  Background="#071B2C" BorderBrush="#2A6C93" BorderThickness="1" VerticalAlignment="Top">
            <Border.Effect><DropShadowEffect Color="#22C9F0" BlurRadius="12" ShadowDepth="0" Opacity="0.45"/></Border.Effect>
            <Viewbox Margin="7">
            <Canvas Width="100" Height="100">

              <Ellipse Canvas.Left="14" Canvas.Top="14" Width="72" Height="72" Fill="#04202F" Opacity="0.65"/>

              <Polyline Points="8,26 8,8 26,8" Stroke="#1E6E96" StrokeThickness="2.5" StrokeLineJoin="Round"/>
              <Polyline Points="74,8 92,8 92,26" Stroke="#1E6E96" StrokeThickness="2.5" StrokeLineJoin="Round"/>
              <Polyline Points="92,74 92,92 74,92" Stroke="#1E6E96" StrokeThickness="2.5" StrokeLineJoin="Round"/>
              <Polyline Points="26,92 8,92 8,74" Stroke="#1E6E96" StrokeThickness="2.5" StrokeLineJoin="Round"/>

              <Polyline Points="30.5,38.8 16,38.8" Stroke="#2E8FB8" StrokeThickness="2.5"/>
              <Polyline Points="69.5,38.8 84,38.8" Stroke="#2E8FB8" StrokeThickness="2.5"/>
              <Polyline Points="30.5,61.2 16,61.2" Stroke="#2E8FB8" StrokeThickness="2.5"/>
              <Polyline Points="69.5,61.2 84,61.2" Stroke="#2E8FB8" StrokeThickness="2.5"/>
              <Ellipse Canvas.Left="11.5" Canvas.Top="36.3" Width="5" Height="5" Fill="#4FD6FF"/>
              <Ellipse Canvas.Left="83" Canvas.Top="36.3" Width="5" Height="5" Fill="#4FD6FF"/>
              <Ellipse Canvas.Left="11.5" Canvas.Top="58.7" Width="5" Height="5" Fill="#4FD6FF"/>
              <Ellipse Canvas.Left="83" Canvas.Top="58.7" Width="5" Height="5" Fill="#4FD6FF"/>

              <Polyline Points="50,27.5 50,15.5" Stroke="#4FD6FF" StrokeThickness="2.5" StrokeLineJoin="Round"/>
              <Polyline Points="50,72.5 50,84.5" Stroke="#4FD6FF" StrokeThickness="2.5" StrokeLineJoin="Round"/>
              <Polyline Points="24,50 15.5,50" Stroke="#4FD6FF" StrokeThickness="2.5" StrokeLineJoin="Round"/>
              <Polyline Points="76,50 84.5,50" Stroke="#4FD6FF" StrokeThickness="2.5" StrokeLineJoin="Round"/>
              <Polyline Points="37,27.5 37,17 24,17" Stroke="#4FD6FF" StrokeThickness="2.5" StrokeLineJoin="Round"/>
              <Polyline Points="63,27.5 63,17 76,17" Stroke="#4FD6FF" StrokeThickness="2.5" StrokeLineJoin="Round"/>
              <Polyline Points="37,72.5 37,83 24,83" Stroke="#4FD6FF" StrokeThickness="2.5" StrokeLineJoin="Round"/>
              <Polyline Points="63,72.5 63,83 76,83" Stroke="#4FD6FF" StrokeThickness="2.5" StrokeLineJoin="Round"/>

              <Rectangle Canvas.Left="46" Canvas.Top="7.5" Width="8" Height="8" Fill="#04202F" Stroke="#7FEAFF" StrokeThickness="2.5"/>
              <Rectangle Canvas.Left="46" Canvas.Top="84.5" Width="8" Height="8" Fill="#04202F" Stroke="#7FEAFF" StrokeThickness="2.5"/>
              <Rectangle Canvas.Left="7.5" Canvas.Top="46" Width="8" Height="8" Fill="#04202F" Stroke="#7FEAFF" StrokeThickness="2.5"/>
              <Rectangle Canvas.Left="84.5" Canvas.Top="46" Width="8" Height="8" Fill="#04202F" Stroke="#7FEAFF" StrokeThickness="2.5"/>
              <Rectangle Canvas.Left="16" Canvas.Top="13" Width="8" Height="8" Fill="#04202F" Stroke="#4FD6FF" StrokeThickness="2.5"/>
              <Rectangle Canvas.Left="76" Canvas.Top="13" Width="8" Height="8" Fill="#04202F" Stroke="#4FD6FF" StrokeThickness="2.5"/>
              <Rectangle Canvas.Left="16" Canvas.Top="79" Width="8" Height="8" Fill="#04202F" Stroke="#4FD6FF" StrokeThickness="2.5"/>
              <Rectangle Canvas.Left="76" Canvas.Top="79" Width="8" Height="8" Fill="#04202F" Stroke="#4FD6FF" StrokeThickness="2.5"/>

              <Path Data="M 76,50 L 63,27.5 L 37,27.5 L 24,50 L 37,72.5 L 63,72.5 Z" Fill="#04202F" Stroke="#4FD6FF" StrokeThickness="3" StrokeLineJoin="Round">
                <Path.Effect>
                  <DropShadowEffect Color="#22C9F0" BlurRadius="10" ShadowDepth="0" Opacity="0.9"/>
                </Path.Effect>
              </Path>

              <Path Data="M 65.6,41 L 50,32 L 34.4,41 L 34.4,59 L 50,68 L 65.6,59 Z" Fill="#0C3450" Stroke="#4FD6FF" StrokeThickness="2.5" StrokeLineJoin="Round">
                <Path.Effect>
                  <DropShadowEffect Color="#22C9F0" BlurRadius="8" ShadowDepth="0" Opacity="0.7"/>
                </Path.Effect>
              </Path>

              <Ellipse Canvas.Left="41" Canvas.Top="41" Width="18" Height="18" Fill="#1E6E96" Stroke="#7FEAFF" StrokeThickness="2.5">
                <Ellipse.Effect>
                  <DropShadowEffect Color="#22C9F0" BlurRadius="10" ShadowDepth="0" Opacity="0.9"/>
                </Ellipse.Effect>
              </Ellipse>

              <Ellipse Canvas.Left="46" Canvas.Top="46" Width="8" Height="8" Fill="#7FEAFF">
                <Ellipse.Effect>
                  <DropShadowEffect Color="#7FEAFF" BlurRadius="12" ShadowDepth="0" Opacity="1"/>
                </Ellipse.Effect>
              </Ellipse>

            </Canvas>
            </Viewbox>
          </Border>
          <StackPanel Grid.Column="1" Margin="0,0,14,0">
            <DockPanel>
              <Button x:Name="BtnHealth" DockPanel.Dock="Right" Content="重新檢查" Width="104" Height="30" VerticalAlignment="Top"/>
              <TextBlock x:Name="LblHealthTitle" Text="設定健檢" Style="{StaticResource H1}"/>
            </DockPanel>
            <TextBlock x:Name="LblHealthDesc" Style="{StaticResource Hint}" Margin="0,2,0,6"
                       Text="檢查外掛檔案、相容性、熱鍵衝突與設定值 —— 全部在你自己的電腦上做,不會連任何網路。"/>
            <Border Height="10" CornerRadius="5" Background="#071220" BorderBrush="#1D5F8A" BorderThickness="1">
              <Border x:Name="BarHealth" HorizontalAlignment="Left" Width="0" CornerRadius="4" Background="#22C9F0"/>
            </Border>
            <WrapPanel Margin="0,7,0,0">
              <TextBlock x:Name="StepH1" Style="{StaticResource Hint}" Margin="0,0,16,0" Text="○ 掃描外掛檔案"/>
              <TextBlock x:Name="StepH2" Style="{StaticResource Hint}" Margin="0,0,16,0" Text="○ 檢查相容性"/>
              <TextBlock x:Name="StepH3" Style="{StaticResource Hint}" Margin="0,0,16,0" Text="○ 檢查熱鍵"/>
              <TextBlock x:Name="StepH4" Style="{StaticResource Hint}" Margin="0,0,16,0" Text="○ 檢查設定檔"/>
              <TextBlock x:Name="StepH5" Style="{StaticResource Hint}" Text="○ 效能與畫質"/>
            </WrapPanel>
          </StackPanel>
          <Border Grid.Column="2" CornerRadius="6" Background="#071220" BorderBrush="#1D5F8A" BorderThickness="1" Padding="9,7">
            <DockPanel>
              <TextBlock DockPanel.Dock="Top" Text="即時日誌" Foreground="#5FE0FF" FontSize="12.5" FontWeight="Bold" Margin="0,0,0,4"/>
              <ScrollViewer x:Name="SvHealthLog" VerticalScrollBarVisibility="Auto" Height="78">
                <TextBlock x:Name="LblHealthLog" Foreground="#7C93AD" FontSize="11.5" TextWrapping="NoWrap"/>
              </ScrollViewer>
            </DockPanel>
          </Border>
        </Grid>
      </Border>
    </Border>

    <!-- 底部動作列 -->
    <Border DockPanel.Dock="Bottom" Padding="18,10,18,8" Background="#050B14">
      <Grid MaxWidth="1380">
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="300"/><ColumnDefinition Width="*"/><ColumnDefinition Width="300"/>
        </Grid.ColumnDefinitions>
        <Border Style="{StaticResource CardBox}" Margin="0,0,12,0">
          <StackPanel>
            <TextBlock Text="目前選擇摘要" Style="{StaticResource H1}" Margin="0,0,0,6"/>
            <TextBlock x:Name="LblSum1" Style="{StaticResource Hint}"/>
            <TextBlock x:Name="LblSum2" Style="{StaticResource Hint}"/>
            <TextBlock x:Name="LblSum3" Style="{StaticResource Hint}"/>
            <TextBlock x:Name="LblSum4" Style="{StaticResource Hint}" Text="翻譯模式: —"/>
          </StackPanel>
        </Border>
        <StackPanel Grid.Column="1" VerticalAlignment="Center" Margin="4,0">
          <Button x:Name="BtnApply" Style="{StaticResource AccentBtn}" Height="58" Margin="0,0,0,8">
            <StackPanel Orientation="Horizontal">
              <TextBlock Style="{StaticResource Ico}" Foreground="White" Text="&#xE73E;" FontSize="20"/>
              <StackPanel>
                <TextBlock Text="套用設定" FontSize="16" FontWeight="Bold"/>
                <TextBlock Text="寫入設定檔,遊戲內約 5 秒自動生效(不用重裝、不用重開遊戲)" FontSize="11.5" Foreground="#D8E6FF"/>
              </StackPanel>
            </StackPanel>
          </Button>
          <Button x:Name="BtnResetAll" Height="44">
            <StackPanel Orientation="Horizontal">
              <TextBlock Style="{StaticResource Ico}" Text="&#xE72C;"/>
              <TextBlock Text="重設所有設定(回復所有選項為預設值)" VerticalAlignment="Center"/>
            </StackPanel>
          </Button>
        </StackPanel>
        <Border Grid.Column="2" Style="{StaticResource CardBox}" Margin="12,0,0,0">
          <StackPanel>
            <TextBlock Text="小提示" Style="{StaticResource H1}" Margin="0,0,0,6"/>
            <TextBlock Style="{StaticResource Hint}" Text="‧勾選 = 啟用/停用,檔案照常安裝"/>
            <TextBlock Style="{StaticResource Hint}" Text="‧套用後遊戲不用重開,約 5 秒生效"/>
            <TextBlock x:Name="HintAdv" Style="{StaticResource Hint}" Text="‧分享/匯入掉寶音效在「掉落音效」頁"/>
          </StackPanel>
        </Border>
      </Grid>
    </Border>

    <!-- 頂部:遊戲路徑列 -->
    <Border DockPanel.Dock="Top" Padding="18,14,18,0" Background="#050B14">
      <Border Style="{StaticResource CardBox}" MaxWidth="1380">
        <StackPanel>
          <DockPanel>
            <StackPanel DockPanel.Dock="Right" Orientation="Horizontal" Margin="10,0,0,0">
              <CheckBox x:Name="ChkSplash" Content="開場動畫" Margin="0,0,12,0" VerticalAlignment="Center"/>
              <TextBlock Text="音量" VerticalAlignment="Center" Margin="0,0,6,0"/>
              <TextBox x:Name="TxtVol" Width="52" Margin="0,0,12,0"/>
              <TextBlock Text="介面縮放" VerticalAlignment="Center" Margin="0,0,6,0"/>
              <ComboBox x:Name="CboUiScale" Width="84" VerticalAlignment="Center">
                <ComboBoxItem Content="100%" Tag="1.0"/><ComboBoxItem Content="115%" Tag="1.15"/>
                <ComboBoxItem Content="130%" Tag="1.3"/><ComboBoxItem Content="150%" Tag="1.5"/>
              </ComboBox>
            </StackPanel>
            <TextBlock Text="遊戲路徑" Style="{StaticResource H1}"/>
          </DockPanel>
          <DockPanel Margin="0,8,0,0">
            <Button x:Name="BtnTutorial" DockPanel.Dock="Right" Margin="8,0,0,0">
              <StackPanel Orientation="Horizontal">
                <TextBlock Style="{StaticResource Ico}" Text="&#xE897;"/>
                <TextBlock Text="使用教學" VerticalAlignment="Center"/>
              </StackPanel>
            </Button>
            <Button x:Name="BtnBrowse" DockPanel.Dock="Right" Content="瀏覽" Margin="8,0,0,0"/>
            <TextBox x:Name="TxtPath" IsReadOnly="True"/>
          </DockPanel>
          <TextBlock x:Name="LblVer" Style="{StaticResource Hint}" Margin="0,7,0,0"/>
        </StackPanel>
      </Border>
    </Border>

    <!-- 分頁 -->
    <TabControl x:Name="Tabs" Margin="18,4,18,0" MaxWidth="1380">
      <!-- ═ 功能自選 ═ -->
      <TabItem x:Name="TabMain">
        <TabItem.Header>
          <StackPanel Orientation="Horizontal">
            <TextBlock Text="&#xE71D;" FontFamily="Segoe MDL2 Assets" FontSize="15" Margin="0,0,7,0" VerticalAlignment="Center"/>
            <TextBlock Text="功能自選" FontSize="14.5" VerticalAlignment="Center"/>
          </StackPanel>
        </TabItem.Header>
        <ScrollViewer VerticalScrollBarVisibility="Auto" Padding="0,10,6,0">
          <Grid>
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="*"/><ColumnDefinition Width="316"/>
            </Grid.ColumnDefinitions>
            <StackPanel Grid.Column="0" Margin="0,0,14,0">
              <DockPanel x:Name="ChipBar" Margin="2,0,2,10">
                <StackPanel DockPanel.Dock="Right" Orientation="Horizontal">
                  <Button x:Name="BtnAll" Content="全選" Margin="0,0,8,0"/>
                  <Button x:Name="BtnInv" Content="反選" Margin="0,0,8,0"/>
                  <Button x:Name="BtnRst" Content="重設"/>
                </StackPanel>
                <StackPanel Orientation="Horizontal">
                  <ToggleButton x:Name="ChipAll" Style="{StaticResource Chip}" Content="全部" IsChecked="True"/>
                  <ToggleButton x:Name="ChipView" Style="{StaticResource Chip}" Content="畫面"/>
                  <ToggleButton x:Name="ChipPerf" Style="{StaticResource Chip}" Content="效能"/>
                  <ToggleButton x:Name="ChipCd" Style="{StaticResource Chip}" Content="冷卻"/>
                  <ToggleButton x:Name="ChipInst" Style="{StaticResource Chip}" Content="安裝"/>
                </StackPanel>
              </DockPanel>

              <Border x:Name="CardView" Style="{StaticResource CardBox}">
                <StackPanel>
                  <StackPanel Orientation="Horizontal" Margin="0,0,0,6">
                    <TextBlock Style="{StaticResource Ico}" Text="&#xE7F4;"/>
                    <TextBlock Text="畫面" Style="{StaticResource H1}"/>
                    <TextBlock Text="(純顯示,不影響任何遊戲數值)" Style="{StaticResource Hint}"/>
                  </StackPanel>
                  <CheckBox x:Name="ChkHide" Content="隱藏其他玩家(含其坐騎/寵物;自己、怪物、掉落物不受影響)"/>
                  <StackPanel Orientation="Horizontal" Margin="26,0,0,0">
                    <CheckBox x:Name="ChkParty" Content="隊友照常顯示" Margin="0,5,26,5"/>
                    <CheckBox x:Name="ChkGuild" Content="公會成員照常顯示" Margin="0,5,26,5"/>
                    <CheckBox x:Name="ChkFriend" Content="好友照常顯示"/>
                  </StackPanel>
                  <CheckBox x:Name="ChkNum" Content="只隱藏他們跳出來的傷害數字(特效與音效照舊)" Margin="26,5,0,5"/>
                  <CheckBox x:Name="ChkFx" Content="連他們的技能特效一起隱藏(比遊戲內建特效開關更徹底)" Margin="26,5,0,5"/>
                  <CheckBox x:Name="ChkMute" Content="連他們的技能/攻擊音效一起靜音(自己、怪物、掉寶音效不受影響)" Margin="26,5,0,5"/>
                  <CheckBox x:Name="ChkFull" Content="完全隱藏(連他們的所有行為一起停用;最徹底,實驗性)" Margin="26,5,0,5"/>
                  <Separator Margin="0,6,0,6" Background="#2A3448"/>
                  <CheckBox x:Name="ChkZero" Content="擋掉地上莫名其妙跳出來的「0」(值 0 + 沒有攻擊者 + 沒打中,三者同時才擋;跟隱藏玩家無關)"/>
                </StackPanel>
              </Border>

              <Border x:Name="CardPerf" Style="{StaticResource CardBox}">
                <StackPanel>
                  <StackPanel Orientation="Horizontal" Margin="0,0,0,6">
                    <TextBlock Style="{StaticResource Ico}" Text="&#xE945;"/>
                    <TextBlock Text="效能" Style="{StaticResource H1}"/>
                    <TextBlock Text="(純本機顯示層,只對你自己生效)" Style="{StaticResource Hint}"/>
                  </StackPanel>
                  <CheckBox x:Name="ChkShadow" Content="關閉陰影(顯著省最多;陰影是整批額外的繪製呼叫)"/>
                  <CheckBox x:Name="ChkAnim" Content="其他玩家的動畫「鏡頭外不計算」(主城省 CPU;畫面內的玩家不受影響)"/>
                  <CheckBox x:Name="ChkFxMine" Content="技能特效只留自己人的(陌生人特效全關;隊友/公會/好友與傷害數字照舊)"/>
                </StackPanel>
              </Border>
              <Border x:Name="CardChat" Style="{StaticResource CardBox}">
                <StackPanel>
                  <StackPanel Orientation="Horizontal" Margin="0,0,0,6">
                    <TextBlock Style="{StaticResource Ico}" Text="&#xE8BD;"/>
                    <TextBlock Text="聊天" Style="{StaticResource H1}"/>
                  </StackPanel>
                  <WrapPanel>
                    <TextBlock Text="右鍵玩家名稱 → 「組隊邀請」:" VerticalAlignment="Center" Margin="0,0,8,0"/>
                    <ComboBox x:Name="CboChatInvite" Width="230">
                      <ComboBoxItem Content="關閉"/>
                      <ComboBoxItem Content="填好 /invite 名字,按 Enter 送(預設)"/>
                      <ComboBoxItem Content="按了直接送出"/>
                    </ComboBox>
                  </WrapPanel>
                  <TextBlock Style="{StaticResource Hint}" Margin="0,6,0,0" Text="‧走的是遊戲自己的 /invite 指令,跟手打完全一樣;系統訊息與自己的訊息不會出現這個選項。"/>
                </StackPanel>
              </Border>
              <Border x:Name="CardBuff" Style="{StaticResource CardBox}">
                <StackPanel>
                  <StackPanel Orientation="Horizontal" Margin="0,0,0,6">
                    <TextBlock Style="{StaticResource Ico}" Text="&#xE7C4;"/>
                    <TextBlock Text="Buff / Debuff 圖示位置" Style="{StaticResource H1}"/>
                    <TextBlock Text="(純顯示:把三排狀態圖示移出遊戲的排版;關掉就掛回原位)" Style="{StaticResource Hint}"/>
                  </StackPanel>
                  <WrapPanel>
                    <TextBlock Text="放在:" VerticalAlignment="Center" Margin="0,0,8,0"/>
                    <ComboBox x:Name="CboBuffPos" Width="260">
                      <ComboBoxItem Content="遊戲預設位置(不動)"/>
                      <ComboBoxItem Content="面板(可拖曳的小面板,含開關按鈕)"/>
                      <ComboBoxItem Content="跟著角色(腳下血條 + 下面的位移)"/>
                    </ComboBox>
                    <TextBlock Text="縮放:" VerticalAlignment="Center" Margin="14,0,6,0"/>
                    <TextBox x:Name="TBuffScale" Width="56"/>
                  </WrapPanel>
                  <WrapPanel Margin="0,8,0,0">
                    <TextBlock Text="Buff 列位移 X" VerticalAlignment="Center" Margin="0,0,6,0"/>
                    <TextBox x:Name="TBuffX" Width="62" Margin="0,0,10,0"/>
                    <TextBlock Text="Y" VerticalAlignment="Center" Margin="0,0,6,0"/>
                    <TextBox x:Name="TBuffY" Width="62" Margin="0,0,18,0"/>
                    <TextBlock Text="Debuff 列位移 X" VerticalAlignment="Center" Margin="0,0,6,0"/>
                    <TextBox x:Name="TDebuffX" Width="62" Margin="0,0,10,0"/>
                    <TextBlock Text="Y" VerticalAlignment="Center" Margin="0,0,6,0"/>
                    <TextBox x:Name="TDebuffY" Width="62"/>
                  </WrapPanel>
                  <WrapPanel Margin="0,8,0,0">
                    <TextBlock Text="主要狀態列位移 X" VerticalAlignment="Center" Margin="0,0,6,0"/>
                    <TextBox x:Name="TMainX" Width="62" Margin="0,0,10,0"/>
                    <TextBlock Text="Y" VerticalAlignment="Center" Margin="0,0,6,0"/>
                    <TextBox x:Name="TMainY" Width="62"/>
                  </WrapPanel>
                  <WrapPanel Margin="0,8,0,0">
                    <CheckBox x:Name="ChkPartyBuff" Content="隊伍框顯示成員的狀態列(取消勾選 = 整排隱藏)" VerticalAlignment="Center"/>
                    <TextBlock Text="遊戲內切換快捷鍵:" VerticalAlignment="Center" Margin="14,0,6,0"/>
                    <TextBox x:Name="TPartyBuffKey" Width="70" VerticalAlignment="Center"/>
                    <TextBlock Text="(點欄位直接按鍵,例 F9;Esc=清空)" Foreground="#8A94A8" FontSize="12" VerticalAlignment="Center" Margin="6,0,0,0"/>
                  </WrapPanel>
                  <TextBlock Style="{StaticResource Hint}" TextWrapping="Wrap" Margin="0,6,0,0" Text="‧「面板」= 一塊可拖曳的小面板:左鍵按住標題列整塊拖著走,面板上有「隊伍列」與「跟著角色」兩顆按鈕,位置放開自動記住。‧「跟著角色」的排版是【全自動】的:外掛會量角色名牌有多深、每一排實際多寬多高,自動排在名牌下方、置中、依序往下堆疊 —— 位移欄位【全部留 0 即可】,只有想再往旁邊挪一點時才填(單位是像素,Y 往下為正)。按 DPS 編輯鍵(預設 F10)可左鍵單獨拖每一排微調;此模式下面板縮小留著當控制台,按「收回面板」切回。改完套用,遊戲裡 5 秒生效。"/>
                </StackPanel>
              </Border>
              <Border x:Name="CardFxSkill" Style="{StaticResource CardBox}">
                <StackPanel>
                  <StackPanel Orientation="Horizontal" Margin="0,0,0,6">
                    <TextBlock Style="{StaticResource Ico}" Text="&#xE91B;"/>
                    <TextBlock Text="只關特定技能的特效" Style="{StaticResource H1}"/>
                    <TextBlock Text="(別人放的這些技能不生特效;你自己的永遠不受影響)" Style="{StaticResource Hint}"/>
                  </StackPanel>
                  <CheckBox x:Name="ChkFxSkillOn" Content="啟用技能特效黑名單"/>
                  <DockPanel Margin="0,8,0,0">
                    <StackPanel DockPanel.Dock="Right" Margin="10,0,0,0" Width="190">
                      <Button x:Name="BFxSkillPick" Content="從技能清單挑…" Margin="0,0,0,6"/>
                      <Button x:Name="BFxSkillImport" Content="從 log 匯入" Margin="0,0,0,6"/>
                      <CheckBox x:Name="ChkFxSkillDiag" Content="收集模式(記技能代號)" Margin="0,0,0,6"/>
                      <TextBlock Style="{StaticResource Hint}" TextWrapping="Wrap"
                                 Text="勾收集模式 → 去最洗版的地方站一下 → 回來按「從 log 匯入」,別人放過的技能會列出來,留下想關的就好。"/>
                    </StackPanel>
                    <TextBox x:Name="TFxSkill" AcceptsReturn="True" TextWrapping="NoWrap" VerticalScrollBarVisibility="Auto" Height="110" FontFamily="Consolas"/>
                  </DockPanel>
                  <TextBlock Style="{StaticResource Hint}" TextWrapping="Wrap" Margin="0,6,0,0"
                             Text="‧一行一個技能代號(英文,例如 HolyWrathField)。「#」開頭的行是註解。只關特效,不關傷害、不關音效、不影響任何數值。怪物/王的技能不會被這份清單影響(同名也不會)。"/>
                </StackPanel>
              </Border>

              <Border x:Name="CardCd" Style="{StaticResource CardBox}">
                <StackPanel>
                  <StackPanel Orientation="Horizontal" Margin="0,0,0,6">
                    <TextBlock Style="{StaticResource Ico}" Text="&#xE823;"/>
                    <TextBlock Text="技能冷卻顯示" Style="{StaticResource H1}"/>
                    <TextBlock Text="(只改外觀,不影響冷卻時間本身)" Style="{StaticResource Hint}"/>
                  </StackPanel>
                  <TextBlock Style="{StaticResource Hint}" Margin="0,0,0,8"
                             Text="遊戲原廠:遮罩偏灰白、秒數壓在圖示正中央。下面全部留空 / 0 就是維持原樣。"/>
                  <!-- 固定欄寬的格線:WrapPanel 在窄視窗會把「秒數顏色」擠到下一行,標籤與欄位就錯位了 -->
                  <Grid>
                    <Grid.ColumnDefinitions>
                      <ColumnDefinition Width="112"/><ColumnDefinition Width="Auto"/>
                      <ColumnDefinition Width="90"/><ColumnDefinition Width="Auto"/>
                      <ColumnDefinition Width="*"/>
                    </Grid.ColumnDefinitions>
                    <Grid.RowDefinitions>
                      <RowDefinition Height="36"/><RowDefinition Height="36"/><RowDefinition Height="36"/><RowDefinition Height="36"/>
                    </Grid.RowDefinitions>
                    <TextBlock Grid.Row="0" Grid.Column="0" Text="冷卻遮罩顏色:" VerticalAlignment="Center"/>
                    <Button x:Name="BtnCdMask" Grid.Row="0" Grid.Column="1" Content="(不改)" Width="110" HorizontalAlignment="Left"/>
                    <TextBlock Grid.Row="0" Grid.Column="2" Text="不透明度:" VerticalAlignment="Center" Margin="16,0,0,0"/>
                    <TextBox x:Name="TxtCdAlpha" Grid.Row="0" Grid.Column="3" Width="56" HorizontalAlignment="Left"/>
                    <TextBlock Grid.Row="0" Grid.Column="4" Text="-1 = 不改;0~100(原廠約 94)" Style="{StaticResource Hint}" Margin="10,0,0,0"/>
                    <TextBlock Grid.Row="1" Grid.Column="0" Text="秒數顏色:" VerticalAlignment="Center"/>
                    <Button x:Name="BtnCdText" Grid.Row="1" Grid.Column="1" Content="(不改)" Width="110" HorizontalAlignment="Left"/>
                    <TextBlock Grid.Row="1" Grid.Column="4" Text="建議遮罩顏色偏黑、再把不透明度調高,冷卻中才看得出來變暗" Style="{StaticResource Hint}" Margin="10,0,0,0"/>
                    <TextBlock Grid.Row="2" Grid.Column="0" Text="秒數位移 X:" VerticalAlignment="Center"/>
                    <TextBox x:Name="TxtCdX" Grid.Row="2" Grid.Column="1" Width="56" HorizontalAlignment="Left"/>
                    <TextBlock Grid.Row="2" Grid.Column="2" Text="Y:" VerticalAlignment="Center" Margin="16,0,0,0"/>
                    <TextBox x:Name="TxtCdY" Grid.Row="2" Grid.Column="3" Width="56" HorizontalAlignment="Left"/>
                    <TextBlock Grid.Row="2" Grid.Column="4" Text="像素;X 正=往右、Y 正=往上。想把秒數挪離圖案中央就用這個" Style="{StaticResource Hint}" Margin="10,0,0,0"/>
                    <TextBlock Grid.Row="3" Grid.Column="0" Text="秒數字級:" VerticalAlignment="Center"/>
                    <TextBox x:Name="TxtCdSize" Grid.Row="3" Grid.Column="1" Width="56" HorizontalAlignment="Left"/>
                    <TextBlock Grid.Row="3" Grid.Column="4" Text="0 = 不改(遊戲原廠 60)" Style="{StaticResource Hint}" Margin="10,0,0,0"/>
                  </Grid>
                </StackPanel>
              </Border>

              <Border x:Name="CardInst" Style="{StaticResource CardBox}">
                <StackPanel>
                  <StackPanel Orientation="Horizontal" Margin="0,0,0,10">
                    <TextBlock Style="{StaticResource Ico}" Text="&#xE896;"/>
                    <TextBlock Text="安裝與維護" Style="{StaticResource H1}"/>
                    <TextBlock Text="(會開黑色視窗執行,完成後回到本畫面)" Style="{StaticResource Hint}"/>
                  </StackPanel>
                  <UniformGrid Columns="3">
                    <Button x:Name="BtnInstall" Height="64" Margin="0,0,10,0">
                      <StackPanel>
                        <StackPanel Orientation="Horizontal" HorizontalAlignment="Center">
                          <TextBlock Style="{StaticResource Ico}" Text="&#xE896;"/>
                          <TextBlock Text="安裝 / 更新翻譯" FontWeight="Bold" VerticalAlignment="Center"/>
                        </StackPanel>
                        <TextBlock Text="依「翻譯與字型」分頁的選擇進行" Style="{StaticResource Hint}" HorizontalAlignment="Center"/>
                      </StackPanel>
                    </Button>
                    <Button x:Name="BtnDiag" Height="64" Margin="0,0,10,0">
                      <StackPanel>
                        <StackPanel Orientation="Horizontal" HorizontalAlignment="Center">
                          <TextBlock Style="{StaticResource Ico}" Text="&#xE9F9;"/>
                          <TextBlock Text="產生診斷報告" FontWeight="Bold" VerticalAlignment="Center"/>
                        </StackPanel>
                        <TextBlock Text="收集系統與遊戲資訊" Style="{StaticResource Hint}" HorizontalAlignment="Center"/>
                      </StackPanel>
                    </Button>
                    <Button x:Name="BtnUninstall" Height="64">
                      <StackPanel>
                        <StackPanel Orientation="Horizontal" HorizontalAlignment="Center">
                          <TextBlock Style="{StaticResource Ico}" Text="&#xE74D;"/>
                          <TextBlock Text="移除翻譯" FontWeight="Bold" VerticalAlignment="Center"/>
                        </StackPanel>
                        <TextBlock Text="一鍵恢復原版" Style="{StaticResource Hint}" HorizontalAlignment="Center"/>
                      </StackPanel>
                    </Button>
                  </UniformGrid>
                </StackPanel>
              </Border>
            </StackPanel>

            <Border x:Name="CardPerfParam" Grid.Column="1" Style="{StaticResource CardBox}" VerticalAlignment="Top">
              <StackPanel>
                <TextBlock Text="自訂參數(效能模組專屬)" Style="{StaticResource H1}" Margin="0,0,0,12"/>
                <TextBlock Text="渲染解析度"/>
                <TextBox x:Name="TxtScale" Margin="0,5,0,2"/>
                <TextBlock Text="倍(0 = 不縮放;0.75 是畫質與效能的甜蜜點)" Style="{StaticResource Hint}" Margin="0,0,0,10"/>
                <TextBlock Text="放大濾鏡"/>
                <ComboBox x:Name="CboUp" Margin="0,5,0,10">
                  <ComboBoxItem Content="不使用"/><ComboBoxItem Content="FSR(建議)"/><ComboBoxItem Content="STP"/>
                </ComboBox>
                <TextBlock Text="銳利度"/>
                <TextBox x:Name="TxtSharp" Margin="0,5,0,2"/>
                <TextBlock Text="0~1(0 = 預設)" Style="{StaticResource Hint}" Margin="0,0,0,10"/>
                <TextBlock Text="幀率上限"/>
                <TextBox x:Name="TxtFps" Margin="0,5,0,2"/>
                <TextBlock Text="fps(0 = 不限)" Style="{StaticResource Hint}" Margin="0,0,0,10"/>
                <TextBlock Text="垂直同步"/>
                <ComboBox x:Name="CboVs" Margin="0,5,0,10">
                  <ComboBoxItem Content="不變更"/><ComboBoxItem Content="關閉"/><ComboBoxItem Content="開啟"/>
                </ComboBox>
                <TextBlock Text="抗鋸齒 MSAA"/>
                <ComboBox x:Name="CboMsaa" Margin="0,5,0,10">
                  <ComboBoxItem Content="不變更"/><ComboBoxItem Content="關閉"/><ComboBoxItem Content="2x"/><ComboBoxItem Content="4x"/><ComboBoxItem Content="8x"/>
                </ComboBox>
                <TextBlock Style="{StaticResource Hint}" Margin="0,4,0,0"
                           Text="‧選 STP 時 MSAA 必須設「關閉」,否則 STP 會被 URP 停用。"/>
                <TextBlock Style="{StaticResource Hint}" Margin="0,6,0,0"
                           Text="‧放大濾鏡要搭「渲染解析度」一起用 —— 解析度保持 0 或 1 時,濾鏡完全不會作用。"/>
              </StackPanel>
            </Border>
          </Grid>
        </ScrollViewer>
      </TabItem>

      <!-- ═ 翻譯與字型(本批遷移)═ -->
      <TabItem x:Name="TabTrans">
        <TabItem.Header>
          <StackPanel Orientation="Horizontal">
            <TextBlock Text="&#xE8D2;" FontFamily="Segoe MDL2 Assets" FontSize="15" Margin="0,0,7,0" VerticalAlignment="Center"/>
            <TextBlock Text="翻譯與字型" FontSize="14.5" VerticalAlignment="Center"/>
          </StackPanel>
        </TabItem.Header>
        <ScrollViewer VerticalScrollBarVisibility="Auto" Padding="0,10,6,0">
          <StackPanel MaxWidth="1000" HorizontalAlignment="Left">
            <Border Style="{StaticResource CardBox}">
              <StackPanel>
                <StackPanel Orientation="Horizontal" Margin="0,0,0,6">
                  <TextBlock Style="{StaticResource Ico}" Text="&#xE8C1;"/>
                  <TextBlock Text="顯示模式" Style="{StaticResource H1}"/>
                  <TextBlock Text="(改完按下方「套用設定」,遊戲內 5 秒生效)" Style="{StaticResource Hint}"/>
                </StackPanel>
                <RadioButton x:Name="RbM1" Content="全部雙語 —— 物品/技能/職業/屬性/狀態/NPC 都顯示「中文 English」"/>
                <RadioButton x:Name="RbM2" Content="物品名雙語 —— 物品/地圖/怪物名雙語,其他名詞純中文(預設)"/>
                <RadioButton x:Name="RbM3" Content="物品名純中文 —— 全中文,畫面最乾淨"/>
                <RadioButton x:Name="RbM4" Content="原文 —— 完全不翻譯,只用掉寶音效/隱藏玩家等功能"/>
                <Separator Margin="0,8,0,6" Background="#2A3448"/>
                <CheckBox x:Name="ChkMapWrap" Content="地圖名雙語分成上下兩行(哥布林村莊 ↵ Goblin Village;3D 大標籤會多一行)"/>
                <CheckBox x:Name="ChkBaseStatEn" Content="六大基礎能力值維持英文縮寫(STR / AGI / VIT / INT / DEX / LUK 不翻成中文)" Margin="0,5,0,0"/>
                <TextBlock Style="{StaticResource Hint}" Margin="26,2,0,0"
                           Text="‧能力值那項寫進 SpiritZh_keep.txt(保留原文清單)。習慣看英文縮寫配裝的人勾這個。"/>
              </StackPanel>
            </Border>
            <Border Style="{StaticResource CardBox}">
              <StackPanel>
                <StackPanel Orientation="Horizontal" Margin="0,0,0,6">
                  <TextBlock Style="{StaticResource Ico}" Text="&#xE8D2;"/>
                  <TextBlock Text="自訂字型" Style="{StaticResource H1}"/>
                  <TextBlock Text="(改整個遊戲介面的字型;改完按「套用設定」)" Style="{StaticResource Hint}"/>
                </StackPanel>
                <WrapPanel>
                  <ComboBox x:Name="CboFont" Width="340" Margin="0,0,10,0"/>
                  <Button x:Name="BtnFontFile" Content="載入字型檔(.ttf / .otf / .ttc)…"/>
                </WrapPanel>
                <TextBlock x:Name="LblFontNow" Style="{StaticResource Hint}" Margin="0,8,0,0"/>
                <Border Background="#101827" BorderBrush="#33405A" BorderThickness="1" CornerRadius="4" Padding="10,6" Margin="0,8,0,0">
                  <TextBlock x:Name="LblFontPreview" FontSize="18" Text="預覽:小兔子 Bunny 攻擊 ATK 永恆之塔 0123 傳說裝備"/>
                </Border>
                <TextBlock Style="{StaticResource Hint}" Margin="0,4,0,0"
                           Text="‧「遊戲預設」= 不改字型。字型檔會自動複製到外掛資料夾;中文檔名會自動轉存成英數檔名(中文檔名會讓底層載入器靜默失敗)。"/>
                <TextBlock Style="{StaticResource Hint}" Margin="0,4,0,0"
                           Text="‧上面的預覽框用的是你電腦的字型;遊戲裡實際長相以進遊戲為準(外掛會把字型檔複製進外掛資料夾)。"/>
              </StackPanel>
            </Border>
          </StackPanel>
        </ScrollViewer>
      </TabItem>

      <!-- ═ 掉落音效(本批遷移)═ -->
      <TabItem x:Name="TabSerial">
        <TabItem.Header>
          <StackPanel Orientation="Horizontal">
            <TextBlock Text="&#xE192;" FontFamily="Segoe MDL2 Assets" FontSize="15" Margin="0,0,7,0" VerticalAlignment="Center"/>
            <TextBlock Text="序號" FontSize="14.5" VerticalAlignment="Center"/>
          </StackPanel>
        </TabItem.Header>
        <ScrollViewer VerticalScrollBarVisibility="Auto" Padding="0,10,6,0">
          <StackPanel MaxWidth="1000" HorizontalAlignment="Left">
            <Border Style="{StaticResource CardBox}">
              <StackPanel>
                <StackPanel Orientation="Horizontal" Margin="0,0,0,6">
                  <TextBlock Style="{StaticResource Ico}" Text="&#xE192;"/>
                  <TextBlock Text="序號" Style="{StaticResource H1}"/>
                </StackPanel>
                <TextBlock Style="{StaticResource Hint}" TextWrapping="Wrap"
                           Text="沒有加入指定公會、但作者給了你序號時用這裡。序號會綁定你的 Steam 帳號 —— 別人拿去用不了;你自己重灌或換電腦則可以再啟用一次。"/>
              </StackPanel>
            </Border>
            <Border x:Name="CardSerial" Style="{StaticResource CardBox}">
              <StackPanel>
                <StackPanel Orientation="Horizontal" Margin="0,0,0,4">
                  <TextBlock Text="①" Style="{StaticResource H1}" Margin="0,0,8,0"/>
                  <TextBlock Text="把你的帳號識別給作者" Style="{StaticResource H1}"/>
                </StackPanel>
                <TextBlock Style="{StaticResource Hint}" TextWrapping="Wrap" Margin="0,0,0,10"
                           Text="按「複製申請訊息」會複製一段寫好的文字,直接貼給作者就行。顯示「(先進遊戲一次才會產生)」的話,先進遊戲一次再按「重新整理」。"/>
                <StackPanel Orientation="Horizontal" Margin="0,0,0,8">
                  <TextBlock Text="我的帳號識別" VerticalAlignment="Center" Margin="0,0,10,0" MinWidth="96"/>
                  <TextBox x:Name="TxtMyId" Width="250" IsReadOnly="True" VerticalAlignment="Center" FontFamily="Consolas"/>
                </StackPanel>
                <WrapPanel>
                  <Button x:Name="BtnMyIdReq" Content="複製申請訊息" Width="130" Margin="0,0,10,0"/>
                  <Button x:Name="BtnMyIdCopy" Content="只複製號碼" Width="110" Margin="0,0,10,0"/>
                  <Button x:Name="BtnMyIdRefresh" Content="重新整理" Width="100"/>
                </WrapPanel>
              </StackPanel>
            </Border>
            <Border Style="{StaticResource CardBox}">
              <StackPanel>
                <StackPanel Orientation="Horizontal" Margin="0,0,0,4">
                  <TextBlock Text="②" Style="{StaticResource H1}" Margin="0,0,8,0"/>
                  <TextBlock Text="貼上序號" Style="{StaticResource H1}"/>
                </StackPanel>
                <TextBlock Style="{StaticResource Hint}" TextWrapping="Wrap" Margin="0,0,0,10"
                           Text="整串貼上,不要漏字也不要斷行(SVZH1. 開頭,大約五百多個字元)。按「套用序號」之後,如果是需要啟用的序號,會多出一顆「啟用」按鈕。"/>
                <TextBox x:Name="TxtSerial" Height="80" TextWrapping="Wrap" AcceptsReturn="True"
                         VerticalScrollBarVisibility="Auto" FontFamily="Consolas" FontSize="11"/>
                <WrapPanel Margin="0,10,0,0">
                  <Button x:Name="BtnSerialApply" Content="套用序號" Width="120" Height="30" Margin="0,0,10,0"/>
                  <Button x:Name="BtnSerialAct" Content="啟用" Width="120" Height="30" Margin="0,0,10,0" Visibility="Collapsed"/>
                  <Button x:Name="BtnSerialClear" Content="清除序號" Width="110" Height="30"/>
                </WrapPanel>
              </StackPanel>
            </Border>
            <Border Style="{StaticResource CardBox}">
              <StackPanel>
                <StackPanel Orientation="Horizontal" Margin="0,0,0,4">
                  <TextBlock Text="③" Style="{StaticResource H1}" Margin="0,0,8,0"/>
                  <TextBlock Text="目前狀態" Style="{StaticResource H1}"/>
                </StackPanel>
                <TextBlock x:Name="LblSerialState" Style="{StaticResource Hint}" TextWrapping="Wrap" Text=""/>
                <TextBlock Style="{StaticResource Hint}" TextWrapping="Wrap" Margin="0,8,0,0"
                           Text="‧套用或啟用完成後要【重開遊戲】才生效。&#10;‧想確認成功沒有:進遊戲一次,再到「關於」頁按「產生診斷報告」,最上面那行會寫「序號: …」。&#10;‧換電腦或重灌之後,同一組序號可以再啟用一次,不用跟作者要新的。"/>
              </StackPanel>
            </Border>
          </StackPanel>
        </ScrollViewer>
      </TabItem>
      <TabItem x:Name="TabAudio">
        <TabItem.Header>
          <StackPanel Orientation="Horizontal">
            <TextBlock Text="&#xE995;" FontFamily="Segoe MDL2 Assets" FontSize="15" Margin="0,0,7,0" VerticalAlignment="Center"/>
            <TextBlock Text="掉落音效" FontSize="14.5" VerticalAlignment="Center"/>
          </StackPanel>
        </TabItem.Header>
        <ScrollViewer VerticalScrollBarVisibility="Auto" Padding="0,10,6,0">
          <Grid>
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="*"/><ColumnDefinition Width="340"/>
            </Grid.ColumnDefinitions>
            <StackPanel Grid.Column="0" Margin="0,0,14,0">
              <Border Style="{StaticResource CardBox}">
                <StackPanel>
                  <StackPanel Orientation="Horizontal" Margin="0,0,0,4">
                    <TextBlock Style="{StaticResource Ico}" Text="&#xE995;"/>
                    <TextBlock Text="掉寶音效" Style="{StaticResource H1}"/>
                    <TextBlock Text="(依遊戲光柱顏色;藍光/白光遊戲本身沒聲音,是這個外掛幫你播的)" Style="{StaticResource Hint}"/>
                  </StackPanel>
                  <TextBlock Style="{StaticResource Hint}" Margin="0,0,0,10" TextWrapping="Wrap"
                             Text="※ 精華與採集花是【藍光】不是紫光 —— 想聽採集提示要設藍光那一列。音效檔支援 wav / mp3(ogg 不支援,請先轉檔)。"/>
                  <Button x:Name="BAudPreset" HorizontalAlignment="Left" Width="230" Margin="0,0,0,12">
                    <StackPanel Orientation="Horizontal">
                      <TextBlock Style="{StaticResource Ico}" Text="&#xE735;"/>
                      <TextBlock Text="一鍵套用作者推薦" VerticalAlignment="Center"/>
                    </StackPanel>
                  </Button>
                  <Grid>
                    <Grid.ColumnDefinitions>
                      <ColumnDefinition Width="148"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>
                    <Grid.RowDefinitions>
                      <RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/>
                      <RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/>
                    </Grid.RowDefinitions>
                    <TextBlock Grid.Row="0" Text="金光(傳說裝備)" VerticalAlignment="Center" Foreground="#FFC24A" FontWeight="Bold"/>
                    <ComboBox x:Name="CboSndLegendary" Grid.Row="0" Grid.Column="1" Margin="0,3,8,3"/>
                    <Button   x:Name="BSndLegendary" Grid.Row="0" Grid.Column="2" Content="選音效檔…" Width="104" Margin="0,3,8,3"/>
                    <TextBox  x:Name="TVolLegendary" Grid.Row="0" Grid.Column="3" Width="74" Margin="0,3,0,3" TextAlignment="Center"/>
                    <TextBlock Grid.Row="1" Text="紫光(傳說寶物)" VerticalAlignment="Center" Foreground="#C77DFF" FontWeight="Bold"/>
                    <ComboBox x:Name="CboSndPurple" Grid.Row="1" Grid.Column="1" Margin="0,3,8,3"/>
                    <Button   x:Name="BSndPurple" Grid.Row="1" Grid.Column="2" Content="選音效檔…" Width="104" Margin="0,3,8,3"/>
                    <TextBox  x:Name="TVolPurple" Grid.Row="1" Grid.Column="3" Width="74" Margin="0,3,0,3" TextAlignment="Center"/>
                    <TextBlock Grid.Row="2" Text="綠光(獨特)" VerticalAlignment="Center" Foreground="#5BE38B" FontWeight="Bold"/>
                    <ComboBox x:Name="CboSndUnique" Grid.Row="2" Grid.Column="1" Margin="0,3,8,3"/>
                    <Button   x:Name="BSndUnique" Grid.Row="2" Grid.Column="2" Content="選音效檔…" Width="104" Margin="0,3,8,3"/>
                    <TextBox  x:Name="TVolUnique" Grid.Row="2" Grid.Column="3" Width="74" Margin="0,3,0,3" TextAlignment="Center"/>
                    <TextBlock Grid.Row="3" Text="藍光(稀有)" VerticalAlignment="Center" Foreground="#5FC8FF" FontWeight="Bold"/>
                    <ComboBox x:Name="CboSndRare" Grid.Row="3" Grid.Column="1" Margin="0,3,8,3"/>
                    <Button   x:Name="BSndRare" Grid.Row="3" Grid.Column="2" Content="選音效檔…" Width="104" Margin="0,3,8,3"/>
                    <TextBox  x:Name="TVolRare" Grid.Row="3" Grid.Column="3" Width="74" Margin="0,3,0,3" TextAlignment="Center"/>
                    <TextBlock Grid.Row="4" Text="白光(普通)" VerticalAlignment="Center" Foreground="#E8EFF6" FontWeight="Bold"/>
                    <ComboBox x:Name="CboSndCommon" Grid.Row="4" Grid.Column="1" Margin="0,3,8,3"/>
                    <Button   x:Name="BSndCommon" Grid.Row="4" Grid.Column="2" Content="選音效檔…" Width="104" Margin="0,3,8,3"/>
                    <TextBox  x:Name="TVolCommon" Grid.Row="4" Grid.Column="3" Width="74" Margin="0,3,0,3" TextAlignment="Center"/>
                    <TextBlock Grid.Row="5" Text="貴重礦石(細分)" VerticalAlignment="Center" Foreground="#9BE8C8" FontWeight="Bold"/>
                    <ComboBox x:Name="CboSndGreen" Grid.Row="5" Grid.Column="1" Margin="0,3,8,3"/>
                    <Button   x:Name="BSndGreen" Grid.Row="5" Grid.Column="2" Content="選音效檔…" Width="104" Margin="0,3,8,3"/>
                    <TextBox  x:Name="TVolGreen" Grid.Row="5" Grid.Column="3" Width="74" Margin="0,3,0,3" TextAlignment="Center"/>
                  </Grid>
                  <TextBlock Style="{StaticResource Hint}" Margin="0,4,0,10" Text="右邊那格是音量 %(5~300;100 = 原音量)。「貴重礦石」比紫光更優先,用來把高階礦石跟其他紫光分開。"/>
                  <WrapPanel>
                    <TextBlock Text="防洗版冷卻:" VerticalAlignment="Center" Margin="0,0,6,0"/>
                    <TextBox x:Name="TAudCool" Width="60" Margin="0,0,6,0"/>
                    <TextBlock Text="秒(0~30;0 = 每件都響,長音效照樣播完)" Style="{StaticResource Hint}" Margin="0,0,0,0"/>
                  </WrapPanel>
                  <CheckBox x:Name="ChkOwnOnly" Content="只有自己的掉落才播音效(別人的、以及過期的公共掉落都不播)" Margin="0,10,0,0"/>
                </StackPanel>
              </Border>

              <Border Style="{StaticResource CardBox}">
                <StackPanel>
                  <StackPanel Orientation="Horizontal" Margin="0,0,0,4">
                    <TextBlock Style="{StaticResource Ico}" Text="&#xE71C;"/>
                    <TextBlock Text="什麼情況才播" Style="{StaticResource H1}"/>
                    <TextBlock Text="(全部不勾 = 所有掉落都播)" Style="{StaticResource Hint}"/>
                  </StackPanel>
                  <CheckBox x:Name="ChkSkipLocked" Content="別人的掉落(灰色/鎖定中)不播音效"/>
                  <TextBlock Text="物品分類:" Margin="0,10,0,4"/>
                  <WrapPanel>
                    <CheckBox x:Name="FEquip" Content="裝備" Margin="0,4,18,4"/>
                    <CheckBox x:Name="FArtifact" Content="神器" Margin="0,4,18,4"/>
                    <CheckBox x:Name="FCard" Content="卡片" Margin="0,4,18,4"/>
                    <CheckBox x:Name="FGem" Content="寶石" Margin="0,4,18,4"/>
                    <CheckBox x:Name="FConsumable" Content="消耗品" Margin="0,4,18,4"/>
                    <CheckBox x:Name="FCosmetic" Content="時裝" Margin="0,4,18,4"/>
                    <CheckBox x:Name="FJunk" Content="雜物" Margin="0,4,0,4"/>
                  </WrapPanel>
                  <TextBlock Text="稀有度:" Margin="0,8,0,4"/>
                  <WrapPanel>
                    <CheckBox x:Name="RLegendary" Content="傳說(金/紫光)" Margin="0,4,18,4"/>
                    <CheckBox x:Name="RUnique" Content="獨特(綠光)" Margin="0,4,18,4"/>
                    <CheckBox x:Name="RRare" Content="稀有(藍光)" Margin="0,4,18,4"/>
                    <CheckBox x:Name="RCommon" Content="普通(白光)" Margin="0,4,0,4"/>
                  </WrapPanel>
                  <WrapPanel Margin="0,10,0,0">
                    <TextBlock Text="多組條件怎麼組合:" VerticalAlignment="Center" Margin="0,0,8,0"/>
                    <ComboBox x:Name="CboFMode" Width="230">
                      <ComboBoxItem Content="每一組都要符合(且,預設)"/><ComboBoxItem Content="符合任一組就播(或)"/>
                    </ComboBox>
                  </WrapPanel>
                  <TextBlock Style="{StaticResource Hint}" Margin="0,6,0,0" TextWrapping="Wrap"
                             Text="例:勾了稀有度「獨特」又指定了物品清單 —— 「且」= 只有【獨特而且在清單裡】的才響(多數人要的);「或」= 所有獨特都會響,物品清單等於沒作用。"/>
                  <TextBlock Text="指定物品(可與上面併用):" Margin="0,12,0,4"/>
                  <DockPanel>
                    <StackPanel DockPanel.Dock="Right" Margin="10,0,0,0" Width="130">
                      <Button x:Name="BNameAdd" Content="加入物品…" Margin="0,0,8,8"/>
                      <Button x:Name="BNameDel" Content="移除選取" Margin="0,0,8,0"/>
                    </StackPanel>
                    <ListBox x:Name="LstNames" Height="120" Background="#101827" Foreground="#E6EBF2" BorderBrush="#33405A"/>
                  </DockPanel>
                  <TextBlock x:Name="LblNameCount" Style="{StaticResource Hint}" Margin="0,6,0,0"/>
                </StackPanel>
              </Border>

              <Border Style="{StaticResource CardBox}">
                <StackPanel>
                  <StackPanel Orientation="Horizontal" Margin="0,0,0,4">
                    <TextBlock Style="{StaticResource Ico}" Text="&#xE74F;"/>
                    <TextBlock Text="完全靜音的物品" Style="{StaticResource H1}"/>
                    <TextBlock Text="(優先於上面所有條件)" Style="{StaticResource Hint}"/>
                  </StackPanel>
                  <TextBlock Style="{StaticResource Hint}" Margin="0,0,0,8" TextWrapping="Wrap"
                             Text="命中的物品連【遊戲自己的掉落聲】也會一起壓掉 —— 就算你沒設任何自訂音效,也可以只用這一項讓某些東西別再吵你。"/>
                  <DockPanel>
                    <StackPanel DockPanel.Dock="Right" Margin="10,0,0,0" Width="130">
                      <Button x:Name="BMuteAdd" Content="加入物品…" Margin="0,0,8,8"/>
                      <Button x:Name="BMuteDel" Content="移除選取" Margin="0,0,8,0"/>
                    </StackPanel>
                    <ListBox x:Name="LstMute" Height="120" Background="#101827" Foreground="#E6EBF2" BorderBrush="#33405A"/>
                  </DockPanel>
                  <TextBlock x:Name="LblMuteCount" Style="{StaticResource Hint}" Margin="0,6,0,0"/>
                  <TextBlock Style="{StaticResource Hint}" Margin="0,6,0,0" TextWrapping="Wrap"
                             Text="※ 侷限:攔截點分不出「這一聲屬於哪一件掉落」,同一個 0.8 秒內連掉多件時,靜音可能連帶壓掉隔壁那件的原音。"/>
                </StackPanel>
              </Border>
            </StackPanel>

            <StackPanel Grid.Column="1">
              <Border Style="{StaticResource CardBox}">
                <StackPanel>
                  <StackPanel Orientation="Horizontal" Margin="0,0,0,8">
                    <TextBlock Style="{StaticResource Ico}" Text="&#xE8B7;"/>
                    <TextBlock Text="音效檔" Style="{StaticResource H1}"/>
                  </StackPanel>
                  <TextBlock Style="{StaticResource Hint}" TextWrapping="Wrap"
                             Text="音效檔放在遊戲的 BepInEx\plugins\SpiritZh_sounds\;用「選音效檔…」挑檔會自動複製進去,之後在下拉選單就選得到。"/>
                  <Button x:Name="BSndFolder" Content="開啟音效資料夾" Margin="0,10,0,0"/>
                  <Button x:Name="BSndRefresh" Content="重新掃描音效檔" Margin="0,8,0,0"/>
                  <Separator Margin="0,10,0,8" Background="#2A3448"/>
                  <TextBlock Text="分享給朋友" Style="{StaticResource H1}" Margin="0,0,0,4"/>
                  <Button x:Name="BSndExport" Content="匯出分享檔(.svsnd)…" Margin="0,4,0,0"/>
                  <Button x:Name="BSndImport" Content="匯入別人的分享檔…" Margin="0,8,0,0"/>
                  <TextBlock Style="{StaticResource Hint}" TextWrapping="Wrap" Margin="0,6,0,0"
                             Text="把掉寶音效與過濾器設定(可連音效檔)打包成一個檔給朋友;匯入會【整組取代】,動手前自動備份。"/>
                </StackPanel>
              </Border>
              <Border Style="{StaticResource CardBox}">
                <StackPanel>
                  <StackPanel Orientation="Horizontal" Margin="0,0,0,8">
                    <TextBlock Style="{StaticResource Ico}" Text="&#xE946;"/>
                    <TextBlock Text="判定順序" Style="{StaticResource H1}"/>
                  </StackPanel>
                  <TextBlock Style="{StaticResource Hint}" TextWrapping="Wrap"
                             Text="① 靜音清單命中 → 連原音一起壓掉&#10;② 貴重礦石(細分)&#10;③ 紫光(傳說但不是裝備:卡片/神器/材料)&#10;④ 稀有度(金光 = 傳說裝備)&#10;⑤ 上面的「什麼情況才播」再過濾一次"/>
                  <Separator Margin="0,10,0,10" Background="#2A3448"/>
                  <TextBlock Style="{StaticResource Hint}" Text="‧音效沒反應時:到「關於」頁打開「掉落來源結構」診斷,再產生診斷報告。"/>
                </StackPanel>
              </Border>
            </StackPanel>
          </Grid>
        </ScrollViewer>
      </TabItem>
      <!-- ═ 掉落光柱(本批遷移;依 mockup 3)═ -->
      <TabItem x:Name="TabBeam">
        <TabItem.Header>
          <StackPanel Orientation="Horizontal">
            <TextBlock Text="&#xE790;" FontFamily="Segoe MDL2 Assets" FontSize="15" Margin="0,0,7,0" VerticalAlignment="Center"/>
            <TextBlock Text="掉落光柱" FontSize="14.5" VerticalAlignment="Center"/>
          </StackPanel>
        </TabItem.Header>
        <ScrollViewer VerticalScrollBarVisibility="Auto" Padding="0,10,6,0">
          <Grid>
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="*"/><ColumnDefinition Width="316"/>
            </Grid.ColumnDefinitions>
            <StackPanel Grid.Column="0" Margin="0,0,14,0">
              <Border Style="{StaticResource CardBox}">
                <StackPanel>
                  <StackPanel Orientation="Horizontal" Margin="0,0,0,4">
                    <TextBlock Style="{StaticResource Ico}" Text="&#xE790;"/>
                    <TextBlock Text="自訂光柱" Style="{StaticResource H1}"/>
                    <TextBlock Text="(純顯示層:只改你自己畫面上那顆光柱的顏色,不碰數值、不碰封包)" Style="{StaticResource Hint}"/>
                  </StackPanel>
                  <CheckBox x:Name="ChkBeamOn" Content="啟用自訂光柱(以下規則才會作用;不影響其他玩家)"/>
                  <TextBlock Style="{StaticResource Hint}" Margin="26,0,0,0"
                             Text="光柱是遊戲本身就有的東西,這裡只是把它換個顏色 —— 沒有光柱的掉落(白光雜物)不會憑空多出來。"/>
                </StackPanel>
              </Border>

              <Border Style="{StaticResource CardBox}">
                <StackPanel>
                  <StackPanel Orientation="Horizontal" Margin="0,0,0,8">
                    <TextBlock Style="{StaticResource Ico}" Text="&#xE8FD;"/>
                    <TextBlock Text="自動規則" Style="{StaticResource H1}"/>
                    <TextBlock Text="(優先序:指定物品 > 王卡 > 王裝 > 獨特裝備 > 紫光整組 > 低掉率;顏色留空 = 該規則不啟用)" Style="{StaticResource Hint}"/>
                  </StackPanel>
                  <Grid>
                    <Grid.ColumnDefinitions>
                      <ColumnDefinition Width="230"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/>
                    </Grid.ColumnDefinitions>
                    <Grid.RowDefinitions>
                      <RowDefinition Height="38"/><RowDefinition Height="38"/><RowDefinition Height="38"/>
                      <RowDefinition Height="38"/><RowDefinition Height="38"/><RowDefinition Height="38"/>
                    </Grid.RowDefinitions>
                    <TextBlock Grid.Row="0" Text="王卡 —— Boss 掉落重點標示" VerticalAlignment="Center"/>
                    <Button x:Name="BBossCard" Grid.Row="0" Grid.Column="1" Content="(不用)" Width="120"/>
                    <TextBlock Grid.Row="0" Grid.Column="2" Text="Boss 掉的卡片" Style="{StaticResource Hint}" Margin="10,0,0,0"/>
                    <TextBlock Grid.Row="1" Text="王裝 —— Boss 掉落裝備" VerticalAlignment="Center"/>
                    <Button x:Name="BBossEquip" Grid.Row="1" Grid.Column="1" Content="(不用)" Width="120"/>
                    <TextBlock Grid.Row="1" Grid.Column="2" Text="Boss 掉的裝備" Style="{StaticResource Hint}" Margin="10,0,0,0"/>
                    <TextBlock Grid.Row="2" Text="獨特裝備 —— 遊戲標記 Unique" VerticalAlignment="Center"/>
                    <Button x:Name="BUniqueEq" Grid.Row="2" Grid.Column="1" Content="(不用)" Width="120"/>
                    <TextBlock Grid.Row="2" Grid.Column="2" Text="遊戲內標記為 Unique(獨特)的裝備" Style="{StaticResource Hint}" Margin="10,0,0,0"/>
                    <TextBlock Grid.Row="3" Text="紫光整組 —— 卡片/神器/鑲嵌材料" VerticalAlignment="Center"/>
                    <Button x:Name="BPurpleAll" Grid.Row="3" Grid.Column="1" Content="(不用)" Width="120"/>
                    <TextBlock Grid.Row="3" Grid.Column="2" Text="所有紫光掉落整組換色(建議這一組才用彩虹)" Style="{StaticResource Hint}" Margin="10,0,0,0"/>
                    <TextBlock Grid.Row="4" Text="稀有掉落 —— 掉率低於門檻" VerticalAlignment="Center"/>
                    <Button x:Name="BChance" Grid.Row="4" Grid.Column="1" Content="(不用)" Width="120"/>
                    <StackPanel Grid.Row="4" Grid.Column="2" Orientation="Horizontal" Margin="10,0,0,0">
                      <TextBlock Text="掉率低於" VerticalAlignment="Center" Margin="0,0,6,0"/>
                      <TextBox x:Name="TChance" Width="72"/>
                      <TextBlock Text="%(0 = 不用這條規則)" Style="{StaticResource Hint}" Margin="6,0,0,0"/>
                    </StackPanel>
                    <TextBlock Grid.Row="5" Text="測試 —— 所有掉落都染色" VerticalAlignment="Center"/>
                    <Button x:Name="BTestAll" Grid.Row="5" Grid.Column="1" Content="(不用)" Width="120"/>
                    <TextBlock Grid.Row="5" Grid.Column="2" Text="確認功能有沒有作用用的;平常留空" Style="{StaticResource Hint}" Margin="10,0,0,0"/>
                  </Grid>
                </StackPanel>
              </Border>

              <Border Style="{StaticResource CardBox}">
                <StackPanel>
                  <StackPanel Orientation="Horizontal" Margin="0,0,0,8">
                    <TextBlock Style="{StaticResource Ico}" Text="&#xED1A;"/>
                    <TextBlock Text="沒命中任何規則的掉落" Style="{StaticResource H1}"/>
                  </StackPanel>
                  <WrapPanel>
                    <ComboBox x:Name="CboMiss" Width="180" Margin="0,0,14,0">
                      <ComboBoxItem Content="照常顯示(預設)"/><ComboBoxItem Content="半透明(壓暗)"/><ComboBoxItem Content="隱藏光柱"/>
                    </ComboBox>
                    <TextBlock Text="亮度:" VerticalAlignment="Center" Margin="0,0,6,0"/>
                    <TextBox x:Name="TDim" Width="72"/>
                    <TextBlock Text="(0.05~0.9;半透明才用到)" Style="{StaticResource Hint}" Margin="6,0,0,0"/>
                  </WrapPanel>
                  <TextBlock Text="隱藏掉落(整個物品消失:光柱+名稱+圖示):" Margin="0,12,0,4"/>
                  <WrapPanel>
                    <CheckBox x:Name="HEquip" Content="裝備" Margin="0,4,18,4"/>
                    <CheckBox x:Name="HArtifact" Content="神器" Margin="0,4,18,4"/>
                    <CheckBox x:Name="HCard" Content="卡片" Margin="0,4,18,4"/>
                    <CheckBox x:Name="HGem" Content="寶石" Margin="0,4,18,4"/>
                    <CheckBox x:Name="HJunk" Content="材料" Margin="0,4,18,4"/>
                    <CheckBox x:Name="HConsumable" Content="消耗品" Margin="0,4,18,4"/>
                    <CheckBox x:Name="HCosmetic" Content="時裝" Margin="0,4,18,4"/>
                    <CheckBox x:Name="HKeepLeg" Content="傳說(金/紫光)不隱藏" Margin="0,4,0,4"/>
                  </WrapPanel>
                  <TextBlock Style="{StaticResource Hint}" Margin="0,4,0,0"
                             Text="※ 命中上面任何規則、或「指定物品」清單裡的掉落【永遠不會被隱藏】—— 你點名要看的一定看得到。"/>
                </StackPanel>
              </Border>

              <Border Style="{StaticResource CardBox}">
                <StackPanel>
                  <StackPanel Orientation="Horizontal" Margin="0,0,0,8">
                    <TextBlock Style="{StaticResource Ico}" Text="&#xE8EC;"/>
                    <TextBlock Text="指定物品" Style="{StaticResource H1}"/>
                    <TextBlock Text="(優先於上面的自動規則)" Style="{StaticResource Hint}"/>
                  </StackPanel>
                  <DockPanel>
                    <StackPanel DockPanel.Dock="Right" Margin="10,0,0,0" Width="130">
                      <Button x:Name="BItemAdd" Content="加入物品…" Margin="0,0,0,8"/>
                      <Button x:Name="BItemDel" Content="移除選取"/>
                    </StackPanel>
                    <ListBox x:Name="LstItems" Height="150" Background="#101827" Foreground="#E6EBF2" BorderBrush="#33405A"/>
                  </DockPanel>
                  <TextBlock x:Name="LblItemCount" Style="{StaticResource Hint}" Margin="0,6,0,0"/>
                </StackPanel>
              </Border>
            </StackPanel>

            <Border Grid.Column="1" Style="{StaticResource CardBox}" VerticalAlignment="Top">
              <StackPanel>
                <TextBlock Text="外觀參數" Style="{StaticResource H1}" Margin="0,0,0,12"/>
                <TextBlock Text="地上物品名稱的字色"/>
                <ComboBox x:Name="CboNameMode" Margin="0,5,0,4">
                  <ComboBoxItem Content="跟光柱顏色(預設)"/><ComboBoxItem Content="自訂顏色"/><ComboBoxItem Content="不改"/>
                </ComboBox>
                <Button x:Name="BNameColor" Content="(自訂顏色)" Margin="0,0,0,10"/>
                <TextBlock Text="光柱放大倍率"/>
                <TextBox x:Name="TScale" Margin="0,5,0,2"/>
                <TextBlock Text="倍(1.0 = 原本大小;只有命中規則的掉落會放大)" Style="{StaticResource Hint}" Margin="0,0,0,10"/>
                <TextBlock Text="RGB 循環速度"/>
                <TextBox x:Name="TRbSpeed" Margin="0,5,0,2"/>
                <TextBlock Text="秒轉一圈(數字越小變色越快)" Style="{StaticResource Hint}" Margin="0,0,0,10"/>
                <Separator Margin="0,4,0,10" Background="#2A3448"/>
                <TextBlock Style="{StaticResource Hint}" Text="‧顏色沒變時:到「關於」頁打開「光柱處理過程」診斷,再產生診斷報告。"/>
              </StackPanel>
            </Border>
          </Grid>
        </ScrollViewer>
      </TabItem>
      <!-- ═ 詞條品質(本批遷移;依 mockup 4)═ -->
      <TabItem x:Name="TabQuality">
        <TabItem.Header>
          <StackPanel Orientation="Horizontal">
            <TextBlock Text="&#xE9D9;" FontFamily="Segoe MDL2 Assets" FontSize="15" Margin="0,0,7,0" VerticalAlignment="Center"/>
            <TextBlock Text="詞條品質" FontSize="14.5" VerticalAlignment="Center"/>
          </StackPanel>
        </TabItem.Header>
        <ScrollViewer VerticalScrollBarVisibility="Auto" Padding="0,10,6,0">
          <Grid>
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="*"/><ColumnDefinition Width="340"/>
            </Grid.ColumnDefinitions>
            <StackPanel Grid.Column="0" Margin="0,0,14,0">
              <Border Style="{StaticResource CardBox}">
                <StackPanel>
                  <StackPanel Orientation="Horizontal" Margin="0,0,0,4">
                    <TextBlock Style="{StaticResource Ico}" Text="&#xE9D9;"/>
                    <TextBlock Text="詞條品質快篩" Style="{StaticResource H1}"/>
                    <TextBlock Text="(純顯示層:只在你自己畫面上標示裝備好壞,不改數值、不送封包)" Style="{StaticResource Hint}"/>
                  </StackPanel>
                  <CheckBox x:Name="ChkQOn" Content="啟用(背包/倉庫/攤位格子標色 + 物品說明評級行 + 撿起提示音都靠這個總開關)"/>
                  <TextBlock Style="{StaticResource Hint}" Margin="26,0,0,10"
                             Text="分數 = 該件裝備【最好的 3 條】詞條 roll(0~100)的平均;神器看「顯示值頂滿幾條」(3/3 神品、2/3 珍品、1/3 精品)。"/>
                  <TextBlock Text="評級門檻與顏色(分數下限,由高到低比對;顏色留空 = 這一級不標示)" Margin="0,0,0,6"/>
                  <Grid>
                    <Grid.ColumnDefinitions>
                      <ColumnDefinition Width="60"/><ColumnDefinition Width="80"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/>
                    </Grid.ColumnDefinitions>
                    <Grid.RowDefinitions>
                      <RowDefinition Height="38"/><RowDefinition Height="38"/><RowDefinition Height="38"/><RowDefinition Height="38"/><RowDefinition Height="38"/>
                    </Grid.RowDefinitions>
                    <TextBlock Grid.Row="0" Text="神品" VerticalAlignment="Center"/>
                    <TextBox  Grid.Row="0" Grid.Column="1" x:Name="TQ神品" Width="64" HorizontalAlignment="Left"/>
                    <Button   Grid.Row="0" Grid.Column="2" x:Name="BQC神品" Content="(不標)" Width="120" Margin="6,0,0,0"/>
                    <TextBlock Grid.Row="0" Grid.Column="3" Text="分以上。前 4% 的貨;想要跑馬燈就選「RGB 循環」" Style="{StaticResource Hint}" Margin="10,0,0,0"/>
                    <TextBlock Grid.Row="1" Text="珍品" VerticalAlignment="Center"/>
                    <TextBox  Grid.Row="1" Grid.Column="1" x:Name="TQ珍品" Width="64" HorizontalAlignment="Left"/>
                    <Button   Grid.Row="1" Grid.Column="2" x:Name="BQC珍品" Content="(不標)" Width="120" Margin="6,0,0,0"/>
                    <TextBlock Grid.Row="1" Grid.Column="3" Text="分以上。前 10%" Style="{StaticResource Hint}" Margin="10,0,0,0"/>
                    <TextBlock Grid.Row="2" Text="精品" VerticalAlignment="Center"/>
                    <TextBox  Grid.Row="2" Grid.Column="1" x:Name="TQ精品" Width="64" HorizontalAlignment="Left"/>
                    <Button   Grid.Row="2" Grid.Column="2" x:Name="BQC精品" Content="(不標)" Width="120" Margin="6,0,0,0"/>
                    <TextBlock Grid.Row="2" Grid.Column="3" Text="分以上。前 19% —— 這是「有沒有顏色」的分界線,想標少一點就把它調高" Style="{StaticResource Hint}" Margin="10,0,0,0"/>
                    <TextBlock Grid.Row="3" Text="良品" VerticalAlignment="Center"/>
                    <TextBox  Grid.Row="3" Grid.Column="1" x:Name="TQ良品" Width="64" HorizontalAlignment="Left"/>
                    <Button   Grid.Row="3" Grid.Column="2" x:Name="BQC良品" Content="(不標)" Width="120" Margin="6,0,0,0"/>
                    <TextBlock Grid.Row="3" Grid.Column="3" Text="分以上。前 45%;預設不標色" Style="{StaticResource Hint}" Margin="10,0,0,0"/>
                    <TextBlock Grid.Row="4" Text="凡品" VerticalAlignment="Center"/>
                    <TextBlock Grid.Row="4" Grid.Column="1" Text="其餘" Style="{StaticResource Hint}" VerticalAlignment="Center"/>
                    <Button   Grid.Row="4" Grid.Column="2" x:Name="BQC凡品" Content="(不標)" Width="120" Margin="6,0,0,0"/>
                    <TextBlock Grid.Row="4" Grid.Column="3" Text="低於良品門檻的一律凡品;預設不標色 —— 快篩的重點是讓好貨跳出來" Style="{StaticResource Hint}" Margin="10,0,0,0"/>
                  </Grid>
                </StackPanel>
              </Border>

              <Border Style="{StaticResource CardBox}">
                <StackPanel>
                  <StackPanel Orientation="Horizontal" Margin="0,0,0,4">
                    <TextBlock Style="{StaticResource Ico}" Text="&#xE790;"/>
                    <TextBlock Text="格子顯示與染色" Style="{StaticResource H1}"/>
                  </StackPanel>
                  <WrapPanel>
                    <TextBlock Text="背包/倉庫/攤位的格子:" VerticalAlignment="Center" Margin="0,0,6,0"/>
                    <ComboBox x:Name="CboQStyle" Width="200" Margin="0,0,14,0">
                      <ComboBoxItem Content="整格背景染色(預設)"/><ComboBoxItem Content="名稱前加 ◆ 記號"/><ComboBoxItem Content="不標示(只靠說明與提示音)"/>
                    </ComboBox>
                    <TextBlock Text="染色濃度:" VerticalAlignment="Center" Margin="0,0,6,0"/>
                    <TextBox x:Name="TQBlend" Width="64" Margin="0,0,4,0"/>
                    <TextBlock Text="(0~1.0;1 = 整格塗滿,0.45 = 淡淡一層,0 = 不染)" Style="{StaticResource Hint}"/>
                  </WrapPanel>
                  <WrapPanel Margin="0,8,0,0">
                    <TextBlock Text="物品名稱也跟著變色:" VerticalAlignment="Center" Margin="0,0,6,0"/>
                    <ComboBox x:Name="CboQName" Width="200" Margin="0,0,10,0">
                      <ComboBoxItem Content="維持原色(預設)"/><ComboBoxItem Content="所有等級都染"/><ComboBoxItem Content="只染 RGB 循環那一級"/>
                    </ComboBox>
                    <TextBlock Text="只在「整格背景染色」樣式下有作用(◆ 記號樣式名稱一律上色);「所有等級都染」會蓋掉遊戲自己的詞綴色(例「風暴」的黃字)" Style="{StaticResource Hint}" TextWrapping="Wrap" MaxWidth="560"/>
                  </WrapPanel>
                </StackPanel>
              </Border>

              <Border Style="{StaticResource CardBox}">
                <StackPanel>
                  <StackPanel Orientation="Horizontal" Margin="0,0,0,4">
                    <TextBlock Style="{StaticResource Ico}" Text="&#xE946;"/>
                    <TextBlock Text="物品說明評級行" Style="{StaticResource H1}"/>
                  </StackPanel>
                  <CheckBox x:Name="ChkQTip" Content="物品說明開頭多一行評級(例:【珍品】詞條品質 77 分・頂滿 1 條・潛力…)"/>
                </StackPanel>
              </Border>

              <Border Style="{StaticResource CardBox}">
                <StackPanel>
                  <StackPanel Orientation="Horizontal" Margin="0,0,0,4">
                    <TextBlock Style="{StaticResource Ico}" Text="&#xE7BF;"/>
                    <TextBlock Text="自動查市價" Style="{StaticResource H1}"/>
                    <TextBlock Text="(本外掛唯一會對伺服器產生流量的功能 —— 詳見「關於」)" Style="{StaticResource Hint}"/>
                  </StackPanel>
                  <CheckBox x:Name="ChkQPrice" Content="市場搜尋視窗開著時(及關閉後 60 秒內),滑鼠指到的物品自動查最低價,顯示在物品說明上"/>
                  <WrapPanel Margin="26,6,0,0">
                    <TextBlock Text="同一物品每" VerticalAlignment="Center" Margin="0,0,6,0"/>
                    <TextBox x:Name="TQTtl" Width="56" Margin="0,0,6,0"/>
                    <TextBlock Text="分鐘重查一次(1~60;物價波動大就調小)。呼叫的是遊戲自己的搜尋入口、送的跟手動搜尋一樣、全域 2 秒節流;會擔心就關掉,其他功能不受影響。" Style="{StaticResource Hint}" TextWrapping="Wrap" MaxWidth="560"/>
                  </WrapPanel>
                  <CheckBox x:Name="ChkQHist" Content="市場沒開時,物品說明也顯示上次查到的 低 / 中 / 高(只讀本機紀錄,不發任何請求)" Margin="0,10,0,0"/>
                  <WrapPanel Margin="26,6,0,0">
                    <TextBox x:Name="TQHistDays" Width="56" Margin="0,0,6,0"/>
                    <TextBlock Text="天內的紀錄才顯示(1~90)。紀錄來自你自己逛市場時查到的價格;3.76 之前的紀錄格式不可靠,不會顯示,再逛一次市場就會更新。" Style="{StaticResource Hint}" TextWrapping="Wrap" MaxWidth="560"/>
                  </WrapPanel>
                  <DockPanel Margin="26,10,0,0">
                    <Button x:Name="BtnPrices" DockPanel.Dock="Left" Padding="12,6">
                      <StackPanel Orientation="Horizontal">
                        <TextBlock Style="{StaticResource Ico}" Text="&#xE9D5;"/>
                        <TextBlock Text="開啟市價表" VerticalAlignment="Center"/>
                      </StackPanel>
                    </Button>
                    <TextBlock x:Name="LblPriceStat" Style="{StaticResource Hint}" VerticalAlignment="Center" Margin="10,0,0,0" TextWrapping="Wrap"/>
                  </DockPanel>
                  <TextBlock Style="{StaticResource Hint}" TextWrapping="Wrap" Margin="26,8,0,0" Foreground="#7C93AD" Text="※ 這個勾選框【不】控制左下角那塊「市場分析」面板 —— 那是下面那張卡片。"/>
                </StackPanel>
              </Border>

              <Border Style="{StaticResource CardBox}">
                <StackPanel>
                  <StackPanel Orientation="Horizontal" Margin="0,0,0,4">
                    <TextBlock Style="{StaticResource Ico}" Text="&#xE9D2;"/>
                    <TextBlock Text="市場分析面板" Style="{StaticResource H1}"/>
                    <TextBlock Text="(不會對伺服器發任何請求)" Style="{StaticResource Hint}"/>
                  </StackPanel>
                  <CheckBox x:Name="ChkMktPanel" Content="開市場搜尋視窗時,左下角顯示「市場分析」面板"/>
                  <CheckBox x:Name="ChkMktMark" Content="在市場清單上標出低於行情的掛單" Margin="0,6,0,0"/>
                  <TextBlock Style="{StaticResource Hint}" TextWrapping="Wrap" Margin="26,6,0,0" Text="‧資料只來自【你自己搜尋時畫面上已經出現的掛單】,加上本機累積的行情檔 —— 這兩項一次請求都不會多送。"/>
                  <TextBlock Style="{StaticResource Hint}" TextWrapping="Wrap" Margin="26,2,0,0" Text="‧覺得擋畫面就把上面那個取消;跟「自動查市價」是兩個獨立的功能,關一個不會關掉另一個。"/>
                </StackPanel>
              </Border>

              <Border Style="{StaticResource CardBox}">
                <StackPanel>
                  <StackPanel Orientation="Horizontal" Margin="0,0,0,4">
                    <TextBlock Style="{StaticResource Ico}" Text="&#xE8D6;"/>
                    <TextBlock Text="撿起提示音" Style="{StaticResource H1}"/>
                    <TextBlock Text="(撿到達標的裝備/神器那一瞬間播一聲;wav/mp3)" Style="{StaticResource Hint}"/>
                  </StackPanel>
                  <Grid Margin="0,4,0,0">
                    <Grid.ColumnDefinitions>
                      <ColumnDefinition Width="44"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>
                    <Grid.RowDefinitions>
                      <RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/>
                    </Grid.RowDefinitions>
                    <TextBlock Grid.Row="0" Text="神品" VerticalAlignment="Center"/>
                    <TextBox  Grid.Row="0" Grid.Column="1" x:Name="TQP神品" Margin="0,3,8,3"/>
                    <Button   Grid.Row="0" Grid.Column="2" x:Name="BQP神品" Content="瀏覽…" Width="80" Margin="0,3,0,3"/>
                    <TextBlock Grid.Row="1" Text="珍品" VerticalAlignment="Center"/>
                    <TextBox  Grid.Row="1" Grid.Column="1" x:Name="TQP珍品" Margin="0,3,8,3"/>
                    <Button   Grid.Row="1" Grid.Column="2" x:Name="BQP珍品" Content="瀏覽…" Width="80" Margin="0,3,0,3"/>
                    <TextBlock Grid.Row="2" Text="精品" VerticalAlignment="Center"/>
                    <TextBox  Grid.Row="2" Grid.Column="1" x:Name="TQP精品" Margin="0,3,8,3"/>
                    <Button   Grid.Row="2" Grid.Column="2" x:Name="BQP精品" Content="瀏覽…" Width="80" Margin="0,3,0,3"/>
                  </Grid>
                  <WrapPanel Margin="0,6,0,0">
                    <TextBlock Text="音量倍率:" VerticalAlignment="Center" Margin="0,0,6,0"/>
                    <TextBox x:Name="TQVol" Width="56" Margin="0,0,6,0"/>
                    <TextBlock Text="(0 = 關閉提示音,檔案路徑保留;1.0 = 原音量,超過 1.0 不會更大聲)。留空的等級不提示;為什麼不是光柱?詞條 roll 是撿起那一刻伺服器才給,地上做不到。" Style="{StaticResource Hint}" TextWrapping="Wrap" MaxWidth="560"/>
                  </WrapPanel>
                </StackPanel>
              </Border>
            </StackPanel>

            <StackPanel Grid.Column="1">
              <Border Style="{StaticResource CardBox}">
                <StackPanel>
                  <StackPanel Orientation="Horizontal" Margin="0,0,0,6">
                    <TextBlock Style="{StaticResource Ico}" Text="&#xE73A;"/>
                    <TextBlock Text="關注詞條(BD 適配)" Style="{StaticResource H1}"/>
                  </StackPanel>
                  <TextBlock Style="{StaticResource Hint}" TextWrapping="Wrap"
                             Text="勾選你流派在意的屬性,物品說明會多一行「關注 N 條・S 分」—— 只看你在意的詞條算,不影響主分數與格子顏色。「分數很高但不是我要的詞」一眼看穿。"/>
                  <DockPanel Margin="0,10,0,0">
                    <Button x:Name="BQFocusClr" DockPanel.Dock="Right" Content="清除" Width="64" Margin="6,0,0,0"/>
                    <Button x:Name="BQFocus" DockPanel.Dock="Right" Content="設定…" Width="90"/>
                    <TextBlock x:Name="LblQFocus" Text="已勾選 0 項" VerticalAlignment="Center"/>
                  </DockPanel>
                </StackPanel>
              </Border>
              <Border Style="{StaticResource CardBox}">
                <StackPanel>
                  <StackPanel Orientation="Horizontal" Margin="0,0,0,6">
                    <TextBlock Style="{StaticResource Ico}" Text="&#xE707;"/>
                    <TextBlock Text="市場進階濾鏡面板位置" Style="{StaticResource H1}"/>
                  </StackPanel>
                  <WrapPanel>
                    <TextBlock Text="X:" VerticalAlignment="Center" Margin="0,0,6,0"/>
                    <TextBox x:Name="TQPanX" Width="72" Margin="0,0,12,0"/>
                    <TextBlock Text="Y:" VerticalAlignment="Center" Margin="0,0,6,0"/>
                    <TextBox x:Name="TQPanY" Width="72"/>
                  </WrapPanel>
                  <TextBlock Style="{StaticResource Hint}" Margin="0,6,0,0" TextWrapping="Wrap"
                             Text="像素;0 = 遊戲預設(正 X 往右、正 Y 往上)。覺得面板擋畫面就挪開它 —— 遊戲裡也能【按住右鍵拖曳面板】,放開會自動寫回這兩格。"/>
                </StackPanel>
              </Border>
              <Border Style="{StaticResource CardBox}">
                <StackPanel>
                  <StackPanel Orientation="Horizontal" Margin="0,0,0,6">
                    <TextBlock Style="{StaticResource Ico}" Text="&#xE946;"/>
                    <TextBlock Text="小技巧" Style="{StaticResource H1}"/>
                  </StackPanel>
                  <TextBlock Style="{StaticResource Hint}" TextWrapping="Wrap"
                             Text="‧背包搜尋框打「品質90」只顯示 90 分以上的裝備;「品質70到85」= 區間篩選。&#10;‧神器獨立門檻(a神品…)平常用不到,要調請直接編輯 SpiritZh_quality.txt。&#10;‧叫出設定工具 / 帶入進階濾鏡的熱鍵在「傷害統計與熱鍵」頁。"/>
                  <Separator Margin="0,10,0,10" Background="#2A3448"/>
                  <TextBlock Style="{StaticResource Hint}" Text="‧「roll 值範圍」診斷在「關於」頁(預設開著,寫進 status.txt)。"/>
                </StackPanel>
              </Border>
            </StackPanel>
          </Grid>
        </ScrollViewer>
      </TabItem>

      <!-- ═ 傷害統計與熱鍵(本批遷移;依 mockup 5)═ -->
      <TabItem x:Name="TabDps">
        <TabItem.Header>
          <StackPanel Orientation="Horizontal">
            <TextBlock Text="&#xE9D2;" FontFamily="Segoe MDL2 Assets" FontSize="15" Margin="0,0,7,0" VerticalAlignment="Center"/>
            <TextBlock Text="傷害統計" FontSize="14.5" VerticalAlignment="Center"/>
          </StackPanel>
        </TabItem.Header>
        <ScrollViewer VerticalScrollBarVisibility="Auto" Padding="0,10,6,0">
          <StackPanel MaxWidth="1000" HorizontalAlignment="Left">
            <Border Style="{StaticResource CardBox}">
              <StackPanel>
                <StackPanel Orientation="Horizontal" Margin="0,0,0,6">
                  <TextBlock Style="{StaticResource Ico}" Text="&#xE765;"/>
                  <TextBlock Text="熱鍵" Style="{StaticResource H1}"/>
                  <TextBlock Text="(點欄位後【直接按鍵盤】;支援 F1~F12、字母、數字、數字鍵盤、方向鍵等;Esc = 清空停用)" Style="{StaticResource Hint}"/>
                </StackPanel>
                <WrapPanel>
                  <TextBlock Text="開關面板:" VerticalAlignment="Center" Margin="0,0,6,0"/>
                  <TextBox x:Name="KDpsKey" Width="118" Margin="0,0,16,0" TextAlignment="Center"/>
                  <TextBlock Text="切換模式:" VerticalAlignment="Center" Margin="0,0,6,0"/>
                  <TextBox x:Name="KDpsMode" Width="118" Margin="0,0,16,0" TextAlignment="Center"/>
                  <TextBlock Text="歸零重算:" VerticalAlignment="Center" Margin="0,0,6,0"/>
                  <TextBox x:Name="KDpsReset" Width="118" Margin="0,0,16,0" TextAlignment="Center"/>
                  <TextBlock Text="移動面板(編輯模式):" VerticalAlignment="Center" Margin="0,0,6,0"/>
                  <TextBox x:Name="KDpsEdit" Width="118" TextAlignment="Center"/>
                </WrapPanel>
                <TextBlock Style="{StaticResource Hint}" Margin="0,8,0,0"
                           Text="‧進入編輯模式後用【左鍵】拖曳面板,再按一次結束;「移動面板」留空 = 鎖住位置。"/>
              </StackPanel>
            </Border>
            <Border Style="{StaticResource CardBox}">
              <StackPanel>
                <StackPanel Orientation="Horizontal" Margin="0,0,0,6">
                  <TextBlock Style="{StaticResource Ico}" Text="&#xE7F4;"/>
                  <TextBlock Text="面板位置與顯示" Style="{StaticResource H1}"/>
                </StackPanel>
                <WrapPanel>
                  <TextBlock Text="位置 X:" VerticalAlignment="Center" Margin="0,0,6,0"/>
                  <TextBox x:Name="TDpsX" Width="76" Margin="0,0,12,0"/>
                  <TextBlock Text="Y:" VerticalAlignment="Center" Margin="0,0,6,0"/>
                  <TextBox x:Name="TDpsY" Width="76" Margin="0,0,12,0"/>
                  <TextBlock Text="字級:" VerticalAlignment="Center" Margin="0,0,6,0"/>
                  <TextBox x:Name="TDpsSize" Width="56" Margin="0,0,12,0"/>
                  <TextBlock Text="背景暗度:" VerticalAlignment="Center" Margin="0,0,6,0"/>
                  <TextBox x:Name="TDpsBg" Width="56" Margin="0,0,12,0"/>
                  <TextBlock Text="行距:" VerticalAlignment="Center" Margin="0,0,6,0"/>
                  <TextBox x:Name="TDpsLine" Width="56"/>
                </WrapPanel>
                <WrapPanel Margin="0,10,0,0">
                  <TextBlock Text="文字顏色:" VerticalAlignment="Center" Margin="0,0,8,0"/>
                  <Button x:Name="BDpsColor" Content="#D9E0EA" Width="110" Margin="0,0,16,0"/>
                  <CheckBox x:Name="CDpsIcon" Content="每列顯示技能/職業圖示(直接取自遊戲本身,不需額外圖檔)"/>
                </WrapPanel>
                <WrapPanel Margin="0,10,0,0">
                  <TextBlock Text="面板風格:" VerticalAlignment="Center" Margin="0,0,8,0"/>
                  <ComboBox x:Name="CboDpsSkin" Width="190" Margin="0,0,16,0">
                    <ComboBoxItem Content="預設(深藍)" Tag="default"/>
                    <ComboBoxItem Content="暗黑哥德" Tag="gothic"/>
                    <ComboBoxItem Content="科技 HUD" Tag="hud"/>
                    <ComboBoxItem Content="王者金" Tag="gold"/>
                    <ComboBoxItem Content="極簡淺色" Tag="flat"/>
                    <ComboBoxItem Content="冰晶" Tag="ice"/>
                    <ComboBoxItem Content="木紋" Tag="wood"/>
                    <ComboBoxItem Content="復古像素" Tag="pixel"/>
                    <ComboBoxItem Content="賽博霓虹" Tag="neon"/>
                    <ComboBoxItem Content="石板" Tag="stone"/>
                  </ComboBox>
                  <TextBlock Text="自訂邊框圖:" VerticalAlignment="Center" Margin="0,0,6,0"/>
                  <Button x:Name="BDpsFrame" Content="(用風格的)" Width="170" Margin="0,0,6,0"/>
                  <Button x:Name="BDpsFrameClr" Content="清除" Margin="0,0,12,0"/>
                  <TextBlock Text="邊框顏色:" VerticalAlignment="Center" Margin="0,0,6,0"/>
                  <Button x:Name="BDpsFrameColor" Content="(用風格的)" Width="110"/>
                </WrapPanel>
                <TextBlock Style="{StaticResource Hint}" TextWrapping="Wrap" Margin="0,6,0,0"
                           Text="‧風格 = 底色 + 邊框 + 長條色 + 文字色一整套。想用自己(或 AI 生成)的邊框:挑一張【白色 + 透明背景】的 PNG(四邊 28px 是不拉伸的邊角),顏色用右邊的「邊框顏色」染;彩色圖也可以,顏色填 #FFFFFF 就是原色。"/>
                <TextBlock Style="{StaticResource Hint}" Margin="0,8,0,0"
                           Text="‧遊戲裡進入編輯模式(F10)也能直接左鍵拖曳,放開自動記住位置。背景暗度 0 = 不加背景。"/>
              </StackPanel>
            </Border>
            <Border Style="{StaticResource CardBox}">
              <StackPanel>
                <StackPanel Orientation="Horizontal" Margin="0,0,0,6">
                  <TextBlock Style="{StaticResource Ico}" Text="&#xE9D2;"/>
                  <TextBlock Text="統計行為" Style="{StaticResource H1}"/>
                </StackPanel>
                <WrapPanel>
                  <TextBlock Text="開機預設模式:" VerticalAlignment="Center" Margin="0,0,6,0"/>
                  <ComboBox x:Name="CboDpsMode" Width="150" Margin="0,0,16,0">
                    <ComboBoxItem Content="自身(依技能拆)"/><ComboBoxItem Content="隊伍"/><ComboBoxItem Content="全部"/><ComboBoxItem Content="王(每個玩家對王的傷害排行)"/>
                  </ComboBox>
                  <TextBlock Text="脫戰重算:" VerticalAlignment="Center" Margin="0,0,6,0"/>
                  <TextBox x:Name="TDpsIdle" Width="56" Margin="0,0,4,0"/>
                  <TextBlock Text="秒(0 = 只用熱鍵手動歸零)" Style="{StaticResource Hint}" Margin="0,0,16,0"/>
                </WrapPanel>
                <WrapPanel Margin="0,10,0,0">
                  <TextBlock Text="顯示列數:" VerticalAlignment="Center" Margin="0,0,6,0"/>
                  <TextBox x:Name="TDpsRows" Width="56" Margin="0,0,12,0"/>
                  <TextBlock Text="刷新間隔:" VerticalAlignment="Center" Margin="0,0,6,0"/>
                  <TextBox x:Name="TDpsRate" Width="64" Margin="0,0,4,0"/>
                  <TextBlock Text="毫秒(越小越跟手,越大越省效能)" Style="{StaticResource Hint}" Margin="0,0,16,0"/>
                  <CheckBox x:Name="CDpsHp" Content="隊伍/全部模式顯示血量%(打王時一眼看出誰快掛了)"/>
                </WrapPanel>
                <WrapPanel Margin="0,8,0,0">
                  <CheckBox x:Name="CDpsTarget" Content="只顯示「目前目標」的傷害(換目標就換一組數字,舊資料保留)" Margin="0,0,16,0"/>
                  <CheckBox x:Name="CDpsZone" Content="換地區後自動重算" Margin="0,0,16,0"/>
                  <CheckBox x:Name="CDpsMonster" Content="「全部」模式也列出怪物打的傷害"/>
                </WrapPanel>
                <TextBlock Style="{StaticResource Hint}" TextWrapping="Wrap" Margin="0,10,0,0"
                           Text="‧「王」是第 4 種模式,不是過濾器 —— 平常三種照舊,要看王的時候按切換鍵(預設 F8)切過去就好。"/>
                <TextBlock Style="{StaticResource Hint}" TextWrapping="Wrap" Margin="0,2,0,0"
                           Text="‧王模式 = 每個玩家(隊友+路人)對【真正的王】的傷害排行,精英不算;路上清小怪的數字不會把打王的紀錄洗掉。想看自己對王的技能明細:用「自身」+ 下面的「只看目前目標」。切換模式會自動重算(兩種口徑不能混)。"/>
                <TextBlock Style="{StaticResource Hint}" Margin="0,8,0,0"
                           Text="‧每列顯示:名字/總傷害/DPS/次數/佔比+長條。技能名與職業名跟著你的翻譯模式走。純被動統計,不發任何請求。"/>
              </StackPanel>
            </Border>

            <Border Style="{StaticResource CardBox}">
              <StackPanel>
                <StackPanel Orientation="Horizontal" Margin="0,0,0,6">
                  <TextBlock Style="{StaticResource Ico}" Text="&#xE765;"/>
                  <TextBlock Text="其他熱鍵" Style="{StaticResource H1}"/>
                  <TextBlock Text="(一樣點欄位直接按鍵;Esc = 清空停用)" Style="{StaticResource Hint}"/>
                </StackPanel>
                <WrapPanel>
                  <TextBlock Text="叫出設定工具:" VerticalAlignment="Center" Margin="0,0,6,0"/>
                  <TextBox x:Name="KToolKey" Width="118" Margin="0,0,24,0" TextAlignment="Center"/>
                  <TextBlock Text="帶入進階濾鏡:" VerticalAlignment="Center" Margin="0,0,6,0"/>
                  <TextBox x:Name="KMkKey" Width="118" TextAlignment="Center" Margin="0,0,10,0"/>
                  <CheckBox x:Name="ChkMkAuto" Content="自動跟隨(auto)" VerticalAlignment="Center"/>
                </WrapPanel>
                <TextBlock Style="{StaticResource Hint}" Margin="0,8,0,0" TextWrapping="Wrap"
                           Text="‧叫出設定工具:遊戲裡按這個鍵直接打開本工具(要用安裝程式裝過一次,遊戲才知道安裝包在哪)。&#10;‧帶入進階濾鏡:舊功能,預設關閉(留空)—— 查價已改成自動顯示在物品說明上(詞條品質頁)。勾「自動跟隨」= 進階濾鏡面板開著時,條件自動跟到滑鼠指到的那件裝備(不用按鍵)。"/>
              </StackPanel>
            </Border>
          </StackPanel>
        </ScrollViewer>
      </TabItem>
      <!-- ═ 自訂(自訂翻譯 / 地圖音樂)═ -->
      <TabItem x:Name="TabBoss">
        <TabItem.Header>
          <StackPanel Orientation="Horizontal">
            <TextBlock Text="&#xE7C1;" FontFamily="Segoe MDL2 Assets" FontSize="15" Margin="0,0,7,0" VerticalAlignment="Center"/>
            <TextBlock Text="王" FontSize="14.5" VerticalAlignment="Center"/>
          </StackPanel>
        </TabItem.Header>
        <ScrollViewer VerticalScrollBarVisibility="Auto" Padding="0,10,6,0">
          <StackPanel MaxWidth="1000" HorizontalAlignment="Left">
            <Border Style="{StaticResource CardBox}">
              <StackPanel>
                <StackPanel Orientation="Horizontal" Margin="0,0,0,6">
                  <TextBlock Style="{StaticResource Ico}" Text="&#xE7BA;"/>
                  <TextBlock Text="王技提示音" Style="{StaticResource H1}"/>
                  <TextBlock Text="(王開始詠唱就響 —— 提前預警,不是挨打後才響)" Style="{StaticResource Hint}"/>
                </StackPanel>
                <CheckBox x:Name="ChkBaOn" Content="王(Boss / 精英)開始詠唱指定技能時播提示音"/>
                <TextBlock Style="{StaticResource Hint}" TextWrapping="Wrap" Margin="26,4,0,0"
                           Text="‧只認 Boss 與精英怪。玩家的寵物/坐騎/召喚物在這款遊戲也算「怪物」,但會被排除,不會被寵物放技能吵死。"/>

                <WrapPanel Margin="0,10,0,0">
                  <CheckBox x:Name="ChkBaBanner" Content="同時在畫面中央跳一行字" Margin="0,0,20,0"/>
                  <TextBlock Text="音量:" VerticalAlignment="Center" Margin="0,0,6,0"/>
                  <TextBox x:Name="TBaVol" Width="56" Margin="0,0,16,0"/>
                  <TextBlock Text="同一招冷卻:" VerticalAlignment="Center" Margin="0,0,6,0"/>
                  <TextBox x:Name="TBaCd" Width="64" Margin="0,0,4,0"/>
                  <TextBlock Text="毫秒(不同招各響各的)" Style="{StaticResource Hint}"/>
                </WrapPanel>

                <Separator Margin="0,12,0,10" Background="#2A3448"/>
                <StackPanel Orientation="Horizontal" Margin="0,0,0,6">
                  <TextBlock Text="通用提示音" Style="{StaticResource H1}" VerticalAlignment="Center" Margin="0,0,10,0"/>
                  <Button x:Name="BtnBaAll" Content="(不設定)" Width="230"/>
                  <Button x:Name="BtnBaAllClear" Content="清除" Margin="8,0,0,0"/>
                </StackPanel>
                <TextBlock Style="{StaticResource Hint}" TextWrapping="Wrap"
                           Text="‧設了這個,【所有】王技都會響(下面沒有專屬設定的用這個音)。想先聽聽看有哪些技能會觸發,先只設這一個最快。"/>

                <StackPanel Orientation="Horizontal" Margin="0,14,0,6">
                  <TextBlock Text="個別技能" Style="{StaticResource H1}" VerticalAlignment="Center" Margin="0,0,10,0"/>
                  <Button x:Name="BtnBaPick" Content="從王的清單挑…"/>
                  <Button x:Name="BtnBaAdd" Content="自己打技能 id" Margin="8,0,0,0"/>
                  <Button x:Name="BtnBaImport" Content="從 log 匯入" Margin="8,0,0,0"/>
                  <Button x:Name="BtnBaClear" Content="全部清空" Margin="8,0,0,0"/>
                </StackPanel>
                <Border Background="#0C1E31" BorderBrush="#2A3448" BorderThickness="1" CornerRadius="6" Padding="8">
                  <ScrollViewer MaxHeight="220" VerticalScrollBarVisibility="Auto">
                    <StackPanel x:Name="BaList"/>
                  </ScrollViewer>
                </Border>
                <TextBlock x:Name="LblBaEmpty" Style="{StaticResource Hint}" TextWrapping="Wrap" Margin="0,6,0,0"
                           Text="‧還沒有任何規則。按上面的「從王的清單挑…」→ 左邊點一隻王 → 右邊【勾】技能(或按「全勾這隻王」)→ 按「加入清單」。不用自己打英文。"/>

                <Separator Margin="0,12,0,10" Background="#2A3448"/>
                <StackPanel Orientation="Horizontal">
                  <CheckBox x:Name="ChkBaDiag" Content="收集模式:打王時把看到的技能名稱記進 log" VerticalAlignment="Center"/>
                  <Button x:Name="BtnBaSounds" Content="開啟音效資料夾" Margin="16,0,0,0"/>
                </StackPanel>
                <TextBlock Style="{StaticResource Hint}" TextWrapping="Wrap" Margin="26,4,0,0"
                           Text="‧不知道要填哪些技能?勾「收集模式」→ 去打一場王 → 回來按「從 log 匯入」,偵測到的技能會自動列出來,你只要挑音效就好。收集完記得把它取消。"/>
                <TextBlock Style="{StaticResource Hint}" TextWrapping="Wrap" Margin="26,2,0,0"
                           Text="‧音效檔放在 BepInEx\plugins\SpiritZh_sounds\(wav / mp3,不支援 ogg)。安裝包附了三個現成的。"/>
              </StackPanel>
            </Border>
            <Border Style="{StaticResource CardBox}">
              <StackPanel>
                <StackPanel Orientation="Horizontal" Margin="0,0,0,6">
                  <TextBlock Style="{StaticResource Ico}" Text="&#xE7C1;"/>
                  <TextBlock Text="王方位箭頭" Style="{StaticResource H1}"/>
                  <TextBlock Text="(繞著你角色一圈的箭頭,指向附近的王;越遠越小越淡)" Style="{StaticResource Hint}"/>
                </StackPanel>
                <CheckBox x:Name="ChkArrowOn" Content="顯示王方位箭頭"/>
                <CheckBox x:Name="ChkArrowMini" Content="精英怪(MiniBoss)也指(預設只指真正的王 —— 精英多的圖會亂成一團)" Margin="0,4,0,0"/>
                <WrapPanel Margin="0,10,0,0">
                  <TextBlock Text="樣式:" VerticalAlignment="Center" Margin="0,0,6,0"/>
                  <ComboBox x:Name="CboArrowImg" Width="150" Margin="0,0,12,0">
                    <ComboBoxItem Content="經典" Tag="boss_arrow.png"/>
                    <ComboBoxItem Content="單尖 ˄" Tag="arrow_chevron.png"/>
                    <ComboBoxItem Content="雙尖" Tag="arrow_chevron2.png"/>
                    <ComboBoxItem Content="三尖" Tag="arrow_chevron3.png"/>
                    <ComboBoxItem Content="飛鏢" Tag="arrow_dart.png"/>
                    <ComboBoxItem Content="三角" Tag="arrow_triangle.png"/>
                    <ComboBoxItem Content="空心" Tag="arrow_outline.png"/>
                    <ComboBoxItem Content="圓環" Tag="arrow_ring.png"/>
                    <ComboBoxItem Content="游標" Tag="arrow_pointer.png"/>
                    <ComboBoxItem Content="自己的圖…" Tag="?"/>
                  </ComboBox>
                  <TextBlock Text="顏色:" VerticalAlignment="Center" Margin="0,0,6,0"/>
                  <Button x:Name="BArrowColor" Content="#FF6B59" Width="110" Margin="0,0,12,0"/>
                  <TextBlock Text="大小:" VerticalAlignment="Center" Margin="0,0,6,0"/>
                  <TextBox x:Name="TArrowSize" Width="62" Margin="0,0,12,0"/>
                  <TextBlock Text="離角色距離:" VerticalAlignment="Center" Margin="0,0,6,0"/>
                  <TextBox x:Name="TArrowRad" Width="62" Margin="0,0,4,0"/>
                  <TextBlock Text="px" Style="{StaticResource Hint}" Margin="0,0,12,0"/>
                </WrapPanel>
                <WrapPanel Margin="0,8,0,0">
                  <TextBlock Text="最多同時指:" VerticalAlignment="Center" Margin="0,0,6,0"/>
                  <ComboBox x:Name="CboArrowMax" Width="64" Margin="0,0,12,0">
                    <ComboBoxItem Content="1"/><ComboBoxItem Content="2"/><ComboBoxItem Content="3"/><ComboBoxItem Content="4"/>
                  </ComboBox>
                  <TextBlock Text="隻;超過" VerticalAlignment="Center" Margin="0,0,6,0"/>
                  <TextBox x:Name="TArrowFar" Width="56" Margin="0,0,4,0"/>
                  <TextBlock Text="公尺就不畫(0 = 不限)" Style="{StaticResource Hint}" Margin="0,0,12,0"/>
                  <TextBlock x:Name="LblArrowImg" Style="{StaticResource Hint}" VerticalAlignment="Center"/>
                </WrapPanel>
                <TextBlock Style="{StaticResource Hint}" TextWrapping="Wrap" Margin="0,10,0,0"
                           Text="‧★ 先講清楚它做不到什麼:王【沒出現在你附近】時,你的電腦上根本沒有那隻王的資料,箭頭指不出來 —— 這不是壞掉,是外掛不跟伺服器多要任何資料的必然結果。它能幫你的是「王在附近但被地形/人群擋住」,不是拿來當雷達找王。"/>
                <TextBlock Style="{StaticResource Hint}" TextWrapping="Wrap" Margin="0,2,0,0"
                           Text="‧自己的圖:白色 + 透明背景的 PNG,箭頭朝上,放進 BepInEx\plugins\SpiritZh_ui\ 再選「自己的圖…」。顏色會用上面的顏色去染。"/>
              </StackPanel>
            </Border>
          </StackPanel>
        </ScrollViewer>
      </TabItem>
      <TabItem x:Name="TabCustom">
        <TabItem.Header>
          <StackPanel Orientation="Horizontal">
            <TextBlock Text="&#xE713;" FontFamily="Segoe MDL2 Assets" FontSize="15" Margin="0,0,7,0" VerticalAlignment="Center"/>
            <TextBlock Text="自訂" FontSize="14.5" VerticalAlignment="Center"/>
          </StackPanel>
        </TabItem.Header>
        <ScrollViewer VerticalScrollBarVisibility="Auto" Padding="0,10,6,0">
          <Grid>
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="*"/><ColumnDefinition Width="340"/>
            </Grid.ColumnDefinitions>
            <StackPanel Grid.Column="0" Margin="0,0,14,0">
              <Border Style="{StaticResource CardBox}">
                <StackPanel>
                  <StackPanel Orientation="Horizontal" Margin="0,0,0,4">
                    <TextBlock Style="{StaticResource Ico}" Text="&#xE8D2;"/>
                    <TextBlock Text="自訂翻譯" Style="{StaticResource H1}"/>
                    <TextBlock Text="(把譯文改成你喜歡的說法;更新翻譯包不會蓋掉這裡)" Style="{StaticResource Hint}"/>
                  </StackPanel>
                  <TextBlock Style="{StaticResource Hint}" Margin="0,0,0,8" TextWrapping="Wrap"
                             Text="這裡的規則【優先於】內建字典。「句中也換」= 句子裡出現就換(HP: 120 → 生命值: 120);不勾 = 整格剛好等於原文才換。"/>
                  <DockPanel>
                    <StackPanel DockPanel.Dock="Right" Margin="10,0,0,0" Width="130">
                      <Button x:Name="BCuDel" Content="刪除選取" Margin="0,0,8,8"/>
                      <Button x:Name="BCuPreset" Content="常用範例…" Margin="0,0,8,0"/>
                    </StackPanel>
                    <ListBox x:Name="LstCustom" Height="170" Background="#101827" Foreground="#E6EBF2" BorderBrush="#33405A"/>
                  </DockPanel>
                  <TextBlock x:Name="LblCuCount" Style="{StaticResource Hint}" Margin="0,6,0,8"/>
                  <WrapPanel>
                    <TextBlock Text="原文:" VerticalAlignment="Center" Margin="0,0,6,0"/>
                    <TextBox x:Name="TCuSrc" Width="150" Margin="0,0,12,0"/>
                    <TextBlock Text="譯文:" VerticalAlignment="Center" Margin="0,0,6,0"/>
                    <TextBox x:Name="TCuDst" Width="150" Margin="0,0,12,0"/>
                    <CheckBox x:Name="ChkCuWord" Content="句中也換" VerticalAlignment="Center" Margin="0,0,12,0" IsChecked="True"/>
                    <Button x:Name="BCuAdd" Content="加入 / 更新" Width="116"/>
                  </WrapPanel>
                  <TextBlock Style="{StaticResource Hint}" Margin="0,8,0,0" TextWrapping="Wrap"
                             Text="‧點清單裡的項目會把它填回上面,改完再按「加入 / 更新」就是修改。&#10;‧同一個原文只會留一條。太短的原文要小心誤傷(~MP 也會動到 MP Regen)—— 把長的也寫一條就好,長的自動優先。"/>
                </StackPanel>
              </Border>

              <Border x:Name="CardMusic" Style="{StaticResource CardBox}">
                <StackPanel>
                  <StackPanel Orientation="Horizontal" Margin="0,0,0,4">
                    <TextBlock Style="{StaticResource Ico}" Text="&#xE8D6;"/>
                    <TextBlock Text="自訂地圖背景音樂" Style="{StaticResource H1}"/>
                    <TextBlock Text="(走遊戲自己的音樂播放器,遊戲的音樂音量與靜音照常生效)" Style="{StaticResource Hint}"/>
                  </StackPanel>
                  <WrapPanel>
                    <CheckBox x:Name="ChkMusicOn" Content="啟用(沒指定的地圖照放遊戲原曲)" VerticalAlignment="Center" Margin="0,0,20,0"/>
                    <TextBlock Text="音量倍率:" VerticalAlignment="Center" Margin="0,0,6,0"/>
                    <TextBox x:Name="TMuVol" Width="70" Margin="0,0,6,0"/>
                    <TextBlock Text="(0~1;在遊戲音樂音量之上再乘一次)" Style="{StaticResource Hint}" VerticalAlignment="Center"/>
                  </WrapPanel>
                  <DockPanel Margin="0,10,0,0">
                    <StackPanel DockPanel.Dock="Right" Margin="10,0,0,0" Width="130">
                      <Button x:Name="BMuDel" Content="移除選取" Margin="0,0,8,8"/>
                      <Button x:Name="BMuFolder" Content="開啟資料夾" Margin="0,0,8,0"/>
                    </StackPanel>
                    <ListBox x:Name="LstMusic" Height="150" Background="#101827" Foreground="#E6EBF2" BorderBrush="#33405A"/>
                  </DockPanel>
                  <TextBlock x:Name="LblMuCount" Style="{StaticResource Hint}" Margin="0,6,0,8"/>
                  <WrapPanel>
                    <TextBlock Text="地圖:" VerticalAlignment="Center" Margin="0,0,6,0"/>
                    <ComboBox x:Name="CboMuMap" Width="250" Margin="0,0,14,0"/>
                    <TextBlock Text="音樂:" VerticalAlignment="Center" Margin="0,0,6,0"/>
                    <TextBox x:Name="TMuFile" Width="220" Margin="0,0,8,0"/>
                    <Button x:Name="BMuBrowse" Content="瀏覽…" Width="86" Margin="0,0,8,0"/>
                    <Button x:Name="BMuSet" Content="設定這張圖" Width="120"/>
                  </WrapPanel>
                  <TextBlock Style="{StaticResource Hint}" Margin="0,8,0,0" TextWrapping="Wrap"
                             Text="支援 mp3 / wav(ogg 不支援 —— 播放走 Windows 內建解碼,請先轉檔)。從外面挑的檔會自動複製進 SpiritZh_music\ 資料夾,之後你把原檔刪了也不影響。"/>
                </StackPanel>
              </Border>
            </StackPanel>

            <StackPanel Grid.Column="1">
              <Border Style="{StaticResource CardBox}">
                <StackPanel>
                  <StackPanel Orientation="Horizontal" Margin="0,0,0,8">
                    <TextBlock Style="{StaticResource Ico}" Text="&#xE946;"/>
                    <TextBlock Text="自訂翻譯怎麼寫" Style="{StaticResource H1}"/>
                  </StackPanel>
                  <TextBlock Style="{StaticResource Hint}" TextWrapping="Wrap"
                             Text="【整格】原文 Attack → 攻擊力&#10;  「Attack」這一格會變,「Attack: 120」不會。&#10;&#10;【句中也換】原文 HP → 生命值&#10;  「HP: 120」「Max HP」都會變。&#10;&#10;不確定就先用「句中也換」,適用範圍比較廣。&#10;&#10;想把某個詞改回英文也可以 —— 原文填中文、譯文填英文。"/>
                </StackPanel>
              </Border>
              <Border x:Name="CardMusicHelp" Style="{StaticResource CardBox}">
                <StackPanel>
                  <StackPanel Orientation="Horizontal" Margin="0,0,0,8">
                    <TextBlock Style="{StaticResource Ico}" Text="&#xE8B7;"/>
                    <TextBlock Text="地圖音樂" Style="{StaticResource H1}"/>
                  </StackPanel>
                  <TextBlock Style="{StaticResource Hint}" TextWrapping="Wrap"
                             Text="‧音樂檔放在 BepInEx\plugins\SpiritZh_music\&#10;‧會自動循環播放,切到背景也跟著暫停&#10;‧沒設定的地圖完全不介入&#10;‧地圖清單是外掛跑過遊戲後產生的;新地圖沒出現就進遊戲逛一圈再開這裡"/>
                </StackPanel>
              </Border>
              <Border x:Name="CardMore" Style="{StaticResource CardBox}">
                <StackPanel>
                  <StackPanel Orientation="Horizontal" Margin="0,0,0,8">
                    <TextBlock Style="{StaticResource Ico}" Text="&#xE713;"/>
                    <TextBlock Text="更多" Style="{StaticResource H1}"/>
                  </StackPanel>
                  <TextBlock Style="{StaticResource Hint}" TextWrapping="Wrap"
                             Text="‧分享 / 匯入掉寶音效設定:在「掉落音效」頁的「音效檔」區。&#10;‧移除翻譯:在「功能自選」頁最下面。&#10;‧回報問題用的診斷開關:在「關於」頁。&#10;‧舊的「進階設定」視窗已經整個併進來了,不再需要另開一支程式。"/>
                </StackPanel>
              </Border>
            </StackPanel>
          </Grid>
        </ScrollViewer>
      </TabItem>

      <!-- ═ 游標 ═ -->
      <TabItem x:Name="TabCursor">
        <TabItem.Header>
          <StackPanel Orientation="Horizontal">
            <TextBlock Text="&#xE962;" FontFamily="Segoe MDL2 Assets" FontSize="15" Margin="0,0,7,0" VerticalAlignment="Center"/>
            <TextBlock Text="游標" FontSize="14.5" VerticalAlignment="Center"/>
          </StackPanel>
        </TabItem.Header>
        <ScrollViewer VerticalScrollBarVisibility="Auto" Padding="0,10,6,0">
          <StackPanel MaxWidth="1000" HorizontalAlignment="Left">

            <Border Style="{StaticResource CardBox}">
              <StackPanel>
                <StackPanel Orientation="Horizontal" Margin="0,0,0,6">
                  <TextBlock Text="&#xE962;" Style="{StaticResource Ico}"/>
                  <TextBlock Text="滑鼠游標放大" Style="{StaticResource H1}"/>
                  <TextBlock Text="(改完按下方「套用設定」,遊戲內 5 秒生效)" Style="{StaticResource Hint}"/>
                </StackPanel>
                <CheckBox x:Name="ChkCurOn" Content="把滑鼠游標換成比較大、比較好找的(純視覺,不改點擊位置)"/>
                <TextBlock Style="{StaticResource Hint}" Text="‧不勾 = 完全不動游標。"/>
                <TextBlock Style="{StaticResource Hint}" Text="‧【先試這個】遊戲設定 → General 裡本來就有幾個游標可以換,夠用的話就不必開這裡。"/>
                <TextBlock Style="{StaticResource Hint}" TextWrapping="Wrap" Text="‧⚠ 勾了之後,遊戲設定 → General 選的游標會【看起來沒作用】—— 畫面上被這裡蓋過去了。你的選擇沒有被改掉,取消勾選就會變回你選的那個。"/>
              </StackPanel>
            </Border>

            <Border Style="{StaticResource CardBox}">
              <StackPanel>
                <StackPanel Orientation="Horizontal" Margin="0,0,0,6">
                  <TextBlock Text="&#xE740;" Style="{StaticResource Ico}"/>
                  <TextBlock Text="游標樣式與大小" Style="{StaticResource H1}"/>
                  <TextBlock Text="(點一個樣式;內建圖只有這五種尺寸,不是無段縮放)" Style="{StaticResource Hint}"/>
                </StackPanel>
                <ListBox x:Name="LstCurStyle" Background="Transparent" BorderThickness="0" Padding="0" Margin="0,0,0,8"
                         ScrollViewer.HorizontalScrollBarVisibility="Disabled" ScrollViewer.VerticalScrollBarVisibility="Disabled">
                  <ListBox.ItemsPanel><ItemsPanelTemplate><WrapPanel/></ItemsPanelTemplate></ListBox.ItemsPanel>
                  <ListBox.ItemContainerStyle>
                    <Style TargetType="ListBoxItem">
                      <Setter Property="Margin" Value="0,0,6,6"/>
                      <Setter Property="Padding" Value="0"/>
                      <Setter Property="Cursor" Value="Hand"/>
                      <Setter Property="Template">
                        <Setter.Value>
                          <ControlTemplate TargetType="ListBoxItem">
                            <Border x:Name="Bd" Background="#101827" BorderBrush="#33405A" BorderThickness="1" CornerRadius="7" Padding="6,6,6,3">
                              <ContentPresenter/>
                            </Border>
                            <ControlTemplate.Triggers>
                              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Bd" Property="BorderBrush" Value="#5A7CA8"/></Trigger>
                              <Trigger Property="IsSelected" Value="True">
                                <Setter TargetName="Bd" Property="Background" Value="#1B3556"/>
                                <Setter TargetName="Bd" Property="BorderBrush" Value="#4FC3F7"/>
                                <Setter TargetName="Bd" Property="BorderThickness" Value="2"/>
                              </Trigger>
                            </ControlTemplate.Triggers>
                          </ControlTemplate>
                        </Setter.Value>
                      </Setter>
                    </Style>
                  </ListBox.ItemContainerStyle>
                </ListBox>
                <TextBlock x:Name="LblCurStyleLock" Style="{StaticResource Hint}" TextWrapping="Wrap" Visibility="Collapsed" Foreground="#7C93AD" Text="※ 你選了自訂圖,上面的樣式不會作用 —— 按「清除」就回到內建樣式。"/>
                <WrapPanel Margin="0,2,0,8">
                  <CheckBox x:Name="ChkCurAnim" Content="特效動畫(星芒閃爍、光環繞圈、火舌搖曳…;經典箭頭沒有特效所以不會動)" VerticalAlignment="Center"/>
                  <TextBlock Text="速度:" VerticalAlignment="Center" Margin="14,0,6,0"/>
                  <ComboBox x:Name="CboCurAnimSpd" Width="150" SelectedIndex="1">
                    <ComboBoxItem Content="慢(6 格/秒)" Tag="6"/>
                    <ComboBoxItem Content="普通(10 格/秒)" Tag="10"/>
                    <ComboBoxItem Content="快(15 格/秒)" Tag="15"/>
                  </ComboBox>
                </WrapPanel>
                <TextBlock Style="{StaticResource Hint}" TextWrapping="Wrap" Text="‧動畫 = 每隔一小段時間換一張圖(速度可選),箭頭本體不動、只有旁邊的特效在動。下面的預覽圖會跟著動。如果遊戲裡游標會閃,把這個取消。"/>
                <ComboBox x:Name="CboCurSize" Width="260" HorizontalAlignment="Left" SelectedIndex="2">
                  <ComboBoxItem Content="32 × 32(原本大小)"/>
                  <ComboBoxItem Content="48 × 48(1.5 倍)"/>
                  <ComboBoxItem Content="64 × 64(2 倍,建議)"/>
                  <ComboBoxItem Content="96 × 96(3 倍)"/>
                  <ComboBoxItem Content="128 × 128(4 倍,很大)"/>
                </ComboBox>
                <TextBlock Style="{StaticResource Hint}" TextWrapping="Wrap" Text="‧64 是建議值 —— 96 和 128 打王時會蓋住怪物血條和地上的圈,而且不少電腦畫不出這麼大的系統游標。"/>
                <TextBlock x:Name="LblCurBig" Style="{StaticResource Hint}" TextWrapping="Wrap" Visibility="Collapsed" Foreground="#FFB020" Text="⚠ 這個尺寸不少電腦畫不出來。套用後如果游標沒變大,到下面把「改用遊戲自己畫游標」勾起來。"/>
                <TextBlock x:Name="LblCurLock" Style="{StaticResource Hint}" TextWrapping="Wrap" Visibility="Collapsed" Foreground="#7C93AD" Text="※ 你選了自訂圖,所以這裡的大小不會作用 —— 自訂圖一律照原尺寸顯示。"/>
              </StackPanel>
            </Border>

            <Border Style="{StaticResource CardBox}">
              <StackPanel>
                <StackPanel Orientation="Horizontal" Margin="0,0,0,6">
                  <TextBlock Text="&#xEB9F;" Style="{StaticResource Ico}"/>
                  <TextBlock Text="換成自己的圖" Style="{StaticResource H1}"/>
                  <TextBlock Text="(選填;PNG,大小請自己在繪圖軟體調好)" Style="{StaticResource Hint}"/>
                </StackPanel>
                <StackPanel Orientation="Horizontal">
                  <TextBox x:Name="TxtCurImg" Width="330" IsReadOnly="True" VerticalAlignment="Center"/>
                  <Button x:Name="BtnCurPick" Content="選圖片…" Margin="8,0,0,0"/>
                  <Button x:Name="BtnCurClear" Content="清除(用內建箭頭)" Margin="8,0,0,0"/>
                </StackPanel>
                <StackPanel Orientation="Horizontal" Margin="0,10,0,0">
                  <Border Background="#0C1E31" BorderBrush="#2A6C93" BorderThickness="1" CornerRadius="6" Padding="10" VerticalAlignment="Top">
                    <Image x:Name="ImgCurPrev" Width="128" Height="128" Stretch="None"
                           RenderOptions.BitmapScalingMode="NearestNeighbor"/>
                  </Border>
                  <StackPanel Margin="12,0,0,0" VerticalAlignment="Top">
                    <TextBlock x:Name="LblCurPrev" Style="{StaticResource Hint}" Text="(還沒選圖)"/>
                    <TextBlock Text="真正的點擊位置(這張圖上的哪一個點才算「你點到的地方」)" Style="{StaticResource Hint}" Margin="0,8,0,2"/>
                    <WrapPanel>
                      <TextBlock Text="X" VerticalAlignment="Center" Margin="0,0,6,0"/>
                      <TextBox x:Name="TCurHotX" Width="70"/>
                      <TextBlock Text="Y" VerticalAlignment="Center" Margin="12,0,6,0"/>
                      <TextBox x:Name="TCurHotY" Width="70"/>
                      <Button x:Name="BtnCurTL" Content="設在左上角(箭頭類)" Margin="12,0,0,0"/>
                      <Button x:Name="BtnCurCenter" Content="設在正中央(準星類)" Margin="8,0,0,0"/>
                    </WrapPanel>
                    <TextBlock x:Name="LblCurHotWarn" Style="{StaticResource Hint}" TextWrapping="Wrap" Visibility="Collapsed" Foreground="#FFB020" Text="⚠ 這個位置超出圖片範圍了,游標會歪掉。"/>
                    <TextBlock x:Name="LblCurHotAuto" Style="{StaticResource Hint}" TextWrapping="Wrap" Foreground="#7C93AD" Text="※ 內建樣式的點擊位置由外掛自動決定(箭頭=尖端、準星=正中央),這兩格只對自訂圖有效。"/>
                  </StackPanel>
                </StackPanel>
                <TextBlock Style="{StaticResource Hint}" TextWrapping="Wrap" Margin="0,8,0,0" Text="‧從別的地方選的圖會自動複製一份到 BepInEx\plugins\SpiritZh_ui\ —— 外掛只認那個資料夾。"/>
              </StackPanel>
            </Border>

            <Border Style="{StaticResource CardBox}">
              <StackPanel>
                <StackPanel Orientation="Horizontal" Margin="0,0,0,6">
                  <TextBlock Text="&#xE9CE;" Style="{StaticResource Ico}"/>
                  <TextBlock Text="游標沒有變大?" Style="{StaticResource H1}"/>
                </StackPanel>
                <TextBlock Style="{StaticResource Hint}" Text="‧先照順序試:① 按過「套用設定」了嗎 ② 大小選到 96 / 128 了嗎 ③ 勾下面這個。"/>
                <CheckBox x:Name="ChkCurSoft" Content="改用遊戲自己畫游標(一定畫得出來,代價是移動時會慢半拍)" Margin="0,6,0,0"/>
                <TextBlock Style="{StaticResource Hint}" TextWrapping="Wrap" Text="‧⚠ 這個在人多的主城、8 人副本打王時最有感 —— 遊戲掉幀,游標會跟著卡。看得到但比較難用,自己權衡。"/>
                <CheckBox x:Name="ChkCurReapply" Content="游標偶爾會自己變回原本的 → 勾這個持續修正" Margin="0,10,0,0"/>
                <TextBlock Style="{StaticResource Hint}" TextWrapping="Wrap" Text="‧遊戲切換畫面時可能把游標設回它自己的,勾了就每 2 秒修正一次(成本可以忽略)。如果發現拖曳物品的手勢游標會閃回箭頭,把這個取消。"/>
                <TextBlock Style="{StaticResource Hint}" TextWrapping="Wrap" Margin="0,8,0,0" Text="‧勾了還是沒變 = 圖檔沒被讀到。按最上方「設定健檢」旁邊的「重新檢查」,它會直接告訴你圖檔在不在。"/>
              </StackPanel>
            </Border>

          </StackPanel>
        </ScrollViewer>
      </TabItem>

      <!-- ═ 關於 ═ -->
      <TabItem x:Name="TabAbout">
        <TabItem.Header>
          <StackPanel Orientation="Horizontal">
            <TextBlock Text="&#xE946;" FontFamily="Segoe MDL2 Assets" FontSize="15" Margin="0,0,7,0" VerticalAlignment="Center"/>
            <TextBlock Text="關於" FontSize="14.5" VerticalAlignment="Center"/>
          </StackPanel>
        </TabItem.Header>
        <ScrollViewer VerticalScrollBarVisibility="Auto" Padding="0,10,6,0">
          <StackPanel MaxWidth="1000" HorizontalAlignment="Left">
            <Border Style="{StaticResource CardBox}">
              <StackPanel>
                <TextBlock x:Name="LblAbout" Style="{StaticResource H1}" Margin="0,0,0,8"/>
                <TextBlock Style="{StaticResource Hint}" Text="非官方翻譯;純顯示層,不修改任何遊戲檔案。所有腳本皆為明文,可用記事本檢視。完全免費分享,禁止轉售;轉載請註明出處。"/>
              </StackPanel>
            </Border>
            <Border x:Name="CardUpdate" Style="{StaticResource CardBox}">
              <StackPanel>
                <StackPanel Orientation="Horizontal" Margin="0,0,0,6">
                  <TextBlock Style="{StaticResource Ico}" Text="&#xE895;"/>
                  <TextBlock Text="檢查更新" Style="{StaticResource H1}"/>
                  <TextBlock Text="(只連我的 GitHub 讀版本號,不會傳你的任何資料)" Style="{StaticResource Hint}"/>
                </StackPanel>
                <WrapPanel>
                  <Button x:Name="BtnUpdCheck" Content="立即檢查" Width="110" Margin="0,0,10,0"/>
                  <TextBlock Text="啟動時:" VerticalAlignment="Center" Margin="4,0,6,0"/>
                  <ComboBox x:Name="CboUpdMode" Width="230" VerticalAlignment="Center">
                    <ComboBoxItem Content="只通知我有新版(預設)"/>
                    <ComboBoxItem Content="自動下載,下載完再問我要不要裝"/>
                    <ComboBoxItem Content="不要檢查更新"/>
                  </ComboBox>
                </WrapPanel>
                <TextBlock x:Name="LblUpdState" Style="{StaticResource Hint}" TextWrapping="Wrap" Margin="0,8,0,0" Text="尚未檢查。"/>
                <TextBlock Style="{StaticResource Hint}" TextWrapping="Wrap" Margin="0,6,0,0"
                           Text="‧下載回來的安裝包會【驗證數位簽章與 SHA256】才會給你安裝 —— 即使我的 GitHub 帳號被盜,對方沒有我的私鑰也偽造不出能通過驗證的更新檔。&#10;‧不會自動覆蓋你的遊戲:下載完只會提示你「關掉遊戲後按安裝」,設定檔一律保留。"/>
              </StackPanel>
            </Border>
            <Border x:Name="CardCompat" Style="{StaticResource CardBox}">
              <StackPanel>
                <TextBlock Text="已知的外掛相容性" Style="{StaticResource H1}" Margin="0,0,0,8"/>
                <TextBlock Style="{StaticResource Hint}" Margin="0,0,0,6"
                           Text="‧【Loot Beams】設定面板預設 F5,與本外掛「帶入進階濾鏡」熱鍵可能相同 —— 到「傷害統計與熱鍵」頁改掉或留空(預設就是空的)。"/>
                <TextBlock Style="{StaticResource Hint}"
                           Text="‧【Loot Beams】會銷毀被它過濾的光柱特效,本外掛的光柱染色會時有時無 —— 兩邊的光柱功能建議只開一邊。"/>
              </StackPanel>
            </Border>
            <Border x:Name="CardDiag" Style="{StaticResource CardBox}">
              <StackPanel>
                <StackPanel Orientation="Horizontal" Margin="0,0,0,6">
                  <TextBlock Style="{StaticResource Ico}" Text="&#xE9D9;"/>
                  <TextBlock Text="回報問題用的診斷開關" Style="{StaticResource H1}"/>
                  <TextBlock Text="(全部唯讀,只會多印 log;查完請關掉)" Style="{StaticResource Hint}"/>
                </StackPanel>
                <TextBlock Text="外掛 log 診斷" Style="{StaticResource Hint}" Margin="0,0,0,4"/>
                <WrapPanel>
                  <CheckBox x:Name="ChkDgView" Content="隱藏玩家 / 身分判定" Margin="0,0,16,6"/>
                  <CheckBox x:Name="ChkDgSfx" Content="音效漏擋(座標名冊)" Margin="0,0,16,6"/>
                  <CheckBox x:Name="ChkDgZero" Content="「0」彈字來源" Margin="0,0,16,6"/>
                  <CheckBox x:Name="ChkDgSearch" Content="背包搜尋時序(物品閃一下消失時)" Margin="0,0,16,6"/>
                  <CheckBox x:Name="ChkDgArrow" Content="王方位掃描 / 相機" Margin="0,0,16,6"/>
                  <CheckBox x:Name="ChkAudDiag" Content="掉落來源結構(音效沒反應時)" Margin="0,0,16,6"/>
                  <CheckBox x:Name="ChkBeamDiag" Content="光柱處理過程(顏色沒變時)" Margin="0,0,16,6"/>
                  <CheckBox x:Name="ChkQDiag" Content="詞條 roll 值範圍(寫進 status.txt)" Margin="0,0,16,6"/>
                </WrapPanel>
                <TextBlock Text="收集模式(跟各功能頁的那顆勾是同一個開關)" Style="{StaticResource Hint}" Margin="0,6,0,4"/>
                <WrapPanel>
                  <CheckBox x:Name="ChkDgBoss" Content="王技收集(打王時記技能名 → 「王」頁從 log 匯入)" Margin="0,0,16,6"/>
                  <CheckBox x:Name="ChkDgFxSkill" Content="技能代號收集(→ 「功能自選」頁從 log 匯入)" Margin="0,0,16,6"/>
                </WrapPanel>
                <WrapPanel Margin="0,4,0,0">
                  <TextBlock Text="追蹤翻譯(原文→譯文):" VerticalAlignment="Center" Margin="0,0,6,0"/>
                  <TextBox x:Name="TDgWatch" Width="300" Margin="0,0,6,0"/>
                  <TextBlock Text="填中文或英文,逗號分隔;留空 = 關" Style="{StaticResource Hint}"/>
                </WrapPanel>
                <TextBlock Style="{StaticResource Hint}" TextWrapping="Wrap" Margin="0,8,0,0"
                           Text="‧畫面上出現一個不知道從哪個英文翻來的中文時,把它填進「追蹤翻譯」,進遊戲讓它出現一次,log 的 [watch] 行會寫出原文與 UI 路徑。回報時附上 BepInEx\LogOutput.log。"/>
              </StackPanel>
            </Border>
            <Border x:Name="CardPriceNote" Style="{StaticResource CardBox}">
              <StackPanel>
                <TextBlock Text="關於「自動查市價」" Style="{StaticResource H1}" Margin="0,0,0,8"/>
                <TextBlock Style="{StaticResource Hint}"
                           Text="它是本外掛唯一會對伺服器產生流量的功能:呼叫遊戲自己的市場搜尋入口,送出內容與手動搜尋完全相同,並有嚴格節流。但它畢竟是自動觸發的,不保證絕無風險 —— 會擔心就到「詞條品質」頁把「自動查市價」取消勾選,其他功能完全不受影響。"/>
              </StackPanel>
            </Border>
          </StackPanel>
        </ScrollViewer>
      </TabItem>
    </TabControl>
  </DockPanel>
</Window>
'@

$window = [Windows.Markup.XamlReader]::Parse($xaml)
foreach ($n in @("LblStatus","LblVer","TxtPath","BtnBrowse","BtnTutorial","TabBoss","CboUiScale","BSndExport","BSndImport","LblFontPreview","BtnHealth","LblHealthTitle","LblHealthDesc","BarHealth","LblHealthLog","SvHealthLog","StepH1","StepH2","StepH3","StepH4","StepH5","BtnAll","BtnInv","BtnRst",
                 "ChipAll","ChipView","ChipPerf","ChipCd","ChipInst","CardView","CardPerf","CardCd","CardInst",
                 "ChkHide","ChkParty","ChkGuild","ChkFriend","ChkNum","ChkFx","ChkMute","ChkFull",
                 "ChkShadow","ChkAnim","ChkFxMine","ChkZero","ChkMapWrap","ChkBaseStatEn",
                 "CardChat","CboChatInvite","CardBuff","CboBuffPos","TBuffScale","TBuffX","TBuffY","TDebuffX","TDebuffY","TMainX","TMainY","ChkPartyBuff","TPartyBuffKey","CardFxSkill","ChkFxSkillOn","BFxSkillPick","BFxSkillImport","ChkFxSkillDiag","TFxSkill",
                 "CardDiag","ChkDgView","ChkDgSfx","ChkDgZero","ChkDgSearch","ChkDgArrow","TDgWatch","ChkDgBoss","ChkDgFxSkill",
                 "BtnCdMask","BtnCdText","TxtCdAlpha","TxtCdX","TxtCdY","TxtCdSize",
                 "BtnInstall","BtnDiag","BtnUninstall",
                 "TxtScale","CboUp","TxtSharp","TxtFps","CboVs","CboMsaa","ChkSplash","TxtVol",
                 "RbM1","RbM2","RbM3","RbM4","CboFont","BtnFontFile","LblFontNow","LblAbout",
                 "CardUpdate","BtnUpdCheck","CboUpdMode","LblUpdState",
                 "CardSerial","TxtMyId","BtnMyIdCopy","BtnMyIdRefresh","BtnMyIdReq","TxtSerial","BtnSerialApply","BtnSerialClear","BtnSerialAct","LblSerialState",
                 "KDpsKey","KDpsMode","KDpsReset","KDpsEdit","KToolKey","KMkKey","ChkMkAuto",
                 "ChkQOn","TQ神品","TQ珍品","TQ精品","TQ良品","BQC神品","BQC珍品","BQC精品","BQC良品","BQC凡品",
                 "CboQStyle","TQBlend","CboQName","ChkQTip","ChkQPrice","ChkQHist","TQHistDays","ChkMktPanel","ChkMktMark","TQTtl",
                 "ChkBaOn","ChkBaBanner","TBaVol","TBaCd","BtnBaAll","BtnBaAllClear",
                 "BtnBaPick","BtnBaAdd","BtnBaImport","BtnBaClear","BaList","LblBaEmpty","ChkBaDiag","BtnBaSounds",
                 "LstCurStyle","LblCurStyleLock","LblCurHotAuto","ChkCurAnim","CboCurAnimSpd","ChkArrowOn","ChkArrowMini","CboArrowImg","BArrowColor","TArrowSize","TArrowRad","CboArrowMax","TArrowFar","LblArrowImg",
                 "TQP神品","TQP珍品","TQP精品","BQP神品","BQP珍品","BQP精品","TQVol",
                 "BQFocus","BQFocusClr","LblQFocus","TQPanX","TQPanY","ChkQDiag",
                 "LstCustom","TCuSrc","TCuDst","ChkCuWord","BCuAdd","BCuDel","BCuPreset","LblCuCount",
                 "ChkMusicOn","TMuVol","LstMusic","CboMuMap","TMuFile","BMuBrowse","BMuSet","BMuDel","BMuFolder","LblMuCount",
                 "BAudPreset","TAudCool","ChkOwnOnly","ChkSkipLocked","CboFMode","ChkAudDiag",
                 "CboSndLegendary","CboSndPurple","CboSndUnique","CboSndRare","CboSndCommon","CboSndGreen",
                 "BSndLegendary","BSndPurple","BSndUnique","BSndRare","BSndCommon","BSndGreen",
                 "TVolLegendary","TVolPurple","TVolUnique","TVolRare","TVolCommon","TVolGreen",
                 "FEquip","FArtifact","FCard","FGem","FConsumable","FCosmetic","FJunk",
                 "RLegendary","RUnique","RRare","RCommon",
                 "BNameAdd","BNameDel","LstNames","LblNameCount","BMuteAdd","BMuteDel","LstMute","LblMuteCount",
                 "BSndFolder","BSndRefresh",
                 "ChkBeamOn","BBossCard","BBossEquip","BUniqueEq","BPurpleAll","BChance","TChance","BTestAll",
                 "CboMiss","TDim","HEquip","HArtifact","HCard","HGem","HJunk","HConsumable","HCosmetic","HKeepLeg",
                 "BItemAdd","BItemDel","LstItems","LblItemCount","CboNameMode","BNameColor","TScale","TRbSpeed","ChkBeamDiag",
                 "TDpsX","TDpsY","TDpsSize","TDpsBg","TDpsLine","BDpsColor","CDpsIcon",
                 "CboDpsSkin","BDpsFrame","BDpsFrameClr","BDpsFrameColor","CDpsTarget","CDpsZone","CDpsMonster",
                 "CboDpsMode","TDpsIdle","TDpsRows","TDpsRate","CDpsHp",
                 "BtnPrices","LblPriceStat",
                 "ChkCurOn","CboCurSize","LblCurBig","LblCurLock","TxtCurImg","BtnCurPick","BtnCurClear",
                 "ImgCurPrev","LblCurPrev","TCurHotX","TCurHotY","BtnCurTL","BtnCurCenter","LblCurHotWarn",
                 "ChkCurSoft","ChkCurReapply",
                 "LblSum1","LblSum2","LblSum3","LblSum4","BtnApply","BtnResetAll","Tabs",
                 "TabMain","TabTrans","TabSerial","TabAudio","TabBeam","TabQuality","TabDps","TabCustom","TabCursor","TabAbout",
                 "ChipBar","CardPerfParam","CardMusic","CardMusicHelp","CardMore","CardCompat","CardPriceNote","HintAdv")) {
    Set-Variable -Name $n -Value $window.FindName($n)
}

# ── 純翻譯包:只留 翻譯與字型 / 安裝 / 自訂翻譯 / 關於 ──────────────────────────────
# 邏輯層(Load-*/Save-*/Update-Summary/BtnResetAll/健檢)全部照跑:Collapsed 分頁裡的控制項 FindName 照樣找得到、
# 屬性可讀寫、事件照觸發(實測)。這裡只動 Visibility 與文案;寫檔的守門在 Do-Apply / BtnInstall / Save-Config。
if ($script:IsPure) {
    # 純翻譯包:序號對它沒有意義(GuildGateTick 在名單為空時就早退)→ 一併隱藏
    foreach ($t in @($TabAudio, $TabBeam, $TabQuality, $TabDps, $TabBoss, $TabCursor, $TabSerial)) { $t.Visibility = "Collapsed" }
    foreach ($c in @($ChipBar, $CardView, $CardPerf, $CardCd, $CardPerfParam,
                     $CardMusic, $CardMusicHelp, $CardMore, $HintAdv, $CardFxSkill, $CardChat, $CardBuff, $CardDiag,
                     $CardCompat, $CardPriceNote, $LblSum1, $LblSum2, $LblSum3)) { $c.Visibility = "Collapsed" }
    $Tabs.SelectedIndex = 0   # ★ TabControl 顯示時自動選 Items[0] 且【不會跳過 Collapsed 頁】;明確設一次
    # 功能自選頁只剩「安裝與維護」卡 → 分頁名改「安裝」
    try { foreach ($tb in $TabMain.Header.Children) { if ($tb -is [System.Windows.Controls.TextBlock] -and $tb.Text -eq "功能自選") { $tb.Text = "安裝" } } } catch {}
    $RbM4.Content = "原文 —— 完全不翻譯(對照或除錯時用)"
}

$window.Add_SourceInitialized({
    try {
        Add-Type -Name Dwm -Namespace SpiritZh -MemberDefinition '[DllImport("dwmapi.dll")] public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int val, int size);'
        $h = (New-Object System.Windows.Interop.WindowInteropHelper($window)).Handle
        $on = 1
        [SpiritZh.Dwm]::DwmSetWindowAttribute($h, 20, [ref]$on, 4) | Out-Null
        [SpiritZh.Dwm]::DwmSetWindowAttribute($h, 19, [ref]$on, 4) | Out-Null
    } catch {}
})

# ── 現值載入 ────────────────────────────────────────────────────────────────
function Refresh-Header {
    $TxtPath.Text = $(if ($script:GamePath) { $script:GamePath } else { "(找不到遊戲,請按「瀏覽」)" })
    $gameVer = Get-DllVer (Join-Path (PluginDir) "SpiritZh.dll")
    $gameEd = Get-DllEdition (Join-Path (PluginDir) "SpiritZh.dll")
    $edName = Edition-Name $ToolEdition
    $tabName = $(if ($script:IsPure) { "安裝" } else { "功能自選" })
    $window.Title = "SpiritVale 繁中化 設定工具 $ToolVer($edName)" + $(if ($gameVer) { "(遊戲內: $gameVer" + $(if ($gameVer -ne $ToolVer) { " ⚠未更新)" } else { ")" }) } else { "" }) + "  by 源"
    $LblVer.Text = $(if (-not $script:GamePath) { "尚未找到遊戲資料夾" }
                     elseif (-not $gameVer) { "尚未安裝翻譯 —— 請到「$tabName」按「安裝 / 更新翻譯」" }
                     elseif ($gameEd -eq "guild" -and $ToolEdition -ne "guild") { "⚠ 遊戲內是【公會專用版】,這個安裝包是【純翻譯包】—— 不要按安裝,那會關掉你的付費功能" }
                     elseif ($gameVer -ne $ToolVer) { "遊戲內是 $gameVer,安裝包是 $ToolVer —— 按「安裝 / 更新翻譯」升級" }
                     elseif ($gameEd -and $gameEd -ne $ToolEdition) { "遊戲內裝的是「" + (Edition-Name $gameEd) + "」,這個安裝包是「$edName」—— 按「安裝 / 更新翻譯」換過來" }
                     else { "已安裝翻譯($gameVer,$edName),版本一致" })
    $LblAbout.Text = "SpiritVale 繁體中文化 $ToolVer($edName)   開發:源"
    Update-ApplyEnabled
}
# ★ 「套用設定」是畫面上最大那顆按鈕。以前沒安裝翻譯時按下去只有角落一行小灰字,
#   使用者按了最大那顆按鈕卻覺得「什麼都沒發生」—— 最傷信任的體驗。
#   改成【按下去之前就講】:條件不成立時按鈕變灰 + 滑鼠提示說明原因。
function Update-ApplyEnabled {
    # ★★ v3.76.12:這裡本來是【裸 elseif】(前面沒有 if)——
    #   PowerShell 把 elseif 當成指令名,執行期直接丟 CommandNotFoundException,
    #   函式在第一行就中止 → 下面的 BtnApply.IsEnabled / ToolTip 從來沒有執行過,
    #   也就是說「按鈕變灰 + 提示原因」這個功能【從上線以來都是壞的】。
    #   而 PowerShell 的 Parser 不會把它判成語法錯誤,所以語法檢查一路綠燈,查不出來。
    $why = ""
    if (-not $script:GamePath) { $why = "還沒找到遊戲資料夾 —— 請先按上方的「瀏覽」。" }
    elseif (-not (Test-Path -LiteralPath (PluginDir))) { $why = "還沒安裝翻譯 —— 請先按「安裝 / 更新翻譯」。設定要有地方寫才存得起來。" }
    try {
        $BtnApply.IsEnabled = ($why -eq "")
        $BtnApply.ToolTip = $(if ($why -eq "") { "把畫面上的設定寫進設定檔(遊戲內約 5 秒生效)" } else { $why })
    } catch {}
}
$script:cdMask = ""; $script:cdText = ""
$DEFAULT_FONT = "遊戲預設(不改字型)"
$script:fontFilePath = ""
# ══════════════════════════════════════════════════════════════════════
#  滑鼠游標(SpiritZh_cursor.txt)—— v3.73
# ══════════════════════════════════════════════════════════════════════
# 外掛端只認 BepInEx\plugins\SpiritZh_ui\ 裡的檔名(CursorTex 寫死了那個資料夾),
# 所以從別處挑的圖一定要複製進去,不然玩家會遇到「設了但游標沒變」。
# scale 只有五張實體圖(32/48/64/96/128),下拉直接對應,不做無段滑桿 ——
# 讓人填 2.7 卻拿到 96px 是最難解釋的那種 bug。
$script:CUR_SIZES = @(32, 48, 64, 96, 128)
$script:CUR_SCALES = @(1.0, 1.5, 2.0, 3.0, 4.0)
$script:curImg = ""
$script:curStyle = ""     # "" = 經典(cursor_<size>.png);其餘 = cursor_<style>_<size>.png(要跟外掛 CUR_STYLES 一致)
$script:curReapplyMs = 2000
$script:CUR_STYLES = @(
    @{ k = "";         n = "經典" },
    @{ k = "silver";   n = "銀鉻" },
    @{ k = "neon";     n = "霓虹藍" },
    @{ k = "ice";      n = "冰晶" },
    @{ k = "gold";     n = "黃金" },
    @{ k = "amethyst"; n = "紫晶" },
    @{ k = "fire";     n = "烈焰" },
    @{ k = "nature";   n = "翠葉" },
    @{ k = "rainbow";  n = "彩虹" },
    @{ k = "steel";    n = "黑鋼" },
    @{ k = "blood";    n = "血紅" },
    @{ k = "pixel";    n = "像素" },
    @{ k = "ring";     n = "準星" }
)
function CurStyleFile([string]$style, [int]$size) { if ($style) { "cursor_" + $style + "_" + $size + ".png" } else { "cursor_" + $size + ".png" } }
function Load-PngFile([string]$path) {
    # OnLoad + StreamSource:讀完就放開檔案(同 CurUpdatePreview 的注意事項)
    $bi = New-Object System.Windows.Media.Imaging.BitmapImage
    $bi.BeginInit()
    $bi.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
    $bi.StreamSource = New-Object System.IO.MemoryStream (,[System.IO.File]::ReadAllBytes($path))
    $bi.EndInit(); $bi.Freeze(); return $bi
}
function Build-CurStyleList {
    # 縮圖優先讀安裝包 payload(工具在 ZIP包 裡跑,一定有);沒有再退回遊戲資料夾
    $LstCurStyle.Items.Clear()
    $dirs = @()
    try { $dirs += (Join-Path $PSScriptRoot "payload\BepInEx\plugins\SpiritZh_ui") } catch {}
    $pd = PluginDir; if ($pd) { $dirs += (Join-Path $pd "SpiritZh_ui") }
    foreach ($st in $script:CUR_STYLES) {
        $sp = New-Object System.Windows.Controls.StackPanel
        $sp.Width = 74
        $im = New-Object System.Windows.Controls.Image
        $im.Width = 48; $im.Height = 48; $im.Stretch = "Uniform"
        [System.Windows.Media.RenderOptions]::SetBitmapScalingMode($im, [System.Windows.Media.BitmapScalingMode]::HighQuality)
        foreach ($d in $dirs) {
            $f = Join-Path $d (CurStyleFile $st.k 64)
            if (Test-Path -LiteralPath $f) { try { $im.Source = Load-PngFile $f; break } catch {} }
        }
        $tb = New-Object System.Windows.Controls.TextBlock
        $tb.Text = $st.n; $tb.FontSize = 12; $tb.HorizontalAlignment = "Center"; $tb.Margin = "0,3,0,0"
        $tb.Foreground = "#E6EBF2"
        [void]$sp.Children.Add($im); [void]$sp.Children.Add($tb)
        $sp.Tag = $st.k
        [void]$LstCurStyle.Items.Add($sp)
    }
}
$script:curAnimFrames = @(); $script:curAnimIdx = 0
$script:curAnimTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:curAnimTimer.Interval = [TimeSpan]::FromMilliseconds(100)
$script:curAnimTimer.Add_Tick({
    if ($script:curAnimFrames.Count -lt 2) { $script:curAnimTimer.Stop(); return }
    $script:curAnimIdx = ($script:curAnimIdx + 1) % $script:curAnimFrames.Count
    $ImgCurPrev.Source = $script:curAnimFrames[$script:curAnimIdx]
})
$script:curAnimFps = 10   # 手填的格率(例如 8)要記住,存檔時原值寫回,不被下拉量化成 6/10/15(同 reapply 的作法)
function CurAnimFps { return [int]$script:curAnimFps }
function CurSelectStyle([string]$k) {
    for ($i = 0; $i -lt $LstCurStyle.Items.Count; $i++) { if (([string]$LstCurStyle.Items[$i].Tag) -eq $k) { $LstCurStyle.SelectedIndex = $i; return } }
    $LstCurStyle.SelectedIndex = 0
}
function CurIdxFromScale([double]$sc) {
    # 對齊外掛的 CurPick():want = round(32 * scale),挑最接近的一張;平手取先到的(同 C# 的 d < bd)
    $want = [math]::Round(32.0 * $sc)
    $best = 0; $bd = [int]::MaxValue
    for ($i = 0; $i -lt $script:CUR_SIZES.Count; $i++) {
        $d = [math]::Abs($script:CUR_SIZES[$i] - $want)
        if ($d -lt $bd) { $bd = $d; $best = $i }
    }
    return $best
}
function CurUpdatePreview {
    $img = $script:curImg
    $custom = ($img -ne "")
    $file = $(if ($custom) { $img } else { CurStyleFile $script:curStyle $script:CUR_SIZES[[math]::Max(0, $CboCurSize.SelectedIndex)] })
    $TxtCurImg.Text = $(if ($custom) { $img } else { "(用內建樣式)" })
    # 內建樣式:熱點由外掛決定,欄位鎖住(同下面 CboCurSize 的作法:IsEnabled + Opacity 一起壓)
    foreach ($c in @($TCurHotX, $TCurHotY, $BtnCurTL, $BtnCurCenter)) { $c.IsEnabled = $custom; $c.Opacity = $(if ($custom) { 1.0 } else { 0.40 }) }
    $LblCurHotAuto.Visibility = $(if ($custom) { "Collapsed" } else { "Visible" })
    $LstCurStyle.IsEnabled = (-not $custom)
    $LstCurStyle.Opacity = $(if ($custom) { 0.40 } else { 1.0 })
    $LblCurStyleLock.Visibility = $(if ($custom) { "Visible" } else { "Collapsed" })
    # 自訂圖時大小卡片變灰。★ 只設 IsEnabled 不會變灰 —— 這個工具的 ControlTemplate 沒有
    #   IsEnabled 的 Trigger,點不下去但長得一模一樣,使用者只會覺得工具壞了。要同時壓 Opacity。
    $CboCurSize.IsEnabled = (-not $custom)
    $CboCurSize.Opacity = $(if ($custom) { 0.40 } else { 1.0 })
    $LblCurLock.Visibility = $(if ($custom) { "Visible" } else { "Collapsed" })
    $LblCurBig.Visibility = $(if ((-not $custom) -and $CboCurSize.SelectedIndex -ge 3) { "Visible" } else { "Collapsed" })
    $w = 0; $h = 0
    try {
        $pdir = PluginDir
        if (-not $pdir) { throw "先按上方「瀏覽」指定遊戲資料夾" }   # 1-9:先檢查再 Join-Path,不然印出來的是英文參數綁定錯誤
        $p = Join-Path (Join-Path $pdir "SpiritZh_ui") $file
        if (Test-Path -LiteralPath $p) {
            $bi = New-Object System.Windows.Media.Imaging.BitmapImage
            $bi.BeginInit()
            # ★ OnLoad + StreamSource:讀完就放開檔案,不然玩家覆蓋不了自己那張圖。
            #   ★★ 絕對不要加 BitmapCreateOptions.IgnoreImageCache —— 它的快取鍵就是 UriSource,
            #      配 StreamSource 會在 EndInit() 丟「Key cannot be null. Parameter name: key」。
            $bi.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
            $bytes = [System.IO.File]::ReadAllBytes($p)
            $bi.StreamSource = New-Object System.IO.MemoryStream (,$bytes)   # 逗號不能拿掉
            $bi.EndInit()
            $bi.Freeze()
            $ImgCurPrev.Source = $bi
            $w = $bi.PixelWidth; $h = $bi.PixelHeight
            $ImgCurPrev.Stretch = $(if ($w -gt 128 -or $h -gt 128) { "Uniform" } else { "None" })
            $LblCurPrev.Text = "$file — $w × $h 像素"
            # 動畫預覽:旁邊有 <名>_f0.png、_f1.png… 就輪播(跟外掛同一套命名)
            $script:curAnimTimer.Stop(); $script:curAnimFrames = @()
            if ($ChkCurAnim.IsChecked) {
                $base = $p.Substring(0, $p.Length - 4); $fr = @()
                for ($i = 0; $i -lt 32; $i++) {
                    $fp = "${base}_f$i.png"
                    if (-not (Test-Path -LiteralPath $fp)) { break }
                    try { $fr += (Load-PngFile $fp) } catch { break }
                }
                if ($fr.Count -ge 2) {
                    $script:curAnimFrames = $fr; $script:curAnimIdx = 0
                    $script:curAnimTimer.Interval = [TimeSpan]::FromMilliseconds([int](1000 / (CurAnimFps)))
                    $script:curAnimTimer.Start()
                    $LblCurPrev.Text += "(動畫 " + $fr.Count + " 格)"
                } elseif (-not $custom -and $script:curStyle) {
                    $LblCurPrev.Text += "(這台還沒有動畫圖檔 —— 重新安裝一次就有)"
                }
            }
        } else {
            $script:curAnimTimer.Stop(); $script:curAnimFrames = @()
            $ImgCurPrev.Source = $null
            $LblCurPrev.Text = "找不到 $file"
        }
    } catch { $script:curAnimTimer.Stop(); $script:curAnimFrames = @(); $ImgCurPrev.Source = $null; $LblCurPrev.Text = "圖片讀不到:" + $_.Exception.Message }
    # 熱點超出圖片範圍 = 游標會歪掉
    $hx = ClampInt $TCurHotX.Text 0 256 0
    $hy = ClampInt $TCurHotY.Text 0 256 0
    $LblCurHotWarn.Visibility = $(if ($custom -and $w -gt 0 -and ($hx -ge $w -or $hy -ge $h)) { "Visible" } else { "Collapsed" })   # 像素座標是 0..w-1,等於 w 就出界了;內建圖熱點不是這兩格決定的,不警告
}
function Load-CursorConfig {
    $pd = PluginDir
    if (-not $pd) { return }
    $v = Read-KV (Join-Path $pd "SpiritZh_cursor.txt")
    if ($null -eq $v) { return }   # 讀不到就整段不動畫面(同其他頁的慣例)
    $ChkCurOn.IsChecked = ($v["enabled"] -eq "1")
    $sc = 2.0
    try { if ($v["scale"]) { $sc = [double]::Parse($v["scale"], [Globalization.CultureInfo]::InvariantCulture) } } catch { $sc = 2.0 }
    $CboCurSize.SelectedIndex = CurIdxFromScale $sc
    $script:curImg = $(if ($v["image"]) { $v["image"].Trim() } else { "" })
    $st = $(if ($v["style"]) { $v["style"].Trim().ToLowerInvariant() } else { "" })
    if ($st -eq "classic" -or $st -eq "default") { $st = "" }
    if ($st -and -not ($script:CUR_STYLES | Where-Object { $_.k -eq $st })) { $st = "" }   # 不認得的風格名 → 經典(外掛端同樣處理)
    $script:curStyle = $st
    CurSelectStyle $st
    $TCurHotX.Text = [string](ClampInt $v["hotx"] 0 256 0)
    $TCurHotY.Text = [string](ClampInt $v["hoty"] 0 256 0)
    $ChkCurSoft.IsChecked = ($v["software"] -eq "1")
    $ChkCurAnim.IsChecked = ($v["anim"] -ne "0")   # 沒這個鍵(舊設定檔)= 開
    $fps = ClampInt $v["animfps"] 2 20 10
    $CboCurAnimSpd.SelectedIndex = $(if ($fps -le 7) { 0 } elseif ($fps -le 12) { 1 } else { 2 })
    $script:curAnimFps = $fps   # ★ 要放在 SelectedIndex 之後:SelectionChanged 會把它設成下拉的值
    $re = ClampInt $v["reapply"] 0 60000 2000
    $ChkCurReapply.IsChecked = ($re -gt 0)
    $script:curReapplyMs = $(if ($re -gt 0) { $re } else { 2000 })   # 手填的毫秒數(例如 500)要記住,存檔時原值寫回,不被蓋成 2000
    $script:cfgLoaded["cursor"] = $true
    CurUpdatePreview
}
function Save-CursorConfig {
    if (-not $script:cfgLoaded["cursor"]) { $script:saveErr += "SpiritZh_cursor.txt:沒讀成功過,為避免覆蓋成空白設定,這次不寫入"; return }
    $pd = PluginDir
    if (-not $pd) { return }
    $inv = [Globalization.CultureInfo]::InvariantCulture
    $kv = @{
        "enabled"  = $(if ($ChkCurOn.IsChecked) { "1" } else { "0" })
        "scale"    = ($script:CUR_SCALES[[math]::Max(0, $CboCurSize.SelectedIndex)]).ToString("0.0", $inv)
        "image"    = $script:curImg
        "style"    = $script:curStyle
        "hotx"     = [string](ClampInt $TCurHotX.Text 0 256 0)
        "hoty"     = [string](ClampInt $TCurHotY.Text 0 256 0)
        "software" = $(if ($ChkCurSoft.IsChecked) { "1" } else { "0" })
        "anim"     = $(if ($ChkCurAnim.IsChecked) { "1" } else { "0" })
        "animfps"  = [string](CurAnimFps)
        "reapply"  = $(if ($ChkCurReapply.IsChecked) { [string]$script:curReapplyMs } else { "0" })
    }
    [void](Save-KV (Join-Path $pd "SpiritZh_cursor.txt") $kv)
}
$CboCurSize.Add_SelectionChanged({ CurUpdatePreview })
$ChkCurAnim.Add_Checked({ CurUpdatePreview }); $ChkCurAnim.Add_Unchecked({ CurUpdatePreview })
$CboCurAnimSpd.Add_SelectionChanged({ try { $script:curAnimFps = [int]$CboCurAnimSpd.SelectedItem.Tag } catch {}; CurUpdatePreview })
$LstCurStyle.Add_SelectionChanged({
    $it = $LstCurStyle.SelectedItem
    if ($null -eq $it) { return }
    $script:curStyle = [string]$it.Tag
    CurUpdatePreview
})
$TCurHotX.Add_TextChanged({ CurUpdatePreview })
$TCurHotY.Add_TextChanged({ CurUpdatePreview })
$BtnCurTL.Add_Click({ $TCurHotX.Text = "0"; $TCurHotY.Text = "0"; Mark-Dirty $BtnCurTL })
$BtnCurCenter.Add_Click({
    try {
        $src = $ImgCurPrev.Source
        if ($null -eq $src) { Show-Msg "還沒有圖" "先選一張圖或選好內建尺寸,才知道中央在哪。" "warn"; return }
        $TCurHotX.Text = [string][int]([math]::Round($src.PixelWidth / 2))
        $TCurHotY.Text = [string][int]([math]::Round($src.PixelHeight / 2))
        Mark-Dirty $BtnCurCenter
    } catch {}
})
$BtnCurClear.Add_Click({
    $script:curImg = ""
    # ★ 熱點一定要跟著歸零:自訂圖置中可能留下 64,64,切回 32px 箭頭後游標會歪掉一大截。
    $TCurHotX.Text = "0"; $TCurHotY.Text = "0"
    Mark-Dirty $BtnCurClear
    CurUpdatePreview
})
$BtnCurPick.Add_Click({
    $pd = PluginDir
    if (-not $pd) { Show-Msg "找不到遊戲" "先按上方的「瀏覽」指定遊戲資料夾。" "warn"; return }
    $uiDir = Join-Path $pd "SpiritZh_ui"
    $d = New-Object System.Windows.Forms.OpenFileDialog
    $d.Filter = "PNG 圖片 (*.png)|*.png"
    $d.Title = "選一張游標圖(PNG)"
    if (Test-Path -LiteralPath $uiDir) { $d.InitialDirectory = $uiDir }
    if ($d.ShowDialog() -ne "OK") { return }
    $src = $d.FileName
    $name = [System.IO.Path]::GetFileName($src)
    if ($name -match '^cursor_([a-z]+_)?(32|48|64|96|128)\.png$') {
        Show-Msg "那是內建的樣式" "「$name」是安裝包內建的游標圖。要用內建的請按「清除」,再從上面的樣式列點選就好,不用從這裡挑。" "warn"
        return
    }
    # ★ SpiritZh_ui 是跟 DPS 面板 / 市場面板【共用】的素材夾(panel / logbox / bar_bg / bar_fill / avatar …)。
    #   使用者從桌面挑一張剛好也叫 panel.png 的圖 → 複製進去會把面板底圖蓋掉,畫面直接壞掉。
    #   白名單直接從安裝包的 payload 目錄讀,之後新增素材不用回來改這裡;讀不到就退回寫死的清單。
    $shipped = @()
    try {
        $payUi = Join-Path $PSScriptRoot "payload\BepInEx\plugins\SpiritZh_ui"
        if (Test-Path -LiteralPath $payUi) { $shipped = @(Get-ChildItem -LiteralPath $payUi -File | ForEach-Object { $_.Name.ToLowerInvariant() }) }
    } catch {}
    if ($shipped.Count -eq 0) { $shipped = @("avatar.png", "bar_bg.png", "bar_fill.png", "logbox.png", "panel.png") }
    if ($shipped -contains $name.ToLowerInvariant()) {
        Show-Msg "這個檔名被佔用了" "「$name」是安裝包附的介面素材(DPS / 市場面板在用),不能被蓋掉。`n`n請把你的圖改個名字(例如 my_cursor.png)再選一次。" "warn"
        return
    }
    try {
        if (-not (Test-Path -LiteralPath $uiDir)) { New-Item -ItemType Directory -Path $uiDir -Force | Out-Null }
        $dst = Join-Path $uiDir $name
        # 外掛只認 SpiritZh_ui\ 裡的檔名,所以一定要複製進去
        if ((Resolve-Path -LiteralPath $src).Path -ne $dst) {
            if ((Test-Path -LiteralPath $dst) -and -not (Confirm-Msg "已經有同名的圖" "SpiritZh_ui 裡已經有「$name」了,要覆蓋嗎?" "覆蓋" "取消")) { return }
            Copy-Item -LiteralPath $src -Destination $dst -Force
        }
        $script:curImg = $name
        Mark-Dirty $BtnCurPick
        CurUpdatePreview
    } catch { Show-Msg "複製失敗" ("沒辦法把圖片複製到 SpiritZh_ui:`n" + $_.Exception.Message) "error" }
})

# ══════════════════════════════════════════════════════════════════════
#  王技提示音(SpiritZh_bossalert.txt)—— v3.73
# ══════════════════════════════════════════════════════════════════════
# 設定檔格式跟其他頁不同:除了 enabled/banner/volume/cooldown 幾個固定鍵之外,
# 其餘每一行都是「技能id=音效檔」的自由規則,還有一條特別的 "*" 通用規則。
# 所以不能用 Read-KV/Save-KV 那套(它們只認固定鍵),要自己讀寫。
# ★ 使用者手打進去、但 GUI 不認得的規則一定要原樣保留 —— 同關注詞條的原則。
$script:baRules = New-Object System.Collections.ArrayList   # 每筆 @{ id=..; snd=.. }
$script:baAll = ""                                          # "*" 通用音
$NOBA = "(不設定)"
function BossAlertPath { $pd = PluginDir; if ($pd) { Join-Path $pd "SpiritZh_bossalert.txt" } else { "" } }

# 一列規則 = 技能id 文字框 + 音效下拉 + 刪除鈕。整份重畫,不做增量(規則數量很少)。
function Refresh-BaList {
    $BaList.Children.Clear()
    $files = @(Get-SoundFiles)
    for ($i = 0; $i -lt $script:baRules.Count; $i++) {
        $r = $script:baRules[$i]
        $row = New-Object System.Windows.Controls.DockPanel
        $row.Margin = "0,0,0,6"
        $del = New-Object System.Windows.Controls.Button
        $del.Content = "刪除"; $del.Width = 60; $del.Margin = "8,0,0,0"
        [System.Windows.Controls.DockPanel]::SetDock($del, "Right")
        # ★ 用 Tag 記住這一列對應哪一筆,不要靠 closure 抓 $i —— PowerShell 的
        #   事件處理常式是延後執行的,直接抓 $i 會全部拿到迴圈結束後的值。
        $del.Tag = $r
        $del.Add_Click({
            $script:baRules.Remove($this.Tag)
            Refresh-BaList; Mark-Dirty $this
        })
        $cb = New-Object System.Windows.Controls.ComboBox
        $cb.Width = 240; $cb.Margin = "8,0,0,0"
        [System.Windows.Controls.DockPanel]::SetDock($cb, "Right")
        [void]$cb.Items.Add($NOBA)
        foreach ($f in $files) { [void]$cb.Items.Add($f) }
        if ($r.snd -and $cb.Items.IndexOf($r.snd) -lt 0) { [void]$cb.Items.Add($r.snd) }   # 檔案被刪也不能弄丟設定
        $cb.SelectedItem = $(if ($r.snd) { $r.snd } else { $NOBA })
        $cb.Tag = $r
        $cb.Add_SelectionChanged({
            $v = [string]$this.SelectedItem
            $this.Tag.snd = $(if ($v -eq $NOBA) { "" } else { $v })
        })
        # 中文名 +「誰的招」—— 一眼看出這條是哪隻王的技能
        $info = New-Object System.Windows.Controls.TextBlock
        $info.VerticalAlignment = "Center"; $info.Margin = "8,0,0,0"; $info.Width = 300
        $info.TextTrimming = "CharacterEllipsis"
        $info.Foreground = "#8A94A8"; $info.FontSize = 12
        [System.Windows.Controls.DockPanel]::SetDock($info, "Right")
        $tb = New-Object System.Windows.Controls.TextBox
        $tb.Text = [string]$r.id
        $tb.Tag = @{ r = $r; info = $info }
        $setInfo = {
            param($id, $lbl)
            $zh = $script:SKZH[$id]
            $bs = $script:SK2BOSS[$id]
            if (-not $zh -and -not $bs) { $lbl.Text = "(不在已知王技清單裡 —— 打錯字?)"; $lbl.ToolTip = $null; return }
            $txt = $(if ($zh) { $zh } else { "" })
            if ($bs) {
                $txt += "  ← " + $(if ($bs.Count -le 3) { $bs -join "、" } else { ($bs[0..2] -join "、") + " 等 " + $bs.Count + " 隻王" })
                $lbl.ToolTip = ($bs -join "、")
            }
            $lbl.Text = $txt
        }
        & $setInfo ([string]$r.id) $info
        $tb.Add_TextChanged({
            $id = $this.Text.Trim()
            $this.Tag.r.id = $id
            $lbl = $this.Tag.info
            $zh = $script:SKZH[$id]; $bs = $script:SK2BOSS[$id]
            if (-not $zh -and -not $bs) { $lbl.Text = "(不在已知王技清單裡 —— 打錯字?)"; $lbl.ToolTip = $null; return }
            $x = $(if ($zh) { $zh } else { "" })
            if ($bs) {
                $x += "  ← " + $(if ($bs.Count -le 3) { $bs -join "、" } else { ($bs[0..2] -join "、") + " 等 " + $bs.Count + " 隻王" })
                $lbl.ToolTip = ($bs -join "、")
            }
            $lbl.Text = $x
        })
        [void]$row.Children.Add($del); [void]$row.Children.Add($cb); [void]$row.Children.Add($info); [void]$row.Children.Add($tb)
        [void]$BaList.Children.Add($row)
    }
    $LblBaEmpty.Visibility = $(if ($script:baRules.Count -eq 0) { "Visible" } else { "Collapsed" })
}
# ══ 職業技能資料(來源:靈谷資料庫 spiritvale-zhtw.pages.dev 的技能樹 + 遊戲本地化表 skill.<Id>.name 對 id;15 職業 / 256 技能)══
# 用途:技能特效黑名單的「從技能清單挑」對話框。i = 外掛要的技能 id,z = 中文,e = 英文顯示名。
$script:SKILL_DB = @(
  @{zh='侍僧';en='Acolyte';base=$true;sk=@(@{i='Heal';z='治療術';e='Heal'},@{i='CodexMastery';z='典籍精通';e='Codex Mastery'},@{i='IncreasedManaRegen';z='恢復提升';e='Increased Recovery'},@{i='Haste';z='加速';e='Haste'},@{i='Blessing';z='祝禱';e='Benediction'},@{i='HolyLight';z='聖光';e='Holy Light'},@{i='Grace';z='神聖恩典';e='Divine Grace'},@{i='Barrier';z='聖盾';e='Sacred Aegis'},@{i='Cure';z='治癒術';e='Cure'},@{i='TrueSight';z='真視';e='True Sight'},@{i='SpellShield';z='法術結界';e='Arcanum Ward'},@{i='Faith';z='信仰';e='Faith'},@{i='Revive';z='復活';e='Resurrection'})}
  @{zh='騎士';en='Knight';base=$true;sk=@(@{i='Taunt';z='嘲諷';e='Taunt'},@{i='SpearMastery';z='槍術精通';e='Spear Mastery'},@{i='ShieldMastery';z='盾術精通';e='Shield Mastery'},@{i='Endure';z='堅忍';e='Endure'},@{i='SpearThrust';z='穿刺連擊';e='Piercing Flurry'},@{i='Fortify';z='強化壁壘';e='Fortify'},@{i='TwohandParry';z='雙手格擋';e='Twohand Parry'},@{i='SpearStab';z='穿刺';e='Impale'},@{i='ReflectShield';z='反射護盾';e='Reflect Shield'},@{i='IncreasedHealthRegen';z='活力再生';e='Increased Regeneration'},@{i='SpearSlice';z='空氣斬';e='Air Cutter'},@{i='SpearQuicken';z='槍術加速';e='Spear Quicken'},@{i='WeaponThrow';z='擲武器';e='Weapon Throw'},@{i='Counter';z='反擊架式';e='Counter Stance'})}
  @{zh='法師';en='Mage';base=$true;sk=@(@{i='WandMastery';z='杖術精通';e='Wand Mastery'},@{i='Earthbolt';z='石箭術';e='Earthbolt'},@{i='Firebolt';z='火箭術';e='Firebolt'},@{i='IncreasedManaRegen';z='恢復提升';e='Increased Recovery'},@{i='Thunderbolt';z='落雷';e='Thunderbolt'},@{i='Icebolt';z='冰箭術';e='Icebolt'},@{i='EarthSpikes';z='大地尖刺';e='Earth Spikes'},@{i='Fireball';z='火球術';e='Fireball'},@{i='TrueSight';z='真視';e='True Sight'},@{i='ThunderStorm';z='雷暴';e='Thunder Storm'},@{i='IceShard';z='冰晶';e='Ice Shard'},@{i='EnergyShield';z='能量護盾';e='Energy Shield'},@{i='FreeCast';z='自由施法';e='Free Cast'},@{i='Blink';z='閃現';e='Blink'})}
  @{zh='盜賊';en='Rogue';base=$true;sk=@(@{i='BladeMastery';z='劍術精通';e='Blade Mastery'},@{i='ShadowStep';z='暗影步';e='Shadow Step'},@{i='Multistrike';z='多重打擊';e='Multistrike'},@{i='VenomStrike';z='毒液打擊';e='Venom Strike'},@{i='Cloaking';z='隱形';e='Cloaking'},@{i='LightningReflexes';z='閃電反射';e='Lightning Reflexes'},@{i='VenomCoating';z='毒液塗層';e='Venom Coating'},@{i='BladeDance';z='劍舞';e='Blade Dance'},@{i='DualWieldMastery';z='雙持精通';e='Dual Wield Mastery'},@{i='EnchantPoison';z='附魔·劇毒';e='Enchant Poison'},@{i='SmokeScreen';z='煙幕';e='Smoke Screen'},@{i='Haste';z='加速';e='Haste'},@{i='Cure';z='治癒術';e='Cure'})}
  @{zh='斥候';en='Scout';base=$true;sk=@(@{i='SteadyHands';z='穩定之手';e='Steady Hands'},@{i='StrafingVolley';z='掃射齊發';e='Strafing Volley'},@{i='PreciseAim';z='精準瞄準';e='Precise Aim'},@{i='ArrowShower';z='箭雨';e='Arrow Shower'},@{i='ForceShot';z='強力射擊';e='Force Shot'},@{i='Marked';z='標記目標';e='Mark Target'},@{i='Agility';z='專注';e='Inner Focus'},@{i='SlowTrap';z='緩速陷阱';e='Slow Trap'},@{i='VolatileBolt';z='不穩定彈';e='Volatile Bolt'},@{i='SniperNest';z='狙擊點';e='Sniper''s Nest'})}
  @{zh='召喚師';en='Summoner';base=$true;sk=@(@{i='SummonAngel';z='召喚天使';e='Summon Angel'},@{i='SummonCactus';z='召喚仙人掌';e='Summon Cactus'},@{i='SummonMastery';z='召喚精通';e='Summon Mastery'},@{i='SummonCat';z='召喚貓';e='Summon Cat'},@{i='SummonWolf';z='召喚狼';e='Summon Wolf'},@{i='FieldHealing';z='共鳴之井';e='Resonance Well'},@{i='FieldSilence';z='壓制領域';e='Suppression Field'},@{i='SoulStrike';z='靈魂打擊';e='Soul Strike'},@{i='FieldCurse';z='放逐領域';e='Banishment Field'},@{i='FieldDamage';z='失諧之井';e='Dissonance Well'},@{i='Conjurer';z='召喚羈絆';e='Conjurer'},@{i='GuardianBond';z='守護連結';e='Guardian Bond'},@{i='TrueSight';z='真視';e='True Sight'},@{i='FuryBond';z='盛怒連結';e='Fury Bond'},@{i='Invoker';z='召喚覺醒';e='Invoker'},@{i='SummonAttack';z='召喚指令';e='Summon Command'},@{i='SummonRecall';z='召喚回收';e='Summon Recall'},@{i='SummonSwap';z='召喚切換';e='Summon Swap'},@{i='SummonMount';z='召喚坐騎';e='Summon Mount'})}
  @{zh='戰士';en='Warrior';base=$true;sk=@(@{i='AxeMastery';z='斧術精通';e='Axe Mastery'},@{i='Bash';z='猛擊';e='Bash'},@{i='Stomp';z='踐踏';e='Stomp'},@{i='AxeArc';z='雙重劈砍';e='Twin Cleave'},@{i='AxeVortex';z='漩渦斬';e='Vortex Slash'},@{i='Whirlwind';z='旋風斬';e='Whirlwind'},@{i='CritMastery';z='磨礪之刃';e='Honed Blade'},@{i='DualWieldMastery';z='雙持精通';e='Dual Wield Mastery'},@{i='ResistanceMastery';z='自然抗性';e='Natural Resistance'})}
  @{zh='狂戰士';en='Berserker';base=$false;sk=@(@{i='ShoutMight';z='強力咆哮';e='Mighty Roar'},@{i='GroundSlam';z='裂地';e='Earth Splitter'},@{i='DarkClaw';z='暗爪';e='Dark Claw'},@{i='WildCharge';z='狂野衝鋒';e='Wild Charge'},@{i='ShoutBlood';z='血嚎';e='Blood Howl'},@{i='ShoutFury';z='狂怒吼叫';e='Furious Shout'},@{i='Execute';z='處決';e='Execute'},@{i='RageMastery';z='殘暴';e='Brutality'},@{i='Cyclone';z='氣旋';e='Cyclone'},@{i='ShoutStun';z='威嚇怒吼';e='Fearsome Cry'},@{i='Berserk';z='狂暴';e='Berserk'},@{i='AxeThrow';z='擲斧';e='Axe Throw'},@{i='BloodFrenzy';z='嗜血狂暴';e='Blood Frenzy'},@{i='IncreasedHealthRegen';z='活力再生';e='Increased Regeneration'},@{i='BloodCrash';z='活力怒爆';e='Blood Crash'},@{i='Unyielding';z='不屈';e='Unyielding'})}
  @{zh='神槍手';en='Gunslinger';base=$false;sk=@(@{i='SuppressiveShot';z='壓制連射';e='Suppressive Shot'},@{i='PiercingShot';z='穿刺射擊';e='Piercing Shot'},@{i='FanFire';z='扇形射擊';e='Fan Fire'},@{i='ShrapnelShot';z='破片';e='Shrapnel'},@{i='ExplosiveGrenade';z='爆裂手榴彈';e='Explosive Grenade'},@{i='PoisonGrenade';z='毒氣手榴彈';e='Poison Grenade'},@{i='SniperShot';z='狙擊射擊';e='Sniper Shot'},@{i='PanicBurst';z='恐慌爆發';e='Panic Burst'},@{i='GunMastery';z='槍械精通';e='Gun Mastery'},@{i='PointBlankShot';z='近距射擊';e='Point Blank'},@{i='FreezeGrenade';z='冰凍手榴彈';e='Freeze Grenade'},@{i='AerialShot';z='浮空射擊';e='Aerial Shot'},@{i='FlashBang';z='閃光彈';e='Flash Bang'},@{i='JumpShot';z='跳躍射擊';e='Jump Shot'},@{i='TriggerHappy';z='連射狂熱';e='Trigger Happy'},@{i='Lockdown';z='封鎖';e='Lockdown'},@{i='WeaponSwap';z='雙重配置';e='Dual Loadout'})}
  @{zh='死靈法師';en='Necromancer';base=$false;sk=@(@{i='SummonAbomination';z='召喚憎惡';e='Summon Abomination'},@{i='SummonSkeleton';z='召喚骷髏';e='Summon Skeleton'},@{i='SkeletonMastery';z='骷髏精通';e='Skeleton Mastery'},@{i='SummonSkeletonMage';z='召喚骷髏法師';e='Summon Skeleton Mage'},@{i='SummonWraith';z='召喚幽魂';e='Summon Wraith'},@{i='BoneSpear';z='骨矛';e='Bone Spear'},@{i='CorpseBarrier';z='屍體屏障';e='Corpse Barrier'},@{i='ScytheMastery';z='鐮術精通';e='Scythe Mastery'},@{i='BoneSpikes';z='骨刺';e='Bone Spikes'},@{i='DeathCoil';z='死亡纏繞';e='Death Coil'},@{i='CorpseExplosion';z='屍體爆炸';e='Corpse Explosion'},@{i='Harvest';z='躍動收割';e='Harvest'},@{i='TwohandParry';z='雙手格擋';e='Twohand Parry'},@{i='Reanimation';z='復生';e='Reanimation'},@{i='LifeDrain';z='生命汲取';e='Life Drain'},@{i='DeathBond';z='死亡連結';e='Death Bond'},@{i='Reap';z='鐮割';e='Reap'},@{i='SummonReanimation';z='召喚復生體';e='Summon Reanimation'},@{i='DeathNova';z='死亡新星';e='Death Nova'},@{i='DeathSpiral';z='死亡螺旋';e='Death Spiral'},@{i='DeathBramble';z='腐屍氣場';e='Necrotic Presence'},@{i='GraveChill';z='墓寒';e='Grave Chill'},@{i='SoulDrain';z='靈魂汲取';e='Soul Drain'})}
  @{zh='聖騎士';en='Paladin';base=$false;sk=@(@{i='HighGuard';z='高階格擋';e='High Guard'},@{i='HolyShield';z='神聖護盾';e='Holy Shield'},@{i='Faith';z='信仰';e='Faith'},@{i='Sacrifice';z='獻祭';e='Sacrifice'},@{i='Consecration';z='祝聖';e='Consecration'},@{i='Aegis';z='光之神盾';e='Aegis of Light'},@{i='ShieldBash';z='盾擊';e='Shield Bash'},@{i='EnchantArmorHoly';z='祝聖';e='Sanctify'},@{i='JudgementBlade';z='審判之刃';e='Judgement Blade'},@{i='DivinePunishment';z='神罰';e='Divine Punishment'},@{i='ShieldThrow';z='擲盾';e='Shield Throw'},@{i='LifeBond';z='生命連結';e='Life Bond'},@{i='GrandCross';z='聖十字';e='Grand Cross'},@{i='Defiance';z='反抗光環';e='Defiance Aura'},@{i='Vitality';z='活力光環';e='Vitality Aura'},@{i='Conviction';z='堅信光環';e='Conviction Aura'},@{i='MountMastery';z='獅鷲騎乘';e='Gryphon Riding'})}
  @{zh='牧師';en='Priest';base=$false;sk=@(@{i='HighHeal';z='高階治療術';e='High Heal'},@{i='ReviveAll';z='救贖';e='Salvation'},@{i='MaceMastery';z='錘術精通';e='Mace Mastery'},@{i='Sanctuary';z='聖域';e='Sanctuary'},@{i='StatusRecovery';z='狀態恢復';e='Status Recovery'},@{i='TurnUndead';z='驅逐不死';e='Turn Undead'},@{i='Zeal';z='熱忱';e='Zeal'},@{i='Damnation';z='天譴';e='Damnation'},@{i='SacredGround';z='聖地';e='Sacred Ground'},@{i='GuardianSpirit';z='守護靈';e='Guardian Spirit'},@{i='Exorcism';z='驅魔';e='Exorcism'},@{i='EndowHoly';z='賦予神聖';e='Endow Holy'},@{i='Smite';z='制裁';e='Smite'},@{i='Divinity';z='神性';e='Divinity'},@{i='Sacrament';z='聖禮';e='Sacrament'},@{i='Fanaticism';z='狂熱';e='Fanaticism'},@{i='HolyWrath';z='神聖之怒';e='Holy Wrath'},@{i='Dispell';z='赦罪';e='Absolution'})}
  @{zh='忍者';en='Shinobi';base=$false;sk=@(@{i='FlameOrb';z='火焰球';e='Flame Orb'},@{i='FrostBlade';z='螺旋束縛';e='Binding Spiral'},@{i='LightningStrike';z='瞬步';e='Flash Step'},@{i='FireRelease';z='火遁';e='Fire Release'},@{i='IceRelease';z='冰遁';e='Ice Release'},@{i='LightningRelease';z='雷遁';e='Lightning Release'},@{i='FlowState';z='心流狀態';e='Flow State'},@{i='NinjutsuMastery';z='忍術精通';e='Ninjutsu Mastery'},@{i='ShadowSeal';z='暗影印記';e='Shadow Seal'},@{i='ShadowMastery';z='暗影精通';e='Shadow Mastery'},@{i='SilentEdge';z='無聲之刃';e='Silent Edge'},@{i='FanOfKnives';z='刀扇';e='Fan Of Knives'},@{i='ShadowFeint';z='迷蹤佯攻';e='Elusive Feint'},@{i='TwistOfFate';z='命運扭轉';e='Twist Of Fate'},@{i='ShurikenFan';z='萬旋手裏劍';e='Shuriken Fan'},@{i='MimicSeal';z='擬態印記';e='Mimic Seal'},@{i='ShadowRelease';z='黑刃';e='Black Blade'})}
  @{zh='織者';en='Weaver';base=$false;sk=@(@{i='Heal';z='治療術';e='Heal'},@{i='Icebolt';z='冰箭術';e='Icebolt'},@{i='Firebolt';z='火箭術';e='Firebolt'},@{i='WeaverMastery';z='織者精通';e='Weaver Mastery'},@{i='SpearThrust';z='穿刺連擊';e='Piercing Flurry'},@{i='StrafingVolley';z='掃射齊發';e='Strafing Volley'},@{i='VenomStrike';z='毒液打擊';e='Venom Strike'},@{i='Haste';z='加速';e='Haste'},@{i='IceShard';z='冰晶';e='Ice Shard'},@{i='Fireball';z='火球術';e='Fireball'},@{i='Bash';z='猛擊';e='Bash'},@{i='SpearStab';z='穿刺';e='Impale'},@{i='ArrowShower';z='箭雨';e='Arrow Shower'},@{i='VenomCoating';z='毒液塗層';e='Venom Coating'},@{i='Cure';z='治癒術';e='Cure'},@{i='Earthbolt';z='石箭術';e='Earthbolt'},@{i='Thunderbolt';z='落雷';e='Thunderbolt'},@{i='Endure';z='堅忍';e='Endure'},@{i='SpearSlice';z='空氣斬';e='Air Cutter'},@{i='BladeDance';z='劍舞';e='Blade Dance'},@{i='ShadowStep';z='暗影步';e='Shadow Step'},@{i='HolyLight';z='聖光';e='Holy Light'},@{i='EarthSpikes';z='大地尖刺';e='Earth Spikes'},@{i='ThunderStorm';z='雷暴';e='Thunder Storm'},@{i='Fortify';z='強化壁壘';e='Fortify'},@{i='Stomp';z='踐踏';e='Stomp'},@{i='Marked';z='標記目標';e='Mark Target'},@{i='Cloaking';z='隱形';e='Cloaking'},@{i='SoulStrike';z='靈魂打擊';e='Soul Strike'},@{i='FieldSilence';z='壓制領域';e='Suppression Field'},@{i='FieldCurse';z='放逐領域';e='Banishment Field'},@{i='ResistanceMastery';z='自然抗性';e='Natural Resistance'},@{i='AxeVortex';z='漩渦斬';e='Vortex Slash'},@{i='SteadyHands';z='穩定之手';e='Steady Hands'},@{i='LightningReflexes';z='閃電反射';e='Lightning Reflexes'},@{i='Blessing';z='祝禱';e='Benediction'},@{i='FieldHealing';z='共鳴之井';e='Resonance Well'},@{i='FieldDamage';z='失諧之井';e='Dissonance Well'},@{i='Grace';z='神聖恩典';e='Divine Grace'},@{i='Whirlwind';z='旋風斬';e='Whirlwind'},@{i='Agility';z='專注';e='Inner Focus'},@{i='DualWieldMastery';z='雙持精通';e='Dual Wield Mastery'})}
  @{zh='巫師';en='Wizard';base=$false;sk=@(@{i='FirePillar';z='火柱';e='Fire Pillar'},@{i='FireBarrier';z='火焰化身';e='Avatar of Fire'},@{i='ChainLightning';z='連鎖閃電';e='Chain Lightning'},@{i='Meteor';z='隕石';e='Meteor'},@{i='Tempest';z='怒雷風暴';e='Tempest'},@{i='EarthBarrier';z='岩石化身';e='Avatar of Stone'},@{i='TetraVortex';z='元素爆發';e='Elemental Overload'},@{i='WindBarrier';z='風暴化身';e='Avatar of Storm'},@{i='Earthquake';z='地震術';e='Earthquake'},@{i='FreezingField';z='暴風雪';e='Blizzard'},@{i='EarthWall';z='土牆';e='Earth Wall'},@{i='WaterBarrier';z='寒霜化身';e='Avatar of Frost'},@{i='HydroVortex';z='水龍捲';e='Hydro Vortex'},@{i='ArcaneSigil';z='奧術符印';e='Arcane Sigil'})}
)
# ══ 王技資料(來源:靈谷資料庫 spiritvale-zhtw.pages.dev,32 隻王 / 114 技能)══
# 用途:①「從王的清單挑」對話框 ② 規則列顯示「這是誰的招」
$script:BOSS_DB = @(
  @{en='Sting';zh='毒刺蜂';lv=15;sk=@(@{i='LightningReflexes';z='閃電反射'},@{i='SmokeScreen';z='煙幕'},@{i='ForceShot';z='強力射擊'},@{i='StrafingVolley';z='掃射齊發'},@{i='Thunderbolt';z='落雷'},@{i='PanicBurst';z='恐慌爆發'},@{i='NPC_WideBlind';z='廣域致盲'})}
  @{en='Hare';zh='野兔';lv=30;sk=@(@{i='Berserk';z='狂暴'},@{i='Stomp';z='踐踏'},@{i='ShadowStep';z='暗影步'},@{i='NPC_WideStun';z='廣域暈眩'})}
  @{en='Werewolf';zh='狼人';lv=35;sk=@(@{i='LifeDrain';z='生命汲取'},@{i='ShadowStep';z='暗影步'},@{i='AxeArc';z='雙重劈砍'},@{i='ShadowRelease';z='黑刃'},@{i='NPC_WideBleed';z='廣域流血'})}
  @{en='Cat Bolt';zh='雷電貓';lv=35;sk=@(@{i='LightningReflexes';z='閃電反射'},@{i='ThunderStorm';z='雷暴'},@{i='LightningRelease';z='雷遁'},@{i='ChainLightning';z='連鎖閃電'},@{i='Thunderbolt';z='落雷'},@{i='Tempest';z='怒雷風暴'},@{i='NPC_WideFreeze';z='廣域冰凍'})}
  @{en='Cactus Boss';zh='仙人掌王';lv=40;sk=@(@{i='NPC_SpikedShell';z='荊棘'},@{i='Stomp';z='踐踏'},@{i='SpearSlice';z='空氣斬'},@{i='ShieldThrow';z='擲盾'},@{i='ShieldBash';z='盾擊'},@{i='Earthquake';z='地震術'},@{i='NPC_WidePoison';z='廣域劇毒'})}
  @{en='Sunflora Pixie';zh='向日葵妖精';lv=40;sk=@(@{i='NPC_SpellGuard';z='法術護盾'},@{i='EarthSpikes';z='大地尖刺'},@{i='FieldSilence';z='壓制領域'},@{i='FieldHealing';z='共鳴之井'},@{i='Earthbolt';z='石箭術'},@{i='NPC_WideSilence';z='廣域沉默'})}
  @{en='Scorpion King';zh='蠍王';lv=40;sk=@(@{i='Berserk';z='狂暴'},@{i='Fireball';z='火球術'},@{i='Stomp';z='踐踏'},@{i='AxeArc';z='雙重劈砍'},@{i='Firebolt';z='火箭術'},@{i='NPC_WideBleed';z='廣域流血'})}
  @{en='Hermit King';zh='寄居蟹王';lv=45;sk=@(@{i='NPC_SteelGuard';z='強化'},@{i='Whirlwind';z='旋風斬'},@{i='HydroVortex';z='水龍捲'},@{i='IceShard';z='冰晶'},@{i='Icebolt';z='冰箭術'},@{i='NPC_WideFreeze';z='廣域冰凍'})}
  @{en='Snake Naga';zh='娜迦';lv=50;sk=@(@{i='NPC_SpellGuard';z='法術護盾'},@{i='NPC_Venom';z='劇毒'},@{i='FieldSilence';z='壓制領域'},@{i='VolatileBolt';z='不穩定彈'},@{i='StrafingVolley';z='掃射齊發'},@{i='NPC_WideBlind';z='廣域致盲'})}
  @{en='Goblin Giant Gold';zh='獸人王';lv=55;sk=@(@{i='Berserk';z='狂暴'},@{i='Stomp';z='踐踏'},@{i='Whirlwind';z='旋風斬'},@{i='SpearSlice';z='空氣斬'},@{i='ShieldBash';z='盾擊'},@{i='Earthquake';z='地震術'},@{i='GroundSlam';z='裂地'},@{i='NPC_WideBleed';z='廣域流血'})}
  @{en='Bat Lord';zh='蝙蝠領主';lv=55;sk=@(@{i='LightningReflexes';z='閃電反射'},@{i='NPC_Venom';z='劇毒'},@{i='SmokeScreen';z='煙幕'},@{i='ShadowStep';z='暗影步'},@{i='NPC_ManaLeech';z='魔力汲取'},@{i='NPC_WidePoison';z='廣域劇毒'})}
  @{en='Zombie Goblin King';zh='殭屍獸人領主';lv=65;sk=@(@{i='Berserk';z='狂暴'},@{i='Stomp';z='踐踏'},@{i='Whirlwind';z='旋風斬'},@{i='DeathCoil';z='死亡纏繞'},@{i='Damnation';z='天譴'},@{i='NPC_WideCurse';z='廣域詛咒'})}
  @{en='Queen Worm';zh='蟲后';lv=75;sk=@(@{i='NPC_Venom';z='劇毒'},@{i='NPC_Poison';z='黏液射擊'},@{i='FieldDamage';z='失諧之井'},@{i='PoisonGrenade';z='毒氣手榴彈'},@{i='FieldCurse';z='放逐領域'},@{i='NPC_WidePoison';z='廣域劇毒'})}
  @{en='Ice Mage';zh='冰法師';lv=80;sk=@(@{i='NPC_SpellGuard';z='法術護盾'},@{i='IceShard';z='冰晶'},@{i='ThunderStorm';z='雷暴'},@{i='HydroVortex';z='水龍捲'},@{i='Icebolt';z='冰箭術'},@{i='FreezingField';z='暴風雪'},@{i='FreezeGrenade';z='冰凍手榴彈'},@{i='NPC_WideFreeze';z='廣域冰凍'})}
  @{en='Angel Mage';zh='熾天使';lv=90;sk=@(@{i='NPC_SpellGuard';z='法術護盾'},@{i='DivinePunishment';z='神罰'},@{i='Sanctuary';z='聖域'},@{i='Exorcism';z='驅魔'},@{i='HolyLight';z='聖光'},@{i='Damnation';z='天譴'},@{i='Smite';z='制裁'},@{i='NPC_WideCurse';z='廣域詛咒'},@{i='SacredGround';z='聖地'})}
  @{en='Worm Creep';zh='蠕蟲';lv=95;sk=@(@{i='NPC_Venom';z='劇毒'},@{i='VenomStrike';z='毒液打擊'},@{i='FieldDamage';z='失諧之井'},@{i='PoisonGrenade';z='毒氣手榴彈'},@{i='SmokeScreen';z='煙幕'},@{i='NPC_WidePoison';z='廣域劇毒'})}
  @{en='Imp Devil';zh='惡魔領主';lv=105;sk=@(@{i='Berserk';z='狂暴'},@{i='Fireball';z='火球術'},@{i='FieldCurse';z='放逐領域'},@{i='Meteor';z='隕石'},@{i='Firebolt';z='火箭術'},@{i='FirePillar';z='火柱'},@{i='ExplosiveGrenade';z='爆裂手榴彈'},@{i='NPC_WideCurse';z='廣域詛咒'},@{i='NPC_WideStun';z='廣域暈眩'})}
  @{en='Eyeball Monster';zh='巨眼怪';lv=110;sk=@(@{i='Berserk';z='狂暴'},@{i='NPC_ManaLeech';z='魔力汲取'},@{i='ShieldBash';z='盾擊'},@{i='FreezingField';z='暴風雪'},@{i='IceShard';z='冰晶'},@{i='Earthquake';z='地震術'},@{i='NPC_WideFreeze';z='廣域冰凍'},@{i='NPC_WideCurse';z='廣域詛咒'})}
  @{en='Wraith';zh='幽魂王';lv=125;sk=@(@{i='Berserk';z='狂暴'},@{i='DeathCoil';z='死亡纏繞'},@{i='Harvest';z='躍動收割'},@{i='Reap';z='鐮割'},@{i='DeathSpiral';z='死亡螺旋'},@{i='BoneSpikes';z='骨刺'},@{i='ShadowRelease';z='黑刃'},@{i='NPC_WideCurse';z='廣域詛咒'},@{i='NPC_WideSilence';z='廣域沉默'})}
  @{en='Death Mage';zh='死亡法師';lv=130;sk=@(@{i='Berserk';z='狂暴'},@{i='SoulStrike';z='靈魂打擊'},@{i='Dark Exorcism';z='黑暗驅魔'},@{i='Cloaking';z='隱形'},@{i='ShadowStep';z='暗影步'},@{i='ShadowRelease';z='黑刃'},@{i='TurnUndead';z='驅逐不死'},@{i='NPC_WideBlind';z='廣域致盲'},@{i='NPC_WideSilence';z='廣域沉默'})}
  @{en='Goblin Warchief';zh='獸人酋長';lv=130;sk=@(@{i='Berserk';z='狂暴'},@{i='Execute';z='處決'},@{i='Cyclone';z='氣旋'},@{i='Tempest';z='怒雷風暴'},@{i='Earthquake';z='地震術'},@{i='FirePillar';z='火柱'},@{i='WildCharge';z='狂野衝鋒'},@{i='NPC_WideBleed';z='廣域流血'},@{i='NPC_WideStun';z='廣域暈眩'})}
  @{en='Alien Big Blink';zh='宇宙實體';lv=135;sk=@(@{i='Berserk';z='狂暴'},@{i='VolatileBolt';z='不穩定彈'},@{i='ShadowRelease';z='黑刃'},@{i='ShadowStrike';z='暗影打擊'},@{i='Damnation';z='天譴'},@{i='GrandCross';z='聖十字'},@{i='Dark Exorcism';z='黑暗驅魔'},@{i='NPC_WideCurse';z='廣域詛咒'},@{i='NPC_WideSilence';z='廣域沉默'})}
  @{en='Spider Queen Robot';zh='蜘蛛女王機器人';lv=135;sk=@(@{i='Berserk';z='狂暴'},@{i='JumpShot';z='跳躍射擊'},@{i='FieldDamage';z='失諧之井'},@{i='ShadowRelease';z='黑刃'},@{i='PointBlankShot';z='近距射擊'},@{i='NPC_Poison';z='黏液射擊'},@{i='SmokeScreen';z='煙幕'},@{i='NPC_WidePoison';z='廣域劇毒'},@{i='NPC_WideStun';z='廣域暈眩'})}
  @{en='Mega Ice Golem';zh='巨型冰魔像';lv=140;sk=@(@{i='Berserk';z='狂暴'},@{i='Stomp';z='踐踏'},@{i='FreezingField';z='暴風雪'},@{i='HydroVortex';z='水龍捲'},@{i='IceRelease';z='冰遁'},@{i='ShieldBash';z='盾擊'},@{i='Earthquake';z='地震術'},@{i='NPC_WideFreeze';z='廣域冰凍'},@{i='NPC_WideStun';z='廣域暈眩'})}
  @{en='Turtle King';zh='烏龜王';lv=140;sk=@(@{i='Berserk';z='狂暴'},@{i='TetraVortexFire';z='超載·火焰'},@{i='Earthquake';z='地震術'},@{i='IceRelease';z='冰遁'},@{i='JudgementBlade';z='審判之刃'},@{i='GrandCross';z='聖十字'},@{i='EnergyShield';z='能量護盾'},@{i='NPC_WideFreeze';z='廣域冰凍'},@{i='NPC_WideStun';z='廣域暈眩'})}
  @{en='NightmareWizardBoss';zh='回聲巫師';lv=155;sk=@(@{i='Berserk';z='狂暴'},@{i='SoulStrike';z='靈魂打擊'},@{i='HydroVortex';z='水龍捲'},@{i='Tempest';z='怒雷風暴'},@{i='Meteor';z='隕石'},@{i='FreezingField';z='暴風雪'},@{i='Earthquake';z='地震術'},@{i='ChainLightning';z='連鎖閃電'},@{i='ArcaneSigil';z='奧術符印'},@{i='EnergyShield';z='能量護盾'})}
  @{en='NightmareShinobiBoss';zh='回聲忍者';lv=155;sk=@(@{i='Berserk';z='狂暴'},@{i='ShadowSeal';z='暗影印記'},@{i='ShadowFeint';z='迷蹤佯攻'},@{i='TwistOfFate';z='命運扭轉'},@{i='ShadowRelease';z='黑刃'},@{i='LightningStrike';z='瞬步'},@{i='FrostBlade';z='螺旋束縛'},@{i='FlameOrb';z='火焰球'},@{i='LightningReflexes';z='閃電反射'},@{i='SmokeScreen';z='煙幕'})}
  @{en='NightmareNecromancerBoss';zh='回聲死靈法師';lv=155;sk=@(@{i='Berserk';z='狂暴'},@{i='SummonWraith';z='召喚幽魂'},@{i='FuryBond';z='盛怒連結'},@{i='Harvest';z='躍動收割'},@{i='Reap';z='鐮割'},@{i='DeathSpiral';z='死亡螺旋'},@{i='DeathCoil';z='死亡纏繞'},@{i='DeathNova';z='死亡新星'})}
  @{en='NightmarePriestBoss';zh='回聲牧師';lv=155;sk=@(@{i='Berserk';z='狂暴'},@{i='Heal';z='治療術'},@{i='Sanctuary';z='聖域'},@{i='Exorcism';z='驅魔'},@{i='Haste';z='加速'},@{i='Blessing';z='祝禱'},@{i='Zeal';z='熱忱'},@{i='Barrier';z='聖盾'},@{i='Dispell';z='赦罪'},@{i='SacredGround';z='聖地'})}
  @{en='NightmareBerserkerBoss';zh='回聲狂戰士';lv=155;sk=@(@{i='Berserk';z='狂暴'},@{i='ShoutFury';z='狂怒吼叫'},@{i='WildCharge';z='狂野衝鋒'},@{i='GroundSlam';z='裂地'},@{i='Cyclone';z='氣旋'},@{i='DarkClaw';z='暗爪'},@{i='Execute';z='處決'},@{i='Unyielding';z='不屈'},@{i='ShoutStun';z='威嚇怒吼'},@{i='TwohandQuicken';z='斧術加速'})}
  @{en='NightmareGunslingerBoss';zh='回聲神槍手';lv=155;sk=@(@{i='Berserk';z='狂暴'},@{i='FanFire';z='扇形射擊'},@{i='PanicBurst';z='恐慌爆發'},@{i='PiercingShot';z='穿刺射擊'},@{i='SniperShot';z='狙擊射擊'},@{i='SuppressiveShot';z='壓制連射'},@{i='SlowTrap';z='緩速陷阱'},@{i='Marked';z='標記目標'},@{i='Agility';z='專注'})}
  @{en='NightmarePaladinBoss';zh='回聲聖騎士';lv=155;sk=@(@{i='Berserk';z='狂暴'},@{i='ShieldBash';z='盾擊'},@{i='Consecration';z='祝聖'},@{i='GrandCross';z='聖十字'},@{i='LifeBond';z='生命連結'},@{i='HighGuard';z='高階格擋'},@{i='Aegis';z='光之神盾'},@{i='Conviction';z='堅信光環'})}
  @{en='Eternal Tower Bosses';zh='無盡之塔(塔王)';lv=0;sk=@(@{i='UmbralDecay';z='陰影腐蝕(黑火)'},@{i='UmbralCollapse';z='陰影崩塌(90% 真傷)'})}
)
# 技能英文 id -> 會用它的王(中文名)。給規則列顯示「這是誰的招」用。
$script:SK2BOSS = @{
  'Aegis' = @('回聲聖騎士')
  'Agility' = @('回聲神槍手')
  'ArcaneSigil' = @('回聲巫師')
  'AxeArc' = @('狼人','蠍王')
  'Barrier' = @('回聲牧師')
  'Berserk' = @('野兔','蠍王','獸人王','殭屍獸人領主','惡魔領主','巨眼怪','幽魂王','死亡法師','獸人酋長','宇宙實體','蜘蛛女王機器人','巨型冰魔像','烏龜王','回聲巫師','回聲忍者','回聲死靈法師','回聲牧師','回聲狂戰士','回聲神槍手','回聲聖騎士')
  'Blessing' = @('回聲牧師')
  'BoneSpikes' = @('幽魂王')
  'ChainLightning' = @('雷電貓','回聲巫師')
  'Cloaking' = @('死亡法師')
  'Consecration' = @('回聲聖騎士')
  'Conviction' = @('回聲聖騎士')
  'Cyclone' = @('獸人酋長','回聲狂戰士')
  'Damnation' = @('殭屍獸人領主','熾天使','宇宙實體')
  'Dark Exorcism' = @('死亡法師','宇宙實體')
  'DarkClaw' = @('回聲狂戰士')
  'DeathCoil' = @('殭屍獸人領主','幽魂王','回聲死靈法師')
  'DeathNova' = @('回聲死靈法師')
  'DeathSpiral' = @('幽魂王','回聲死靈法師')
  'Dispell' = @('回聲牧師')
  'DivinePunishment' = @('熾天使')
  'EarthSpikes' = @('向日葵妖精')
  'Earthbolt' = @('向日葵妖精')
  'Earthquake' = @('仙人掌王','獸人王','巨眼怪','獸人酋長','巨型冰魔像','烏龜王','回聲巫師')
  'EnergyShield' = @('烏龜王','回聲巫師')
  'Execute' = @('獸人酋長','回聲狂戰士')
  'Exorcism' = @('熾天使','回聲牧師')
  'ExplosiveGrenade' = @('惡魔領主')
  'FanFire' = @('回聲神槍手')
  'FieldCurse' = @('蟲后','惡魔領主')
  'FieldDamage' = @('蟲后','蠕蟲','蜘蛛女王機器人')
  'FieldHealing' = @('向日葵妖精')
  'FieldSilence' = @('向日葵妖精','娜迦')
  'FirePillar' = @('惡魔領主','獸人酋長')
  'Fireball' = @('蠍王','惡魔領主')
  'Firebolt' = @('蠍王','惡魔領主')
  'FlameOrb' = @('回聲忍者')
  'ForceShot' = @('毒刺蜂')
  'FreezeGrenade' = @('冰法師')
  'FreezingField' = @('冰法師','巨眼怪','巨型冰魔像','回聲巫師')
  'FrostBlade' = @('回聲忍者')
  'FuryBond' = @('回聲死靈法師')
  'GrandCross' = @('宇宙實體','烏龜王','回聲聖騎士')
  'GroundSlam' = @('獸人王','回聲狂戰士')
  'Harvest' = @('幽魂王','回聲死靈法師')
  'Haste' = @('回聲牧師')
  'Heal' = @('回聲牧師')
  'HighGuard' = @('回聲聖騎士')
  'HolyLight' = @('熾天使')
  'HydroVortex' = @('寄居蟹王','冰法師','巨型冰魔像','回聲巫師')
  'IceRelease' = @('巨型冰魔像','烏龜王')
  'IceShard' = @('寄居蟹王','冰法師','巨眼怪')
  'Icebolt' = @('寄居蟹王','冰法師')
  'JudgementBlade' = @('烏龜王')
  'JumpShot' = @('蜘蛛女王機器人')
  'LifeBond' = @('回聲聖騎士')
  'LifeDrain' = @('狼人')
  'LightningReflexes' = @('毒刺蜂','雷電貓','蝙蝠領主','回聲忍者')
  'LightningRelease' = @('雷電貓')
  'LightningStrike' = @('回聲忍者')
  'Marked' = @('回聲神槍手')
  'Meteor' = @('惡魔領主','回聲巫師')
  'NPC_ManaLeech' = @('蝙蝠領主','巨眼怪')
  'NPC_Poison' = @('蟲后','蜘蛛女王機器人')
  'NPC_SpellGuard' = @('向日葵妖精','娜迦','冰法師','熾天使')
  'NPC_SpikedShell' = @('仙人掌王')
  'NPC_SteelGuard' = @('寄居蟹王')
  'NPC_Venom' = @('娜迦','蝙蝠領主','蟲后','蠕蟲')
  'NPC_WideBleed' = @('狼人','蠍王','獸人王','獸人酋長')
  'NPC_WideBlind' = @('毒刺蜂','娜迦','死亡法師')
  'NPC_WideCurse' = @('殭屍獸人領主','熾天使','惡魔領主','巨眼怪','幽魂王','宇宙實體')
  'NPC_WideFreeze' = @('雷電貓','寄居蟹王','冰法師','巨眼怪','巨型冰魔像','烏龜王')
  'NPC_WidePoison' = @('仙人掌王','蝙蝠領主','蟲后','蠕蟲','蜘蛛女王機器人')
  'NPC_WideSilence' = @('向日葵妖精','幽魂王','死亡法師','宇宙實體')
  'NPC_WideStun' = @('野兔','惡魔領主','獸人酋長','蜘蛛女王機器人','巨型冰魔像','烏龜王')
  'PanicBurst' = @('毒刺蜂','回聲神槍手')
  'PiercingShot' = @('回聲神槍手')
  'PointBlankShot' = @('蜘蛛女王機器人')
  'PoisonGrenade' = @('蟲后','蠕蟲')
  'Reap' = @('幽魂王','回聲死靈法師')
  'SacredGround' = @('熾天使','回聲牧師')
  'Sanctuary' = @('熾天使','回聲牧師')
  'ShadowFeint' = @('回聲忍者')
  'ShadowRelease' = @('狼人','幽魂王','死亡法師','宇宙實體','蜘蛛女王機器人','回聲忍者')
  'ShadowSeal' = @('回聲忍者')
  'ShadowStep' = @('野兔','狼人','蝙蝠領主','死亡法師')
  'ShadowStrike' = @('宇宙實體')
  'ShieldBash' = @('仙人掌王','獸人王','巨眼怪','巨型冰魔像','回聲聖騎士')
  'ShieldThrow' = @('仙人掌王')
  'ShoutFury' = @('回聲狂戰士')
  'ShoutStun' = @('回聲狂戰士')
  'SlowTrap' = @('回聲神槍手')
  'Smite' = @('熾天使')
  'SmokeScreen' = @('毒刺蜂','蝙蝠領主','蠕蟲','蜘蛛女王機器人','回聲忍者')
  'SniperShot' = @('回聲神槍手')
  'SoulStrike' = @('死亡法師','回聲巫師')
  'SpearSlice' = @('仙人掌王','獸人王')
  'Stomp' = @('野兔','仙人掌王','蠍王','獸人王','殭屍獸人領主','巨型冰魔像')
  'StrafingVolley' = @('毒刺蜂','娜迦')
  'SummonWraith' = @('回聲死靈法師')
  'SuppressiveShot' = @('回聲神槍手')
  'Tempest' = @('雷電貓','獸人酋長','回聲巫師')
  'TetraVortexFire' = @('烏龜王')
  'ThunderStorm' = @('雷電貓','冰法師')
  'Thunderbolt' = @('毒刺蜂','雷電貓')
  'TurnUndead' = @('死亡法師')
  'TwistOfFate' = @('回聲忍者')
  'TwohandQuicken' = @('回聲狂戰士')
  'Unyielding' = @('回聲狂戰士')
  'VenomStrike' = @('蠕蟲')
  'VolatileBolt' = @('娜迦','宇宙實體')
  'Whirlwind' = @('寄居蟹王','獸人王','殭屍獸人領主')
  'WildCharge' = @('獸人酋長','回聲狂戰士')
  'Zeal' = @('回聲牧師')
}
# 技能英文 id -> 中文名
$script:SKZH = @{
  'Aegis' = '光之神盾'
  'Agility' = '專注'
  'ArcaneSigil' = '奧術符印'
  'AxeArc' = '雙重劈砍'
  'Barrier' = '聖盾'
  'Berserk' = '狂暴'
  'Blessing' = '祝禱'
  'BoneSpikes' = '骨刺'
  'ChainLightning' = '連鎖閃電'
  'Cloaking' = '隱形'
  'Consecration' = '祝聖'
  'Conviction' = '堅信光環'
  'Cyclone' = '氣旋'
  'Damnation' = '天譴'
  'Dark Exorcism' = '黑暗驅魔'
  'DarkClaw' = '暗爪'
  'DeathCoil' = '死亡纏繞'
  'DeathNova' = '死亡新星'
  'DeathSpiral' = '死亡螺旋'
  'Dispell' = '赦罪'
  'DivinePunishment' = '神罰'
  'EarthSpikes' = '大地尖刺'
  'Earthbolt' = '石箭術'
  'Earthquake' = '地震術'
  'EnergyShield' = '能量護盾'
  'Execute' = '處決'
  'Exorcism' = '驅魔'
  'ExplosiveGrenade' = '爆裂手榴彈'
  'FanFire' = '扇形射擊'
  'FieldCurse' = '放逐領域'
  'FieldDamage' = '失諧之井'
  'FieldHealing' = '共鳴之井'
  'FieldSilence' = '壓制領域'
  'FirePillar' = '火柱'
  'Fireball' = '火球術'
  'Firebolt' = '火箭術'
  'FlameOrb' = '火焰球'
  'ForceShot' = '強力射擊'
  'FreezeGrenade' = '冰凍手榴彈'
  'FreezingField' = '暴風雪'
  'FrostBlade' = '螺旋束縛'
  'FuryBond' = '盛怒連結'
  'GrandCross' = '聖十字'
  'GroundSlam' = '裂地'
  'Harvest' = '躍動收割'
  'Haste' = '加速'
  'Heal' = '治療術'
  'HighGuard' = '高階格擋'
  'HolyLight' = '聖光'
  'HydroVortex' = '水龍捲'
  'IceRelease' = '冰遁'
  'IceShard' = '冰晶'
  'Icebolt' = '冰箭術'
  'JudgementBlade' = '審判之刃'
  'JumpShot' = '跳躍射擊'
  'LifeBond' = '生命連結'
  'LifeDrain' = '生命汲取'
  'LightningReflexes' = '閃電反射'
  'LightningRelease' = '雷遁'
  'LightningStrike' = '瞬步'
  'Marked' = '標記目標'
  'Meteor' = '隕石'
  'NPC_ManaLeech' = '魔力汲取'
  'NPC_Poison' = '黏液射擊'
  'NPC_SpellGuard' = '法術護盾'
  'NPC_SpikedShell' = '荊棘'
  'NPC_SteelGuard' = '強化'
  'NPC_Venom' = '劇毒'
  'NPC_WideBleed' = '廣域流血'
  'NPC_WideBlind' = '廣域致盲'
  'NPC_WideCurse' = '廣域詛咒'
  'NPC_WideFreeze' = '廣域冰凍'
  'NPC_WidePoison' = '廣域劇毒'
  'NPC_WideSilence' = '廣域沉默'
  'NPC_WideStun' = '廣域暈眩'
  'PanicBurst' = '恐慌爆發'
  'PiercingShot' = '穿刺射擊'
  'PointBlankShot' = '近距射擊'
  'PoisonGrenade' = '毒氣手榴彈'
  'Reap' = '鐮割'
  'SacredGround' = '聖地'
  'Sanctuary' = '聖域'
  'ShadowFeint' = '迷蹤佯攻'
  'ShadowRelease' = '黑刃'
  'ShadowSeal' = '暗影印記'
  'ShadowStep' = '暗影步'
  'ShadowStrike' = '暗影打擊'
  'ShieldBash' = '盾擊'
  'ShieldThrow' = '擲盾'
  'ShoutFury' = '狂怒吼叫'
  'ShoutStun' = '威嚇怒吼'
  'SlowTrap' = '緩速陷阱'
  'Smite' = '制裁'
  'SmokeScreen' = '煙幕'
  'SniperShot' = '狙擊射擊'
  'SoulStrike' = '靈魂打擊'
  'SpearSlice' = '空氣斬'
  'Stomp' = '踐踏'
  'StrafingVolley' = '掃射齊發'
  'SummonWraith' = '召喚幽魂'
  'SuppressiveShot' = '壓制連射'
  'Tempest' = '怒雷風暴'
  'TetraVortexFire' = '超載·火焰'
  'ThunderStorm' = '雷暴'
  'Thunderbolt' = '落雷'
  'TurnUndead' = '驅逐不死'
  'TwistOfFate' = '命運扭轉'
  'TwohandQuicken' = '斧術加速'
  'Unyielding' = '不屈'
  'VenomStrike' = '毒液打擊'
  'VolatileBolt' = '不穩定彈'
  'Whirlwind' = '旋風斬'
  'WildCharge' = '狂野衝鋒'
  'Zeal' = '熱忱'
}

# 選王 → 勾技能。比手打英文 id 好用太多,而且不會打錯字。
# ── 「從技能清單挑」:左邊選職業、右邊勾技能(技能特效黑名單用)────────
function Pick-ClassSkills([System.Collections.ArrayList]$already) {
    $x = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="從技能清單挑要關特效的技能" Width="900" Height="660" WindowStartupLocation="CenterOwner"
        Background="#151C2B" FontFamily="Microsoft JhengHei UI" FontSize="14" Foreground="#E6EBF2" ShowInTaskbar="False">
  <Window.Resources>
    <Style TargetType="CheckBox"><Setter Property="Foreground" Value="#E6EBF2"/></Style>
    <Style TargetType="Button"><Setter Property="Foreground" Value="#E6EBF2"/><Setter Property="Background" Value="#22304A"/></Style>
  </Window.Resources>
  <DockPanel Margin="14">
    <TextBlock DockPanel.Dock="Top" Margin="0,0,0,8" TextWrapping="Wrap" Foreground="#8A94A8"
               Text="左邊選職業,右邊勾要關掉特效的技能(別人放的才會被關;你自己的永遠不受影響)。勾好按「加入清單」。"/>
    <DockPanel DockPanel.Dock="Bottom" Margin="0,10,0,0">
      <TextBlock x:Name="Cnt" DockPanel.Dock="Left" VerticalAlignment="Center" Foreground="#8FE3B0"/>
      <Button x:Name="Ok" DockPanel.Dock="Right" Content="加入清單" Width="130" Height="34"/>
      <Button x:Name="Cancel" DockPanel.Dock="Right" Content="取消" Width="90" Height="34" Margin="0,0,8,0"/>
      <Button x:Name="AllOfClass" DockPanel.Dock="Right" Content="全勾這個職業" Width="120" Height="34" Margin="0,0,8,0"/>
      <TextBlock/>
    </DockPanel>
    <Grid>
      <Grid.ColumnDefinitions><ColumnDefinition Width="230"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
      <ListBox x:Name="LB" Grid.Column="0" Background="#101827" Foreground="#E6EBF2" BorderBrush="#33405A"/>
      <ScrollViewer Grid.Column="1" Margin="10,0,0,0" VerticalScrollBarVisibility="Auto">
        <StackPanel x:Name="SP"/>
      </ScrollViewer>
    </Grid>
  </DockPanel>
</Window>
"@
    $d = [Windows.Markup.XamlReader]::Parse($x)
    if ($window.IsVisible) { $d.Owner = $window }
    $lb = $d.FindName("LB"); $sp = $d.FindName("SP"); $cnt = $d.FindName("Cnt")
    $picked = New-Object System.Collections.ArrayList
    foreach ($cl in $script:SKILL_DB) { [void]$lb.Items.Add($(if ($cl.base) { "★ " } else { "　 " }) + $cl.zh + "  " + $cl.en) }
    $refreshCnt = { $cnt.Text = "已勾 " + $picked.Count + " 個技能" }
    & $refreshCnt
    # ★★ 不要用 .GetNewClosure() 掛勾選事件(源實測 2026-08-25:勾了卻顯示「已勾 0 個」)——
    #   閉包只複製【建立當層】的區域變數,而 $picked/$cnt 在函式那一層,進到閉包裡全是 null,
    #   .Add() 打在 null 上、計數器也叫不到,整個勾選等於沒發生(同檔 3611 行早就記過這個坑)。
    #   純 scriptblock 保留定義處的作用域,看得到函式層變數 —— 跟一直正常的 $fill 同一個道理。
    $syncPick = {
        foreach ($c in $sp.Children) {
            if ($c -is [System.Windows.Controls.CheckBox]) {
                $id = [string]$c.Tag
                if ($c.IsChecked) { if (-not ($picked -contains $id)) { [void]$picked.Add($id) } }
                else { $picked.Remove($id) }
            }
        }
        $cnt.Text = "已勾 " + $picked.Count + " 個技能"
    }
    $fill = {
        & $syncPick          # 換職業前先把這一頁的勾記起來(跨頁保留)
        $sp.Children.Clear()
        if ($lb.SelectedIndex -lt 0) { return }
        $cl = $script:SKILL_DB[$lb.SelectedIndex]
        $h = New-Object System.Windows.Controls.TextBlock
        $h.Text = $cl.zh + "  (" + $cl.en + ")" + $(if ($cl.base) { "  基礎職業" } else { "  進階職業" })
        $h.FontWeight = "Bold"; $h.Margin = "0,0,0,8"; $h.Foreground = "#7FD4FF"; $h.FontSize = 15
        [void]$sp.Children.Add($h)
        foreach ($s in $cl.sk) {
            $c = New-Object System.Windows.Controls.CheckBox
            $inList = ($already -contains $s.i)
            $c.Content = $s.z + "   " + $s.e + "   (" + $s.i + ")" + $(if ($inList) { "   ← 已在清單裡" } else { "" })
            $c.Margin = "0,3,0,3"; $c.Foreground = $(if ($inList) { "#8A94A8" } else { "#E6EBF2" })
            $c.Tag = $s.i
            $c.IsChecked = ($picked -contains $s.i)
            $c.Add_Checked($syncPick)
            $c.Add_Unchecked($syncPick)
            [void]$sp.Children.Add($c)
        }
    }
    $lb.Add_SelectionChanged($fill)
    $lb.SelectedIndex = 0
    $btnAllClass = $d.FindName("AllOfClass")
    if ($btnAllClass) { $btnAllClass.Add_Click({ foreach ($c in $sp.Children) { if ($c -is [System.Windows.Controls.CheckBox]) { $c.IsChecked = $true } }; & $syncPick }) }
    $d.FindName("Ok").Add_Click({
        & $syncPick          # 保險:以畫面上的勾為準
        if ($picked.Count -eq 0) {
            [System.Windows.MessageBox]::Show("還沒勾任何技能。`n`n在右邊把要關特效的技能【勾起來】再按「加入清單」;`n不想一個一個挑就按「全勾這個職業」。", "沒有勾選", "OK", "Information") | Out-Null
            return
        }
        $d.DialogResult = $true
    })
    $d.FindName("Cancel").Add_Click({ $d.DialogResult = $false })
    if (-not $d.ShowDialog()) { return @() }
    return @($picked)
}
function Pick-BossSkills {
    $x = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="從王的清單挑技能" Width="880" Height="640" WindowStartupLocation="CenterOwner"
        Background="#151C2B" FontFamily="Microsoft JhengHei UI" FontSize="14" Foreground="#E6EBF2" ShowInTaskbar="False">
  <!-- ★ 這是【獨立的 Window】,吃不到主視窗的資源字典。而 WPF 內建的 CheckBox / Button 樣式會
       【明確設定】前景色(系統的黑),不會繼承上面那個 Foreground="#E6EBF2" ——
       所以深色底上的字會變成幾乎看不見的黑。這裡一定要自己補一份。 -->
  <Window.Resources>
    <Style TargetType="CheckBox">
      <Setter Property="Foreground" Value="#E6EBF2"/>
      <Setter Property="FontSize" Value="14"/>
      <Setter Property="Padding" Value="6,0,0,0"/>
    </Style>
    <Style TargetType="Button">
      <Setter Property="Foreground" Value="#E6EBF2"/>
      <Setter Property="Background" Value="#22304A"/>
      <Setter Property="BorderBrush" Value="#3A4A66"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Padding" Value="10,4"/>
    </Style>
    <Style TargetType="TextBlock">
      <Setter Property="Foreground" Value="#E6EBF2"/>
    </Style>
  </Window.Resources>
  <DockPanel Margin="14">
    <TextBlock DockPanel.Dock="Top" Margin="0,0,0,8" TextWrapping="Wrap" Foreground="#8A94A8"
               Text="左邊選王,右邊勾要預警的技能。勾好按「加入清單」,回去替它們挑音效。同一個技能好幾隻王共用時只會加一條。"/>
    <DockPanel DockPanel.Dock="Bottom" Margin="0,10,0,0">
      <TextBlock x:Name="Cnt" DockPanel.Dock="Left" VerticalAlignment="Center" Foreground="#8FE3B0"/>
      <Button x:Name="Ok" DockPanel.Dock="Right" Content="加入清單" Width="130" Height="34"/>
      <Button x:Name="Cancel" DockPanel.Dock="Right" Content="取消" Width="90" Height="34" Margin="0,0,8,0"/>
      <!-- ★ 這顆按鈕以前只存在於程式與提示文字裡,XAML 忘了加(源回報:訊息叫我按,畫面上卻找不到) -->
      <Button x:Name="AllOfBoss" DockPanel.Dock="Right" Content="全勾這隻王" Width="120" Height="34" Margin="0,0,8,0"/>
      <TextBlock/>
    </DockPanel>
    <Grid>
      <Grid.ColumnDefinitions><ColumnDefinition Width="250"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
      <ListBox x:Name="LB" Grid.Column="0" Background="#101827" Foreground="#E6EBF2" BorderBrush="#33405A"/>
      <ScrollViewer Grid.Column="1" Margin="10,0,0,0" VerticalScrollBarVisibility="Auto">
        <StackPanel x:Name="SP"/>
      </ScrollViewer>
    </Grid>
  </DockPanel>
</Window>
"@
    $d = [Windows.Markup.XamlReader]::Parse($x)
    if ($window.IsVisible) { $d.Owner = $window }
    $lb = $d.FindName("LB"); $sp = $d.FindName("SP"); $cnt = $d.FindName("Cnt")
    $picked = New-Object System.Collections.ArrayList     # 已勾的技能 id(跨王保留)
    foreach ($bo in $script:BOSS_DB) { [void]$lb.Items.Add(("Lv" + $bo.lv).PadRight(6) + $bo.zh) }
    $refreshCnt = { $cnt.Text = "已勾 " + $picked.Count + " 個技能" }
    & $refreshCnt
    # ★★ 不要用 .GetNewClosure() 掛勾選事件(源實測 2026-08-25:勾了卻顯示「已勾 0 個」)——
    #   閉包只複製【建立當層】的區域變數,而 $picked/$cnt 在函式那一層,進到閉包裡全是 null,
    #   .Add() 打在 null 上、計數器也叫不到,整個勾選等於沒發生(同檔 3611 行早就記過這個坑)。
    #   純 scriptblock 保留定義處的作用域,看得到函式層變數 —— 跟一直正常的 $fill 同一個道理。
    $syncPick = {
        foreach ($c in $sp.Children) {
            if ($c -is [System.Windows.Controls.CheckBox]) {
                $id = [string]$c.Tag
                if ($c.IsChecked) { if (-not ($picked -contains $id)) { [void]$picked.Add($id) } }
                else { $picked.Remove($id) }
            }
        }
        $cnt.Text = "已勾 " + $picked.Count + " 個技能"
    }
    $fill = {
        & $syncPick          # 換王之前先把這隻王的勾記起來(跨王保留)
        $sp.Children.Clear()
        if ($lb.SelectedIndex -lt 0) { return }
        $bo = $script:BOSS_DB[$lb.SelectedIndex]
        $h = New-Object System.Windows.Controls.TextBlock
        $h.Text = $bo.zh + "  (" + $bo.en + ")  Lv" + $bo.lv
        $h.FontWeight = "Bold"; $h.Margin = "0,0,0,8"; $h.Foreground = "#7FD4FF"; $h.FontSize = 15
        [void]$sp.Children.Add($h)
        foreach ($s in $bo.sk) {
            $c = New-Object System.Windows.Controls.CheckBox
            $others = @($script:SK2BOSS[$s.i] | Where-Object { $_ -ne $bo.zh })
            $c.Content = $s.z + "   (" + $s.i + ")" + $(if ($others.Count -gt 0) { "   ← 另有 " + $others.Count + " 隻王也會用" } else { "" })
            $c.Margin = "0,3,0,3"
            $c.Foreground = "#E6EBF2"   # 保險:就算樣式沒吃到也強制亮色
            if ($others.Count -gt 0) { $c.ToolTip = "也會用這招的王:" + ($others -join "、") }
            $c.Tag = $s.i
            $c.IsChecked = ($picked -contains $s.i)
            $c.Add_Checked($syncPick)
            $c.Add_Unchecked($syncPick)
            [void]$sp.Children.Add($c)
        }
    }
    $lb.Add_SelectionChanged($fill)
    $lb.SelectedIndex = 0
    # ★★ 網友回報「清單刪光後按加入沒反應」—— 用真實按鈕事件重現之後,程式邏輯沒壞;
    #    是【左邊點了王、右邊沒勾技能】就按「加入清單」:對話框靜靜關掉、一個字都不說,
    #    看起來就是沒反應。空清單時特別容易這樣(會以為點王就夠了)。
    #    改成:沒勾就不關窗、直接講;另給一顆「全勾這隻王」。
    $d.FindName("Ok").Add_Click({
        & $syncPick          # 保險:以畫面上的勾為準
        if ($picked.Count -eq 0) {
            [System.Windows.MessageBox]::Show("還沒勾任何技能。`n`n在右邊把要預警的技能【勾起來】再按「加入清單」;`n不想一個一個挑就按「全勾這隻王」。", "沒有勾選", "OK", "Information") | Out-Null
            return
        }
        $d.DialogResult = $true
    })
    # null-safe:XAML 少了這顆鈕時,舊寫法會在這裡把事件掛到 null 上(整個對話框的後續設定被中斷)
    $btnAllBoss = $d.FindName("AllOfBoss")
    if ($btnAllBoss) {
        $btnAllBoss.Add_Click({
            foreach ($c in $sp.Children) { if ($c -is [System.Windows.Controls.CheckBox]) { $c.IsChecked = $true } }
            & $syncPick
        })
    }
    $d.FindName("Cancel").Add_Click({ $d.DialogResult = $false })
    if (-not $d.ShowDialog()) { return @() }
    return @($picked)
}
# ── 技能特效黑名單(SpiritZh_fxskill.txt)────────────────────────
#   格式跟外掛端一致:enabled=0/1 + 一行一個技能 id(可帶 =註解,工具只留 id)。
#   ★ 整檔重建,但檔頭說明從範本抄 —— 使用者看到的檔案要跟範本長得一樣。
function FxSkillPath { $pd = PluginDir; if ($pd) { Join-Path $pd "SpiritZh_fxskill.txt" } else { "" } }
function Load-FxSkill {
    $p = FxSkillPath
    $ChkFxSkillOn.IsChecked = $false; $TFxSkill.Text = ""
    if (-not $p -or -not (Test-Path -LiteralPath $p)) { return }
    $ids = New-Object System.Collections.ArrayList
    try {
        foreach ($line in (Get-Content -LiteralPath $p -Encoding UTF8 -ErrorAction Stop)) {
            $s = $line.Trim().TrimStart([char]0xFEFF)
            if ($s.Length -eq 0 -or $s.StartsWith("//")) { continue }
            if ($s.StartsWith("#")) { [void]$ids.Add($s); continue }      # 使用者自己的註解行留著
            $k = $s; $eq = $s.IndexOf('='); if ($eq -gt 0) { $k = $s.Substring(0, $eq) }
            $cm = $k.IndexOf("//"); if ($cm -ge 0) { $k = $k.Substring(0, $cm) }
            $k = $k.Trim()
            if ($k.Length -eq 0) { continue }
            if ($k -ieq "enabled") { $v = $s.Substring($eq + 1).Trim(); $ChkFxSkillOn.IsChecked = ($v -eq "1" -or $v -ieq "true"); continue }
            $zh = $script:SKILL_ZH[$k]
            [void]$ids.Add($k + $(if ($zh) { "=          // " + $zh } else { "" }))
        }
    } catch { }
    $TFxSkill.Text = ($ids -join "`r`n")
}
function Save-FxSkill {
    $p = FxSkillPath; if (-not $p) { return }
    $out = New-Object System.Collections.ArrayList
    [void]$out.Add("// ═══ 技能特效黑名單 —— 這個檔由設定工具維護,也可以直接手改 ═══")
    [void]$out.Add("// 列在下面的技能,【別人放的】不生特效;你自己的永遠不受影響。只關特效,不關傷害/音效/數值。")
    [void]$out.Add("// 不知道技能代號:設定工具勾「收集模式」→ 進遊戲站一下 → 「從 log 匯入」。")
    [void]$out.Add("")
    [void]$out.Add("enabled=" + $(if ($ChkFxSkillOn.IsChecked) { "1" } else { "0" }))
    [void]$out.Add("")
    $seen = @{}
    foreach ($line in ($TFxSkill.Text -split "`r?`n")) {
        $s = $line.Trim()
        if ($s.Length -eq 0) { continue }
        if ($s.StartsWith("#")) { [void]$out.Add($s); continue }
        $k = $s; $eq = $s.IndexOf('='); if ($eq -gt 0) { $k = $s.Substring(0, $eq).Trim() }
        $cm = $k.IndexOf("//"); if ($cm -ge 0) { $k = $k.Substring(0, $cm).Trim() }
        if ($k.Length -eq 0 -or $seen.ContainsKey($k.ToLowerInvariant())) { continue }
        $seen[$k.ToLowerInvariant()] = $true
        $zh = $script:SKILL_ZH[$k]
        [void]$out.Add($k + "=" + $(if ($zh) { "          // " + $zh } else { "" }))
    }
    try { Set-Content -LiteralPath $p -Value $out -Encoding UTF8 -ErrorAction Stop }
    catch { $script:saveErr += "SpiritZh_fxskill.txt:寫入失敗(" + $_.Exception.Message + ")" }
}
# 技能 id → 中文(給清單旁的提示與「從技能清單挑」用)
$script:SKILL_ZH = @{}
foreach ($cl in $script:SKILL_DB) { foreach ($s in $cl.sk) { if (-not $script:SKILL_ZH.ContainsKey($s.i)) { $script:SKILL_ZH[$s.i] = $s.z } } }
$BFxSkillPick.Add_Click({
    $have = New-Object System.Collections.ArrayList
    foreach ($line in ($TFxSkill.Text -split "`r?`n")) { $k = $line.Trim(); if ($k.StartsWith("#")) { continue }; $eq = $k.IndexOf('='); if ($eq -gt 0) { $k = $k.Substring(0, $eq).Trim() }; if ($k) { [void]$have.Add($k) } }
    $ids = @(Pick-ClassSkills $have)
    if ($ids.Count -eq 0) { $LblStatus.Text = "狀態:沒有加入任何技能(對話框裡要先【勾】技能再按「加入清單」)"; return }
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append($TFxSkill.Text.TrimEnd())
    $add = 0
    foreach ($id in $ids) {
        if ($have -contains $id) { continue }
        if ($sb.Length -gt 0) { [void]$sb.Append("`r`n") }
        $zh = $script:SKILL_ZH[$id]
        [void]$sb.Append($id + "=" + $(if ($zh) { "          // " + $zh } else { "" })); $add++
    }
    $TFxSkill.Text = $sb.ToString(); Mark-Dirty $BFxSkillPick
    $LblStatus.Text = "狀態:加了 " + $add + " 個技能(其餘已在清單裡)—— 記得按「套用設定」"
})
# 從 log 撈 [fxskilldiag] 印出來的技能 id(只收「玩家放的」,怪物的那幾行外掛會標註,跳過)
$BFxSkillImport.Add_Click({
    $pd = PluginDir
    if (-not $pd) { Show-Msg "找不到遊戲" "先按上方的「瀏覽」指定遊戲資料夾。" "warn"; return }
    $log = Join-Path (Split-Path -Parent $pd) "LogOutput.log"
    if (-not (Test-Path -LiteralPath $log)) { Show-Msg "找不到 log" ("讀不到:`n" + $log) "warn"; return }
    $found = New-Object System.Collections.ArrayList; $skipMon = 0
    try {
        foreach ($line in (Get-Content -LiteralPath $log -Encoding UTF8 -ErrorAction Stop)) {
            if ($line -notmatch '\[fxskilldiag\]') { continue }
            if ($line -match '怪物/王') { $skipMon++; continue }
            if ($line -match '\[fxskilldiag\]\s*([A-Za-z0-9_]+)=\s*//\s*(.*?)\s+←') {
                $id = $Matches[1].Trim(); $zh = $Matches[2].Trim()
                if ($id.Length -gt 0 -and -not ($found | Where-Object { $_.id -eq $id })) { [void]$found.Add(@{ id = $id; zh = $zh }) }
            }
        }
    } catch { Show-Msg "讀取失敗" $_.Exception.Message "error"; return }
    if ($found.Count -eq 0) {
        Show-Msg "log 裡沒有技能紀錄" "先勾「收集模式」,按套用,然後進遊戲到人多的地方站一下,再回來按這個按鈕。`n`n※ 遊戲每次啟動會清空 log,所以要在【同一次遊戲】收集完再匯入。" "warn"; return
    }
    $have = @{}
    foreach ($line in ($TFxSkill.Text -split "`r?`n")) { $k = $line.Trim(); $eq = $k.IndexOf('='); if ($eq -gt 0) { $k = $k.Substring(0, $eq).Trim() }; if ($k) { $have[$k.ToLowerInvariant()] = $true } }
    $add = 0; $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append($TFxSkill.Text.TrimEnd())
    foreach ($f in $found) {
        if ($have.ContainsKey($f.id.ToLowerInvariant())) { continue }
        if ($sb.Length -gt 0) { [void]$sb.Append("`r`n") }
        [void]$sb.Append("# " + $f.zh); [void]$sb.Append("`r`n"); [void]$sb.Append($f.id); $add++
    }
    $TFxSkill.Text = $sb.ToString(); Mark-Dirty $BFxSkillImport
    $LblStatus.Text = "狀態:從 log 匯入 " + $add + " 個技能(略過怪物/王的 " + $skipMon + " 筆)—— 把不想關的行刪掉,再按「套用設定」"
})
# ── 六大能力值維持英文(SpiritZh_keep.txt 的 basestat 標記 + 18 個字)────
#   這段從舊工具 settings.ps1 搬過來:它用「// basestat=zh|en」標記行記住選擇,
#   選 en 就把 18 個縮寫/全名寫進保留原文清單。★ 其他使用者自己加的保留字一律不動。
$script:BaseStatWords = @("Strength","Str","STR","Agility","Agi","AGI","Vitality","Vit","VIT","Intelligence","Int","INT","Dexterity","Dex","DEX","Luck","Luk","LUK")
function KeepPath { $pd = PluginDir; if ($pd) { Join-Path $pd "SpiritZh_keep.txt" } else { "" } }
function Load-KeepStat {
    $ChkBaseStatEn.IsChecked = $false
    $p = KeepPath; if (-not $p -or -not (Test-Path -LiteralPath $p)) { return }
    try {
        foreach ($line in (Get-Content -LiteralPath $p -Encoding UTF8 -ErrorAction Stop)) {
            if ($line -match '^\s*//\s*basestat\s*=\s*en') { $ChkBaseStatEn.IsChecked = $true; return }
        }
    } catch { }
}
function Save-KeepStat {
    $p = KeepPath; if (-not $p) { return }
    $lines = @()
    if (Test-Path -LiteralPath $p) { try { $lines = @(Get-Content -LiteralPath $p -Encoding UTF8 -ErrorAction Stop) } catch { $script:saveErr += "SpiritZh_keep.txt:讀取失敗(" + $_.Exception.Message + ")"; return } }
    $en = [bool]$ChkBaseStatEn.IsChecked
    $wordSet = @{}; foreach ($w in $script:BaseStatWords) { $wordSet[$w] = $true }
    $out = New-Object System.Collections.ArrayList
    $hadMark = $false
    foreach ($l in $lines) {
        $t = $l.Trim().TrimStart([char]0xFEFF)
        if ($t -match '^//\s*basestat\s*=') { [void]$out.Add("// basestat=" + $(if ($en) { "en" } else { "zh" })); $hadMark = $true; continue }
        if ($wordSet.ContainsKey($t)) { continue }    # 舊的能力值字先拿掉,下面依勾選決定要不要放回去
        [void]$out.Add($l)
    }
    if (-not $hadMark) { [void]$out.Add("// basestat=" + $(if ($en) { "en" } else { "zh" })) }
    if ($en) { foreach ($w in $script:BaseStatWords) { [void]$out.Add($w) } }
    try { Set-Content -LiteralPath $p -Value $out -Encoding UTF8 -ErrorAction Stop }
    catch { $script:saveErr += "SpiritZh_keep.txt:寫入失敗(" + $_.Exception.Message + ")" }
}
function Load-BossAlert {
    $p = BossAlertPath
    $script:baRules.Clear(); $script:baAll = ""
    $ChkBaOn.IsChecked = $false; $ChkBaBanner.IsChecked = $true
    $TBaVol.Text = "1.0"; $TBaCd.Text = "3000"
    Reset-ArrowUi
    if ($p -and (Test-Path -LiteralPath $p)) {
        try {
            foreach ($line in (Get-Content -LiteralPath $p -Encoding UTF8 -ErrorAction Stop)) {
                $s = $line.Trim().TrimStart([char]0xFEFF)
                if ($s.Length -eq 0 -or $s.StartsWith("//") -or $s.StartsWith("#")) { continue }
                $eq = $s.IndexOf('=')
                if ($eq -le 0) { continue }
                $k = $s.Substring(0, $eq).Trim(); $v = $s.Substring($eq + 1).Trim()
                # ★ 剝掉行內註解:範本長成「Berserk=          // 狂暴」,不剝的話音效檔名會變成「// 狂暴」。
                #   外掛端 LoadBossAlert 也做同一件事,兩邊必須一致。
                $cm = $v.IndexOf("//")
                if ($cm -ge 0) { $v = $v.Substring(0, $cm).Trim() }
                # ★★ 不能用 switch + continue:PowerShell 的 continue 在 switch 裡只結束【該分支】,
                #    不會跳出外層的 foreach —— 固定鍵會被下面的 if 再收成一條技能規則(實測抓到)。
                #    改成一個布林旗標明確標記「這行已經處理掉了」。
                $handled = $true
                switch ($k.ToLowerInvariant()) {
                    "enabled"  { $ChkBaOn.IsChecked = ($v -eq "1") }
                    "banner"   { $ChkBaBanner.IsChecked = ($v -ne "0") }
                    "volume"   { $TBaVol.Text = $v }
                    "cooldown" { $TBaCd.Text = $v }
                    "*"        { $script:baAll = $v }
                    # ── 王方位箭頭(v3.75)。★ 一定要在這裡接住:不接的話 default 分支會把
                    #    bossarrow=1 當成一條「技能 id = bossarrow」收進清單,存檔時再以技能規則寫回 ——
                    #    箭頭設定整組消失,清單裡多出八條怪東西。
                    "bossarrow"         { $ChkArrowOn.IsChecked = ($v -eq "1") }
                    "bossarrowminiboss" { $ChkArrowMini.IsChecked = ($v -eq "1") }
                    "bossarrowradius"   { $TArrowRad.Text = $v }
                    "bossarrowsize"     { $TArrowSize.Text = $v }
                    "bossarrowmax"      { $i2 = 3; if ([int]::TryParse($v, [ref]$i2)) { $CboArrowMax.SelectedIndex = [Math]::Max(0, [Math]::Min(3, $i2 - 1)) } }
                    "bossarrowfar"      { $TArrowFar.Text = $v }
                    "bossarrowimg"      { Set-ArrowImg $v }
                    "bossarrowcolor"    { $script:arrowColor = $(if ($v) { $v } else { "#FF6B59" }); $BArrowColor.Content = $script:arrowColor }
                    default    { $handled = $false }
                }
                if ($handled) { continue }
                # ★ 範本改成【依王分組】之後,同一個技能會出現在好幾隻王底下(例如「狂暴」20 隻王都有)。
                #   讀進來一定要合併,不然清單會冒出上百列重複。
                #   合併規則:有值的贏過空的(範本裡重複那幾行是空的);兩邊都有值時保留先出現的。
                if ($k.Length -gt 0) {
                    $hit = $null
                    foreach ($r in $script:baRules) { if (([string]$r.id).ToLowerInvariant() -eq $k.ToLowerInvariant()) { $hit = $r; break } }
                    if ($hit) { if ($v.Length -gt 0 -and -not $hit.snd) { $hit.snd = $v } }
                    else { [void]$script:baRules.Add(@{ id = $k; snd = $v }) }
                }
            }
        } catch { $script:saveErr += "SpiritZh_bossalert.txt:讀取失敗(" + $_.Exception.Message + ")" }
    }
    $script:cfgLoaded["bossalert"] = $true
    $BtnBaAll.Content = $(if ($script:baAll) { $script:baAll } else { $NOBA })
    Refresh-BaList
}
function Save-BossAlert {
    if (-not $script:cfgLoaded["bossalert"]) { $script:saveErr += "SpiritZh_bossalert.txt:沒讀成功過,這次不寫入"; return }
    $p = BossAlertPath
    if (-not $p) { return }
    $inv = [Globalization.CultureInfo]::InvariantCulture
    $vol = 1.0
    try { $vol = [double]::Parse($TBaVol.Text.Trim(), $inv) } catch { $vol = 1.0 }
    if ($vol -lt 0.05) { $vol = 0.05 } elseif ($vol -gt 3.0) { $vol = 3.0 }
    $out = New-Object System.Collections.ArrayList
    [void]$out.Add("// ═══ 王技提示音 —— 這個檔由設定工具維護,也可以直接手改 ═══")
    [void]$out.Add("// 王(Boss / 精英)開始詠唱時播提示音。收集技能名稱:在 SpiritZh_view.txt 設 bossdiag=1 去打王,")
    [void]$out.Add("// log 會印出可以直接貼進來的行,或用設定工具的「從 log 匯入」。")
    [void]$out.Add("")
    [void]$out.Add("enabled=" + $(if ($ChkBaOn.IsChecked) { "1" } else { "0" }))
    [void]$out.Add("banner=" + $(if ($ChkBaBanner.IsChecked) { "1" } else { "0" }))
    [void]$out.Add("volume=" + $vol.ToString("0.0#", $inv))
    [void]$out.Add("cooldown=" + [string](ClampInt $TBaCd.Text 0 60000 3000))
    [void]$out.Add("")
    # ── 王方位箭頭(v3.75)。這個檔是整檔重建,所以【每一個】鍵都要在這裡寫,少寫一個就等於刪掉它。
    [void]$out.Add("// 王方位箭頭:繞著角色一圈指向附近的王。★ 王沒出現在你附近時指不出來(客戶端沒那筆資料),不是壞掉。")
    [void]$out.Add("bossarrow=" + $(if ($ChkArrowOn.IsChecked) { "1" } else { "0" }))
    [void]$out.Add("bossarrowminiboss=" + $(if ($ChkArrowMini.IsChecked) { "1" } else { "0" }))
    [void]$out.Add("bossarrowradius=" + [string](ClampInt $TArrowRad.Text 20 600 110))
    [void]$out.Add("bossarrowsize=" + [string](ClampInt $TArrowSize.Text 8 256 46))
    [void]$out.Add("bossarrowmax=" + [string]($CboArrowMax.SelectedIndex + 1))
    [void]$out.Add("bossarrowfar=" + [string](ClampInt $TArrowFar.Text 0 9999 0))
    [void]$out.Add("bossarrowimg=" + $script:arrowImg)
    [void]$out.Add("bossarrowcolor=" + $script:arrowColor)
    [void]$out.Add("")
    if ($script:baAll) { [void]$out.Add("*=" + $script:baAll) }
    $seen = @{}
    foreach ($r in $script:baRules) {
        $id = ([string]$r.id).Trim()
        if ($id.Length -eq 0 -or $id -eq "*") { continue }
        if ($seen.ContainsKey($id.ToLowerInvariant())) { continue }   # 同一個技能只留一條
        $seen[$id.ToLowerInvariant()] = $true
        [void]$out.Add($id + "=" + ([string]$r.snd).Trim())
    }
    try { Set-Content -LiteralPath $p -Value $out -Encoding UTF8 -ErrorAction Stop }
    catch { $script:saveErr += "SpiritZh_bossalert.txt:寫入失敗(" + $_.Exception.Message + ")" }
}
# 從音效資料夾挑一個檔。★ 沒有現成的通用挑檔對話框(Pick-GameItem 是物品專用),
#   所以用 OpenFileDialog 直接開在音效資料夾 —— 順便讓使用者可以從別處拉檔進來。
# ── 王方位箭頭 UI 狀態 ──────────────────────────────────────────
$script:arrowImg = "boss_arrow.png"; $script:arrowColor = "#FF6B59"
function Reset-ArrowUi {
    $ChkArrowOn.IsChecked = $false; $ChkArrowMini.IsChecked = $false
    $TArrowRad.Text = "110"; $TArrowSize.Text = "46"; $CboArrowMax.SelectedIndex = 2; $TArrowFar.Text = "0"
    $script:arrowColor = "#FF6B59"; $BArrowColor.Content = $script:arrowColor
    Set-ArrowImg "boss_arrow.png"
}
# 依檔名把下拉對到內建樣式;不是內建的就落在「自己的圖…」並把檔名顯示在旁邊
function Set-ArrowImg([string]$file) {
    $f = ("" + $file).Trim()
    if ($f.Length -eq 0) { $f = "boss_arrow.png" }
    $script:arrowImg = $f
    $script:arrowImgSetting = $true
    try {
        $hit = -1
        for ($i = 0; $i -lt $CboArrowImg.Items.Count; $i++) { if (([string]$CboArrowImg.Items[$i].Tag) -eq $f) { $hit = $i; break } }
        if ($hit -ge 0) { $CboArrowImg.SelectedIndex = $hit; $LblArrowImg.Text = "" }
        else { $CboArrowImg.SelectedIndex = $CboArrowImg.Items.Count - 1; $LblArrowImg.Text = "檔案:" + $f }
    } finally { $script:arrowImgSetting = $false }
}
$CboArrowImg.Add_SelectionChanged({
    if ($script:arrowImgSetting) { return }
    $it = $CboArrowImg.SelectedItem
    if ($null -eq $it) { return }
    $tag = [string]$it.Tag
    if ($tag -ne "?") { $script:arrowImg = $tag; $LblArrowImg.Text = ""; Mark-Dirty $CboArrowImg; return }
    # 自己的圖:開在 SpiritZh_ui 資料夾挑 PNG,只記檔名(外掛只在那個資料夾找)
    $pd = PluginDir
    $ui = $(if ($pd) { Join-Path $pd "SpiritZh_ui" } else { "" })
    $d = New-Object System.Windows.Forms.OpenFileDialog
    $d.Filter = "PNG 圖檔 (*.png)|*.png"
    if ($ui -and (Test-Path -LiteralPath $ui)) { $d.InitialDirectory = $ui }
    if ($d.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $name = [System.IO.Path]::GetFileName($d.FileName)
        # 不在 SpiritZh_ui 裡的話幫他複製進去(外掛只認那個資料夾)
        if ($ui -and (Test-Path -LiteralPath $ui)) {
            $dst = Join-Path $ui $name
            if (-not (Test-Path -LiteralPath $dst)) { try { Copy-Item -LiteralPath $d.FileName -Destination $dst -ErrorAction Stop } catch { Show-Msg "複製失敗" $_.Exception.Message "warn" } }
        }
        Set-ArrowImg $name; Mark-Dirty $CboArrowImg
    } else { Set-ArrowImg $script:arrowImg }   # 取消 → 下拉回到原本的樣式
})
$BArrowColor.Add_Click({
    $r = Pick-CdColor $script:arrowColor
    if ($null -ne $r) {
        if ($r -eq "") { $r = "#FF6B59" }
        $script:arrowColor = $r; $BArrowColor.Content = $r; Mark-Dirty $BArrowColor
    }
})
function Pick-BaSound {
    $sd = SoundDir
    if (-not $sd) { Show-Msg "找不到遊戲" "先按上方的「瀏覽」指定遊戲資料夾。" "warn"; return $null }
    if (-not (Test-Path -LiteralPath $sd)) { New-Item -ItemType Directory -Path $sd -Force | Out-Null }
    $d = New-Object System.Windows.Forms.OpenFileDialog
    $d.Filter = "音效檔 (*.wav;*.mp3)|*.wav;*.mp3"
    $d.Title = "選一個提示音"
    $d.InitialDirectory = $sd
    if ($d.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return $null }
    $src = $d.FileName
    $name = [System.IO.Path]::GetFileName($src)
    try {
        # 外掛只認 SpiritZh_sounds\ 裡的檔名,從別處挑的要複製進去
        $dst = Join-Path $sd $name
        if ((Resolve-Path -LiteralPath $src).Path -ne $dst) {
            if ((Test-Path -LiteralPath $dst) -and -not (Confirm-Msg "已經有同名的檔" ("SpiritZh_sounds 裡已經有「" + $name + "」了,要覆蓋嗎?") "覆蓋" "取消")) { return $null }
            Copy-Item -LiteralPath $src -Destination $dst -Force
        }
    } catch { Show-Msg "複製失敗" ("沒辦法把音效複製進 SpiritZh_sounds:`n" + $_.Exception.Message) "error"; return $null }
    return $name
}
$BtnBaAll.Add_Click({
    $v = Pick-BaSound
    if ($null -eq $v) { return }
    $script:baAll = $v
    $BtnBaAll.Content = $script:baAll
    Refresh-BaList   # 新複製進來的檔要出現在每一列的下拉裡
    Mark-Dirty $BtnBaAll
})
$BtnBaAllClear.Add_Click({ $script:baAll = ""; $BtnBaAll.Content = $NOBA; Mark-Dirty $BtnBaAllClear })
$BtnBaPick.Add_Click({
    $ids = @(Pick-BossSkills)
    if ($ids.Count -eq 0) { $LblStatus.Text = "狀態:沒有加入任何技能(對話框裡要先【勾】技能再按「加入清單」)"; return }
    $have = @{}
    foreach ($r in $script:baRules) { $have[([string]$r.id).ToLowerInvariant()] = $true }
    $add = 0
    foreach ($id in $ids) { if (-not $have.ContainsKey($id.ToLowerInvariant())) { [void]$script:baRules.Add(@{ id = $id; snd = "" }); $add++ } }
    Refresh-BaList; Mark-Dirty $BtnBaPick
    $LblStatus.Text = "狀態:加了 " + $add + " 條王技(其餘已在清單裡)—— 記得替每條挑提示音,再按「套用設定」"
})
$BtnBaAdd.Add_Click({
    [void]$script:baRules.Add(@{ id = ""; snd = "" })
    Refresh-BaList; Mark-Dirty $BtnBaAdd
})
$BtnBaSounds.Add_Click({
    $sd = SoundDir
    if (-not $sd) { Show-Msg "找不到遊戲" "先按上方的「瀏覽」指定遊戲資料夾。" "warn"; return }
    if (-not (Test-Path -LiteralPath $sd)) { New-Item -ItemType Directory -Path $sd -Force | Out-Null }
    Start-Process explorer.exe (Q $sd)   # 不包引號的話,使用者名稱有空格就會被拆成好幾個參數
})
# 從 log 撈 [bossdiag] 印出來的王技 id
# 全部清空(源需求 2026-08-25:規則多的時候一條一條刪太累)。破壞性動作 → 先問一次。
$BtnBaClear.Add_Click({
    if ($script:baRules.Count -eq 0) { $LblStatus.Text = "狀態:清單本來就是空的"; return }
    $ans = [System.Windows.MessageBox]::Show(
        ("確定要清空「個別技能」的全部 " + $script:baRules.Count + " 條規則嗎?`n`n" +
         "‧只清這份清單,音效檔不會被刪。`n" +
         "‧上面的「通用提示音」不受影響。`n" +
         "‧清完記得按下面的「套用設定」才會寫進設定檔。"),
        "全部清空", "YesNo", "Warning")
    if ($ans -ne "Yes") { return }
    $script:baRules.Clear()
    Refresh-BaList
    Mark-Dirty $BtnBaClear
    $LblStatus.Text = "狀態:已清空個別技能規則(記得按「套用設定」)"
})
$BtnBaImport.Add_Click({
    $pd = PluginDir
    if (-not $pd) { Show-Msg "找不到遊戲" "先按上方的「瀏覽」指定遊戲資料夾。" "warn"; return }
    $log = Join-Path (Split-Path -Parent $pd) "LogOutput.log"
    if (-not (Test-Path -LiteralPath $log)) { Show-Msg "找不到 log" ("讀不到:`n" + $log) "warn"; return }
    $found = New-Object System.Collections.ArrayList
    try {
        foreach ($line in (Get-Content -LiteralPath $log -Encoding UTF8 -ErrorAction Stop)) {
            # [bossdiag] 王技 #3:Enrage=  // 狂暴 ← Giant Magma Golem
            if ($line -notmatch '\[bossdiag\]') { continue }
            if ($line -match '王技\s*#\d+\s*[::]\s*([^=]+)=') {
                $id = $Matches[1].Trim()
                if ($id.Length -gt 0 -and $found -notcontains $id) { [void]$found.Add($id) }
            }
        }
    } catch { Show-Msg "讀取失敗" $_.Exception.Message "error"; return }
    if ($found.Count -eq 0) {
        Show-Msg "log 裡沒有王技紀錄" "先勾「收集模式」,然後去打一場王(Boss 或精英),再回來按這個按鈕。`n`n※ 遊戲每次啟動會清空 log,所以要在【同一次遊戲】收集完再匯入。" "warn"
        return
    }
    $已有 = @{}
    foreach ($r in $script:baRules) { $已有[([string]$r.id).ToLowerInvariant()] = $true }
    $add = 0
    foreach ($id in $found) { if (-not $已有.ContainsKey($id.ToLowerInvariant())) { [void]$script:baRules.Add(@{ id = $id; snd = "" }); $add++ } }
    Refresh-BaList; Mark-Dirty $BtnBaImport
    Show-Msg "匯入完成" ("log 裡找到 " + $found.Count + " 個王技,新增了 " + $add + " 條(其餘已經在清單裡)。`n`n接下來替每一條挑提示音,再按「套用設定」。") "info"
})

function Load-Fonts {
    $CboFont.Items.Clear()
    [void]$CboFont.Items.Add($DEFAULT_FONT)
    try {
        $col = New-Object System.Drawing.Text.InstalledFontCollection
        foreach ($fam in ($col.Families | Sort-Object Name)) { [void]$CboFont.Items.Add($fam.Name) }
    } catch {}
    $CboFont.SelectedIndex = 0
}
function Load-Config {
    $pd = PluginDir; if (-not $pd) { return }
    $v = Read-KV (Join-Path $pd "SpiritZh_view.txt")
    if ($null -ne $v) {   # 讀不到(被鎖)就不動這一段
    $script:cfgLoaded["view"] = $true
    $ChkHide.IsChecked   = ($v["hideplayers"] -eq "1")
    $ChkParty.IsChecked  = ($v["showparty"]  -ne "0")
    $ChkGuild.IsChecked  = ($v["showguild"]  -ne "0")
    $ChkFriend.IsChecked = ($v["showfriends"] -ne "0")
    $ChkNum.IsChecked    = ($v["hidenum"] -eq "1")
    $ChkBaDiag.IsChecked = ($v["bossdiag"] -eq "1")
    $ChkZero.IsChecked   = ($v["hidezero"] -ne "0")          # 預設【開】(外掛端同)
    $civ = 1; if ($v["chatinvite"] -and [int]::TryParse($v["chatinvite"], [ref]$civ)) { $civ = [Math]::Max(0, [Math]::Min(2, $civ)) } else { $civ = 1 }
    $CboChatInvite.SelectedIndex = $civ
    $ChkMapWrap.IsChecked = ($v["mapnamewrap"] -eq "1")
    $CboBuffPos.SelectedIndex = (ClampInt $v["buffpos"] 0 2 0)
    $TBuffScale.Text = $(if ($v["buffscale"]) { $v["buffscale"] } else { "1.0" })
    $TBuffX.Text = [string](ClampInt $v["buffx"] -4000 4000 0); $TBuffY.Text = [string](ClampInt $v["buffy"] -4000 4000 0)
    $TDebuffX.Text = [string](ClampInt $v["debuffx"] -4000 4000 0); $TDebuffY.Text = [string](ClampInt $v["debuffy"] -4000 4000 0)
    $TMainX.Text = [string](ClampInt $v["mainx"] -4000 4000 0); $TMainY.Text = [string](ClampInt $v["mainy"] -4000 4000 0)
    $ChkPartyBuff.IsChecked = ($v["partybuff"] -ne "0")
    $TPartyBuffKey.Text = [string]$v["partybuffkey"]
    $ChkFxSkillDiag.IsChecked = ($v["fxskilldiag"] -eq "1")
    $ChkDgView.IsChecked  = ($v["viewdiag"] -eq "1")
    $ChkDgSfx.IsChecked   = ($v["sfxdiag"] -eq "1")
    $ChkDgZero.IsChecked  = ($v["zerodiag"] -eq "1")
    $ChkDgSearch.IsChecked = ($v["searchdiag"] -eq "1")
    $ChkDgArrow.IsChecked = ($v["bossarrowdiag"] -eq "1")
    $TDgWatch.Text = $(if ($v["watch"]) { $v["watch"] } else { "" })
    Load-FxSkill; Load-KeepStat
    $ChkFx.IsChecked     = ($v["hidefx"]  -eq "1")
    $ChkMute.IsChecked   = ($v["mutefx"]  -eq "1")
    $ChkFull.IsChecked   = ($v["hidefull"] -eq "1")
    $ChkShadow.IsChecked = ($v["shadows"] -eq "0")
    $ChkAnim.IsChecked   = ($v["animcull"] -eq "1")
    $ChkFxMine.IsChecked = ($v["fxonlymine"] -eq "1")
    $TxtScale.Text = $(if ($v["renderscale"]) { $v["renderscale"] } else { "0" })
    $TxtSharp.Text = $(if ($v["sharpness"]) { $v["sharpness"] } else { "0" })
    $TxtFps.Text   = $(if ($v["fpslimit"]) { $v["fpslimit"] } else { "0" })
    $up = ("" + $v["upscaler"]).ToUpperInvariant()
    $CboUp.SelectedIndex = $(if ($up -eq "FSR") { 1 } elseif ($up -eq "STP") { 2 } else { 0 })
    $CboVs.SelectedIndex = $(if ($v["vsync"] -eq "0") { 1 } elseif ($v["vsync"] -eq "1") { 2 } else { 0 })
    $CboMsaa.SelectedIndex = switch ("" + $v["msaa"]) { "1" { 1 } "2" { 2 } "4" { 3 } "8" { 4 } default { 0 } }
    $script:cdMask = "" + $v["cdmaskcolor"]; $script:cdText = "" + $v["cdtextcolor"]
    $BtnCdMask.Content = $(if ($script:cdMask) { $script:cdMask } else { "(不改)" })
    $BtnCdText.Content = $(if ($script:cdText) { $script:cdText } else { "(不改)" })
    $TxtCdAlpha.Text = $(if ($v["cdmaskalpha"]) { $v["cdmaskalpha"] } else { "-1" })
    $TxtCdX.Text = $(if ($v["cdtextx"]) { $v["cdtextx"] } else { "0" })
    $TxtCdY.Text = $(if ($v["cdtexty"]) { $v["cdtexty"] } else { "0" })
    $TxtCdSize.Text = $(if ($v["cdtextsize"]) { $v["cdtextsize"] } else { "0" })
    }
    $g = Read-KV (Join-Path $pd "SpiritZh_gui.txt")
    if ($null -ne $g) {
        $script:cfgLoaded["gui"] = $true
        $ChkSplash.IsChecked = ($g["splash"] -ne "0")
        $TxtVol.Text = $(if ($g["splashvol"]) { $g["splashvol"] } else { "35" })
        $uk = 1.0; if ($g["uiscale"]) { try { $uk = [double]::Parse($g["uiscale"], [System.Globalization.CultureInfo]::InvariantCulture) } catch { $uk = 1.0 } }
        Set-UiScaleCombo $uk
        if (-not $script:uiScaleApplied) { $script:uiScaleApplied = $true; Apply-UiScale $uk }
        $script:tutorialDone = ($g["tutorial"] -eq "1")
        $script:updMode = $(if ($g["update"]) { $g["update"] } else { "notify" })
        $CboUpdMode.SelectedIndex = $(switch ($script:updMode) { "auto" { 1 } "off" { 2 } default { 0 } })
    }
    $m = ""
    try { $m = (Get-Content -LiteralPath (Join-Path $pd "SpiritZh_mode.txt") -Raw -ErrorAction Stop).Trim() } catch {}
    if ($m.Contains("full")) { $RbM1.IsChecked = $true }
    elseif ($m.Contains("chinese")) { $RbM3.IsChecked = $true }
    elseif ($m.Contains("off") -or $m.Contains("none") -or $m.Contains("raw")) { $RbM4.IsChecked = $true }
    else { $RbM2.IsChecked = $true }
    $script:fontFilePath = ""
    $fLine = ""
    try {
        foreach ($l in (Get-Content -LiteralPath (Join-Path $pd "SpiritZh_font.txt") -Encoding UTF8 -ErrorAction Stop)) {
            $s2 = $l.Trim().TrimStart([char]0xFEFF)
            if ($s2.Length -gt 0 -and -not $s2.StartsWith("//") -and -not $s2.StartsWith("#")) { $fLine = $s2; break }
        }
    } catch {}
    if ($fLine -eq "") { $CboFont.SelectedIndex = 0; $LblFontNow.Text = "目前:遊戲預設" }
    elseif ($fLine.Contains("\") -or $fLine.Contains("/")) {
        $script:fontFilePath = $fLine
        $LblFontNow.Text = "目前:字型檔 " + [System.IO.Path]::GetFileName(($fLine -split '#')[0])
    }
    else {
        $ix = $CboFont.Items.IndexOf($fLine)
        if ($ix -ge 0) { $CboFont.SelectedIndex = $ix }
        $LblFontNow.Text = "目前:" + $fLine
    }
}
function ClampInt([string]$t, [int]$lo, [int]$hi, [int]$def) {
    $n = 0; if ([int]::TryParse(("" + $t).Trim(), [ref]$n)) { [Math]::Max($lo, [Math]::Min($hi, $n)) } else { $def }
}
# 使用者在整數欄位打小數(85.5)時,ClampInt 的 [int]::TryParse 會整個失敗而落回預設值 ——
# 那等於把他打的數字丟掉。這個版本先用 double 解析再四捨五入,只有真的不是數字才用預設。
function ClampDblInt([string]$t, [int]$lo, [int]$hi, [int]$def) {
    $n = 0.0
    if ([double]::TryParse(("" + $t).Trim(), [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$n)) {
        return [int][Math]::Max($lo, [Math]::Min($hi, [Math]::Round($n)))
    }
    return $def
}
function ClampDbl([string]$t, [double]$lo, [double]$hi, [double]$def) {
    $n = 0.0
    if ([double]::TryParse(("" + $t).Trim(), [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$n)) {
        [Math]::Max($lo, [Math]::Min($hi, $n))
    } else { $def }
}
function Save-Config {
    $pd = PluginDir; if (-not $pd) { $LblStatus.Text = "狀態:找不到遊戲資料夾,無法寫入"; return $false }
    if (-not (Test-Path -LiteralPath $pd)) { $LblStatus.Text = "狀態:尚未安裝翻譯 —— 請先按「安裝 / 更新翻譯」"; return $false }
    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    $kv = @{
        "hideplayers" = $(if ($ChkHide.IsChecked) { "1" } else { "0" })
        "showparty"   = $(if ($ChkParty.IsChecked) { "1" } else { "0" })
        "showguild"   = $(if ($ChkGuild.IsChecked) { "1" } else { "0" })
        "showfriends" = $(if ($ChkFriend.IsChecked) { "1" } else { "0" })
        "hidenum"     = $(if ($ChkNum.IsChecked) { "1" } else { "0" })
        "bossdiag"    = $(if ($ChkBaDiag.IsChecked) { "1" } else { "0" })
        "hidezero"    = $(if ($ChkZero.IsChecked) { "1" } else { "0" })
        "chatinvite"  = [string][Math]::Max(0, $CboChatInvite.SelectedIndex)
        "mapnamewrap" = $(if ($ChkMapWrap.IsChecked) { "1" } else { "0" })
        "buffpos"     = [string][Math]::Max(0, $CboBuffPos.SelectedIndex)
        "buffscale"   = (ClampDbl $TBuffScale.Text 0.5 2 1.0).ToString("0.00", [Globalization.CultureInfo]::InvariantCulture)
        "buffx"       = [string](ClampInt $TBuffX.Text -4000 4000 0)
        "buffy"       = [string](ClampInt $TBuffY.Text -4000 4000 0)
        "debuffx"     = [string](ClampInt $TDebuffX.Text -4000 4000 0)
        "debuffy"     = [string](ClampInt $TDebuffY.Text -4000 4000 0)
        "mainx"       = [string](ClampInt $TMainX.Text -4000 4000 0)
        "mainy"       = [string](ClampInt $TMainY.Text -4000 4000 0)
        "partybuff"   = $(if ($ChkPartyBuff.IsChecked) { "1" } else { "0" })
        "partybuffkey" = $TPartyBuffKey.Text.Trim()
        "fxskilldiag" = $(if ($ChkFxSkillDiag.IsChecked) { "1" } else { "0" })
        "viewdiag"    = $(if ($ChkDgView.IsChecked) { "1" } else { "0" })
        "sfxdiag"     = $(if ($ChkDgSfx.IsChecked) { "1" } else { "0" })
        "zerodiag"    = $(if ($ChkDgZero.IsChecked) { "1" } else { "0" })
        "searchdiag"  = $(if ($ChkDgSearch.IsChecked) { "1" } else { "0" })
        "bossarrowdiag" = $(if ($ChkDgArrow.IsChecked) { "1" } else { "0" })
        "watch"       = $TDgWatch.Text.Trim()
        "hidefx"      = $(if ($ChkFx.IsChecked) { "1" } else { "0" })
        "mutefx"      = $(if ($ChkMute.IsChecked) { "1" } else { "0" })
        "hidefull"    = $(if ($ChkFull.IsChecked) { "1" } else { "0" })
        "shadows"     = $(if ($ChkShadow.IsChecked) { "0" } else { "1" })
        "animcull"    = $(if ($ChkAnim.IsChecked) { "1" } else { "0" })
        "fxonlymine"  = $(if ($ChkFxMine.IsChecked) { "1" } else { "0" })
        "renderscale" = (ClampDbl $TxtScale.Text 0 1 0).ToString("0.00", $inv)
        "sharpness"   = (ClampDbl $TxtSharp.Text 0 1 0).ToString("0.00", $inv)
        "fpslimit"    = [string](ClampInt $TxtFps.Text 0 500 0)
        "upscaler"    = @("off", "FSR", "STP")[[Math]::Max(0, $CboUp.SelectedIndex)]
        "vsync"       = @("-1", "0", "1")[[Math]::Max(0, $CboVs.SelectedIndex)]
        "msaa"        = @("-1", "1", "2", "4", "8")[[Math]::Max(0, $CboMsaa.SelectedIndex)]
        "cdmaskcolor" = $script:cdMask
        "cdtextcolor" = $script:cdText
        "cdmaskalpha" = [string](ClampInt $TxtCdAlpha.Text -1 100 -1)
        "cdtextx"     = [string](ClampInt $TxtCdX.Text -200 200 0)
        "cdtexty"     = [string](ClampInt $TxtCdY.Text -200 200 0)
        "cdtextsize"  = [string](ClampInt $TxtCdSize.Text 0 200 0)
    }
    if ($script:IsPure) { }   # 純翻譯包:view.txt 全是功能鍵(隱藏/效能/冷卻),不寫 —— 否則第一次套用會憑空生出一份全預設的功能設定檔
    elseif ($script:cfgLoaded["view"]) { [void](Save-KV (Join-Path $pd "SpiritZh_view.txt") $kv) }
    else { $script:saveErr += "SpiritZh_view.txt:沒讀成功過,為避免覆蓋成空白設定,這次不寫入" }
    if ($script:cfgLoaded["gui"]) {
        [void](Save-KV (Join-Path $pd "SpiritZh_gui.txt") @{
            "splash"    = $(if ($ChkSplash.IsChecked) { "1" } else { "0" })
            "splashvol" = [string](ClampInt $TxtVol.Text 0 100 35)
        })
    }
    $modeText = "bilingual"
    if ($RbM1.IsChecked) { $modeText = "full" }
    elseif ($RbM3.IsChecked) { $modeText = "chinese" }
    elseif ($RbM4.IsChecked) { $modeText = "off" }
    try { Set-Content -LiteralPath (Join-Path $pd "SpiritZh_mode.txt") -Value $modeText -Encoding UTF8 -NoNewline -ErrorAction Stop } catch { $script:saveErr += ("SpiritZh_mode.txt:寫入失敗(" + $_.Exception.Message + ")") }
    $fVal = ""
    if ($script:fontFilePath) { $fVal = $script:fontFilePath }
    elseif ($CboFont.SelectedIndex -gt 0) { $fVal = [string]$CboFont.SelectedItem }
    $fLines = @("// SpiritZh 自訂字型設定(設定工具產生)",
                "// 底下那行 = 目前選擇;全部是註解 = 使用遊戲預設字型。")
    if ($fVal) { $fLines += $fVal }
    try { Set-Content -LiteralPath (Join-Path $pd "SpiritZh_font.txt") -Value $fLines -Encoding UTF8 -ErrorAction Stop } catch { $script:saveErr += ("SpiritZh_font.txt:寫入失敗(" + $_.Exception.Message + ")") }
    return $true
}

# ── 深色訊息視窗:系統 MessageBox 是白底黑字,跟整個工具格格不入 ──────────
function Show-Msg([string]$title, [string]$body, [string]$kind = "info") {
    $x3 = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Width="440" SizeToContent="Height" WindowStartupLocation="CenterOwner" ResizeMode="NoResize"
        Background="#151C2B" FontFamily="Microsoft JhengHei UI" FontSize="14" Foreground="#E6EBF2" ShowInTaskbar="False">
  <StackPanel Margin="18,16,18,16">
    <StackPanel Orientation="Horizontal" Margin="0,0,0,10">
      <TextBlock x:Name="Ico" FontFamily="Segoe MDL2 Assets" FontSize="22" Margin="0,0,10,0" VerticalAlignment="Center"/>
      <TextBlock x:Name="Ttl" FontSize="16" FontWeight="Bold" VerticalAlignment="Center"/>
    </StackPanel>
    <TextBlock x:Name="Body" TextWrapping="Wrap" LineHeight="22" Foreground="#C9D1DE"/>
    <Button x:Name="Ok" Content="確定" Width="110" HorizontalAlignment="Right" Margin="0,16,0,0" Padding="10,7"/>
  </StackPanel>
</Window>
'@
    $d = [Windows.Markup.XamlReader]::Parse($x3)
    try { $d.Owner = $window } catch {}
    $d.Title = $title
    $d.FindName("Ttl").Text = $title
    $d.FindName("Body").Text = $body
    $ico = $d.FindName("Ico")
    if ($kind -eq "warn") { $ico.Text = [string][char]0xE7BA; $ico.Foreground = "#FFB020" }
    elseif ($kind -eq "error") { $ico.Text = [string][char]0xEA39; $ico.Foreground = "#FF6B6B" }
    else { $ico.Text = [string][char]0xE946; $ico.Foreground = "#3B82F6" }
    $d.FindName("Ok").Add_Click({ $d.Close() })
    [void]$d.ShowDialog()
}

function Confirm-Msg([string]$title, [string]$body, [string]$yes = "確定", [string]$no = "取消") {
    $xc = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Width="460" SizeToContent="Height" WindowStartupLocation="CenterOwner" ResizeMode="NoResize"
        Background="#151C2B" FontFamily="Microsoft JhengHei UI" FontSize="14" Foreground="#E6EBF2" ShowInTaskbar="False">
  <StackPanel Margin="18,16,18,16">
    <StackPanel Orientation="Horizontal" Margin="0,0,0,10">
      <TextBlock Text="&#xE7BA;" FontFamily="Segoe MDL2 Assets" FontSize="22" Margin="0,0,10,0" VerticalAlignment="Center" Foreground="#FFB020"/>
      <TextBlock x:Name="Ttl" FontSize="16" FontWeight="Bold" VerticalAlignment="Center"/>
    </StackPanel>
    <TextBlock x:Name="Body" TextWrapping="Wrap" LineHeight="22" Foreground="#C9D1DE"/>
    <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,16,0,0">
      <Button x:Name="No" Content="取消" Width="110" Padding="10,7" Margin="0,0,8,0"/>
      <Button x:Name="Yes" Content="確定" Width="130" Padding="10,7"/>
    </StackPanel>
  </StackPanel>
</Window>
'@
    $d = [Windows.Markup.XamlReader]::Parse($xc)
    try { if ($window.IsVisible) { $d.Owner = $window } } catch {}
    $d.Title = $title; $d.FindName("Ttl").Text = $title; $d.FindName("Body").Text = $body
    $d.FindName("Yes").Content = $yes; $d.FindName("No").Content = $no
    $d.FindName("Yes").Add_Click({ $d.DialogResult = $true })
    $d.FindName("No").Add_Click({ $d.DialogResult = $false })
    return [bool]$d.ShowDialog()
}

# ── 光柱:選色(含彩虹) / 載入 / 寫回 / 物品挑選 ────────────────────────
# 光柱那頁的選色要有「RGB 循環」;冷卻/DPS 文字不需要 —— 用參數區分,不做兩份視窗
function Pick-BeamColor([string]$current, [string]$title) {
    $x4 = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Width="336" SizeToContent="Height" WindowStartupLocation="CenterOwner" ResizeMode="NoResize"
        Background="#151C2B" FontFamily="Microsoft JhengHei UI" Foreground="#E6EBF2" ShowInTaskbar="False">
  <StackPanel Margin="14">
    <WrapPanel x:Name="Swatches"/>
    <Button x:Name="Rb" Height="34" Margin="0,4,0,0" Padding="0">
      <Border CornerRadius="6" Width="290" Height="30">
        <Border.Background>
          <LinearGradientBrush StartPoint="0,0" EndPoint="1,0">
            <GradientStop Color="#FF0000" Offset="0"/><GradientStop Color="#FFFF00" Offset="0.17"/>
            <GradientStop Color="#00FF00" Offset="0.33"/><GradientStop Color="#00FFFF" Offset="0.5"/>
            <GradientStop Color="#0000FF" Offset="0.67"/><GradientStop Color="#FF00FF" Offset="0.83"/>
            <GradientStop Color="#FF0000" Offset="1"/>
          </LinearGradientBrush>
        </Border.Background>
        <TextBlock Text="★ RGB 循環(顏色一直變)" HorizontalAlignment="Center" VerticalAlignment="Center" FontWeight="Bold" Foreground="White">
          <TextBlock.Effect><DropShadowEffect BlurRadius="3" ShadowDepth="1" Opacity="0.9"/></TextBlock.Effect>
        </TextBlock>
      </Border>
    </Button>
    <DockPanel Margin="0,10,0,0">
      <TextBlock Text="色碼:" VerticalAlignment="Center" Margin="0,0,6,0"/>
      <TextBox x:Name="Hex" Background="#101827" Foreground="#E6EBF2" BorderBrush="#33405A" Padding="6,4"/>
    </DockPanel>
    <TextBlock Text="#RRGGBB(六位)或 rainbow;留空 = 不用這條規則" Foreground="#8A94A8" FontSize="12" Margin="0,4,0,10"/>
    <UniformGrid Columns="3">
      <Button x:Name="Ok" Content="確定" Margin="0,0,6,0" Padding="10,6"/>
      <Button x:Name="No" Content="不使用" Margin="0,0,6,0" Padding="10,6"/>
      <Button x:Name="Cancel" Content="取消" Padding="10,6"/>
    </UniformGrid>
  </StackPanel>
</Window>
'@
    $dlg = [Windows.Markup.XamlReader]::Parse($x4)
    $dlg.Owner = $window; $dlg.Title = $(if ($title) { $title } else { "選擇顏色" })
    $sw = $dlg.FindName("Swatches"); $hex = $dlg.FindName("Hex")
    $hex.Text = $current
    foreach ($cc in @("#FF1E1E","#FF8A1E","#FFD24A","#3DDC5A","#00E5FF","#3B82F6","#7C4DFF","#FF4D9D","#FFFFFF","#9AA0A6","#000000","#B00020")) {
        $b = New-Object System.Windows.Controls.Button
        $b.Width = 44; $b.Height = 26
        $b.Margin = New-Object System.Windows.Thickness(0, 0, 6, 6)
        $b.Background = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString($cc))
        $b.Tag = $cc
        $b.Add_Click({ param($s2, $e2) $hex.Text = [string]$s2.Tag }.GetNewClosure())
        [void]$sw.Children.Add($b)
    }
    $script:pbOut = $null
    $dlg.FindName("Rb").Add_Click({ $script:pbOut = "rainbow"; $dlg.DialogResult = $true })
    $dlg.FindName("Ok").Add_Click({
        $t = $hex.Text.Trim()
        if ($t -eq "") { $script:pbOut = ""; $dlg.DialogResult = $true; return }
        if ($t -match '^(?i)(rainbow|rgb)$' -or $t -eq "彩虹") { $script:pbOut = "rainbow"; $dlg.DialogResult = $true; return }
        $tu = $t.ToUpperInvariant()
        if ($tu -match '^#?([0-9A-F]{6}|[0-9A-F]{8})$') {   # 6 位 #RRGGBB;8 位 #AARRGGBB 外掛也吃
            if (-not $tu.StartsWith("#")) { $tu = "#" + $tu }
            $script:pbOut = $tu; $dlg.DialogResult = $true
        } else { Show-Msg "格式不對" "色碼要是 #RRGGBB 六位(或 #AARRGGBB 八位)、rainbow,或留空表示不用。" "warn" }
    })
    $dlg.FindName("No").Add_Click({ $script:pbOut = ""; $dlg.DialogResult = $true })
    $dlg.FindName("Cancel").Add_Click({ $dlg.DialogResult = $false })
    if ($dlg.ShowDialog()) { return $script:pbOut } else { return $null }
}
function BeamBtnText([string]$v) { if ($v -eq "") { "(不用)" } elseif ($v -eq "rainbow") { "★ RGB 循環" } else { $v } }
$script:beam = @{ bosscard=""; bossequip=""; uniqueequip=""; purpleall=""; chancecolor=""; testall=""; namecolor="" }
$script:beamBtn = @{ bosscard=$BBossCard; bossequip=$BBossEquip; uniqueequip=$BUniqueEq; purpleall=$BPurpleAll; chancecolor=$BChance; testall=$BTestAll; namecolor=$BNameColor }
# ★ 不用 GetNewClosure:閉包綁在獨立 module,只有 -File 啟動時才看得到 script 函式;
#   用「以 PowerShell 執行」(-Command)開的話 Pick-BeamColor 會找不到、按鈕靜默沒反應。key 放 Tag,處理器在 script 作用域跑。
foreach ($k in @($script:beamBtn.Keys)) {
    $script:beamBtn[$k].Tag = $k
    $script:beamBtn[$k].Add_Click({
        param($sdr, $e2)
        $key = [string]$sdr.Tag
        $r = Pick-BeamColor $script:beam[$key] ("選擇顏色 —— " + $key)
        if ($null -ne $r) { $script:beam[$key] = $r; $sdr.Content = (BeamBtnText $r) }
    })
}
$hideChecks = @{ Equip=$HEquip; Artifact=$HArtifact; Card=$HCard; Gem=$HGem; Junk=$HJunk; Consumable=$HConsumable; Cosmetic=$HCosmetic }
$script:beamItems = New-Object System.Collections.ArrayList   # 每筆 = @{en=; hex=}
function Refresh-ItemList {
    $LstItems.Items.Clear()
    foreach ($it in $script:beamItems) { [void]$LstItems.Items.Add($it.en + "    " + (BeamBtnText $it.hex)) }
    $LblItemCount.Text = "共 " + $script:beamItems.Count + " 項"
}
function Load-BeamConfig {
    $pd = PluginDir; if (-not $pd) { return }
    $f = Join-Path $pd "SpiritZh_beam.txt"
    $b = Read-KV $f; if ($null -eq $b) { return }
    # item= 行先讀好(讀失敗就整個不動,不能把清單清空)
    $itemLines = @()
    if (Test-Path -LiteralPath $f) { try { $itemLines = @(Get-Content -LiteralPath $f -Encoding UTF8 -ErrorAction Stop) } catch { return } }
    $ChkBeamOn.IsChecked = ($b["enabled"] -eq "1")
    foreach ($k in @($script:beam.Keys)) { $script:beam[$k] = "" + $b[$k]; $script:beamBtn[$k].Content = (BeamBtnText $script:beam[$k]) }
    $TChance.Text = $(if ($b["chancebelow"]) { $b["chancebelow"] } else { "0" })
    $CboMiss.SelectedIndex = switch ("" + $b["missmode"]) { "dim" { 1 } "hide" { 2 } default { 0 } }
    $TDim.Text = $(if ($b["dimlevel"]) { $b["dimlevel"] } else { "0.35" })
    $ht = @(("" + $b["hidetypes"]) -split "," | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    foreach ($k in $hideChecks.Keys) { $hideChecks[$k].IsChecked = ($ht -contains $k) }
    $HKeepLeg.IsChecked = ($b["hidekeeplegendary"] -ne "0")
    $CboNameMode.SelectedIndex = switch ("" + $b["namemode"]) { "custom" { 1 } "off" { 2 } default { 0 } }
    $TScale.Text = $(if ($b["scale"]) { $b["scale"] } else { "1.0" })
    $TRbSpeed.Text = $(if ($b["rainbowspeed"]) { $b["rainbowspeed"] } else { "3.0" })
    $ChkBeamDiag.IsChecked = ($b["diag"] -eq "1")
    # 指定物品:item=<分類或留空>|<英文名>|<#顏色 或 rainbow>
    $script:beamItems.Clear()
    foreach ($l in $itemLines) {
        $t = $l.Trim()
        if (-not $t.StartsWith("item=")) { continue }
        $parts = $t.Substring(5) -split "\|"
        if ($parts.Count -ge 3) { [void]$script:beamItems.Add(@{ en = $parts[1].Trim(); hex = $parts[2].Trim() }) }
    }
    $script:cfgLoaded["beam"] = $true
    Refresh-ItemList
}
function Save-BeamConfig {
    $pd = PluginDir; if (-not $pd -or -not (Test-Path -LiteralPath $pd)) { return }
    if (-not $script:cfgLoaded["beam"]) { $script:saveErr += "SpiritZh_beam.txt:沒讀成功過,為避免覆蓋成空白設定,這次不寫入"; return }
    $f = Join-Path $pd "SpiritZh_beam.txt"
    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    # 純量鍵走 Save-KV(就地改值、保留範本註解);item= 是多行同鍵,另外處理
    $ht = @(); foreach ($k in $hideChecks.Keys) { if ($hideChecks[$k].IsChecked) { $ht += $k } }
    $okKv = Save-KV $f @{
        enabled           = $(if ($ChkBeamOn.IsChecked) { "1" } else { "0" })
        bosscard          = $script:beam["bosscard"]
        bossequip         = $script:beam["bossequip"]
        uniqueequip       = $script:beam["uniqueequip"]
        purpleall         = $script:beam["purpleall"]
        chancecolor       = $script:beam["chancecolor"]
        testall           = $script:beam["testall"]
        namecolor         = $script:beam["namecolor"]
        namemode          = @("follow", "custom", "off")[[Math]::Max(0, $CboNameMode.SelectedIndex)]
        chancebelow       = (ClampDbl $TChance.Text 0 100 0).ToString($inv)
        scale             = (ClampDbl $TScale.Text 0.2 5 1).ToString($inv)
        rainbowspeed      = (ClampDbl $TRbSpeed.Text 0.3 30 3).ToString($inv)
        missmode          = @("normal", "dim", "hide")[[Math]::Max(0, $CboMiss.SelectedIndex)]
        dimlevel          = (ClampDbl $TDim.Text 0.05 0.9 0.35).ToString("0.00", $inv)
        hidetypes         = ($ht -join ",")
        hidekeeplegendary = $(if ($HKeepLeg.IsChecked) { "1" } else { "0" })
        diag              = $(if ($ChkBeamDiag.IsChecked) { "1" } else { "0" })
    }
    if (-not $okKv) { return }   # 純量鍵都寫不進去,item 段也別碰(否則可能把檔案寫成只剩 BOM)
    # item= 行:把舊的全部拿掉、新的接在檔尾
    $lines = @()
    $cur = @()
    try { $cur = @(Get-Content -LiteralPath $f -Encoding UTF8 -ErrorAction Stop) } catch { $script:saveErr += "SpiritZh_beam.txt:讀取失敗(" + $_.Exception.Message + ")"; return }
    foreach ($l in $cur) {
        if ($l.Trim().TrimStart([char]0xFEFF).StartsWith("item=")) { continue }
        $lines += $l
    }
    if ($script:beamItems.Count -gt 0) {
        if (-not ($lines | Where-Object { $_.Contains("item=<分類或留空>") })) { $lines += "// item=<分類或留空>|<物品英文名>|<#顏色 或 rainbow>" }
        foreach ($it in $script:beamItems) { $lines += ("item=|" + $it.en + "|" + $it.hex) }
    }
    try { Set-Content -LiteralPath $f -Value $lines -Encoding UTF8 -ErrorAction Stop } catch { $script:saveErr += ("SpiritZh_beam.txt:寫入失敗(" + $_.Exception.Message + ")") }
}
# 物品清單(給「加入物品」用):names.txt 的英文名 + dict.txt 對照中文;懶載入,第一次按才讀
$script:allItems = $null
$script:allItemsPath = ""
$script:itemEnByDisp = @{}   # 顯示字串 → 遊戲英文名(外掛比對用的是英文名)
function Get-AllItems {
    $pd = PluginDir
    # 空清單不快取(還沒安裝翻譯時會是空的,裝好之後要抓得到);換遊戲路徑也要重讀
    if ($null -ne $script:allItems -and $script:allItems.Count -gt 0 -and $script:allItemsPath -eq $pd) { return $script:allItems }
    $list = New-Object System.Collections.ArrayList
    try {
        # 光色標示:外掛匯出的 SpiritZh_rarity.txt(進遊戲跑過一次才有;沒有就不標)
        $light = @{}
        $rp = Join-Path $pd "SpiritZh_rarity.txt"
        if (Test-Path -LiteralPath $rp) {
            foreach ($l in (Get-Content -LiteralPath $rp -Encoding UTF8)) {
                if ($l.StartsWith("//")) { continue }
                $i = $l.IndexOf("="); if ($i -le 0) { continue }
                $lt = switch ($l.Substring($i + 1).Trim()) { "Common" { "白光" } "Rare" { "藍光" } "Unique" { "綠光" } "Legendary" { "紫光" } "卡片" { "紫光類" } "寶石" { "紫光類" } default { $null } }
                if ($lt) { $light[$l.Substring(0, $i).Trim()] = $lt }
            }
        }
        $dict = @{}
        $dp = Join-Path $pd "SpiritZh_dict.txt"
        if (Test-Path -LiteralPath $dp) {
            foreach ($l in (Get-Content -LiteralPath $dp -Encoding UTF8)) {
                $i = $l.IndexOf("="); if ($i -gt 0 -and -not $l.StartsWith("//")) { $dict[$l.Substring(0, $i)] = $l.Substring($i + 1) }
            }
        }
        $np = Join-Path $pd "SpiritZh_names.txt"
        if (Test-Path -LiteralPath $np) {
            foreach ($l in (Get-Content -LiteralPath $np -Encoding UTF8)) {
                $en = $l.Trim().TrimStart([char]0xFEFF)
                if ($en.Length -eq 0 -or $en.StartsWith("//") -or $en.StartsWith("#")) { continue }
                $zh = $dict[$en]
                $disp = $(if ($zh) { $zh + "  |  " + $en } else { $en })
                if ($light[$en]) { $disp += "  〔" + $light[$en] + "〕" }
                [void]$list.Add($disp); $script:itemEnByDisp[$disp] = $en
            }
        }
    } catch {}
    if ($list.Count -gt 0) { $script:allItems = $list; $script:allItemsPath = $pd }
    return $list
}
# 物品挑選視窗:回傳遊戲英文名(外掛比對用的是英文名,跨字典版本穩定),取消回 $null。
# 光柱頁的「加入物品」與音效頁的「指定物品 / 靜音物品」共用這一份 —— 之前各寫一份,
# 結果只有一邊修好「顯示字串尾巴有〔紫光〕會被當成物品名」那個 bug。
function Pick-GameItem([string]$title, [string]$okText = "選好了") {
    $items = Get-AllItems
    if ($items.Count -eq 0) { Show-Msg "清單載不到" "物品清單需要 SpiritZh_names.txt / SpiritZh_dict.txt —— 請先安裝翻譯。" "warn"; return $null }
    $x5 = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="選一個物品 —— 之後再挑顏色" Width="560" Height="580" WindowStartupLocation="CenterOwner"
        Background="#151C2B" FontFamily="Microsoft JhengHei UI" FontSize="14" Foreground="#E6EBF2" ShowInTaskbar="False">
  <DockPanel Margin="14">
    <TextBox x:Name="Q" DockPanel.Dock="Top" Background="#101827" Foreground="#E6EBF2" BorderBrush="#33405A" Padding="8,6" Margin="0,0,0,8"/>
    <TextBlock DockPanel.Dock="Top" Text="輸入中文或英文關鍵字篩選;雙擊或選好按下方按鈕" Foreground="#8A94A8" FontSize="12" Margin="0,0,0,8"/>
    <Button x:Name="Ok" DockPanel.Dock="Bottom" Content="選好了" Height="36" Margin="0,10,0,0"/>
    <ListBox x:Name="L" Background="#101827" Foreground="#E6EBF2" BorderBrush="#33405A"/>
  </DockPanel>
</Window>
'@
    $d = [Windows.Markup.XamlReader]::Parse($x5)
    if ($window.IsVisible) { $d.Owner = $window }
    if ($title) { $d.Title = $title }
    if ($okText) { $d.FindName("Ok").Content = $okText }
    $q = $d.FindName("Q"); $lb = $d.FindName("L")
    $fill = {
        $kw = $q.Text.Trim(); $lb.Items.Clear(); $c = 0
        foreach ($it in $items) {
            if ($kw.Length -gt 0 -and $it.IndexOf($kw, [StringComparison]::OrdinalIgnoreCase) -lt 0) { continue }
            [void]$lb.Items.Add($it); $c++
            if ($c -ge 600) { break }
        }
    }
    & $fill
    $q.Add_TextChanged($fill)
    $lb.Add_MouseDoubleClick({ if ($lb.SelectedIndex -ge 0) { $d.DialogResult = $true } })
    $d.FindName("Ok").Add_Click({ if ($lb.SelectedIndex -ge 0) { $d.DialogResult = $true } })
    if (-not $d.ShowDialog()) { return $null }
    $disp = [string]$lb.SelectedItem
    $en = $script:itemEnByDisp[$disp]; if (-not $en) { $en = $disp }
    return $en
}
$BItemAdd.Add_Click({
    $en = Pick-GameItem "選一個物品 —— 之後再挑光柱顏色" "選好了,挑顏色"
    if (-not $en) { return }
    $hex = Pick-BeamColor "" ("選擇「" + $en + "」的光柱顏色")
    if ([string]::IsNullOrWhiteSpace($hex)) { return }
    $keep = New-Object System.Collections.ArrayList
    foreach ($it in $script:beamItems) { if ($it.en -ne $en) { [void]$keep.Add($it) } }
    [void]$keep.Add(@{ en = $en; hex = $hex })
    $script:beamItems = $keep
    Refresh-ItemList
    $LblStatus.Text = "狀態:已加入光柱規則:" + $en + " → " + (BeamBtnText $hex) + "(按「套用設定」生效)"
})
$BItemDel.Add_Click({
    if ($LstItems.SelectedIndex -lt 0) { return }
    $script:beamItems.RemoveAt($LstItems.SelectedIndex)
    Refresh-ItemList
})

# ── 掉落音效:稀有度音效 / 過濾器 / 靜音清單 ──────────────────────────────
$script:rarKeys = @("Legendary", "Purple", "Unique", "Rare", "Common", "Green")
$script:rarLabel = @{ Legendary="金光(傳說裝備)"; Purple="紫光(傳說寶物)"; Unique="綠光(獨特)"; Rare="藍光(稀有)"; Common="白光(普通)"; Green="貴重礦石" }
$script:sndCbo = @{}; $script:sndVol = @{}
$script:sndRaw = @{}; $script:sndRawVol = @{}; $script:sndRawFile = @{}   # 載入時的原始字串/換算出來的 %/檔名,用來判斷「使用者有沒有動過」
foreach ($k in $script:rarKeys) {
    $script:sndCbo[$k] = $window.FindName("CboSnd" + $k)
    $script:sndVol[$k] = $window.FindName("TVol" + $k)
}
$NOSND = "(不播放)"
function SoundDir { $pd = PluginDir; if ($pd) { Join-Path $pd "SpiritZh_sounds" } else { "" } }
function Get-SoundFiles {
    # MCI 不吃 ogg,所以只收 wav / mp3
    $sd = SoundDir
    if (-not $sd -or -not (Test-Path -LiteralPath $sd)) { return @() }
    try { return @(Get-ChildItem -LiteralPath $sd -File -ErrorAction Stop | Where-Object { $_.Extension -in '.wav', '.mp3' } | Sort-Object Name | ForEach-Object { $_.Name }) }
    catch { return @() }
}
# 重建下拉:保留目前選的那個檔(即使檔案已被刪或改名,也不能把使用者的設定弄丟)
function Refresh-SoundCombos {
    $files = @(Get-SoundFiles)
    foreach ($k in $script:rarKeys) {
        $cb = $script:sndCbo[$k]
        $cur = [string]$cb.SelectedItem
        $cb.Items.Clear()
        [void]$cb.Items.Add($NOSND)
        foreach ($f in $files) { [void]$cb.Items.Add("自訂:" + $f) }
        if ($cur -and $cur -ne $NOSND -and $cb.Items.IndexOf($cur) -lt 0) { [void]$cb.Items.Add($cur) }
        $cb.SelectedItem = $(if ($cur -and $cb.Items.IndexOf($cur) -ge 0) { $cur } else { $NOSND })
    }
}
function Set-SoundSel([string]$k, [string]$file) {
    $cb = $script:sndCbo[$k]
    if ([string]::IsNullOrWhiteSpace($file)) { $cb.SelectedItem = $NOSND; return }
    $lbl = "自訂:" + $file
    if ($cb.Items.IndexOf($lbl) -lt 0) { [void]$cb.Items.Add($lbl) }
    $cb.SelectedItem = $lbl
}
function Get-SoundSel([string]$k) {
    $v = [string]$script:sndCbo[$k].SelectedItem
    if (-not $v -or $v -eq $NOSND) { return "" }
    if ($v.StartsWith("自訂:")) { return $v.Substring(3) }
    return $v
}
# 選音效檔:複製進 SpiritZh_sounds(來源已經在裡面就不複製 —— 自己複製自己會丟例外)
foreach ($k in $script:rarKeys) {
    $bb = $window.FindName("BSnd" + $k); $bb.Tag = $k
    $bb.Add_Click({
        param($sdr, $e2)
        $key = [string]$sdr.Tag
        $sd = SoundDir
        if (-not $sd) { Show-Msg "尚未安裝" "要先安裝翻譯才能設定音效。" "warn"; return }
        $od = New-Object Microsoft.Win32.OpenFileDialog
        $od.Filter = "音效檔 (*.wav;*.mp3)|*.wav;*.mp3"
        $od.Title = "選擇「" + $script:rarLabel[$key] + "」的音效檔"
        if (-not $od.ShowDialog($window)) { return }
        $ext = [IO.Path]::GetExtension($od.FileName).ToLowerInvariant()
        if ($ext -ne ".wav" -and $ext -ne ".mp3") { Show-Msg "格式不支援" ("只支援 wav 與 mp3(選到的是 " + $ext + ")。ogg 請先轉檔。") "warn"; return }
        try {
            if (-not (Test-Path -LiteralPath $sd)) { New-Item -ItemType Directory -Path $sd -ErrorAction Stop | Out-Null }
            $dst = Join-Path $sd ([IO.Path]::GetFileName($od.FileName))
            if ([IO.Path]::GetFullPath($od.FileName) -ine [IO.Path]::GetFullPath($dst)) {
                # 同名檔要先問:直接蓋掉的話,別的稀有度正在用同一個檔名就會跟著被換聲音,而且原檔救不回來
                if (Test-Path -LiteralPath $dst) {
                    $ans = Confirm-Msg "資料夾裡已經有同名檔" ("音效資料夾裡已經有「" + [IO.Path]::GetFileName($dst) + "」。`n`n" +
                        "要用你剛選的檔【覆蓋】它嗎?(其他稀有度若也在用這個檔名,聲音會一起換掉,而且原檔救不回來)`n`n" +
                        "選「沿用現有的」就直接用資料夾裡那一個,不覆蓋。") "覆蓋" "沿用現有的"
                    if ($ans) { Copy-Item -LiteralPath $od.FileName -Destination $dst -Force -ErrorAction Stop }
                } else {
                    Copy-Item -LiteralPath $od.FileName -Destination $dst -Force -ErrorAction Stop
                }
            }
            if (-not (Test-Path -LiteralPath $dst)) { throw "複製後找不到目的檔 " + $dst }
            Refresh-SoundCombos
            Set-SoundSel $key ([IO.Path]::GetFileName($dst))
            $mb = [math]::Round((Get-Item -LiteralPath $dst).Length / 1MB, 1)
            $LblStatus.Text = "狀態:已載入 " + $script:rarLabel[$key] + " 音效:" + [IO.Path]::GetFileName($dst) + $(if ($mb -ge 5) { "(" + $mb + " MB,分享時可能不好傳)" } else { "" }) + "(按「套用設定」生效)"
        } catch { Show-Msg "失敗" ("音效檔複製失敗:" + $_.Exception.Message) "error" }
    })
}
$BSndRefresh.Add_Click({ Refresh-SoundCombos; $LblStatus.Text = "狀態:音效檔清單已重新掃描(共 " + @(Get-SoundFiles).Count + " 個)" })
$BSndFolder.Add_Click({
    $sd = SoundDir
    if (-not $sd) { Show-Msg "尚未安裝" "要先安裝翻譯才有這個資料夾。" "warn"; return }
    if (-not (Test-Path -LiteralPath $sd)) { try { New-Item -ItemType Directory -Path $sd -ErrorAction Stop | Out-Null } catch { Show-Msg "失敗" $_.Exception.Message "error"; return } }
    Start-Process explorer.exe (Q $sd)
})
$BAudPreset.Add_Click({
    # 隨包附的三個提示音(純合成、無版權疑慮),複製進遊戲資料夾並套好整組
    $sd = SoundDir
    if (-not $sd) { Show-Msg "尚未安裝" "要先安裝翻譯才能套用。" "warn"; return }
    $warnList = $(if ($script:fNames.Count -gt 0) { "`n`n※ 你目前的「指定物品」清單(" + $script:fNames.Count + " 項)會被清空(靜音清單不動)。" } else { "" })
    if (-not (Confirm-Msg "套用作者推薦" ("會把這些一次設好:`n" +
        "‧金光/紫光/獨特/稀有 各一個提示音(音量 100%)`n" +
        "‧白光與礦石不播`n" +
        "‧冷卻 2 秒、只播自己的掉落、別人的掉落不播`n" +
        "‧只提醒「傳說」與「獨特」兩個稀有度" + $warnList) "套用推薦" "取消")) { return }
    try {
        if (-not (Test-Path -LiteralPath $sd)) { New-Item -ItemType Directory -Path $sd -ErrorAction Stop | Out-Null }
        $src = Join-Path $Here "payload\BepInEx\plugins\SpiritZh_sounds"
        $map = @{ Legendary="★推薦_傳說.wav"; Purple="★推薦_傳說.wav"; Unique="★推薦_獨特.wav"; Rare="★推薦_稀有.wav" }
        # 逐檔容錯:一個檔複製失敗不該讓整組設定都不套(而且沒到位的檔絕對不能寫進設定 ——
        # 那會變成「工具說成功、遊戲裡卻沒聲音」)
        $bad = @()
        foreach ($f in @("★推薦_傳說.wav", "★推薦_獨特.wav", "★推薦_稀有.wav")) {
            $sp = Join-Path $src $f; $dp = Join-Path $sd $f
            if (Test-Path -LiteralPath $dp) { continue }                      # 已經在了就不用複製
            if (-not (Test-Path -LiteralPath $sp)) { $bad += $f; continue }   # 安裝包裡找不到來源
            try { Copy-Item -LiteralPath $sp -Destination $dp -Force -ErrorAction Stop } catch { $bad += $f }
        }
        Refresh-SoundCombos
        $okN = 0
        foreach ($k in $script:rarKeys) {
            $f = $map[$k]
            if ($f -and (Test-Path -LiteralPath (Join-Path $sd $f))) { Set-SoundSel $k $f; $script:sndVol[$k].Text = "100"; $okN++ }
            else { Set-SoundSel $k "" }   # 白光/礦石本來就不播;檔案沒到位的也留空,不要寫進不存在的檔名
        }
        $TAudCool.Text = "2"; $ChkOwnOnly.IsChecked = $true; $ChkSkipLocked.IsChecked = $true
        foreach ($c in $script:fTypeChecks.Values) { $c.IsChecked = $false }
        foreach ($k in @($script:fRarChecks.Keys)) { $script:fRarChecks[$k].IsChecked = ($k -eq "Legendary" -or $k -eq "Unique") }
        $script:fNames.Clear(); Refresh-FilterLists
        $CboFMode.SelectedIndex = 0
        if ($bad.Count -gt 0) {
            Show-Msg "部分音效檔沒到位" ("這些推薦音效檔複製不進去,對應的稀有度已留空(不播):`n`n" + ($bad -join "`n") +
                "`n`n其他設定已經套好了。可以用「選音效檔…」自己指定,或重新安裝一次翻譯。") "warn"
            $LblStatus.Text = "狀態:⚠ 已套用作者推薦,但有 " + $bad.Count + " 個音效檔沒到位 —— 那幾列留空(不播)"
        } else {
            $LblStatus.Text = "狀態:★ 已套用作者推薦(" + $okN + " 列提示音、只播自己的掉落、只提醒傳說與獨特;指定物品清單已清空)—— 按「套用設定」存檔"
        }
    } catch { Show-Msg "失敗" ("套用推薦失敗:" + $_.Exception.Message) "error" }
})
$script:fTypeChecks = @{ Equip=$FEquip; Artifact=$FArtifact; Card=$FCard; Gem=$FGem; Consumable=$FConsumable; Cosmetic=$FCosmetic; Junk=$FJunk }
$script:fRarChecks  = @{ Legendary=$RLegendary; Unique=$RUnique; Rare=$RRare; Common=$RCommon }
$script:fNames = New-Object System.Collections.ArrayList
$script:fMute  = New-Object System.Collections.ArrayList
function Refresh-FilterLists {
    $LstNames.Items.Clear(); foreach ($x in $script:fNames) { [void]$LstNames.Items.Add($x) }
    $LstMute.Items.Clear();  foreach ($x in $script:fMute)  { [void]$LstMute.Items.Add($x) }
    $LblNameCount.Text = "共 " + $script:fNames.Count + " 項"
    $LblMuteCount.Text = "共 " + $script:fMute.Count + " 項"
}
$BNameAdd.Add_Click({
    $en = Pick-GameItem "選一個要播音效的物品"
    if (-not $en) { return }
    if ($script:fNames -notcontains $en) { [void]$script:fNames.Add($en) }
    Refresh-FilterLists
    $LblStatus.Text = "狀態:已加入指定物品:" + $en + "(按「套用設定」生效)"
})
$BNameDel.Add_Click({ if ($LstNames.SelectedIndex -ge 0) { $script:fNames.RemoveAt($LstNames.SelectedIndex); Refresh-FilterLists } })
$BMuteAdd.Add_Click({
    $en = Pick-GameItem "選一個要完全靜音的物品"
    if (-not $en) { return }
    if ($script:fMute -notcontains $en) { [void]$script:fMute.Add($en) }
    Refresh-FilterLists
    $LblStatus.Text = "狀態:已加入靜音物品:" + $en + "(按「套用設定」生效)"
})
$BMuteDel.Add_Click({ if ($LstMute.SelectedIndex -ge 0) { $script:fMute.RemoveAt($LstMute.SelectedIndex); Refresh-FilterLists } })
function Load-AudioConfig {
    $pd = PluginDir; if (-not $pd) { return }
    # ── SpiritZh_audio.txt ──
    # ★ 這兩個檔要各自獨立判斷:一邊讀不到就整個 return 的話,另一邊的 UI 會停在空白,
    #   接著按套用就把空白寫進另一個檔(靜音清單整份消失)。
    $a = Read-KV (Join-Path $pd "SpiritZh_audio.txt")
    if ($null -ne $a) {
        Refresh-SoundCombos
        foreach ($k in $script:rarKeys) {
            $raw = "" + $a[$k.ToLowerInvariant()]
            # v3.39 舊鍵 Card= 是 Purple 的前身(外掛端到現在還把它當稀有度鍵)。
            # ※ DropLegendary= / DropUnique= 【不是】舊稀有度鍵 —— 那是遊戲自己的 clip 名,
            #   使用者拿來調原音音量的(DropLegendary=1.8)。誤讀會把「1.8」當成檔名。
            if ($raw -eq "" -and $k -eq "Purple") { $raw = "" + $a["card"] }
            $file = $raw; $vol = 100
            $star = $raw.LastIndexOf("*")
            if ($star -gt 0) {
                $mv = 0.0
                if ([double]::TryParse($raw.Substring($star + 1).Trim(), [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$mv)) {
                    $file = $raw.Substring(0, $star).Trim(); $vol = [int][Math]::Round($mv * 100)
                }
            }
            Set-SoundSel $k $file.Trim()
            $script:sndVol[$k].Text = [string]$vol
            $script:sndRaw[$k] = $raw          # 原始字串:使用者沒動過就原樣寫回(避免 0.333 被量化成 0.33)
            $script:sndRawVol[$k] = [string]$vol
            $script:sndRawFile[$k] = $file.Trim()
        }
        $TAudCool.Text = $(if ($a.ContainsKey("cooldown")) { $a["cooldown"] } else { "2" })
        $ChkOwnOnly.IsChecked = $(if ($a.ContainsKey("ownonly")) { -not ($a["ownonly"] -eq "0" -or $a["ownonly"] -ieq "false") } else { $true })
        $ChkAudDiag.IsChecked = ($a["diag"] -eq "1" -or $a["diag"] -ieq "true")   # 外掛端 true 也算開
        $script:cfgLoaded["audio"] = $true
    }
    # ── SpiritZh_filter.txt ──
    $f = Join-Path $pd "SpiritZh_filter.txt"
    $fl = Read-KV $f; if ($null -eq $fl) { return }
    $lines = @()
    if (Test-Path -LiteralPath $f) { try { $lines = @(Get-Content -LiteralPath $f -Encoding UTF8 -ErrorAction Stop) } catch { return } }
    $ChkSkipLocked.IsChecked = $(if ($fl.ContainsKey("skiplocked")) { -not ($fl["skiplocked"] -eq "0" -or $fl["skiplocked"] -ieq "false") } else { $true })
    $CboFMode.SelectedIndex = $(if (("" + $fl["mode"]) -ieq "any") { 1 } else { 0 })
    $ty = @(("" + $fl["type"]) -split "," | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    foreach ($k in $script:fTypeChecks.Keys) { $script:fTypeChecks[$k].IsChecked = ($ty -contains $k) }
    $ra = @(("" + $fl["rarity"]) -split "," | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    foreach ($k in $script:fRarChecks.Keys) { $script:fRarChecks[$k].IsChecked = ($ra -contains $k) }
    # name= / mute= 是多行同鍵,Read-KV 只留最後一筆 —— 自己逐行收。沒有 = 的行外掛當成物品名,照收。
    $script:fNames.Clear(); $script:fMute.Clear()
    foreach ($l in $lines) {
        $t = $l.Trim().TrimStart([char]0xFEFF)
        if ($t.Length -eq 0 -or $t.StartsWith("//") -or $t.StartsWith("#")) { continue }
        $i = $t.IndexOf("=")
        if ($i -le 0) { if ($script:fNames -notcontains $t) { [void]$script:fNames.Add($t) }; continue }
        $k = $t.Substring(0, $i).Trim().ToLowerInvariant(); $v = $t.Substring($i + 1).Trim()
        if ($k -eq "name") { foreach ($x in ($v -split "," | ForEach-Object { $_.Trim() } | Where-Object { $_ })) { if ($script:fNames -notcontains $x) { [void]$script:fNames.Add($x) } } }
        elseif ($k -eq "mute") { foreach ($x in ($v -split "," | ForEach-Object { $_.Trim() } | Where-Object { $_ })) { if ($script:fMute -notcontains $x) { [void]$script:fMute.Add($x) } } }
    }
    $script:cfgLoaded["filter"] = $true
    Refresh-FilterLists
}
function Save-AudioConfig {
    $pd = PluginDir; if (-not $pd -or -not (Test-Path -LiteralPath $pd)) { return }
    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    # ── audio.txt ──
    if ($script:cfgLoaded["audio"]) {
        # 先清掉 Card=(v3.39 舊稀有度鍵,是 Purple 的後備 —— 留著會讓「不播放」失效)。
        # ※ 只清這一個。DropLegendary= / DropUnique= 是遊戲自己的 clip 名(使用者用來調原音音量),
        #   外掛端的稀有度鍵白名單裡根本沒有它們 —— 舊工具把它們一起刪掉是錯的,不要跟著錯。
        $af = Join-Path $pd "SpiritZh_audio.txt"
        if (Test-Path -LiteralPath $af) {
            $cur = $null
            try { $cur = @(Get-Content -LiteralPath $af -Encoding UTF8 -ErrorAction Stop) } catch { $script:saveErr += "SpiritZh_audio.txt:讀取失敗(" + $_.Exception.Message + ")"; $cur = $null }
            if ($null -ne $cur) {
                $keep = @($cur | Where-Object { -not ($_.Trim() -imatch '^card\s*=') })
                if ($keep.Count -ne $cur.Count) {
                    try { Set-Content -LiteralPath $af -Value $keep -Encoding UTF8 -ErrorAction Stop } catch { $script:saveErr += "SpiritZh_audio.txt:寫入失敗(" + $_.Exception.Message + ")" }
                }
            }
        }
        $kv = @{
            cooldown = (ClampDbl $TAudCool.Text 0 30 2).ToString("0.##", $inv)
            ownonly  = $(if ($ChkOwnOnly.IsChecked) { "1" } else { "0" })
            diag     = $(if ($ChkAudDiag.IsChecked) { "1" } else { "0" })
        }
        foreach ($k in $script:rarKeys) {
            $file = Get-SoundSel $k
            if (-not $file) { $kv[$k] = ""; continue }        # 留空 = 不播(外掛端 f2.Length > 0 才收)
            # 檔名與音量【都】沒動過才把原始字串原樣寫回 —— 手寫的 0.333 不該因為 UI 用整數 % 當中介
            # 就被量化成 0.33;但只要有一邊改了,就得照 UI 重組(不然換了音效檔卻寫回舊檔名)
            if ($script:sndVol[$k].Text.Trim() -eq ("" + $script:sndRawVol[$k]) -and $file -eq ("" + $script:sndRawFile[$k]) -and ("" + $script:sndRaw[$k]) -ne "") {
                $kv[$k] = $script:sndRaw[$k]; continue
            }
            $kv[$k] = $file + "*" + ((ClampDblInt $script:sndVol[$k].Text 5 300 100) / 100.0).ToString("0.##", $inv)
        }
        [void](Save-KV $af $kv)
    } else { $script:saveErr += "SpiritZh_audio.txt:沒讀成功過,為避免覆蓋成空白設定,這次不寫入" }
    # ── filter.txt:純量鍵就地改值;name= / mute= 多行同鍵另外剔舊補新(同 beam 的 item=)──
    if (-not $script:cfgLoaded["filter"]) { $script:saveErr += "SpiritZh_filter.txt:沒讀成功過,為避免把指定物品/靜音清單清空,這次不寫入"; return }
    $ff = Join-Path $pd "SpiritZh_filter.txt"
    $ty = @(); foreach ($k in $script:fTypeChecks.Keys) { if ($script:fTypeChecks[$k].IsChecked) { $ty += $k } }
    $ra = @(); foreach ($k in $script:fRarChecks.Keys)  { if ($script:fRarChecks[$k].IsChecked)  { $ra += $k } }
    $okKv = Save-KV $ff @{
        skiplocked = $(if ($ChkSkipLocked.IsChecked) { "1" } else { "0" })
        type       = ($ty -join ",")
        rarity     = ($ra -join ",")
        mode       = @("all", "any")[[Math]::Max(0, $CboFMode.SelectedIndex)]
    }
    if (-not $okKv) { return }
    $out = @(); $cur2 = @()
    try { $cur2 = @(Get-Content -LiteralPath $ff -Encoding UTF8 -ErrorAction Stop) } catch { $script:saveErr += "SpiritZh_filter.txt:讀取失敗(" + $_.Exception.Message + ")"; return }
    foreach ($l in $cur2) {
        $t = $l.Trim().TrimStart([char]0xFEFF)
        if ($t -imatch '^(name|mute)\s*=') { continue }
        if ($t.Length -gt 0 -and -not $t.StartsWith("//") -and -not $t.StartsWith("#") -and $t.IndexOf("=") -le 0) { continue }   # 沒有 = 的行外掛當物品名,已收進清單
        $out += $l
    }
    foreach ($x in $script:fNames) { if ($x) { $out += ("name=" + $x) } }
    foreach ($x in $script:fMute)  { if ($x) { $out += ("mute=" + $x) } }
    try { Set-Content -LiteralPath $ff -Value $out -Encoding UTF8 -ErrorAction Stop } catch { $script:saveErr += "SpiritZh_filter.txt:寫入失敗(" + $_.Exception.Message + ")" }
}

# ── 自訂:自訂翻譯 / 地圖背景音樂 ─────────────────────────────────────────
$script:cuRules = New-Object System.Collections.ArrayList   # 每筆 = @{ Word=bool; Src=""; Dst="" }
function CuRow($r) { $(if ($r.Word) { "[句中] " } else { "[整格] " }) + $r.Src + "  →  " + $r.Dst }
function Refresh-CuList {
    $LstCustom.Items.Clear()
    foreach ($r in $script:cuRules) { [void]$LstCustom.Items.Add((CuRow $r)) }
    $LblCuCount.Text = "共 " + $script:cuRules.Count + " 條規則"
}
$LstCustom.Add_SelectionChanged({
    $i = $LstCustom.SelectedIndex
    if ($i -lt 0 -or $i -ge $script:cuRules.Count) { return }
    $TCuSrc.Text = $script:cuRules[$i].Src; $TCuDst.Text = $script:cuRules[$i].Dst
    $ChkCuWord.IsChecked = [bool]$script:cuRules[$i].Word
})
$BCuAdd.Add_Click({
    $src = $TCuSrc.Text.Trim(); $dst = $TCuDst.Text.Trim()
    if ($src.Length -eq 0) { Show-Msg "還沒填原文" "「原文」是遊戲裡現在顯示的字(英文或中文都可以),不能留空。" "warn"; return }
    if ($dst.Length -eq 0) { Show-Msg "還沒填譯文" "「譯文」是你想改成的說法,不能留空。想刪掉規則請用「刪除選取」。" "warn"; return }
    if ($src.Contains("=")) { Show-Msg "原文不能有等號" "設定檔用「原文=譯文」的格式,原文裡有等號會讀錯。" "warn"; return }
    # 這三個開頭在設定檔裡是語法標記:~ 代表「句中也換」、// 與 # 代表整行是註解。
    # 不擋的話規則會被靜默改語意(整格變句中、開頭的 ~ 被吃掉)或整條消失。
    if ($src.StartsWith("~") -or $src.StartsWith("//") -or $src.StartsWith("#")) {
        Show-Msg "原文開頭不能是 ~ 或 // 或 #" ("設定檔用「~」代表「句中也換」、用「//」與「#」代表註解,所以原文不能用這三個開頭 ——" +
            "存進去之後會被當成語法而不是文字。`n`n想比對的字如果真的以這些符號開頭,請改用不含它們的一段(例如原文只填後半)。") "warn"
        return
    }
    $r = @{ Word = [bool]$ChkCuWord.IsChecked; Src = $src; Dst = $dst }
    # 同一個原文只留一條(大小寫要分:HP 與 hp 在遊戲裡是不同字串)
    $keep = New-Object System.Collections.ArrayList
    foreach ($x in $script:cuRules) { if (-not ($x.Src -ceq $src)) { [void]$keep.Add($x) } }
    [void]$keep.Add($r); $script:cuRules = $keep
    Refresh-CuList
    $TCuSrc.Text = ""; $TCuDst.Text = ""
    $LblStatus.Text = "狀態:已加入自訂翻譯:" + $src + " → " + $dst + "(按「套用設定」生效)"
})
$BCuDel.Add_Click({
    $i = $LstCustom.SelectedIndex
    if ($i -lt 0 -or $i -ge $script:cuRules.Count) { return }
    $script:cuRules.RemoveAt($i); Refresh-CuList
})
$BCuPreset.Add_Click({
    # 最常被問的六條(屬性縮寫改全名);已經有的略過
    $presets = @(@("HP", "生命值"), @("MP", "魔力值"), @("Atk", "物理攻擊"), @("Matk", "魔法攻擊"), @("Def", "物理防禦"), @("Mdef", "魔法防禦"))
    $add = 0
    foreach ($pp in $presets) {
        $dup = $false
        foreach ($r in $script:cuRules) { if ($r.Src -ceq $pp[0]) { $dup = $true; break } }
        if ($dup) { continue }
        [void]$script:cuRules.Add(@{ Word = $true; Src = $pp[0]; Dst = $pp[1] }); $add++
    }
    Refresh-CuList
    $LblStatus.Text = $(if ($add -gt 0) { "狀態:已加入 " + $add + " 條常用範例(按「套用設定」生效)" } else { "狀態:常用範例都已經在清單裡了" })
})
# 大小寫不敏感:外掛端 MapMusic 是 OrdinalIgnoreCase,這裡若分大小寫,同一張圖會存成兩筆,
# 而遊戲只認其中一筆 —— 工具顯示「設好了」但遊戲放的是另一個檔
$script:musicMap = New-Object System.Collections.Specialized.OrderedDictionary ([System.StringComparer]::OrdinalIgnoreCase)   # 地圖英文名 → 音樂檔
$script:mapList = @()      # music.txt 裡列過的所有地圖(含被註解掉的 —— 那是地圖目錄)
$script:mapZh = @{}
function MusicDir { $pd = PluginDir; if ($pd) { Join-Path $pd "SpiritZh_music" } else { "" } }
# 地圖名一律是英數(Sunny Meadows 1 / Windy Desert North / Demon's Maw)。
# ★ 讀與寫【一定要用同一把尺】—— 只有讀端過濾的話,被過濾掉的行會在寫回時被當成
#   「沒設定的地圖」改寫成「// 鍵=」,等號後面的東西(說明文字或使用者手寫的音樂檔名)就永久消失了。
function Test-MapKey([string]$k) { $k -match '^[A-Za-z0-9][A-Za-z0-9 ''\-\.]*$' }
function MapLabel([string]$en) { if ($script:mapZh[$en]) { $script:mapZh[$en] + "(" + $en + ")" } else { $en } }
function Refresh-MusicList {
    $LstMusic.Items.Clear()
    foreach ($k in $script:musicMap.Keys) { [void]$LstMusic.Items.Add((MapLabel $k) + "  →  " + $script:musicMap[$k]) }
    $LblMuCount.Text = "共 " + $script:musicMap.Count + " 張圖有指定音樂"
}
$BMuBrowse.Add_Click({
    $od = New-Object Microsoft.Win32.OpenFileDialog
    $od.Filter = "音樂檔 (*.mp3;*.wav)|*.mp3;*.wav|全部檔案 (*.*)|*.*"
    $od.Title = "選擇背景音樂"
    if ($od.ShowDialog($window)) { $TMuFile.Text = $od.FileName }
})
$BMuFolder.Add_Click({
    $md = MusicDir
    if (-not $md) { Show-Msg "尚未安裝" "要先安裝翻譯才有這個資料夾。" "warn"; return }
    if (-not (Test-Path -LiteralPath $md)) { try { New-Item -ItemType Directory -Path $md -ErrorAction Stop | Out-Null } catch { Show-Msg "失敗" $_.Exception.Message "error"; return } }
    Start-Process explorer.exe (Q $md)
})
$BMuSet.Add_Click({
    if ($CboMuMap.SelectedIndex -lt 0 -or $CboMuMap.SelectedIndex -ge $script:mapList.Count) { Show-Msg "還沒選地圖" "先在「地圖」下拉選一張圖。" "warn"; return }
    $f = $TMuFile.Text.Trim()
    if ($f.Length -eq 0) { Show-Msg "還沒選音樂" "先按「瀏覽…」挑一個音樂檔,或直接填 SpiritZh_music 資料夾裡的檔名。" "warn"; return }
    # 下拉顯示的是「中文(English)」,英文名要用索引回查,不能拆字串
    $mapEn = [string]$script:mapList[$CboMuMap.SelectedIndex]
    # 外面挑的檔複製進外掛資料夾:原檔被移動/刪掉也不會壞
    if ($f -match '[\\/]') {
        $md = MusicDir
        if (-not $md) { Show-Msg "尚未安裝" "要先安裝翻譯才能設定音樂。" "warn"; return }
        try {
            if (-not (Test-Path -LiteralPath $md)) { New-Item -ItemType Directory -Path $md -ErrorAction Stop | Out-Null }
            $leaf = [IO.Path]::GetFileName($f)
            $dst = Join-Path $md $leaf
            if ([IO.Path]::GetFullPath($f) -ine [IO.Path]::GetFullPath($dst)) {
                if (Test-Path -LiteralPath $dst) {
                    if (-not (Confirm-Msg "資料夾裡已經有同名檔" ("音樂資料夾裡已經有「" + $leaf + "」。`n`n要用你剛選的檔【覆蓋】它嗎?(其他地圖若也在用這個檔名,音樂會一起換掉)`n`n選「沿用現有的」就直接用資料夾裡那一個。") "覆蓋" "沿用現有的")) {
                        $f = $leaf
                    } else {
                        Copy-Item -LiteralPath $f -Destination $dst -Force -ErrorAction Stop; $f = $leaf
                    }
                } else {
                    Copy-Item -LiteralPath $f -Destination $dst -Force -ErrorAction Stop; $f = $leaf
                }
            } else { $f = $leaf }
            if (-not (Test-Path -LiteralPath (Join-Path $md $f))) { throw "複製後找不到目的檔" }
        } catch { Show-Msg "失敗" ("音樂檔複製失敗:" + $_.Exception.Message) "error"; return }
    }
    # 直接打檔名(不含路徑)的話,外掛端會去 SpiritZh_music\ 找 —— 檔案不在那裡的話遊戲端只會寫一行 log,
    # 玩家只感覺到「設了但沒音樂」。先驗一次,不然這條路完全無聲。
    $md2 = MusicDir
    if ($md2 -and -not (Test-Path -LiteralPath (Join-Path $md2 $f))) {
        Show-Msg "找不到這個音樂檔" ("音樂資料夾裡沒有「" + $f + "」。`n`n請按「瀏覽…」挑檔(會自動複製進去),或先把檔案放進:`n" + $md2) "warn"
        return
    }
    $script:musicMap[$mapEn] = $f
    Refresh-MusicList
    $TMuFile.Text = ""
    $LblStatus.Text = "狀態:已設定 " + (MapLabel $mapEn) + " 的背景音樂:" + $f + "(按「套用設定」生效)"
})
$BMuDel.Add_Click({
    $i = $LstMusic.SelectedIndex
    if ($i -lt 0) { return }
    $k = @($script:musicMap.Keys)[$i]
    $script:musicMap.Remove($k)
    Refresh-MusicList
})
function Load-CustomConfig {
    $pd = PluginDir; if (-not $pd) { return }
    # ── SpiritZh_custom.txt(規則行沒有固定鍵名,自己逐行讀)──
    $cf = Join-Path $pd "SpiritZh_custom.txt"
    if (Test-Path -LiteralPath $cf) {
        $lines = $null
        try { $lines = @(Get-Content -LiteralPath $cf -Encoding UTF8 -ErrorAction Stop) } catch { $lines = $null }
        if ($null -ne $lines) {
            $script:cuRules.Clear()
            foreach ($l in $lines) {
                $t = $l.Trim().TrimStart([char]0xFEFF)
                if ($t.Length -eq 0 -or $t.StartsWith("//") -or $t.StartsWith("#")) { continue }
                $w = $false
                if ($t.StartsWith("~")) { $w = $true; $t = $t.Substring(1).TrimStart() }
                $i = $t.IndexOf("=")
                if ($i -le 0) { continue }
                [void]$script:cuRules.Add(@{ Word = $w; Src = $t.Substring(0, $i).Trim(); Dst = $t.Substring($i + 1).Trim() })
            }
            Refresh-CuList
            $script:cfgLoaded["custom"] = $true
        }
    } else {
        # 檔案還沒產生:視同空白(套用時會建出來)。清單一定要一起清掉 ——
        # 不清的話,用「瀏覽」換到另一份遊戲資料夾時,上一份的規則會留在畫面上並被寫進新資料夾。
        $script:cuRules.Clear(); Refresh-CuList
        $script:cfgLoaded["custom"] = $true
    }
    # ── SpiritZh_music.txt(被註解掉的地圖行也要收,那是地圖目錄)──
    $mf = Join-Path $pd "SpiritZh_music.txt"
    # 檔案還沒產生(還沒安裝過)→ 視同「已載入的空設定」。Save 那邊本來就有 Test-Path 保護,
    # 不設旗標的話會變成:每次套用都謊報寫入失敗,連「安裝 / 更新翻譯」都被擋住 —— 而安裝正是唯一能把這個檔補回來的動作。
    if (-not (Test-Path -LiteralPath $mf)) { $script:cfgLoaded["music"] = $true; return }
    $mlines = $null
    try { $mlines = @(Get-Content -LiteralPath $mf -Encoding UTF8 -ErrorAction Stop) } catch { return }
    $script:musicMap = New-Object System.Collections.Specialized.OrderedDictionary ([System.StringComparer]::OrdinalIgnoreCase)
    $script:mapList = @()
    $on = $true; $vol = "1.00"
    foreach ($l in $mlines) {
        $t = $l.Trim().TrimStart([char]0xFEFF)
        if ($t.Length -eq 0 -or $t.StartsWith("#")) { continue }
        $isCmt = $t.StartsWith("//")
        if ($isCmt) { $t = $t.Substring(2).Trim() }
        $i = $t.IndexOf("=")
        if ($i -le 0) { continue }
        $k = $t.Substring(0, $i).Trim()
        $v = $t.Substring($i + 1)
        $c = $v.IndexOf("//"); if ($c -ge 0) { $v = $v.Substring(0, $c) }
        $v = $v.Trim()
        if ($k -ieq "enabled") { if (-not $isCmt) { $on = ($v -eq "1") }; continue }
        if ($k -ieq "volume") { if (-not $isCmt) { $vol = $v }; continue }
        # 檔頭說明裡有「// 例:  Nevaris=」這種示範行,剝掉 // 之後看起來也像地圖行 ——
        # 地圖名一律是英數(Sunny Meadows 1 / Windy Desert North),用這個把說明文字擋掉
        if (-not (Test-MapKey $k)) { continue }
        if ($script:mapList -notcontains $k) { $script:mapList += $k }
        if (-not $isCmt -and $v.Length -gt 0) { $script:musicMap[$k] = $v }
    }
    $ChkMusicOn.IsChecked = $on
    $TMuVol.Text = $vol
    # 地圖中文名:從主字典查(查不到就只顯示英文)
    $script:mapZh = @{}
    try {
        $dp = Join-Path $pd "SpiritZh_dict.txt"
        if ((Test-Path -LiteralPath $dp) -and $script:mapList.Count -gt 0) {
            $want = @{}; foreach ($m in $script:mapList) { $want[$m] = $true }
            foreach ($l in (Get-Content -LiteralPath $dp -Encoding UTF8)) {
                $i2 = $l.IndexOf("=")
                if ($i2 -le 0) { continue }
                $k2 = $l.Substring(0, $i2)
                if ($want.ContainsKey($k2) -and -not $script:mapZh.ContainsKey($k2)) { $script:mapZh[$k2] = ($l.Substring($i2 + 1) -replace '<[^>]+>', '').Trim() }
            }
        }
    } catch {}
    $CboMuMap.Items.Clear()
    foreach ($m in $script:mapList) { [void]$CboMuMap.Items.Add((MapLabel $m)) }
    if ($CboMuMap.Items.Count -gt 0) { $CboMuMap.SelectedIndex = 0 }
    Refresh-MusicList
    $script:cfgLoaded["music"] = $true
}
function Save-CustomConfig {
    $pd = PluginDir; if (-not $pd -or -not (Test-Path -LiteralPath $pd)) { return }
    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    # ── custom.txt:註解與空行原樣留著(那份說明對手改的人很重要),規則行整批重寫 ──
    if ($script:cfgLoaded["custom"]) {
        $cf = Join-Path $pd "SpiritZh_custom.txt"
        $head = New-Object System.Collections.Generic.List[string]
        if (Test-Path -LiteralPath $cf) {
            $cur = $null
            try { $cur = @(Get-Content -LiteralPath $cf -Encoding UTF8 -ErrorAction Stop) } catch { $script:saveErr += "SpiritZh_custom.txt:讀取失敗(" + $_.Exception.Message + ")"; $cur = $null }
            if ($null -eq $cur) { $head = $null }
            foreach ($l in $cur) {
                $t = $l.Trim().TrimStart([char]0xFEFF)
                if ($t.Length -eq 0 -or $t.StartsWith("//") -or $t.StartsWith("#")) { $head.Add($l) }
            }
        }
        if ($null -ne $head) {
            while ($head.Count -gt 0 -and $head[$head.Count - 1].Trim().Length -eq 0) { $head.RemoveAt($head.Count - 1) }
            $head.Add("")
            foreach ($r in $script:cuRules) { $head.Add($(if ($r.Word) { "~" } else { "" }) + $r.Src + "=" + $r.Dst) }
            try { Set-Content -LiteralPath $cf -Value $head -Encoding UTF8 -ErrorAction Stop } catch { $script:saveErr += "SpiritZh_custom.txt:寫入失敗(" + $_.Exception.Message + ")" }
        }
    } else { $script:saveErr += "SpiritZh_custom.txt:沒讀成功過,為避免把自訂翻譯清空,這次不寫入" }
    # ── music.txt:整份結構原樣留著(檔頭說明 + 地圖目錄),只改 enabled / volume / 各地圖那一行 ──
    if (-not $script:cfgLoaded["music"]) { $script:saveErr += "SpiritZh_music.txt:沒讀成功過,為避免把地圖音樂清空,這次不寫入"; return }
    $mf = Join-Path $pd "SpiritZh_music.txt"
    if (-not (Test-Path -LiteralPath $mf)) { return }
    $cur2 = $null
    try { $cur2 = @(Get-Content -LiteralPath $mf -Encoding UTF8 -ErrorAction Stop) } catch { $script:saveErr += "SpiritZh_music.txt:讀取失敗(" + $_.Exception.Message + ")"; return }
    $out = New-Object System.Collections.Generic.List[string]
    $done = @{}
    foreach ($l in $cur2) {
        $t = $l.Trim().TrimStart([char]0xFEFF)
        $isCmt = $t.StartsWith("//")
        $body = $(if ($isCmt) { $t.Substring(2).Trim() } else { $t })
        $i = $body.IndexOf("=")
        if ($t.Length -eq 0 -or $t.StartsWith("#") -or $i -le 0) { $out.Add($l); continue }
        $k = $body.Substring(0, $i).Trim()
        # 行尾的「// 說明」不管哪一種鍵都要保住(使用者自己加的備註也算)
        $tail = ""
        $c2 = $body.IndexOf("//", $i)
        if ($c2 -ge 0) { $tail = "   " + $body.Substring($c2) }
        if ($k -ieq "enabled") { $out.Add("enabled=" + $(if ($ChkMusicOn.IsChecked) { "1" } else { "0" }) + $tail); continue }
        if ($k -ieq "volume") { $out.Add("volume=" + (ClampDbl $TMuVol.Text 0 1 1).ToString("0.00", $inv) + $tail); continue }
        # ★ 認不出是地圖名的行(檔頭說明裡的「// 例:  Nevaris=…」之類)原樣放回去,絕對不能改寫 ——
        #   讀端已經用同一把尺跳過它們了,寫端再改它就是單方面把使用者/範本的文字砍掉
        if (-not (Test-MapKey $k)) { $out.Add($l); continue }
        # 地圖行:有設定就寫出來,沒設定就留成註解(保住地圖目錄與中文對照)
        if ($script:musicMap.Contains($k)) { $out.Add($k + "=" + [string]$script:musicMap[$k] + $tail) }
        elseif ($isCmt) { $out.Add($l) }   # 本來就是註解掉的:原樣留著。有人會用「前面加 //」暫時停用某張圖,把檔名砍掉他就得重打
        else { $out.Add("// " + $k + "=" + $tail) }
        $done[$k] = $true
    }
    foreach ($k in $script:musicMap.Keys) { if (-not $done.ContainsKey($k)) { $out.Add($k + "=" + [string]$script:musicMap[$k]) } }
    try { Set-Content -LiteralPath $mf -Value $out -Encoding UTF8 -ErrorAction Stop } catch { $script:saveErr += "SpiritZh_music.txt:寫入失敗(" + $_.Exception.Message + ")" }
}

# ── 熱鍵擷取:點欄位直接按鍵(解掉「打字打不出 F 鍵」的老問題)────────────
function Wire-KeyBox($tb) {
    $tb.IsReadOnly = $true
    $tb.Add_PreviewKeyDown({
        param($sdr, $e)
        $e.Handled = $true
        $k = $e.Key
        if ("$k" -eq "System") { $k = $e.SystemKey }   # F10 是系統鍵,會包在 SystemKey 裡
        if ("$k" -eq "ImeProcessed") { $k = $e.ImeProcessedKey }   # 中文輸入法攔到的鍵,實鍵在 ImeProcessedKey
        $name = "$k"
        if ($name -in @("Escape", "Back", "Delete")) { $sdr.Text = ""; return }
        # 修飾鍵/鎖定鍵:靜默略過(使用者想按 Ctrl+F5 時第一顆是 Ctrl,不該每次都跳警告;本外掛不支援組合鍵)
        if ($name -in @("LeftShift","RightShift","LeftCtrl","RightCtrl","LeftAlt","RightAlt","LWin","RWin","Capital","NumLock","Scroll")) { return }
        # 名稱要照外掛端 InputSysProp 的規則寫,寫錯遊戲裡就靜默沒反應:
        #   字母 G→gKey、數字 5→digit5Key、F5→f5Key、其他具名鍵 Home→homeKey(首字母轉小寫+Key)
        if ($name -match '^F([1-9]|1[0-2])$') { $sdr.Text = $name; return }
        if ($name -match '^[A-Z]$') { $sdr.Text = $name; return }
        if ($name -match '^D([0-9])$') { $sdr.Text = $Matches[1]; return }                  # 上排數字
        if ($name -match '^NumPad([0-9])$') { $sdr.Text = "Numpad" + $Matches[1]; return }  # 數字鍵盤(P 要小寫,InputSystem 屬性是 numpad5Key)
        # 標點鍵:KeyCode 名 → InputSystem 屬性名是 rightBracketKey 這種「首字母小寫+Key」,
        # 所以 KeyCode 名一定要是 InputSystem 認得的拼法(BackQuote→backQuoteKey 對不上 backquoteKey,故意不收)
        $map = @{ "Up"="UpArrow"; "Down"="DownArrow"; "Left"="LeftArrow"; "Right"="RightArrow";
                  "Prior"="PageUp"; "PageUp"="PageUp"; "Next"="PageDown"; "PageDown"="PageDown";   # WPF 對 PageUp 實際 ToString 是 "PageUp",Prior 只是同值別名
                  "Home"="Home"; "End"="End"; "Insert"="Insert";
                  "Space"="Space"; "Tab"="Tab"; "OemMinus"="Minus"; "OemPlus"="Equals";
                  "OemOpenBrackets"="LeftBracket"; "Oem4"="LeftBracket"; "OemCloseBrackets"="RightBracket"; "Oem6"="RightBracket";
                  "OemSemicolon"="Semicolon"; "Oem1"="Semicolon"; "OemQuotes"="Quote"; "Oem7"="Quote";
                  "OemComma"="Comma"; "OemPeriod"="Period"; "OemQuestion"="Slash"; "Oem2"="Slash";
                  "OemPipe"="Backslash"; "Oem5"="Backslash" }   # OemBackslash(ISO 鍵盤左 Shift 旁那顆)不是同一顆實體鍵,故意不收
        if ($map.ContainsKey($name)) { $sdr.Text = $map[$name]; return }
        Show-Msg "不支援的按鍵" ("這顆鍵不支援。可用的按鍵:`n" +
            "‧F1 ~ F12`n‧字母 A ~ Z`n‧數字 0 ~ 9(上排與數字鍵盤都可以)`n" +
            "‧方向鍵、Home / End / Insert / PageUp / PageDown`n‧Space、Tab`n‧- = [ ] ; ' , . / \ 這些標點鍵`n`n" +
            "Esc = 清空(停用這個熱鍵)") "warn"
    })
}
# 鍵名合法性:外掛端 KeyDown 走 InputSystem 時是把鍵名照 InputSysProp 規則轉成 Keyboard 的屬性名
# (G→gKey、5→digit5Key、F5→f5Key、其他→首字母小寫+Key)再反射拿屬性 —— 所以「合法」的定義就是
# 「那個屬性名在遊戲的 Unity.InputSystem.dll 裡真的存在」。直接讀那顆 DLL 的字串表來查,不自己維護白名單
# (白名單一定比外掛實際能吃的窄或寬:手打 Enter/Escape 遊戲能用,卻會被誤標成死鍵)。找不到 DLL 才退回白名單。
# 載入時發現檔內是「]」這種死值就標橘 + 提示,不然使用者以為設好了,遊戲裡按了沒反應又查不出為什麼。
$script:validKeyNames = @("UpArrow","DownArrow","LeftArrow","RightArrow","PageUp","PageDown","Home","End","Insert","Space","Tab",
                          "Minus","Equals","LeftBracket","RightBracket","Semicolon","Quote","Comma","Period","Slash","Backslash")
$script:isKeyProps = $null; $script:isKeyPropsPath = ""
function Get-InputSysProps {
    $dll = $(if ($script:GamePath) { Join-Path $script:GamePath "BepInEx\interop\Unity.InputSystem.dll" } else { "" })
    if ($null -ne $script:isKeyProps -and $script:isKeyPropsPath -eq $dll) { return $script:isKeyProps }
    $set = New-Object 'System.Collections.Generic.HashSet[string]'
    try {
        if ($dll -and (Test-Path -LiteralPath $dll)) {
            $txt = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($dll))
            foreach ($m in [regex]::Matches($txt, 'get_([a-zA-Z0-9]+Key)\x00')) { [void]$set.Add($m.Groups[1].Value) }
        }
    } catch {}
    if ($set.Count -gt 0) { $script:isKeyProps = $set; $script:isKeyPropsPath = $dll }   # 空的不快取:DLL 是跑過遊戲才會有,之後出現要抓得到
    return $set
}
function Test-KeyName([string]$v) {
    $t = ("" + $v).Trim()
    if ($t -eq "") { return $true }
    # 跟外掛端 InputSysProp 一模一樣的轉換
    $prop = $(if ($t.Length -eq 1 -and [char]::IsLetter($t[0])) { [char]::ToLowerInvariant($t[0]) + "Key" }
              elseif ($t.Length -eq 1 -and [char]::IsDigit($t[0])) { "digit" + $t + "Key" }
              elseif ($t.Length -ge 2 -and ($t[0] -eq 'F') -and [char]::IsDigit($t[1])) { "f" + $t.Substring(1) + "Key" }
              else { [char]::ToLowerInvariant($t[0]) + $t.Substring(1) + "Key" })
    $set = Get-InputSysProps
    if ($set.Count -gt 0) { return $set.Contains($prop) }   # HashSet 預設大小寫敏感,跟 GetProperty 一樣
    if ($t -cmatch '^F([1-9]|1[0-2])$' -or $t -cmatch '^[A-Za-z]$' -or $t -match '^[0-9]$' -or $t -cmatch '^Numpad[0-9]$') { return $true }
    return ($script:validKeyNames -ccontains $t)
}
function Mark-KeyBox($tb) {
    if (Test-KeyName $tb.Text) { $tb.ClearValue([System.Windows.Controls.Control]::ForegroundProperty); $tb.ToolTip = $null }
    else {
        $tb.Foreground = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString("#FFB020"))
        $tb.ToolTip = "遊戲認不得「" + $tb.Text + "」這個鍵名 —— 這顆熱鍵目前是死的。點欄位重新按一次鍵就會修好。"
    }
}
# 熱鍵警告要會「自己消失」——以前只在有問題時寫狀態列,改好之後那行警告會一直掛著,
# 跟健檢面板講的話互相矛盾(源的截圖就是這樣抓到的)。
$script:keyWarnShown = $false
function Update-KeyWarn {
    if ($script:IsPure) { return }   # 純翻譯包:「傷害統計與熱鍵」頁已隱藏(公會版殘留的 quality.txt 可能帶壞鍵名)
    $bad = @(@($KDpsKey, $KDpsMode, $KDpsReset, $KDpsEdit, $KToolKey, $KMkKey) |
             Where-Object { -not (Test-KeyName $_.Text) } | ForEach-Object { $_.Text })
    if ($bad.Count -gt 0) {
        $LblStatus.Text = "狀態:⚠ 有熱鍵遊戲認不得(" + ($bad -join "、") + "),已標橘色 —— 到「傷害統計與熱鍵」頁點欄位重新按一次"
        $script:keyWarnShown = $true
    } elseif ($script:keyWarnShown) {
        $LblStatus.Text = "狀態:熱鍵已修好 —— 記得按「套用設定」才會寫進檔案"
        $script:keyWarnShown = $false
    }
}
foreach ($kb in @($KDpsKey, $KDpsMode, $KDpsReset, $KDpsEdit, $KToolKey, $KMkKey, $TPartyBuffKey)) {
    Wire-KeyBox $kb
    $kb.Add_TextChanged({ param($s2, $e2) Mark-KeyBox $s2; Update-KeyWarn })
}

$script:dpsColor = "#D9E0EA"
function Load-DpsConfig {
    $pd = PluginDir; if (-not $pd) { return }
    $q = Read-KV (Join-Path $pd "SpiritZh_quality.txt"); if ($null -eq $q) { return }   # 讀不到就別動畫面
    $KDpsKey.Text   = $(if ($q.ContainsKey("dpskey")) { $q["dpskey"] } else { "F7" })
    $KDpsMode.Text  = $(if ($q.ContainsKey("dpsmodekey")) { $q["dpsmodekey"] } else { "F8" })
    $KDpsReset.Text = $(if ($q.ContainsKey("dpsresetkey")) { $q["dpsresetkey"] } else { "F9" })
    $KDpsEdit.Text  = $(if ($q.ContainsKey("dpseditkey")) { $q["dpseditkey"] } else { "F10" })
    $TDpsX.Text    = $(if ($q["dpsx"]) { $q["dpsx"] } else { "24" })
    $TDpsY.Text    = $(if ($q["dpsy"]) { $q["dpsy"] } else { "-120" })
    $TDpsSize.Text = $(if ($q["dpssize"]) { $q["dpssize"] } else { "34" })
    $TDpsBg.Text   = $(if ($q["dpsbg"]) { $q["dpsbg"] } else { "65" })
    $TDpsLine.Text = $(if ($q["dpsline"]) { $q["dpsline"] } else { "55" })
    $script:dpsColor = $(if ($q["dpscolor"]) { $q["dpscolor"] } else { "#D9E0EA" })
    $BDpsColor.Content = $script:dpsColor
    $CDpsIcon.IsChecked = ($q["dpsicon"] -ne "0")
    # ★ 上限 3:v3.73 新增「王」模式(0 自身 / 1 隊伍 / 2 全部 / 3 王)。
    #   舊的 dpsboss=1 正交開關由外掛端遷移成 dpsmode=3,這裡跟著吃得下 3 就好。
    $CboDpsMode.SelectedIndex = [Math]::Max(0, [Math]::Min(3, (ClampInt $q["dpsmode"] 0 3 0)))
    $TDpsIdle.Text = $(if ($q["dpsidle"]) { $q["dpsidle"] } else { "15" })
    $TDpsRows.Text = $(if ($q["dpsrows"]) { $q["dpsrows"] } else { "10" })
    $TDpsRate.Text = $(if ($q["dpsrate"]) { $q["dpsrate"] } else { "500" })
    $CDpsHp.IsChecked = ($q["dpshp"] -ne "0")
    # v3.74/75 新鍵
    $CDpsTarget.IsChecked = ($q["dpstarget"] -eq "1")
    $CDpsZone.IsChecked = ($q["dpszonereset"] -ne "0")
    $CDpsMonster.IsChecked = ($q["dpsmonster"] -eq "1")
    Set-DpsSkin $(if ($q["dpsskin"]) { $q["dpsskin"] } else { "default" })
    $script:dpsFrame = $(if ($q["dpsframe"]) { $q["dpsframe"] } else { "" })
    $BDpsFrame.Content = $(if ($script:dpsFrame) { $script:dpsFrame } else { "(用風格的)" })
    $script:dpsFrameColor = $(if ($q["dpsframecolor"]) { $q["dpsframecolor"] } else { "" })
    $BDpsFrameColor.Content = $(if ($script:dpsFrameColor) { $script:dpsFrameColor } else { "(用風格的)" })
    $KToolKey.Text = $(if ($q.ContainsKey("toolkey")) { $q["toolkey"] } else { "F6" })
    $mk = ("" + $q["marketkey"]).Trim()
    $ChkMkAuto.IsChecked = ($mk -ieq "auto"); $KMkKey.Text = $(if ($mk -ieq "auto") { "" } else { $mk })
    $KMkKey.IsEnabled = -not $ChkMkAuto.IsChecked
    # 位置類的鍵遊戲會自己寫回(拖曳放開就存),記住載入值 —— 使用者沒動過就不寫,免得把遊戲剛存的位置蓋掉
    $script:posLoaded["dpsx"] = $TDpsX.Text.Trim(); $script:posLoaded["dpsy"] = $TDpsY.Text.Trim()
    foreach ($kb in @($KDpsKey, $KDpsMode, $KDpsReset, $KDpsEdit, $KToolKey, $KMkKey)) { Mark-KeyBox $kb }
    Update-KeyWarn
    $script:cfgLoaded["dps"] = $true
}
$script:posLoaded = @{}
$ChkMkAuto.Add_Click({ $KMkKey.IsEnabled = -not $ChkMkAuto.IsChecked; if ($ChkMkAuto.IsChecked) { $KMkKey.Text = "" } })
function Save-DpsConfig {
    $pd = PluginDir; if (-not $pd -or -not (Test-Path -LiteralPath $pd)) { return }
    if (-not $script:cfgLoaded["dps"]) { $script:saveErr += "SpiritZh_quality.txt(熱鍵/面板):沒讀成功過,為避免覆蓋成空白設定,這次不寫入"; return }
    $kv = @{
        "dpskey"      = $KDpsKey.Text.Trim()
        "dpsmodekey"  = $KDpsMode.Text.Trim()
        "dpsresetkey" = $KDpsReset.Text.Trim()
        "dpseditkey"  = $KDpsEdit.Text.Trim()
        # ★ v3.73:只做防呆,真正的邊界交給外掛主執行緒的 DpsClampPos(它才知道畫面多大)。
        #   舊的 ±2400/±1600 在 3440×1440 / 3840×2160 上會把玩家拖到右邊的面板夾回去。
        "dpsx"        = [string](ClampInt $TDpsX.Text -16384 16384 24)
        "dpsy"        = [string](ClampInt $TDpsY.Text -16384 16384 -120)
        "dpssize"     = [string](ClampInt $TDpsSize.Text 10 72 34)
        "dpsbg"       = [string](ClampInt $TDpsBg.Text 0 100 65)
        "dpsline"     = [string](ClampInt $TDpsLine.Text 0 200 55)
        "dpscolor"    = $(if ($script:dpsColor) { $script:dpsColor } else { "#D9E0EA" })
        "dpsicon"     = $(if ($CDpsIcon.IsChecked) { "1" } else { "0" })
        "dpsmode"     = [string][Math]::Max(0, $CboDpsMode.SelectedIndex)
        "dpsidle"     = [string](ClampInt $TDpsIdle.Text 0 600 15)       # 外掛端上限 600
        "dpsrows"     = [string](ClampInt $TDpsRows.Text 1 10 10)
        "dpsrate"     = [string](ClampInt $TDpsRate.Text 100 3000 500)
        "dpshp"       = $(if ($CDpsHp.IsChecked) { "1" } else { "0" })
        "dpstarget"   = $(if ($CDpsTarget.IsChecked) { "1" } else { "0" })
        "dpszonereset" = $(if ($CDpsZone.IsChecked) { "1" } else { "0" })
        "dpsmonster"  = $(if ($CDpsMonster.IsChecked) { "1" } else { "0" })
        "dpsskin"     = $script:dpsSkin
        "dpsframe"    = $script:dpsFrame
        "dpsframecolor" = $script:dpsFrameColor
        "toolkey"     = $KToolKey.Text.Trim()
        "marketkey"   = $(if ($ChkMkAuto.IsChecked) { "auto" } else { $KMkKey.Text.Trim() })
    }
    # 遊戲會自己寫回的位置鍵:沒動過就不寫(見 Load-DpsConfig)
    if ($TDpsX.Text.Trim() -eq $script:posLoaded["dpsx"]) { $kv.Remove("dpsx") }
    if ($TDpsY.Text.Trim() -eq $script:posLoaded["dpsy"]) { $kv.Remove("dpsy") }
    [void](Save-KV (Join-Path $pd "SpiritZh_quality.txt") $kv)
}
# ── DPS 面板風格 ────────────────────────────────────────────────
$script:dpsSkin = "default"; $script:dpsFrame = ""; $script:dpsFrameColor = ""; $script:dpsSkinSetting = $false
function Set-DpsSkin([string]$name) {
    $nm = ("" + $name).Trim().ToLowerInvariant(); if ($nm.Length -eq 0) { $nm = "default" }
    $script:dpsSkin = $nm
    $script:dpsSkinSetting = $true
    try {
        $hit = 0
        for ($i = 0; $i -lt $CboDpsSkin.Items.Count; $i++) { if (([string]$CboDpsSkin.Items[$i].Tag) -eq $nm) { $hit = $i; break } }
        $CboDpsSkin.SelectedIndex = $hit
        $script:dpsSkin = [string]$CboDpsSkin.Items[$hit].Tag   # 不認得的名字退回 default,跟外掛端一致
    } finally { $script:dpsSkinSetting = $false }
}
$CboDpsSkin.Add_SelectionChanged({
    if ($script:dpsSkinSetting) { return }
    $it = $CboDpsSkin.SelectedItem; if ($null -eq $it) { return }
    $script:dpsSkin = [string]$it.Tag; Mark-Dirty $CboDpsSkin
})
$BDpsFrame.Add_Click({
    $pd = PluginDir
    $ui = $(if ($pd) { Join-Path $pd "SpiritZh_ui" } else { "" })
    $d = New-Object System.Windows.Forms.OpenFileDialog
    $d.Filter = "PNG 圖檔 (*.png)|*.png"
    if ($ui -and (Test-Path -LiteralPath $ui)) { $d.InitialDirectory = $ui }
    if ($d.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return }
    $name = [System.IO.Path]::GetFileName($d.FileName)
    if ($ui -and (Test-Path -LiteralPath $ui)) {
        $dst = Join-Path $ui $name
        if (-not (Test-Path -LiteralPath $dst)) { try { Copy-Item -LiteralPath $d.FileName -Destination $dst -ErrorAction Stop } catch { Show-Msg "複製失敗" $_.Exception.Message "warn" } }
    }
    $script:dpsFrame = $name; $BDpsFrame.Content = $name; Mark-Dirty $BDpsFrame
})
$BDpsFrameClr.Add_Click({ $script:dpsFrame = ""; $BDpsFrame.Content = "(用風格的)"; Mark-Dirty $BDpsFrameClr })
$BDpsFrameColor.Add_Click({
    $r = Pick-CdColor $(if ($script:dpsFrameColor) { $script:dpsFrameColor } else { "#FFFFFF" })
    if ($null -ne $r) {
        $script:dpsFrameColor = $r
        $BDpsFrameColor.Content = $(if ($r) { $r } else { "(用風格的)" })
        Mark-Dirty $BDpsFrameColor
    }
})
$BDpsColor.Add_Click({
    $r = Pick-CdColor $script:dpsColor
    if ($null -ne $r) {
        if ($r -eq "") { $r = "#D9E0EA" }   # 「不使用」= 回預設柔和灰白
        $script:dpsColor = $r; $BDpsColor.Content = $r
    }
})

# ── 詞條品質:各級顏色 / 提示音 / 關注詞條 / 讀寫 ─────────────────────────────
function QColText([string]$v) {
    $t = ("" + $v).Trim()
    if ($t -eq "") { "(不標)" }
    elseif ($t -match '^(?i)(rainbow|rgb)$' -or $t -eq "彩虹") { "★ RGB 循環" }
    else { $t }
}
$script:qCol = @{ "神品"=""; "珍品"=""; "精品"=""; "良品"=""; "凡品"="" }
$script:qColBtn = @{ "神品"=$BQC神品; "珍品"=$BQC珍品; "精品"=$BQC精品; "良品"=$BQC良品; "凡品"=$BQC凡品 }
foreach ($k in @($script:qColBtn.Keys)) {
    $script:qColBtn[$k].Tag = $k
    $script:qColBtn[$k].Add_Click({
        param($sdr, $e2)
        $key = [string]$sdr.Tag
        $r = Pick-BeamColor $script:qCol[$key] ("選擇「" + $key + "」的標示顏色")
        if ($null -ne $r) { $script:qCol[$key] = $r; $sdr.Content = (QColText $r) }
    })
}
$script:qPickTxt = @{ "神品"=$TQP神品; "珍品"=$TQP珍品; "精品"=$TQP精品 }
foreach ($k in @("神品", "珍品", "精品")) {
    $bb = $window.FindName("BQP" + $k); $bb.Tag = $k
    $bb.Add_Click({
        param($sdr, $e2)
        $dlg = New-Object Microsoft.Win32.OpenFileDialog
        $dlg.Filter = "音效檔 (*.wav;*.mp3)|*.wav;*.mp3|全部檔案 (*.*)|*.*"
        $dlg.Title = "選擇提示音檔"
        if ($dlg.ShowDialog($window)) { $script:qPickTxt[[string]$sdr.Tag].Text = $dlg.FileName }
    })
}
# 關注詞條名單:「中文 列舉名」,存檔取列舉名(逗號分隔)。不在名單裡的冷門屬性(使用者手打進 focus= 的)
# 讀進來會原樣保留、寫回時接在後面 —— 不能因為 GUI 不認得就把人家的設定吃掉。
$qFocusList = @(
    "力量 Str","體質 Vit","敏捷 Agi","靈巧 Dex","智力 Int","幸運 Luk","全屬性 AllStats",
    "生命 Hp","魔力 Mp","生命% HpMult","魔力% MpMult",
    "物攻 Atk","魔攻 Matk","物攻% AtkMult","魔攻% MatkMult",
    "物防 Def","魔防 Mdef","物防% DefMult","魔防% MdefMult",
    "命中 Hit","閃避 Flee","暴擊 Crit","暴擊傷害 CritDamage",
    "攻速 AtkSpd","詠唱速度 CastSpd","移動速度 MoveSpd",
    "技能傷害 SkillDamage","最終傷害 FinalDamage","普攻傷害 AutoattackDamage",
    "近戰傷害 DamageMelee","魔法傷害 DamageMagic","遠程傷害 DamageRanged","對王傷害 DamageToBoss",
    "吸血 Leech","吸魔 LeechMp","擊中回血 HealthOnHit","擊中回魔 ManaOnHit",
    "生命回復 HpRegen","魔力回復 MpRegen","治療量 Healing","受治療量 HealingReceived",
    "射程 Range","格擋 Block","經驗加成 ExpRate","掉寶率 DropRate",
    # ── v3.73 補齊(鍵名全部取自遊戲的 StatType 列舉,Cecil 實讀)──
    "冷卻恢復 CooldownRecovery","技能冷卻 SkillCooldown","技能冷卻(單技) CooldownSkill","詠唱時間縮減 CastTimeReduction",
    "技能詠唱時間 SkillCastTime","全元素抗性 AllResist","元素抗性 ElementResist","能量護盾 EnergyShield",
    "生命護壁 HealthBarrier","暴擊抗性 CritDef","完美迴避 PerfectDodge","反傷 ReflectDamage",
    "法術反射 ReflectSpell","盾牌格擋 BlockShield","雙重攻擊 DoubleAttack","法術迴響 SpellEcho",
    "連鎖 Chain","濺射 Splash","技能濺射 SkillSplash","技能穿透 SkillPiercing",
    "技能連鎖數 SkillChains","技能範圍 SkillArea","技能持續 SkillDuration","技能充能 SkillCharges",
    "物防穿透 DefPierce","魔防穿透 MdefPierce","必中 PerfectHit","雙持 DualWield",
    "魔力消耗 MpCost","增益持續 BuffDuration","狀態持續 StatusDuration","負重上限 WeightLimit",
    "治療轉護壁 HealingToBarrier","仇恨倍率 ThreatMult","技能仇恨 SkillThreat","召喚物傷害 SummonDamage",
    "召喚物攻速 SummonAtkSpd","召喚物物攻% SummonAtkMult","召喚物魔攻% SummonMatkMult","召喚物生命% SummonHpMult",
        "召喚物全屬性 SummonAllStats","召喚物暴擊 SummonCrit","召喚物抗性 SummonResist","召喚物減傷 SummonDamageReduction",
    # 實測探針統計:這 6 個在 6401 件樣本裡出現次數都很高(AtkSpdLimit 365 次比 CritDamage 還多)
    "攻速上限 AtkSpdLimit","受近戰傷害 DamageFromMelee","受魔法傷害 DamageFromMagic",
    "生命回復% HpRegenMult","魔力回復% MpRegenMult","施法距離 CastRange")
$script:qFocus = New-Object System.Collections.ArrayList   # 目前勾選的列舉名(含名單外的)
function Refresh-FocusLabel { $LblQFocus.Text = "已勾選 " + $script:qFocus.Count + " 項" }
$BQFocusClr.Add_Click({
    # 只清名單內的;不在名單裡的(使用者手打進 focus= 的冷門屬性)保留 —— 跟對話框裡的「清除」一致
    $known = @($qFocusList | ForEach-Object { ($_ -split " ")[-1] })
    $keep = New-Object System.Collections.ArrayList
    foreach ($f in $script:qFocus) { if ($known -notcontains $f) { [void]$keep.Add($f) } }
    $script:qFocus = $keep; Refresh-FocusLabel
})
$BQFocus.Add_Click({
    $x6 = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="關注詞條(BD 適配)—— 勾你流派在意的屬性" Width="930" SizeToContent="Height" WindowStartupLocation="CenterOwner"
        Background="#151C2B" FontFamily="Microsoft JhengHei UI" FontSize="14" Foreground="#E6EBF2" ShowInTaskbar="False" ResizeMode="NoResize">
  <StackPanel Margin="16">
    <TextBlock Text="物品說明會多一行「關注 N 條・S 分」,只看勾選的詞條算分;不影響主分數與格子顏色。" Foreground="#8A94A8" FontSize="12.5" Margin="0,0,0,10"/>
    <WrapPanel x:Name="Wrap"/>
    <TextBlock x:Name="Extra" Foreground="#8A94A8" FontSize="12" Margin="0,8,0,0"/>
    <DockPanel Margin="0,14,0,0">
      <Button x:Name="Ok" DockPanel.Dock="Right" Content="確定" Width="100" Height="34" Margin="8,0,0,0"/>
      <Button x:Name="Cancel" DockPanel.Dock="Right" Content="取消" Width="90" Height="34"/>
      <Button x:Name="All" DockPanel.Dock="Left" Content="全選" Width="80" Height="34" Margin="0,0,8,0"/>
      <Button x:Name="None" DockPanel.Dock="Left" Content="清除" Width="80" Height="34"/>
      <TextBlock/>
    </DockPanel>
  </StackPanel>
</Window>
'@
    $d = [Windows.Markup.XamlReader]::Parse($x6); if ($window.IsVisible) { $d.Owner = $window }
    try { [void]$d.Resources.MergedDictionaries.Add($window.Resources) } catch {}   # 沿用主視窗的深色勾選框/按鈕樣式
    $wrap = $d.FindName("Wrap"); $boxes = @()
    foreach ($item in $qFocusList) {
        $en = ($item -split " ")[-1]
        $cb = New-Object System.Windows.Controls.CheckBox
        $cb.Content = $item; $cb.Tag = $en; $cb.Width = 218
        $cb.Margin = New-Object System.Windows.Thickness(0, 3, 6, 3)
        $cb.IsChecked = ($script:qFocus -contains $en)
        [void]$wrap.Children.Add($cb); $boxes += $cb
    }
    $known = @($qFocusList | ForEach-Object { ($_ -split " ")[-1] })
    $extra = @($script:qFocus | Where-Object { $known -notcontains $_ })
    if ($extra.Count -gt 0) { $d.FindName("Extra").Text = "另有手動加入的屬性(原樣保留):" + ($extra -join ", ") }
    $d.FindName("All").Add_Click({ foreach ($b in $boxes) { $b.IsChecked = $true } })
    $d.FindName("None").Add_Click({ foreach ($b in $boxes) { $b.IsChecked = $false } })
    $d.FindName("Ok").Add_Click({ $d.DialogResult = $true })
    $d.FindName("Cancel").Add_Click({ $d.DialogResult = $false })
    if (-not $d.ShowDialog()) { return }
    $new = New-Object System.Collections.ArrayList
    foreach ($b in $boxes) { if ($b.IsChecked) { [void]$new.Add([string]$b.Tag) } }
    foreach ($e in $extra) { [void]$new.Add($e) }
    $script:qFocus = $new
    Refresh-FocusLabel
})
function Load-QualityConfig {
    $pd = PluginDir; if (-not $pd) { return }
    $q = Read-KV (Join-Path $pd "SpiritZh_quality.txt"); if ($null -eq $q) { return }
    $ChkQOn.IsChecked = $(if ($q.ContainsKey("enabled")) { $q["enabled"] -eq "1" } else { $true })   # 外掛端是 == "1"
    $defTh = @{ "神品"="86"; "珍品"="75"; "精品"="72"; "良品"="58" }
    foreach ($k in @("神品", "珍品", "精品", "良品")) { $window.FindName("TQ" + $k).Text = $(if ($q["t" + $k]) { $q["t" + $k] } else { $defTh[$k] }) }
    $defCol = @{ "神品"="rgb"; "珍品"="#FFD24A"; "精品"="#A855F7"; "良品"=""; "凡品"="" }
    foreach ($k in @($script:qCol.Keys)) {
        # 鍵存在就照檔案(含刻意留空 = 不標);鍵不存在(舊版檔)才給預設
        $script:qCol[$k] = $(if ($q.ContainsKey("c" + $k)) { "" + $q["c" + $k] } else { $defCol[$k] })
        $script:qColBtn[$k].Content = (QColText $script:qCol[$k])
    }
    $style = ("" + $q["cellstyle"]).ToLowerInvariant()
    $CboQStyle.SelectedIndex = switch ($style) { "name" { 1 } "corner" { 1 } "off" { 2 } default { 0 } }   # corner 是 name 的舊名(外掛端併入 name)
    $TQBlend.Text = $(if ($q["bgblend"]) { $q["bgblend"] } else { "0.85" })
    $CboQName.SelectedIndex = (ClampInt $q["namecolor"] 0 2 0)
    $ChkQTip.IsChecked = $(if ($q.ContainsKey("tooltip")) { $q["tooltip"] -eq "1" } else { $true })
    $ChkQPrice.IsChecked = ($q["showprice"] -ne "0")
    $ChkMktPanel.IsChecked = ($q["mktpanel"] -ne "0")   # 範本預設 1
    $ChkMktMark.IsChecked  = ($q["mktmark"] -ne "0")
    $TQTtl.Text = $(if ($q["pricettl"]) { $q["pricettl"] } else { "3" })
    $ChkQHist.IsChecked = ($q["histprice"] -ne "0")   # 沒這個鍵(舊設定檔)= 開
    $TQHistDays.Text = $(if ($q["histdays"]) { $q["histdays"] } else { "7" })
    foreach ($k in @("神品", "珍品", "精品")) { $script:qPickTxt[$k].Text = "" + $q["pickup" + $k] }
    $TQVol.Text = $(if ($q.ContainsKey("pickupvol") -and ("" + $q["pickupvol"]).Trim() -ne "") { ("" + $q["pickupvol"]).Trim() } else { "1.0" })
    $script:qFocus.Clear()
    foreach ($f in @(("" + $q["focus"]) -split "," | ForEach-Object { $_.Trim() } | Where-Object { $_ })) { [void]$script:qFocus.Add($f) }
    Refresh-FocusLabel
    $TQPanX.Text = $(if ($q["panelx"]) { $q["panelx"] } else { "0" })
    $TQPanY.Text = $(if ($q["panely"]) { $q["panely"] } else { "0" })
    $ChkQDiag.IsChecked = $(if ($q.ContainsKey("diag")) { $q["diag"] -eq "1" } else { $true })   # 範本/外掛預設都是開
    $script:posLoaded["panelx"] = $TQPanX.Text.Trim(); $script:posLoaded["panely"] = $TQPanY.Text.Trim()
    $script:cfgLoaded["quality"] = $true
}
function Save-QualityConfig {
    $pd = PluginDir; if (-not $pd -or -not (Test-Path -LiteralPath $pd)) { return }
    if (-not $script:cfgLoaded["quality"]) { $script:saveErr += "SpiritZh_quality.txt(詞條品質):沒讀成功過,為避免覆蓋成空白設定,這次不寫入"; return }
    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    $kv = @{
        "enabled"   = $(if ($ChkQOn.IsChecked) { "1" } else { "0" })
        "cellstyle" = @("bg", "name", "off")[[Math]::Max(0, $CboQStyle.SelectedIndex)]
        "bgblend"   = (ClampDbl $TQBlend.Text 0 1 0.85).ToString("0.00", $inv)   # 外掛端 0..1,0 有意義(不染)
        "namecolor" = [string][Math]::Max(0, $CboQName.SelectedIndex)
        "tooltip"   = $(if ($ChkQTip.IsChecked) { "1" } else { "0" })
        "showprice" = $(if ($ChkQPrice.IsChecked) { "1" } else { "0" })
        "mktpanel"  = $(if ($ChkMktPanel.IsChecked) { "1" } else { "0" })
        "mktmark"   = $(if ($ChkMktMark.IsChecked) { "1" } else { "0" })
        "pricettl"  = [string](ClampInt $TQTtl.Text 1 60 3)
        "histprice" = $(if ($ChkQHist.IsChecked) { "1" } else { "0" })
        "histdays"  = [string](ClampInt $TQHistDays.Text 1 90 7)
        "pickupvol" = (ClampDbl $TQVol.Text 0 2 1).ToString("0.0##", $inv)   # 1 → 1.0(跟範本一樣),1.25 原樣
        "focus"     = (@($script:qFocus) -join ",")
        "panelx"    = [string](ClampInt $TQPanX.Text -1200 1200 0)
        "panely"    = [string](ClampInt $TQPanY.Text -800 800 0)
        "diag"      = $(if ($ChkQDiag.IsChecked) { "1" } else { "0" })
    }
    $defTh = @{ "神品"=86; "珍品"=75; "精品"=72; "良品"=58 }
    foreach ($k in @("神品", "珍品", "精品", "良品")) { $kv["t" + $k] = [string](ClampInt $window.FindName("TQ" + $k).Text 0 999 $defTh[$k]) }   # 外掛端不夾;101 = 該級永不出現
    foreach ($k in @($script:qCol.Keys)) { $kv["c" + $k] = $script:qCol[$k] }
    foreach ($k in @("神品", "珍品", "精品")) { $kv["pickup" + $k] = $script:qPickTxt[$k].Text.Trim() }
    # 遊戲會自己寫回的位置鍵(右鍵拖曳面板放開就存):沒動過就不寫
    if ($TQPanX.Text.Trim() -eq $script:posLoaded["panelx"]) { $kv.Remove("panelx") }
    if ($TQPanY.Text.Trim() -eq $script:posLoaded["panely"]) { $kv.Remove("panely") }
    [void](Save-KV (Join-Path $pd "SpiritZh_quality.txt") $kv)
}

# ── 摘要 / 全選 / 反選 / 重設 / 篩選籤 ──────────────────────────────────────
# ★★ 新增「畫面」卡片的勾選框時,這裡【和下面的 $BtnRst】都要補一份 ——
#    漏了的話:摘要的分母不對、全選/反選跳過它、按「重設」與「全部重設」都清不掉它。
#    v3.73 的 ChkNum(只隱藏傷害數字)就漏了一次:使用者按重設以為回原廠,數字還在被過濾。
$viewChecks = @($ChkHide, $ChkParty, $ChkGuild, $ChkFriend, $ChkNum, $ChkFx, $ChkMute, $ChkFull)
$perfChecks = @($ChkShadow, $ChkAnim, $ChkFxMine)
function Update-Summary {
    $vc = @($viewChecks | Where-Object { $_.IsChecked }).Count
    $pc = @($perfChecks | Where-Object { $_.IsChecked }).Count
    $cd = ($script:cdMask) -or ($script:cdText) -or ((ClampInt $TxtCdAlpha.Text -1 100 -1) -ge 0) -or
          ((ClampInt $TxtCdX.Text -200 200 0) -ne 0) -or ((ClampInt $TxtCdY.Text -200 200 0) -ne 0) -or
          ((ClampInt $TxtCdSize.Text 0 200 0) -ne 0)
    $LblSum1.Text = "畫面模組: $vc / $($viewChecks.Count)"
    $LblSum2.Text = "效能模組: $pc / $($perfChecks.Count)"
    $LblSum3.Text = "冷卻樣式: " + $(if ($cd) { "自訂" } else { "未使用" })
    $mode = "物品名雙語"
    if ($RbM1.IsChecked) { $mode = "全部雙語" } elseif ($RbM3.IsChecked) { $mode = "物品名純中文" } elseif ($RbM4.IsChecked) { $mode = "原文" }
    $LblSum4.Text = "翻譯模式: " + $mode
}
foreach ($c in ($viewChecks + $perfChecks)) { $c.Add_Checked({ Update-Summary }); $c.Add_Unchecked({ Update-Summary }) }
foreach ($r in @($RbM1, $RbM2, $RbM3, $RbM4)) { $r.Add_Checked({ Update-Summary }) }
$BtnAll.Add_Click({ foreach ($c in $viewChecks) { $c.IsChecked = $true };  Update-Summary })
$BtnInv.Add_Click({ foreach ($c in $viewChecks) { $c.IsChecked = -not $c.IsChecked }; Update-Summary })
$BtnRst.Add_Click({
    $ChkHide.IsChecked = $false
    $ChkParty.IsChecked = $true; $ChkGuild.IsChecked = $true; $ChkFriend.IsChecked = $true
    $ChkNum.IsChecked = $false
    $ChkZero.IsChecked = $true; $ChkMapWrap.IsChecked = $false; $ChkBaseStatEn.IsChecked = $false; $CboChatInvite.SelectedIndex = 1
    $CboBuffPos.SelectedIndex = 0; $TBuffScale.Text = "1.0"; $TBuffX.Text = "0"; $TBuffY.Text = "0"; $TDebuffX.Text = "0"; $TDebuffY.Text = "0"; $TMainX.Text = "0"; $TMainY.Text = "0"; $ChkPartyBuff.IsChecked = $true; $TPartyBuffKey.Text = ""
    $ChkFxSkillOn.IsChecked = $false; $ChkFxSkillDiag.IsChecked = $false
    $ChkDgView.IsChecked = $false; $ChkDgSfx.IsChecked = $false; $ChkDgZero.IsChecked = $false; $ChkDgSearch.IsChecked = $false; $ChkDgArrow.IsChecked = $false; $TDgWatch.Text = ""
    $ChkFx.IsChecked = $false; $ChkMute.IsChecked = $false; $ChkFull.IsChecked = $false
    Update-Summary
})
$BtnResetAll.Add_Click({
    $BtnRst.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Button]::ClickEvent)))
    $script:posLoaded.Clear()   # 使用者明確按了重設 → 位置鍵一定要寫回預設,不能被「等於載入值就不寫」的規則吃掉
    $ChkShadow.IsChecked = $false; $ChkAnim.IsChecked = $false; $ChkFxMine.IsChecked = $false
    $TxtScale.Text = "0"; $TxtSharp.Text = "0"; $TxtFps.Text = "0"
    $CboUp.SelectedIndex = 0; $CboVs.SelectedIndex = 0; $CboMsaa.SelectedIndex = 0
    $script:cdMask = ""; $script:cdText = ""
    $BtnCdMask.Content = "(不改)"; $BtnCdText.Content = "(不改)"
    $TxtCdAlpha.Text = "-1"; $TxtCdX.Text = "0"; $TxtCdY.Text = "0"; $TxtCdSize.Text = "0"
    $RbM2.IsChecked = $true; $CboFont.SelectedIndex = 0; $script:fontFilePath = ""
    $KDpsKey.Text = "F7"; $KDpsMode.Text = "F8"; $KDpsReset.Text = "F9"; $KDpsEdit.Text = "F10"
    $TDpsX.Text = "24"; $TDpsY.Text = "-120"; $TDpsSize.Text = "34"; $TDpsBg.Text = "65"; $TDpsLine.Text = "55"
    $script:dpsColor = "#D9E0EA"; $BDpsColor.Content = "#D9E0EA"; $CDpsIcon.IsChecked = $true
    $CboDpsMode.SelectedIndex = 0; $TDpsIdle.Text = "15"; $TDpsRows.Text = "10"; $TDpsRate.Text = "500"; $CDpsHp.IsChecked = $true
    $CDpsTarget.IsChecked = $false; $CDpsZone.IsChecked = $true; $CDpsMonster.IsChecked = $false
    Set-DpsSkin "default"; $script:dpsFrame = ""; $BDpsFrame.Content = "(用風格的)"; $script:dpsFrameColor = ""; $BDpsFrameColor.Content = "(用風格的)"
    # 光柱回預設(範本 = 總開關關、規則全空;指定物品清單保留 —— 那是使用者一筆筆挑的,不該被「重設」掃掉)
    $ChkBeamOn.IsChecked = $false
    foreach ($k in @($script:beam.Keys)) { $script:beam[$k] = ""; $script:beamBtn[$k].Content = "(不用)" }
    $TChance.Text = "0"; $CboMiss.SelectedIndex = 0; $TDim.Text = "0.35"
    foreach ($k in $hideChecks.Keys) { $hideChecks[$k].IsChecked = $false }
    $HKeepLeg.IsChecked = $true; $CboNameMode.SelectedIndex = 0; $TScale.Text = "1.0"; $TRbSpeed.Text = "3.0"; $ChkBeamDiag.IsChecked = $false
    # 詞條品質回預設(提示音檔路徑與關注詞條清單保留 —— 使用者挑的資料不該被「重設」掃掉)
    $ChkQOn.IsChecked = $true
    $TQ神品.Text = "86"; $TQ珍品.Text = "75"; $TQ精品.Text = "72"; $TQ良品.Text = "58"
    $script:qCol["神品"] = "rgb"; $script:qCol["珍品"] = "#FFD24A"; $script:qCol["精品"] = "#A855F7"; $script:qCol["良品"] = ""; $script:qCol["凡品"] = ""
    foreach ($k in @($script:qCol.Keys)) { $script:qColBtn[$k].Content = (QColText $script:qCol[$k]) }
    $CboQStyle.SelectedIndex = 0; $TQBlend.Text = "0.85"; $CboQName.SelectedIndex = 0
    $ChkQTip.IsChecked = $true; $ChkQPrice.IsChecked = $true; $TQTtl.Text = "3"; $ChkQHist.IsChecked = $true; $TQHistDays.Text = "7"
    $ChkMktPanel.IsChecked = $true; $ChkMktMark.IsChecked = $true   # 範本預設都是 1
    $TQVol.Text = "1.0"; $TQPanX.Text = "0"; $TQPanY.Text = "0"; $ChkQDiag.IsChecked = $true   # 範本預設 diag=1
    $KToolKey.Text = "F6"; $KMkKey.Text = ""; $ChkMkAuto.IsChecked = $false; $KMkKey.IsEnabled = $true
    # 掉落音效回預設(音效檔本身與指定/靜音清單保留 —— 那是使用者挑的資料)
    $TAudCool.Text = "2"; $ChkOwnOnly.IsChecked = $true; $ChkSkipLocked.IsChecked = $true
    $CboFMode.SelectedIndex = 0; $ChkAudDiag.IsChecked = $false
    foreach ($c in $script:fTypeChecks.Values) { $c.IsChecked = $false }
    foreach ($c in $script:fRarChecks.Values) { $c.IsChecked = $false }
    # 游標回範本預設(自訂圖的【檔案】留在 SpiritZh_ui 裡不刪 —— 那是使用者放的東西;只清掉設定裡的引用)
    $script:baRules.Clear(); $script:baAll = ""; $BtnBaAll.Content = $NOBA; Refresh-BaList
    $ChkBaOn.IsChecked = $false; $ChkBaBanner.IsChecked = $true; $TBaVol.Text = "1.0"; $TBaCd.Text = "3000"; $ChkBaDiag.IsChecked = $false
    Reset-ArrowUi
    $ChkCurOn.IsChecked = $false; $CboCurSize.SelectedIndex = 2; $script:curImg = ""; $script:curStyle = ""; CurSelectStyle ""
    $ChkCurAnim.IsChecked = $true; $CboCurAnimSpd.SelectedIndex = 1; $script:curAnimFps = 10
    $TCurHotX.Text = "0"; $TCurHotY.Text = "0"; $ChkCurSoft.IsChecked = $false; $ChkCurReapply.IsChecked = $true
    CurUpdatePreview
    Update-Summary
    $LblStatus.Text = "狀態:已回復預設值(還沒寫入 —— 按「套用設定」才生效)"
})
$chipMap = @{}
$chipMap[$ChipView] = @($CardView, $CardChat, $CardBuff, $CardFxSkill); $chipMap[$ChipPerf] = @($CardPerf); $chipMap[$ChipCd] = @($CardCd); $chipMap[$ChipInst] = @($CardInst)
function Set-Filter($active) {
    if ($script:IsPure) { return }   # 純翻譯包:功能卡片已 Collapsed,ChipAll 會把它們設回 Visible
    foreach ($chip in @($ChipAll) + @($chipMap.Keys)) { $chip.IsChecked = ($chip -eq $active) }
    foreach ($chip in $chipMap.Keys) {
        foreach ($card in $chipMap[$chip]) { $card.Visibility = $(if ($active -eq $ChipAll -or $chip -eq $active) { "Visible" } else { "Collapsed" }) }
    }
}
$ChipAll.Add_Click({ Set-Filter $ChipAll })
$ChipView.Add_Click({ Set-Filter $ChipView })
$ChipPerf.Add_Click({ Set-Filter $ChipPerf })
$ChipCd.Add_Click({ Set-Filter $ChipCd })
$ChipInst.Add_Click({ Set-Filter $ChipInst })
# 深色模式:目前只有深色。★ 舊版是「取消勾選 → 程式強制勾回去」,那看起來就像工具壞了 ——
#   使用者點了、勾勾自己彈回來、還跳一行字。改成明確停用 + 滑鼠提示,不要假裝可以點。
#   (實測全檔 270 個硬寫的十六進位顏色、要跟主題換的有 231 處,而那 6 支具名筆刷
#    只被引用 10 次 = 形同虛設;淺色不是換色票,是要把「深藍黑底 + 青色發光」整套重新設計。)
# ── 介面縮放(SpiritZh_gui.txt 的 uiscale,從舊工具搬來的想法)────────────
#   WPF 直接對根容器套 LayoutTransform 就好,視窗尺寸跟著乘。改了要重開工具才生效
#  (套在已經排好版的視窗上會讓 ScrollViewer 的量測亂掉,與其修一堆邊角,不如老實重開)。
$script:uiScale = 1.0
function Apply-UiScale([double]$k) {
    if ($k -lt 0.7) { $k = 0.7 } elseif ($k -gt 3.0) { $k = 3.0 }
    $script:uiScale = $k
    if ([Math]::Abs($k - 1.0) -lt 0.001) { return }
    try {
        $root = $window.Content
        $root.LayoutTransform = New-Object System.Windows.Media.ScaleTransform($k, $k)
        $window.Width = [Math]::Min(1100 * $k, [System.Windows.SystemParameters]::WorkArea.Width)
        $window.Height = [Math]::Min(1040 * $k, [System.Windows.SystemParameters]::WorkArea.Height)
    } catch { }
}
function Set-UiScaleCombo([double]$k) {
    $script:uiScaleSetting = $true
    try {
        $best = 0; $bd = 99.0
        for ($i = 0; $i -lt $CboUiScale.Items.Count; $i++) { $d = [Math]::Abs([double]$CboUiScale.Items[$i].Tag - $k); if ($d -lt $bd) { $bd = $d; $best = $i } }
        $CboUiScale.SelectedIndex = $best
    } finally { $script:uiScaleSetting = $false }
}
$CboUiScale.Add_SelectionChanged({
    if ($script:uiScaleSetting) { return }
    $it = $CboUiScale.SelectedItem; if ($null -eq $it) { return }
    $k = [double]$it.Tag
    $pd = PluginDir
    if ($pd -and (Test-Path -LiteralPath $pd)) { [void](Save-KV (Join-Path $pd "SpiritZh_gui.txt") @{ "uiscale" = $k.ToString("0.##", [System.Globalization.CultureInfo]::InvariantCulture) }) }
    $LblStatus.Text = "狀態:介面縮放已記住(" + $it.Content + ")—— 重開設定工具生效"
})

# ── 選色(常用色 + HEX;冷卻用途不提供彩虹)──────────────────────────────────
function Pick-CdColor([string]$current) {
    $x2 = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="選擇顏色" Width="336" SizeToContent="Height" WindowStartupLocation="CenterOwner"
        Background="#151C2B" FontFamily="Microsoft JhengHei UI" Foreground="#E6EBF2" ResizeMode="NoResize">
  <StackPanel Margin="14">
    <WrapPanel x:Name="Swatches"/>
    <DockPanel Margin="0,10,0,0">
      <TextBlock Text="色碼:" VerticalAlignment="Center" Margin="0,0,6,0"/>
      <TextBox x:Name="Hex" Background="#101827" Foreground="#E6EBF2" BorderBrush="#33405A" Padding="6,4"/>
    </DockPanel>
    <TextBlock Text="#RRGGBB(六位);留空 = 不改" Foreground="#8A94A8" FontSize="12" Margin="0,4,0,10"/>
    <UniformGrid Columns="3">
      <Button x:Name="Ok" Content="確定" Margin="0,0,6,0" Padding="10,6"/>
      <Button x:Name="No" Content="不使用" Margin="0,0,6,0" Padding="10,6"/>
      <Button x:Name="Cancel" Content="取消" Padding="10,6"/>
    </UniformGrid>
  </StackPanel>
</Window>
'@
    $dlg = [Windows.Markup.XamlReader]::Parse($x2)
    $dlg.Owner = $window
    $sw = $dlg.FindName("Swatches"); $hex = $dlg.FindName("Hex")
    $hex.Text = $current
    foreach ($cc in @("#000000","#1B1B1B","#B00020","#FF8A1E","#FFD24A","#2E7D32","#00B4D8","#3B82F6","#7C4DFF","#FF4D9D","#FFFFFF","#9AA0A6")) {
        $b = New-Object System.Windows.Controls.Button
        $b.Width = 44; $b.Height = 26
        $b.Margin = New-Object System.Windows.Thickness(0, 0, 6, 6)
        $b.Background = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString($cc))
        $b.Tag = $cc
        $b.Add_Click({ param($s, $e) $hex.Text = [string]$s.Tag }.GetNewClosure())
        [void]$sw.Children.Add($b)
    }
    $script:pcOut = $null
    $dlg.FindName("Ok").Add_Click({
        $t = $hex.Text.Trim().ToUpperInvariant()
        if ($t -eq "") { $script:pcOut = ""; $dlg.DialogResult = $true; return }
        if ($t -match '^#?[0-9A-F]{6}$') {
            if (-not $t.StartsWith("#")) { $t = "#" + $t }
            $script:pcOut = $t; $dlg.DialogResult = $true
        } else {
            Show-Msg "格式不對" "色碼要是 #RRGGBB 六位(例 #000000),或留空表示不改。" "warn"
        }
    })
    $dlg.FindName("No").Add_Click({ $script:pcOut = ""; $dlg.DialogResult = $true })
    $dlg.FindName("Cancel").Add_Click({ $dlg.DialogResult = $false })
    if ($dlg.ShowDialog()) { return $script:pcOut } else { return $null }
}
$BtnCdMask.Add_Click({
    $r = Pick-CdColor $script:cdMask
    if ($null -ne $r) { $script:cdMask = $r; $BtnCdMask.Content = $(if ($r) { $r } else { "(不改)" }); Update-Summary }
})
$BtnCdText.Add_Click({
    $r = Pick-CdColor $script:cdText
    if ($null -ne $r) { $script:cdText = $r; $BtnCdText.Content = $(if ($r) { $r } else { "(不改)" }); Update-Summary }
})

# ── 字型 ─────────────────────────────────────────────────────────────────────
$CboFont.Add_SelectionChanged({
    if ($CboFont.SelectedIndex -ge 0) {
        $script:fontFilePath = ""
        $LblFontNow.Text = $(if ($CboFont.SelectedIndex -eq 0) { "目前:遊戲預設" } else { "目前:" + [string]$CboFont.SelectedItem })
        # 即時預覽(從舊工具搬來):系統字型直接換 FontFamily;遊戲預設那項用工具自己的字
        try {
            if ($CboFont.SelectedIndex -eq 0) { $LblFontPreview.FontFamily = $window.FontFamily }
            else { $LblFontPreview.FontFamily = New-Object System.Windows.Media.FontFamily([string]$CboFont.SelectedItem) }
        } catch { }
    }
})
$BtnFontFile.Add_Click({
    $fd = New-Object System.Windows.Forms.OpenFileDialog
    $fd.Filter = "字型檔 (*.ttf;*.otf;*.ttc)|*.ttf;*.otf;*.ttc"
    if ($fd.ShowDialog() -ne "OK") { return }
    $pd = PluginDir
    if (-not $pd -or -not (Test-Path -LiteralPath $pd)) {
        Show-Msg "尚未安裝" "要先安裝翻譯才能載入字型檔。" "warn"; return
    }
    try {
        $dstDir = Join-Path $pd "SpiritZh_fonts"
        if (-not (Test-Path -LiteralPath $dstDir)) { New-Item -ItemType Directory -Path $dstDir -ErrorAction Stop | Out-Null }
        # 中文檔名會讓底層字型載入器【靜默失敗】(v3.70 血淚)—— 直接複製成純英數檔名
        $ext = [System.IO.Path]::GetExtension($fd.FileName)
        $ascii = ($fd.FileName.ToCharArray() | ForEach-Object { [int]$_ } | Where-Object { $_ -gt 126 }).Count -eq 0
        $dstName = $(if ($ascii) { [System.IO.Path]::GetFileName($fd.FileName) }
                     else {
                        $md5 = [System.Security.Cryptography.MD5]::Create()
                        $hash = [BitConverter]::ToString($md5.ComputeHash([Text.Encoding]::UTF8.GetBytes($fd.FileName))).Replace("-","").Substring(0,8).ToLower()
                        "zhfont_" + $hash + $ext
                     })
        $dst = Join-Path $dstDir $dstName
        # 選回 SpiritZh_fonts 裡已經匯入過的檔:來源就是目的,不能自己複製自己(Copy-Item 會丟「無法以自身覆寫」)
        if ([IO.Path]::GetFullPath($fd.FileName).TrimEnd('\') -ine [IO.Path]::GetFullPath($dst).TrimEnd('\')) {
            Copy-Item -LiteralPath $fd.FileName -Destination $dst -Force -ErrorAction Stop
        }
        if (-not (Test-Path -LiteralPath $dst)) { throw "複製後找不到目的檔 " + $dst }
        $script:fontFilePath = $dst
        $LblFontNow.Text = "目前:字型檔 " + [System.IO.Path]::GetFileName($fd.FileName) + $(if (-not $ascii) { "(已轉存為英數檔名)" } else { "" })
        $LblStatus.Text = "狀態:字型檔已載入 —— 按「套用設定」寫入,進遊戲看效果"
    } catch {
        Show-Msg "失敗" ("字型檔複製失敗:" + $_.Exception.Message) "error"
    }
})

# ── 數字欄位的上下箭頭 ───────────────────────────────────────────────────────
# WPF 沒有內建 NumericUpDown。與其在 XAML 裡把三十幾個欄位一個個改成 Grid+按鈕(改動大、容易改錯),
# 這裡在啟動時用程式把 TextBox【原地包起來】:父容器裡把 TextBox 換成一個 Grid(左=原本的框、右=兩顆箭頭),
# 寬度/邊距/Grid.Row/Column 這些附加屬性原樣搬過去。XAML 一個字都不用動。
$SpinXamlUp = @'
<RepeatButton xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
              xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
              Delay="400" Interval="55" Focusable="False" Cursor="Hand">
  <RepeatButton.Template>
    <ControlTemplate TargetType="RepeatButton">
      <Border x:Name="b" Background="#0C1E31" BorderBrush="#2A6C93" BorderThickness="1" CornerRadius="3" Margin="0,0,0,1">
        <Path Data="M 0,4 L 4.5,0 L 9,4 Z" Fill="#5FE0FF" HorizontalAlignment="Center" VerticalAlignment="Center"/>
      </Border>
      <ControlTemplate.Triggers>
        <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="Background" Value="#123A56"/></Trigger>
        <Trigger Property="IsPressed" Value="True"><Setter TargetName="b" Property="Background" Value="#0A2438"/></Trigger>
      </ControlTemplate.Triggers>
    </ControlTemplate>
  </RepeatButton.Template>
</RepeatButton>
'@
$SpinXamlDown = $SpinXamlUp.Replace('M 0,4 L 4.5,0 L 9,4 Z', 'M 0,0 L 4.5,4 L 9,0 Z').Replace('Margin="0,0,0,1"', 'Margin="0,1,0,0"')

# ★ $delta 一定要宣告型別:呼叫端寫 `Spin-Apply $tb -1` 時,PowerShell 會把裸的 -1 當成【字串】傳進來
#   (它先當參數名解析),於是 "-1" * 0.05 變成字串重複、整個算式歪掉。宣告 [int] 就會自動轉回數字。
function Spin-Apply($tb, [int]$delta) {
    $cfg = $tb.Tag
    if (-not $cfg) { return }
    $cur = 0.0
    if (-not [double]::TryParse(("" + $tb.Text).Trim(), [System.Globalization.NumberStyles]::Float,
                                [System.Globalization.CultureInfo]::InvariantCulture, [ref]$cur)) {
        # 欄位裡是亂打的字 → 直接回預設值,不要再加減一格(使用者是想修正,不是想微調)
        $tb.Text = $(if ([int]$cfg.dec -le 0) { [string][int]$cfg.def } else { ([double]$cfg.def).ToString("0." + ("#" * [int]$cfg.dec), [System.Globalization.CultureInfo]::InvariantCulture) })
        return
    }
    $v = $cur + ($delta * [double]$cfg.step)
    $v = [Math]::Max([double]$cfg.min, [Math]::Min([double]$cfg.max, $v))
    $v = [Math]::Round($v, [int]$cfg.dec)
    $tb.Text = $(if ([int]$cfg.dec -le 0) { [string][int]$v } else { $v.ToString("0." + ("#" * [int]$cfg.dec), [System.Globalization.CultureInfo]::InvariantCulture) })
}
function Add-Spinner($tb, [double]$min, [double]$max, [double]$step, [int]$dec, [double]$def) {
    if (-not $tb) { return }
    $parent = $tb.Parent
    if (-not $parent -or -not $parent.Children) { return }
    $i = $parent.Children.IndexOf($tb)
    if ($i -lt 0) { return }
    $tb.Tag = @{ min = $min; max = $max; step = $step; dec = $dec; def = $def }
    # 把版面屬性搬到外層容器
    $w = $tb.Width; $mg = $tb.Margin; $ha = $tb.HorizontalAlignment
    $gr = [System.Windows.Controls.Grid]::GetRow($tb); $gc = [System.Windows.Controls.Grid]::GetColumn($tb)
    $gcs = [System.Windows.Controls.Grid]::GetColumnSpan($tb); $dk = [System.Windows.Controls.DockPanel]::GetDock($tb)
    $grid = New-Object System.Windows.Controls.Grid
    $grid.Margin = $mg; $grid.HorizontalAlignment = $ha
    # 外層要比原本的框【寬 20px】(箭頭欄 17 + 間距 3),不然箭頭會吃掉輸入框的字
    if (-not [double]::IsNaN($w)) { $grid.Width = $w + 20 } else { $grid.MinWidth = 78 }
    $c1 = New-Object System.Windows.Controls.ColumnDefinition; $c1.Width = New-Object System.Windows.GridLength(1, "Star")
    $c2 = New-Object System.Windows.Controls.ColumnDefinition; $c2.Width = New-Object System.Windows.GridLength(17)
    [void]$grid.ColumnDefinitions.Add($c1); [void]$grid.ColumnDefinitions.Add($c2)
    $parent.Children.RemoveAt($i)
    $tb.Margin = New-Object System.Windows.Thickness(0, 0, 3, 0)
    $tb.ClearValue([System.Windows.FrameworkElement]::WidthProperty)
    $tb.ClearValue([System.Windows.FrameworkElement]::HorizontalAlignmentProperty)
    [System.Windows.Controls.Grid]::SetColumn($tb, 0)
    [void]$grid.Children.Add($tb)
    $col = New-Object System.Windows.Controls.Grid
    $r1 = New-Object System.Windows.Controls.RowDefinition; $r1.Height = New-Object System.Windows.GridLength(1, "Star")
    $r2 = New-Object System.Windows.Controls.RowDefinition; $r2.Height = New-Object System.Windows.GridLength(1, "Star")
    [void]$col.RowDefinitions.Add($r1); [void]$col.RowDefinitions.Add($r2)
    $up = [Windows.Markup.XamlReader]::Parse($SpinXamlUp)
    $dn = [Windows.Markup.XamlReader]::Parse($SpinXamlDown)
    $up.Tag = $tb; $dn.Tag = $tb
    $up.Add_Click({ param($sdr, $e2) Spin-Apply $sdr.Tag 1 })
    $dn.Add_Click({ param($sdr, $e2) Spin-Apply $sdr.Tag -1 })
    [System.Windows.Controls.Grid]::SetRow($up, 0); [System.Windows.Controls.Grid]::SetRow($dn, 1)
    [void]$col.Children.Add($up); [void]$col.Children.Add($dn)
    [System.Windows.Controls.Grid]::SetColumn($col, 1)
    [void]$grid.Children.Add($col)
    [System.Windows.Controls.Grid]::SetRow($grid, $gr); [System.Windows.Controls.Grid]::SetColumn($grid, $gc)
    [System.Windows.Controls.Grid]::SetColumnSpan($grid, $gcs); [System.Windows.Controls.DockPanel]::SetDock($grid, $dk)
    $parent.Children.Insert($i, $grid)
    # 滑鼠滾輪與上下鍵也能調(游標在框上滾就好)
    $tb.Add_PreviewMouseWheel({ param($sdr, $e2) Spin-Apply $sdr $(if ($e2.Delta -gt 0) { 1 } else { -1 }); $e2.Handled = $true })
    $tb.Add_PreviewKeyDown({
        param($sdr, $e2)
        if ("$($e2.Key)" -eq "Up")   { Spin-Apply $sdr 1;  $e2.Handled = $true }
        elseif ("$($e2.Key)" -eq "Down") { Spin-Apply $sdr -1; $e2.Handled = $true }
    })
}
# 每個欄位的範圍/級距要跟外掛端一致(夾範圍的邏輯在各 Save-*Config 裡)
foreach ($sp in @(
    @($TxtVol, 0, 100, 5, 0, 35),
    @($TxtScale, 0, 4, 0.05, 2, 0), @($TxtSharp, 0, 1, 0.05, 2, 0), @($TxtFps, 0, 1000, 10, 0, 0),
    @($TxtCdAlpha, -1, 100, 5, 0, -1), @($TxtCdX, -200, 200, 2, 0, 0), @($TxtCdY, -200, 200, 2, 0, 0), @($TxtCdSize, 0, 120, 2, 0, 0),
    @($TCurHotX, 0, 256, 1, 0, 0), @($TCurHotY, 0, 256, 1, 0, 0),
    @($TDpsX, -16384, 16384, 10, 0, 24), @($TDpsY, -16384, 16384, 10, 0, -120), @($TDpsSize, 10, 72, 1, 0, 34),
    @($TDpsBg, 0, 100, 5, 0, 65), @($TDpsLine, 0, 200, 5, 0, 55), @($TDpsIdle, 0, 600, 1, 0, 15),
    @($TDpsRows, 1, 10, 1, 0, 10), @($TDpsRate, 100, 3000, 50, 0, 500),
    @($TQ神品, 0, 999, 1, 0, 86), @($TQ珍品, 0, 999, 1, 0, 75), @($TQ精品, 0, 999, 1, 0, 72), @($TQ良品, 0, 999, 1, 0, 58),
    @($TQBlend, 0, 1, 0.05, 2, 0.85), @($TQTtl, 1, 60, 1, 0, 3), @($TQHistDays, 1, 90, 1, 0, 7), @($TQVol, 0, 2, 0.1, 1, 1),
    @($TQPanX, -1200, 1200, 10, 0, 0), @($TQPanY, -800, 800, 10, 0, 0),
    @($TChance, 0, 100, 0.5, 2, 0), @($TDim, 0.05, 0.9, 0.05, 2, 0.35), @($TScale, 0.2, 5, 0.1, 1, 1), @($TRbSpeed, 0.3, 30, 0.5, 1, 3),
    @($TAudCool, 0, 30, 0.5, 1, 2), @($TMuVol, 0, 1, 0.05, 2, 1),
    @($TVolLegendary, 5, 300, 5, 0, 100), @($TVolPurple, 5, 300, 5, 0, 100), @($TVolUnique, 5, 300, 5, 0, 100),
    @($TVolRare, 5, 300, 5, 0, 100), @($TVolCommon, 5, 300, 5, 0, 100), @($TVolGreen, 5, 300, 5, 0, 100)
)) { Add-Spinner $sp[0] $sp[1] $sp[2] $sp[3] $sp[4] $sp[5] }

# ── 每組標題旁邊的「?」說明鈕 ───────────────────────────────────────────────
# 一樣不動 XAML:啟動時走一次 logical tree(用 logical 不用 visual —— 沒被選到的分頁
# 還沒實體化,visual tree 裡是空的),看到標題文字對得上下面這張表就在它旁邊插一顆 ?。
# 滑鼠指著看簡述、點下去開完整說明。
$HelpText = @{
"畫面" = "主城人多的時候,把其他玩家整個藏起來。`n`n‧只影響你自己的畫面,別人看你還是正常的。`n‧自己、怪物、掉落物永遠不會被藏。`n‧下面三個「照常顯示」是例外名單:勾了隊友,隊友就不會被藏。`n‧特效/音效那兩項是額外的:人藏起來了但技能光還在,就把它們也勾上。`n‧「完全隱藏」最徹底(連他們的行為一起停用),偶爾會有相容性問題,所以標實驗性。"
"效能" = "三個各自獨立的省效能開關,要開哪個就開哪個。`n`n‧關閉陰影:省最多,因為陰影等於整個場景再畫一次。`n‧鏡頭外不計算:只在主城/人多時有感,畫面內的玩家動作完全正常。`n‧特效只留自己的:場面亂的時候最有效,傷害數字不受影響。`n`n三項都只動你這台電腦的顯示層,不會改遊戲數值。"
"技能冷卻顯示" = "遊戲原廠的冷卻遮罩偏灰白、不太看得出哪個技能還在轉,秒數又壓在圖案正中央擋住圖示。這一區就是拿來改這兩件事。`n`n‧全部留空 / 0 = 完全維持原樣。`n‧想看清楚冷卻:遮罩顏色選偏黑的,再把不透明度拉到 70 以上。`n‧不透明度 -1 是「不要改」,跟 0(全透明)不一樣。`n‧秒數位移 X 正=往右、Y 正=往上,挪到角落就不會擋圖案。`n`n只改外觀,冷卻時間本身一秒都不會變。"
"安裝與維護" = "‧安裝 / 更新翻譯:把翻譯檔複製進遊戲。你在「翻譯與字型」選的顯示模式與字型,是按這顆才真的寫進去的。`n`n‧產生診斷報告:收集遊戲版本、外掛清單與 log。出問題時把它貼出來最快。`n`n‧移除翻譯:刪掉外掛檔案、恢復原版。你的設定檔會留著,重裝就回來了。`n`n三個都會開一個黑色的命令視窗,跑完自己會回到這個畫面。"
"自訂參數(效能模組專屬)" = "這一區是給另外裝了效能模組的人用的;沒裝就整區留空,不影響任何東西。`n`n‧渲染解析度:用比較低的解析度算圖再放大。0.75 是畫質與 FPS 的甜蜜點,0 = 不縮放。`n‧放大濾鏡:把縮小的畫面補回來的方法,FSR 最通用。解析度保持 0 或 1 時濾鏡完全不會作用。`n‧選 STP 時 MSAA 一定要設「關閉」,否則 STP 會被引擎直接停用。`n‧幀率上限 0 = 不限。想壓顯卡溫度就設 60。"
"顯示模式" = "決定遊戲裡的名詞怎麼顯示,四選一。`n`n‧全部雙語:什麼都「中文 English」,查攻略、跟外國人組隊最方便。`n‧物品名雙語(預設):只有物品/地圖/怪物雙語,介面其他地方純中文 —— 大部分人用這個。`n‧物品名純中文:畫面最乾淨,但看國外資料時要自己換算。`n‧原文:完全不翻譯。只想用掉寶音效、隱藏玩家這些功能的人選它。`n`n改完要按下方「套用設定」,遊戲裡約 5 秒生效,不用重開。"
"自訂字型" = "換掉整個遊戲介面的字型。`n`n‧「遊戲預設」= 不改字型。`n‧支援 .ttf / .otf / .ttc。挑好的檔會自動複製到外掛資料夾,之後你把原檔刪了也不影響。`n‧檔名有中文會自動轉存成英數檔名 —— 底層載入器碰到中文檔名會安靜地失敗,不轉的話就是「按了沒反應」。`n‧選完要按「套用設定」,再進遊戲看。"
"掉寶音效" = "遊戲本身只有金光/紫光/綠光有聲音,藍光跟白光是沒有的 —— 這一區可以幫每種光柱各配一個音效。`n`n‧左邊下拉選音效、右邊那格是音量 %(100 = 原音量,最高可到 300)。`n‧※ 精華與採集花是【藍光】不是紫光,想聽採集提示要設藍光那一列。`n‧「貴重礦石」比紫光優先,用來把高階礦石從一堆紫光裡分出來。`n‧支援 wav / mp3,ogg 不支援請先轉檔。`n‧防洗版冷卻:一波掉一堆時只響第一聲;設 0 = 每件都響。`n`n不知道從哪開始,就按「一鍵套用作者推薦」。"
"什麼情況才播" = "上面配好音效之後,這裡再過濾一次「哪些掉落才值得響」。`n`n‧全部不勾 = 所有掉落都播。`n‧物品分類、稀有度、指定物品是三組獨立條件。`n‧「且」(預設)= 每一組都要符合才響,這是多數人要的。例:勾了獨特又指定了物品清單,就只有【獨特而且在清單裡】的才會響。`n‧「或」= 符合任一組就響,這時候物品清單等於沒作用。`n‧別人的掉落(灰色/鎖定中)可以單獨關掉,人多的地方會安靜很多。"
"完全靜音的物品" = "這是黑名單,優先於上面所有條件。`n`n命中的物品連【遊戲自己原本的掉落聲】也會一起壓掉 —— 所以就算你一個自訂音效都沒設,也可以只用這一項讓某些東西別再吵你。`n`n※ 侷限:攔截的地方分不出「這一聲是哪一件掉落發出來的」,同一個 0.8 秒內連掉好幾件時,靜音可能會連隔壁那件的原音一起壓掉。"
"音效檔" = "所有音效檔都放在遊戲的 BepInEx\plugins\SpiritZh_sounds\ 裡面。`n`n‧用「選音效檔…」挑檔案會自動複製進去,之後在下拉選單就找得到。`n‧自己直接丟檔案進資料夾的話,要按「重新掃描音效檔」才會出現在清單裡。`n‧支援 wav / mp3;ogg 不支援,請先轉檔。"
"自訂光柱" = "光柱是遊戲本身就有的東西,這裡只是把它換個顏色 —— 沒有光柱的掉落(白光雜物)不會憑空多長出一根。`n`n這個勾勾是整區的總開關,不勾的話下面的規則全部不作用。`n`n純顯示層:只改你自己畫面上那顆光柱,不碰數值、不送封包,別人看到的顏色不變。"
"自動規則" = "由上往下比對,先命中的先算。優先序:指定物品 > 王卡 > 王裝 > 獨特裝備 > 紫光整組 > 低掉率。`n`n‧顏色留空(不用)= 這一條不啟用。`n‧「紫光整組」範圍最大(卡片/神器/鑲嵌材料都算),建議只有這一組才用彩虹,不然畫面會很吵。`n‧「稀有掉落」看的是掉率:填 0.5 就是掉率低於 0.5% 的才染色;填 0 = 不用這條。`n‧不確定有沒有生效,先把「測試」設一個顏色,所有掉落都會被染 —— 確認完記得改回留空。"
"沒命中任何規則的掉落" = "上面規則都沒中的那些雜物,要怎麼處理。`n`n‧照常顯示(預設)。`n‧半透明:壓暗,還看得到但不搶眼;下面那格 0.05~0.9 是壓多暗。`n‧隱藏光柱:只收掉那根光,名稱跟圖示還在。`n‧隱藏掉落:整個消失(光柱+名稱+圖示),地上最乾淨。怕誤殺就把「傳說不隱藏」勾著。`n`n※ 有命中規則、或在「指定物品」清單裡的東西【永遠不會被隱藏】—— 你點名要看的一定看得到。"
"指定物品" = "點名的物品,優先於上面所有自動規則。`n`n‧不管掉率多高、稀有度多低,只要在這張清單裡就一定會用你指定的顏色標出來,也絕對不會被隱藏。`n‧拿來標你正在收的材料最有用。"
"外觀參數" = "‧地上物品名稱的字色:預設跟著光柱顏色走;想固定成一個顏色就選「自訂顏色」。`n‧光柱放大倍率:只有命中規則的掉落會放大,1.0 = 原本大小。想遠遠就看到就設 1.5~2。`n‧RGB 循環速度:選了彩虹的規則轉一圈要幾秒,數字越小變色越快。`n‧診斷模式平常不用開;顏色沒變的時候打開它,再去按「產生診斷報告」。"
"詞條品質快篩" = "這是整個「詞條品質」分頁的總開關 —— 格子標色、說明評級行、撿起提示音都靠它。`n`n分數怎麼算:該件裝備【最好的 3 條】詞條 roll(0~100)的平均。神器沒有 roll,改看「顯示值頂滿幾條」(3/3 神品、2/3 珍品、1/3 精品)。`n`n門檻由高到低比對,顏色留空 = 這一級不標示。「精品」那一條是有沒有顏色的分界線 —— 覺得畫面太花就把它調高。`n`n※ v3.72 起「神品」預設是【RGB 循環】(跑馬燈)。v3.70~v3.71 曾改成固定金色 #FFB020,但實測那個顏色跟珍品的 #FFD24A 幾乎分不出來(色差只有正常需求的一半),所以改回來。覺得跑馬燈吵的話建議填 #FF5A1F(橘紅),不要用回 #FFB020。`n`n純顯示層:只在你自己畫面上標好壞,不改數值、不送封包。"
"格子顯示與染色" = "背包/倉庫/攤位裡,達標的裝備長什麼樣。`n`n‧整格背景染色(預設):最顯眼。`n‧名稱前加 ◆ 記號:最低調,適合不想要滿畫面顏色的人。`n‧染色濃度 1 = 整格塗滿、0.45 = 淡淡一層、0 = 不染。`n‧「物品名稱也跟著變色」只在整格染色樣式下有作用;選「所有等級都染」會蓋掉遊戲自己的詞綴色(例如「風暴」的黃字),介意就選「只染 RGB 循環那一級」。"
"物品說明評級行" = "滑鼠指到裝備時,說明的最前面多一行評級。`n`n例:【珍品】詞條品質 77 分・頂滿 1 條・潛力…`n`n不想看到就取消勾選,格子染色不受影響。"
"自動查市價" = "這是本外掛唯一會對伺服器產生流量的功能,所以講清楚:`n`n‧只有在市場搜尋視窗開著時(以及關閉後 60 秒內)才會動作。`n‧呼叫的是遊戲自己的搜尋入口,送出的內容跟你手動搜尋完全一樣。`n‧全域 2 秒節流,同一件物品在你設定的分鐘數內不重查。`n`n它畢竟是自動觸發的,不保證絕無風險 —— 會擔心就把它取消勾選,其他功能完全不受影響。"
"撿起提示音" = "撿到達標的裝備/神器那一瞬間播一聲。`n`n‧留空的等級不提示。`n‧音量倍率 0 = 關掉提示音但保留檔案路徑;1.0 = 原音量,超過 1.0 不會更大聲。`n‧支援 wav / mp3。`n`n為什麼不做成光柱?因為詞條 roll 是你撿起來那一刻伺服器才給的,東西還在地上時誰也不知道它幾分。"
"關注詞條(BD 適配)" = "勾你這套流派在意的屬性,物品說明就會多一行「關注 N 條・S 分」。`n`n只拿你勾的那幾種詞條來算,不影響主分數,也不影響格子顏色。`n`n用途:專治「分數很高但一條都不是我要的」—— 一眼看穿。"
"市場進階濾鏡面板位置" = "兩格都是像素,0 = 遊戲預設位置(正 X 往右、正 Y 往上)。`n`n覺得面板擋畫面就把它挪開。其實遊戲裡【按住右鍵拖曳面板】更快,放開的時候會自動把座標寫回這兩格。`n`n※ 別跟左下角那塊【市場分析】搞混:那是本外掛自己畫的面板,用【左鍵】按住拖(不是右鍵),位置記在 mktx / mkty。點它一下可以展開/收起。"
"熱鍵" = "點一下欄位,然後【直接按你要的那顆鍵】,不用打字。`n`n‧支援 F1~F12、字母、數字、數字鍵盤、方向鍵等。`n‧按 Esc = 清空,那個功能就停用。`n‧「移動面板」留空 = 面板鎖住位置,不會被誤拖。`n`n跟其他外掛撞鍵的話,視窗下面會提醒你。"
"面板位置與顯示" = "‧位置 X/Y 是像素。其實遊戲裡進編輯模式(預設 F10)直接左鍵拖曳更快,放開會自動記住,寫回這兩格。`n‧背景暗度 0 = 不加背景,只留文字。`n‧行距是百分比:55 比較緊湊、80 比較鬆。`n‧圖示直接取自遊戲本身,不需要額外下載圖檔。"
"統計行為" = "‧開機預設模式:進遊戲時先顯示哪一種。「自身(依技能拆)」看自己哪一招輸出高;隊伍/全部看誰在打。`n  ※ v3.72 起「全部」= 所有玩家 + 召喚物,【不再列怪物打出來的傷害】—— 那是「你被打了多少」,混進輸出排行會讓佔比失真。想看回來就在 SpiritZh_quality.txt 設 dpsmonster=1。`n  ※ 面板上的「(召喚物)」以前寫「(寵)」,那會讓人以為是寵物打的 —— 遊戲裡寵物不造成傷害,造成傷害的是召喚物。`n  ※ 治療技能打傷不死系怪物的那些傷害【本來就會統計】(會顯示成該技能自己的名字,例如「治療術 Heal」),不用另外設定。`n‧脫戰重算:離開戰鬥幾秒後自動歸零;0 = 只用熱鍵手動歸零。`n‧顯示列數:面板最多幾行。`n‧刷新間隔:越小越跟手、越大越省效能,500 毫秒很順。`n‧血量% 只在隊伍/全部模式下顯示,打王時一眼看出誰快掛了。`n`n純被動統計,不對伺服器發任何請求。"
"其他熱鍵" = "‧叫出設定工具:遊戲裡按一下就直接打開這個視窗。要先用安裝程式裝過一次,遊戲才知道安裝包放在哪。`n‧帶入進階濾鏡:舊功能,預設留空關閉 —— 查價已經改成自動顯示在物品說明上了(在「詞條品質」頁)。`n‧一樣是點欄位直接按鍵,Esc = 清空。"
"自訂翻譯" = "把譯文改成你自己喜歡的說法,而且更新翻譯包不會蓋掉這裡。`n`n‧這裡的規則【優先於】內建字典。`n‧不勾「句中也換」= 整格剛好等於原文才換。例:寫 Attack → 攻擊力,只有「Attack」那一格會變,「Attack: 120」不會。`n‧勾「句中也換」= 句子裡出現就換。例:寫 HP → 生命值,「HP: 120」「Max HP」都會變。`n‧太短的原文要小心誤傷(寫 MP 會連 MP Regen 一起動到)—— 把長的也寫一條就好,長的自動優先。`n‧點清單裡的項目會把它填回上面,改完再按「加入 / 更新」就是修改;同一個原文只會留一條。"
"王技提示音" = "王(Boss / 精英)開始詠唱指定技能的那一刻播提示音,可以同時在畫面中央跳一行字。`n`n★ 這是【提前】預警 —— 遊戲的施法訊息帶了詠唱時間,所以你有時間閃或打斷,不是挨打後才響。`n`n‧不知道要填什麼:勾「收集模式」→ 打一場王 → 回來按「從 log 匯入」,偵測到的技能會自動列出來,你只要挑音效。`n‧「通用提示音」= 所有王技都響,想先聽聽看有哪些技能會觸發時最快。`n‧玩家的寵物/坐騎/召喚物在這款遊戲也算「怪物」,但會被排除,不會被寵物吵。`n‧音效檔放 BepInEx\plugins\SpiritZh_sounds\(wav / mp3,不支援 ogg)。`n`n純本地播放,不對伺服器發任何請求。"
"滑鼠游標放大" = "把遊戲的滑鼠游標換成比較大、比較好找的。純視覺,點擊位置完全不變。`n`n‧先試遊戲自己的:設定 → General 本來就有幾個游標可以換,夠用就不必開這裡。`n‧勾了之後,遊戲設定裡選的游標會【看起來沒作用】—— 是被這裡蓋過去了,你的選擇沒有被改掉,取消勾選就回來。`n‧改完要按下方「套用設定」,遊戲裡約 5 秒生效。"
"游標樣式與大小" = "13 種內建樣式(經典/銀鉻/霓虹藍/冰晶/黃金/紫晶/烈焰/翠葉/彩虹/黑鋼/血紅/像素/準星),點一個就換;點擊位置外掛會自己算(箭頭=尖端、準星=正中央)。`n`n特效動畫:每種樣式附 10 張動畫圖,外掛每 0.1 秒換一張(箭頭本體不動、特效在動)。只是把原本「每 2 秒重設游標」的頻率拉高,不吃效能;遊戲裡會閃的話取消勾選就回靜態。`n`n內建圖每種只有五張(32 / 48 / 64 / 96 / 128),所以大小是五選一,不是無段縮放。`n`n‧64 是建議值。`n‧96 和 128 打王時會蓋住怪物血條跟地上的圈,而且不少電腦畫不出這麼大的系統游標 —— 套用後沒變大,到下面「游標沒有變大?」那張卡處理。`n‧選了自訂圖時這裡不會作用,自訂圖一律照原尺寸。"
"換成自己的圖" = "選一張 PNG 當游標。大小請先在繪圖軟體調好(建議 64×64 以內),這裡不會幫你縮放。`n`n‧從別的地方選的圖會自動複製一份到 BepInEx\plugins\SpiritZh_ui\,外掛只認那個資料夾。`n‧「真正的點擊位置」= 這張圖上的哪一個點才算你點到的地方。箭頭類選「左上角」,準星類選「正中央」。`n‧位置超出圖片範圍會有黃字提醒,那時候游標會歪掉。"
"游標沒有變大?" = "照順序試:`n`n① 按過「套用設定」了嗎?`n② 大小選到 96 / 128 了嗎?`n③ 勾「改用遊戲自己畫游標」—— 一定畫得出來,代價是移動時會慢半拍,人多的主城、8 人副本打王掉幀時最有感。`n`n‧「持續修正」是給「游標偶爾自己變回原本的」這種情況用的,每 2 秒修正一次,成本可以忽略;如果發現拖曳物品的手勢游標會閃回箭頭,就把它取消。`n‧都試過還是沒變 = 圖檔沒被讀到,按最上方的「重新檢查」看圖檔在不在。"
"自訂地圖背景音樂" = "指定某張地圖要放你自己的曲子。`n`n‧走遊戲自己的音樂播放器,所以遊戲的音樂音量、靜音、切到背景暫停都照常生效。`n‧支援 mp3 / wav;ogg 不支援(播放走 Windows 內建解碼),請先轉檔。`n‧從外面挑的檔會自動複製進 SpiritZh_music\ 資料夾,之後你把原檔刪了也不影響。`n‧音量倍率是在遊戲音樂音量之上再乘一次。`n‧沒指定的地圖完全不介入,照放遊戲原曲。`n‧地圖清單是外掛跑過遊戲之後產生的 —— 新地圖沒出現就先進遊戲走一趟。"
}
$HelpXaml = @'
<Button xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Width="17" Height="17" Padding="0" Cursor="Hand" Focusable="False"
        Margin="7,1,3,0" VerticalAlignment="Center">
  <Button.Template>
    <ControlTemplate TargetType="Button">
      <Border x:Name="b" Background="#0C1E31" BorderBrush="#2A6C93" BorderThickness="1" CornerRadius="9">
        <TextBlock Text="?" Foreground="#5FE0FF" FontSize="11.5" FontWeight="Bold" FontFamily="Segoe UI"
                   HorizontalAlignment="Center" VerticalAlignment="Center" Margin="0,-1,0,0"/>
      </Border>
      <ControlTemplate.Triggers>
        <Trigger Property="IsMouseOver" Value="True">
          <Setter TargetName="b" Property="Background" Value="#123A56"/>
          <Setter TargetName="b" Property="BorderBrush" Value="#5FE0FF"/>
        </Trigger>
      </ControlTemplate.Triggers>
    </ControlTemplate>
  </Button.Template>
</Button>
'@
if ($script:IsPure) { $HelpText["顯示模式"] = $HelpText["顯示模式"].Replace("只想用掉寶音效、隱藏玩家這些功能的人選它。", "對照或除錯時用。") }
function Get-LogicalTextBlocks($node, $acc) {
    if ($node -is [System.Windows.Controls.TextBlock]) { [void]$acc.Add($node) }
    foreach ($c in [System.Windows.LogicalTreeHelper]::GetChildren($node)) {
        if ($c -is [System.Windows.DependencyObject]) { Get-LogicalTextBlocks $c $acc }
    }
}
function Add-HelpButtons {
    $h1 = $null
    try { $h1 = $window.FindResource("H1") } catch {}
    $acc = New-Object System.Collections.ArrayList
    Get-LogicalTextBlocks $window $acc
    $n = 0
    foreach ($tb in $acc) {
        $t = "" + $tb.Text
        if (-not $HelpText.ContainsKey($t)) { continue }
        # 標題文字可能剛好跟別的地方撞,再認一次樣式才動手
        if ($h1 -and -not [object]::ReferenceEquals($tb.Style, $h1)) { continue }
        $par = $tb.Parent
        if (-not ($par -is [System.Windows.Controls.Panel])) { continue }
        $i = $par.Children.IndexOf($tb)
        if ($i -lt 0) { continue }
        $btn = [Windows.Markup.XamlReader]::Parse($HelpXaml)
        $btn.Tag = @{ t = $t; b = $HelpText[$t] }
        $btn.Add_Click({ param($sdr, $e2) Show-Msg $sdr.Tag.t $sdr.Tag.b })
        $tip = New-Object System.Windows.Controls.ToolTip
        $tipTb = New-Object System.Windows.Controls.TextBlock
        $tipTb.Text = $HelpText[$t]
        $tipTb.TextWrapping = "Wrap"; $tipTb.MaxWidth = 430; $tipTb.LineHeight = 21
        $tipTb.Foreground = "#DCE6F2"
        $tip.Content = $tipTb
        $tip.Background = "#0A1626"; $tip.BorderBrush = "#2A6C93"; $tip.Foreground = "#DCE6F2"
        $tip.Padding = New-Object System.Windows.Thickness(11, 8, 11, 9)
        $tip.MaxWidth = 460
        $btn.ToolTip = $tip
        [System.Windows.Controls.ToolTipService]::SetInitialShowDelay($btn, 250)
        [System.Windows.Controls.ToolTipService]::SetShowDuration($btn, 120000)
        if ($par -is [System.Windows.Controls.StackPanel] -and "$($par.Orientation)" -eq "Horizontal") {
            # 標題本來就跟圖示排成一列 —— 直接插在標題後面
            $par.Children.Insert($i + 1, $btn)
        } else {
            # 標題是直排容器的一個小孩(沒有圖示那一列)—— 幫它包一層橫排,版面屬性照搬
            $row = New-Object System.Windows.Controls.StackPanel
            $row.Orientation = "Horizontal"
            $row.Margin = $tb.Margin
            [System.Windows.Controls.Grid]::SetRow($row, [System.Windows.Controls.Grid]::GetRow($tb))
            [System.Windows.Controls.Grid]::SetColumn($row, [System.Windows.Controls.Grid]::GetColumn($tb))
            [System.Windows.Controls.Grid]::SetColumnSpan($row, [System.Windows.Controls.Grid]::GetColumnSpan($tb))
            [System.Windows.Controls.DockPanel]::SetDock($row, [System.Windows.Controls.DockPanel]::GetDock($tb))
            $par.Children.RemoveAt($i)
            $tb.Margin = New-Object System.Windows.Thickness(0)
            [void]$row.Children.Add($tb)
            [void]$row.Children.Add($btn)
            $par.Children.Insert($i, $row)
        }
        $n++
    }
    return $n
}
$null = Add-HelpButtons

# ══ 市價表(v3.71.1)══════════════════════════════════════════════════════
# 網友問「能不能做一個在工具上即時查價的工具」。老實說:【不行】,而且不是難做是不通 ——
# 查價是在遊戲裡呼叫遊戲自己的市場搜尋入口(FishNet RPC,塞在遊戲客戶端那條已登入的連線上),
# 伺服器認的是「這條連線 + 這個角色」,不是可以複製出去的通行證;回應也是伺服器反過來打回
# 遊戲客戶端、外掛靠攔截才拿得到。這個工具是遊戲外的獨立程式,那三樣一樣都沒有。
# 硬要做只剩「自己寫一個假客戶端」= 自製封包,作者不做那件事。
# 所以改成反方向:外掛把【已經查到的】價格寫進 SpiritZh_prices.txt,這裡讀它。
# 對伺服器零額外流量,代價是「只有你逛過的東西才有價格」。
function Get-PricePath { $pd = PluginDir; if ($pd) { Join-Path $pd "SpiritZh_market.txt" } else { "" } }       # 掛單觀測(市場分析用)
function Get-PricesLogPath { $pd = PluginDir; if ($pd) { Join-Path $pd "SpiritZh_prices.txt" } else { "" } }   # 查價紀錄(物品說明的「市價」行用)

# 讀外掛落下來的掛單紀錄。一列 = 一筆掛單被看到的一次觀測。
# 欄位:時間 物品ID 譯名 分類 單價 可買數量 已售數量 上架數量 賣家 掛單編號
function Read-Market {
    $r = @{ ok = $false; err = ""; rows = @() }
    $path = Get-PricePath
    if (-not $path) { $r.err = "找不到遊戲資料夾"; return $r }
    if (-not (Test-Path -LiteralPath $path)) { $r.err = "還沒有任何紀錄"; return $r }
    $txt = $null
    try {
        # ★ 外掛隨時可能在 append,裸讀會鎖住它 —— 而外掛那邊的寫入包在 catch{} 裡,
        #   被我們鎖住的話那一批掛單會安靜消失。一定要 ReadWrite 共用。
        $fs = [System.IO.File]::Open($path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        try {
            $sr = New-Object System.IO.StreamReader($fs, [System.Text.Encoding]::UTF8)
            try { $txt = $sr.ReadToEnd() } finally { $sr.Dispose() }
        } finally { $fs.Dispose() }
    } catch { $r.err = "讀不到:$($_.Exception.Message)"; return $r }
    $rows = New-Object System.Collections.ArrayList
    foreach ($ln in ($txt -split "`r?`n")) {
        if ([string]::IsNullOrWhiteSpace($ln) -or $ln.StartsWith("//")) { continue }
        $f = $ln -split "`t"
        if ($f.Count -lt 10) { continue }
        $price = 0L; [void][long]::TryParse($f[4], [ref]$price)
        if ($price -le 0) { continue }
        $avail = 0; [void][int]::TryParse($f[5], [ref]$avail)
        $sold = 0;  [void][int]::TryParse($f[6], [ref]$sold)
        $init = 0;  [void][int]::TryParse($f[7], [ref]$init)
        [void]$rows.Add([pscustomobject]@{
            T = $f[0]; Id = $f[1]; Zh = $f[2]; Cat = $f[3]
            Price = $price; Avail = $avail; Sold = $sold; Init = $init
            Seller = $f[8]; Lid = $f[9]
        })
    }
    $r.ok = $true; $r.rows = @($rows)
    return $r
}

# 把觀測切成一批一批的「造訪」。
# ★ 不能用「同一秒」當邊界:玩家捲動清單時,同一頁的列會分散在好幾秒裡寫進來,
#   那樣切會變成「掛單 1 筆」這種假數字(實測踩過)。改用時間間隔:超過 3 分鐘沒看到就算新的一批。
function Split-Batches($items) {
    $ci = [Globalization.CultureInfo]::InvariantCulture
    $sorted = @($items | Sort-Object T)
    $out = New-Object System.Collections.ArrayList
    $cur = New-Object System.Collections.ArrayList
    $prev = $null
    foreach ($x in $sorted) {
        $t = [datetime]::MinValue
        [void][datetime]::TryParseExact($x.T, "yyyy-MM-dd HH:mm:ss", $ci, [Globalization.DateTimeStyles]::None, [ref]$t)
        if ($null -ne $prev -and ($t - $prev).TotalSeconds -gt 180) { [void]$out.Add(@($cur)); $cur = New-Object System.Collections.ArrayList }
        [void]$cur.Add($x); $prev = $t
    }
    if ($cur.Count -gt 0) { [void]$out.Add(@($cur)) }
    # ★ 前面加逗號:PowerShell 的 return 會把集合【展開】,不加的話這個「陣列的陣列」
    #   會被攤平成一大包,批次數就變成筆數(實測 52 批 = 52 筆單一觀測被當成 52 次造訪)。
    return , @($out)
}
function Get-MarketSummary($rows) {
    $out = New-Object System.Collections.ArrayList
    foreach ($grp in ($rows | Group-Object Id)) {
        $batches = Split-Batches $grp.Group
        $last = $batches[-1]
        $prices = @($last | ForEach-Object { $_.Price } | Sort-Object)
        $min = $prices[0]
        $med = if ($prices.Count % 2 -eq 1) { $prices[[int](($prices.Count - 1) / 2)] } else { [long](($prices[$prices.Count / 2 - 1] + $prices[$prices.Count / 2]) / 2) }
        $sold = ($last | Measure-Object Sold -Sum).Sum
        $delta = ""
        if ($batches.Count -ge 2) {
            $pm = @($batches[-2] | ForEach-Object { $_.Price } | Sort-Object)[0]
            if ($pm -gt 0) {
                $d = [math]::Round((($min - $pm) / [double]$pm) * 100)
                if ($d -gt 0) { $delta = "▲$d%" } elseif ($d -lt 0) { $delta = "▼$([math]::Abs($d))%" } else { $delta = "—" }
            }
        }
        $nm = $last[0].Zh; if (-not $nm) { $nm = $grp.Name }
        [void]$out.Add([pscustomobject]@{
            名稱 = $nm
            分類 = $last[0].Cat
            最低價 = $min.ToString("N0")
            中位數 = $med.ToString("N0")
            掛單 = @($last | Select-Object -ExpandProperty Lid -Unique).Count
            已售 = $(if ($sold) { $sold.ToString("N0") } else { "0" })
            漲跌 = $delta
            最後更新 = $(if ($last[0].T.Length -ge 16) { $last[0].T.Substring(5, 11) } else { $last[0].T })
            批次 = $batches.Count
            Sort = $last[0].T
            Id = $grp.Name
        })
    }
    return @($out)
}

function Read-Prices {
    # 回傳 @{ ok=$bool; err=$str; rows=@(...) };rows 每筆 = 一次查價紀錄
    $r = @{ ok = $false; err = ""; rows = @() }
    $path = Get-PricesLogPath   # ★ 以前誤用 Get-PricePath(market.txt),欄位會整個錯位
    if (-not $path) { $r.err = "找不到遊戲資料夾"; return $r }
    if (-not (Test-Path -LiteralPath $path)) { $r.err = "還沒有任何紀錄"; return $r }
    $lines = $null
    try {
        # ★ 外掛隨時可能在 append,裸讀會互相卡住 —— 而且外掛那邊的寫入是包在 catch{} 裡的,
        #   被我們鎖住的話那一筆價格會【安靜地消失】。一定要用 ReadWrite 共用模式。
        $fs = [System.IO.File]::Open($path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        try {
            $sr = New-Object System.IO.StreamReader($fs, [System.Text.Encoding]::UTF8)
            try { $lines = $sr.ReadToEnd() -split "`r?`n" } finally { $sr.Dispose() }
        } finally { $fs.Dispose() }
    } catch { $r.err = "讀不到:$($_.Exception.Message)"; return $r }
    $rows = New-Object System.Collections.ArrayList
    foreach ($ln in $lines) {
        if ([string]::IsNullOrWhiteSpace($ln)) { continue }
        if ($ln.StartsWith("//")) { continue }
        $f = $ln -split "`t"
        if ($f.Count -lt 6) { continue }
        $units = @()
        if ($f.Count -ge 7 -and $f[6]) {
            foreach ($u in ($f[6] -split ",")) { $v = 0L; if ([long]::TryParse($u, [ref]$v) -and $v -gt 0) { $units += $v } }
        }
        $t = [datetime]::MinValue
        [void][datetime]::TryParseExact($f[0], "yyyy-MM-dd HH:mm:ss", [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$t)
        $min = 0L; [void][long]::TryParse($f[3], [ref]$min)
        $cnt = 0;  [void][int]::TryParse($f[4], [ref]$cnt)
        # v3.76 第 8 欄 "v2" = 清單確定是這件物品自己的;舊列的最低價/清單可能是整頁別件物品的,遊戲裡不顯示
        $ver = $(if ($f.Count -ge 8) { $f[7].Trim() } else { "" })
        $su = @($units | Sort-Object)
        $lo = $(if ($su.Count -gt 0) { $su[0] } else { 0L }); $hi = $(if ($su.Count -gt 0) { $su[-1] } else { 0L })
        $mid = 0L
        if ($su.Count -gt 0) { $mid = if ($su.Count % 2 -eq 1) { $su[[int](($su.Count - 1) / 2)] } else { [long](($su[$su.Count / 2 - 1] + $su[$su.Count / 2]) / 2) } }
        [void]$rows.Add([pscustomobject]@{
            Time = $t; Raw = $f[1]; Zh = $f[2]; Min = $min; Cnt = $cnt
            More = ($f[5] -eq "1"); Units = $units
            Ver = $ver; Valid = ($ver -eq "v2" -and $su.Count -gt 0); Lo = $lo; Mid = $mid; Hi = $hi
        })
    }
    $r.ok = $true; $r.rows = @($rows)
    return $r
}

function Get-PriceSummary($rows) {
    # 同一個物品只留【最新那一次】當現價,但筆數/最早時間要看整段歷史
    $g = $rows | Group-Object Raw
    $out = New-Object System.Collections.ArrayList
    foreach ($grp in $g) {
        $sorted = @($grp.Group | Sort-Object Time)
        $last = $sorted[-1]
        $med = 0L
        if ($last.Units.Count -gt 0) {
            $u = @($last.Units | Sort-Object)
            $med = if ($u.Count % 2 -eq 1) { $u[[int](($u.Count - 1) / 2)] } else { [long](($u[$u.Count / 2 - 1] + $u[$u.Count / 2]) / 2) }
        }
        # 漲跌:拿最新的最低價跟【上一次不同時間】的最低價比
        $delta = ""
        if ($sorted.Count -ge 2) {
            $prev = $sorted[-2]
            if ($prev.Min -gt 0 -and $last.Min -gt 0) {
                $d = [math]::Round((($last.Min - $prev.Min) / [double]$prev.Min) * 100)
                if ($d -gt 0) { $delta = "▲$d%" } elseif ($d -lt 0) { $delta = "▼$([math]::Abs($d))%" } else { $delta = "—" }
            }
        }
        # ★ 顯示用的欄位一律先格式化成字串(金額要千分位、時間要短)。
        #   但排序不能用字串 —— 另外留 Sort/SortMin 兩個原始值欄位給 Sort-Object 用。
        [void]$out.Add([pscustomobject]@{
            名稱 = $(if ($last.Zh) { $last.Zh } else { $last.Raw })
            原文 = $last.Raw
            最低價 = $last.Min.ToString("N0")
            中位數 = $(if ($med -gt 0) { $med.ToString("N0") } else { "—" })
            掛單 = $(if ($last.More) { "$($last.Cnt)+" } else { "$($last.Cnt)" })
            漲跌 = $delta
            最後更新 = $last.Time.ToString("MM-dd HH:mm")
            紀錄數 = $sorted.Count
            Sort = $last.Time
            SortMin = $last.Min
        })
    }
    return @($out)
}

$PriceXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="市價表" Width="980" Height="640" WindowStartupLocation="CenterOwner"
        Background="#050B14" FontFamily="Microsoft JhengHei UI" FontSize="14" Foreground="#DCE6F2">
  <Window.Resources>
    <Style TargetType="TextBox">
      <Setter Property="Background" Value="#0C1E31"/><Setter Property="Foreground" Value="#E6EDF6"/>
      <Setter Property="BorderBrush" Value="#1D5F8A"/><Setter Property="Padding" Value="6,5"/>
      <Setter Property="CaretBrush" Value="#5FE0FF"/>
    </Style>
    <Style TargetType="Button">
      <Setter Property="Background" Value="#0C2438"/><Setter Property="Foreground" Value="#CFE6F5"/>
      <Setter Property="BorderBrush" Value="#2A6C93"/><Setter Property="Padding" Value="12,6"/>
    </Style>
    <Style TargetType="GridViewColumnHeader">
      <Setter Property="Background" Value="#0E2438"/><Setter Property="Foreground" Value="#9FD8F5"/>
      <Setter Property="BorderBrush" Value="#1D5F8A"/><Setter Property="Padding" Value="8,6"/>
      <Setter Property="HorizontalContentAlignment" Value="Left"/>
    </Style>
    <Style TargetType="ListView">
      <Setter Property="Background" Value="#0A1626"/><Setter Property="Foreground" Value="#DCE6F2"/>
      <Setter Property="BorderBrush" Value="#1D5F8A"/>
    </Style>
    <!-- 預設的選取樣式是【淺藍底】,配上我們的淺色字等於整列看不見 —— 一定要自己蓋掉 -->
    <Style TargetType="ListViewItem">
      <Setter Property="Foreground" Value="#DCE6F2"/><Setter Property="Padding" Value="2,3"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ListViewItem">
            <Border x:Name="bd" Background="Transparent" BorderBrush="Transparent" BorderThickness="0,0,0,1" Padding="{TemplateBinding Padding}">
              <GridViewRowPresenter Content="{TemplateBinding Content}" Columns="{TemplateBinding GridView.ColumnCollection}"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="bd" Property="Background" Value="#0F2C44"/></Trigger>
              <Trigger Property="IsSelected" Value="True">
                <Setter TargetName="bd" Property="Background" Value="#123A56"/>
                <Setter TargetName="bd" Property="BorderBrush" Value="#5FE0FF"/>
                <Setter Property="Foreground" Value="#EAF6FF"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Window.Resources>
  <DockPanel Margin="14">
    <DockPanel DockPanel.Dock="Top" Margin="0,0,0,10">
      <Button x:Name="PRefresh" DockPanel.Dock="Right" Content="重新整理" Margin="8,0,0,0"/>
      <Button x:Name="POpenDir" DockPanel.Dock="Right" Content="開啟檔案位置"/>
      <TextBlock Text="搜尋:" VerticalAlignment="Center" Margin="0,0,6,0" Foreground="#8FB6D0"/>
      <TextBox x:Name="PFind" Width="260" HorizontalAlignment="Left"/>
    </DockPanel>
    <TextBlock x:Name="PInfo" DockPanel.Dock="Bottom" Margin="0,8,0,0" TextWrapping="Wrap"
               Foreground="#8FA6BC" FontSize="12.5"/>
    <Grid>
      <Grid.RowDefinitions><RowDefinition Height="*"/><RowDefinition Height="188"/></Grid.RowDefinitions>
      <ListView x:Name="PList" Grid.Row="0">
        <ListView.View>
          <GridView>
            <GridViewColumn Header="物品" Width="232" DisplayMemberBinding="{Binding 名稱}"/>
            <GridViewColumn Header="分類" Width="76" DisplayMemberBinding="{Binding 分類}"/>
            <GridViewColumn Header="最低價" Width="96" DisplayMemberBinding="{Binding 最低價}"/>
            <GridViewColumn Header="中位數" Width="96" DisplayMemberBinding="{Binding 中位數}"/>
            <GridViewColumn Header="掛單" Width="56" DisplayMemberBinding="{Binding 掛單}"/>
            <GridViewColumn Header="已售" Width="76" DisplayMemberBinding="{Binding 已售}"/>
            <GridViewColumn Header="漲跌" Width="60" DisplayMemberBinding="{Binding 漲跌}"/>
            <GridViewColumn Header="最後看到" Width="104" DisplayMemberBinding="{Binding 最後更新}"/>
          </GridView>
        </ListView.View>
      </ListView>
      <Border Grid.Row="1" Margin="0,10,0,0" Background="#0A1626" BorderBrush="#1D5F8A" BorderThickness="1" CornerRadius="6">
        <DockPanel Margin="12,10,12,10">
          <TextBlock x:Name="PDetTitle" DockPanel.Dock="Top" Foreground="#5FE0FF" FontWeight="Bold" Margin="0,0,0,6"
                     Text="歷史紀錄(點上面任一列)"/>
          <ScrollViewer VerticalScrollBarVisibility="Auto">
            <TextBlock x:Name="PDet" FontFamily="Consolas,Microsoft JhengHei UI" FontSize="13"
                       Foreground="#C7D6E4" TextWrapping="NoWrap"/>
          </ScrollViewer>
        </DockPanel>
      </Border>
    </Grid>
  </DockPanel>
</Window>
'@

function Show-PriceWindow {
    $w = [Windows.Markup.XamlReader]::Parse($PriceXaml)
    try { $w.Owner = $window } catch {}
    $lst = $w.FindName("PList"); $find = $w.FindName("PFind"); $info = $w.FindName("PInfo")
    $det = $w.FindName("PDet"); $detT = $w.FindName("PDetTitle")
    $script:pvRows = @(); $script:pvSum = @()
    $fill = {
        $q = ("" + $find.Text).Trim()
        $view = $script:pvSum
        if ($q) { $view = @($view | Where-Object { $_.名稱 -like "*$q*" -or $_.Id -like "*$q*" -or $_.分類 -like "*$q*" }) }
        $lst.ItemsSource = @($view | Sort-Object Sort -Descending)
        $info.Text = "共 $($script:pvSum.Count) 種物品、$($script:pvRows.Count) 筆掛單觀測" +
                     $(if ($q) { "(篩選後 $($view.Count) 種)" } else { "" }) +
                     "。※ 這是【你在遊戲裡看過的掛單】的紀錄,不是即時行情 —— 沒搜尋過的物品不會出現," +
                     "而且外掛不會為了更新它去多發任何一次請求。要更新就在遊戲裡再搜尋一次。" +
                     "「已售」是那些掛單累計被買走的數量,是最實在的需求訊號。"
    }
    $reload = {
        $r = Read-Market
        if (-not $r.ok) {
            $script:pvRows = @(); $script:pvSum = @()
            $lst.ItemsSource = $null
            $info.Text = "$($r.err)。做法:進遊戲 → 開市場的「購買物品」搜尋一次,你看到的每一筆掛單就會被記下來(檔案:$(Get-PricePath))"
            return
        }
        $script:pvRows = $r.rows
        $script:pvSum = Get-MarketSummary $r.rows
        & $fill
    }
    $w.FindName("PRefresh").Add_Click({ & $reload })
    $find.Add_TextChanged({ if ($script:pvSum.Count) { & $fill } })
    $w.FindName("POpenDir").Add_Click({
        $pp = Get-PricePath
        if (Test-Path $pp) { Start-Process explorer.exe "/select,`"$pp`"" }
        else { Start-Process explorer.exe (Q (Split-Path $pp)) }
    })
    $lst.Add_SelectionChanged({
        $sel = $lst.SelectedItem
        if (-not $sel) { return }
        $detT.Text = "$($sel.名稱)  ·  $($sel.Id)  ·  $($sel.分類)  —— 共 $($sel.批次) 批觀測"
        $hist = @($script:pvRows | Where-Object { $_.Id -eq $sel.Id })
        $sb = New-Object System.Text.StringBuilder
        [void]$sb.AppendLine(("{0,-20} {1,10} {2,10} {3,8} {4,8}  {5}" -f "看到的時間", "單價", "還剩", "已售", "上架", "賣家"))
        $bs = Split-Batches $hist
        [array]::Reverse($bs)
        foreach ($b in $bs) {
            foreach ($h in ($b | Sort-Object Price)) {
                [void]$sb.AppendLine(("{0,-20} {1,10} {2,10} {3,8} {4,8}  {5}" -f `
                    $h.T, $h.Price.ToString("N0"), $h.Avail.ToString("N0"), $h.Sold.ToString("N0"), $h.Init.ToString("N0"), $h.Seller))
            }
            [void]$sb.AppendLine("")
        }
        $det.Text = $sb.ToString()
    })
    & $reload
    [void]$w.ShowDialog()
}
if ($BtnPrices) { $BtnPrices.Add_Click({ Show-PriceWindow }) }
# 主畫面那行小字:讓人一眼知道現在累積了多少
function Update-PriceStat {
    if (-not $LblPriceStat) { return }
    $pp = Get-PricePath
    if (-not $pp -or -not (Test-Path -LiteralPath $pp)) { $LblPriceStat.Text = "還沒有紀錄 —— 進遊戲到市場「購買物品」搜尋一次就會開始累積"; return }
    try {
        $r = Read-Market
        if ($r.ok) {
            $kinds = @($r.rows | Group-Object Id).Count
            $LblPriceStat.Text = "已累積 $kinds 種物品、$($r.rows.Count) 筆掛單觀測"
        } else { $LblPriceStat.Text = $r.err }
    } catch { $LblPriceStat.Text = "" }
}

# ── 設定健檢:真的去掃,不是跑動畫 ─────────────────────────────────────────
# 用 DispatcherTimer 一次做一步:UI 不會卡住,而且進度條與日誌是跟著真實步驟走的。
# (刻意不叫「AI」:這裡全是本機的規則檢查,不連任何網路 —— 這個外掛最敏感的就是「會不會連線」。)
$script:hSteps = @($StepH1, $StepH2, $StepH3, $StepH4, $StepH5)
$script:hFind = @()
function HLog([string]$t) {
    $ts = (Get-Date).ToString("HH:mm:ss")
    $LblHealthLog.Text = $(if ($LblHealthLog.Text) { $LblHealthLog.Text + "`n" } else { "" }) + "[" + $ts + "] " + $t
    $SvHealthLog.ScrollToEnd()
}
function HStep([int]$i, [string]$state) {
    if ($i -lt 0 -or $i -ge $script:hSteps.Count) { return }
    $tb = $script:hSteps[$i]
    $txt = $tb.Text -replace '^[○◐✔✖]\s*', ''
    if ($state -eq "run")  { $tb.Text = "◐ " + $txt; $tb.Foreground = "#5FE0FF" }
    elseif ($state -eq "ok")   { $tb.Text = "✔ " + $txt; $tb.Foreground = "#5BE38B" }
    elseif ($state -eq "warn") { $tb.Text = "✖ " + $txt; $tb.Foreground = "#FFB020" }
    else { $tb.Text = "○ " + $txt; $tb.Foreground = "#7C93AD" }
}
function Run-HealthCheck {
    if ($script:hTimer) { $script:hTimer.Stop() }
    $script:hFind = @()
    $LblHealthLog.Text = ""
    for ($i = 0; $i -lt 5; $i++) { HStep $i "idle" }
    $BarHealth.Width = 0
    $LblHealthTitle.Text = "設定健檢 —— 檢查中…"
    $LblHealthDesc.Text = "檢查外掛檔案、相容性、熱鍵衝突與設定值 —— 全部在你自己的電腦上做,不會連任何網路。"
    $script:hIdx = 0; $script:hDone = $false
    $script:hTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:hTimer.Interval = [TimeSpan]::FromMilliseconds(260)
    $script:hTimer.Add_Tick({ Health-Tick })
    $script:hTimer.Start()
}
function Health-Tick {
    $pd = PluginDir
    $i = $script:hIdx
    if ($i -ge 5) {
        $script:hTimer.Stop()
        if ($script:hDone) { return }   # 收尾只跑一次
        $script:hDone = $true
        $BarHealth.Width = ($BarHealth.Parent.ActualWidth - 2)
        $bad = @($script:hFind)
        if ($bad.Count -eq 0) {
            $LblHealthTitle.Text = "設定健檢 —— 沒發現問題"
            $LblHealthDesc.Text = "外掛檔案齊全、沒有已知的相容性衝突、熱鍵沒有互撞、設定檔都讀得到。"
            HLog "檢查完成:沒有發現問題"
        } else {
            $LblHealthTitle.Text = "設定健檢 —— 發現 " + $bad.Count + " 項"
            $LblHealthDesc.Text = ($bad -join "  ‧  ")
            HLog ("檢查完成:發現 " + $bad.Count + " 項")
        }
        return
    }
    HStep $i "run"
    $warn = $false
    switch ($i) {
        0 {
            # 掃描外掛檔案
            if (-not $pd -or -not (Test-Path -LiteralPath $pd)) {
                HLog "找不到 plugins 資料夾 —— 還沒安裝翻譯"; $script:hFind += "還沒安裝翻譯"; $warn = $true
            } else {
                $dll = Join-Path $pd "SpiritZh.dll"
                $v = $(if (Test-Path -LiteralPath $dll) { Get-DllVer $dll } else { "" })
                HLog $(if ($v) { "外掛 SpiritZh.dll " + $v } else { "找不到 SpiritZh.dll" })   # Get-DllVer 回傳已含 v
                if (-not $v) { $script:hFind += "找不到 SpiritZh.dll"; $warn = $true }
                $need = @("SpiritZh_dict.txt", "SpiritZh_names.txt")
                $miss = @($need | Where-Object { -not (Test-Path -LiteralPath (Join-Path $pd $_)) })
                if ($miss.Count -gt 0) { HLog ("翻譯資料檔不見了:" + ($miss -join "、")); $script:hFind += "翻譯資料檔缺 " + $miss.Count + " 個(可能被防毒刪掉)"; $warn = $true }
                else { HLog "翻譯資料檔齊全" }
            }
        }
        1 {
            # 相容性:同資料夾裡的其他外掛
            if ($pd -and (Test-Path -LiteralPath $pd)) {
                $others = @()
                try { $others = @(Get-ChildItem -LiteralPath $pd -Filter *.dll -Recurse -ErrorAction Stop | Where-Object { $_.Name -ne "SpiritZh.dll" }) } catch {}
                HLog ("同資料夾其他外掛:" + $others.Count + " 個")
                foreach ($o in $others) { HLog ("  ‧ " + $o.Name) }
                $lb = @($others | Where-Object { $_.Name -match '(?i)loot|beam' })
                if ($lb.Count -gt 0 -and -not $script:IsPure) {   # 純翻譯包沒有光柱功能,這條警告沒意義
                    HLog "偵測到 Loot Beams 類外掛 —— 它會銷毀被它過濾掉的光柱特效"
                    $script:hFind += "與 Loot Beams 併用(光柱可能被它吃掉)"; $warn = $true
                }
            }
        }
        2 {
            # 熱鍵:名稱遊戲認不認得 + 有沒有互撞
            if ($script:IsPure) { HLog "純翻譯包沒有熱鍵功能"; break }   # 公會版殘留的 quality.txt 會讓這步對著隱藏頁報錯
            $boxes = @{ "開關面板" = $KDpsKey; "切換模式" = $KDpsMode; "歸零重算" = $KDpsReset; "移動面板" = $KDpsEdit; "叫出設定工具" = $KToolKey; "帶入進階濾鏡" = $KMkKey }
            $badName = @(); $used = @{}; $dup = @()
            foreach ($k in $boxes.Keys) {
                $t = $boxes[$k].Text.Trim()
                if ($t -eq "") { continue }
                if (-not (Test-KeyName $t)) { $badName += ($k + "=" + $t) }
                if ($used.ContainsKey($t)) { $dup += ($t + "(" + $used[$t] + " / " + $k + ")") } else { $used[$t] = $k }
            }
            if ($badName.Count -gt 0) { HLog ("遊戲認不得的鍵名:" + ($badName -join "、")); $script:hFind += "有 " + $badName.Count + " 個熱鍵遊戲認不得"; $warn = $true }
            if ($dup.Count -gt 0) { HLog ("熱鍵互撞:" + ($dup -join "、")); $script:hFind += "熱鍵互撞 " + $dup.Count + " 組"; $warn = $true }
            if ($badName.Count -eq 0 -and $dup.Count -eq 0) {
                HLog "熱鍵設定沒問題"
                # 健檢看的是【畫面上】的值。畫面改好但還沒按套用時,檔案裡仍是舊的壞值 —— 講清楚,不然
                # 使用者會以為已經好了(源就是這樣:欄位改好了、檔案還是 ]、狀態列還掛著舊警告)
                $qf = $(if ($pd) { Join-Path $pd "SpiritZh_quality.txt" } else { "" })
                if ($qf -and (Test-Path -LiteralPath $qf)) {
                    $fk = Read-KV $qf
                    if ($null -ne $fk) {
                        $stale = @()
                        foreach ($kk in @("dpskey", "dpsmodekey", "dpsresetkey", "dpseditkey", "toolkey", "marketkey")) {
                            $fv = "" + $fk[$kk]
                            if ($fv -ne "" -and -not (Test-KeyName $fv)) { $stale += ($kk + "=" + $fv) }
                        }
                        if ($stale.Count -gt 0) {
                            HLog ("但檔案裡還是舊的壞值(" + ($stale -join "、") + ")—— 按「套用設定」才會寫進去")
                            $script:hFind += "熱鍵改好了但還沒套用"
                            $warn = $true
                        }
                    }
                }
            }
        }
        3 {
            # 設定檔讀得到嗎 + 指到的檔案在不在
            $files = @("SpiritZh_view.txt", "SpiritZh_gui.txt", "SpiritZh_quality.txt", "SpiritZh_beam.txt", "SpiritZh_audio.txt", "SpiritZh_filter.txt", "SpiritZh_custom.txt", "SpiritZh_music.txt", "SpiritZh_cursor.txt", "SpiritZh_bossalert.txt")
            $unread = @()
            if ($pd -and (Test-Path -LiteralPath $pd)) {
                foreach ($f in $files) {
                    $fp = Join-Path $pd $f
                    if (-not (Test-Path -LiteralPath $fp)) { continue }
                    if ($null -eq (Read-KV $fp)) { $unread += $f }
                }
            }
            if ($unread.Count -gt 0) { HLog ("讀不到(被鎖?):" + ($unread -join "、")); $script:hFind += "有 " + $unread.Count + " 個設定檔讀不到"; $warn = $true }
            else { HLog "設定檔都讀得到" }
            # 音效檔 / 音樂檔 / 字型檔指到的東西還在不在
            $missFile = @()
            $sd = SoundDir
            foreach ($k in $script:rarKeys) {
                $fn = Get-SoundSel $k
                if ($fn -and $sd -and -not (Test-Path -LiteralPath (Join-Path $sd $fn))) { $missFile += ("音效 " + $fn) }
            }
            $md = MusicDir
            foreach ($k in $script:musicMap.Keys) {
                $fn = [string]$script:musicMap[$k]
                if ($fn -and ($fn -notmatch '[\\/]') -and $md -and -not (Test-Path -LiteralPath (Join-Path $md $fn))) { $missFile += ("音樂 " + $fn) }
            }
            if ($script:fontFilePath -and -not (Test-Path -LiteralPath $script:fontFilePath)) { $missFile += "字型檔" }
            # 游標圖:游標頁的提示文字承諾「重新檢查會告訴你圖檔在不在」,這裡就要真的查
            if ($ChkCurOn.IsChecked -and -not $script:IsPure) {   # 純翻譯包沒有游標功能(殘留的 cursor.txt 可能是 enabled=1)
                $curFile = $(if ($script:curImg) { $script:curImg } else { CurStyleFile $script:curStyle $script:CUR_SIZES[[math]::Max(0, $CboCurSize.SelectedIndex)] })
                if ($pd -and -not (Test-Path -LiteralPath (Join-Path (Join-Path $pd "SpiritZh_ui") $curFile))) { $missFile += ("游標圖 " + $curFile) }
            }
            if ($missFile.Count -gt 0) { HLog ("指到的檔案不見了:" + ($missFile -join "、")); $script:hFind += "有 " + $missFile.Count + " 個檔案指到不存在的路徑"; $warn = $true }
            else { HLog "音效/音樂/字型/游標圖檔都在" }
        }
        4 {
            # 效能與畫質:給具體建議
            $tips = @()
            $sc = ClampDbl $TxtScale.Text 0 4 0
            if ($sc -gt 0 -and $sc -lt 0.5) { $tips += "渲染解析度 " + $sc + " 偏低,畫面會很糊" }
            if ($CboUp.SelectedIndex -gt 0 -and ($sc -eq 0 -or $sc -eq 1)) { $tips += "放大濾鏡要搭渲染解析度 <1 才有作用" }
            $fps = ClampInt $TxtFps.Text 0 1000 0
            if ($fps -gt 0 -and $fps -lt 30) { $tips += "幀率上限 " + $fps + " 太低" }
            if (-not $script:IsPure -and -not $ChkShadow.IsChecked -and -not $ChkAnim.IsChecked -and -not $ChkFxMine.IsChecked) { $tips += "三個效能選項都沒開 —— 卡的話可以先開「關閉陰影」" }   # 純翻譯包恆成立,會把「沒發現問題」變成永遠「1 項」
            foreach ($t in $tips) { HLog $t }
            if ($tips.Count -eq 0) { HLog "效能與畫質設定看起來合理" }
            else { $script:hFind += "效能建議 " + $tips.Count + " 條"; $warn = $true }
        }
    }
    HStep $i $(if ($warn) { "warn" } else { "ok" })
    $script:hIdx++
    $w = $BarHealth.Parent.ActualWidth - 2
    if ($w -gt 0) { $BarHealth.Width = [Math]::Max(0, $w * $script:hIdx / 5) }
}
$BtnHealth.Add_Click({ Run-HealthCheck })

# ── 動作 ─────────────────────────────────────────────────────────────────────
# ★ Windows 的命令列引號規則【不是】「包起來就好」:
#   反斜線只有在【緊接著引號】的時候才需要加倍。路徑結尾是反斜線時(例如 D:\Games\SpiritVale\),
#   那個反斜線會緊接著我們補上的收尾引號 → 變成跳脫引號 → 收尾引號被吃掉,後面的參數整組被吞進去。
#   實測:install.ps1 -GamePath "D:\Games\SpiritVale\" -Mode 1 -Font x
#     → 子行程收到的 GamePath 變成【D:\Games\SpiritVale" -Mode 1 -Font x】,而 install.ps1 沒有
#       PositionalBinding=$false,所以是【靜默】綁錯,一個錯誤訊息都不會有。
#   C:\Program Files (x86)\... 這種一般含空白的路徑舊寫法是對的 —— 所以平常看不出問題。
function Q([string]$s) {
    if ($null -eq $s) { $s = "" }
    $s = [regex]::Replace($s, '(\\*)"', '$1$1\"')   # 引號前的反斜線加倍,引號本身跳脫
    $s = [regex]::Replace($s, '(\\+)$', '$1$1')     # 結尾的反斜線加倍(它們緊接著收尾引號)
    return '"' + $s + '"'
}
function Current-ModeArg {
    if ($RbM1.IsChecked) { return "1" }
    if ($RbM3.IsChecked) { return "3" }
    if ($RbM4.IsChecked) { return "4" }
    return "2"
}
function Current-FontArg {
    if ($script:fontFilePath) { return $script:fontFilePath }
    if ($CboFont.SelectedIndex -gt 0) { return [string]$CboFont.SelectedItem }
    return "0"
}
# (v3.75:舊的「進階設定」= settings.ps1 已整個併進本工具,相關的啟動/互斥/重讀邏輯一併移除)
$BtnBrowse.Add_Click({
    $fb = New-Object System.Windows.Forms.FolderBrowserDialog
    $fb.Description = "選擇 SpiritVale 遊戲資料夾(裡面有 SpiritVale.exe)"
    if ($fb.ShowDialog() -eq "OK") {
        if (Test-Game $fb.SelectedPath) { $script:GamePath = $fb.SelectedPath; Refresh-Header; Load-Config; Load-DpsConfig; Load-QualityConfig; Load-BeamConfig; Load-AudioConfig; Load-CustomConfig; Load-CursorConfig; Load-BossAlert; Update-Summary }
        else { Show-Msg "不是遊戲資料夾" "那個資料夾裡沒有 SpiritVale.exe。" "warn" }
    }
})
# ── 收集模式的鏡像勾:功能頁那顆與「關於」頁那顆是同一個開關,勾哪一顆另一顆跟著動 ──
function Link-Checks($a, $b) {
    $a.Add_Checked({ if (-not $b.IsChecked) { $b.IsChecked = $true } }.GetNewClosure())
    $a.Add_Unchecked({ if ($b.IsChecked) { $b.IsChecked = $false } }.GetNewClosure())
    $b.Add_Checked({ if (-not $a.IsChecked) { $a.IsChecked = $true } }.GetNewClosure())
    $b.Add_Unchecked({ if ($a.IsChecked) { $a.IsChecked = $false } }.GetNewClosure())
}
Link-Checks $ChkBaDiag $ChkDgBoss
Link-Checks $ChkFxSkillDiag $ChkDgFxSkill
# ── 使用教學(從舊工具 settings.ps1 搬來,內容改成對應本工具的分頁)────────
function Show-Tutorial([bool]$firstRun) {
    $msg = @"
歡迎使用 SpiritVale 繁體中文化!(開發:源)

【第一次使用,照這三步做】

  1. 按最下面的「安裝 / 更新翻譯」
     → 會開一個黑色視窗自動安裝,跳出 UAC 授權請按「是」
       (用途只是把遊戲資料夾加入防毒排除,避免外掛被誤刪)

  2. 用 Steam 正常啟動遊戲
     → 首次啟動會有黑窗跑 1~3 分鐘產生外掛組件,請耐心等它跑完

  3. 之後想改設定,回到本工具改完按「套用設定」
     → 遊戲開著也行,約 5 秒自動生效,不用重開

【最重要的一件事】

  「套用設定」只存設定;「安裝 / 更新翻譯」才會更新外掛本體。
  下載新版安裝包後,一定要按一次「安裝 / 更新翻譯」再重開遊戲,
  否則新功能不會生效(這是最多人踩到的坑)。

【各分頁在做什麼】

  ● 功能自選   — 隱藏其他玩家、技能特效、效能選項、技能冷卻顯示、安裝與移除
  ● 翻譯與字型 — 選要不要雙語、換中文字型(有即時預覽)
  ● 掉落音效   — 依稀有度設定掉寶提示音;可匯出/匯入分享給朋友
  ● 掉落光柱   — 把王卡/王裝/指定物品的光柱換成自己挑的顏色
  ● 詞條品質   — 裝備詞條快篩、自動查市價、市場分析面板
  ● 傷害統計   — DPS 面板(四種模式、十種風格)與熱鍵
  ● 王         — 王技提示音、王方位箭頭
  ● 自訂       — 自訂翻譯、地圖背景音樂
  ● 游標       — 滑鼠游標放大、換圖
  ● 關於       — 版本、相容性、回報問題用的診斷開關

  每個功能區標題旁有「?」,滑過去有詳細說明。

【最上面那一排】

  ● 開場動畫 — 開工具時播放開場畫面與音樂,畫面上點一下可跳過。
  ● 介面縮放 — 螢幕太大字太小的話調這個,重開工具生效。

【出問題怎麼辦】

  按「產生診斷報告」,把報告貼到巴哈討論串或公會群,
  附上 BepInEx\LogOutput.log 可以直接看出問題,不用來回猜。
"@
    if ($firstRun) { $msg = $msg + "`r`n`r`n(本教學只在第一次開啟時自動顯示;之後按右上角「使用教學」重看)" }
    Show-BigText "使用教學 — SpiritVale 繁體中文化" $msg
}
function Show-BigText([string]$title, [string]$text) {
    $x9 = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Width="760" Height="700" WindowStartupLocation="CenterOwner"
        Background="#151C2B" FontFamily="Microsoft JhengHei UI" FontSize="14" Foreground="#E6EBF2" ShowInTaskbar="False">
  <DockPanel Margin="14">
    <Button x:Name="Ok" DockPanel.Dock="Bottom" Content="關閉" Width="110" Height="34" HorizontalAlignment="Right" Margin="0,10,0,0" Foreground="#E6EBF2" Background="#22304A"/>
    <ScrollViewer VerticalScrollBarVisibility="Auto">
      <TextBox x:Name="Body" IsReadOnly="True" TextWrapping="Wrap" Background="#101827" Foreground="#E6EBF2" BorderThickness="0" Padding="12" FontSize="14"/>
    </ScrollViewer>
  </DockPanel>
</Window>
'@
    $d = [Windows.Markup.XamlReader]::Parse($x9)
    $d.Title = $title
    if ($window.IsVisible) { $d.Owner = $window }
    $d.FindName("Body").Text = $text
    $d.FindName("Ok").Add_Click({ $d.Close() })
    [void]$d.ShowDialog()
}
# ── 掉寶音效分享檔(.svsnd)匯出 / 匯入 —— 從舊工具 settings.ps1 搬來 ────────
#   包內容:config\SpiritZh_audio.txt、config\SpiritZh_filter.txt、sounds\*.wav|mp3、pack.txt
#   ★ 匯入的安全邊界照舊:整包 ≤60MB、≤60 個項目、只取【檔名】(路徑穿越在結構上不可能)、
#     只收 wav/mp3 與那兩個 txt、每個音效有界解壓 ≤8MB。
function Test-SafeName([string]$nm) {
    if ([string]::IsNullOrWhiteSpace($nm) -or $nm.Length -gt 120 -or $nm -eq "." -or $nm -eq "..") { return $false }
    foreach ($c in [System.IO.Path]::GetInvalidFileNameChars()) { if ($nm.IndexOf($c) -ge 0) { return $false } }
    return $true
}
function Extract-Bounded($entry, [string]$dst, [long]$maxBytes) {
    $in = $entry.Open(); $out = [System.IO.File]::Create($dst)
    try {
        $buf = New-Object byte[] 65536; $tot = 0L
        while (($k = $in.Read($buf, 0, $buf.Length)) -gt 0) {
            $tot += $k
            if ($tot -gt $maxBytes) { throw "音效檔實際內容超過上限,已中止(疑似惡意壓縮檔)" }
            $out.Write($buf, 0, $k)
        }
    } finally { $out.Dispose(); $in.Dispose() }
}
# 設定裡真正引用到的音效檔名(稀有度下拉的「自訂:」+ audio.txt 的換音設定)
function Get-RefSounds {
    $set = New-Object System.Collections.Generic.HashSet[string]
    foreach ($k in $script:rarKeys) {
        $sel = [string]$script:sndCbo[$k].SelectedItem
        if ($sel -and $sel.StartsWith("自訂:")) { [void]$set.Add($sel.Substring(3)) }
    }
    try {
        $af2 = Join-Path (PluginDir) "SpiritZh_audio.txt"
        if (Test-Path -LiteralPath $af2) {
            foreach ($l in (Get-Content -LiteralPath $af2 -Encoding UTF8)) {
                $s = $l.Trim(); if ($s.Length -eq 0 -or $s.StartsWith("//")) { continue }
                $i = $s.IndexOf("="); if ($i -le 0) { continue }
                $v = $s.Substring($i + 1).Trim(); $j = $v.IndexOf("*"); if ($j -gt 0) { $v = $v.Substring(0, $j).Trim() }
                $e = [System.IO.Path]::GetExtension($v).ToLowerInvariant()
                if ($e -eq ".wav" -or $e -eq ".mp3") { [void]$set.Add([System.IO.Path]::GetFileName($v)) }
            }
        }
    } catch { }
    return $set
}
$BSndExport.Add_Click({
    $pd = PluginDir
    if (-not $pd -or -not (Test-Path -LiteralPath $pd)) { Show-Msg "尚未安裝" "尚未安裝翻譯,沒有設定可以匯出。" "warn"; return }
    $stage = $null
    try {
        $refs = Get-RefSounds
        $withSnd = "No"
        if ($refs.Count -gt 0) {
            $withSnd = [System.Windows.MessageBox]::Show("要把音效檔一起打包嗎?`n`n【是】連音效檔一起(對方直接能用,檔案較大)`n【否】只有設定(約 1 KB,對方要自備同名檔)", "匯出分享檔", "YesNo", "Question")
        }
        $sd = New-Object System.Windows.Forms.SaveFileDialog
        $sd.Filter = "SpiritVale 掉寶音效分享檔 (*.svsnd)|*.svsnd"
        $sd.FileName = "我的掉寶音效設定.svsnd"
        $sd.InitialDirectory = [Environment]::GetFolderPath("Desktop")
        if ($sd.ShowDialog() -ne "OK") { return }
        $stage = Join-Path ([System.IO.Path]::GetTempPath()) ("svsnd_" + [Guid]::NewGuid().ToString("N"))
        New-Item -ItemType Directory -Path (Join-Path $stage "config") -Force -ErrorAction Stop | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $stage "sounds") -Force -ErrorAction Stop | Out-Null
        foreach ($fn in @("SpiritZh_audio.txt", "SpiritZh_filter.txt")) {
            $src = Join-Path $pd $fn
            if (Test-Path -LiteralPath $src) { Copy-Item -LiteralPath $src -Destination (Join-Path $stage ("config\" + $fn)) -Force }
        }
        $sndDir = Join-Path $pd "SpiritZh_sounds"; $copied = 0; $skipped = @()
        if ($withSnd -eq "Yes") {
            foreach ($f in $refs) {
                $sp = Join-Path $sndDir $f
                if (-not (Test-Path -LiteralPath $sp)) { $skipped += ($f + "(找不到)"); continue }
                if ((Get-Item -LiteralPath $sp).Length -gt 8MB) { $skipped += ($f + "(超過 8 MB)"); continue }
                Copy-Item -LiteralPath $sp -Destination (Join-Path $stage ("sounds\" + $f)) -Force; $copied++
            }
        }
        $pk = @("packver=1", "tool=" + $ToolVer, "date=" + (Get-Date -Format "yyyy-MM-dd HH:mm"), "sounds=" + $copied, "note=SpiritVale 掉寶音效分享檔;請用設定工具「掉落音效」頁的「匯入別人的分享檔」載入")
        Set-Content -LiteralPath (Join-Path $stage "pack.txt") -Value ($pk -join "`r`n") -Encoding UTF8
        Add-Type -AssemblyName System.IO.Compression; Add-Type -AssemblyName System.IO.Compression.FileSystem
        if (Test-Path -LiteralPath $sd.FileName) { [System.IO.File]::Delete($sd.FileName) }
        [System.IO.Compression.ZipFile]::CreateFromDirectory($stage, $sd.FileName, [System.IO.Compression.CompressionLevel]::Optimal, $false)
        $mb = [math]::Round((Get-Item -LiteralPath $sd.FileName).Length / 1MB, 2)
        $msg = "已匯出:" + [System.IO.Path]::GetFileName($sd.FileName) + "(" + $mb + " MB,含音效 " + $copied + " 個)"
        if ($skipped.Count -gt 0) { $msg += "  ※ 略過:" + ($skipped -join "、") }
        if ($mb -ge 9) { $msg += "  ※ 超過 9 MB,Discord 免費帳號可能傳不上去,建議改用雲端硬碟" }
        $LblStatus.Text = "狀態:" + $msg
    } catch { Show-Msg "匯出失敗" $_.Exception.Message "error" }
    finally { if ($stage -and (Test-Path -LiteralPath $stage)) { Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue } }
})
$BSndImport.Add_Click({
    $pd = PluginDir
    if (-not $pd -or -not (Test-Path -LiteralPath $pd)) { Show-Msg "尚未安裝" "請先按「安裝 / 更新翻譯」再匯入。" "warn"; return }
    $zip = $null
    try {
        $od = New-Object System.Windows.Forms.OpenFileDialog
        $od.Filter = "SpiritVale 掉寶音效分享檔 (*.svsnd)|*.svsnd|所有檔案 (*.*)|*.*"
        $od.Title = "選擇別人分享的 .svsnd"
        if ($od.ShowDialog() -ne "OK") { return }
        $packBytes = (Get-Item -LiteralPath $od.FileName).Length
        if ($packBytes -gt 60MB) { throw "分享檔過大(" + [math]::Round($packBytes/1MB,1) + " MB),已中止" }
        Add-Type -AssemblyName System.IO.Compression; Add-Type -AssemblyName System.IO.Compression.FileSystem
        $zip = [System.IO.Compression.ZipFile]::OpenRead($od.FileName)
        if ($zip.Entries.Count -gt 60) { throw "檔案數異常(" + $zip.Entries.Count + " 個),已中止" }
        $comp = 0L; foreach ($e in $zip.Entries) { $comp += $e.CompressedLength }
        if ($comp -gt 50MB) { throw "壓縮內容異常,已中止" }
        $audioTxt = $null; $filterTxt = $null; $packTxt = $null; $sndEntries = @{}; $ignored = @()
        foreach ($e in $zip.Entries) {
            $base = [System.IO.Path]::GetFileName($e.FullName)
            if ($base -eq "") { continue }
            if (-not (Test-SafeName $base)) { $ignored += $e.FullName; continue }
            $ext = [System.IO.Path]::GetExtension($base).ToLowerInvariant()
            if ($base -eq "SpiritZh_audio.txt") { $audioTxt = $e }
            elseif ($base -eq "SpiritZh_filter.txt") { $filterTxt = $e }
            elseif ($base -eq "pack.txt") { $packTxt = $e }
            elseif ($ext -eq ".wav" -or $ext -eq ".mp3") { $sndEntries[$base] = $e }
            else { $ignored += $e.FullName }
        }
        if (-not $audioTxt -and -not $filterTxt) { throw "這不是有效的分享檔(找不到任何設定)" }
        $rd = { param($en) $sr = New-Object System.IO.StreamReader($en.Open(), [System.Text.Encoding]::UTF8); try { return $sr.ReadToEnd() } finally { $sr.Dispose() } }
        $pkInfo = ""; if ($packTxt) { $pkInfo = (& $rd $packTxt) }
        $ver = 1; if ($pkInfo -match 'packver\s*=\s*(\d+)') { $ver = [int]$Matches[1] }
        if ($ver -gt 1) { throw "這個分享檔是較新的格式(packver=$ver),請先更新安裝包" }
        $prev = @("來源:" + [System.IO.Path]::GetFileName($od.FileName), "")
        if ($pkInfo) { $prev += (($pkInfo -split "`r?`n" | Where-Object { $_ -and -not $_.StartsWith("packver") }) -join "`n") }
        $prev += ""
        $prev += ("音效檔 " + $sndEntries.Count + " 個:" + (($sndEntries.Keys | Select-Object -First 8) -join "、"))
        $prev += ("設定檔:" + $(if ($audioTxt) { "音效 " } else { "" }) + $(if ($filterTxt) { "過濾器" } else { "" }))
        if ($ignored.Count -gt 0) { $prev += ("`n已忽略 " + $ignored.Count + " 個不安全或不支援的項目:" + (($ignored | Select-Object -First 5) -join "、")) }
        $prev += "`n⚠ 匯入會【整組取代】你目前的掉寶音效與過濾器設定(不是疊加)。"
        $prev += "動手前會自動備份成 .bak_匯入前_日期時間(設定檔與同名音效檔都備份)。"
        $prev += "`n要繼續嗎?"
        if ([System.Windows.MessageBox]::Show(($prev -join "`n"), "匯入分享檔 — 預覽", "OKCancel", "Information") -ne "OK") { return }
        $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
        foreach ($fn in @("SpiritZh_audio.txt", "SpiritZh_filter.txt")) {
            $src2 = Join-Path $pd $fn
            if (Test-Path -LiteralPath $src2) { Copy-Item -LiteralPath $src2 -Destination ($src2 + ".bak_匯入前_" + $stamp) -Force -ErrorAction Stop }
        }
        $sndDir = Join-Path $pd "SpiritZh_sounds"
        if (-not (Test-Path -LiteralPath $sndDir)) { New-Item -ItemType Directory -Path $sndDir -Force -ErrorAction Stop | Out-Null }
        $got = 0
        foreach ($k in $sndEntries.Keys) {
            $dst = Join-Path $sndDir $k
            # 同名音效先備份;備不起來就中止,不要為了跑完流程毀掉人家的檔案
            if (Test-Path -LiteralPath $dst) { Copy-Item -LiteralPath $dst -Destination ($dst + ".bak_匯入前_" + $stamp) -Force -ErrorAction Stop }
            try { Extract-Bounded $sndEntries[$k] $dst 8MB; $got++ }
            catch { if (Test-Path -LiteralPath $dst) { [System.IO.File]::Delete($dst) }; throw }
        }
        # ★ 新工具的作法:分享包裡就是完整的設定檔,直接寫進遊戲端,再讓畫面從檔案重讀。
        #   (舊工具是逐項灌進 WinForms 控制項;這裡的資料模型不同,直接寫檔反而最不會出錯,
        #    而且外掛 5 秒內就熱重載,不用再按套用。)
        if ($audioTxt)  { Set-Content -LiteralPath (Join-Path $pd "SpiritZh_audio.txt")  -Value (& $rd $audioTxt)  -Encoding UTF8 -ErrorAction Stop }
        if ($filterTxt) { Set-Content -LiteralPath (Join-Path $pd "SpiritZh_filter.txt") -Value (& $rd $filterTxt) -Encoding UTF8 -ErrorAction Stop }
        Load-AudioConfig
        $script:uiDirty = $false
        $LblStatus.Text = "狀態:已匯入(音效檔 " + $got + " 個)—— 設定已寫入遊戲端,約 5 秒生效;原設定備份在 .bak_匯入前_" + $stamp
    } catch { Show-Msg "匯入失敗" $_.Exception.Message "error" }
    finally { if ($zip) { $zip.Dispose() } }
})
function Do-Apply {
    if (-not $BtnApply.IsEnabled) { return }
    $script:saveErr = @()
    if (Save-Config) {
        if ($script:IsPure) { Save-CustomConfig }   # 純翻譯包:只有自訂翻譯(music 段自己有 Test-Path 守門)
        else { Save-DpsConfig; Save-QualityConfig; Save-BeamConfig; Save-AudioConfig; Save-CustomConfig; Save-CursorConfig; Save-BossAlert; Save-FxSkill }
        Save-KeepStat   # 兩種版本都有翻譯,能力值保留字兩邊都要寫
        if ($script:saveErr.Count -gt 0) {
            # 寫失敗就【不要】重讀 —— 檔案八成還被鎖著,重讀會把畫面刷成預設值,使用者再按一次套用就把預設值寫進去了。
            # 畫面維持使用者剛才的修改,解鎖後再按一次套用就是重試同樣的內容。
            $LblStatus.Text = "狀態:⚠ 有設定檔沒寫成功 —— 這次的修改沒有存到"
            Show-Msg "設定檔寫入失敗" ("下面這些檔案沒寫成功(唯讀?被防毒或其他程式鎖住?):`n`n" + ($script:saveErr -join "`n") + "`n`n畫面上仍是你剛才改的內容,沒有丟掉。關掉會鎖檔的程式(或取消唯讀)後再按一次「套用設定」即可。") "error"
        } else {
            # 寫完立刻重讀:文字框顯示的就是檔案裡真正的值(打錯被夾回預設會直接看到),位置鍵的「載入基準」也跟著刷新
            Load-DpsConfig; Load-QualityConfig; Load-BeamConfig; Load-AudioConfig; Load-CustomConfig; Load-CursorConfig; Load-BossAlert
            $script:uiDirty = $false   # 存成功了,關視窗不用再問
            $LblStatus.Text = "狀態:已套用 —— 遊戲內約 5 秒自動生效(不用重開)"
        }
    }
}
$BtnApply.Add_Click({ Do-Apply })
# ── 跑外部腳本但【不要卡住介面】────────────────────────────────────────────
# 舊寫法是 Start-Process … -Wait,而那是跑在 WPF 的 UI 執行緒上 —— 訊息迴圈整個停擺,
# Windows 會直接把視窗標成「沒有回應」,使用者看到的就是當機
# (源實測:按「產生診斷報告」→ 工具當機無回應。診斷要讀 284KB 的 log + 960KB 的殘留檔,
#  跑好幾秒是正常的,問題不在它慢,在我們卡住了介面)。
# 改成 -PassThru 拿到行程,再用 DispatcherTimer 每 0.25 秒問一次「跑完了沒」。
# ★ 事件處理常式裡只呼叫 script scope 的函式(不要用 GetNewClosure)—— 這個專案踩過那個坑。
$script:childProc = $null; $script:childDone = ""; $script:childAfter = ""; $script:childTimer = $null
function Set-BusyButtons([bool]$on) {
    foreach ($b in @($BtnInstall, $BtnDiag, $BtnUninstall)) { if ($b) { $b.IsEnabled = $on } }
}
function Start-Child([string]$file, [string[]]$extra, [string]$busy, [string]$done, [string]$after) {
    if ($script:childProc -and -not $script:childProc.HasExited) {
        Show-Msg "請稍候" "上一個作業還在跑,等它結束再按。" "warn"; return
    }
    $sp = Join-Path $Here $file
    if (-not (Test-Path -LiteralPath $sp)) {
        Show-Msg "找不到檔案" "$file 不在安裝包資料夾裡:`n$Here`n`n請確認安裝包是完整解壓的。" "error"; return
    }
    $LblStatus.Text = $busy
    Set-BusyButtons $false
    $a = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", (Q $sp)) + $extra
    try { $script:childProc = Start-Process powershell -ArgumentList $a -PassThru -ErrorAction Stop }
    catch {
        $script:childProc = $null; Set-BusyButtons $true
        $LblStatus.Text = "狀態:⚠ 啟動失敗 —— $($_.Exception.Message)"
        Show-Msg "啟動失敗" "叫不起 PowerShell 子行程:`n$($_.Exception.Message)" "error"; return
    }
    $script:childDone = $done; $script:childAfter = $after
    if (-not $script:childTimer) {
        $script:childTimer = New-Object System.Windows.Threading.DispatcherTimer
        $script:childTimer.Interval = [TimeSpan]::FromMilliseconds(250)
        $script:childTimer.Add_Tick({ Child-Tick })
    }
    $script:childTimer.Start()
}
function Child-Tick {
    if (-not $script:childProc) { if ($script:childTimer) { $script:childTimer.Stop() }; return }
    if (-not $script:childProc.HasExited) { return }
    $script:childTimer.Stop()
    $script:childProc = $null
    Set-BusyButtons $true
    $LblStatus.Text = $script:childDone
    if ($script:childAfter -eq "reload") {
        # 剛裝好的範本值要讀進來,不然接著按套用會把工具裡的預設值寫回去
        Refresh-Header; Load-Config; Load-DpsConfig; Load-QualityConfig; Load-BeamConfig
        Load-AudioConfig; Load-CustomConfig; Load-CursorConfig; Load-BossAlert; Update-PriceStat; Update-Summary
        Run-HealthCheck
    }
    elseif ($script:childAfter -eq "header") { Refresh-Header; Run-HealthCheck }
    $script:childAfter = ""
}

$BtnInstall.Add_Click({
    if (-not $script:GamePath) { Show-Msg "找不到遊戲" "先按「瀏覽」指定遊戲資料夾。" "warn"; return }
    # ★★ CRITICAL 防呆(2026-08-28 深度審查):擋住「用純翻譯包覆蓋掉公會專用版」。
    #    舊版完全沒有 edition 檢查 —— 一個已裝公會版的【付費客戶】只要從公開下載的
    #    「一鍵安裝包」開這支工具,畫面會叫他「按安裝升級」,一按 payload 的 pure DLL 就蓋上去:
    #    GuildGateHashes 變空 → 所有付費功能靜默關閉、序號分頁消失,而標題列只寫「版本一致」。
    #    這是會直接毀掉付費客戶的操作,必須先問清楚,而且預設不要繼續。
    try {
        $gameEdNow = Get-DllEdition (Join-Path (PluginDir) "SpiritZh.dll")
        if ($gameEdNow -eq "guild" -and $ToolEdition -ne "guild") {
            $ans = [System.Windows.MessageBox]::Show(
                "你的遊戲現在裝的是【公會專用版】,而這個安裝包是【純翻譯包】。`r`n`r`n" +
                "繼續安裝會把公會專用版【覆蓋掉】,結果是:`r`n" +
                "  ‧所有付費功能(詞條品質 / 傷害統計 / 掉落音效 / 掉落光柱…)全部關閉`r`n" +
                "  ‧設定工具的「序號」分頁會消失`r`n" +
                "  ‧序號在純翻譯包上完全無效`r`n`r`n" +
                "如果你有買序號或公會授權,請【不要】繼續 —— 改用「公會專用版」的安裝包。`r`n`r`n" +
                "真的還是要覆蓋成純翻譯包嗎?",
                "⚠ 這會把公會專用版覆蓋掉", "YesNo", "Warning")
            if ($ans -ne "Yes") {
                $LblStatus.Text = "狀態:已取消 —— 請改用「公會專用版」的安裝包"
                return
            }
        }
    } catch { }
    # 安裝前把四個分頁的修改都先寫進去(不然安裝完重讀時,DPS/詞條品質/光柱三頁沒套用的修改會被靜默丟掉;
    # 首次安裝時 plugins 資料夾還不存在,三個 Save-* 會自己跳過)
    $script:saveErr = @()
    if (Save-Config) { if ($script:IsPure) { Save-CustomConfig } else { Save-DpsConfig; Save-QualityConfig; Save-BeamConfig; Save-AudioConfig; Save-CustomConfig; Save-CursorConfig; Save-BossAlert } }
    if ($script:saveErr.Count -gt 0) {
        Show-Msg "先處理設定檔" ("安裝前要先把你在各分頁改的設定寫進檔案,但這些檔案寫不進去:`n`n" + ($script:saveErr -join "`n") + "`n`n請先關掉會鎖檔的程式(或取消唯讀),按一次「套用設定」確認能存,再按「安裝 / 更新翻譯」。這次沒有開始安裝。") "error"
        $LblStatus.Text = "狀態:⚠ 設定檔寫不進去,安裝沒有開始"
        return
    }
    Start-Child "install.ps1" @("-GamePath", (Q $script:GamePath), "-Mode", (Current-ModeArg), "-Font", (Q (Current-FontArg))) `
        "狀態:安裝中……請看黑色視窗(跳 UAC 請按「是」)" "狀態:安裝流程結束 —— 標題列版本一致就是成功" "reload"
})
$BtnDiag.Add_Click({
    Start-Child "diagnose.ps1" @() `
        "狀態:產生診斷報告中……(會讀整份 log,大約十幾秒;這個視窗不會鎖住)" `
        "狀態:診斷報告已產生" ""
})
$BtnUninstall.Add_Click({
    $r = [System.Windows.MessageBox]::Show(
        "確定要移除翻譯嗎?`n`n會把 BepInEx 整個拿掉," + $(if ($script:IsPure) { "你的自訂翻譯/保留原文清單/字型設定" } else { "你的音效/光柱/畫面設定" }) + "會自動備份到遊戲資料夾的「SpiritZh_設定備份」。" +
        $(if (-not $script:IsPure) { "`n`n★ 你的【序號與啟用憑證】也會一起備份到那裡。`n   重裝後把 SpiritZh_serial.txt / SpiritZh_activation.txt 複製回 BepInEx\plugins\ 就會恢復,`n   不用重新跟作者要序號。" } else { "" }),
        "移除翻譯", "YesNo", "Warning")
    if ($r -ne "Yes") { return }
    Start-Child "uninstall.ps1" @("-GamePath", (Q $script:GamePath)) `
        "狀態:移除中……請看黑色視窗" "狀態:移除流程結束" "header"
})
$BtnTutorial.Add_Click({ Show-Tutorial $false })


# ══════════════════════════════════════════════════════════════════════
#  開場動畫(v3.72 搬回來)
# ══════════════════════════════════════════════════════════════════════
#  ★ 這整段是從舊工具 settings.ps1 原樣搬過來的,不是重寫。
#    新介面(shell.ps1)一直有「開場動畫」那顆勾勾、勾了也會寫進 SpiritZh_gui.txt,
#    但工具自己【從來沒有播過】—— 玩家從舊工具換過來就會發現動畫不見了(源回報)。
#  ★ 只適配了兩處:$PluginDir(舊工具是變數,這裡是函式)與 $UiK(WPF 自己處理 DPI,
#    但 SplashBody 跑在 WinForms 的 runspace 上,還是要自己算)。
$UiK = 1.0
try {
    $bmK = New-Object System.Drawing.Bitmap 1, 1
    $gK = [System.Drawing.Graphics]::FromImage($bmK)
    $UiK = [double]$gK.DpiX / 96.0
    $gK.Dispose(); $bmK.Dispose()
} catch { $UiK = 1.0 }
if ($UiK -lt 1.0) { $UiK = 1.0 }
if ($UiK -gt 3.0) { $UiK = 3.0 }

# ══════════════════ 開場載入畫面(LOGO + 音樂)══════════════════
# 動畫另開一條 STA 執行緒跑,主執行緒照常做耗時的載入(字型列舉、2404 項物品清單);
# 載入完成後主執行緒通知它淡出 —— 音樂跟著淡掉並停止,絕不會殘留在背景播放。
# 開場畫面永遠不會擋住工具:最長等 8 秒就強制放行(Stop-Splash 內有逾時)。
$script:SplashSync = $null; $script:SplashPS = $null; $script:SplashRS = $null

function Find-IntroMusic {
    # 找得到就播,找不到就只跑動畫。使用者把自己的檔案命名為 SpiritZh_intro.*
    # 放在工具資料夾即可覆蓋內建音樂(第一順位)。
    $dirs = @($Here,
              (Join-Path $Here "payload\BepInEx\plugins"),
              (PluginDir))
    foreach ($d in $dirs) {
        if ([string]::IsNullOrWhiteSpace($d)) { continue }
        foreach ($ext in @("wav", "mp3", "mp4", "m4a", "wma", "ogg", "flac")) {
            try {
                $p = Join-Path $d ("SpiritZh_intro." + $ext)
                if (Test-Path -LiteralPath $p) { return $p }
            } catch {}
        }
    }
    return ""
}

$SplashBody = @'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
try { Add-Type -AssemblyName PresentationCore } catch {}
[System.Windows.Forms.Application]::EnableVisualStyles()
$SPW = 720; $SPH = 470

function Draw-SpiritLogo([System.Drawing.Graphics]$g, [int]$CW, [int]$CH, [double]$prog, [double]$t, [string]$ver) {
    $g.SmoothingMode     = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAlias
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $full = New-Object System.Drawing.Rectangle(0, 0, $CW, $CH)

    # ── 1. 夜空漸層 ──
    $bg = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
        $full, [System.Drawing.Color]::FromArgb(255, 10, 12, 34),
               [System.Drawing.Color]::FromArgb(255, 46, 27, 71),
        [System.Drawing.Drawing2D.LinearGradientMode]::Vertical)
    $g.FillRectangle($bg, $full); $bg.Dispose()

    # ── 2. 星空(固定種子,每次開啟星位一樣)──
    $rnd = New-Object System.Random 20260727
    for ($i = 0; $i -lt 90; $i++) {
        $x = $rnd.Next(0, $CW); $y = $rnd.Next(0, 235)
        $r = $rnd.NextDouble() * 1.6 + 0.5
        $a = [int]((1.0 - $y / 260.0) * (120 + $rnd.Next(0, 135)))
        if ($a -lt 12) { $a = 12 }
        $a = [int]([Math]::Min(255, $a * (1.0 + 0.35 * [Math]::Sin($t * 2.2 + $i))))
        if ($a -lt 1) { $a = 1 }
        $sb = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb($a, 235, 232, 255))
        $g.FillEllipse($sb, [single]($x - $r), [single]($y - $r), [single]($r * 2), [single]($r * 2))
        $sb.Dispose()
    }

    # ── 3. 靈魂之光的大範圍光暈 ──
    $orbX = 360.0; $orbY = 132.0
    $glowR = 190.0 + 10.0 * [Math]::Sin($t * 1.3)
    $gp = New-Object System.Drawing.Drawing2D.GraphicsPath
    $gp.AddEllipse([single]($orbX - $glowR), [single]($orbY - $glowR), [single]($glowR * 2), [single]($glowR * 2))
    $pgb = New-Object System.Drawing.Drawing2D.PathGradientBrush $gp
    $pgb.CenterColor = [System.Drawing.Color]::FromArgb(150, 255, 226, 160)
    $pgb.SurroundColors = @([System.Drawing.Color]::FromArgb(0, 120, 90, 200))
    $pgb.FocusScales = New-Object System.Drawing.PointF(0.08, 0.08)
    $g.FillEllipse($pgb, [single]($orbX - $glowR), [single]($orbY - $glowR), [single]($glowR * 2), [single]($glowR * 2))
    $pgb.Dispose(); $gp.Dispose()

    # ── 4. 山谷(Vale)剪影:遠景帶霧、近景全暗 ──
    function New-Ridge([int[]]$pts, [int]$baseY) {
        $l = New-Object System.Collections.Generic.List[System.Drawing.Point]
        for ($i = 0; $i -lt $pts.Length; $i += 2) { $l.Add((New-Object System.Drawing.Point($pts[$i], $pts[$i + 1]))) }
        $l.Add((New-Object System.Drawing.Point(760, $baseY)))
        $l.Add((New-Object System.Drawing.Point(-40, $baseY)))
        return $l.ToArray()
    }
    $far = New-Ridge @(-40, 236, 58, 186, 122, 214, 205, 150, 268, 200, 330, 168, 392, 206, 452, 146, 520, 200, 596, 170, 660, 212, 760, 178) 300
    $bFar = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(215, 38, 44, 84))
    $g.FillPolygon($bFar, $far); $bFar.Dispose()
    $mistR = New-Object System.Drawing.Rectangle(0, 196, $CW, 74)
    $bMist = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
        $mistR, [System.Drawing.Color]::FromArgb(0, 150, 140, 210),
                [System.Drawing.Color]::FromArgb(70, 168, 152, 226),
        [System.Drawing.Drawing2D.LinearGradientMode]::Vertical)
    $g.FillRectangle($bMist, $mistR); $bMist.Dispose()
    $near = New-Ridge @(-40, 268, 74, 214, 158, 258, 246, 196, 300, 240, 360, 214, 424, 246, 500, 198, 578, 250, 664, 210, 760, 262) 320
    $bNear = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 14, 16, 40))
    $g.FillPolygon($bNear, $near); $bNear.Dispose()

    # ── 5. 靈魂光球(脈動外環 + 由谷底上升的光點)──
    for ($k = 0; $k -lt 2; $k++) {
        $ph = ($t * 0.55 + $k * 0.5) % 1.0
        $rr = 16.0 + $ph * 52.0
        $aa = [int]((1.0 - $ph) * 130)
        if ($aa -gt 0) {
            $pn = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb($aa, 255, 224, 150)), 1.6
            $g.DrawEllipse($pn, [single]($orbX - $rr), [single]($orbY - $rr), [single]($rr * 2), [single]($rr * 2))
            $pn.Dispose()
        }
    }
    $cr = 26.0
    $gp2 = New-Object System.Drawing.Drawing2D.GraphicsPath
    $gp2.AddEllipse([single]($orbX - $cr), [single]($orbY - $cr), [single]($cr * 2), [single]($cr * 2))
    $pg2 = New-Object System.Drawing.Drawing2D.PathGradientBrush $gp2
    $pg2.CenterColor = [System.Drawing.Color]::FromArgb(255, 255, 252, 236)
    $pg2.SurroundColors = @([System.Drawing.Color]::FromArgb(0, 255, 196, 96))
    $g.FillEllipse($pg2, [single]($orbX - $cr), [single]($orbY - $cr), [single]($cr * 2), [single]($cr * 2))
    $pg2.Dispose(); $gp2.Dispose()
    $bCore = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 255, 253, 244))
    $g.FillEllipse($bCore, [single]($orbX - 7), [single]($orbY - 7), 14, 14); $bCore.Dispose()
    for ($i = 0; $i -lt 7; $i++) {
        $ph = (($t * 0.30) + $i / 7.0) % 1.0
        $sx = $orbX + [Math]::Sin($i * 2.1 + $ph * 3.0) * (110 - 80 * $ph)
        $sy = 262 - $ph * 128
        $sa = [int]((1.0 - [Math]::Abs($ph - 0.45) * 2.0) * 190)
        if ($sa -gt 0) {
            $sr = 1.4 + (1.0 - $ph) * 1.6
            $bw = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb($sa, 255, 235, 180))
            $g.FillEllipse($bw, [single]($sx - $sr), [single]($sy - $sr), [single]($sr * 2), [single]($sr * 2))
            $bw.Dispose()
        }
    }

    # ── 6. 下方文字底板 ──
    $panel = New-Object System.Drawing.Rectangle(0, 248, $CW, ($CH - 248))
    $bPan = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
        $panel, [System.Drawing.Color]::FromArgb(0, 8, 9, 26),
                [System.Drawing.Color]::FromArgb(255, 8, 9, 26),
        [System.Drawing.Drawing2D.LinearGradientMode]::Vertical)
    $g.FillRectangle($bPan, $panel); $bPan.Dispose()

    $sf = New-Object System.Drawing.StringFormat
    $sf.Alignment = [System.Drawing.StringAlignment]::Center
    $sf.LineAlignment = [System.Drawing.StringAlignment]::Center

    # ── 7. 標題 SpiritVale(金色漸層 + 外光暈)──
    # 光暈迴圈變數務必用 $gw:PowerShell 變數不分大小寫,寫 $w 會把畫布寬 $CW…$W 系列蓋掉
    try { $ff = New-Object System.Drawing.FontFamily "Georgia" } catch { $ff = [System.Drawing.FontFamily]::GenericSerif }
    $tRect = New-Object System.Drawing.RectangleF(0, 266, $CW, 66)
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $path.AddString("SpiritVale", $ff, [int][System.Drawing.FontStyle]::Bold, 54, $tRect, $sf)
    for ($gw = 13; $gw -ge 3; $gw -= 2) {
        $pgl = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(16, 255, 205, 120)), ([single]$gw)
        $pgl.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
        $g.DrawPath($pgl, $path); $pgl.Dispose()
    }
    $bTit = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
        (New-Object System.Drawing.Rectangle(0, 266, $CW, 66)),
        [System.Drawing.Color]::FromArgb(255, 255, 245, 205),
        [System.Drawing.Color]::FromArgb(255, 206, 150, 58),
        [System.Drawing.Drawing2D.LinearGradientMode]::Vertical)
    $g.FillPath($bTit, $path); $bTit.Dispose()
    $pEdge = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(190, 92, 58, 16)), 1.2
    $pEdge.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
    $g.DrawPath($pEdge, $path); $pEdge.Dispose(); $path.Dispose()

    # ── 8. 副標 ──
    $fSub = New-Object System.Drawing.Font("Microsoft JhengHei UI", 17, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
    $bSub = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 202, 190, 236))
    $g.DrawString("繁 體 中 文 化", $fSub, $bSub, (New-Object System.Drawing.RectangleF(0, 332, $CW, 26)), $sf)
    $bSub.Dispose(); $fSub.Dispose()

    # ── 9. 分隔線(兩側漸淡金線 + 中央菱形)──
    $ly = 368; $dHalf = 150; $dCx = [int]($CW / 2)
    $lrL = New-Object System.Drawing.Rectangle(($dCx - 12 - $dHalf), ($ly - 1), $dHalf, 1)
    $bL = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
        $lrL, [System.Drawing.Color]::FromArgb(0, 226, 182, 106),
              [System.Drawing.Color]::FromArgb(235, 226, 182, 106),
        [System.Drawing.Drawing2D.LinearGradientMode]::Horizontal)
    $g.FillRectangle($bL, $lrL); $bL.Dispose()
    $lrR = New-Object System.Drawing.Rectangle(($dCx + 12), ($ly - 1), $dHalf, 1)
    $bR = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
        $lrR, [System.Drawing.Color]::FromArgb(235, 226, 182, 106),
              [System.Drawing.Color]::FromArgb(0, 226, 182, 106),
        [System.Drawing.Drawing2D.LinearGradientMode]::Horizontal)
    $g.FillRectangle($bR, $lrR); $bR.Dispose()
    $dm = New-Object System.Drawing.Point[] 4
    $dm[0] = New-Object System.Drawing.Point($dCx, ($ly - 6))
    $dm[1] = New-Object System.Drawing.Point(($dCx + 5), ($ly - 1))
    $dm[2] = New-Object System.Drawing.Point($dCx, ($ly + 4))
    $dm[3] = New-Object System.Drawing.Point(($dCx - 5), ($ly - 1))
    $bDm = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 240, 206, 138))
    $g.FillPolygon($bDm, $dm); $bDm.Dispose()

    # ── 10. 作者印章「源」+ 署名 ──
    $fCr = New-Object System.Drawing.Font("Microsoft JhengHei UI", 15, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
    $credit = "開發人員:源"
    $csz = $g.MeasureString($credit, $fCr)
    $sealS = 30
    $totW = $sealS + 10 + $csz.Width
    $cx = ($CW - $totW) / 2.0
    $cy = 382.0
    $sp = New-Object System.Drawing.Drawing2D.GraphicsPath
    $rr2 = 7; $sx2 = [single]$cx; $sy2 = [single]$cy
    $sp.AddArc($sx2, $sy2, ($rr2 * 2), ($rr2 * 2), 180, 90)
    $sp.AddArc(($sx2 + $sealS - $rr2 * 2), $sy2, ($rr2 * 2), ($rr2 * 2), 270, 90)
    $sp.AddArc(($sx2 + $sealS - $rr2 * 2), ($sy2 + $sealS - $rr2 * 2), ($rr2 * 2), ($rr2 * 2), 0, 90)
    $sp.AddArc($sx2, ($sy2 + $sealS - $rr2 * 2), ($rr2 * 2), ($rr2 * 2), 90, 90)
    $sp.CloseFigure()
    $bSeal = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
        (New-Object System.Drawing.Rectangle([int]$cx, [int]$cy, $sealS, $sealS)),
        [System.Drawing.Color]::FromArgb(255, 176, 58, 52),
        [System.Drawing.Color]::FromArgb(255, 118, 30, 34),
        [System.Drawing.Drawing2D.LinearGradientMode]::Vertical)
    $g.FillPath($bSeal, $sp); $bSeal.Dispose()
    $pSeal = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(255, 226, 182, 106)), 1.4
    $g.DrawPath($pSeal, $sp); $pSeal.Dispose(); $sp.Dispose()
    $fSeal = New-Object System.Drawing.Font("Microsoft JhengHei UI", 20, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
    $bSealT = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 255, 244, 220))
    $g.DrawString("源", $fSeal, $bSealT,
        (New-Object System.Drawing.RectangleF([single]$cx, [single]($cy + 1), [single]$sealS, [single]$sealS)), $sf)
    $bSealT.Dispose(); $fSeal.Dispose()
    $sfL = New-Object System.Drawing.StringFormat
    $sfL.Alignment = [System.Drawing.StringAlignment]::Near
    $sfL.LineAlignment = [System.Drawing.StringAlignment]::Center
    $bCr = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 222, 210, 246))
    $g.DrawString($credit, $fCr, $bCr,
        (New-Object System.Drawing.RectangleF([single]($cx + $sealS + 10), [single]$cy, [single]($csz.Width + 8), [single]$sealS)), $sfL)
    $bCr.Dispose(); $fCr.Dispose()

    # ── 11. 進度條 ──
    $barX = 150; $barW = 420; $barY = $CH - 26
    $bTrk = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(90, 120, 108, 168))
    $g.FillRectangle($bTrk, $barX, $barY, $barW, 3); $bTrk.Dispose()
    $fillW = [int]($barW * [Math]::Max(0.0, [Math]::Min(1.0, $prog)))
    if ($fillW -gt 2) {
        $bFill = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
            (New-Object System.Drawing.Rectangle($barX, $barY, $fillW, 3)),
            [System.Drawing.Color]::FromArgb(255, 226, 182, 106),
            [System.Drawing.Color]::FromArgb(255, 255, 246, 208),
            [System.Drawing.Drawing2D.LinearGradientMode]::Horizontal)
        $g.FillRectangle($bFill, $barX, $barY, $fillW, 3); $bFill.Dispose()
        $bh = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(200, 255, 252, 232))
        $g.FillEllipse($bh, [single]($barX + $fillW - 3), [single]($barY - 2), 7, 7); $bh.Dispose()
    }
    $fLd = New-Object System.Drawing.Font("Microsoft JhengHei UI", 11, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
    $bLd = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(190, 158, 146, 200))
    $g.DrawString("載入中…", $fLd, $bLd, [single]$barX, [single]($barY - 20))
    $sfR = New-Object System.Drawing.StringFormat
    $sfR.Alignment = [System.Drawing.StringAlignment]::Far
    $g.DrawString("點一下可跳過", $fLd, $bLd,
        (New-Object System.Drawing.RectangleF([single]$barX, [single]($barY - 20), [single]$barW, 18)), $sfR)
    if ($ver) {
        $bVer = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(120, 176, 164, 214))
        $g.DrawString($ver, $fLd, $bVer, (New-Object System.Drawing.RectangleF(0, 10, ($CW - 14), 18)), $sfR)
        $bVer.Dispose()
    }
    $bLd.Dispose(); $fLd.Dispose()

    # ── 12. 外框 ──
    $pB = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(150, 148, 122, 190)), 1
    $g.DrawRectangle($pB, 0, 0, ($CW - 1), ($CH - 1)); $pB.Dispose()
    $sf.Dispose(); $sfL.Dispose(); $sfR.Dispose()
}

# ── 音樂:WPF MediaPlayer(走 Media Foundation,wav/mp3/mp4/m4a 都吃)──
# 不用 SoundPlayer 是因為它只支援 wav;不用 MCI 是因為它無法平順淡出音量。
$player = $null
if ($MUSIC -and (Test-Path -LiteralPath $MUSIC)) {
    try {
        $player = New-Object System.Windows.Media.MediaPlayer
        $player.Volume = [double]$VOL
        $player.Open([Uri]$MUSIC)
        $player.Play()
    } catch { $player = $null }
}

$f = New-Object System.Windows.Forms.Form
try { $f.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::None } catch {}
$f.FormBorderStyle = "None"; $f.StartPosition = "CenterScreen"
$f.ClientSize = New-Object System.Drawing.Size([int]($SPW * $UIK), [int]($SPH * $UIK))
$f.ShowInTaskbar = $false; $f.TopMost = $true
$f.BackColor = [System.Drawing.Color]::FromArgb(10, 12, 34)
$f.Opacity = 0.0
$f.KeyPreview = $true
$f.Cursor = [System.Windows.Forms.Cursors]::Hand
# 雙緩衝(不設會閃爍;Form 的 DoubleBuffered 是 protected,只能用反射開)
try { $f.GetType().GetProperty("DoubleBuffered", [Reflection.BindingFlags]"Instance,NonPublic").SetValue($f, $true, $null) } catch {}

$state = @{ T0 = [Diagnostics.Stopwatch]::StartNew(); Fading = $false; FadeT0 = 0.0 }
$FADEMS = 520.0

$f.Add_Paint({
    try {
        $el = $state.T0.Elapsed.TotalMilliseconds
        $p = $el / $MINMS
        if ($SYNC.Close) { $p = [Math]::Max($p, 0.90) }
        if ($state.Fading) { $p = 1.0 }
        # 高 DPI:畫布仍以 720x470 設計,整張用變換矩陣等比放大
        if ($UIK -gt 1.01) { $_.Graphics.ScaleTransform([single]$UIK, [single]$UIK) }
        Draw-SpiritLogo $_.Graphics $SPW $SPH $p ($el / 1000.0) $VER
    } catch {}
})

$skip = { $SYNC.Skip = $true }
$f.Add_Click($skip)
$f.Add_KeyDown($skip)

$tm = New-Object System.Windows.Forms.Timer
$tm.Interval = 33
$tm.Add_Tick({
    try {
        $el = $state.T0.Elapsed.TotalMilliseconds
        if (-not $state.Fading) {
            if ($f.Opacity -lt 1.0) { $f.Opacity = [Math]::Min(1.0, $f.Opacity + 0.10) }   # 淡入
            $f.Invalidate()
            # 載入完成(且已達最短展示時間)或使用者點擊 → 開始淡出
            if ($SYNC.Skip -or ($SYNC.Close -and $el -ge $MINMS)) {
                $state.Fading = $true
                $state.FadeT0 = $el
            }
        } else {
            $k = ($state.T0.Elapsed.TotalMilliseconds - $state.FadeT0) / $FADEMS
            if ($k -ge 1.0) { $tm.Stop(); $f.Close() }
            else {
                $f.Opacity = [Math]::Max(0.0, 1.0 - $k)
                # 音樂跟著畫面一起淡掉,不會「啪」一聲斷掉
                if ($player) { try { $player.Volume = [double]$VOL * (1.0 - $k) } catch {} }
            }
        }
    } catch { try { $tm.Stop(); $f.Close() } catch {} }
})
$tm.Start()
try { [void]$f.ShowDialog() } catch {}
try { $tm.Stop(); $tm.Dispose() } catch {}
if ($player) { try { $player.Stop(); $player.Close() } catch {} }
try { $f.Dispose() } catch {}
$SYNC.Done = $true
'@

function Start-Splash([string]$music, [double]$vol, [string]$ver, [double]$minMs) {
    try {
        $script:SplashSync = [hashtable]::Synchronized(@{ Close = $false; Skip = $false; Done = $false })
        $script:SplashRS = [runspacefactory]::CreateRunspace()
        $script:SplashRS.ApartmentState = "STA"        # WinForms 一定要 STA,否則視窗行為異常
        $script:SplashRS.ThreadOptions = "ReuseThread"
        $script:SplashRS.Open()
        $script:SplashRS.SessionStateProxy.SetVariable("SYNC",  $script:SplashSync)
        $script:SplashRS.SessionStateProxy.SetVariable("MUSIC", $music)
        $script:SplashRS.SessionStateProxy.SetVariable("VOL",   $vol)
        $script:SplashRS.SessionStateProxy.SetVariable("VER",   $ver)
        $script:SplashRS.SessionStateProxy.SetVariable("MINMS", $minMs)
        $script:SplashRS.SessionStateProxy.SetVariable("UIK",   $UiK)
        $script:SplashPS = [powershell]::Create()
        $script:SplashPS.Runspace = $script:SplashRS
        [void]$script:SplashPS.AddScript($SplashBody)
        [void]$script:SplashPS.BeginInvoke()
    } catch { $script:SplashSync = $null }   # 開場畫面失敗就當作沒有,絕不影響工具本身
}

function Stop-Splash {
    if (-not $script:SplashSync) { return }
    try {
        $script:SplashSync.Close = $true
        $sw = [Diagnostics.Stopwatch]::StartNew()
        # 等它淡出結束;最多 8 秒,絕不讓開場畫面把工具卡死
        while (-not $script:SplashSync.Done -and $sw.ElapsedMilliseconds -lt 8000) { Start-Sleep -Milliseconds 40 }
    } catch {}
    $script:SplashSync = $null
    try { $script:SplashPS.Dispose() } catch {}
    try { $script:SplashRS.Close(); $script:SplashRS.Dispose() } catch {}
}

# 讀 SpiritZh_gui.txt 的 splash / splashvol 決定要不要播。
# ★ 直接讀檔不等 Load-Config —— 那個要到最後才跑,開場動畫得在耗時的載入【之前】就開始。
$curSplash = $true; $curSplashVol = 35
try {
    $gp = Join-Path (PluginDir) "SpiritZh_gui.txt"
    if ((PluginDir) -ne "" -and (Test-Path -LiteralPath $gp)) {
        foreach ($l in (Get-Content -LiteralPath $gp -Encoding UTF8)) {
            if ($l.Trim() -match "^splash\s*=\s*0") { $curSplash = $false }
            if ($l.Trim() -match "^splashvol\s*=\s*(\d+)") { $curSplashVol = [int]$Matches[1] }
        }
    }
} catch {}
if ($curSplashVol -lt 0) { $curSplashVol = 0 }
if ($curSplashVol -gt 100) { $curSplashVol = 100 }
if ($curSplash) {
    $introFile = Find-IntroMusic
    # 有音樂就讓它唱完一句(4.2 秒);沒音樂只跑動畫,縮短到 2.2 秒不拖時間
    $minShow = 2200.0
    if ($introFile -ne "") { $minShow = 4200.0 }
    Start-Splash $introFile ($curSplashVol / 100.0) $ToolVer $minShow
}

# ★★ 視窗尺寸一定要夾到螢幕工作區才顯示。
#   XAML 寫死 Height=1040(DIP)+ WindowStartupLocation="CenterScreen",
#   但 1366x768 的筆電、或 1080p 開 150% 縮放(DIP 高度只剩 720)都放不下 ——
#   CenterScreen 會把 Top 算成負值,結果是【標題列跑到畫面上方外面、
#   底部那條「套用設定」跑到下方外面】,而且拖不回來(抓不到標題列)。
#   舊工具 settings.ps1:184-188 有夾限,新工具搬功能時漏掉了。
#   ※ SystemParameters::WorkArea 回傳的已經是 DIP,不用自己換算 DPI 縮放。
try {
    $wa = [System.Windows.SystemParameters]::WorkArea
    if ($wa.Height -gt 200 -and $window.Height -gt ($wa.Height - 40)) {
        $window.Height = [Math]::Max(560, $wa.Height - 40)
    }
    if ($wa.Width -gt 200 -and $window.Width -gt ($wa.Width - 40)) {
        $window.Width = [Math]::Max(900, $wa.Width - 40)
    }
} catch {}

Refresh-Header
Load-Fonts
Load-Config
Load-DpsConfig
Load-QualityConfig
Load-BeamConfig
Load-AudioConfig
Load-CustomConfig
Build-CurStyleList
Load-CursorConfig
Load-BossAlert
Update-PriceStat
Update-Summary
# 版面量好之後自動跑一次健檢(進度條要有 ActualWidth 才算得出寬度)
# ★★ 未儲存保護。用 WPF 的【類別層級】事件處理常式一次攔住所有 TextBox/勾選/下拉,
#    不必去綁兩百個控制項(這個工具有 ~200 個 x:Name)。
#    $script:uiReady 之前的變更是程式自己 Load-* 造成的,不算「使用者改過」。
#    ★ TabControl 也繼承 Selector —— 換分頁會冒泡上來,要排除,不然切個分頁就被當成改過。
$script:uiDirty = $false; $script:uiReady = $false
function Mark-Dirty($s) {
    if (-not $script:uiReady) { return }
    if ($s -is [System.Windows.Controls.TabControl]) { return }
    $script:uiDirty = $true
}
try {
    [System.Windows.EventManager]::RegisterClassHandler(
        [System.Windows.Controls.TextBox], [System.Windows.Controls.TextBox]::TextChangedEvent,
        [System.Windows.Controls.TextChangedEventHandler]{ param($s, $e) Mark-Dirty $s })
    [System.Windows.EventManager]::RegisterClassHandler(
        [System.Windows.Controls.Primitives.ToggleButton], [System.Windows.Controls.Primitives.ToggleButton]::CheckedEvent,
        [System.Windows.RoutedEventHandler]{ param($s, $e) Mark-Dirty $s })
    [System.Windows.EventManager]::RegisterClassHandler(
        [System.Windows.Controls.Primitives.ToggleButton], [System.Windows.Controls.Primitives.ToggleButton]::UncheckedEvent,
        [System.Windows.RoutedEventHandler]{ param($s, $e) Mark-Dirty $s })
    [System.Windows.EventManager]::RegisterClassHandler(
        [System.Windows.Controls.Primitives.Selector], [System.Windows.Controls.Primitives.Selector]::SelectionChangedEvent,
        [System.Windows.Controls.SelectionChangedEventHandler]{ param($s, $e) Mark-Dirty $s })
} catch {}
$window.Add_Closing({
    param($s, $e)
    if (-not $script:uiDirty) { return }
    # 套用不了的時候(沒安裝翻譯、進階設定開著)不要問「要不要先套用」—— 那會給一個按了沒用的選項。
    if (-not $BtnApply.IsEnabled) {
        $why = $(if ($BtnApply.ToolTip) { [string]$BtnApply.ToolTip } else { "目前無法套用。" })
        if (-not (Confirm-Msg "改的東西會不見" ("你改了設定但還沒套用,而且現在套用不了:`n`n" + $why + "`n`n還是要關掉嗎?") "關掉(丟棄修改)" "先不要關")) {
            $e.Cancel = $true
        }
        return
    }
    if (-not (Confirm-Msg "還沒套用" "你改了設定但還沒按「套用設定」,直接關掉的話這些修改會不見。`n`n要先套用嗎?" "先套用再關" "直接關掉")) { return }
    Do-Apply
    # ★ 套用失敗就別關 —— 檔案八成被鎖著,關掉等於把使用者剛才的修改直接丟掉。
    #   留在畫面上,他解鎖後再按一次「套用設定」就是重試同樣的內容。
    if ($script:saveErr -and $script:saveErr.Count -gt 0) { $e.Cancel = $true }
})
# 鍵盤:Ctrl+S 套用、Esc 關閉。★ 刻意不接 Enter —— 焦點在文字框裡按 Enter 是換行/確認輸入,
#   拿來當「套用」會讓人在打字打到一半誤觸。
$window.Add_KeyDown({
    param($s, $e)
    try {
        if ($e.Key -eq [System.Windows.Input.Key]::Escape) { $window.Close(); return }
        if ($e.Key -eq [System.Windows.Input.Key]::S -and
            ([System.Windows.Input.Keyboard]::Modifiers -band [System.Windows.Input.ModifierKeys]::Control)) {
            $e.Handled = $true; Do-Apply
        }
    } catch {}
})
$window.Add_ContentRendered({
    $script:uiReady = $true; Run-HealthCheck
    # 第一次開工具自動跳教學(舊工具的行為);看過就寫 tutorial=1 進 gui.txt,之後不再跳
    if (-not $script:tutorialDone) {
        $pd = PluginDir
        if ($pd -and (Test-Path -LiteralPath $pd)) {
            try { Show-Tutorial $true } catch { }
            [void](Save-KV (Join-Path $pd "SpiritZh_gui.txt") @{ "tutorial" = "1" })
            $script:tutorialDone = $true
        }
    }
})
# 載入完成 → 通知開場動畫淡出(內含 8 秒逾時,絕不會把工具卡死)。
# ★ Stop-Splash 裡的 Start-Sleep 迴圈跑在 ShowDialog【之前】,那時還沒有訊息迴圈,
#   跟本專案「Start-Process -Wait 讓已經在跑的 UI 沒有回應」那個坑不是同一件事。
Stop-Splash

# ══════════════════════════════════════════════════════════════════════
#  檢查更新(v3.76.4)—— 設計理由見 tools\更新機制說明.md
#   ★ 一定驗簽:只驗 SHA256 擋不住「GitHub 帳號被盜、ZIP 與雜湊一起改」;
#     簽章的私鑰只在作者電腦上,偽造不了。驗不過一律當作沒有更新(不提示、不重試)。
#   ★ 不做全自動安裝:遊戲開著時檔案是鎖住的,而且靜默覆蓋別人的東西是壞習慣。
#   ★ 網路動作全在背景 runspace,UI 不卡;主執行緒只用 DispatcherTimer 收結果。
# ══════════════════════════════════════════════════════════════════════
$script:UPD_OWNER = "SillyGirlsBoy"
$script:UPD_REPO  = "SpiritVale-ModsTool"
$script:UPD_BRANCH = "main"
$script:UPD_PUB = @'
<RSAKeyValue><Modulus>uFdotcA1O0lHncEP9akiJMUTwWsDIpBvi+FzPfrgo6QonhaVYI+p90EA9dy4bSIiA0fBp8YLtfWrNaPg6wT6DIcrmv8MlH2tgayXX4/mdGib9QnF7FMfGvwP5dJPULIJl6bCOgEllag6oSAracHmCCkYx+d3eBvsUqbHvs1tnsNx+53oYR8Ylnw22jRlFx3FJdaY6q3z3KbWu9xdrowKjnPvCTZIXfRgfx/S35Y18F/JvXSlhvq1FH/2YN1+7LwKSVU4Lg+2RXUyMPCSXLMJjmH73xqJaWXQYaU51F7AWZzLSkJ7FbtQADPCtJrOQbrsvrb3+nPRgr44i6lWKOxZON7auJJNr6GuezuHls6vpsFwUQXVrtKWSGh4KRVGaE8tdj8HJ+ZfvfoU1W3viSXItdkuEWAB5WvoQDJBk9VszzOh+bhz2IBxgYLoRqYftcOHWn5xMfS4HAX+chDRoS+dYiuZQsyqZyNoJxe/iey5uNy0fD+x0vvbsXoplUd6QPjV</Modulus><Exponent>AQAB</Exponent></RSAKeyValue>
'@
$script:updMode  = "notify"      # notify | auto | off
$script:updBusy  = $false
$script:updShared = $null
$script:updRs = $null; $script:updPs = $null; $script:updHandle = $null
$script:updTimer = $null
$script:updInfo = $null          # 驗過簽的 version.json 物件
$script:updZip = ""              # 下載好且驗過雜湊的 ZIP 路徑

function Upd-Say([string]$s) { try { $LblUpdState.Text = $s } catch {} }

# 版本字串比大小:1.2.10 > 1.2.9(純字串比會判錯)
function Upd-VerGt([string]$a, [string]$b) {
    $pa = @(($a -replace "[^0-9.]", "").Split(".") | ForEach-Object { [int]("0" + $_) })
    $pb = @(($b -replace "[^0-9.]", "").Split(".") | ForEach-Object { [int]("0" + $_) })
    for ($i = 0; $i -lt [Math]::Max($pa.Count, $pb.Count); $i++) {
        $x = $(if ($i -lt $pa.Count) { $pa[$i] } else { 0 })
        $y = $(if ($i -lt $pb.Count) { $pb[$i] } else { 0 })
        if ($x -ne $y) { return ($x -gt $y) }
    }
    return $false
}

# 驗簽:對【位元組】驗,所以 version.json 產出時固定 UTF-8 無 BOM + LF,誰都不准順手改編碼
function Upd-VerifySig([byte[]]$data, [string]$sigB64) {
    try {
        $rsa = [System.Security.Cryptography.RSA]::Create()
        try {
            $rsa.FromXmlString($script:UPD_PUB.Trim())
            return $rsa.VerifyData($data, [Convert]::FromBase64String($sigB64.Trim()),
                [System.Security.Cryptography.HashAlgorithmName]::SHA256,
                [System.Security.Cryptography.RSASignaturePadding]::Pkcs1)
        } finally { $rsa.Dispose() }
    } catch { return $false }
}

# 背景工作:$mode = "check"(抓 version.json)或 "download"(抓 ZIP)
# ── 下載進度視窗(源要求:大檔下載要有進度條,不然像當機)──
# 非模態、置頂;進度靠下載 job 的 $sh.pct 推。Content-Length 拿不到時切跑馬燈。
$script:updProg = $null; $script:updProgBar = $null; $script:updProgLbl = $null
function Upd-ProgShow([double]$sizeMB) {
    try {
        $px = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        WindowStyle="None" ResizeMode="NoResize" ShowInTaskbar="False" Topmost="True"
        WindowStartupLocation="CenterOwner" SizeToContent="Height" Width="470"
        Background="#151C2B" FontFamily="Microsoft JhengHei UI" Foreground="#E6EBF2">
  <Border BorderBrush="#1D5F8A" BorderThickness="1" Padding="24,20">
    <StackPanel>
      <TextBlock Text="正在下載更新…" FontSize="16" FontWeight="SemiBold" Foreground="#22C9F0" Margin="0,0,0,4"/>
      <TextBlock x:Name="PS" Text="" FontSize="12" Foreground="#7C93AD" Margin="0,0,0,14"/>
      <ProgressBar x:Name="PB" Height="20" Minimum="0" Maximum="100" Value="0"
                   Foreground="#22C9F0" Background="#0A1626" BorderBrush="#14526E" BorderThickness="1"/>
      <TextBlock x:Name="PL" Text="連線中…" FontSize="13" Foreground="#E6EBF2" Margin="0,10,0,0"/>
      <TextBlock Text="下載完會自動驗證數位簽章與 SHA256,請稍候。" FontSize="12" Foreground="#7C93AD" Margin="0,4,0,16" TextWrapping="Wrap"/>
      <Button x:Name="BC" Content="取消下載" Width="110" Height="30" HorizontalAlignment="Right"/>
    </StackPanel>
  </Border>
</Window>
'@
        $script:updProg = [Windows.Markup.XamlReader]::Parse($px)
        try { $script:updProg.Owner = $window } catch {}
        $script:updProgBar = $script:updProg.FindName("PB")
        $script:updProgLbl = $script:updProg.FindName("PL")
        $script:updProg.FindName("PS").Text = "共 " + [math]::Round($sizeMB, 1) + " MB"
        $script:updProg.FindName("BC").Add_Click({
            try { if ($script:updShared) { $script:updShared.cancel = $true } } catch {}
            try { $script:updProgLbl.Text = "取消中…" } catch {}
        })
        # 沒有標題列,但 Alt+F4 仍可能關 —— 當成取消,並允許關閉
        $script:updProg.Add_Closing({ try { if ($script:updShared) { $script:updShared.cancel = $true } } catch {} })
        $script:updProgBar.IsIndeterminate = $true    # 還沒收到進度前先跑馬燈
        $script:updProg.Show()
    } catch {}
}
function Upd-ProgSet([int]$pct) {
    try {
        if (-not $script:updProg) { return }
        if ($pct -le 0) {
            if (-not $script:updProgBar.IsIndeterminate) { $script:updProgBar.IsIndeterminate = $true }
            $script:updProgLbl.Text = "連線中…"
        } else {
            if ($pct -gt 100) { $pct = 100 }
            if ($script:updProgBar.IsIndeterminate) { $script:updProgBar.IsIndeterminate = $false }
            $script:updProgBar.Value = $pct
            $script:updProgLbl.Text = "$pct%"
        }
    } catch {}
}
function Upd-ProgHide {
    try { if ($script:updProg) { $script:updProg.Close() } } catch {}
    $script:updProg = $null; $script:updProgBar = $null; $script:updProgLbl = $null
}

function Upd-StartJob([string]$mode, [hashtable]$arg) {
    if ($script:updBusy) { return $false }
    $script:updBusy = $true
    $script:updShared = [hashtable]::Synchronized(@{ done = $false; ok = $false; err = ""; pct = 0; mode = $mode })
    foreach ($k in $arg.Keys) { $script:updShared[$k] = $arg[$k] }
    $sb = {
        param($sh)
        try {
            [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
            if ($sh.mode -eq "check") {
                $wc = New-Object System.Net.WebClient
                $wc.Encoding = [System.Text.Encoding]::UTF8
                $wc.Headers.Add("User-Agent", "SpiritZh-Updater")
                $sh.json = $wc.DownloadData($sh.urlJson)      # 位元組:驗簽要用原始位元組
                $sh.sig  = $wc.DownloadString($sh.urlSig)
                $wc.Dispose()
                $sh.ok = $true
            }
            else {
                $req = [System.Net.HttpWebRequest]::Create($sh.url)
                $req.UserAgent = "SpiritZh-Updater"; $req.Timeout = 30000
                $res = $req.GetResponse(); $total = $res.ContentLength
                $ins = $res.GetResponseStream()
                $outs = [System.IO.File]::Create($sh.dest)
                try {
                    $buf = New-Object byte[] 262144; $got = 0
                    while (($r = $ins.Read($buf, 0, $buf.Length)) -gt 0) {
                        $outs.Write($buf, 0, $r); $got += $r
                        if ($total -gt 0) { $sh.pct = [int](100 * $got / $total) }
                        if ($sh.cancel) { break }
                    }
                } finally { $outs.Close(); $ins.Close(); $res.Close() }
                if ($sh.cancel) { $sh.err = "已取消" }
                else {
                    $h = (Get-FileHash -LiteralPath $sh.dest -Algorithm SHA256).Hash.ToUpperInvariant()
                    if ($h -ne $sh.sha) { $sh.err = "下載回來的檔案雜湊對不上(可能下載中斷,或檔案在傳輸途中被改過)" }
                    else { $sh.ok = $true }
                }
            }
        }
        catch { $sh.err = $_.Exception.Message }
        finally { $sh.done = $true }
    }
    $script:updRs = [runspacefactory]::CreateRunspace(); $script:updRs.ApartmentState = "MTA"; $script:updRs.Open()
    $script:updPs = [powershell]::Create(); $script:updPs.Runspace = $script:updRs
    [void]$script:updPs.AddScript($sb).AddArgument($script:updShared)
    $script:updHandle = $script:updPs.BeginInvoke()
    if (-not $script:updTimer) {
        $script:updTimer = New-Object System.Windows.Threading.DispatcherTimer
        $script:updTimer.Interval = [TimeSpan]::FromMilliseconds(400)
        $script:updTimer.Add_Tick({ Upd-Poll })
    }
    $script:updTimer.Start()
    return $true
}

function Upd-Cleanup {
    try { if ($script:updTimer) { $script:updTimer.Stop() } } catch {}
    try { if ($script:updPs) { $script:updPs.Dispose() } } catch {}
    try { if ($script:updRs) { $script:updRs.Close(); $script:updRs.Dispose() } } catch {}
    $script:updPs = $null; $script:updRs = $null; $script:updHandle = $null; $script:updBusy = $false
}

function Upd-Poll {
    $sh = $script:updShared
    if (-not $sh) { try { $script:updTimer.Stop() } catch {}; return }
    if ($sh.mode -eq "download" -and -not $sh.done) { Upd-Say ("下載中… " + $sh.pct + "%"); Upd-ProgSet $sh.pct; return }
    if (-not $sh.done) { return }
    $mode = $sh.mode; $ok = $sh.ok; $err = $sh.err
    Upd-Cleanup
    if ($mode -eq "download") { Upd-ProgHide }
    if ($mode -eq "check") { Upd-OnChecked $ok $err $sh } else { Upd-OnDownloaded $ok $err $sh }
}

# 更新摘要 → 給對話框用的文字。內容是【簽章保護】的,不是隨便抓來的網頁文字。
# 最多列 12 條,免得對話框長到爆版;其餘請看 GitHub 的 Releases 頁。
function Upd-ChangeText {
    try {
        $c = $script:updInfo.changes
        if (-not $c -or $c.Count -eq 0) { return "" }
        $n = [Math]::Min(12, $c.Count)
        $s = "`n這版改了什麼:`n"
        for ($i = 0; $i -lt $n; $i++) { $s += ("  ‧" + $c[$i] + "`n") }
        if ($c.Count -gt $n) { $s += ("  ‧…另外還有 " + ($c.Count - $n) + " 項`n") }
        return $s
    } catch { return "" }
}

# ── 公會白名單落檔(v3.76.6)──
#   version.json 裡的 guilds 是【外掛自己會驗簽】的一段字串,設定工具只負責【原封不動搬運】,
#   不解析、不判斷、不加工 —— 因為 shell.ps1 是 509 KB 明文,記事本就能改,外掛不能信它。
#   ★ 一定要在【版本比較之前】呼叫:加公會的時候版本號不會變,放在後面的話,
#     已經是最新版的人會在「已經是最新版」那個 return 就跳出,永遠拿不到新清單。
#   ★ guilds 是空的或沒有這個欄位 → 什麼都不做(不刪舊檔)。舊版 version.json 沒有這欄,
#     刪檔會把已付費公會誤殺;要收回公會靠的是清單裡各自的到期日,不是刪檔。
# ── 把「有新版」告訴外掛(遊戲中會跳公告)──
#   ★ 外掛【不連網】(硬性原則:不對遊戲伺服器多發任何一次請求)。
#     設定工具本來就會查 GitHub,查到就落一個小檔,外掛只負責讀。
#   ★ 已經是最新版 → 刪掉這個檔,不然更新完進遊戲還會再喊一次。
function Upd-DropNewVer([string]$newVer, [bool]$hasNew) {
    try {
        $d = PluginDir
        if (-not $d -or -not (Test-Path -LiteralPath $d)) { return }
        $f = Join-Path $d "SpiritZh_newver.txt"
        if (-not $hasNew) {
            if (Test-Path -LiteralPath $f) { Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue }
            return
        }
        if ([string]::IsNullOrWhiteSpace($newVer)) { return }
        $newVer = $newVer.Trim()
        # 沒變就不寫(外掛看 mtime,不必要的寫入會讓它重讀)
        if (Test-Path -LiteralPath $f) {
            $cur = ""
            try { $cur = (Get-Content -LiteralPath $f -Raw -Encoding UTF8).Trim() } catch { }
            if ($cur -eq $newVer) { return }
        }
        [IO.File]::WriteAllText($f, $newVer, (New-Object Text.UTF8Encoding($false)))
    } catch { }
}

function Upd-DropGuilds {
    try {
        $g = $null
        try { $g = [string]$script:updInfo.guilds } catch { }
        if ([string]::IsNullOrWhiteSpace($g)) { return }
        $d = PluginDir
        if (-not $d -or -not (Test-Path -LiteralPath $d)) { return }
        $f = Join-Path $d "SpiritZh_guilds.dat"
        $g = $g.Trim()
        # 沒變就不寫,免得每次檢查更新都動一次磁碟(外掛是看 mtime 決定要不要重讀)
        if (Test-Path -LiteralPath $f) {
            $cur = ""
            try { $cur = (Get-Content -LiteralPath $f -Raw -Encoding UTF8).Trim() } catch { }
            if ($cur -eq $g) { return }
        }
        [IO.File]::WriteAllText($f, $g, (New-Object Text.UTF8Encoding($false)))
        Upd-Say "公會白名單已更新。"
    } catch { }
}

function Upd-OnChecked([bool]$ok, [string]$err, $sh) {
    if (-not $ok) {
        Upd-Say ("查不到更新資訊(" + $err + ")—— 不影響使用,稍後再試或到 GitHub 手動看。")
        if ($script:updManual) { Show-Msg "檢查更新失敗" ("連不上更新伺服器:`n" + $err + "`n`n可以稍後再試,或直接到 GitHub 的 Releases 頁看。") "warn" }
        $script:updManual = $false
        return
    }
    if (-not (Upd-VerifySig $sh.json $sh.sig)) {
        # 驗不過 = 更新檔可能被動過手腳 → 一律當作沒有更新,並且【明白告訴使用者】
        Upd-Say "⚠ 更新資訊的數位簽章驗證失敗 —— 已忽略這次結果(不會下載任何東西)。"
        if ($script:updManual) { Show-Msg "簽章驗證失敗" "從更新伺服器讀到的版本資訊【簽章不正確】。`n`n為了安全,這次結果一律忽略,不會下載任何檔案。`n如果一直出現這個訊息,請直接到 GitHub 的 Releases 頁手動下載。" "warn" }
        $script:updManual = $false
        return
    }
    try { $script:updInfo = ([System.Text.Encoding]::UTF8.GetString($sh.json) | ConvertFrom-Json) } catch { $script:updInfo = $null }
    if (-not $script:updInfo) { Upd-Say "更新資訊格式看不懂 —— 已忽略。"; $script:updManual = $false; return }
    Upd-DropGuilds
    $newVer = [string]$script:updInfo.version
    $cur = ($ToolVer -replace "^v", "")
    if (-not (Upd-VerGt $newVer $cur)) {
        Upd-DropNewVer "" $false   # 已是最新 → 清掉遊戲內提示檔
        Upd-Say ("已經是最新版(" + $cur + ")。")
        if ($script:updManual) { Show-Msg "已是最新版" ("你目前的版本 v" + $cur + " 已經是最新的了。") "info" }
        $script:updManual = $false
        return
    }
    $script:updManual = $false
    Upd-DropNewVer $newVer $true   # 讓外掛在遊戲中也能提示「已有新的版本補丁」
    Upd-Say ("發現新版 v" + $newVer + "(你目前是 v" + $cur + ")")
    if ($script:updMode -eq "auto") { Upd-Download; return }
    $ans = [System.Windows.MessageBox]::Show(
        ("發現新版 v" + $newVer + "`n你目前的版本:v" + $cur + "`n" + (Upd-ChangeText) + "`n要現在下載嗎?`n`n" +
         "‧下載完會先驗證數位簽章與 SHA256,確認無誤才會讓你安裝`n" +
         "‧不會自動覆蓋你的遊戲,也不會動到你的設定檔"),
        "有新版可以更新", "YesNo", "Information")
    if ($ans -eq "Yes") { Upd-Download }
    else { Upd-Say ("發現新版 v" + $newVer + " —— 你選擇稍後再說。隨時可以按「立即檢查」。") }
}

function Upd-Download {
    if (-not $script:updInfo) { return }
    # 挑包:裝哪一版就更新哪一版(公會版 / 純翻譯包)
    $key = $(if ($script:IsPure) { "pure" } else { "guild" })
    $pkg = $script:updInfo.packages.$key
    if (-not $pkg) { Upd-Say "更新資訊裡找不到對應的安裝包。"; return }
    $dest = Join-Path ([System.IO.Path]::GetTempPath()) ([string]$pkg.file)
    Upd-Say ("下載中… 0%  (" + [math]::Round(([double]$pkg.size) / 1MB, 1) + " MB)")
    Upd-ProgShow ([double]$pkg.size / 1MB)
    [void](Upd-StartJob "download" @{ url = [string]$pkg.url; dest = $dest; sha = ([string]$pkg.sha256).ToUpperInvariant(); cancel = $false })
}

function Upd-OnDownloaded([bool]$ok, [string]$err, $sh) {
    if (-not $ok) {
        if ($err -eq "已取消") { Upd-Say "已取消下載。"; return }
        Upd-Say ("下載失敗:" + $err)
        Show-Msg "下載失敗" ($err + "`n`n可以稍後再試,或到 GitHub 的 Releases 頁手動下載。") "warn"
        return
    }
    $script:updZip = [string]$sh.dest
    Upd-Say ("已下載完成並通過驗證:" + (Split-Path -Leaf $script:updZip))
    $script:updNotes = (Upd-ChangeText)   # 安裝完成後還要再顯示一次
    $running = @(Get-Process -Name "SpiritVale" -ErrorAction SilentlyContinue).Count -gt 0
    $msg = "新版 v" + [string]$script:updInfo.version + " 已下載完成,而且通過數位簽章與 SHA256 驗證。`n"
    $msg += (Upd-ChangeText) + "`n"
    if ($running) { $msg += "⚠ 偵測到遊戲正在執行 —— 安裝需要覆蓋遊戲資料夾的檔案,請先完全關閉遊戲。`n`n" }
    $msg += "要現在解壓縮並開始安裝嗎?`n(安裝程式會保留你目前的所有設定)"
    $ans = [System.Windows.MessageBox]::Show($msg, "準備安裝", "YesNo", $(if ($running) { "Warning" } else { "Information" }))
    if ($ans -ne "Yes") { Upd-Say ("已下載完成,放在:" + $script:updZip + "(你選擇稍後安裝)"); return }
    if ($running) { Show-Msg "遊戲還開著" "請先完全關閉遊戲,再按一次「立即檢查」→「安裝」。`n`n(遊戲執行中時,外掛檔案是被鎖住的,覆蓋一定會失敗)" "warn"; return }
    Upd-Install
}

# ── 把新版安裝包同步回【使用者原本的安裝包資料夾】──
#   為什麼需要:install.ps1 只更新遊戲資料夾。不同步的話,設定工具自己永遠是舊版,
#   每次啟動都會再跳一次更新(網友實測:無限鬼打牆)。
#   ★ 不能當場覆蓋:設定工具正在執行,shell.ps1 與 payload 的 DLL 可能被鎖住 ——
#     交給一個【獨立行程】,先等 8 秒(讓使用者關掉設定工具),再複製。
#   ★ 只覆蓋同名檔、不刪任何東西:使用者自己放的音樂/游標圖不會被清掉。
#   ★ 來源要「看起來真的是安裝包」(有 payload 且有 安裝.bat)才做,避免亂複製。
function Upd-SelfUpdate([string]$srcRoot) {
    try {
        if (-not $srcRoot -or -not (Test-Path -LiteralPath $srcRoot)) { return }
        # 來源必須是完整安裝包
        if (-not (Test-Path -LiteralPath (Join-Path $srcRoot "payload"))) { return }
        $dst = $Here
        if (-not $dst -or -not (Test-Path -LiteralPath $dst)) { return }
        # 目的地也必須是安裝包(有 payload)—— 不然不知道在複製到哪
        if (-not (Test-Path -LiteralPath (Join-Path $dst "payload"))) { return }
        # ★★ 目的地【絕不能】在 %TEMP% 底下(2026-08-27 鬼打牆根因):
        #   那是自動更新的暫存解壓夾,Windows 隨時會清掉 —— 更新到那裡等於沒更新,
        #   使用者開的還是原本那個舊資料夾,於是每次都再跳一次更新。
        try {
            $tmpRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
            if ([IO.Path]::GetFullPath($dst).TrimEnd('\').StartsWith($tmpRoot, [StringComparison]::OrdinalIgnoreCase)) { return }
        } catch { }
        # 同一個資料夾就不用做(從安裝包自己跑安裝的情況)
        try { if ([IO.Path]::GetFullPath($srcRoot).TrimEnd('\') -ieq [IO.Path]::GetFullPath($dst).TrimEnd('\')) { return } } catch { }

        $q1 = $srcRoot -replace "'", "''"
        $q2 = $dst -replace "'", "''"
        # 等設定工具關掉再複製;就算沒關,8 秒後多半也複製得動(只有正在讀的檔會失敗,下次更新會補上)
        $inner = "Start-Sleep -Seconds 8; " +
                 "try { Get-ChildItem -LiteralPath '$q1' -Force | ForEach-Object { " +
                 "Copy-Item -LiteralPath `$_.FullName -Destination '$q2' -Recurse -Force -ErrorAction SilentlyContinue } } catch {}"
        Start-Process powershell -WindowStyle Hidden `
            -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", $inner) -ErrorAction Stop
    } catch { }
}

function Upd-Install {
    try {
        $dir = Join-Path ([System.IO.Path]::GetTempPath()) ("SpiritZh_update_" + (Get-Date -Format "yyyyMMddHHmmss"))
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        Upd-Say "解壓縮中…"
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::ExtractToDirectory($script:updZip, $dir)
        # 找安裝入口:解出來通常是一層資料夾
        $bat = @(Get-ChildItem -LiteralPath $dir -Recurse -Filter "安裝.bat" -ErrorAction SilentlyContinue | Select-Object -First 1)
        if ($bat.Count -eq 0) { $bat = @(Get-ChildItem -LiteralPath $dir -Recurse -Filter "install.ps1" -ErrorAction SilentlyContinue | Select-Object -First 1) }
        if ($bat.Count -eq 0) {
            Start-Process explorer.exe $dir
            Show-Msg "請手動安裝" "已經解壓縮到:`n$dir`n`n裡面找不到安裝.bat,請自己雙擊執行安裝程式。" "warn"
            return
        }
        $target = $bat[0].FullName
        # ★★ 自我更新安裝包資料夾(網友回報「更新後每次開都還是跳更新,無限鬼打牆」)
        #  背景:install.ps1 只把檔案複製到【遊戲】資料夾,使用者手上這個安裝包資料夾不會被動到。
        #  而 $ToolVer 讀的是 $Here\payload\...\SpiritZh.dll(本檔開頭)—— 永遠停在舊版本,
        #  所以每次開設定工具都比對到「有新版」,但遊戲裡其實早就更新好了。
        #  標題列「v3.76.5(遊戲內: v3.76.6 ⚠未更新)」就是這個狀態。
        Upd-SelfUpdate (Split-Path -Parent $target)
        Upd-Say "已交給安裝程式,請照它的畫面操作。"
        if ($target.ToLowerInvariant().EndsWith(".bat")) { Start-Process -FilePath $target -WorkingDirectory (Split-Path -Parent $target) }
        # ★ $target 要包引號:Start-Process 會把 -ArgumentList 陣列用空白接成一整串而且【不補引號】,
        #   而這個路徑在 %TEMP% 底下 —— 使用者名稱只要有空格(C:\Users\John Smith\...)就會被拆開,
        #   powershell 收到一個不存在的 -File 路徑,安裝【靜默不執行】,而下面還是照跳「安裝程式已啟動」。
        else { Start-Process powershell -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", (Q $target)) -WorkingDirectory (Split-Path -Parent $target) }
        Show-Msg "安裝程式已啟動" "安裝視窗會另外開啟,請照它的指示完成。`n`n安裝完成後請關閉這個設定工具再重新開啟,才會讀到新版本。" "info"
    }
    catch { Upd-Say ("解壓縮或啟動安裝程式失敗:" + $_.Exception.Message); Show-Msg "安裝失敗" $_.Exception.Message "error" }
}

# 只取【公會白名單】,不做任何版本更新提示 —— 給「更新檢查:完全不檢查」的使用者用。
#   公會授權跟版本更新是兩件事:使用者可以不想升級,但不能因此拿不到自己買的授權。
#   ★ 一樣走驗簽:沒驗過的位元組一個字都不信(跟 Upd-OnChecked 同一套 Upd-VerifySig)。
#   ★ 失敗完全靜默:這只是補一條授權通道,不該打擾不想更新的人。
function Upd-GuildsOnly {
    if ($script:IsTempCopy) { return }
    try {
        $base = "https://raw.githubusercontent.com/$($script:UPD_OWNER)/$($script:UPD_REPO)/$($script:UPD_BRANCH)"
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $wc = New-Object System.Net.WebClient
        $wc.Encoding = [System.Text.Encoding]::UTF8
        $wc.Headers.Add("User-Agent", "SpiritZh-Updater")
        $j = $wc.DownloadData("$base/version.json")
        $s = $wc.DownloadString("$base/version.json.sig")
        $wc.Dispose()
        if (-not (Upd-VerifySig $j $s)) { return }   # 驗不過就當作沒拿到
        $script:updInfo = ([System.Text.Encoding]::UTF8.GetString($j) | ConvertFrom-Json)
        Upd-DropGuilds
        Upd-Say "已更新公會授權清單(更新檢查為關閉,不會提示新版)。"
    } catch { }
}

function Upd-Check([bool]$manual) {
    if ($script:updBusy) { if ($manual) { Show-Msg "正在忙" "上一個更新工作還沒結束,請稍候。" "info" }; return }
    # ★ 暫存副本不查更新:它的版本永遠是「解壓當下那一版」,查了必定說有新版 → 無限鬼打牆。
    if ($script:IsTempCopy) {
        Upd-Say "這是更新用的暫存副本,不檢查更新 —— 請從你原本的安裝包資料夾開啟設定工具。"
        if ($manual) {
            Show-Msg "這是暫存副本" ("你現在開的是【自動更新解壓出來的暫存副本】:`n" + $Here + "`n`n" +
                "這個資料夾隨時會被系統清掉,而且它的版本永遠停在解壓當下那一版,`n" +
                "所以每次開都會說有新版 —— 這就是「一直跳更新」的原因。`n`n" +
                "請改從你【原本的安裝包資料夾】開啟設定工具。") "warn"
        }
        return
    }
    $script:updManual = $manual
    $base = "https://raw.githubusercontent.com/$($script:UPD_OWNER)/$($script:UPD_REPO)/$($script:UPD_BRANCH)"
    Upd-Say "檢查中…"
    [void](Upd-StartJob "check" @{ urlJson = "$base/version.json"; urlSig = "$base/version.json.sig" })
}

$BtnUpdCheck.Add_Click({ Upd-Check $true })
$CboUpdMode.Add_SelectionChanged({
    $script:updMode = @("notify", "auto", "off")[[Math]::Max(0, $CboUpdMode.SelectedIndex)]
    $pd = PluginDir
    if ($pd -and (Test-Path -LiteralPath $pd)) { [void](Save-KV (Join-Path $pd "SpiritZh_gui.txt") @{ "update" = $script:updMode }) }
})
# 啟動檢查:等視窗畫完再跑,而且是背景 runspace —— 不卡開啟速度
$script:updBootTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:updBootTimer.Interval = [TimeSpan]::FromSeconds(2)
$script:updBootTimer.Add_Tick({
    $script:updBootTimer.Stop()
    # ★★ v3.76.11 深度審查 H23:公會白名單是【授權資料】,不該跟「要不要升級版本」綁在一起。
    #   舊版 Upd-DropGuilds 只在 Upd-OnChecked 裡被呼叫,而更新模式選「完全不檢查」時
    #   根本不會走到那裡 —— 結果是買了公會方案的人【永遠開不了功能】,而且查不出原因。
    #   所以:off 模式仍然去取一次清單(只驗簽落檔,不提示更新、不下載任何東西)。
    if ($script:updMode -ne "off") { Upd-Check $false } else { Upd-GuildsOnly }
})
$script:updBootTimer.Start()

# ══════════ 序號(v3.76.5)══════════
# 使用者這一端【完全不用碰指令列】:把作者給的那串貼上、按套用,工具負責寫檔。
# 檔案位置固定是 遊戲\BepInEx\plugins\SpiritZh_serial.txt(外掛只認這個路徑)。
# ★ 這裡【不做驗證】—— 驗簽在外掛裡(它才有公鑰,而且驗完才知道綁的是不是這台的帳號)。
#   工具只做格式的粗檢,擋掉「整串沒複製完」這種最常見的失誤,其餘交給外掛回報。
# 「啟用」按鈕只在【需啟用(N:)型】的序號上出現 —— 其他型別按了也沒意義,不要讓人困惑。
function Serial-SyncActBtn {
    try {
        $s = ($TxtSerial.Text -replace '\s','')
        $show = $false
        if ($s -and (Get-Command Serial-Kind -ErrorAction SilentlyContinue)) {
            $show = ((Serial-Kind $s).kind -eq "N:")
        }
        $BtnSerialAct.Visibility = $(if ($show) { "Visible" } else { "Collapsed" })
    } catch { }
}

function Serial-File { $d = PluginDir; if ($d) { Join-Path $d "SpiritZh_serial.txt" } else { "" } }

function Serial-Refresh {
    # 我的帳號識別:外掛進遊戲一次後會寫 SpiritZh_myid.txt
    $d = PluginDir
    $idFile = if ($d) { Join-Path $d "SpiritZh_myid.txt" } else { "" }
    $id = ""
    if ($idFile -and (Test-Path -LiteralPath $idFile)) {
        foreach ($ln in (Get-Content -LiteralPath $idFile -Encoding UTF8)) {
            if ($ln.Trim() -match '^\d{17}$') { $id = $ln.Trim(); break }
        }
    }
    if ($id) { $TxtMyId.Text = $id; $BtnMyIdCopy.IsEnabled = $true }
    else { $TxtMyId.Text = "(先進遊戲一次才會產生)"; $BtnMyIdCopy.IsEnabled = $false }

    $f = Serial-File
    if ($f -and (Test-Path -LiteralPath $f)) {
        $cur = ((Get-Content -LiteralPath $f -Encoding UTF8) | Where-Object { $_.Trim() -ne "" -and -not $_.Trim().StartsWith("#") } | Select-Object -First 1)
        if ($cur) {
            $TxtSerial.Text = $cur.Trim()
            $LblSerialState.Text = "已經有一組序號。是否有效要看遊戲裡的判定 —— 進遊戲後開「產生診斷報告」,最上面那行會寫「序號: …」。"
            Serial-SyncActBtn
            return
        }
    }
    Serial-SyncActBtn
    $LblSerialState.Text = "目前沒有序號。"
}

$BtnMyIdCopy.Add_Click({
    try { [Windows.Clipboard]::SetText($TxtMyId.Text); $LblSerialState.Text = "已複製你的帳號識別 —— 貼給作者換序號。" }
    catch { $LblSerialState.Text = "複製失敗,請自己反白選取那串數字。" }
})

$BtnSerialApply.Add_Click({
    $s = ($TxtSerial.Text -replace '\s', '')   # 貼上時常常夾到換行/空白,先清掉
    if (-not $s) { $LblSerialState.Text = "請先把序號貼進上面的欄位。"; return }
    $f = Serial-File
    if (-not $f) { $LblSerialState.Text = "還沒找到遊戲資料夾 —— 請先到「安裝」頁按「瀏覽」。"; return }
    # 粗檢:SVZH1. 開頭、三段、長度像樣。真正的驗簽在外掛裡(公鑰在那邊)。
    $p = $s.Split('.')
    if ($p.Length -ne 3 -or $p[0] -ne "SVZH1" -or $s.Length -lt 200) {
        $LblSerialState.Text = "這串看起來不完整。"
        [void][Windows.MessageBox]::Show("這串序號看起來不完整。`r`n`r`n序號是 SVZH1. 開頭、五百多個字元的一整串,中間不能斷行也不能漏字。`r`n請回去重新完整複製一次。", "序號格式不對", "OK", "Warning")
        return
    }
    try {
        $body = "# SpiritZh 序號 —— 由設定工具寫入,請勿手動修改`r`n" + $s + "`r`n"
        [IO.File]::WriteAllText($f, $body, (New-Object Text.UTF8Encoding($true)))
        $TxtSerial.Text = $s
        Serial-SyncActBtn
        if ((Serial-Kind $s).kind -eq "N:") {
            $LblSerialState.Text = "序號已存好。這是【需啟用】的序號 —— 請接著按「啟用」。"
            [void][Windows.MessageBox]::Show("序號已存好。`r`n`r`n這組是【需啟用】的序號,請接著按「啟用」按鈕完成綁定。", "序號", "OK", "Information")
        } else {
            $LblSerialState.Text = "已寫入。請【重開遊戲】讓它生效。"
            [void][Windows.MessageBox]::Show("序號已寫入。`r`n`r`n請重新開啟遊戲讓它生效。", "序號", "OK", "Information")
        }
    } catch { $LblSerialState.Text = "寫入失敗:" + $_.Exception.Message }
})

$BtnSerialClear.Add_Click({
    $f = Serial-File
    try {
        if ($f -and (Test-Path -LiteralPath $f)) { Remove-Item -LiteralPath $f -Force }
        $TxtSerial.Text = ""
        $LblSerialState.Text = "序號已移除。重開遊戲後會回到公會驗證模式。"
    } catch { $LblSerialState.Text = "移除失敗:" + $_.Exception.Message }
})

$BtnMyIdRefresh.Add_Click({ Serial-Refresh; if ($TxtMyId.Text -match '^\d{17}$') { $LblSerialState.Text = "已讀到你的帳號識別。" } })

# 一鍵複製一段【格式好的申請訊息】—— 對方直接貼給作者,作者那邊也能整段吃下去自動抓號碼。
# 少一次「你那串在哪」「只要數字」的來回。
$BtnMyIdReq.Add_Click({
    if ($TxtMyId.Text -notmatch '^\d{17}$') { $LblSerialState.Text = "還沒讀到帳號識別 —— 先進遊戲一次,再按「重新整理」。"; return }
    $msg = "我要申請 SpiritVale 繁中化的序號`r`n帳號識別:" + $TxtMyId.Text + "`r`n(這串是我的 SteamID64,序號會綁定它)"
    try { [Windows.Clipboard]::SetText($msg); $LblSerialState.Text = "已複製申請訊息 —— 直接貼給作者就好。" }
    catch { $LblSerialState.Text = "複製失敗,請自己把上面那串數字傳給作者。" }
})

# ★ 切到「關於」頁就重讀一次。使用者的動線通常是【先開工具 → 再進遊戲 → 回來看】,
#   只在啟動時讀一次的話,帳號識別永遠停在「先進遊戲一次才會產生」(源 2026-08-26 實測回報)。
$Tabs.Add_SelectionChanged({
    if ($_.Source -eq $Tabs -and ($Tabs.SelectedItem -eq $TabSerial -or $Tabs.SelectedItem -eq $TabAbout)) { Serial-Refresh }
})

# ══════════ 序號啟用(只有這裡會連網,而且只在按下「啟用」那一次)══════════
# 「需啟用(N:)」型的序號本身不含帳號 —— 對方按下啟用,伺服器確認這組還沒被別人綁走,
# 回一張【伺服器私鑰簽的憑證】存在本機。外掛驗那張憑證(內嵌第二把公鑰),偽造不出來。
# ★ 之後完全離線:外掛自己不連網,遊戲行程沒有任何 HTTP 行為。
$script:ACT_URL = "https://spiritzh-activate.bb86850663.workers.dev"

function Serial-Payload([string]$serial) {
    # 只解碼、不驗簽(工具沒有公鑰,驗簽是外掛的事)。目的只是看出它是不是 N: 型。
    try {
        $p = $serial.Split('.')
        if ($p.Length -ne 3) { return $null }
        $s = $p[1].Replace('-','+').Replace('_','/')
        $m = $s.Length % 4
        if ($m -eq 2) { $s += "==" } elseif ($m -eq 3) { $s += "=" } elseif ($m -eq 1) { return $null }
        return [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($s))
    } catch { return $null }
}

function Serial-Kind([string]$serial) {
    $t = Serial-Payload $serial
    if (-not $t) { return @{ kind = "?"; id = "" } }
    $f = $t.Split('|')
    if ($f.Length -lt 3) { return @{ kind = "?"; id = "" } }
    $b = $f[1]
    $k = if ($b -eq "*") { "*" } elseif ($b.Length -ge 2) { $b.Substring(0,2) } else { "?" }
    @{ kind = $k; id = $(if ($f.Length -ge 4) { $f[3] } else { "" }) }
}

function Serial-Sha256Hex([string]$s) {
    $h = [System.Security.Cryptography.SHA256]::Create()
    try { (($h.ComputeHash([Text.Encoding]::UTF8.GetBytes($s)) | ForEach-Object { $_.ToString("x2") }) -join "") }
    finally { $h.Dispose() }
}

$BtnSerialAct.Add_Click({
    $s = ($TxtSerial.Text -replace '\s','')
    if (-not $s) { $LblSerialState.Text = "請先貼上序號並按「套用序號」。"; return }
    if (-not $script:ACT_URL) { $LblSerialState.Text = "這個版本還沒設定啟用伺服器 —— 請跟作者回報。"; return }
    $info = Serial-Kind $s
    if (-not $info.id) { $LblSerialState.Text = "這組序號沒有編號,無法啟用。"; return }
    if ($TxtMyId.Text -notmatch '^\d{17}$') { $LblSerialState.Text = "還沒讀到你的帳號識別 —— 先進遊戲一次,再按「重新整理」。"; return }
    $d = PluginDir
    if (-not $d) { $LblSerialState.Text = "還沒找到遊戲資料夾。"; return }
    try {
        # 舊系統預設可能還在 TLS 1.0,不設的話連不上 Cloudflare
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $LblSerialState.Text = "啟用中…"
        $body = @{ serialId = $info.id; acctHash = (Serial-Sha256Hex $TxtMyId.Text).Substring(0,32) } | ConvertTo-Json -Compress
        $r = Invoke-RestMethod -Uri ($script:ACT_URL.TrimEnd('/') + "/activate") -Method Post `
                               -ContentType "application/json; charset=utf-8" -Body $body -TimeoutSec 20
        if (-not $r.ok) {
            $LblSerialState.Text = "啟用失敗:" + $r.reason
            [void][Windows.MessageBox]::Show("啟用失敗`r`n`r`n" + $r.reason + "`r`n`r`n如果你確定這組序號是給你的,請聯絡作者。", "啟用失敗", "OK", "Error")
            return
        }
        $f = Join-Path $d "SpiritZh_activation.txt"
        [IO.File]::WriteAllText($f, "# SpiritZh 啟用憑證 —— 由設定工具寫入,請勿手動修改`r`n" + $r.cert + "`r`n",
                                (New-Object Text.UTF8Encoding($true)))
        $m2 = $(if ($r.firstTime) { "啟用成功!`r`n`r`n這組序號已經綁定你的 Steam 帳號,別人拿去用不了。" } else { "已重新取得憑證。`r`n`r`n這組序號本來就綁在你的帳號上(重灌/換電腦都可以再啟用)。" })
        $LblSerialState.Text = $(if ($r.firstTime) { "啟用成功!已綁定你的帳號。" } else { "已重新取得憑證。" }) + " 請重開遊戲。"
        [void][Windows.MessageBox]::Show($m2 + "`r`n`r`n請重新開啟遊戲讓它生效。", "啟用成功", "OK", "Information")
    } catch {
        $msg = $_.Exception.Message
        if ($_.Exception.Response) {
            try {
                $sr = New-Object IO.StreamReader($_.Exception.Response.GetResponseStream())
                $j = $sr.ReadToEnd() | ConvertFrom-Json
                if ($j.reason) { $msg = $j.reason }
            } catch { }
        }
        $LblSerialState.Text = "啟用失敗:" + $msg
        [void][Windows.MessageBox]::Show("啟用失敗`r`n`r`n" + $msg + "`r`n`r`n如果是連線問題,檢查一下網路再試一次。", "啟用失敗", "OK", "Error")
    }
})

Serial-Refresh

[void]$window.ShowDialog()
