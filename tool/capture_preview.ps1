param(
    [Parameter(Mandatory = $true)]
    [string]$DeviceId
)
$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')
$previousDeviceId = $env:COMPLIANCE_DEVICE_ID
try {
    $env:COMPLIANCE_DEVICE_ID = $DeviceId
    & flutter --suppress-analytics drive `
        --driver=test_driver/preview_driver.dart `
        --target=integration_test/app_smoke_test.dart `
        --dart-define=CAPTURE_PREVIEW=true `
        -d $DeviceId
    if ($LASTEXITCODE -ne 0) {
        throw "Native preview failed with exit code $LASTEXITCODE"
    }
} finally {
    $env:COMPLIANCE_DEVICE_ID = $previousDeviceId
}
