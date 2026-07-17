# --- 启动初始化：单实例互斥、进程身份、应用图标、数据文件路径（必须先于窗口创建） ---
$showRequestEventName = 'Local' + [char]92 + 'FocusGuardCN_ShowWindow'
$createdNew = $false
$mutex = New-Object System.Threading.Mutex($true, 'Local\FocusGuardCN_SingleInstance', [ref]$createdNew)
if (-not $createdNew) {
    if (-not $StartMinimized) {
        try {
            $existingShowEvent = [System.Threading.EventWaitHandle]::OpenExisting($showRequestEventName)
            [void]$existingShowEvent.Set()
            $existingShowEvent.Dispose()
        } catch {
            [System.Windows.MessageBox]::Show('专注守卫正在后台运行，请稍后再启动一次以恢复窗口。', '专注守卫') | Out-Null
        }
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
$sessionHistoryPath = Join-Path $settingsDirectory 'session-history.json'

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
        $parsed = Get-Content -LiteralPath $reminderHistoryPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $items = @($parsed)
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
        ConvertTo-Json -InputObject @($script:ReminderHistory) -Depth 4 | Set-Content -LiteralPath $reminderHistoryPath -Encoding UTF8
    } catch {
        Write-AppLog "保存提醒历史失败：$($_.Exception.Message)"
    }
}

function Load-SessionHistory {
    $script:SessionHistory = @()
    $script:LastSessionEvaluation = $null
    if (-not (Test-Path -LiteralPath $sessionHistoryPath)) { return }
    try {
        $parsed = Get-Content -LiteralPath $sessionHistoryPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $items = @($parsed)
        $valid = New-Object System.Collections.ArrayList
        $migrationNeeded = $false
        foreach ($item in $items) {
            if ($null -ne $item -and $null -ne $item.Score -and $item.Timestamp) {
                if ($null -eq $item.PSObject.Properties['ReviewedAt']) {
                    $item | Add-Member -NotePropertyName ReviewedAt -NotePropertyValue ''
                    $migrationNeeded = $true
                }
                [void]$valid.Add($item)
            }
        }
        $script:SessionHistory = if ($valid.Count -gt 100) { @($valid | Select-Object -Last 100) } else { @($valid) }
        if ($script:SessionHistory.Count -gt 0) {
            $script:LastSessionEvaluation = $script:SessionHistory[-1]
        }
        if ($migrationNeeded) { Save-SessionHistory }
    } catch {
        Write-AppLog "读取专注评分历史失败：$($_.Exception.Message)"
    }
}

function Save-SessionHistory {
    try {
        if (-not (Test-Path -LiteralPath $settingsDirectory)) {
            New-Item -ItemType Directory -Path $settingsDirectory -Force | Out-Null
        }
        ConvertTo-Json -InputObject @($script:SessionHistory) -Depth 6 |
            Set-Content -LiteralPath $sessionHistoryPath -Encoding UTF8
    } catch {
        Write-AppLog "保存专注评分历史失败：$($_.Exception.Message)"
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
$window.Title = "专注守卫 v$script:FocusGuardVersion"

$TaskBox = Find-Control $window 'TaskBox'
$DurationBox = Find-Control $window 'DurationBox'
$IdleBox = Find-Control $window 'IdleBox'
$GraceBox = Find-Control $window 'GraceBox'
$ToneBox = Find-Control $window 'ToneBox'
$AllowedAppsList = Find-Control $window 'AllowedAppsList'
$AllowedTitlesList = Find-Control $window 'AllowedTitlesList'
$AllowedAppInput = Find-Control $window 'AllowedAppInput'
$AllowedTitleInput = Find-Control $window 'AllowedTitleInput'
$AddAllowedAppButton = Find-Control $window 'AddAllowedAppButton'
$AddAllowedTitleButton = Find-Control $window 'AddAllowedTitleButton'
$RemoveAllowedAppButton = Find-Control $window 'RemoveAllowedAppButton'
$RemoveAllowedTitleButton = Find-Control $window 'RemoveAllowedTitleButton'
$AllowedAppsCountLabel = Find-Control $window 'AllowedAppsCountLabel'
$AllowedTitlesCountLabel = Find-Control $window 'AllowedTitlesCountLabel'
$SoundCheck = Find-Control $window 'SoundCheck'
$AddCurrentAppButton = Find-Control $window 'AddCurrentAppButton'
$StartWithWindowsCheck = Find-Control $window 'StartWithWindowsCheck'
$StartWithWindowsStatusLabel = Find-Control $window 'StartWithWindowsStatusLabel'
$ResetLayoutButton = Find-Control $window 'ResetLayoutButton'
$SettingsColumn = Find-Control $window 'SettingsColumn'
$MainPaneSplitter = Find-Control $window 'MainPaneSplitter'
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
$HistoryButton = Find-Control $window 'HistoryButton'
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
$script:SessionHistory = @()
$script:LastSessionEvaluation = $null
$script:SessionLastSampleAt = $null
$script:SessionActivityState = 'untracked'
$script:SessionOnTaskSeconds = 0.0
$script:SessionOffTaskSeconds = 0.0
$script:SessionIdleSeconds = 0.0
$script:SessionRecoveryCount = 0
$script:SessionPauseCount = 0
$script:SessionBreakCount = 0
$script:CurrentSessionTask = ''
$script:PendingReviewShown = $false
$script:AutoStartChangeInternal = $false
$script:HistoryWindowWidth = 1280.0
$script:HistoryWindowHeight = 960.0
$script:HistoryInsightWidth = 380.0

function Update-RuleCountLabels {
    $AllowedAppsCountLabel.Text = "$( @(Get-RuleItems $AllowedAppsList).Count ) 个应用"
    $AllowedTitlesCountLabel.Text = "$( @(Get-RuleItems $AllowedTitlesList).Count ) 个关键词"
}

function Save-Settings {
    $tone = '直接'
    if ($ToneBox.SelectedItem) { $tone = $ToneBox.SelectedItem.Content.ToString() }
    $bounds = if ($window.WindowState -eq [Windows.WindowState]::Normal) {
        [pscustomobject]@{ Width = $window.ActualWidth; Height = $window.ActualHeight }
    } else {
        $window.RestoreBounds
    }
    $settings = [ordered]@{
        LayoutRevision = 3
        HistoryLayoutRevision = 2
        Task = $TaskBox.Text
        DurationMinutes = Get-IntSetting $DurationBox 45 1 480
        IdleSeconds = Get-IntSetting $IdleBox 180 30 3600
        GraceSeconds = Get-IntSetting $GraceBox 25 3 600
        Tone = $tone
        AllowedApps = (@(Get-RuleItems $AllowedAppsList) -join "`r`n")
        AllowedTitles = (@(Get-RuleItems $AllowedTitlesList) -join "`r`n")
        Sound = [bool]$SoundCheck.IsChecked
        StartWithWindows = [bool]$StartWithWindowsCheck.IsChecked
        MainWindowWidth = [Math]::Round([Math]::Max(1180.0, [Math]::Min(2200.0, [double]$bounds.Width)))
        MainWindowHeight = [Math]::Round([Math]::Max(760.0, [Math]::Min(1300.0, [double]$bounds.Height)))
        SettingsPanelWidth = [Math]::Round([Math]::Max(440.0, [Math]::Min(720.0, [double]$SettingsColumn.ActualWidth)))
        HistoryWindowWidth = [Math]::Round([Math]::Max(1040.0, [Math]::Min(2200.0, $script:HistoryWindowWidth)))
        HistoryWindowHeight = [Math]::Round([Math]::Max(800.0, [Math]::Min(1300.0, $script:HistoryWindowHeight)))
        HistoryInsightWidth = [Math]::Round([Math]::Max(320.0, [Math]::Min(520.0, $script:HistoryInsightWidth)))
    }
    if (-not (Test-Path $settingsDirectory)) { New-Item -ItemType Directory -Path $settingsDirectory -Force | Out-Null }
    $settings | ConvertTo-Json | Set-Content -Path $settingsPath -Encoding UTF8
}

function Load-Settings {
    Set-RuleItems $AllowedAppsList @('code', 'winword', 'excel', 'powerpnt', 'notepad', 'obsidian')
    Set-RuleItems $AllowedTitlesList @('Codex', 'Visual Studio Code', 'Microsoft Word', 'Excel', 'PowerPoint', 'Notion', '学习', '工作', '课程', '文档')
    try {
        if (Test-Path $settingsPath) {
            $settings = Get-Content -Path $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($null -ne $settings.Task) { $TaskBox.Text = [string]$settings.Task }
            if ($null -ne $settings.DurationMinutes) { $DurationBox.Text = [string]$settings.DurationMinutes }
            if ($null -ne $settings.IdleSeconds) { $IdleBox.Text = [string]$settings.IdleSeconds }
            if ($null -ne $settings.GraceSeconds) { $GraceBox.Text = [string]$settings.GraceSeconds }
            if ($null -ne $settings.AllowedApps) { Set-RuleItems $AllowedAppsList @(Split-RuleLines ([string]$settings.AllowedApps)) }
            if ($null -ne $settings.AllowedTitles) { Set-RuleItems $AllowedTitlesList @(Split-RuleLines ([string]$settings.AllowedTitles)) }
            if ($null -ne $settings.Sound) { $SoundCheck.IsChecked = [bool]$settings.Sound }
            $toneIndex = switch ([string]$settings.Tone) { '温和' { 0 } '暴躁' { 2 } default { 1 } }
            $ToneBox.SelectedIndex = $toneIndex
            $layoutRevision = [int](Get-ObjectPropertyValue $settings 'LayoutRevision' 0)
            $mainWidth = Get-ObjectPropertyValue $settings 'MainWindowWidth' $null
            $mainHeight = Get-ObjectPropertyValue $settings 'MainWindowHeight' $null
            $settingsWidth = Get-ObjectPropertyValue $settings 'SettingsPanelWidth' $null
            $historyWidth = Get-ObjectPropertyValue $settings 'HistoryWindowWidth' $null
            $historyHeight = Get-ObjectPropertyValue $settings 'HistoryWindowHeight' $null
            $historyInsightWidth = Get-ObjectPropertyValue $settings 'HistoryInsightWidth' $null
            $historyLayoutRevision = [int](Get-ObjectPropertyValue $settings 'HistoryLayoutRevision' 0)
            if ($layoutRevision -lt 3) {
                $window.Width = 1440; $window.Height = 920
                $SettingsColumn.Width = New-Object Windows.GridLength 560
                $script:HistoryWindowWidth = 1280; $script:HistoryWindowHeight = 960; $script:HistoryInsightWidth = 380
            } else {
                if ($null -ne $mainWidth) { $window.Width = [Math]::Max(1180.0, [Math]::Min(2200.0, [double]$mainWidth)) }
                if ($null -ne $mainHeight) { $window.Height = [Math]::Max(760.0, [Math]::Min(1300.0, [double]$mainHeight)) }
                if ($null -ne $settingsWidth) { $SettingsColumn.Width = New-Object Windows.GridLength ([Math]::Max(440.0, [Math]::Min(720.0, [double]$settingsWidth))) }
                if ($null -ne $historyWidth) { $script:HistoryWindowWidth = [Math]::Max(1040.0, [Math]::Min(2200.0, [double]$historyWidth)) }
                if ($null -ne $historyHeight) { $script:HistoryWindowHeight = [Math]::Max(800.0, [Math]::Min(1300.0, [double]$historyHeight)) }
                if ($null -ne $historyInsightWidth) { $script:HistoryInsightWidth = [Math]::Max(320.0, [Math]::Min(520.0, [double]$historyInsightWidth)) }
            }
            if ($historyLayoutRevision -lt 2) { $script:HistoryWindowWidth = 1280; $script:HistoryWindowHeight = 960; $script:HistoryInsightWidth = 380 }
        }
    } catch {
        # 损坏的设置文件不会阻止应用启动。
    }
    Update-RuleCountLabels
    $script:AutoStartChangeInternal = $true
    $autoStartEnabled = Get-AutoStartEnabled
    $StartWithWindowsCheck.IsChecked = $autoStartEnabled
    $StartWithWindowsStatusLabel.Text = if ($autoStartEnabled) { '已启用 · 下次登录后最小化运行' } else { '当前未启用' }
    $script:AutoStartChangeInternal = $false
    if ($autoStartEnabled) {
        try { Set-AutoStartEnabled $true } catch { Write-AppLog "刷新开机启动项失败：$($_.Exception.Message)" }
    }
}

function Set-StatusVisual {
    param([string]$Text, [string]$Color)
    $StatusBadge.Text = $Text
    $palette = switch ($Text) {
        '正在守卫' { @('#DDF4E8', '#176B4D') }
        '已暂停' { @('#F8ECD4', '#8A621C') }
        '休息中' { @('#DDECF7', '#346A91') }
        '本轮完成' { @('#DDF4E8', '#176B4D') }
        default { @('#E7ECE8', '#53605A') }
    }
    Set-BrushColorAnimated $StatusDot.Fill $Color
    Set-BrushColorAnimated $StatusBadgeContainer.Background $palette[0]
    Set-BrushColorAnimated $StatusBadge.Foreground $palette[1]
    if ($null -ne $notifyIcon) {
        try { $notifyIcon.Text = "专注守卫 · $Text" } catch { }
    }
}

function Add-SessionSample {
    param(
        [DateTime]$Timestamp,
        [ValidateSet('ontask', 'offtask', 'idle')][string]$ActivityState
    )
    if ($null -eq $script:SessionLastSampleAt) {
        $script:SessionLastSampleAt = $Timestamp
        $script:SessionActivityState = $ActivityState
        return
    }
    # DispatcherTimer 偶尔会因系统忙碌而晚到；单次最多计 3 秒，避免休眠/唤醒污染评分。
    $seconds = [Math]::Max(0.0, [Math]::Min(3.0, ($Timestamp - $script:SessionLastSampleAt).TotalSeconds))
    $script:SessionLastSampleAt = $Timestamp
    switch ($ActivityState) {
        'ontask' { $script:SessionOnTaskSeconds += $seconds }
        'offtask' { $script:SessionOffTaskSeconds += $seconds }
        'idle' { $script:SessionIdleSeconds += $seconds }
    }
    if ($ActivityState -eq 'ontask' -and $script:SessionActivityState -in @('offtask', 'idle')) {
        $script:SessionRecoveryCount++
    }
    $script:SessionActivityState = $ActivityState
}

function Register-SessionEvaluation {
    param(
        $Evaluation,
        [DateTime]$EndedAt,
        [bool]$Completed,
        [double]$ActiveElapsedSeconds,
        [double]$PausedSeconds
    )
    $record = [pscustomobject][ordered]@{
        Timestamp = $EndedAt.ToString('o')
        StartedAt = $script:StartedAt.ToString('o')
        Task = $script:CurrentSessionTask
        Completed = $Completed
        PlannedSeconds = $script:SessionDurationSeconds
        ActiveElapsedSeconds = [Math]::Round($ActiveElapsedSeconds, 1)
        OnTaskSeconds = [Math]::Round($script:SessionOnTaskSeconds, 1)
        OffTaskSeconds = [Math]::Round($script:SessionOffTaskSeconds, 1)
        IdleSeconds = [Math]::Round($script:SessionIdleSeconds, 1)
        ReminderCount = $script:ReminderCount
        ReturnCount = $script:ReturnCount
        RecoveryCount = $script:SessionRecoveryCount
        PauseCount = $script:SessionPauseCount
        BreakCount = $script:SessionBreakCount
        PausedSeconds = [Math]::Round($PausedSeconds, 1)
        Score = $Evaluation.Score
        Grade = $Evaluation.Grade
        Verdict = $Evaluation.Verdict
        QualityPoints = $Evaluation.QualityPoints
        CompletionPoints = $Evaluation.CompletionPoints
        RecoveryPoints = $Evaluation.RecoveryPoints
        RhythmPoints = $Evaluation.RhythmPoints
        FocusPercent = $Evaluation.FocusPercent
        ProgressPercent = $Evaluation.ProgressPercent
        RecoveryPercent = $Evaluation.RecoveryPercent
        OnTaskMinutes = $Evaluation.OnTaskMinutes
        OffTaskMinutes = $Evaluation.OffTaskMinutes
        IdleMinutes = $Evaluation.IdleMinutes
        ActiveMinutes = $Evaluation.ActiveMinutes
        PausedMinutes = $Evaluation.PausedMinutes
        Metrics = $Evaluation.Metrics
        Analysis = $Evaluation.Analysis
        Suggestion = $Evaluation.Suggestion
        KeyInsight = $Evaluation.KeyInsight
        Evidence = $Evaluation.Evidence
        NextAction = $Evaluation.NextAction
        TellOff = $Evaluation.TellOff
        ReviewedAt = ''
    }
    $script:SessionHistory += $record
    if ($script:SessionHistory.Count -gt 100) {
        $script:SessionHistory = @($script:SessionHistory | Select-Object -Last 100)
    }
    $script:LastSessionEvaluation = $record
    Save-SessionHistory
    if ($null -ne $HistoryButton) { $HistoryButton.IsEnabled = $true }
    return $record
}

function Show-SessionSummary {
    param(
        $Evaluation,
        [bool]$RequireReview = $false,
        $OwnerWindow = $null
    )
    if ($null -eq $Evaluation) { return }
    if ($null -eq $SummaryXaml) {
        $fallback = "$($Evaluation.Score) 分 · $($Evaluation.Grade)`r`n`r`n$($Evaluation.Analysis)`r`n`r`n下一轮建议：$($Evaluation.Suggestion)"
        if ($Evaluation.TellOff) { $fallback += "`r`n`r`n没到满分，听一句：$($Evaluation.TellOff)" }
        [System.Windows.MessageBox]::Show($fallback, '本轮专注分析') | Out-Null
        return
    }

    $summary = Convert-XamlToWindow -Xaml $SummaryXaml
    $summary.Owner = if ($null -ne $OwnerWindow) { $OwnerWindow } else { $window }
    $summary.Icon = $window.Icon
    $ScoreAccentBorder = Find-Control $summary 'ScoreAccentBorder'
    $ScoreLabel = Find-Control $summary 'ScoreLabel'
    $GradeLabel = Find-Control $summary 'GradeLabel'
    $VerdictLabel = Find-Control $summary 'VerdictLabel'
    $QualityScoreLabel = Find-Control $summary 'QualityScoreLabel'
    $CompletionScoreLabel = Find-Control $summary 'CompletionScoreLabel'
    $RecoveryScoreLabel = Find-Control $summary 'RecoveryScoreLabel'
    $RhythmScoreLabel = Find-Control $summary 'RhythmScoreLabel'
    $MetricsLabel = Find-Control $summary 'MetricsLabel'
    $AnalysisLabel = Find-Control $summary 'AnalysisLabel'
    $SuggestionLabel = Find-Control $summary 'SuggestionLabel'
    $KeyInsightLabel = Find-Control $summary 'KeyInsightLabel'
    $EvidenceLabel = Find-Control $summary 'EvidenceLabel'
    $TellOffCard = Find-Control $summary 'TellOffCard'
    $TellOffLabel = Find-Control $summary 'TellOffLabel'
    $ReviewGateCard = Find-Control $summary 'ReviewGateCard'
    $ReviewAcknowledgeCheck = Find-Control $summary 'ReviewAcknowledgeCheck'
    $ReviewGateHint = Find-Control $summary 'ReviewGateHint'
    $SessionMetaLabel = Find-Control $summary 'SessionMetaLabel'
    $CloseSummaryButton = Find-Control $summary 'CloseSummaryButton'

    $ScoreLabel.Text = '0'
    $GradeLabel.Text = [string]$Evaluation.Grade
    $VerdictLabel.Text = [string]$Evaluation.Verdict
    $QualityScoreLabel.Text = "$($Evaluation.QualityPoints) / 50"
    $CompletionScoreLabel.Text = "$($Evaluation.CompletionPoints) / 30"
    $RecoveryScoreLabel.Text = "$($Evaluation.RecoveryPoints) / 10"
    $RhythmScoreLabel.Text = "$($Evaluation.RhythmPoints) / 10"
    $MetricsLabel.Text = [string]$Evaluation.Metrics
    $AnalysisLabel.Text = [string]$Evaluation.Analysis
    $SuggestionLabel.Text = [string]$Evaluation.Suggestion
    $keyInsight = [string](Get-ObjectPropertyValue $Evaluation 'KeyInsight' (Get-ObjectPropertyValue $Evaluation 'Verdict' '这一轮已经记录。'))
    $evidence = [string](Get-ObjectPropertyValue $Evaluation 'Evidence' (Get-ObjectPropertyValue $Evaluation 'Metrics' '暂无更多数据。'))
    $KeyInsightLabel.Text = $keyInsight
    $EvidenceLabel.Text = $evidence
    if ([int]$Evaluation.Score -eq 100) {
        $TellOffCard.Visibility = 'Collapsed'
    } else {
        $TellOffCard.Visibility = 'Visible'
        $TellOffLabel.Text = [string]$Evaluation.TellOff
    }
    $displayTime = [string]$Evaluation.Timestamp
    try { $displayTime = ([DateTime]$Evaluation.Timestamp).ToString('yyyy-MM-dd HH:mm') } catch { }
    $SessionMetaLabel.Text = "$displayTime · $($Evaluation.Task)"

    $palette = if ([int]$Evaluation.Score -ge 90) {
        @('#DDF4E8', '#176B4D')
    } elseif ([int]$Evaluation.Score -ge 70) {
        @('#FFF3D8', '#8A621C')
    } else {
        @('#FCE6DE', '#9A4834')
    }
    $ScoreAccentBorder.Background = New-Object Windows.Media.SolidColorBrush ([Windows.Media.ColorConverter]::ConvertFromString($palette[0]))
    $ScoreLabel.Foreground = New-Object Windows.Media.SolidColorBrush ([Windows.Media.ColorConverter]::ConvertFromString($palette[1]))

    $reviewNeeded = $RequireReview -and [int]$Evaluation.Score -lt 100
    if ($reviewNeeded) {
        $ReviewGateCard.Visibility = 'Visible'
        $ReviewAcknowledgeCheck.IsChecked = $false
        $CloseSummaryButton.IsEnabled = $false
        $CloseSummaryButton.Content = '先完成复盘确认'
        $ReviewAcknowledgeCheck.Add_Checked({
            $CloseSummaryButton.IsEnabled = $true
            $CloseSummaryButton.Content = '确认已复盘'
            $ReviewGateHint.Text = '已确认；关闭后会写入本机历史档案'
        })
        $ReviewAcknowledgeCheck.Add_Unchecked({
            $CloseSummaryButton.IsEnabled = $false
            $CloseSummaryButton.Content = '先完成复盘确认'
            $ReviewGateHint.Text = '勾选后才能结束本次复盘'
        })
    } else {
        $ReviewGateCard.Visibility = 'Collapsed'
        $CloseSummaryButton.IsEnabled = $true
        $CloseSummaryButton.Content = if ([int]$Evaluation.Score -eq 100) { '收下满分' } else { '关闭' }
    }

    $summary.Add_Closing({
        param($sender, $eventArgs)
        if ($reviewNeeded -and -not [bool]$ReviewAcknowledgeCheck.IsChecked) {
            $eventArgs.Cancel = $true
            $ReviewGateHint.Text = '不能跳过：先确认你已经看清最大缺口和下一轮动作'
            $ReviewGateHint.Foreground = New-Object Windows.Media.SolidColorBrush ([Windows.Media.ColorConverter]::ConvertFromString('#B14F35'))
            $ReviewGateCard.BringIntoView()
            return
        }
        if ($reviewNeeded) {
            $reviewedAt = (Get-Date).ToString('o')
            $reviewProperty = $Evaluation.PSObject.Properties['ReviewedAt']
            if ($null -eq $reviewProperty) {
                $Evaluation | Add-Member -NotePropertyName ReviewedAt -NotePropertyValue $reviewedAt
            } else {
                $reviewProperty.Value = $reviewedAt
            }
            Save-SessionHistory
        }
    })
    Start-WindowEntrance -Window $summary -OffsetY 14 -DurationMs 280
    $borderScale = New-Object Windows.Media.ScaleTransform(0.85, 0.85)
    $ScoreAccentBorder.RenderTransform = $borderScale
    $ScoreAccentBorder.RenderTransformOrigin = New-Object Windows.Point(0.5, 0.5)
    $summary.Add_ContentRendered({
        Start-TextCountUp -TextBlock $ScoreLabel -Target ([int]$Evaluation.Score)
        $popAnimation = New-Object Windows.Media.Animation.DoubleAnimation(0.85, 1.0, [TimeSpan]::FromMilliseconds(320))
        $popAnimation.EasingFunction = New-Object Windows.Media.Animation.BackEase -Property @{ EasingMode = 'EaseOut'; Amplitude = 0.5 }
        $borderScale.BeginAnimation([Windows.Media.ScaleTransform]::ScaleXProperty, $popAnimation)
        $borderScale.BeginAnimation([Windows.Media.ScaleTransform]::ScaleYProperty, $popAnimation)
    })
    $CloseSummaryButton.Add_Click({ $summary.Close() })

    if ($null -eq $OwnerWindow) {
        $window.ShowInTaskbar = $true
        $window.Show()
        if ($window.WindowState -eq [Windows.WindowState]::Minimized) {
            $window.WindowState = [Windows.WindowState]::Normal
        }
        [void]$window.Activate()
    } else {
        [void]$OwnerWindow.Activate()
    }
    [void]$summary.ShowDialog()
}
