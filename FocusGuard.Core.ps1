Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$script:FocusGuardVersion = '1.4.8'

# 启动画面：打包环境中存在 FocusGuard.Splash.exe 时立即显示，主窗口渲染完成后关闭。
# 自检与开机最小化启动不显示。
$script:SplashCloseEvent = $null
$selfTestVar = Get-Variable -Name 'SelfTest' -ErrorAction SilentlyContinue
$startMinVar = Get-Variable -Name 'StartMinimized' -ErrorAction SilentlyContinue
$splashAllowed = ($null -eq $selfTestVar -or -not $selfTestVar.Value) -and ($null -eq $startMinVar -or -not $startMinVar.Value)
if ($splashAllowed) {
    $splashExePath = Join-Path $PSScriptRoot 'FocusGuard.Splash.exe'
    if (Test-Path -LiteralPath $splashExePath) {
        $script:SplashCloseEvent = New-Object System.Threading.EventWaitHandle($false, [System.Threading.EventResetMode]::ManualReset, 'Local\FocusGuardCN_SplashClose')
        [void](Start-Process -FilePath $splashExePath -PassThru)
    }
}

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# 原生互操作类型：优先加载构建产物 FocusGuard.Native.dll（快），否则从 .cs 源码即时编译（开发模式）
$nativeDllPath = Join-Path $PSScriptRoot 'FocusGuard.Native.dll'
$nativeSourcePath = Join-Path $PSScriptRoot 'FocusGuard.Native.cs'
if (Test-Path -LiteralPath $nativeDllPath) {
    Add-Type -LiteralPath $nativeDllPath
} elseif (Test-Path -LiteralPath $nativeSourcePath) {
    Add-Type -TypeDefinition (Get-Content -LiteralPath $nativeSourcePath -Raw -Encoding UTF8) -ReferencedAssemblies 'System.Windows.Forms.dll'
} else {
    throw '缺少 FocusGuard.Native.dll 或 FocusGuard.Native.cs'
}

$mainXamlPath = Join-Path $PSScriptRoot 'FocusGuard.Main.xaml'
$reminderXamlPath = Join-Path $PSScriptRoot 'FocusGuard.Reminder.xaml'
$summaryXamlPath = Join-Path $PSScriptRoot 'FocusGuard.Summary.xaml'
$historyXamlPath = Join-Path $PSScriptRoot 'FocusGuard.History.xaml'
if (-not (Test-Path -LiteralPath $mainXamlPath)) { throw '缺少 FocusGuard.Main.xaml' }
if (-not (Test-Path -LiteralPath $reminderXamlPath)) { throw '缺少 FocusGuard.Reminder.xaml' }
[xml]$MainXaml = Get-Content -LiteralPath $mainXamlPath -Raw -Encoding UTF8
[xml]$ReminderXaml = Get-Content -LiteralPath $reminderXamlPath -Raw -Encoding UTF8
$SummaryXaml = $null
if (Test-Path -LiteralPath $summaryXamlPath) {
    [xml]$SummaryXaml = Get-Content -LiteralPath $summaryXamlPath -Raw -Encoding UTF8
}
$HistoryXaml = $null
if (Test-Path -LiteralPath $historyXamlPath) {
    [xml]$HistoryXaml = Get-Content -LiteralPath $historyXamlPath -Raw -Encoding UTF8
}

$script:SharedStyleDictionary = $null
$stylesXamlPath = Join-Path $PSScriptRoot 'FocusGuard.Styles.xaml'
if (Test-Path -LiteralPath $stylesXamlPath) {
    $script:SharedStyleDictionary = [Windows.Markup.XamlReader]::Parse((Get-Content -LiteralPath $stylesXamlPath -Raw -Encoding UTF8))
}

function Convert-XamlToWindow {
    param([xml]$Xaml)
    $reader = New-Object System.Xml.XmlNodeReader $Xaml
    $loaded = [Windows.Markup.XamlReader]::Load($reader)
    if ($null -ne $script:SharedStyleDictionary) {
        [void]$loaded.Resources.MergedDictionaries.Add($script:SharedStyleDictionary)
    }
    return $loaded
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

function Get-RuleItems {
    param($ListBox)
    if ($null -eq $ListBox) { return @() }
    return @($ListBox.Items | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ })
}

function Set-RuleItems {
    param($ListBox, [string[]]$Items)
    if ($null -eq $ListBox) { return }
    $ListBox.Items.Clear()
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($item in @($Items)) {
        $value = ([string]$item).Trim()
        if ($value -and $seen.Add($value)) { [void]$ListBox.Items.Add($value) }
    }
}

function Add-RuleItem {
    param($ListBox, [string]$Value, [switch]$ProcessName)
    if ($null -eq $ListBox) { return $false }
    $normalized = ([string]$Value -replace "[`r`n]", ' ').Trim()
    if ($ProcessName -and $normalized) {
        try {
            if ($normalized.IndexOfAny(@([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)) -ge 0) {
                $normalized = [IO.Path]::GetFileName($normalized)
            }
        } catch { }
        if ($normalized.EndsWith('.exe', [StringComparison]::OrdinalIgnoreCase)) {
            $normalized = $normalized.Substring(0, $normalized.Length - 4)
        }
    }
    if (-not $normalized) { return $false }
    foreach ($existing in @(Get-RuleItems $ListBox)) {
        if ([string]::Equals($existing, $normalized, [StringComparison]::OrdinalIgnoreCase)) { return $false }
    }
    [void]$ListBox.Items.Add($normalized)
    return $true
}

function Remove-SelectedRuleItems {
    param($ListBox)
    if ($null -eq $ListBox) { return 0 }
    $selected = @($ListBox.SelectedItems)
    foreach ($item in $selected) { $ListBox.Items.Remove($item) }
    return $selected.Count
}

function Get-AutoStartCommand {
    param([string]$Root = $PSScriptRoot)
    $wscript = Join-Path $env:WINDIR 'System32\wscript.exe'
    $launcher = Join-Path $Root '启动专注守卫.vbs'
    return ('"{0}" "{1}" /minimized' -f $wscript, $launcher)
}

function Get-AutoStartEnabled {
    try {
        $value = (Get-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'FocusGuardCN' -ErrorAction Stop).FocusGuardCN
        return -not [string]::IsNullOrWhiteSpace([string]$value)
    } catch { return $false }
}

function Set-AutoStartEnabled {
    param([bool]$Enabled)
    $runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
    if ($Enabled) {
        if (-not (Test-Path -LiteralPath $runKey)) { New-Item -Path $runKey -Force | Out-Null }
        Set-ItemProperty -LiteralPath $runKey -Name 'FocusGuardCN' -Value (Get-AutoStartCommand) -Type String
    } else {
        Remove-ItemProperty -LiteralPath $runKey -Name 'FocusGuardCN' -ErrorAction SilentlyContinue
    }
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

function Get-SessionEvaluation {
    param(
        [double]$PlannedSeconds,
        [double]$ActiveElapsedSeconds,
        [double]$OnTaskSeconds,
        [double]$OffTaskSeconds,
        [double]$IdleSeconds,
        [int]$ReminderCount,
        [int]$RecoveryCount,
        [int]$PauseCount,
        [int]$BreakCount,
        [double]$PausedSeconds,
        [bool]$Completed
    )

    $planned = [Math]::Max(1.0, $PlannedSeconds)
    $activeElapsed = [Math]::Max(0.0, $ActiveElapsedSeconds)
    $onTask = [Math]::Max(0.0, $OnTaskSeconds)
    $offTask = [Math]::Max(0.0, $OffTaskSeconds)
    $idle = [Math]::Max(0.0, $IdleSeconds)
    $tracked = $onTask + $offTask + $idle
    $focusRatio = if ($tracked -gt 0) { $onTask / $tracked } else { 0.0 }
    $progressRatio = if ($Completed) { 1.0 } else { [Math]::Min(1.0, $activeElapsed / $planned) }
    $recoveryRatio = if ($ReminderCount -le 0) { 1.0 } else { [Math]::Min(1.0, $RecoveryCount / [double]$ReminderCount) }
    $interruptions = [Math]::Max(0, $PauseCount) + [Math]::Max(0, $BreakCount)
    $pausedRatio = [Math]::Min(1.0, [Math]::Max(0.0, $PausedSeconds) / [Math]::Max(1.0, $activeElapsed + $PausedSeconds))

    # 满分必须在该维度真的无缺口；Floor 避免 99.x% 被四舍五入成完美。
    $qualityPoints = [int][Math]::Floor(50.0 * $focusRatio + 0.000001)
    $completionPoints = [int][Math]::Floor(30.0 * $progressRatio + 0.000001)
    $recoveryPoints = [int][Math]::Floor(10.0 * $recoveryRatio + 0.000001)
    $rhythmRaw = 10.0 - [Math]::Min(6.0, $interruptions * 1.25) - [Math]::Min(4.0, $pausedRatio * 12.0)
    $rhythmPoints = [int][Math]::Round([Math]::Max(0.0, $rhythmRaw))
    if (($interruptions -gt 0 -or $PausedSeconds -gt 3) -and $rhythmPoints -ge 10) { $rhythmPoints = 9 }
    $score = [Math]::Max(0, [Math]::Min(100, $qualityPoints + $completionPoints + $recoveryPoints + $rhythmPoints))

    $grade = switch ($score) {
        { $_ -ge 95 } { 'S · 极稳'; break }
        { $_ -ge 85 } { 'A · 很稳'; break }
        { $_ -ge 75 } { 'B · 状态不错'; break }
        { $_ -ge 60 } { 'C · 基本在线'; break }
        default { 'D · 需要调整' }
    }
    $focusPercent = [int][Math]::Round($focusRatio * 100)
    $progressPercent = [int][Math]::Round($progressRatio * 100)
    $recoveryPercent = [int][Math]::Round($recoveryRatio * 100)
    $onMinutes = [Math]::Round($onTask / 60.0, 1)
    $offMinutes = [Math]::Round($offTask / 60.0, 1)
    $idleMinutes = [Math]::Round($idle / 60.0, 1)
    $activeMinutes = [Math]::Round($activeElapsed / 60.0, 1)
    $pausedMinutes = [Math]::Round([Math]::Max(0.0, $PausedSeconds) / 60.0, 1)

    $verdict = if ($score -eq 100) {
        '这一轮所有评分维度都守住了：时长完成、注意力稳定、恢复及时、节奏连续。'
    } elseif ($score -ge 80) {
        '这一轮整体可靠，任务推进和注意力都在线，但仍有明确的丢分点。'
    } elseif ($score -ge 60) {
        '这一轮有实质推进，不过注意力或完成度还不够稳定。'
    } else {
        '这一轮没有守住计划，需要缩小目标并重新建立专注节奏。'
    }

    $completionText = if ($Completed) { '按计划完成本轮时长' } else { "完成计划时长的 $progressPercent%" }
    $reminderText = if ($ReminderCount -eq 0) {
        '全程没有触发跑偏或无操作提醒。'
    } else {
        "共触发 $ReminderCount 次提醒，检测到 $RecoveryCount 次重新进入专注范围，恢复率 $recoveryPercent%。"
    }
    $pauseText = if ($interruptions -eq 0) {
        '本轮没有暂停或提醒后休息，节奏保持连续。'
    } else {
        "本轮暂停 $PauseCount 次、提醒后休息 $BreakCount 次，合计暂停约 $pausedMinutes 分钟。"
    }
    $analysis = "• $completionText，实际有效进行约 $activeMinutes 分钟。`r`n" +
                "• 有效监测中，专注范围占 $focusPercent%；跑偏约 $offMinutes 分钟，无操作约 $idleMinutes 分钟。`r`n" +
                "• $reminderText`r`n" +
                "• $pauseText"

    $suggestion = if (-not $Completed) {
        $nextMinutes = [Math]::Max(10, [int][Math]::Round($activeElapsed / 60.0))
        "下一轮先把目标时长设为 $nextMinutes 分钟，并把任务缩成一个能在这段时间内交付的结果。先连续完成，再逐步加时。"
    } elseif ($tracked -gt 0 -and ($idle / $tracked) -ge 0.12) {
        '无操作是主要缺口。若是在看屏幕或纸质材料，请适当调高无操作阈值；否则给任务设一个每几分钟可见的产出动作。'
    } elseif ($tracked -gt 0 -and ($offTask / $tracked) -ge 0.10) {
        '跑偏是主要缺口。下一轮开始前关掉无关窗口，并把真正需要的应用或标题关键词补进允许范围。'
    } elseif ($ReminderCount -gt 0 -and $recoveryRatio -lt 0.8) {
        '提醒后的恢复不够快。下一次弹窗出现时直接关闭无关内容并返回目标，不把提醒当作新的停顿。'
    } elseif ($interruptions -ge 2) {
        '节奏被多次切断。下一轮把喝水、资料和必要窗口提前准备好，争取只保留一次计划内休息。'
    } else {
        '保持当前规则。下一轮把目标写成更具体的交付物，并尝试在不增加跑偏的前提下多守住 5 分钟。'
    }

    if (-not $Completed) {
        $keyInsight = '这一轮最需要面对的是：计划没有被完整兑现。'
        $evidence = "实际有效进行约 $activeMinutes 分钟，只走完计划的 $progressPercent%；注意力质量不是唯一问题，目标大小也需要调整。"
    } elseif ($tracked -le 0) {
        $keyInsight = '这一轮已经完成，但可用于判断注意力质量的数据还不够。'
        $evidence = '本轮没有形成有效的前台窗口或无操作采样，因此不把缺失数据包装成稳定表现。'
    } elseif (($offTask / $tracked) -ge 0.10 -and $offTask -ge $idle) {
        $keyInsight = '主要缺口不是时长，而是注意力离开了计划范围。'
        $evidence = "有效监测中有约 $offMinutes 分钟处于允许范围外，专注占比为 $focusPercent%。"
    } elseif (($idle / $tracked) -ge 0.12) {
        $keyInsight = '主要缺口是一段持续无操作，让系统无法确认你仍在推进。'
        $evidence = "无操作累计约 $idleMinutes 分钟，占有效监测时间的 $([int][Math]::Round(($idle / $tracked) * 100))%。"
    } elseif ($ReminderCount -gt 0 -and $recoveryRatio -lt 0.8) {
        $keyInsight = '提醒出现以后，返回任务的动作还不够果断。'
        $evidence = "$ReminderCount 次提醒中检测到 $RecoveryCount 次恢复，恢复率为 $recoveryPercent%。"
    } elseif ($interruptions -ge 2) {
        $keyInsight = '任务完成了，但节奏被多次切断。'
        $evidence = "暂停和提醒后休息合计 $interruptions 次，累计约 $pausedMinutes 分钟。"
    } elseif ($score -eq 100) {
        $keyInsight = '这一轮没有发现需要解释的缺口：完成、注意力、恢复和节奏都守住了。'
        $evidence = "完成计划时长，专注范围占比 $focusPercent%，没有提醒或额外中断。"
    } else {
        $keyInsight = '整体可靠，丢分来自小幅波动，不需要同时改很多东西。'
        $evidence = "完成进度 $progressPercent%，专注范围占比 $focusPercent%，本轮共触发 $ReminderCount 次提醒。"
    }

    $tellOff = ''
    if ($score -lt 100) {
        $losses = @(
            [pscustomobject]@{ Name = '专注质量'; Lost = 50 - $qualityPoints; Detail = "你有约 $offMinutes 分钟跑偏、$idleMinutes 分钟无操作" },
            [pscustomobject]@{ Name = '完成进度'; Lost = 30 - $completionPoints; Detail = "你只完成了计划的 $progressPercent%" },
            [pscustomobject]@{ Name = '跑偏恢复'; Lost = 10 - $recoveryPoints; Detail = "提醒后的恢复率只有 $recoveryPercent%" },
            [pscustomobject]@{ Name = '节奏连续'; Lost = 10 - $rhythmPoints; Detail = "暂停和休息一共打断了 $interruptions 次" }
        ) | Sort-Object Lost -Descending
        $mainLoss = $losses | Select-Object -First 1
        $tellOff = "这轮不是满分，别拿「差不多」当完成。最大缺口是$($mainLoss.Name)：$($mainLoss.Detail)。下一轮先把这个口子堵上，再谈状态好不好。"
    }

    return [pscustomobject][ordered]@{
        Score = [int]$score
        Grade = $grade
        Verdict = $verdict
        QualityPoints = $qualityPoints
        CompletionPoints = $completionPoints
        RecoveryPoints = $recoveryPoints
        RhythmPoints = $rhythmPoints
        FocusPercent = $focusPercent
        ProgressPercent = $progressPercent
        RecoveryPercent = $recoveryPercent
        OnTaskMinutes = $onMinutes
        OffTaskMinutes = $offMinutes
        IdleMinutes = $idleMinutes
        ActiveMinutes = $activeMinutes
        PausedMinutes = $pausedMinutes
        Analysis = $analysis
        Suggestion = $suggestion
        KeyInsight = $keyInsight
        Evidence = $evidence
        NextAction = $suggestion
        TellOff = $tellOff
        Metrics = "专注范围 $onMinutes 分钟 · 跑偏 $offMinutes 分钟 · 无操作 $idleMinutes 分钟 · 提醒 $ReminderCount 次"
    }
}

function Get-ObjectPropertyValue {
    param($InputObject, [string]$Name, $DefaultValue = $null)
    if ($null -eq $InputObject) { return $DefaultValue }
    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $property -or $null -eq $property.Value) { return $DefaultValue }
    return $property.Value
}

function Get-HistoryOverview {
    param([object[]]$Records)
    $valid = @($Records | Where-Object { $null -ne $_ -and $null -ne (Get-ObjectPropertyValue $_ 'Score') } |
        Sort-Object { try { [DateTime](Get-ObjectPropertyValue $_ 'Timestamp' [DateTime]::MinValue) } catch { [DateTime]::MinValue } })
    if ($valid.Count -eq 0) {
        return [pscustomobject][ordered]@{
            TotalSessions = 0
            AverageScore = '--'
            CompletionRate = '--'
            TotalMinutes = 0
            WeakestDimension = '等待更多数据'
            AccountabilityHeadline = '先积累第一轮真实成绩'
            AccountabilityText = '历史不是装饰。完成一轮后，这里会指出长期趋势和最需要修正的维度。'
            TrendSummary = '至少完成 3 轮后，才会判断趋势。'
            ShortTermInsight = '完成一轮后，这里会先解释最近发生了什么。'
            LongTermInsight = '数据不足时不会硬套结论；先积累真实记录。'
            ReviewStatus = '暂无待复盘记录'
            UnreviewedCount = 0
            RecentRecords = @()
        }
    }

    $scoreTotal = 0.0
    $totalMinutes = 0.0
    $completedCount = 0
    $qualityRateTotal = 0.0
    $completionRateTotal = 0.0
    $recoveryRateTotal = 0.0
    $rhythmRateTotal = 0.0
    $unreviewedCount = 0
    foreach ($record in $valid) {
        $score = [double](Get-ObjectPropertyValue $record 'Score' 0)
        $scoreTotal += $score
        if ([bool](Get-ObjectPropertyValue $record 'Completed' $false)) { $completedCount++ }
        $activeMinutes = Get-ObjectPropertyValue $record 'ActiveMinutes' $null
        if ($null -eq $activeMinutes) {
            $activeMinutes = [double](Get-ObjectPropertyValue $record 'ActiveElapsedSeconds' 0) / 60.0
        }
        $totalMinutes += [double]$activeMinutes
        $qualityRateTotal += [double](Get-ObjectPropertyValue $record 'QualityPoints' 0) / 50.0
        $completionRateTotal += [double](Get-ObjectPropertyValue $record 'CompletionPoints' 0) / 30.0
        $recoveryRateTotal += [double](Get-ObjectPropertyValue $record 'RecoveryPoints' 0) / 10.0
        $rhythmRateTotal += [double](Get-ObjectPropertyValue $record 'RhythmPoints' 0) / 10.0
        $reviewProperty = $record.PSObject.Properties['ReviewedAt']
        if ($score -lt 100 -and $null -ne $reviewProperty -and [string]::IsNullOrWhiteSpace([string]$reviewProperty.Value)) {
            $unreviewedCount++
        }
    }

    $count = $valid.Count
    $averageScore = [int][Math]::Round($scoreTotal / $count)
    $completionPercent = [int][Math]::Round(($completedCount / [double]$count) * 100)
    $dimensions = @(
        [pscustomobject]@{ Name = '专注质量'; Rate = $qualityRateTotal / $count },
        [pscustomobject]@{ Name = '完成进度'; Rate = $completionRateTotal / $count },
        [pscustomobject]@{ Name = '跑偏恢复'; Rate = $recoveryRateTotal / $count },
        [pscustomobject]@{ Name = '节奏连续'; Rate = $rhythmRateTotal / $count }
    )
    $weakest = $dimensions | Sort-Object Rate | Select-Object -First 1
    $weakestPercent = [int][Math]::Round($weakest.Rate * 100)

    $recent = @($valid | Select-Object -Last 10)
    $trendSummary = if ($count -lt 3) {
        "目前只有 $count 轮，样本还不足。先连续完成 3 轮，不要急着给自己下结论。"
    } else {
        $latestCount = [Math]::Min(3, $count)
        $latest = @($valid | Select-Object -Last $latestCount)
        $latestAverage = ($latest | ForEach-Object { [double](Get-ObjectPropertyValue $_ 'Score' 0) } | Measure-Object -Average).Average
        if ($count -ge 6) {
            $comparison = @($valid | Select-Object -Last 6 | Select-Object -First 3)
            $comparisonAverage = ($comparison | ForEach-Object { [double](Get-ObjectPropertyValue $_ 'Score' 0) } | Measure-Object -Average).Average
            $delta = [int][Math]::Round($latestAverage - $comparisonAverage)
            if ($delta -ge 3) {
                "最近 3 轮均分 $([int][Math]::Round($latestAverage))，比之前 3 轮提高 $delta 分。趋势在变好，但别用一次高分提前庆祝。"
            } elseif ($delta -le -3) {
                "最近 3 轮均分 $([int][Math]::Round($latestAverage))，比之前 3 轮下降 $([Math]::Abs($delta)) 分。状态正在滑坡，下一轮必须先修正最大缺口。"
            } else {
                "最近 3 轮均分 $([int][Math]::Round($latestAverage))，与之前基本持平。稳定不等于优秀，继续盯住最弱维度。"
            }
        } else {
            "最近 $latestCount 轮均分 $([int][Math]::Round($latestAverage))。完成 6 轮后会开始比较前后趋势。"
        }
    }

    if ($unreviewedCount -gt 0) {
        $headline = "还有 $unreviewedCount 轮没有完成复盘"
        $accountability = '先处理待复盘记录。带着没看清的问题直接开始下一轮，只是在重复同一种失误。'
        $reviewStatus = "$unreviewedCount 轮待复盘；下次启动仍会要求确认"
    } elseif ($count -lt 3) {
        $headline = '先连续完成 3 轮，再谈稳定性'
        $accountability = "目前只有 $count 轮记录。不要用单次状态证明自己，先建立最小可判断的样本。"
        $reviewStatus = '所有非满分记录均已完成复盘'
    } elseif ($averageScore -lt 70) {
        $headline = "平均只有 $averageScore 分，问题不是偶发"
        $accountability = "最大长期缺口是$($weakest.Name)。下一轮必须先执行建议中的调整，不要继续用同样的设置碰运气。"
        $reviewStatus = '所有非满分记录均已完成复盘'
    } elseif ($completionPercent -lt 70) {
        $headline = "按时完成率只有 $completionPercent%"
        $accountability = '目标设得再漂亮，频繁提前结束也不算兑现。缩小时长或缩小任务，先把完成率拉起来。'
        $reviewStatus = '所有非满分记录均已完成复盘'
    } elseif ($weakestPercent -lt 80) {
        $headline = "$($weakest.Name)长期只有 $weakestPercent%"
        $accountability = '这已经是稳定出现的行为缺口，不是运气。下一轮只抓这一项，直到它不再拖后腿。'
        $reviewStatus = '所有非满分记录均已完成复盘'
    } else {
        $headline = "平均 $averageScore 分，继续用长期表现证明稳定"
        $accountability = '整体表现可靠，但不要拿平均分遮住具体丢分。每一轮仍按结果页建议修正一个最小动作。'
        $reviewStatus = '所有非满分记录均已完成复盘'
    }

    $shortTermInsight = $trendSummary
    $longTermInsight = if ($count -lt 3) {
        "长期样本还不足，目前只确认已记录 $count 轮；继续积累，不把偶然高低分当成习惯。"
    } elseif ($count -lt 6) {
        "目前可见的长期信号是：平均 $averageScore 分、完成率 $completionPercent%，$($weakest.Name)相对更容易丢分。再多完成几轮，判断会更可靠。"
    } elseif ($averageScore -ge 85 -and $completionPercent -ge 85 -and $weakestPercent -ge 80) {
        "你的长期表现已经比较稳定：平均 $averageScore 分、完成率 $completionPercent%。接下来关注波动发生在哪些日期和任务，而不是继续追求空泛的努力。"
    } else {
        "跨越 $count 轮后，$($weakest.Name)仍是重复出现最多的缺口（约 $weakestPercent%）；平均 $averageScore 分、完成率 $completionPercent%。这更像模式，而不是某一轮的偶然。"
    }

    return [pscustomobject][ordered]@{
        TotalSessions = $count
        AverageScore = $averageScore
        CompletionRate = "$completionPercent%"
        TotalMinutes = [int][Math]::Round($totalMinutes)
        WeakestDimension = "$($weakest.Name) · $weakestPercent%"
        AccountabilityHeadline = $headline
        AccountabilityText = $accountability
        TrendSummary = $trendSummary
        ShortTermInsight = $shortTermInsight
        LongTermInsight = $longTermInsight
        ReviewStatus = $reviewStatus
        UnreviewedCount = $unreviewedCount
        RecentRecords = $recent
    }
}

function Get-FocusHeatmapData {
    param(
        [object[]]$Records,
        [DateTime]$EndDate = (Get-Date).Date,
        [int]$Weeks = 18
    )
    $Weeks = [Math]::Max(8, [Math]::Min(26, $Weeks))
    $today = $EndDate.Date
    $currentSunday = $today.AddDays(-[int]$today.DayOfWeek)
    $startDate = $currentSunday.AddDays(-7 * ($Weeks - 1))
    $endGridDate = $currentSunday.AddDays(6)
    $buckets = @{}
    foreach ($record in @($Records)) {
        $timestamp = [DateTime]::MinValue
        try { $timestamp = [DateTime](Get-ObjectPropertyValue $record 'Timestamp' [DateTime]::MinValue) } catch { continue }
        $day = $timestamp.Date
        if ($day -lt $startDate -or $day -gt $today) { continue }
        $key = $day.ToString('yyyy-MM-dd')
        if (-not $buckets.ContainsKey($key)) {
            $buckets[$key] = [ordered]@{ Sessions = 0; ActiveMinutes = 0.0; ScoreTotal = 0.0; Completed = 0; QualityMinutes = 0.0 }
        }
        $active = Get-ObjectPropertyValue $record 'ActiveMinutes' $null
        if ($null -eq $active) { $active = [double](Get-ObjectPropertyValue $record 'ActiveElapsedSeconds' 0) / 60.0 }
        $score = [double](Get-ObjectPropertyValue $record 'Score' 0)
        $bucket = $buckets[$key]
        $bucket.Sessions++
        $bucket.ActiveMinutes += [double]$active
        $bucket.ScoreTotal += $score
        $bucket.QualityMinutes += [double]$active * ($score / 100.0)
        if ([bool](Get-ObjectPropertyValue $record 'Completed' $false)) { $bucket.Completed++ }
    }

    $days = New-Object System.Collections.ArrayList
    $date = $startDate
    while ($date -le $endGridDate) {
        $key = $date.ToString('yyyy-MM-dd')
        $bucket = if ($buckets.ContainsKey($key)) { $buckets[$key] } else { $null }
        $sessions = if ($null -ne $bucket) { [int]$bucket.Sessions } else { 0 }
        $quality = if ($null -ne $bucket) { [double]$bucket.QualityMinutes } else { 0.0 }
        $level = if ($date -gt $today -or $sessions -eq 0) { 0 } elseif ($quality -lt 15) { 1 } elseif ($quality -lt 35) { 2 } elseif ($quality -lt 60) { 3 } else { 4 }
        [void]$days.Add([pscustomobject][ordered]@{
            Date = $date
            Sessions = $sessions
            ActiveMinutes = if ($null -ne $bucket) { [Math]::Round([double]$bucket.ActiveMinutes, 1) } else { 0.0 }
            AverageScore = if ($sessions -gt 0) { [int][Math]::Round([double]$bucket.ScoreTotal / $sessions) } else { 0 }
            Completed = if ($null -ne $bucket) { [int]$bucket.Completed } else { 0 }
            QualityMinutes = [Math]::Round($quality, 1)
            Level = $level
            IsFuture = $date -gt $today
        })
        $date = $date.AddDays(1)
    }
    $activeDays = @($days | Where-Object { -not $_.IsFuture -and $_.Sessions -gt 0 })
    $streak = 0
    $cursor = $today
    if (-not $buckets.ContainsKey($cursor.ToString('yyyy-MM-dd'))) { $cursor = $cursor.AddDays(-1) }
    while ($cursor -ge $startDate -and $buckets.ContainsKey($cursor.ToString('yyyy-MM-dd'))) {
        $streak++
        $cursor = $cursor.AddDays(-1)
    }
    $best = $activeDays | Sort-Object QualityMinutes -Descending | Select-Object -First 1
    $summary = if ($activeDays.Count -eq 0) {
        '这段时间还没有形成可视化记录。颜色按“有效分钟 × 得分质量”计算，不用挂机时长冒充投入。'
    } elseif ($activeDays.Count -lt 4) {
        "近 $Weeks 周有 $($activeDays.Count) 个有效日，样本仍少；先建立连续记录，再判断长期模式。"
    } else {
        $bestText = if ($null -ne $best) { "$($best.Date.ToString('MM月dd日'))质量投入 $([int][Math]::Round($best.QualityMinutes)) 分钟" } else { '暂无最佳日' }
        "近 $Weeks 周有 $($activeDays.Count) 个有效日，当前连续 $streak 天；$bestText。深色代表质量投入更高，不只是坐得更久。"
    }
    return [pscustomobject][ordered]@{
        StartDate = $startDate
        EndDate = $endGridDate
        Days = @($days)
        ActiveDays = $activeDays.Count
        CurrentStreak = $streak
        BestDay = $best
        Summary = $summary
    }
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

function New-EaseOutAnimation {
    param([double]$To, [int]$DurationMs, [double]$From = [double]::NaN)
    if ([double]::IsNaN($From)) {
        $animation = New-Object Windows.Media.Animation.DoubleAnimation($To, [TimeSpan]::FromMilliseconds($DurationMs))
    } else {
        $animation = New-Object Windows.Media.Animation.DoubleAnimation($From, $To, [TimeSpan]::FromMilliseconds($DurationMs))
    }
    $animation.EasingFunction = New-Object Windows.Media.Animation.CubicEase -Property @{ EasingMode = 'EaseOut' }
    return $animation
}

function Set-BrushColorAnimated {
    param($Brush, [string]$ColorHex, [int]$DurationMs = 220)
    if ($null -eq $Brush) { return }
    $target = [Windows.Media.ColorConverter]::ConvertFromString($ColorHex)
    if ($Brush.Color -eq $target) { return }
    $from = $Brush.Color
    $Brush.Color = $target
    $animation = New-Object Windows.Media.Animation.ColorAnimation($from, $target, [TimeSpan]::FromMilliseconds($DurationMs))
    $animation.FillBehavior = [Windows.Media.Animation.FillBehavior]::Stop
    $Brush.BeginAnimation([Windows.Media.SolidColorBrush]::ColorProperty, $animation)
}

function Set-ProgressValue {
    param($ProgressBar, [double]$Target, [int]$DurationMs = 450)
    $current = [double]$ProgressBar.Value
    if ([Math]::Abs($current - $Target) -lt 0.01) { return }
    $ProgressBar.Value = $Target
    $animation = New-EaseOutAnimation -From $current -To $Target -DurationMs $DurationMs
    $animation.FillBehavior = [Windows.Media.Animation.FillBehavior]::Stop
    $ProgressBar.BeginAnimation([Windows.Controls.Primitives.RangeBase]::ValueProperty, $animation)
}

function Reset-ProgressValue {
    param($ProgressBar, [double]$Value = 0)
    $ProgressBar.BeginAnimation([Windows.Controls.Primitives.RangeBase]::ValueProperty, $null)
    $ProgressBar.Value = $Value
}

function Start-WindowEntrance {
    param($Window, [double]$OffsetY = 16, [int]$DurationMs = 260, [switch]$Pop, [switch]$Immediate)
    # Window 不支持 RenderTransform，位移/缩放施加在根内容元素上
    $root = $Window.Content -as [Windows.UIElement]
    $transform = $null
    $scale = $null
    $translate = $null
    if ($null -ne $root) {
        $transform = New-Object Windows.Media.TransformGroup
        $scale = New-Object Windows.Media.ScaleTransform(1, 1)
        $translate = New-Object Windows.Media.TranslateTransform(0, $OffsetY)
        [void]$transform.Children.Add($scale)
        [void]$transform.Children.Add($translate)
        $root.RenderTransform = $transform
        $root.RenderTransformOrigin = New-Object Windows.Point(0.5, 0.5)
    }
    $Window.Opacity = 0
    $duration = [TimeSpan]::FromMilliseconds($DurationMs)
    $fade = New-EaseOutAnimation -From 0 -To 1 -DurationMs $DurationMs
    $rise = New-EaseOutAnimation -From $OffsetY -To 0 -DurationMs $DurationMs
    $scaleAnimation = $null
    if ($Pop -and $null -ne $scale) {
        $scale.ScaleX = 0.96
        $scale.ScaleY = 0.96
        $scaleAnimation = New-Object Windows.Media.Animation.DoubleAnimation(0.96, 1.0, $duration)
        $scaleAnimation.EasingFunction = New-Object Windows.Media.Animation.BackEase -Property @{ EasingMode = 'EaseOut'; Amplitude = 0.4 }
    }
    $begin = {
        $Window.BeginAnimation([Windows.UIElement]::OpacityProperty, $fade)
        if ($null -ne $translate) {
            $translate.BeginAnimation([Windows.Media.TranslateTransform]::YProperty, $rise)
        }
        if ($null -ne $scaleAnimation) {
            $scale.BeginAnimation([Windows.Media.ScaleTransform]::ScaleXProperty, $scaleAnimation)
            $scale.BeginAnimation([Windows.Media.ScaleTransform]::ScaleYProperty, $scaleAnimation)
        }
    }.GetNewClosure()
    if ($Immediate) {
        & $begin
    } else {
        $Window.Add_ContentRendered($begin)
    }
}

function Start-ColumnWidthAnimation {
    param($Column, [double]$Target, [int]$DurationMs = 260)
    $start = [double]$Column.ActualWidth
    if ([Math]::Abs($start - $Target) -lt 2) {
        $Column.Width = New-Object Windows.GridLength $Target
        return
    }
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $animationTimer = New-Object Windows.Threading.DispatcherTimer
    $animationTimer.Interval = [TimeSpan]::FromMilliseconds(15)
    $tick = {
        $elapsed = [Math]::Min(1.0, $stopwatch.ElapsedMilliseconds / [double]$DurationMs)
        $eased = 1.0 - [Math]::Pow(1.0 - $elapsed, 3)
        $Column.Width = New-Object Windows.GridLength ($start + ($Target - $start) * $eased)
        if ($elapsed -ge 1.0) { $animationTimer.Stop() }
    }.GetNewClosure()
    $animationTimer.Add_Tick($tick)
    $animationTimer.Start()
}

function Start-WindowSizeAnimation {
    param($Window, [double]$TargetWidth, [double]$TargetHeight, [int]$DurationMs = 300)
    if ([double]::IsNaN($Window.Width) -or [double]::IsNaN($Window.Height)) {
        $Window.Width = $TargetWidth
        $Window.Height = $TargetHeight
        return
    }
    $fromWidth = [double]$Window.Width
    $fromHeight = [double]$Window.Height
    $Window.Width = $TargetWidth
    $Window.Height = $TargetHeight
    $ease = New-Object Windows.Media.Animation.CubicEase -Property @{ EasingMode = 'EaseInOut' }
    $widthAnimation = New-Object Windows.Media.Animation.DoubleAnimation($fromWidth, $TargetWidth, [TimeSpan]::FromMilliseconds($DurationMs))
    $widthAnimation.EasingFunction = $ease
    $widthAnimation.FillBehavior = [Windows.Media.Animation.FillBehavior]::Stop
    $heightAnimation = New-Object Windows.Media.Animation.DoubleAnimation($fromHeight, $TargetHeight, [TimeSpan]::FromMilliseconds($DurationMs))
    $heightAnimation.EasingFunction = $ease
    $heightAnimation.FillBehavior = [Windows.Media.Animation.FillBehavior]::Stop
    $Window.BeginAnimation([Windows.Window]::WidthProperty, $widthAnimation)
    $Window.BeginAnimation([Windows.Window]::HeightProperty, $heightAnimation)
}

function Start-TextCountUp {
    param($TextBlock, [int]$Target, [int]$DurationMs = 550)
    if ($Target -le 0) {
        $TextBlock.Text = [string]$Target
        return
    }
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $countTimer = New-Object Windows.Threading.DispatcherTimer
    $countTimer.Interval = [TimeSpan]::FromMilliseconds(33)
    $tick = {
        $elapsed = [Math]::Min(1.0, $stopwatch.ElapsedMilliseconds / [double]$DurationMs)
        $eased = 1.0 - [Math]::Pow(1.0 - $elapsed, 3)
        $TextBlock.Text = [string][int][Math]::Round($Target * $eased)
        if ($elapsed -ge 1.0) {
            $TextBlock.Text = [string]$Target
            $countTimer.Stop()
        }
    }.GetNewClosure()
    $countTimer.Add_Tick($tick)
    $countTimer.Start()
}

function Invoke-FocusGuardSelfTest {
    $mainTest = Convert-XamlToWindow -Xaml $MainXaml
    $reminderTest = Convert-XamlToWindow -Xaml $ReminderXaml
    if ($null -eq $SummaryXaml) { throw '缺少 FocusGuard.Summary.xaml' }
    $summaryTest = Convert-XamlToWindow -Xaml $SummaryXaml
    if ($null -eq $HistoryXaml) { throw '缺少 FocusGuard.History.xaml' }
    $historyTest = Convert-XamlToWindow -Xaml $HistoryXaml
    if ($null -eq $script:SharedStyleDictionary) { throw '缺少共享样式 FocusGuard.Styles.xaml' }
    if ($null -eq $mainTest.TryFindResource([Windows.Controls.Primitives.ScrollBar])) { throw '共享滚动条样式未合并到主窗口' }
    $easeTest = New-EaseOutAnimation -From 0 -To 1 -DurationMs 100
    if ($null -eq $easeTest.EasingFunction) { throw '动画辅助函数异常' }
    Start-WindowEntrance -Window $mainTest -Immediate
    Start-WindowEntrance -Window $reminderTest -Pop -Immediate
    if ($null -eq ($mainTest.Content.RenderTransform)) { throw '窗口入场动画未施加到根内容元素' }
    foreach ($xamlDoc in @($MainXaml, $ReminderXaml, $SummaryXaml, $HistoryXaml)) {
        if ($null -ne $xamlDoc -and $xamlDoc.OuterXml -match 'FillBehavior="Stop"') { throw 'XAML 交互态动画禁止使用 FillBehavior=Stop（播完弹回导致闪烁）' }
    }
    $stylesRaw = Get-Content -LiteralPath $stylesXamlPath -Raw -Encoding UTF8
    if ($stylesRaw -match 'FillBehavior="Stop"') { throw '共享样式禁止使用 FillBehavior=Stop（播完弹回导致闪烁）' }
    if (-not (Find-Control $mainTest 'StartButton')) { throw '主窗口缺少 StartButton' }
    if (-not (Find-Control $mainTest 'SessionProgress')) { throw '主窗口缺少 SessionProgress' }
    if (-not (Find-Control $mainTest 'Duration25Button')) { throw '主窗口缺少快捷时长按钮' }
    if (-not (Find-Control $mainTest 'ResetSettingsButton')) { throw '主窗口缺少推荐参数按钮' }
    if (-not (Find-Control $mainTest 'EndBreakButton')) { throw '主窗口缺少结束休息按钮' }
    if (-not (Find-Control $mainTest 'ExitButton')) { throw '主窗口缺少 ExitButton' }
    if (-not (Find-Control $mainTest 'HistoryButton')) { throw '主窗口缺少 HistoryButton' }
    if (-not (Find-Control $mainTest 'AllowedAppsList')) { throw '主窗口缺少结构化应用规则列表' }
    if (-not (Find-Control $mainTest 'StartWithWindowsCheck')) { throw '主窗口缺少开机启动选项' }
    if (-not (Find-Control $mainTest 'SettingsColumn')) { throw '主窗口缺少可调设置面板' }
    if (-not (Find-Control $mainTest 'MainPaneSplitter')) { throw '主窗口缺少即时拖动把手' }
    if (-not (Find-Control $reminderTest 'ReturnButton')) { throw '提醒窗口缺少 ReturnButton' }
    if (-not (Find-Control $summaryTest 'ScoreLabel')) { throw '分析窗口缺少 ScoreLabel' }
    if (-not (Find-Control $summaryTest 'TellOffLabel')) { throw '分析窗口缺少 TellOffLabel' }
    if (-not (Find-Control $summaryTest 'ReviewAcknowledgeCheck')) { throw '分析窗口缺少复盘确认控件' }
    if (-not (Find-Control $summaryTest 'KeyInsightLabel')) { throw '分析窗口缺少自适应重点结论' }
    if (-not (Find-Control $historyTest 'HistoryList')) { throw '历史窗口缺少 HistoryList' }
    if (-not (Find-Control $historyTest 'TrendBarsPanel')) { throw '历史窗口缺少趋势面板' }
    if (-not (Find-Control $historyTest 'HeatmapGrid')) { throw '历史窗口缺少质量投入轨迹' }
    if (-not (Find-Control $historyTest 'HistoryInsightColumn')) { throw '历史窗口缺少可调分析面板' }
    if (-not (Find-Control $historyTest 'HistoryPaneSplitter')) { throw '历史窗口缺少即时拖动把手' }
    $ruleListTest = Find-Control $mainTest 'AllowedAppsList'
    Set-RuleItems $ruleListTest @('code', 'CODE', 'winword')
    if (@(Get-RuleItems $ruleListTest).Count -ne 2) { throw '允许范围去重测试失败' }
    if (-not (Add-RuleItem $ruleListTest 'C:\Apps\PowerPoint.exe' -ProcessName)) { throw '应用路径规范化测试失败' }
    if (Add-RuleItem $ruleListTest 'powerpoint.exe' -ProcessName) { throw '允许范围大小写去重测试失败' }
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
    $perfectScore = Get-SessionEvaluation -PlannedSeconds 1500 -ActiveElapsedSeconds 1500 -OnTaskSeconds 1500 -OffTaskSeconds 0 -IdleSeconds 0 -ReminderCount 0 -RecoveryCount 0 -PauseCount 0 -BreakCount 0 -PausedSeconds 0 -Completed $true
    if ($perfectScore.Score -ne 100 -or $perfectScore.TellOff) { throw '满分评分测试失败' }
    $imperfectScore = Get-SessionEvaluation -PlannedSeconds 1500 -ActiveElapsedSeconds 900 -OnTaskSeconds 700 -OffTaskSeconds 140 -IdleSeconds 60 -ReminderCount 2 -RecoveryCount 1 -PauseCount 1 -BreakCount 0 -PausedSeconds 30 -Completed $false
    if ($imperfectScore.Score -ge 100 -or -not $imperfectScore.TellOff) { throw '非满分训话测试失败' }
    if (-not $imperfectScore.KeyInsight -or -not $imperfectScore.Evidence -or -not $imperfectScore.NextAction) { throw '短期自适应分析测试失败' }
    $historyOverview = Get-HistoryOverview -Records @(
        [pscustomobject]@{ Timestamp = (Get-Date).AddHours(-3).ToString('o'); Score = 100; Completed = $true; ActiveMinutes = 25; QualityPoints = 50; CompletionPoints = 30; RecoveryPoints = 10; RhythmPoints = 10; ReviewedAt = '' },
        [pscustomobject]@{ Timestamp = (Get-Date).AddHours(-2).ToString('o'); Score = 80; Completed = $true; ActiveMinutes = 25; QualityPoints = 40; CompletionPoints = 30; RecoveryPoints = 5; RhythmPoints = 5; ReviewedAt = (Get-Date).ToString('o') },
        [pscustomobject]@{ Timestamp = (Get-Date).AddHours(-1).ToString('o'); Score = 60; Completed = $false; ActiveMinutes = 15; QualityPoints = 30; CompletionPoints = 18; RecoveryPoints = 6; RhythmPoints = 6; ReviewedAt = '' }
    )
    if ($historyOverview.TotalSessions -ne 3 -or $historyOverview.AverageScore -ne 80) { throw '历史汇总统计测试失败' }
    if ($historyOverview.UnreviewedCount -ne 1) { throw '待复盘统计测试失败' }
    if (-not $historyOverview.ShortTermInsight -or -not $historyOverview.LongTermInsight) { throw '长短期分析测试失败' }
    $heatmapTest = Get-FocusHeatmapData -Records @(
        [pscustomobject]@{ Timestamp = (Get-Date).Date.AddDays(-1).AddHours(8).ToString('o'); Score = 80; ActiveMinutes = 30; Completed = $true },
        [pscustomobject]@{ Timestamp = (Get-Date).Date.AddDays(-1).AddHours(10).ToString('o'); Score = 100; ActiveMinutes = 30; Completed = $true }
    ) -Weeks 18
    $heatmapActiveDay = @($heatmapTest.Days | Where-Object { $_.Sessions -eq 2 })
    if ($heatmapTest.ActiveDays -ne 1 -or $heatmapActiveDay.Count -ne 1 -or $heatmapActiveDay[0].QualityMinutes -ne 54) { throw '质量投入轨迹聚合测试失败' }
    if ((Get-AutoStartCommand -Root 'C:\Focus Guard') -notmatch '/minimized') { throw '开机启动命令测试失败' }
    $historyJson = ConvertTo-Json -InputObject @($historyOverview.RecentRecords) -Depth 6
    $historyParsed = $historyJson | ConvertFrom-Json
    if (@($historyParsed).Count -ne 3) { throw '历史 JSON 数组往返测试失败' }
    if ($script:FocusGuardVersion -notmatch '^\d+\.\d+\.\d+$') { throw '版本号格式异常' }
    $idle = [FocusGuardNative]::IdleSeconds()
    Write-Output "FocusGuard self-test passed. IdleSeconds=$([Math]::Round($idle, 1))"
    $mainTest.Close()
    $reminderTest.Close()
    $summaryTest.Close()
    $historyTest.Close()
}