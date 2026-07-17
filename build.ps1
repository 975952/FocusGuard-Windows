#requires -Version 5.0
<#
.SYNOPSIS
    专注守卫发布打包：自检 -> Pester 单元测试（若已安装 5.x+）-> 生成 dist\FocusGuard-Windows-v<版本>.zip
.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -STA -File build.ps1
#>
param(
    [switch]$SkipTests
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

# 构建统一在 Windows PowerShell 5.1（STA）下进行，与应用运行环境一致。
if ($PSVersionTable.PSVersion.Major -ne 5) {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File $PSCommandPath -SkipTests:$SkipTests
    exit $LASTEXITCODE
}

$root = $PSScriptRoot

Write-Host '[1/3] 运行应用自检...'
& powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File (Join-Path $root 'FocusGuard.ps1') -SelfTest
if ($LASTEXITCODE -ne 0) { throw '自检失败，已取消打包。' }

if ($SkipTests) {
    Write-Host '[2/3] 按参数跳过单元测试'
} else {
    $pester = Get-Module -ListAvailable Pester | Sort-Object Version -Descending | Select-Object -First 1
    if ($null -ne $pester -and $pester.Version -ge [version]'5.0.0') {
        Write-Host "[2/3] 运行 Pester $($pester.Version) 单元测试..."
        Import-Module Pester -MinimumVersion 5.0.0
        $result = Invoke-Pester -Path (Join-Path $root 'tests') -PassThru
        if ($result.FailedCount -gt 0) { throw "单元测试失败 $($result.FailedCount) 个，已取消打包。" }
    } else {
        Write-Host '[2/3] 未安装 Pester 5.x+，跳过单元测试（安装：Install-Module Pester -Scope CurrentUser -Force -SkipPublisherCheck）'
    }
}

Write-Host '[3/3] 打包...'
$coreText = Get-Content -LiteralPath (Join-Path $root 'FocusGuard.Core.ps1') -Raw -Encoding UTF8
if ($coreText -notmatch "\`$script:FocusGuardVersion = '([^']+)'") {
    throw '未在 FocusGuard.Core.ps1 中找到 $script:FocusGuardVersion 版本号。'
}
$version = $Matches[1]

$files = @(
    'FocusGuard.ps1',
    'FocusGuard.Core.ps1',
    'FocusGuard.Data.ps1',
    'FocusGuard.Session.ps1',
    'FocusGuard.App.ps1',
    'FocusGuard.Main.xaml',
    'FocusGuard.Reminder.xaml',
    'FocusGuard.Summary.xaml',
    'FocusGuard.History.xaml',
    'FocusGuard.Styles.xaml',
    '启动专注守卫.vbs',
    '启动专注守卫.cmd',
    'README.md'
)
foreach ($file in $files) {
    if (-not (Test-Path -LiteralPath (Join-Path $root $file))) { throw "缺少发布文件：$file" }
}

$distDir = Join-Path $root 'dist'
if (-not (Test-Path -LiteralPath $distDir)) { New-Item -ItemType Directory -Path $distDir | Out-Null }
$zipPath = Join-Path $distDir "FocusGuard-Windows-v$version.zip"
if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }

$staging = Join-Path $distDir "FocusGuard-Windows-v$version"
if (Test-Path -LiteralPath $staging) { Remove-Item -LiteralPath $staging -Recurse -Force }
New-Item -ItemType Directory -Path $staging | Out-Null
foreach ($file in $files) {
    Copy-Item -LiteralPath (Join-Path $root $file) -Destination (Join-Path $staging $file)
}
Compress-Archive -Path $staging -DestinationPath $zipPath -CompressionLevel Optimal
Remove-Item -LiteralPath $staging -Recurse -Force

Write-Host "完成：$zipPath"
