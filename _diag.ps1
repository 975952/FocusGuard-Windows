$existing = $null
if ([System.Threading.Mutex]::TryOpenExisting('Local\FocusGuardCN_SingleInstance', [ref]$existing)) {
    Write-Output 'MUTEX: old instance still running'
    $existing.Dispose()
} else {
    Write-Output 'MUTEX: no instance running'
}
$log = Join-Path $env:APPDATA 'FocusGuardCN\focusguard.log'
if (Test-Path $log) {
    Write-Output '--- last 15 log lines ---'
    Get-Content $log -Tail 15 -Encoding UTF8
} else {
    Write-Output 'no log file'
}
