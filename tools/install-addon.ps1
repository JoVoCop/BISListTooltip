# Copies the same file set the release workflow zips into <AddOns folder>\BISListTooltip, for testing on Windows.
# The first run needs the AddOns folder; it is remembered in .addons-path (gitignored) for later runs.
#
#   powershell -ExecutionPolicy Bypass -File tools\install-addon.ps1 "C:\...\_forever_\Interface\AddOns"
#   powershell -ExecutionPolicy Bypass -File tools\install-addon.ps1
param([string]$AddOnsPath)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$remembered = Join-Path $repo '.addons-path'

if (-not $AddOnsPath) {
    if (-not (Test-Path $remembered)) {
        Write-Error "Give the AddOns folder the first time, for example: tools\install-addon.ps1 'C:\...\_forever_\Interface\AddOns'"
    }
    $AddOnsPath = (Get-Content $remembered -Raw).Trim()
}
if (-not (Test-Path $AddOnsPath -PathType Container)) {
    Write-Error "'$AddOnsPath' is not a folder."
}
Set-Content -Path $remembered -Value $AddOnsPath

$destination = Join-Path $AddOnsPath 'BISListTooltip'
# Removing first keeps files deleted from the repo from lingering in the game folder.
if (Test-Path $destination) { Remove-Item $destination -Recurse -Force }
New-Item -ItemType Directory -Path $destination | Out-Null
Copy-Item (Join-Path $repo 'BISListTooltip.toc') $destination
Copy-Item (Join-Path $repo '*.lua') $destination
Copy-Item (Join-Path $repo 'Data') $destination -Recurse
Copy-Item (Join-Path $repo 'Libs') $destination -Recurse
Copy-Item (Join-Path $repo 'Media') $destination -Recurse
Write-Host "Installed to $destination. Type /reload in game to load the changes."
