function Show-HistorySummary {
    if ($null -eq $HistoryXaml) {
        [System.Windows.MessageBox]::Show('缺少 FocusGuard.History.xaml，无法打开历史汇总。', '专注成绩档案') | Out-Null
        return
    }

    $history = Convert-XamlToWindow -Xaml $HistoryXaml
    $history.Owner = $window
    $history.Icon = $window.Icon
    Start-WindowEntrance -Window $history -OffsetY 14 -DurationMs 280
    $history.Width = $script:HistoryWindowWidth
    $history.Height = $script:HistoryWindowHeight
    $AccountabilityHeadline = Find-Control $history 'AccountabilityHeadline'
    $AccountabilityText = Find-Control $history 'AccountabilityText'
    $WeakestDimensionLabel = Find-Control $history 'WeakestDimensionLabel'
    $TotalSessionsValue = Find-Control $history 'TotalSessionsValue'
    $AverageScoreValue = Find-Control $history 'AverageScoreValue'
    $CompletionRateValue = Find-Control $history 'CompletionRateValue'
    $TotalMinutesValue = Find-Control $history 'TotalMinutesValue'
    $TrendBarsPanel = Find-Control $history 'TrendBarsPanel'
    $TrendSummaryLabel = Find-Control $history 'TrendSummaryLabel'
    $LongTermInsightLabel = Find-Control $history 'LongTermInsightLabel'
    $ReviewStatusLabel = Find-Control $history 'ReviewStatusLabel'
    $HeatmapMonthLabels = Find-Control $history 'HeatmapMonthLabels'
    $HeatmapGrid = Find-Control $history 'HeatmapGrid'
    $HeatmapSummaryLabel = Find-Control $history 'HeatmapSummaryLabel'
    $HistoryInsightColumn = Find-Control $history 'HistoryInsightColumn'
    $HistoryPaneSplitter = Find-Control $history 'HistoryPaneSplitter'
    $HistoryList = Find-Control $history 'HistoryList'
    $EmptyHistoryLabel = Find-Control $history 'EmptyHistoryLabel'
    $ViewSelectedButton = Find-Control $history 'ViewSelectedButton'
    $CloseHistoryButton = Find-Control $history 'CloseHistoryButton'
    $HistoryInsightColumn.Width = New-Object Windows.GridLength $script:HistoryInsightWidth


    $rows = New-Object System.Collections.ArrayList
    foreach ($record in @($script:SessionHistory | Select-Object -Last 100 | Sort-Object { [DateTime](Get-ObjectPropertyValue $_ 'Timestamp' [DateTime]::MinValue) } -Descending)) {
        $timestamp = Get-ObjectPropertyValue $record 'Timestamp' ''
        $displayDate = [string]$timestamp
        try { $displayDate = ([DateTime]$timestamp).ToString('MM-dd HH:mm') } catch { }
        $score = [int](Get-ObjectPropertyValue $record 'Score' 0)
        $reviewProperty = $record.PSObject.Properties['ReviewedAt']
        $review = if ($score -eq 100) {
            '满分'
        } elseif ($null -ne $reviewProperty -and -not [string]::IsNullOrWhiteSpace([string]$reviewProperty.Value)) {
            '已复盘'
        } else {
            '待复盘'
        }
        [void]$rows.Add([pscustomobject]@{
            Date = $displayDate
            Task = [string](Get-ObjectPropertyValue $record 'Task' '未命名任务')
            Score = $score
            Focus = "$([int](Get-ObjectPropertyValue $record 'FocusPercent' 0))%"
            Progress = "$([int](Get-ObjectPropertyValue $record 'ProgressPercent' 0))%"
            Reminders = [int](Get-ObjectPropertyValue $record 'ReminderCount' 0)
            Review = $review
            Record = $record
        })
    }
    $HistoryList.ItemsSource = $rows
    $EmptyHistoryLabel.Visibility = if ($rows.Count -eq 0) { 'Visible' } else { 'Collapsed' }

    $refreshOverview = {
        $overview = Get-HistoryOverview -Records @($script:SessionHistory)
        $AccountabilityHeadline.Text = [string]$overview.AccountabilityHeadline
        $AccountabilityText.Text = [string]$overview.AccountabilityText
        $WeakestDimensionLabel.Text = [string]$overview.WeakestDimension
        $TotalSessionsValue.Text = [string]$overview.TotalSessions
        $AverageScoreValue.Text = [string]$overview.AverageScore
        $CompletionRateValue.Text = [string]$overview.CompletionRate
        $TotalMinutesValue.Text = if ([int]$overview.TotalMinutes -ge 60) {
            "$([Math]::Round([int]$overview.TotalMinutes / 60.0, 1)) 小时"
        } else {
            "$($overview.TotalMinutes) 分钟"
        }
        $TrendSummaryLabel.Text = [string]$overview.TrendSummary
        $LongTermInsightLabel.Text = [string]$overview.LongTermInsight
        $ReviewStatusLabel.Text = [string]$overview.ReviewStatus
        $TrendBarsPanel.Children.Clear()
        $barIndex = 0
        foreach ($record in @($overview.RecentRecords)) {
            $score = [int](Get-ObjectPropertyValue $record 'Score' 0)
            $column = New-Object Windows.Controls.StackPanel
            $column.Margin = New-Object Windows.Thickness(2, 0, 2, 0)
            $scoreText = New-Object Windows.Controls.TextBlock
            $scoreText.Text = [string]$score
            $scoreText.FontSize = 10
            $scoreText.FontWeight = 'SemiBold'
            $scoreText.HorizontalAlignment = 'Center'
            [void]$column.Children.Add($scoreText)
            $barHost = New-Object Windows.Controls.Grid
            $barHost.Height = 92
            $barHost.Margin = New-Object Windows.Thickness(0, 4, 0, 5)
            $bar = New-Object Windows.Controls.Border
            $bar.Width = 18
            $barTargetHeight = [Math]::Max(4, [Math]::Min(88, $score * 0.88))
            $bar.Height = 0
            $bar.VerticalAlignment = 'Bottom'
            $bar.CornerRadius = New-Object Windows.CornerRadius(4, 4, 1, 1)
            $barColor = if ($score -ge 90) { '#2FA875' } elseif ($score -ge 70) { '#D5A13C' } else { '#D06A4F' }
            $bar.Background = New-Object Windows.Media.SolidColorBrush ([Windows.Media.ColorConverter]::ConvertFromString($barColor))
            $bar.ToolTip = "$score 分 · $(Get-ObjectPropertyValue $record 'Task' '未命名任务')"
            $barGrow = New-EaseOutAnimation -From 0 -To $barTargetHeight -DurationMs 380
            $barGrow.BeginTime = [TimeSpan]::FromMilliseconds($barIndex * 45)
            $bar.BeginAnimation([Windows.FrameworkElement]::HeightProperty, $barGrow)
            $barIndex++
            [void]$barHost.Children.Add($bar)
            [void]$column.Children.Add($barHost)
            $dateText = New-Object Windows.Controls.TextBlock
            $dateValue = Get-ObjectPropertyValue $record 'Timestamp' ''
            try { $dateText.Text = ([DateTime]$dateValue).ToString('MM-dd') } catch { $dateText.Text = '--' }
            $dateText.FontSize = 9
            $dateText.Foreground = New-Object Windows.Media.SolidColorBrush ([Windows.Media.ColorConverter]::ConvertFromString('#7A8780'))
            $dateText.HorizontalAlignment = 'Center'
            [void]$column.Children.Add($dateText)
            [void]$TrendBarsPanel.Children.Add($column)
        }

        $heatmap = Get-FocusHeatmapData -Records @($script:SessionHistory) -Weeks 18
        $HeatmapSummaryLabel.Text = [string]$heatmap.Summary
        $HeatmapGrid.Children.Clear()
        $HeatmapGrid.RowDefinitions.Clear()
        $HeatmapGrid.ColumnDefinitions.Clear()
        $HeatmapMonthLabels.Children.Clear()
        $HeatmapMonthLabels.ColumnDefinitions.Clear()
        1..7 | ForEach-Object { [void]$HeatmapGrid.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition)) }
        1..18 | ForEach-Object {
            [void]$HeatmapGrid.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition))
            [void]$HeatmapMonthLabels.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition))
        }
        $colors = @('#E7ECE9', '#D2E7E8', '#8CC6CB', '#4497A0', '#17616C')
        $lastMonth = -1
        $dayIndex = 0
        foreach ($day in @($heatmap.Days)) {
            $columnIndex = [int][Math]::Floor($dayIndex / 7)
            $rowIndex = $dayIndex % 7
            $cell = New-Object Windows.Controls.Border
            $cell.Margin = New-Object Windows.Thickness(2)
            $cell.CornerRadius = New-Object Windows.CornerRadius(3)
            $cell.Background = New-Object Windows.Media.SolidColorBrush ([Windows.Media.ColorConverter]::ConvertFromString($colors[[int]$day.Level]))
            $cellOpacity = if ([bool]$day.IsFuture) { 0.28 } else { 1.0 }
            $cell.Opacity = 0
            $cellFade = New-Object Windows.Media.Animation.DoubleAnimation(0, $cellOpacity, [TimeSpan]::FromMilliseconds(240))
            $cellFade.BeginTime = [TimeSpan]::FromMilliseconds([Math]::Min(700, $dayIndex * 5))
            $cell.BeginAnimation([Windows.UIElement]::OpacityProperty, $cellFade)
            $cell.ToolTip = if ([bool]$day.IsFuture) {
                $day.Date.ToString('yyyy-MM-dd')
            } elseif ([int]$day.Sessions -eq 0) {
                "$($day.Date.ToString('yyyy-MM-dd')) · 无记录"
            } else {
                "$($day.Date.ToString('yyyy-MM-dd')) · $($day.Sessions) 轮 · 有效 $($day.ActiveMinutes) 分钟 · 均分 $($day.AverageScore) · 完成 $($day.Completed) 轮"
            }
            [Windows.Controls.Grid]::SetColumn($cell, $columnIndex)
            [Windows.Controls.Grid]::SetRow($cell, $rowIndex)
            [void]$HeatmapGrid.Children.Add($cell)
            if ($day.Date.Month -ne $lastMonth) {
                $monthLabel = New-Object Windows.Controls.TextBlock
                $monthLabel.Text = "$($day.Date.Month)月"
                $monthLabel.FontSize = 9
                $monthLabel.Foreground = New-Object Windows.Media.SolidColorBrush ([Windows.Media.ColorConverter]::ConvertFromString('#7D8982'))
                $monthLabel.HorizontalAlignment = 'Left'
                [Windows.Controls.Grid]::SetColumn($monthLabel, $columnIndex)
                [void]$HeatmapMonthLabels.Children.Add($monthLabel)
                $lastMonth = $day.Date.Month
            }
            $dayIndex++
        }
    }
    & $refreshOverview

    $openSelected = {
        if ($null -eq $HistoryList.SelectedItem) { return }
        $selected = $HistoryList.SelectedItem
        $requiresReview = [string]$selected.Review -eq '待复盘'
        Show-SessionSummary -Evaluation $selected.Record -RequireReview $requiresReview -OwnerWindow $history
        $reviewProperty = $selected.Record.PSObject.Properties['ReviewedAt']
        if ([int]$selected.Score -lt 100 -and $null -ne $reviewProperty -and -not [string]::IsNullOrWhiteSpace([string]$reviewProperty.Value)) {
            $selected.Review = '已复盘'
            $HistoryList.Items.Refresh()
            & $refreshOverview
        }
    }
    $HistoryList.Add_SelectionChanged({ $ViewSelectedButton.IsEnabled = $null -ne $HistoryList.SelectedItem })
    $HistoryList.Add_MouseDoubleClick($openSelected)
    $HistoryPaneSplitter.Add_MouseDoubleClick({
        Start-ColumnWidthAnimation -Column $HistoryInsightColumn -Target 380
        $script:HistoryInsightWidth = 380
    })
    $ViewSelectedButton.Add_Click($openSelected)
    $CloseHistoryButton.Add_Click({ $history.Close() })
    $history.Add_Closing({
        $bounds = if ($history.WindowState -eq [Windows.WindowState]::Normal) {
            [pscustomobject]@{ Width = $history.ActualWidth; Height = $history.ActualHeight }
        } else { $history.RestoreBounds }
        $script:HistoryWindowWidth = [Math]::Max(1040.0, [Math]::Min(2200.0, [double]$bounds.Width))
        $script:HistoryWindowHeight = [Math]::Max(800.0, [Math]::Min(1300.0, [double]$bounds.Height))
        $script:HistoryInsightWidth = [Math]::Max(320.0, [Math]::Min(520.0, [double]$HistoryInsightColumn.ActualWidth))
        Save-Settings
    })
    [void]$history.ShowDialog()
}

function Sync-ActionState {
    $canPause = $script:SessionRunning -and -not $script:BreakUntil
    $PauseButton.IsEnabled = $canPause
    $PauseButton.Visibility = if ($script:SessionRunning -and $script:BreakUntil) { 'Collapsed' } else { 'Visible' }
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
    $script:SessionLastSampleAt = $now
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

    Start-WindowEntrance -Window $popup -OffsetY 22 -DurationMs 300 -Pop

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
        $script:SessionBreakCount++
        $script:SessionLastSampleAt = $script:BreakStartedAt
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

function Show-TabooLock {
    param([string]$Word, $Snapshot, [int]$Seconds, [int]$Strike, [bool]$SameAsLast = $false)
    if ($script:TabooLockOpen) { return }
    $script:TabooLockOpen = $true
    $script:TabooLockCanClose = $false

    if ([bool]$SoundCheck.IsChecked) { [System.Media.SystemSounds]::Exclamation.Play() }

    $lockWindow = Convert-XamlToWindow -Xaml $TabooXaml
    $script:TabooLockWindow = $lockWindow
    $lockWindow.Add_SourceInitialized({
        $script:TabooLockWindowHandle = (New-Object Windows.Interop.WindowInteropHelper($lockWindow)).Handle
    })
    $TabooWordLabel = Find-Control $lockWindow 'TabooWordLabel'
    $TabooContextLabel = Find-Control $lockWindow 'TabooContextLabel'
    $TabooCountdownLabel = Find-Control $lockWindow 'TabooCountdownLabel'
    $TabooStrikeLabel = Find-Control $lockWindow 'TabooStrikeLabel'

    $baseSeconds = Get-IntSetting $TabooLockBox 15 5 3600
    $TabooWordLabel.Text = $Word
    $contextTitle = if ($Snapshot -and $Snapshot.Title) { $Snapshot.Title } else { '无标题窗口' }
    $contextProcess = if ($Snapshot) { [string]$Snapshot.ProcessName } else { '' }
    $TabooContextLabel.Text = "触发窗口：$contextTitle  ·  $contextProcess"
    $lockSeconds = [Math]::Max(1, $Seconds)
    $TabooCountdownLabel.Text = [string]$lockSeconds
    if ($SameAsLast) {
        $TabooStrikeLabel.Text = "今天第 $Strike 次触发 · 解除锁定后 30 秒内重复触发，锁定时长与上次相同"
    } else {
        $TabooStrikeLabel.Text = "今天第 $Strike 次触发 · 锁定 $baseSeconds 秒 × $Strike；再次触发会更久"
    }

    # 事件处理器每次触发都在新作用域执行：闭包里的局部变量自减不会跨触发保留，
    # GetNewClosure 内的 $script: 也会指向闭包私有作用域。倒计时状态全部放 $script
    # 作用域（与提醒弹窗同一套写法），每秒按截止时间换算剩余秒数。
    $script:TabooLockEndsAt = (Get-Date).AddSeconds($lockSeconds)
    $script:TabooLockCountdownLabel = $TabooCountdownLabel
    $script:TabooLockTimer = New-Object Windows.Threading.DispatcherTimer
    $script:TabooLockTimer.Interval = [TimeSpan]::FromSeconds(1)
    $script:TabooLockTimer.Add_Tick({
        if ($null -eq $script:TabooLockEndsAt) { return }
        $remainingLock = [int][Math]::Ceiling(($script:TabooLockEndsAt - (Get-Date)).TotalSeconds)
        if ($remainingLock -le 0) {
            $script:TabooLockTimer.Stop()
            $script:TabooLockCanClose = $true
            $script:TabooLockWindow.Close()
            return
        }
        $script:TabooLockCountdownLabel.Text = [string]$remainingLock
        try {
            $script:TabooLockWindow.Topmost = $true
            [void]$script:TabooLockWindow.Activate()
        } catch { }
    })

    # 倒计时结束前拦截一切关闭途径（含 Alt+F4）；程序退出时放行。
    $lockWindow.Add_Closing({
        param($sender, $eventArgs)
        if (-not $script:TabooLockCanClose -and -not $script:AllowExit) {
            $eventArgs.Cancel = $true
        }
    })
    $lockWindow.Add_Closed({
        $script:TabooLockTimer.Stop()
        $script:TabooLockOpen = $false
        $script:TabooLockWindow = $null
        $script:TabooLockWindowHandle = [IntPtr]::Zero
        $script:TabooLockCanClose = $false
        $script:TabooLockEndsAt = $null
        $script:TabooLockCountdownLabel = $null
        $script:TabooLockTimer = $null
        $script:TabooGraceUntil = (Get-Date).AddSeconds((Get-IntSetting $TabooGraceBox 10 1 10))
    })
    $script:TabooLockTimer.Start()
    [void]$lockWindow.ShowDialog()
}

function Start-TabooStrike {
    param([string]$Word, $Snapshot)
    $todayStamp = (Get-Date).ToString('yyyy-MM-dd')
    if ($script:TabooStrikeDate -ne $todayStamp) {
        $script:TabooStrikeDate = $todayStamp
        $script:TabooStrikeCount = 0
    }
    $script:TabooStrikeCount++
    try { Save-Settings } catch { Write-AppLog "保存禁忌触发次数失败：$($_.Exception.Message)" }
    # 解除锁定后 30 秒内再次触发：锁定时长与上次相同，不再递增。
    $now = Get-Date
    $sameAsLast = $false
    if ($null -ne $script:TabooLastTriggerAt -and $script:TabooLastLockSeconds -gt 0) {
        $lastLockEndedAt = $script:TabooLastTriggerAt.AddSeconds($script:TabooLastLockSeconds)
        if (($now - $lastLockEndedAt).TotalSeconds -le 30) { $sameAsLast = $true }
    }
    if ($sameAsLast) {
        $lockSeconds = $script:TabooLastLockSeconds
    } else {
        $lockSeconds = Get-TabooLockSeconds -BaseSeconds (Get-IntSetting $TabooLockBox 15 5 3600) -Strike $script:TabooStrikeCount
    }
    $script:TabooLastTriggerAt = $now
    $script:TabooLastLockSeconds = $lockSeconds
    Show-TabooLock -Word $Word -Snapshot $Snapshot -Seconds $lockSeconds -Strike $script:TabooStrikeCount -SameAsLast $sameAsLast
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
    $script:TabooGraceUntil = $null
    $script:ReminderCount = 0
    $script:ReturnCount = 0
    $script:TotalPausedSeconds = 0.0
    $script:SessionLastSampleAt = $script:StartedAt
    $script:SessionActivityState = 'untracked'
    $script:SessionOnTaskSeconds = 0.0
    $script:SessionOffTaskSeconds = 0.0
    $script:SessionIdleSeconds = 0.0
    $script:SessionRecoveryCount = 0
    $script:SessionPauseCount = 0
    $script:SessionBreakCount = 0
    $script:CurrentSessionTask = $TaskBox.Text.Trim()

    $ReminderCountLabel.Text = '0'
    $ReturnCountLabel.Text = '0'
    $FocusedTimeLabel.Text = '0 分钟'
    $CurrentTaskLabel.Text = $TaskBox.Text.Trim()
    $window.Title = "专注中 · $($TaskBox.Text.Trim())"
    $CountdownLabel.Text = '{0:00}:00' -f $duration
    Reset-ProgressValue -ProgressBar $SessionProgress
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
    if ($null -ne $HistoryButton) { $HistoryButton.IsEnabled = $false }
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
        $script:SessionPauseCount++
        $script:SessionLastSampleAt = $script:PausedAt
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
        $script:SessionLastSampleAt = Get-Date
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
    $endedAt = Get-Date
    $pausedSeconds = $script:TotalPausedSeconds
    if ($script:IsPaused -and $script:PausedAt) {
        $pausedSeconds += [Math]::Max(0.0, ($endedAt - $script:PausedAt).TotalSeconds)
    }
    if ($script:BreakUntil -and $script:BreakStartedAt) {
        $pausedSeconds += [Math]::Max(0.0, ($endedAt - $script:BreakStartedAt).TotalSeconds)
    }
    $activeElapsedSeconds = [Math]::Max(0.0, ($endedAt - $script:StartedAt).TotalSeconds - $pausedSeconds)
    $evaluation = Get-SessionEvaluation `
        -PlannedSeconds $script:SessionDurationSeconds `
        -ActiveElapsedSeconds $activeElapsedSeconds `
        -OnTaskSeconds $script:SessionOnTaskSeconds `
        -OffTaskSeconds $script:SessionOffTaskSeconds `
        -IdleSeconds $script:SessionIdleSeconds `
        -ReminderCount $script:ReminderCount `
        -RecoveryCount $script:SessionRecoveryCount `
        -PauseCount $script:SessionPauseCount `
        -BreakCount $script:SessionBreakCount `
        -PausedSeconds $pausedSeconds `
        -Completed $Completed
    $record = Register-SessionEvaluation -Evaluation $evaluation -EndedAt $endedAt -Completed $Completed -ActiveElapsedSeconds $activeElapsedSeconds -PausedSeconds $pausedSeconds

    $script:SessionRunning = $false
    $script:IsPaused = $false
    $script:PausedAt = $null
    $script:BreakUntil = $null
    $script:BreakStartedAt = $null
    $script:SessionLastSampleAt = $null
    $script:OffTaskSince = $null
    $window.Title = "专注守卫 v$script:FocusGuardVersion"
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
    $CountdownLabel.Text = "$($evaluation.Score) 分"
    Set-ProgressValue -ProgressBar $SessionProgress -Target ([double]$evaluation.Score) -DurationMs 600
    $PhaseLabel.Text = "本轮评分 · $($evaluation.Grade)"
    if ($Completed) {
        $MonitorLabel.Text = '本轮时长已完成；点击“历史汇总”查看长期表现'
        Set-StatusVisual '本轮完成' '#48C98B'
        if ([bool]$SoundCheck.IsChecked) { [System.Media.SystemSounds]::Asterisk.Play() }
    } else {
        $MonitorLabel.Text = '本轮提前结束；分析里给出了下一轮调整建议'
        Set-StatusVisual '本轮已评分' '#899087'
    }
    Save-Settings
    Show-SessionSummary -Evaluation $record -RequireReview $true
}

function Show-PendingReviewIfNeeded {
    if ($script:PendingReviewShown) { return }
    $script:PendingReviewShown = $true
    $pendingReview = @($script:SessionHistory | Where-Object {
        $score = [int](Get-ObjectPropertyValue $_ 'Score' 100)
        $reviewProperty = $_.PSObject.Properties['ReviewedAt']
        $score -lt 100 -and $null -ne $reviewProperty -and [string]::IsNullOrWhiteSpace([string]$reviewProperty.Value)
    } | Select-Object -Last 1)
    if ($pendingReview.Count -gt 0) { Show-SessionSummary -Evaluation $pendingReview[0] -RequireReview $true }
}

function Show-MainWindow {
    $wasHidden = -not $window.IsVisible -or $window.WindowState -eq [Windows.WindowState]::Minimized
    $window.ShowInTaskbar = $true
    $window.Show()
    $window.WindowState = [Windows.WindowState]::Normal
    if ($wasHidden) { Start-WindowEntrance -Window $window -OffsetY 8 -DurationMs 200 -Immediate }
    [void]$window.Activate()
    Show-PendingReviewIfNeeded
}
