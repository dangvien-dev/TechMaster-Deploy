param([Parameter(Mandatory=$true)][string]$Root,[Parameter(Mandatory=$true)][string]$ResultPath)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Update.Core.ps1')
. (Join-Path $PSScriptRoot 'Update.Notification.Core.ps1')
Write-DeployJson (Get-DeployUpdateAvailability $Root) $ResultPath
