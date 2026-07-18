#requires -Version 5.1
# 单元测试：需要 Pester 5.x 与 Windows PowerShell 5.1（STA）。
# 运行：Invoke-Pester -Path .\tests
BeforeAll {
    . (Join-Path (Join-Path $PSScriptRoot '..') 'FocusGuard.Core.ps1')
}

Describe 'Test-SnapshotAllowed 规则匹配' {
    It '进程名匹配忽略大小写并允许带 .exe 后缀' {
        Test-SnapshotAllowed -ProcessName 'CODE' -Title '任意窗口' -AllowedApps @('code.exe') -AllowedTitles @() | Should -BeTrue
    }
    It '窗口标题包含关键词时放行' {
        Test-SnapshotAllowed -ProcessName 'chrome' -Title '课程 - Chrome' -AllowedApps @() -AllowedTitles @('课程') | Should -BeTrue
    }
    It '进程和标题都不命中时判定跑偏' {
        Test-SnapshotAllowed -ProcessName 'chrome' -Title '短视频 - Chrome' -AllowedApps @('code') -AllowedTitles @('课程') | Should -BeFalse
    }
    It '任务名（长度至少 2）出现在标题中也算在范围内' {
        Test-SnapshotAllowed -ProcessName 'winword' -Title '季度总结 - Word' -AllowedApps @('code') -AllowedTitles @() -TaskName '季度总结' | Should -BeTrue
    }
    It '任务名只有一个字时不参与匹配' {
        Test-SnapshotAllowed -ProcessName 'winword' -Title '写 - Word' -AllowedApps @('code') -AllowedTitles @() -TaskName '写' | Should -BeFalse
    }
    It '两条规则都为空时全部放行' {
        Test-SnapshotAllowed -ProcessName 'anything' -Title 'whatever' -AllowedApps @() -AllowedTitles @() | Should -BeTrue
    }
}

Describe 'Get-SessionEvaluation 评分' {
    It '全部守住的轮次得 100 分且无训话' {
        $r = Get-SessionEvaluation -PlannedSeconds 1500 -ActiveElapsedSeconds 1500 -OnTaskSeconds 1500 -OffTaskSeconds 0 -IdleSeconds 0 -ReminderCount 0 -RecoveryCount 0 -PauseCount 0 -BreakCount 0 -PausedSeconds 0 -Completed $true
        $r.Score | Should -Be 100
        $r.TellOff | Should -BeNullOrEmpty
        $r.Grade | Should -Be 'S · 极稳'
    }
    It '99.9% 的专注占比不能进位成满分' {
        $r = Get-SessionEvaluation -PlannedSeconds 1000 -ActiveElapsedSeconds 1000 -OnTaskSeconds 999 -OffTaskSeconds 1 -IdleSeconds 0 -ReminderCount 0 -RecoveryCount 0 -PauseCount 0 -BreakCount 0 -PausedSeconds 0 -Completed $true
        $r.QualityPoints | Should -Be 49
        $r.Score | Should -Be 99
    }
    It '提醒后只恢复一部分时按恢复率给分' {
        $r = Get-SessionEvaluation -PlannedSeconds 1000 -ActiveElapsedSeconds 1000 -OnTaskSeconds 1000 -OffTaskSeconds 0 -IdleSeconds 0 -ReminderCount 4 -RecoveryCount 1 -PauseCount 0 -BreakCount 0 -PausedSeconds 0 -Completed $true
        $r.RecoveryPoints | Should -Be 2
        $r.Score | Should -Be 92
    }
    It '多次暂停且暂停时间占比高时节奏分清零' {
        $r = Get-SessionEvaluation -PlannedSeconds 600 -ActiveElapsedSeconds 600 -OnTaskSeconds 600 -OffTaskSeconds 0 -IdleSeconds 0 -ReminderCount 0 -RecoveryCount 0 -PauseCount 5 -BreakCount 0 -PausedSeconds 600 -Completed $true
        $r.RhythmPoints | Should -Be 0
        $r.Score | Should -Be 90
    }
    It '提前结束只按实际推进给完成分，并指出计划未兑现' {
        $r = Get-SessionEvaluation -PlannedSeconds 1500 -ActiveElapsedSeconds 750 -OnTaskSeconds 750 -OffTaskSeconds 0 -IdleSeconds 0 -ReminderCount 0 -RecoveryCount 0 -PauseCount 0 -BreakCount 0 -PausedSeconds 0 -Completed $false
        $r.CompletionPoints | Should -Be 15
        $r.ProgressPercent | Should -Be 50
        $r.Score | Should -Be 85
        $r.TellOff | Should -Not -BeNullOrEmpty
        $r.KeyInsight | Should -Match '计划'
    }
    It '完成但没有任何采样时如实说明数据不足' {
        $r = Get-SessionEvaluation -PlannedSeconds 900 -ActiveElapsedSeconds 900 -OnTaskSeconds 0 -OffTaskSeconds 0 -IdleSeconds 0 -ReminderCount 0 -RecoveryCount 0 -PauseCount 0 -BreakCount 0 -PausedSeconds 0 -Completed $true
        $r.Score | Should -Be 50
        $r.KeyInsight | Should -Match '数据'
    }
}

Describe 'Get-HistoryOverview 历史汇总' {
    It '没有记录时保留判断' {
        $o = Get-HistoryOverview -Records @()
        $o.TotalSessions | Should -Be 0
        $o.AverageScore | Should -Be '--'
        $o.UnreviewedCount | Should -Be 0
        @($o.RecentRecords).Count | Should -Be 0
    }
    It '统计均分、完成率、累计时长与待复盘数量' {
        $records = @(
            [pscustomobject]@{ Timestamp = (Get-Date).AddHours(-3).ToString('o'); Score = 100; Completed = $true; ActiveMinutes = 25; QualityPoints = 50; CompletionPoints = 30; RecoveryPoints = 10; RhythmPoints = 10; ReviewedAt = '' },
            [pscustomobject]@{ Timestamp = (Get-Date).AddHours(-2).ToString('o'); Score = 80; Completed = $true; ActiveMinutes = 25; QualityPoints = 40; CompletionPoints = 30; RecoveryPoints = 5; RhythmPoints = 5; ReviewedAt = (Get-Date).ToString('o') },
            [pscustomobject]@{ Timestamp = (Get-Date).AddHours(-1).ToString('o'); Score = 60; Completed = $false; ActiveMinutes = 15; QualityPoints = 30; CompletionPoints = 18; RecoveryPoints = 6; RhythmPoints = 6; ReviewedAt = '' }
        )
        $o = Get-HistoryOverview -Records $records
        $o.TotalSessions | Should -Be 3
        $o.AverageScore | Should -Be 80
        $o.CompletionRate | Should -Be '67%'
        $o.TotalMinutes | Should -Be 65
        $o.UnreviewedCount | Should -Be 1
        @($o.RecentRecords).Count | Should -Be 3
    }
    It '样本足够时指出前后趋势变化' {
        $records = foreach ($s in @(60, 60, 60, 90, 90, 90)) {
            [pscustomobject]@{ Timestamp = (Get-Date).AddHours(-6 + [array]::IndexOf(@(60, 60, 60, 90, 90, 90), $s)).ToString('o'); Score = $s; Completed = $true; ActiveMinutes = 25; QualityPoints = 50; CompletionPoints = 30; RecoveryPoints = 10; RhythmPoints = 10; ReviewedAt = '已复盘' }
        }
        $o = Get-HistoryOverview -Records $records
        $o.TrendSummary | Should -Match '提高'
    }
}

Describe 'Get-FocusHeatmapData 质量投入轨迹' {
    It '按“有效分钟 × 得分”聚合当天质量投入' {
        $h = Get-FocusHeatmapData -Weeks 18 -Records @(
            [pscustomobject]@{ Timestamp = (Get-Date).Date.AddDays(-1).AddHours(8).ToString('o'); Score = 80; ActiveMinutes = 30; Completed = $true },
            [pscustomobject]@{ Timestamp = (Get-Date).Date.AddDays(-1).AddHours(10).ToString('o'); Score = 100; ActiveMinutes = 30; Completed = $true }
        )
        $h.ActiveDays | Should -Be 1
        $day = @($h.Days | Where-Object { $_.Sessions -eq 2 })
        $day.Count | Should -Be 1
        $day[0].QualityMinutes | Should -Be 54
        $h.CurrentStreak | Should -Be 1
    }
    It '未来日期不上色，周数被夹在 8 到 26' {
        $h = Get-FocusHeatmapData -Records @() -Weeks 2
        @($h.Days).Count | Should -Be 56
        @($h.Days | Where-Object { $_.IsFuture -and $_.Level -ne 0 }).Count | Should -Be 0
    }
}

Describe 'New-ReminderCopy 提醒文案' {
    It '连续生成不重复' {
        $keys = New-Object 'System.Collections.Generic.HashSet[string]'
        1..200 | ForEach-Object {
            $copy = New-ReminderCopy -Reason 'offtask' -Tone '直接' -Task '测试任务' -UsedKeys $keys
            $keys.Add($copy.Key) | Should -BeTrue
        }
    }
    It '任务为空时使用兜底称呼' {
        $copy = New-ReminderCopy -Reason 'idle' -Tone '温和' -Task '' -UsedKeys (New-Object 'System.Collections.Generic.HashSet[string]')
        $copy.Text | Should -Match '你刚才定下的任务'
    }
    It '文案池耗尽时明确报错而不是重复' {
        $keys = New-Object 'System.Collections.Generic.HashSet[string]'
        foreach ($o in 0..7) { foreach ($c in 0..7) { foreach ($a in 0..7) { foreach ($cl in 0..7) {
            [void]$keys.Add("offtask|暴躁|$o|$c|$a|$cl")
        } } } }
        { New-ReminderCopy -Reason 'offtask' -Tone '暴躁' -Task '测试' -UsedKeys $keys } | Should -Throw '48 小时提醒文案池已用尽'
    }
}

Describe 'Get-TabooMatch 禁忌词匹配' {
    It '窗口标题包含禁忌词时命中' {
        Get-TabooMatch -ProcessName 'chrome' -Title '搞笑短视频 - Chrome' -TabooWords @('短视频') | Should -Be '短视频'
    }
    It '进程名等值命中且忽略大小写与 .exe 后缀' {
        Get-TabooMatch -ProcessName 'TikTok' -Title 'TikTok' -TabooWords @('tiktok.exe') | Should -Be 'tiktok.exe'
    }
    It '进程名只做等值匹配，不做包含匹配' {
        Get-TabooMatch -ProcessName 'tiktokhelper' -Title '无关' -TabooWords @('tiktok') | Should -BeNullOrEmpty
    }
    It '进程和标题都不命中时返回空' {
        Get-TabooMatch -ProcessName 'code' -Title '课程文档' -TabooWords @('短视频') | Should -BeNullOrEmpty
    }
    It '禁忌词列表为空时不命中' {
        Get-TabooMatch -ProcessName 'chrome' -Title '短视频' -TabooWords @() | Should -BeNullOrEmpty
    }
}

Describe 'Get-TabooLockSeconds 锁定秒数递增' {
    It '锁定秒数 = 基础秒数 × 当天触发次数' {
        Get-TabooLockSeconds -BaseSeconds 15 -Strike 1 | Should -Be 15
        Get-TabooLockSeconds -BaseSeconds 15 -Strike 2 | Should -Be 30
        Get-TabooLockSeconds -BaseSeconds 15 -Strike 3 | Should -Be 45
    }
    It '基础秒数低于 5 时被夹到 5' {
        Get-TabooLockSeconds -BaseSeconds 3 -Strike 1 | Should -Be 5
    }
    It '基础秒数 10 秒以内可直接使用' {
        Get-TabooLockSeconds -BaseSeconds 10 -Strike 1 | Should -Be 10
        Get-TabooLockSeconds -BaseSeconds 8 -Strike 2 | Should -Be 16
    }
    It '乘积超过 3600 时被夹到 3600' {
        Get-TabooLockSeconds -BaseSeconds 3600 -Strike 5 | Should -Be 3600
    }
}

Describe 'Get-IntSetting 数值输入' {
    It '非法输入回退默认值，越界夹取上下限' {
        Get-IntSetting ([pscustomobject]@{ Text = 'abc' }) 180 30 3600 | Should -Be 180
        Get-IntSetting ([pscustomobject]@{ Text = '99999' }) 180 30 3600 | Should -Be 3600
        Get-IntSetting ([pscustomobject]@{ Text = '5' }) 180 30 3600 | Should -Be 30
        Get-IntSetting ([pscustomobject]@{ Text = ' 240 ' }) 180 30 3600 | Should -Be 240
    }
}

Describe '允许范围列表维护' {
    It '去重、路径规范化与大小写不敏感' {
        $list = New-Object System.Windows.Controls.ListBox
        Set-RuleItems $list @('code', 'CODE', 'winword')
        @(Get-RuleItems $list).Count | Should -Be 2
        Add-RuleItem $list 'C:\Apps\PowerPoint.exe' -ProcessName | Should -BeTrue
        Add-RuleItem $list 'powerpoint.exe' -ProcessName | Should -BeFalse
        Add-RuleItem $list '' | Should -BeFalse
        @(Get-RuleItems $list).Count | Should -Be 3
    }
}
