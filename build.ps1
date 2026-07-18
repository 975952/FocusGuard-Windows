#requires -Version 5.0
<#
.SYNOPSIS
    专注守卫发布打包：自检 -> Pester -> 预编译原生 DLL -> 合并脚本编译 exe -> 生成 dist\FocusGuard-Windows-v<版本>.zip
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

Write-Host '[1/5] 运行应用自检...'
& powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File (Join-Path $root 'FocusGuard.ps1') -SelfTest
if ($LASTEXITCODE -ne 0) { throw '自检失败，已取消打包。' }

if ($SkipTests) {
    Write-Host '[2/5] 按参数跳过单元测试'
} else {
    $pester = Get-Module -ListAvailable Pester | Sort-Object Version -Descending | Select-Object -First 1
    if ($null -ne $pester -and $pester.Version -ge [version]'5.0.0') {
        Write-Host "[2/5] 运行 Pester $($pester.Version) 单元测试..."
        Import-Module Pester -MinimumVersion 5.0.0
        $result = Invoke-Pester -Path (Join-Path $root 'tests') -PassThru
        if ($result.FailedCount -gt 0) { throw "单元测试失败 $($result.FailedCount) 个，已取消打包。" }
    } else {
        Write-Host '[2/5] 未安装 Pester 5.x+，跳过单元测试（安装：Install-Module Pester -Scope CurrentUser -Force -SkipPublisherCheck）'
    }
}

$coreText = Get-Content -LiteralPath (Join-Path $root 'FocusGuard.Core.ps1') -Raw -Encoding UTF8
if ($coreText -notmatch "\`$script:FocusGuardVersion = '([^']+)'") {
    throw '未在 FocusGuard.Core.ps1 中找到 $script:FocusGuardVersion 版本号。'
}
$version = $Matches[1]

$distDir = Join-Path $root 'dist'
if (-not (Test-Path -LiteralPath $distDir)) { New-Item -ItemType Directory -Path $distDir | Out-Null }
$zipPath = Join-Path $distDir "FocusGuard-Windows-v$version.zip"
if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
$staging = Join-Path $distDir "FocusGuard-Windows-v$version"
if (Test-Path -LiteralPath $staging) { Remove-Item -LiteralPath $staging -Recurse -Force }
New-Item -ItemType Directory -Path $staging | Out-Null

Write-Host '[3/5] 预编译原生互操作 DLL 与启动画面...'
$nativeSource = Get-Content -LiteralPath (Join-Path $root 'FocusGuard.Native.cs') -Raw -Encoding UTF8
Add-Type -TypeDefinition $nativeSource -ReferencedAssemblies 'System.Windows.Forms.dll' `
    -OutputAssembly (Join-Path $staging 'FocusGuard.Native.dll') -OutputType Library
$splashSource = Get-Content -LiteralPath (Join-Path $root 'FocusGuard.Splash.cs') -Raw -Encoding UTF8
Add-Type -TypeDefinition $splashSource -ReferencedAssemblies @('PresentationFramework', 'PresentationCore', 'WindowsBase', 'System.Xaml') `
    -OutputAssembly (Join-Path $staging 'FocusGuard.Splash.exe') -OutputType WindowsApplication

Write-Host '[4/5] 合并脚本并编译 exe...'
# 合并入口与四个分部为单一脚本（ps2exe 只接受单文件）；exe 启动时跳过入口的逐文件语法预检。
$mergedPath = Join-Path $env:TEMP 'FocusGuard.Merged.ps1'
$builder = New-Object System.Text.StringBuilder
[void]$builder.AppendLine('param(')
[void]$builder.AppendLine('    [switch]$SelfTest,')
[void]$builder.AppendLine('    [switch]$StartMinimized')
[void]$builder.AppendLine(')')
[void]$builder.AppendLine('')
# ps2exe 编译的 exe 内 $PSScriptRoot 为空，回退到 exe 自身所在目录
[void]$builder.AppendLine('if ([string]::IsNullOrEmpty($PSScriptRoot)) {')
[void]$builder.AppendLine('    $PSScriptRoot = [System.IO.Path]::GetDirectoryName([System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName)')
[void]$builder.AppendLine('}')
[void]$builder.AppendLine('')
foreach ($part in @('FocusGuard.Core.ps1', 'FocusGuard.Data.ps1', 'FocusGuard.Session.ps1', 'FocusGuard.App.ps1')) {
    $partText = Get-Content -LiteralPath (Join-Path $root $part) -Raw -Encoding UTF8
    [void]$builder.AppendLine($partText.TrimStart([char]0xFEFF))
}
[System.IO.File]::WriteAllText($mergedPath, $builder.ToString(), (New-Object System.Text.UTF8Encoding($true)))

# exe 图标复用应用运行时同一套绘制逻辑
. (Join-Path $root 'FocusGuard.Core.ps1')
$iconPath = Join-Path $env:TEMP 'FocusGuard.App.ico'
$appIcon = New-FocusGuardIcon
$iconStream = [System.IO.File]::Create($iconPath)
$appIcon.Save($iconStream)
$iconStream.Close()
$appIcon.Dispose()

if (-not (Get-Module -ListAvailable ps2exe)) { throw '缺少 ps2exe 模块：Install-Module ps2exe -Scope CurrentUser -Force -SkipPublisherCheck' }
Import-Module ps2exe
Invoke-ps2exe -inputFile $mergedPath -outputFile (Join-Path $staging 'FocusGuard.exe') `
    -iconFile $iconPath -noConsole -noOutput -noError -STA `
    -title '专注守卫' -product 'FocusGuard' -version $version | Out-Null
Remove-Item -LiteralPath $mergedPath -Force
Remove-Item -LiteralPath $iconPath -Force

Write-Host '[5/5] 打包...'
$files = @(
    'FocusGuard.ps1',
    'FocusGuard.Core.ps1',
    'FocusGuard.Data.ps1',
    'FocusGuard.Session.ps1',
    'FocusGuard.App.ps1',
    'FocusGuard.Native.cs',
    'FocusGuard.Splash.cs',
    'FocusGuard.Main.xaml',
    'FocusGuard.Reminder.xaml',
    'FocusGuard.Taboo.xaml',
    'FocusGuard.Summary.xaml',
    'FocusGuard.History.xaml',
    'FocusGuard.Styles.xaml',
    '启动专注守卫.vbs',
    '启动专注守卫.cmd',
    'README.md'
)
foreach ($file in $files) {
    if (-not (Test-Path -LiteralPath (Join-Path $root $file))) { throw "缺少发布文件：$file" }
    Copy-Item -LiteralPath (Join-Path $root $file) -Destination (Join-Path $staging $file)
}
Compress-Archive -Path $staging -DestinationPath $zipPath -CompressionLevel Optimal
Remove-Item -LiteralPath $staging -Recurse -Force

Write-Host "完成：$zipPath"
