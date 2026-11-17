$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Office-Cleanup.Core.ps1')
$checks=0
function Assert($condition,$message){if(-not $condition){throw "FAIL: $message"};$script:checks++}
function License($id,$name,$status,$description='Retail channel',$app='0ff1ce15-a989-479d-af46-f275c6370663') {[pscustomobject]@{ID=$id;Name=$name;Description=$description;LicenseStatus=$status;ApplicationID=$app;PartialProductKey='ABCDE'}}
$keys=@(
 (License 'grace' 'Office24HomeBusiness2024R_Grace' 2),
 (License 'trial' 'Office21HomeBusiness2021_Trial' 0),
 (License 'retail-active' 'Office24HomeBusiness2024R_Retail' 1),
 (License 'retail-not-active' 'Office24HomeBusiness2024R_Retail' 0),
 (License 'retail-grace-desc' 'Office24HomeBusiness2024R_Retail' 2 'Retail Grace channel'),
 (License 'grace-active' 'Office24HomeBusiness2024R_Grace' 1),
 (License 'unknown' 'Office24Something' 0),
 (License 'project' 'Office24Project_Grace' 2),
 (License 'windows' 'Office24_Grace' 2 'Retail' '55c92734-d682-4d71-983e-d6ec3f16059f')
)
$inventory=[pscustomobject]@{Products=@('HomeBusiness2024Retail');Keys=$keys}
$plan=Get-OfficeTemporaryPlan $inventory
Assert ((@($plan.Keys.ID)|Sort-Object)-join ',' -ceq 'grace,trial') 'Only explicitly named unlicensed Grace/Trial Office suites are selected'
Assert ('retail-active' -in $plan.PreservedKeys.ID -and 'retail-not-active' -in $plan.PreservedKeys.ID -and 'retail-grace-desc' -in $plan.PreservedKeys.ID) 'Every genuine/unknown Retail key is retained, even with a Grace status/description'
Assert ('grace-active' -in $plan.PreservedKeys.ID -and 'project' -in $plan.PreservedKeys.ID) 'Activated trial and non-suite products are retained'
Assert (@($plan.Products).Count -eq 0 -and $plan.TemporaryOnly) 'Preparation never removes Office applications'
$script:calls=@();$script:remaining=@($keys)
function Get-Process {}
function Invoke-CimMethod($InputObject,$MethodName){$script:calls+=$MethodName;if($MethodName -ne 'UninstallProductKey'){throw 'Trial cleanup must not change KMS settings'};$script:remaining=@($script:remaining|Where-Object ID -ne $InputObject.ID);[pscustomobject]@{ReturnValue=0}}
function Get-OfficeCleanupInventory {[pscustomobject]@{Products=@('HomeBusiness2024Retail');Keys=$script:remaining}}
Invoke-OfficeCleanupPlan $plan '' ([IO.Path]::GetTempPath())
Assert ($script:calls.Count -eq 2 -and @($script:remaining|Where-Object ID -eq 'retail-active').Count -eq 1) 'Actual cleanup removes exactly two trial keys and verifies retained Retail'
Assert (@($script:remaining|Where-Object ID -eq 'windows').Count -eq 1) 'Windows license is untouched'
$before=[pscustomobject]@{Products=@('HomeBusiness2024Retail');Keys=@($keys[2])}
$after=[pscustomobject]@{Products=@('HomeBusiness2024Retail');Keys=@((License 'retail-active' 'Office24HomeBusiness2024R_Retail' 0))}
$caught='';try{Assert-OfficeInventoryUnchanged $before $after}catch{$caught=$_.Exception.Message}
Assert ($caught -match 'thay đổi') 'A status/key change during GUI confirmation aborts the plan'
Write-Host "PASS: $checks temporary Office policy assertions; Retail preserved, explicit Grace/Trial only, no application or KMS deletion."
