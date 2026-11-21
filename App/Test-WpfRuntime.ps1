$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Wpf.Runtime.ps1')
$job = Start-DeployWork 'param($text,$number) [pscustomobject]@{ Text=$text; Number=$number+1 }' @("Máy's [folder]",41)
while (-not $job.Async.IsCompleted) { Start-Sleep -Milliseconds 10 }
$result = @(Receive-DeployWork $job)
if ($result[-1].Text -cne "Máy's [folder]" -or $result[-1].Number -ne 42) { throw 'Worker arguments or output changed.' }
$job = Start-DeployWork 'throw "worker failure"'
while (-not $job.Async.IsCompleted) { Start-Sleep -Milliseconds 10 }
$caught = ''
try { Receive-DeployWork $job } catch { $caught = $_.Exception.Message }
if ($caught -notmatch 'worker failure') { throw 'Worker error not surfaced.' }
# A provider failure may be handled by a worker and intentionally returned as data.
$job = Start-DeployWork 'try { Get-Process -Name __TechMasterNonexistentFixture -ErrorAction Stop } catch { [pscustomobject]@{Readable=$false;Message="Expected inspection failure"} }'
while (-not $job.Async.IsCompleted) { Start-Sleep -Milliseconds 10 }
$result = @(Receive-DeployWork $job)
if ($result[-1].Readable -ne $false -or $result[-1].Message -ne 'Expected inspection failure') { throw 'Handled inspection result was incorrectly discarded.' }
$job = Start-DeployWork 'Write-Error "unhandled nonterminating error"; "partial output"'
while (-not $job.Async.IsCompleted) { Start-Sleep -Milliseconds 10 }
$caught = ''
try { Receive-DeployWork $job } catch { $caught = $_.Exception.Message }
if ($caught -notmatch 'unhandled nonterminating error') { throw 'Nonterminating error record was silently accepted.' }
$job = Start-DeployWork 'Start-Sleep -Seconds 15'
Request-DeployWorkCancel $job
$deadline = [DateTime]::UtcNow.AddSeconds(5)
while (-not $job.Async.IsCompleted -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 10 }
if (-not $job.Async.IsCompleted -or -not $job.Cancelled) { throw 'Worker cancellation failed.' }
try { Receive-DeployWork $job } catch {}
Write-Host 'PASS: real background runspaces preserve Unicode arguments, return results, surface failures and cancel without UI-thread work.'
