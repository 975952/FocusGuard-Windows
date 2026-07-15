param(
    [switch]$SelfTest
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Windows.Forms;

public sealed class FocusGuardTrayRecoveryWindow : NativeWindow, IDisposable
{
    private readonly int taskbarCreatedMessage;

    public event EventHandler TaskbarCreated;

    public FocusGuardTrayRecoveryWindow()
    {
        taskbarCreatedMessage = (int)RegisterWindowMessage("TaskbarCreated");
        CreateHandle(new CreateParams());
    }

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern uint RegisterWindowMessage(string message);

    protected override void WndProc(ref Message message)
    {
        if (message.Msg == taskbarCreatedMessage)
        {
            EventHandler handler = TaskbarCreated;
            if (handler != null) handler(this, EventArgs.Empty);
        }
        base.WndProc(ref message);
    }

    public void Dispose()
    {
        if (Handle != IntPtr.Zero) DestroyHandle();
    }
}
'@ -ReferencedAssemblies 'System.Windows.Forms.dll'

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;

public static class FocusGuardNative
{
    [StructLayout(LayoutKind.Sequential)]
    public struct LASTINPUTINFO
    {
        public uint cbSize;
        public uint dwTime;
    }

    [DllImport("user32.dll")]
    public static extern bool GetLastInputInfo(ref LASTINPUTINFO plii);

    [DllImport("user32.dll")]
    public static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int count);

    [DllImport("user32.dll")]
    public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool DestroyIcon(IntPtr hIcon);

    [DllImport("shell32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern int SetCurrentProcessExplicitAppUserModelID(string appID);

    public static double IdleSeconds()
    {
        LASTINPUTINFO info = new LASTINPUTINFO();
        info.cbSize = (uint)Marshal.SizeOf(info);
        if (!GetLastInputInfo(ref info)) return 0;
        return unchecked((uint)Environment.TickCount - info.dwTime) / 1000.0;
    }
}
'@

[xml]$EmbeddedMainXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="专注守卫 · 别跑偏" Width="1040" Height="720" MinWidth="900" MinHeight="650"
        WindowStartupLocation="CenterScreen" Background="#F4F1EA" FontFamily="Microsoft YaHei UI">
  <Window.Resources>
    <Style TargetType="TextBlock">
      <Setter Property="Foreground" Value="#252521"/>
    </Style>
    <Style TargetType="TextBox">
      <Setter Property="Background" Value="#FFFFFF"/>
      <Setter Property="Foreground" Value="#252521"/>
      <Setter Property="BorderBrush" Value="#D8D4CA"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Padding" Value="10,7"/>
      <Setter Property="FontSize" Value="13"/>
    </Style>
    <Style TargetType="ComboBox">
      <Setter Property="Background" Value="#FFFFFF"/>
      <Setter Property="Foreground" Value="#252521"/>
      <Setter Property="BorderBrush" Value="#D8D4CA"/>
      <Setter Property="Padding" Value="8,5"/>
      <Setter Property="FontSize" Value="13"/>
    </Style>
    <Style x:Key="PrimaryButton" TargetType="Button">
      <Setter Property="Background" Value="#1E5B45"/>
      <Setter Property="Foreground" Value="White"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Padding" Value="22,11"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="FontSize" Value="14"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border Background="{TemplateBinding Background}" CornerRadius="7" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="SecondaryButton" TargetType="Button" BasedOn="{StaticResource PrimaryButton}">
      <Setter Property="Background" Value="#E4E0D6"/>
      <Setter Property="Foreground" Value="#33332E"/>
    </Style>
    <Style x:Key="SmallButton" TargetType="Button" BasedOn="{StaticResource SecondaryButton}">
      <Setter Property="Padding" Value="12,7"/>
      <Setter Property="FontSize" Value="12"/>
    </Style>
  </Window.Resources>

  <Grid Margin="26">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>

    <Grid Grid.Row="0" Margin="0,0,0,20">
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="*"/>
        <ColumnDefinition Width="Auto"/>
      </Grid.ColumnDefinitions>
      <StackPanel>
        <TextBlock Text="专注守卫" FontSize="27" FontWeight="Bold"/>
        <TextBlock Text="在你走神的时候，把你拽回来。所有检测只在本机进行。" Margin="0,6,0,0" Foreground="#6E6C64" FontSize="13"/>
      </StackPanel>
      <Border Grid.Column="1" Background="#E3EFE8" CornerRadius="16" Padding="13,7" VerticalAlignment="Center">
        <StackPanel Orientation="Horizontal">
          <Ellipse x:Name="StatusDot" Width="9" Height="9" Fill="#899087" Margin="0,0,7,0"/>
          <TextBlock x:Name="StatusBadge" Text="尚未开始" Foreground="#295A43" FontWeight="SemiBold"/>
        </StackPanel>
      </Border>
    </Grid>

    <Grid Grid.Row="1">
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="390"/>
        <ColumnDefinition Width="18"/>
        <ColumnDefinition Width="*"/>
      </Grid.ColumnDefinitions>

      <Border Grid.Column="0" Background="#FCFBF8" CornerRadius="13" Padding="22" BorderBrush="#E4E0D7" BorderThickness="1">
        <ScrollViewer VerticalScrollBarVisibility="Auto">
          <StackPanel>
            <TextBlock Text="本次专注" FontSize="18" FontWeight="Bold" Margin="0,0,0,14"/>

            <TextBlock Text="你现在要完成什么？" FontWeight="SemiBold" FontSize="12"/>
            <TextBox x:Name="TaskBox" Margin="0,6,0,13" Text="完成当前最重要的任务"/>

            <Grid Margin="0,0,0,13">
              <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="12"/>
                <ColumnDefinition Width="*"/>
              </Grid.ColumnDefinitions>
              <StackPanel Grid.Column="0">
                <TextBlock Text="专注时长（分钟）" FontWeight="SemiBold" FontSize="12"/>
                <TextBox x:Name="DurationBox" Margin="0,6,0,0" Text="45"/>
              </StackPanel>
              <StackPanel Grid.Column="2">
                <TextBlock Text="无操作提醒（秒）" FontWeight="SemiBold" FontSize="12"/>
                <TextBox x:Name="IdleBox" Margin="0,6,0,0" Text="180"/>
              </StackPanel>
            </Grid>

            <Grid Margin="0,0,0,13">
              <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="12"/>
                <ColumnDefinition Width="*"/>
              </Grid.ColumnDefinitions>
              <StackPanel Grid.Column="0">
                <TextBlock Text="跑偏宽限（秒）" FontWeight="SemiBold" FontSize="12"/>
                <TextBox x:Name="GraceBox" Margin="0,6,0,0" Text="25"/>
              </StackPanel>
              <StackPanel Grid.Column="2">
                <TextBlock Text="提醒语气" FontWeight="SemiBold" FontSize="12"/>
                <ComboBox x:Name="ToneBox" Margin="0,6,0,0" SelectedIndex="1">
                  <ComboBoxItem Content="温和"/>
                  <ComboBoxItem Content="直接"/>
                  <ComboBoxItem Content="暴躁"/>
                </ComboBox>
              </StackPanel>
            </Grid>

            <TextBlock Text="允许的应用（每行一个进程名）" FontWeight="SemiBold" FontSize="12"/>
            <TextBox x:Name="AllowedAppsBox" Height="75" AcceptsReturn="True" VerticalScrollBarVisibility="Auto" Margin="0,6,0,5"
                     Text="code&#x0a;winword&#x0a;excel&#x0a;powerpnt&#x0a;notepad&#x0a;obsidian"/>
            <StackPanel Orientation="Horizontal" Margin="0,0,0,13">
              <Button x:Name="AddCurrentAppButton" Content="＋ 加入当前应用" Style="{StaticResource SmallButton}"/>
              <TextBlock Text="例如：code、winword" Foreground="#817E75" FontSize="11" VerticalAlignment="Center" Margin="10,0,0,0"/>
            </StackPanel>

            <TextBlock Text="允许的窗口标题关键词（每行一个）" FontWeight="SemiBold" FontSize="12"/>
            <TextBox x:Name="AllowedTitlesBox" Height="74" AcceptsReturn="True" VerticalScrollBarVisibility="Auto" Margin="0,6,0,4"
                     Text="Codex&#x0a;Visual Studio Code&#x0a;Microsoft Word&#x0a;Excel&#x0a;PowerPoint&#x0a;Notion&#x0a;学习&#x0a;工作&#x0a;课程&#x0a;文档"/>
            <TextBlock Text="浏览器建议按网页标题关键词放行；直接加入 chrome 会放行它的所有网页。" TextWrapping="Wrap" Foreground="#817E75" FontSize="11" Margin="0,0,0,12"/>

            <CheckBox x:Name="SoundCheck" Content="提醒时播放提示音" IsChecked="True" FontSize="12"/>
          </StackPanel>
        </ScrollViewer>
      </Border>

      <Border Grid.Column="2" Background="#1F2421" CornerRadius="13" Padding="28">
        <Grid>
          <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
          </Grid.RowDefinitions>

          <StackPanel Grid.Row="0">
            <TextBlock x:Name="PhaseLabel" Text="准备开始" Foreground="#AFC1B7" FontWeight="SemiBold" FontSize="13"/>
            <TextBlock x:Name="CurrentTaskLabel" Text="先写下这次要完成的事" Foreground="#FFFFFF" FontSize="19" FontWeight="SemiBold" Margin="0,7,0,0" TextWrapping="Wrap"/>
          </StackPanel>

          <StackPanel Grid.Row="1" VerticalAlignment="Center">
            <TextBlock x:Name="CountdownLabel" Text="45:00" Foreground="#FFFFFF" FontFamily="Consolas" FontSize="72" FontWeight="Bold" HorizontalAlignment="Center"/>
            <TextBlock x:Name="MonitorLabel" Text="点击开始后，我会盯住你的去向" Foreground="#AEB3AF" FontSize="12" HorizontalAlignment="Center" Margin="0,7,0,0" TextTrimming="CharacterEllipsis" MaxWidth="500"/>
            <Border Background="#2A302C" CornerRadius="8" Padding="15,12" Margin="0,24,0,0">
              <StackPanel>
                <TextBlock Text="当前活动窗口" Foreground="#8E9992" FontSize="11"/>
                <TextBlock x:Name="WindowLabel" Text="等待检测" Foreground="#E6E9E7" FontSize="12" Margin="0,5,0,0" TextTrimming="CharacterEllipsis"/>
              </StackPanel>
            </Border>
          </StackPanel>

          <StackPanel Grid.Row="2">
            <Grid Margin="0,0,0,16">
              <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="*"/>
              </Grid.ColumnDefinitions>
              <StackPanel Grid.Column="0">
                <TextBlock Text="提醒次数" Foreground="#89948D" FontSize="11"/>
                <TextBlock x:Name="ReminderCountLabel" Text="0" Foreground="White" FontSize="21" FontWeight="SemiBold"/>
              </StackPanel>
              <StackPanel Grid.Column="1">
                <TextBlock Text="拉回次数" Foreground="#89948D" FontSize="11"/>
                <TextBlock x:Name="ReturnCountLabel" Text="0" Foreground="White" FontSize="21" FontWeight="SemiBold"/>
              </StackPanel>
              <StackPanel Grid.Column="2">
                <TextBlock Text="已专注" Foreground="#89948D" FontSize="11"/>
                <TextBlock x:Name="FocusedTimeLabel" Text="0 分钟" Foreground="White" FontSize="21" FontWeight="SemiBold"/>
              </StackPanel>
            </Grid>
            <StackPanel Orientation="Horizontal" HorizontalAlignment="Center">
              <Button x:Name="StartButton" Content="开始专注" Style="{StaticResource PrimaryButton}" Width="140"/>
              <Button x:Name="PauseButton" Content="暂停" Style="{StaticResource SecondaryButton}" Width="105" Margin="10,0,0,0" IsEnabled="False"/>
              <Button x:Name="StopButton" Content="结束" Style="{StaticResource SecondaryButton}" Width="88" Margin="10,0,0,0" IsEnabled="False"/>
            </StackPanel>
          </StackPanel>
        </Grid>
      </Border>
    </Grid>

    <Grid Grid.Row="2" Margin="0,16,0,0">
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="*"/>
        <ColumnDefinition Width="Auto"/>
      </Grid.ColumnDefinitions>
      <TextBlock Text="隐私：不截屏、不读取按键内容、不上传数据；仅检查空闲时长、应用名和窗口标题。" Foreground="#77746C" FontSize="11" VerticalAlignment="Center"/>
      <StackPanel Grid.Column="1" Orientation="Horizontal">
        <Button x:Name="HideButton" Content="最小化" Style="{StaticResource SmallButton}"/>
        <Button x:Name="ExitButton" Content="退出" Style="{StaticResource SmallButton}" Margin="8,0,0,0"/>
      </StackPanel>
    </Grid>
  </Grid>
</Window>
'@

[xml]$EmbeddedReminderXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="专注守卫提醒" Width="650" Height="370" WindowStartupLocation="CenterScreen"
        WindowStyle="None" ResizeMode="NoResize" Topmost="True" ShowInTaskbar="False"
        AllowsTransparency="True" Background="Transparent" FontFamily="Microsoft YaHei UI">
  <Border Background="#FFFDF7" BorderBrush="#242822" BorderThickness="3" CornerRadius="18" Padding="34">
    <Grid>
      <Grid.RowDefinitions>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="*"/>
        <RowDefinition Height="Auto"/>
      </Grid.RowDefinitions>
      <StackPanel>
        <TextBlock x:Name="AlertKicker" Text="喂，注意力跑了" Foreground="#A54032" FontSize="13" FontWeight="Bold"/>
        <TextBlock x:Name="AlertTitle" Text="该回来了。" Foreground="#20231F" FontSize="30" FontWeight="Bold" Margin="0,8,0,0"/>
      </StackPanel>
      <StackPanel Grid.Row="1" VerticalAlignment="Center">
        <TextBlock x:Name="AlertMessage" Text="" Foreground="#343630" FontSize="17" FontWeight="SemiBold" TextWrapping="Wrap"/>
        <Border Background="#F0ECE2" CornerRadius="7" Padding="12,9" Margin="0,18,0,0">
          <TextBlock x:Name="AlertContext" Text="" Foreground="#777269" FontSize="11" TextWrapping="Wrap" TextTrimming="CharacterEllipsis"/>
        </Border>
      </StackPanel>
      <StackPanel Grid.Row="2" Orientation="Horizontal" HorizontalAlignment="Right">
        <Button x:Name="BreakButton" Content="休息 5 分钟" Background="#E4E0D6" Foreground="#31332F" BorderThickness="0" Padding="18,11" FontWeight="SemiBold" Cursor="Hand"/>
        <Button x:Name="ReturnButton" Content="我现在就回来" Background="#1E5B45" Foreground="White" BorderThickness="0" Padding="22,11" FontWeight="SemiBold" Margin="10,0,0,0" Cursor="Hand"/>
      </StackPanel>
    </Grid>
  </Border>
</Window>
'@

$mainXamlPath = Join-Path $PSScriptRoot 'FocusGuard.Main.xaml'
$reminderXamlPath = Join-Path $PSScriptRoot 'FocusGuard.Reminder.xaml'
[xml]$MainXaml = if (Test-Path -LiteralPath $mainXamlPath) {
    Get-Content -LiteralPath $mainXamlPath -Raw -Encoding UTF8
} else {
    $EmbeddedMainXaml.OuterXml
}
[xml]$ReminderXaml = if (Test-Path -LiteralPath $reminderXamlPath) {
    Get-Content -LiteralPath $reminderXamlPath -Raw -Encoding UTF8
} else {
    $EmbeddedReminderXaml.OuterXml
}

function Convert-XamlToWindow {
    param([xml]$Xaml)
    $reader = New-Object System.Xml.XmlNodeReader $Xaml
    return [Windows.Markup.XamlReader]::Load($reader)
}

function Find-Control {
    param($Root, [string]$Name)
    return $Root.FindName($Name)
}

function Get-ForegroundSnapshot {
    $handle = [FocusGuardNative]::GetForegroundWindow()
    if ($handle -eq [IntPtr]::Zero) {
        return [pscustomobject]@{ Handle = $handle; ProcessName = ''; Title = '' }
    }

    $builder = New-Object System.Text.StringBuilder 1024
    [void][FocusGuardNative]::GetWindowText($handle, $builder, $builder.Capacity)
    [uint32]$pidValue = 0
    [void][FocusGuardNative]::GetWindowThreadProcessId($handle, [ref]$pidValue)
    $processName = ''
    try { $processName = [Diagnostics.Process]::GetProcessById([int]$pidValue).ProcessName } catch { }

    return [pscustomobject]@{
        Handle = $handle
        ProcessName = $processName
        Title = $builder.ToString()
    }
}

function Split-RuleLines {
    param([AllowEmptyString()][string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return @() }
    return @($Text -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}

function Test-SnapshotAllowed {
    param(
        [string]$ProcessName,
        [string]$Title,
        [string[]]$AllowedApps,
        [string[]]$AllowedTitles,
        [string]$TaskName = ''
    )

    $processLower = $ProcessName.ToLowerInvariant()
    $titleLower = $Title.ToLowerInvariant()

    foreach ($app in $AllowedApps) {
        $normalized = $app.ToLowerInvariant().Trim()
        if ($normalized.EndsWith('.exe')) { $normalized = $normalized.Substring(0, $normalized.Length - 4) }
        if ($normalized -and $processLower -eq $normalized) { return $true }
    }

    foreach ($keyword in $AllowedTitles) {
        $normalized = $keyword.ToLowerInvariant().Trim()
        if ($normalized -and $titleLower.Contains($normalized)) { return $true }
    }

    $taskLower = $TaskName.Trim().ToLowerInvariant()
    if ($taskLower.Length -ge 2 -and $titleLower.Contains($taskLower)) { return $true }
    if ($AllowedApps.Count -eq 0 -and $AllowedTitles.Count -eq 0) { return $true }
    return $false
}

function Get-IntSetting {
    param($TextBox, [int]$Default, [int]$Minimum, [int]$Maximum)
    $value = 0
    if (-not [int]::TryParse($TextBox.Text.Trim(), [ref]$value)) { $value = $Default }
    return [Math]::Max($Minimum, [Math]::Min($Maximum, $value))
}

function New-ReminderCopy {
    param(
        [ValidateSet('idle', 'offtask')][string]$Reason,
        [ValidateSet('温和', '直接', '暴躁')][string]$Tone,
        [string]$Task,
        [System.Collections.Generic.HashSet[string]]$UsedKeys
    )

    if (-not $UsedKeys) {
        $UsedKeys = New-Object 'System.Collections.Generic.HashSet[string]'
    }
    if ([string]::IsNullOrWhiteSpace($Task)) { $Task = '你刚才定下的任务' }

    $openers = @(switch ($Tone) {
        '温和' { '先停一下。'; '轻轻把注意力收回来。'; '没关系，现在回来就好。'; '给自己一个重新开始的机会。'; '先做一次小小的重置。'; '注意力偶尔走远很正常。'; '我们慢一点，把方向找回来。'; '现在正好可以重新对焦。' }
        '暴躁' { '停，别继续跑偏。'; '注意力又溜走了。'; '这轮专注不是摆设。'; '先别给摸鱼找借口。'; '方向错了，马上拉回来。'; '该刹车了。'; '别让无关内容接管时间。'; '现在立刻重新对焦。' }
        default { '停一下。'; '把注意力拉回来。'; '现在重新对焦。'; '先确认当前方向。'; '别让这一分钟继续溜走。'; '回到计划。'; '这里需要一次注意力重置。'; '暂停无关动作。' }
    })
    $contexts = @(if ($Reason -eq 'idle') {
        '键鼠已经安静了一会儿。'; '系统检测到一段时间没有操作。'; '这一小段停顿已经有点久了。'; '当前任务暂时没有新的操作。'; '你似乎在原地停留了一会儿。'; '专注节奏刚刚中断了。'; '屏幕前已经安静了一段时间。'; '这轮任务暂时失去了动作。'
    } else {
        '当前窗口不在这轮计划里。'; '你刚才打开的内容不在允许范围。'; '注意力已经离开本轮目标。'; '当前应用和任务方向不一致。'; '刚才的窗口与计划无关。'; '专注范围外的内容正在占用时间。'; '你已经在无关窗口停留了一会儿。'; '当前去向偏离了本轮任务。'
    })
    $actions = @(
        "回到「$Task」，先完成最小的一步。",
        "现在切回「$Task」，连续做两分钟。",
        "关掉无关内容，继续「$Task」的下一步。",
        "把手放回任务上，从「$Task」最容易的部分继续。",
        "只做一个动作：回到「$Task」。",
        "先完成「$Task」里眼前这一小段。",
        "重新打开需要的内容，继续推进「$Task」。",
        "给「$Task」一个完整的五分钟，不再切换。"
    )
    $closers = @(switch ($Tone) {
        '温和' { '不用追求完美，继续就很好。'; '一次小小的返回也算进步。'; '慢慢来，但现在就开始。'; '把下一步做完就够了。'; '你仍然可以守住这一轮。'; '给自己一点耐心，也给任务一点行动。'; '重新开始永远不晚。'; '继续一点点，节奏会回来的。' }
        '暴躁' { '别犹豫，马上行动。'; '现在就切回去。'; '少想借口，先做。'; '把无关窗口关掉。'; '别再浪费下一分钟。'; '动作快一点。'; '这次直接做，不要拖。'; '回去，完成它。' }
        default { '现在执行。'; '先行动，再考虑其他事。'; '守住接下来的两分钟。'; '不要继续切换窗口。'; '完成下一步再休息。'; '让计划重新接管注意力。'; '从现在这一秒继续。'; '做完眼前一步。' }
    })

    $total = $openers.Count * $contexts.Count * $actions.Count * $closers.Count
    $start = Get-Random -Minimum 0 -Maximum $total
    for ($offset = 0; $offset -lt $total; $offset++) {
        $value = ($start + $offset) % $total
        $openerIndex = $value % $openers.Count
        $value = [Math]::Floor($value / $openers.Count)
        $contextIndex = $value % $contexts.Count
        $value = [Math]::Floor($value / $contexts.Count)
        $actionIndex = $value % $actions.Count
        $value = [Math]::Floor($value / $actions.Count)
        $closerIndex = $value % $closers.Count
        $key = "$Reason|$Tone|$openerIndex|$contextIndex|$actionIndex|$closerIndex"
        if (-not $UsedKeys.Contains($key)) {
            return [pscustomobject]@{
                Key = $key
                Text = "$($openers[$openerIndex]) $($contexts[$contextIndex]) $($actions[$actionIndex]) $($closers[$closerIndex])"
            }
        }
    }
    throw '48 小时提醒文案池已用尽'
}

function New-FocusGuardIcon {
    $bitmap = New-Object System.Drawing.Bitmap -ArgumentList 64, 64
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $graphics.Clear([System.Drawing.Color]::Transparent)

    $background = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 18, 92, 67))
    $ringPen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(255, 115, 222, 172)), 7
    $center = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 247, 255, 250))
    try {
        $graphics.FillEllipse($background, 2, 2, 60, 60)
        $graphics.DrawEllipse($ringPen, 16, 16, 32, 32)
        $graphics.FillEllipse($center, 26, 26, 12, 12)
        $handle = $bitmap.GetHicon()
        try {
            return ([System.Drawing.Icon]::FromHandle($handle).Clone())
        } finally {
            [void][FocusGuardNative]::DestroyIcon($handle)
        }
    } finally {
        $center.Dispose()
        $ringPen.Dispose()
        $background.Dispose()
        $graphics.Dispose()
        $bitmap.Dispose()
    }
}

if ($SelfTest) {
    $mainTest = Convert-XamlToWindow -Xaml $MainXaml
    $reminderTest = Convert-XamlToWindow -Xaml $ReminderXaml
    if (-not (Find-Control $mainTest 'StartButton')) { throw '主窗口缺少 StartButton' }
    if (-not (Find-Control $mainTest 'SessionProgress')) { throw '主窗口缺少 SessionProgress' }
    if (-not (Find-Control $mainTest 'Duration25Button')) { throw '主窗口缺少快捷时长按钮' }
    if (-not (Find-Control $mainTest 'ResetSettingsButton')) { throw '主窗口缺少推荐参数按钮' }
    if (-not (Find-Control $mainTest 'EndBreakButton')) { throw '主窗口缺少结束休息按钮' }
    if (-not (Find-Control $mainTest 'ExitButton')) { throw '主窗口缺少 ExitButton' }
    if (-not (Find-Control $reminderTest 'ReturnButton')) { throw '提醒窗口缺少 ReturnButton' }
    if (-not (Test-SnapshotAllowed -ProcessName 'code' -Title 'anything' -AllowedApps @('code.exe') -AllowedTitles @())) { throw '应用规则测试失败' }
    if (-not (Test-SnapshotAllowed -ProcessName 'chrome' -Title '课程 - Chrome' -AllowedApps @() -AllowedTitles @('课程'))) { throw '标题规则测试失败' }
    if (Test-SnapshotAllowed -ProcessName 'chrome' -Title '短视频 - Chrome' -AllowedApps @('code') -AllowedTitles @('课程')) { throw '跑偏规则测试失败' }
    if (Test-SnapshotAllowed -ProcessName 'powershell' -Title '无关脚本' -AllowedApps @('code') -AllowedTitles @('课程')) { throw 'PowerShell 不应被无条件放行' }
    $copyKeys = New-Object 'System.Collections.Generic.HashSet[string]'
    1..100 | ForEach-Object {
        $copy = New-ReminderCopy -Reason 'offtask' -Tone '直接' -Task '测试任务' -UsedKeys $copyKeys
        if (-not $copyKeys.Add($copy.Key)) { throw '提醒文案重复测试失败' }
    }
    $testIcon = New-FocusGuardIcon
    if (-not $testIcon) { throw '应用图标创建失败' }
    $testIcon.Dispose()
    $idle = [FocusGuardNative]::IdleSeconds()
    Write-Output "FocusGuard self-test passed. IdleSeconds=$([Math]::Round($idle, 1))"
    $mainTest.Close()
    $reminderTest.Close()
    exit 0
}

$showRequestEventName = 'Local' + [char]92 + 'FocusGuardCN_ShowWindow'
$createdNew = $false
$mutex = New-Object System.Threading.Mutex($true, 'Local\FocusGuardCN_SingleInstance', [ref]$createdNew)
if (-not $createdNew) {
    try {
        $existingShowEvent = [System.Threading.EventWaitHandle]::OpenExisting($showRequestEventName)
        [void]$existingShowEvent.Set()
        $existingShowEvent.Dispose()
    } catch {
        [System.Windows.MessageBox]::Show('专注守卫正在后台运行，请稍后再启动一次以恢复窗口。', '专注守卫') | Out-Null
    }
    exit 0
}

[void][FocusGuardNative]::SetCurrentProcessExplicitAppUserModelID('FocusGuardCN.Desktop')
$appIcon = New-FocusGuardIcon
$showRequestEvent = [System.Threading.EventWaitHandle]::new(
    $false,
    [System.Threading.EventResetMode]::AutoReset,
    $showRequestEventName
)

$settingsDirectory = Join-Path $env:APPDATA 'FocusGuardCN'
$settingsPath = Join-Path $settingsDirectory 'settings.json'
$logPath = Join-Path $settingsDirectory 'focusguard.log'
$reminderHistoryPath = Join-Path $settingsDirectory 'reminder-history.json'

function Write-AppLog {
    param([string]$Message)
    try {
        if (-not (Test-Path -LiteralPath $settingsDirectory)) {
            New-Item -ItemType Directory -Path $settingsDirectory -Force | Out-Null
        }
        $line = '{0:yyyy-MM-dd HH:mm:ss}  {1}' -f (Get-Date), $Message
        Add-Content -LiteralPath $logPath -Value $line -Encoding UTF8
    } catch { }
}

function Load-ReminderHistory {
    $script:ReminderHistory = @()
    if (-not (Test-Path -LiteralPath $reminderHistoryPath)) { return }
    try {
        $items = @(Get-Content -LiteralPath $reminderHistoryPath -Raw -Encoding UTF8 | ConvertFrom-Json)
        $cutoff = (Get-Date).AddDays(-2)
        $recent = New-Object System.Collections.ArrayList
        foreach ($item in $items) {
            try {
                if ([DateTime]$item.Timestamp -ge $cutoff -and $item.Key) {
                    [void]$recent.Add($item)
                }
            } catch { }
        }
        $script:ReminderHistory = @($recent)
    } catch {
        Write-AppLog "读取提醒历史失败：$($_.Exception.Message)"
    }
}

function Save-ReminderHistory {
    try {
        if (-not (Test-Path -LiteralPath $settingsDirectory)) {
            New-Item -ItemType Directory -Path $settingsDirectory -Force | Out-Null
        }
        @($script:ReminderHistory) | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $reminderHistoryPath -Encoding UTF8
    } catch {
        Write-AppLog "保存提醒历史失败：$($_.Exception.Message)"
    }
}

$window = Convert-XamlToWindow -Xaml $MainXaml
$window.Icon = [System.Windows.Interop.Imaging]::CreateBitmapSourceFromHIcon(
    $appIcon.Handle,
    [System.Windows.Int32Rect]::Empty,
    [System.Windows.Media.Imaging.BitmapSizeOptions]::FromEmptyOptions()
)
$window.Icon.Freeze()
$taskbarInfo = New-Object Windows.Shell.TaskbarItemInfo
$window.TaskbarItemInfo = $taskbarInfo

$TaskBox = Find-Control $window 'TaskBox'
$DurationBox = Find-Control $window 'DurationBox'
$IdleBox = Find-Control $window 'IdleBox'
$GraceBox = Find-Control $window 'GraceBox'
$ToneBox = Find-Control $window 'ToneBox'
$AllowedAppsBox = Find-Control $window 'AllowedAppsBox'
$AllowedTitlesBox = Find-Control $window 'AllowedTitlesBox'
$SoundCheck = Find-Control $window 'SoundCheck'
$AddCurrentAppButton = Find-Control $window 'AddCurrentAppButton'
$Duration25Button = Find-Control $window 'Duration25Button'
$Duration45Button = Find-Control $window 'Duration45Button'
$Duration60Button = Find-Control $window 'Duration60Button'
$ResetSettingsButton = Find-Control $window 'ResetSettingsButton'
$StatusBadgeContainer = Find-Control $window 'StatusBadgeContainer'
$StatusDot = Find-Control $window 'StatusDot'
$StatusBadge = Find-Control $window 'StatusBadge'
$PhaseLabel = Find-Control $window 'PhaseLabel'
$CurrentTaskLabel = Find-Control $window 'CurrentTaskLabel'
$CountdownLabel = Find-Control $window 'CountdownLabel'
$SessionProgress = Find-Control $window 'SessionProgress'
$MonitorLabel = Find-Control $window 'MonitorLabel'
$WindowLabel = Find-Control $window 'WindowLabel'
$ReminderCountLabel = Find-Control $window 'ReminderCountLabel'
$ReturnCountLabel = Find-Control $window 'ReturnCountLabel'
$FocusedTimeLabel = Find-Control $window 'FocusedTimeLabel'
$StartButton = Find-Control $window 'StartButton'
$PauseButton = Find-Control $window 'PauseButton'
$EndBreakButton = Find-Control $window 'EndBreakButton'
$StopButton = Find-Control $window 'StopButton'
$HideButton = Find-Control $window 'HideButton'
$ExitButton = Find-Control $window 'ExitButton'

$script:SessionRunning = $false
$script:IsPaused = $false
$script:PausedAt = $null
$script:BreakUntil = $null
$script:BreakStartedAt = $null
$script:EndTime = $null
$script:StartedAt = $null
$script:OffTaskSince = $null
$script:ReminderCooldownUntil = [DateTime]::MinValue
$script:ReminderCount = 0
$script:ReturnCount = 0
$script:TotalPausedSeconds = 0.0
$script:LastExternalSnapshot = $null
$script:PopupOpen = $false
$script:AllowExit = $false
$script:TrayHintShown = $false
$script:MainWindowHandle = [IntPtr]::Zero
$script:SessionDurationSeconds = 0.0
$script:PopupWindow = $null
$script:PopupWindowHandle = [IntPtr]::Zero
$script:SettingsLoaded = $false
$script:LastErrorMessage = ''
$script:ReminderHistory = @()

function Save-Settings {
    $tone = '直接'
    if ($ToneBox.SelectedItem) { $tone = $ToneBox.SelectedItem.Content.ToString() }
    $settings = [ordered]@{
        Task = $TaskBox.Text
        DurationMinutes = Get-IntSetting $DurationBox 45 1 480
        IdleSeconds = Get-IntSetting $IdleBox 180 30 3600
        GraceSeconds = Get-IntSetting $GraceBox 25 3 600
        Tone = $tone
        AllowedApps = $AllowedAppsBox.Text
        AllowedTitles = $AllowedTitlesBox.Text
        Sound = [bool]$SoundCheck.IsChecked
    }
    if (-not (Test-Path $settingsDirectory)) { New-Item -ItemType Directory -Path $settingsDirectory -Force | Out-Null }
    $settings | ConvertTo-Json | Set-Content -Path $settingsPath -Encoding UTF8
}

function Load-Settings {
    if (-not (Test-Path $settingsPath)) { return }
    try {
        $settings = Get-Content -Path $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($null -ne $settings.Task) { $TaskBox.Text = [string]$settings.Task }
        if ($null -ne $settings.DurationMinutes) { $DurationBox.Text = [string]$settings.DurationMinutes }
        if ($null -ne $settings.IdleSeconds) { $IdleBox.Text = [string]$settings.IdleSeconds }
        if ($null -ne $settings.GraceSeconds) { $GraceBox.Text = [string]$settings.GraceSeconds }
        if ($null -ne $settings.AllowedApps) { $AllowedAppsBox.Text = [string]$settings.AllowedApps }
        if ($null -ne $settings.AllowedTitles) { $AllowedTitlesBox.Text = [string]$settings.AllowedTitles }
        if ($null -ne $settings.Sound) { $SoundCheck.IsChecked = [bool]$settings.Sound }
        $toneIndex = switch ([string]$settings.Tone) { '温和' { 0 } '暴躁' { 2 } default { 1 } }
        $ToneBox.SelectedIndex = $toneIndex
    } catch {
        # 损坏的设置文件不会阻止应用启动。
    }
}

function Set-StatusVisual {
    param([string]$Text, [string]$Color)
    $StatusBadge.Text = $Text
    $StatusDot.Fill = New-Object Windows.Media.SolidColorBrush ([Windows.Media.ColorConverter]::ConvertFromString($Color))
    $palette = switch ($Text) {
        '正在守卫' { @('#DDF4E8', '#176B4D') }
        '已暂停' { @('#F8ECD4', '#8A621C') }
        '休息中' { @('#DDECF7', '#346A91') }
        '本轮完成' { @('#DDF4E8', '#176B4D') }
        default { @('#E7ECE8', '#53605A') }
    }
    $StatusBadgeContainer.Background = New-Object Windows.Media.SolidColorBrush ([Windows.Media.ColorConverter]::ConvertFromString($palette[0]))
    $StatusBadge.Foreground = New-Object Windows.Media.SolidColorBrush ([Windows.Media.ColorConverter]::ConvertFromString($palette[1]))
    if ($null -ne $notifyIcon) {
        try { $notifyIcon.Text = "专注守卫 · $Text" } catch { }
    }
}

function Sync-ActionState {
    $canPause = $script:SessionRunning -and -not $script:BreakUntil
    $PauseButton.IsEnabled = $canPause
    $EndBreakButton.Visibility = if ($script:SessionRunning -and $script:BreakUntil) { 'Visible' } else { 'Collapsed' }
    if ($pauseItem) {
        $pauseItem.Enabled = $canPause
        $pauseItem.Text = if ($script:IsPaused) { '继续专注' } else { '暂停专注' }
    }
    if ($endBreakItem) {
        $endBreakItem.Enabled = [bool]($script:SessionRunning -and $script:BreakUntil)
    }
}

function End-Break {
    if (-not $script:SessionRunning -or -not $script:BreakUntil) { return }
    $now = Get-Date
    if ($script:BreakStartedAt) {
        $breakSeconds = [Math]::Max(0, ($now - $script:BreakStartedAt).TotalSeconds)
        $script:TotalPausedSeconds += $breakSeconds
        $script:EndTime = $script:EndTime.AddSeconds($breakSeconds)
    }
    $script:BreakUntil = $null
    $script:BreakStartedAt = $null
    $script:OffTaskSince = $null
    $script:ReminderCooldownUntil = [DateTime]::MinValue
    $remaining = $script:EndTime - $now
    $CountdownLabel.Text = '{0:00}:{1:00}' -f [Math]::Floor($remaining.TotalMinutes), $remaining.Seconds
    $PhaseLabel.Text = '专注进行中'
    $MonitorLabel.Text = '休息已结束，监测已恢复'
    $taskbarInfo.ProgressState = [Windows.Shell.TaskbarItemProgressState]::Normal
    Set-StatusVisual '正在守卫' '#48C98B'
    Sync-ActionState
}

function Queue-SettingsSave {
    if (-not $script:SettingsLoaded) { return }
    $settingsSaveTimer.Stop()
    $settingsSaveTimer.Start()
}

function Restore-TrayIcon {
    try {
        if ($null -eq $notifyIcon) { return }
        $notifyIcon.Visible = $false
        $notifyIcon.Icon = $appIcon
        $notifyIcon.Text = "专注守卫 · $($StatusBadge.Text)"
        $notifyIcon.Visible = $true
    } catch {
        Write-AppLog "恢复托盘图标失败：$($_.Exception.Message)"
    }
}

function Get-AlertCopy {
    param([string]$Reason)
    $task = $TaskBox.Text.Trim()
    if (-not $task) { $task = '你刚才定下的任务' }
    $tone = if ($ToneBox.SelectedItem) { $ToneBox.SelectedItem.Content.ToString() } else { '直接' }
    $cutoff = (Get-Date).AddDays(-2)
    $recent = New-Object System.Collections.ArrayList
    $usedKeys = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($item in @($script:ReminderHistory)) {
        try {
            if ([DateTime]$item.Timestamp -ge $cutoff -and $item.Key) {
                [void]$recent.Add($item)
                [void]$usedKeys.Add([string]$item.Key)
            }
        } catch { }
    }
    $script:ReminderHistory = @($recent)
    $copy = New-ReminderCopy -Reason $Reason -Tone $tone -Task $task -UsedKeys $usedKeys
    $script:ReminderHistory += [pscustomobject]@{
        Timestamp = (Get-Date).ToString('o')
        Key = $copy.Key
        Text = $copy.Text
    }
    Save-ReminderHistory
    return $copy.Text
}

function Show-Reminder {
    param([string]$Reason, $Snapshot)
    if ($script:PopupOpen) { return }
    $script:PopupOpen = $true
    $script:ReminderCount++
    $ReminderCountLabel.Text = [string]$script:ReminderCount
    $script:ReminderCooldownUntil = (Get-Date).AddSeconds(60)

    if ([bool]$SoundCheck.IsChecked) { [System.Media.SystemSounds]::Exclamation.Play() }

    $popup = Convert-XamlToWindow -Xaml $ReminderXaml
    $script:PopupWindow = $popup
    $popup.Add_SourceInitialized({
        $script:PopupWindowHandle = (New-Object Windows.Interop.WindowInteropHelper($popup)).Handle
    })
    $AlertKicker = Find-Control $popup 'AlertKicker'
    $AlertTitle = Find-Control $popup 'AlertTitle'
    $AlertMessage = Find-Control $popup 'AlertMessage'
    $AlertContext = Find-Control $popup 'AlertContext'
    $BreakButton = Find-Control $popup 'BreakButton'
    $ReturnButton = Find-Control $popup 'ReturnButton'

    if ($Reason -eq 'idle') {
        $AlertKicker.Text = '喂，人还在吗？'
        $AlertTitle.Text = '别悄悄掉线。'
        $AlertContext.Text = "检测到 $([Math]::Floor([FocusGuardNative]::IdleSeconds())) 秒没有键鼠操作"
    } else {
        $AlertKicker.Text = '喂，注意力跑了'
        $AlertTitle.Text = '该回来了。'
        $contextTitle = if ($Snapshot.Title) { $Snapshot.Title } else { '无标题窗口' }
        $AlertContext.Text = "刚才在看：$contextTitle  ·  $($Snapshot.ProcessName)"
    }
    $AlertMessage.Text = Get-AlertCopy -Reason $Reason

    $popup.Add_ContentRendered({
        $popup.Activate() | Out-Null
        $popup.Focus() | Out-Null
    })
    $ReturnButton.Add_Click({
        $script:ReturnCount++
        $ReturnCountLabel.Text = [string]$script:ReturnCount
        $script:OffTaskSince = $null
        $popup.Close()
    })
    $BreakButton.Add_Click({
        $script:BreakStartedAt = Get-Date
        $script:BreakUntil = (Get-Date).AddMinutes(5)
        $script:OffTaskSince = $null
        $taskbarInfo.ProgressState = [Windows.Shell.TaskbarItemProgressState]::Paused
        Sync-ActionState
        $popup.Close()
    })
    $popup.Add_Closed({
        $script:PopupOpen = $false
        $script:PopupWindow = $null
        $script:PopupWindowHandle = [IntPtr]::Zero
    })
    [void]$popup.ShowDialog()
}

function Start-Session {
    $duration = Get-IntSetting $DurationBox 45 1 480
    $DurationBox.Text = [string]$duration
    $IdleBox.Text = [string](Get-IntSetting $IdleBox 180 30 3600)
    $GraceBox.Text = [string](Get-IntSetting $GraceBox 25 3 600)
    if ([string]::IsNullOrWhiteSpace($TaskBox.Text)) {
        $TaskBox.Text = '完成当前最重要的任务'
    }
    Save-Settings

    $script:SessionRunning = $true
    $script:IsPaused = $false
    $script:PausedAt = $null
    $script:BreakUntil = $null
    $script:BreakStartedAt = $null
    $script:StartedAt = Get-Date
    $script:EndTime = (Get-Date).AddMinutes($duration)
    $script:SessionDurationSeconds = $duration * 60.0
    $script:OffTaskSince = $null
    $script:ReminderCooldownUntil = [DateTime]::MinValue
    $script:ReminderCount = 0
    $script:ReturnCount = 0
    $script:TotalPausedSeconds = 0.0

    $ReminderCountLabel.Text = '0'
    $ReturnCountLabel.Text = '0'
    $FocusedTimeLabel.Text = '0 分钟'
    $CurrentTaskLabel.Text = $TaskBox.Text.Trim()
    $window.Title = "专注中 · $($TaskBox.Text.Trim())"
    $CountdownLabel.Text = '{0:00}:00' -f $duration
    $SessionProgress.Value = 0
    $taskbarInfo.ProgressValue = 0
    $taskbarInfo.ProgressState = [Windows.Shell.TaskbarItemProgressState]::Normal
    $TaskBox.IsEnabled = $false
    $DurationBox.IsEnabled = $false
    $Duration25Button.IsEnabled = $false
    $Duration45Button.IsEnabled = $false
    $Duration60Button.IsEnabled = $false
    $ResetSettingsButton.IsEnabled = $false
    $StartButton.IsEnabled = $false
    $StopButton.IsEnabled = $true
    $PauseButton.Content = '暂停'
    Sync-ActionState
    Set-StatusVisual '正在守卫' '#48C98B'
    $PhaseLabel.Text = '专注进行中'
    $MonitorLabel.Text = '监测已开启；跑偏超过宽限时间就会提醒'
}

function Pause-Session {
    if (-not $script:SessionRunning -or $script:BreakUntil) { return }
    if (-not $script:IsPaused) {
        $script:IsPaused = $true
        $script:PausedAt = Get-Date
        $PauseButton.Content = '继续'
        $PhaseLabel.Text = '已暂停'
        $MonitorLabel.Text = '暂停期间不会检测'
        $taskbarInfo.ProgressState = [Windows.Shell.TaskbarItemProgressState]::Paused
        Set-StatusVisual '已暂停' '#E2A93B'
        $script:OffTaskSince = $null
    } else {
        $pauseDuration = ((Get-Date) - $script:PausedAt).TotalSeconds
        $script:TotalPausedSeconds += $pauseDuration
        $script:EndTime = $script:EndTime.AddSeconds($pauseDuration)
        $script:IsPaused = $false
        $script:PausedAt = $null
        $PauseButton.Content = '暂停'
        $PhaseLabel.Text = '专注进行中'
        $MonitorLabel.Text = '监测已恢复'
        $taskbarInfo.ProgressState = [Windows.Shell.TaskbarItemProgressState]::Normal
        Set-StatusVisual '正在守卫' '#48C98B'
    }
    Sync-ActionState
}

function Stop-Session {
    param([bool]$Completed = $false)
    if (-not $script:SessionRunning) { return }
    $script:SessionRunning = $false
    $script:IsPaused = $false
    $script:BreakUntil = $null
    $script:BreakStartedAt = $null
    $script:OffTaskSince = $null
    $window.Title = '专注守卫'
    $TaskBox.IsEnabled = $true
    $DurationBox.IsEnabled = $true
    $Duration25Button.IsEnabled = $true
    $Duration45Button.IsEnabled = $true
    $Duration60Button.IsEnabled = $true
    $ResetSettingsButton.IsEnabled = $true
    $StartButton.IsEnabled = $true
    $StopButton.IsEnabled = $false
    $PauseButton.Content = '暂停'
    $taskbarInfo.ProgressState = [Windows.Shell.TaskbarItemProgressState]::None
    Sync-ActionState
    if ($Completed) {
        $CountdownLabel.Text = '完成'
        $SessionProgress.Value = 100
        $PhaseLabel.Text = '这轮守住了'
        $MonitorLabel.Text = '做得好。休息一下，或者开始下一轮。'
        Set-StatusVisual '本轮完成' '#48C98B'
        if ([bool]$SoundCheck.IsChecked) { [System.Media.SystemSounds]::Asterisk.Play() }
    } else {
        $CountdownLabel.Text = '{0:00}:00' -f (Get-IntSetting $DurationBox 45 1 480)
        $SessionProgress.Value = 0
        $PhaseLabel.Text = '本轮已结束'
        $MonitorLabel.Text = '设置好下一轮，随时重新开始'
        Set-StatusVisual '尚未开始' '#899087'
    }
    Save-Settings
}

function Show-MainWindow {
    $window.ShowInTaskbar = $true
    $window.Show()
    $window.WindowState = [Windows.WindowState]::Normal
    [void]$window.Activate()
}

function Update-Tick {
    if ($showRequestEvent.WaitOne(0)) { Show-MainWindow }
    $snapshot = Get-ForegroundSnapshot
    $isMainWindow = $script:MainWindowHandle -ne [IntPtr]::Zero -and $snapshot.Handle -eq $script:MainWindowHandle
    $isReminderWindow = $script:PopupWindowHandle -ne [IntPtr]::Zero -and $snapshot.Handle -eq $script:PopupWindowHandle
    $isOwnWindow = $isMainWindow -or $isReminderWindow
    if (-not $isOwnWindow -and $snapshot.Title) {
        $script:LastExternalSnapshot = $snapshot
    }

    if ($script:LastExternalSnapshot) {
        $displayTitle = if ($script:LastExternalSnapshot.Title) { $script:LastExternalSnapshot.Title } else { '无标题窗口' }
        $WindowLabel.Text = "$displayTitle  ·  $($script:LastExternalSnapshot.ProcessName)"
    }

    if (-not $script:SessionRunning) { return }

    $now = Get-Date
    if ($script:BreakUntil) {
        if ($now -lt $script:BreakUntil) {
            $remainingBreak = $script:BreakUntil - $now
            $CountdownLabel.Text = '{0:00}:{1:00}' -f [Math]::Floor($remainingBreak.TotalMinutes), $remainingBreak.Seconds
            $PhaseLabel.Text = '休息中'
            $MonitorLabel.Text = '休息结束后自动恢复监测'
            Set-StatusVisual '休息中' '#4F87B8'
            return
        }
        End-Break
    }

    if ($script:IsPaused) { return }

    $remaining = $script:EndTime - $now
    if ($remaining.TotalSeconds -le 0) {
        Stop-Session -Completed $true
        return
    }
    $CountdownLabel.Text = '{0:00}:{1:00}' -f [Math]::Floor($remaining.TotalMinutes), $remaining.Seconds
    $progress = [Math]::Min(100, [Math]::Max(0, (1 - ($remaining.TotalSeconds / $script:SessionDurationSeconds)) * 100))
    $SessionProgress.Value = $progress
    $taskbarInfo.ProgressValue = $progress / 100.0
    $focusedSeconds = [Math]::Max(0, ($now - $script:StartedAt).TotalSeconds - $script:TotalPausedSeconds)
    $FocusedTimeLabel.Text = "$([Math]::Floor($focusedSeconds / 60)) 分钟"

    if ($script:PopupOpen) { return }
    if ($now -lt $script:ReminderCooldownUntil) {
        $MonitorLabel.Text = '监测继续，保持专注'
        return
    }

    $idleThreshold = Get-IntSetting $IdleBox 180 30 3600
    $idleSeconds = [FocusGuardNative]::IdleSeconds()
    if ($idleSeconds -ge $idleThreshold) {
        Show-Reminder -Reason 'idle' -Snapshot $snapshot
        return
    }

    $allowedApps = @(Split-RuleLines $AllowedAppsBox.Text)
    $allowedTitles = @(Split-RuleLines $AllowedTitlesBox.Text)
    $allowed = $isOwnWindow -or (Test-SnapshotAllowed -ProcessName $snapshot.ProcessName -Title $snapshot.Title -AllowedApps $allowedApps -AllowedTitles $allowedTitles -TaskName $TaskBox.Text)

    if ($allowed) {
        $script:OffTaskSince = $null
        $MonitorLabel.Text = '在允许范围内，继续保持'
        return
    }

    if (-not $script:OffTaskSince) { $script:OffTaskSince = $now }
    $grace = Get-IntSetting $GraceBox 25 3 600
    $offSeconds = ($now - $script:OffTaskSince).TotalSeconds
    if ($offSeconds -ge $grace) {
        $MonitorLabel.Text = '检测到跑偏，正在提醒'
        Show-Reminder -Reason 'offtask' -Snapshot $snapshot
        return
    }
    $secondsUntilReminder = [Math]::Max(1, [Math]::Ceiling($grace - $offSeconds))
    $MonitorLabel.Text = "疑似跑偏：$secondsUntilReminder 秒后提醒"
}

Load-Settings
Load-ReminderHistory
$CountdownLabel.Text = '{0:00}:00' -f (Get-IntSetting $DurationBox 45 1 480)
$CurrentTaskLabel.Text = if ($TaskBox.Text.Trim()) { $TaskBox.Text.Trim() } else { '先写下这次要完成的事' }

$timer = New-Object Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromSeconds(1)
$timer.Add_Tick({
    try { Update-Tick } catch {
        $MonitorLabel.Text = '监测暂时遇到问题，下一秒会自动重试'
        $message = $_.Exception.Message
        if ($message -ne $script:LastErrorMessage) {
            $script:LastErrorMessage = $message
            Write-AppLog "监测错误：$message"
        }
    }
})
$timer.Start()

$settingsSaveTimer = New-Object Windows.Threading.DispatcherTimer
$settingsSaveTimer.Interval = [TimeSpan]::FromMilliseconds(800)
$settingsSaveTimer.Add_Tick({
    $settingsSaveTimer.Stop()
    try { Save-Settings } catch { Write-AppLog "保存设置失败：$($_.Exception.Message)" }
})
$script:SettingsLoaded = $true

$notifyIcon = New-Object System.Windows.Forms.NotifyIcon
$notifyIcon.Icon = $appIcon
$notifyIcon.Text = '专注守卫 · 准备就绪'
$notifyIcon.Visible = $true
$trayMenu = New-Object System.Windows.Forms.ContextMenuStrip
$openItem = $trayMenu.Items.Add('打开专注守卫')
$pauseItem = $trayMenu.Items.Add('暂停专注')
$pauseItem.Enabled = $false
$endBreakItem = $trayMenu.Items.Add('结束休息')
$endBreakItem.Enabled = $false
[void]$trayMenu.Items.Add('-')
$quitItem = $trayMenu.Items.Add('退出')
$notifyIcon.ContextMenuStrip = $trayMenu

$trayRecoveryWindow = New-Object FocusGuardTrayRecoveryWindow
$trayRecoveryWindow.Add_TaskbarCreated({
    Restore-TrayIcon
    Write-AppLog '检测到 Windows 资源管理器重启，已重新注册托盘图标'
})

$trayHealthTimer = New-Object Windows.Threading.DispatcherTimer
$trayHealthTimer.Interval = [TimeSpan]::FromSeconds(20)
$trayHealthTimer.Add_Tick({
    try {
        if (-not $notifyIcon.Visible) { Restore-TrayIcon }
    } catch {
        Write-AppLog "托盘状态检查失败：$($_.Exception.Message)"
    }
})
$trayHealthTimer.Start()

$dispatcher = [Windows.Threading.Dispatcher]::CurrentDispatcher
$dispatcher.Add_UnhandledException({
    param($sender, $eventArgs)
    $message = $eventArgs.Exception.Message
    Write-AppLog "界面未捕获异常：$message"
    try {
        Restore-TrayIcon
        $MonitorLabel.Text = '刚才遇到一个问题，程序已自动恢复'
    } catch { }
    $eventArgs.Handled = $true
})

$showWindow = { Show-MainWindow }
$openItem.Add_Click($showWindow)
$notifyIcon.Add_DoubleClick($showWindow)
$notifyIcon.Add_BalloonTipClicked($showWindow)
$pauseItem.Add_Click({ Pause-Session })
$endBreakItem.Add_Click({ End-Break })

function Exit-Application {
    $script:AllowExit = $true
    if ($script:PopupWindow) { $script:PopupWindow.Close() }
    $window.Close()
}

$quitItem.Add_Click({ Exit-Application })

$StartButton.Add_Click({
    try {
        Start-Session
    } catch {
        $message = $_.Exception.Message
        Write-AppLog "开始专注失败：$message"
        $script:SessionRunning = $false
        $script:IsPaused = $false
        $StartButton.IsEnabled = $true
        $PauseButton.IsEnabled = $false
        $StopButton.IsEnabled = $false
        $TaskBox.IsEnabled = $true
        $DurationBox.IsEnabled = $true
        $Duration25Button.IsEnabled = $true
        $Duration45Button.IsEnabled = $true
        $Duration60Button.IsEnabled = $true
        $ResetSettingsButton.IsEnabled = $true
        $PhaseLabel.Text = '启动失败'
        $MonitorLabel.Text = "无法开始：$message"
        $StatusBadge.Text = '启动失败'
    }
})
$PauseButton.Add_Click({ Pause-Session })
$EndBreakButton.Add_Click({ End-Break })
$StopButton.Add_Click({ Stop-Session -Completed $false })
$HideButton.Add_Click({
    $window.ShowInTaskbar = $true
    $window.WindowState = [Windows.WindowState]::Minimized
})
$ExitButton.Add_Click({ Exit-Application })
$AddCurrentAppButton.Add_Click({
    if (-not $script:LastExternalSnapshot -or -not $script:LastExternalSnapshot.ProcessName) {
        [System.Windows.MessageBox]::Show('还没有检测到其他应用。先切换到要允许的应用，再回来点击。', '专注守卫') | Out-Null
        return
    }
    $items = @(Split-RuleLines $AllowedAppsBox.Text)
    $process = $script:LastExternalSnapshot.ProcessName
    if ($process -notin $items) {
        $AllowedAppsBox.Text = (($items + $process) -join "`r`n")
        Save-Settings
    }
})
$Duration25Button.Add_Click({
    if (-not $script:SessionRunning) { $DurationBox.Text = '25' }
})
$Duration45Button.Add_Click({
    if (-not $script:SessionRunning) { $DurationBox.Text = '45' }
})
$Duration60Button.Add_Click({
    if (-not $script:SessionRunning) { $DurationBox.Text = '60' }
})
$ResetSettingsButton.Add_Click({
    if ($script:SessionRunning) { return }
    $DurationBox.Text = '45'
    $IdleBox.Text = '180'
    $GraceBox.Text = '25'
    $ToneBox.SelectedIndex = 1
    $SoundCheck.IsChecked = $true
    $MonitorLabel.Text = '已恢复推荐参数'
    Queue-SettingsSave
})
$DurationBox.Add_TextChanged({
    if (-not $script:SessionRunning) {
        $CountdownLabel.Text = '{0:00}:00' -f (Get-IntSetting $DurationBox 45 1 480)
    }
    Queue-SettingsSave
})
$DurationBox.Add_LostFocus({
    if (-not $script:SessionRunning) {
        $DurationBox.Text = [string](Get-IntSetting $DurationBox 45 1 480)
    }
})
$TaskBox.Add_TextChanged({
    if (-not $script:SessionRunning) {
        $CurrentTaskLabel.Text = if ($TaskBox.Text.Trim()) { $TaskBox.Text.Trim() } else { '先写下这次要完成的事' }
    }
    Queue-SettingsSave
})
$IdleBox.Add_TextChanged({ Queue-SettingsSave })
$GraceBox.Add_TextChanged({ Queue-SettingsSave })
$AllowedAppsBox.Add_TextChanged({ Queue-SettingsSave })
$AllowedTitlesBox.Add_TextChanged({ Queue-SettingsSave })
$ToneBox.Add_SelectionChanged({ Queue-SettingsSave })
$SoundCheck.Add_Click({ Queue-SettingsSave })
$IdleBox.Add_LostFocus({ $IdleBox.Text = [string](Get-IntSetting $IdleBox 180 30 3600) })
$GraceBox.Add_LostFocus({ $GraceBox.Text = [string](Get-IntSetting $GraceBox 25 3 600) })

$window.Add_SourceInitialized({
    $script:MainWindowHandle = (New-Object Windows.Interop.WindowInteropHelper($window)).Handle
})
$window.Add_Closing({
    param($sender, $eventArgs)
    Save-Settings
    $timer.Stop()
    $settingsSaveTimer.Stop()
    $trayHealthTimer.Stop()
    if ($script:PopupWindow) { $script:PopupWindow.Close() }
    $notifyIcon.Visible = $false
    $notifyIcon.Dispose()
    $trayRecoveryWindow.Dispose()
    $appIcon.Dispose()
    $showRequestEvent.Dispose()
    if ($mutex) { $mutex.ReleaseMutex(); $mutex.Dispose() }
})

[void]$window.ShowDialog()
