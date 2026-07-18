$ErrorActionPreference = 'Stop'
$d = 'C:\Users\Wang Wenbo\AppData\Local\Temp\fg-splash-test\FocusGuard-Windows-v1.4.8'
$exe = Join-Path $d 'FocusGuard.exe'
$sw = [Diagnostics.Stopwatch]::StartNew()
$main = Start-Process -FilePath $exe -PassThru
$splashAt = $null
$mainAt = $null
$splashClosedAt = $null
while ($sw.Elapsed.TotalSeconds -lt 30) {
    if ($null -eq $splashAt) {
        $sp = Get-Process -Name 'FocusGuard.Splash' -ErrorAction SilentlyContinue
        if ($sp -and $sp.MainWindowHandle -ne 0) { $splashAt = $sw.ElapsedMilliseconds }
    }
    if ($null -eq $mainAt) {
        $main.Refresh()
        if ($main.MainWindowHandle -ne 0) { $mainAt = $sw.ElapsedMilliseconds }
    }
    if ($null -ne $splashAt -and $null -eq $splashClosedAt) {
        $sp2 = Get-Process -Name 'FocusGuard.Splash' -ErrorAction SilentlyContinue
        if (-not $sp2) { $splashClosedAt = $sw.ElapsedMilliseconds }
    }
    if ($null -ne $mainAt -and $null -ne $splashClosedAt) { break }
    Start-Sleep -Milliseconds 30
}
Write-Output ("splash=" + $splashAt + "ms main=" + $mainAt + "ms splashClosed=" + $splashClosedAt + "ms")
Start-Sleep -Milliseconds 500
if (-not $main.HasExited) { [void]$main.CloseMainWindow() }
Start-Sleep -Seconds 2
if (-not $main.HasExited) { $main.Kill() }
Get-Process -Name 'FocusGuard.Splash' -ErrorAction SilentlyContinue | Stop-Process -Force
