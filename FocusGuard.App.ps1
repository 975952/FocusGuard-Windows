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
            $script:SessionLastSampleAt = $now
            $remainingBreak = $script:BreakUntil - $now
            $CountdownLabel.Text = '{0:00}:{1:00}' -f [Math]::Floor($remainingBreak.TotalMinutes), $remainingBreak.Seconds
            $PhaseLabel.Text = '休息中'
            $MonitorLabel.Text = '休息结束后自动恢复监测'
            Set-StatusVisual '休息中' '#4F87B8'
            return
        }
        End-Break
    }

    if ($script:IsPaused) {
        $script:SessionLastSampleAt = $now
        return
    }

    $remaining = $script:EndTime - $now
    if ($remaining.TotalSeconds -le 0) {
        Stop-Session -Completed $true
        return
    }
    $CountdownLabel.Text = '{0:00}:{1:00}' -f [Math]::Floor($remaining.TotalMinutes), $remaining.Seconds
    $progress = [Math]::Min(100, [Math]::Max(0, (1 - ($remaining.TotalSeconds / $script:SessionDurationSeconds)) * 100))
    Set-ProgressValue -ProgressBar $SessionProgress -Target $progress
    $taskbarInfo.ProgressValue = $progress / 100.0
    $focusedSeconds = [Math]::Max(0, ($now - $script:StartedAt).TotalSeconds - $script:TotalPausedSeconds)
    $FocusedTimeLabel.Text = "$([Math]::Floor($focusedSeconds / 60)) 分钟"

    if ($script:PopupOpen) {
        if ($script:SessionActivityState -in @('offtask', 'idle')) {
            Add-SessionSample -Timestamp $now -ActivityState $script:SessionActivityState
        } else {
            $script:SessionLastSampleAt = $now
        }
        return
    }

    $idleThreshold = Get-IntSetting $IdleBox 180 30 3600
    $idleSeconds = [FocusGuardNative]::IdleSeconds()
    $allowedApps = @(Get-RuleItems $AllowedAppsList)
    $allowedTitles = @(Get-RuleItems $AllowedTitlesList)
    $allowed = $isOwnWindow -or (Test-SnapshotAllowed -ProcessName $snapshot.ProcessName -Title $snapshot.Title -AllowedApps $allowedApps -AllowedTitles $allowedTitles -TaskName $TaskBox.Text)

    if ($idleSeconds -ge $idleThreshold) {
        Add-SessionSample -Timestamp $now -ActivityState 'idle'
        $script:OffTaskSince = $null
        if ($now -lt $script:ReminderCooldownUntil) {
            $MonitorLabel.Text = '仍处于无操作状态，提醒冷却中'
            return
        }
        Show-Reminder -Reason 'idle' -Snapshot $snapshot
        return
    }

    if ($allowed) {
        Add-SessionSample -Timestamp $now -ActivityState 'ontask'
        $script:OffTaskSince = $null
        $MonitorLabel.Text = '在允许范围内，继续保持'
        return
    }

    Add-SessionSample -Timestamp $now -ActivityState 'offtask'
    if ($now -lt $script:ReminderCooldownUntil) {
        $MonitorLabel.Text = '仍在专注范围外，提醒冷却中'
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
Load-SessionHistory
if ($null -ne $HistoryButton) { $HistoryButton.IsEnabled = $true }
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
        if ($null -ne $HistoryButton) { $HistoryButton.IsEnabled = $true }
        $PhaseLabel.Text = '启动失败'
        $MonitorLabel.Text = "无法开始：$message"
        $StatusBadge.Text = '启动失败'
    }
})
$PauseButton.Add_Click({ Pause-Session })
$EndBreakButton.Add_Click({ End-Break })
$StopButton.Add_Click({ Stop-Session -Completed $false })
if ($null -ne $HistoryButton) {
    $HistoryButton.Add_Click({ Show-HistorySummary })
}
$HideButton.Add_Click({
    $window.ShowInTaskbar = $true
    $window.WindowState = [Windows.WindowState]::Minimized
})
$ExitButton.Add_Click({ Exit-Application })
$addAllowedApp = {
    if (Add-RuleItem $AllowedAppsList $AllowedAppInput.Text -ProcessName) {
        $AllowedAppInput.Clear()
        Update-RuleCountLabels
        Queue-SettingsSave
    }
}
$addAllowedTitle = {
    if (Add-RuleItem $AllowedTitlesList $AllowedTitleInput.Text) {
        $AllowedTitleInput.Clear()
        Update-RuleCountLabels
        Queue-SettingsSave
    }
}
$AddAllowedAppButton.Add_Click($addAllowedApp)
$AddAllowedTitleButton.Add_Click($addAllowedTitle)
$AllowedAppInput.Add_KeyDown({
    param($sender, $eventArgs)
    if ($eventArgs.Key -eq [Windows.Input.Key]::Return) { $eventArgs.Handled = $true; & $addAllowedApp }
})
$AllowedTitleInput.Add_KeyDown({
    param($sender, $eventArgs)
    if ($eventArgs.Key -eq [Windows.Input.Key]::Return) { $eventArgs.Handled = $true; & $addAllowedTitle }
})
$RemoveAllowedAppButton.Add_Click({
    if ((Remove-SelectedRuleItems $AllowedAppsList) -gt 0) { Update-RuleCountLabels; Queue-SettingsSave }
})
$RemoveAllowedTitleButton.Add_Click({
    if ((Remove-SelectedRuleItems $AllowedTitlesList) -gt 0) { Update-RuleCountLabels; Queue-SettingsSave }
})
$AllowedAppsList.Add_KeyDown({
    param($sender, $eventArgs)
    if ($eventArgs.Key -eq [Windows.Input.Key]::Delete -and (Remove-SelectedRuleItems $AllowedAppsList) -gt 0) { Update-RuleCountLabels; Queue-SettingsSave }
})
$AllowedTitlesList.Add_KeyDown({
    param($sender, $eventArgs)
    if ($eventArgs.Key -eq [Windows.Input.Key]::Delete -and (Remove-SelectedRuleItems $AllowedTitlesList) -gt 0) { Update-RuleCountLabels; Queue-SettingsSave }
})
$AddCurrentAppButton.Add_Click({
    if (-not $script:LastExternalSnapshot -or -not $script:LastExternalSnapshot.ProcessName) {
        [System.Windows.MessageBox]::Show('还没有检测到其他应用。先切换到要允许的应用，再回来点击。', '专注守卫') | Out-Null
        return
    }
    $process = $script:LastExternalSnapshot.ProcessName
    if (Add-RuleItem $AllowedAppsList $process -ProcessName) { Update-RuleCountLabels; Save-Settings }
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
$ToneBox.Add_SelectionChanged({ Queue-SettingsSave })
$SoundCheck.Add_Click({ Queue-SettingsSave })
$StartWithWindowsCheck.Add_Click({
    if ($script:AutoStartChangeInternal) { return }
    $desired = [bool]$StartWithWindowsCheck.IsChecked
    try {
        Set-AutoStartEnabled $desired
        $StartWithWindowsStatusLabel.Text = if ($desired) { '已启用 · 下次登录后最小化运行' } else { '当前未启用' }
        $StartWithWindowsStatusLabel.Foreground = New-Object Windows.Media.SolidColorBrush ([Windows.Media.ColorConverter]::ConvertFromString('#607269'))
        Save-Settings
    } catch {
        $script:AutoStartChangeInternal = $true
        $StartWithWindowsCheck.IsChecked = -not $desired
        $script:AutoStartChangeInternal = $false
        $StartWithWindowsStatusLabel.Text = "设置失败：$($_.Exception.Message)"
        $StartWithWindowsStatusLabel.Foreground = New-Object Windows.Media.SolidColorBrush ([Windows.Media.ColorConverter]::ConvertFromString('#A54836'))
    }
})
$ResetLayoutButton.Add_Click({
    Start-WindowSizeAnimation -Window $window -TargetWidth 1440 -TargetHeight 920
    Start-ColumnWidthAnimation -Column $SettingsColumn -Target 560
    $script:HistoryWindowWidth = 1280
    $script:HistoryWindowHeight = 960
    $script:HistoryInsightWidth = 380
    Queue-SettingsSave
    $MonitorLabel.Text = '已恢复推荐窗口与面板大小'
})
$MainPaneSplitter.Add_MouseDoubleClick({
    Start-ColumnWidthAnimation -Column $SettingsColumn -Target 560
    Queue-SettingsSave
    $MonitorLabel.Text = '已恢复推荐面板宽度'
})
$IdleBox.Add_LostFocus({ $IdleBox.Text = [string](Get-IntSetting $IdleBox 180 30 3600) })
$GraceBox.Add_LostFocus({ $GraceBox.Text = [string](Get-IntSetting $GraceBox 25 3 600) })

$window.Add_SourceInitialized({
    $script:MainWindowHandle = (New-Object Windows.Interop.WindowInteropHelper($window)).Handle
})
$window.Add_ContentRendered({
    if ($window.WindowState -ne [Windows.WindowState]::Minimized) { Show-PendingReviewIfNeeded }
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

if ($StartMinimized) {
    $window.WindowState = [Windows.WindowState]::Minimized
    $window.ShowInTaskbar = $true
}
if ($null -ne $script:SplashCloseEvent) {
    $window.Add_ContentRendered({
        try { [void]$script:SplashCloseEvent.Set() } catch {}
    }.GetNewClosure())
}
Start-WindowEntrance -Window $window -OffsetY 12 -DurationMs 280
[void]$window.ShowDialog()
