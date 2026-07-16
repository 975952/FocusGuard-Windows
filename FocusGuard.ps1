param(
    [switch]$SelfTest,
    [switch]$StartMinimized
)

$focusGuardPartFiles = @(
    'FocusGuard.Part1.ps1',
    'FocusGuard.Part2.ps1',
    'FocusGuard.Part3.ps1',
    'FocusGuard.Part4.ps1'
)

if ($SelfTest) {
    foreach ($focusGuardPart in $focusGuardPartFiles) {
        $focusGuardPartPath = Join-Path $PSScriptRoot $focusGuardPart
        if (-not (Test-Path -LiteralPath $focusGuardPartPath)) { throw "缺少 $focusGuardPart" }
        $tokens = $null
        $errors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($focusGuardPartPath, [ref]$tokens, [ref]$errors)
        if ($errors.Count -gt 0) { throw ($errors | Select-Object -First 1).ToString() }
    }
    . (Join-Path $PSScriptRoot 'FocusGuard.Part1.ps1')
    exit 0
}

foreach ($focusGuardPart in $focusGuardPartFiles) {
    $focusGuardPartPath = Join-Path $PSScriptRoot $focusGuardPart
    if (-not (Test-Path -LiteralPath $focusGuardPartPath)) { throw "缺少 $focusGuardPart" }
    . $focusGuardPartPath
}
