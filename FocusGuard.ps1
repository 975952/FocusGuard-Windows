param(
    [switch]$SelfTest,
    [switch]$StartMinimized
)

$focusGuardPartFiles = @(
    'FocusGuard.Core.ps1',
    'FocusGuard.Data.ps1',
    'FocusGuard.Session.ps1',
    'FocusGuard.App.ps1'
)

foreach ($focusGuardPart in $focusGuardPartFiles) {
    $focusGuardPartPath = Join-Path $PSScriptRoot $focusGuardPart
    if (-not (Test-Path -LiteralPath $focusGuardPartPath)) { throw "缺少 $focusGuardPart" }
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($focusGuardPartPath, [ref]$tokens, [ref]$errors)
    if ($errors.Count -gt 0) { throw ($errors | Select-Object -First 1).ToString() }
}

if ($SelfTest) {
    . (Join-Path $PSScriptRoot 'FocusGuard.Core.ps1')
    Invoke-FocusGuardSelfTest
    exit 0
}

foreach ($focusGuardPart in $focusGuardPartFiles) {
    . (Join-Path $PSScriptRoot $focusGuardPart)
}
