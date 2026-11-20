# All mutations/CIM/native commands are mocked. No driver installation on the test host.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'DriverFix.Engine.ps1')
. (Join-Path $PSScriptRoot 'DriverFix.Report.ps1')
$checks=0
function Assert($Condition,[string]$Message){if(-not $Condition){throw "FAIL: $Message"};$script:checks++}
function Throws([scriptblock]$Code,[string]$Message){$caught=$false;try{& $Code}catch{$caught=$true};Assert $caught $Message}
function Device([string]$Instance,[string[]]$Ids,[int]$Code=28,[string]$Name='Test device'){
    [pscustomobject]@{Name=$Name;InstanceId=$Instance;HardwareIds=$Ids;ErrorCode=$Code;Description=(Get-DriverFixErrorDescription $Code);Service='test';PnpClass='MEDIA'}
}
function Snapshot([object[]]$Devices){[pscustomobject]@{Time='2026-11-20T10:00:00Z';All=$Devices;Problems=@($Devices|Where-Object ErrorCode -ne 0)}}
$root=Join-Path ([IO.Path]::GetTempPath()) ('tm-driver-tests-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root|Out-Null
try{
    $pci=@(Get-DriverFixCatalogLinks @('PCI\VEN_8086&DEV_51C8&SUBSYS_72708086&REV_01'))
    Assert ($pci.Count -eq 2 -and $pci[0].Query -ceq 'VEN_8086&DEV_51C8') 'PCI query drops OEM SUBSYS and revision'
    Assert ($pci[0].Url -match 'VEN_8086%26DEV_51C8$' -and $pci[0].Url -notmatch '&DEV') 'Ampersands are URL encoded'
    $acpi=@(Get-DriverFixCatalogLinks @('ACPI\INTC1055\2&DABA3FF&0'))
    Assert ($acpi.Count -eq 2 -and $acpi[0].Query -ceq 'INTC1055') 'ACPI query uses actual ACPI ID'
    $audioId='INTELAUDIO\CTLR_DEV_51C8&LINKTYPE_06&DEVTYPE_06&VEN_8086&DEV_AE50&SUBSYS_72708086'
    $audio=@(Get-DriverFixCatalogLinks @($audioId))
    Assert ($audio.Count -eq 3 -and $audio[0].Query -ceq 'CTLR_DEV_51C8&LINKTYPE_06' -and $audio[2].Query -ceq 'DEV_AE50') 'Audio queries separate controller+linktype and endpoint'
    Assert (-not @($audio|Where-Object Query -eq 'DEV_51C8').Count) 'Controller DEV is never mistaken for the endpoint'
    $dsp=@(Get-DriverFixCatalogLinks @('INTELAUDIO\DSP_CTLR_DEV_51C8&VEN_8086&DEV_0222'))
    Assert ($dsp[0].Query -ceq 'VEN_8086&DEV_0222') 'DSP OED endpoint gets its own Catalog query'
    $usb=@(Get-DriverFixCatalogLinks @('USB\VID_1234&PID_5678&REV_0100','USB\VID_1234&PID_5678'))
    Assert ($usb.Count -eq 2 -and $usb[0].Query -ceq 'VID_1234&PID_5678') 'USB pairs VID/PID and deduplicates fallback IDs'
    $hda=@(Get-DriverFixCatalogLinks @('HDAUDIO\FUNC_01&VEN_10EC&DEV_0256&SUBSYS_12345678&REV_1000'))
    Assert ($hda[0].Query -ceq 'VEN_10EC&DEV_0256') 'Generic HDAUDIO codecs use their own vendor/device pair'
    $acpiVen=@(Get-DriverFixCatalogLinks @('ACPI\VEN_INTC&DEV_1055'))
    Assert ($acpiVen[0].Query -ceq 'INTC1055') 'ACPI VEN/DEV form normalizes to the searchable ACPI token'
    $otherLink=@(Get-DriverFixCatalogLinks @('ROOT\SOMEDEVICE\0000'))
    Assert ($otherLink[0].Query -ceq 'ROOT\SOMEDEVICE') 'Unknown device classes retain the hardware token in generic fallback'
    Assert ((Get-DriverFixErrorDescription 43) -match 'báo lỗi' -and (Get-DriverFixErrorDescription 22) -match 'disable') 'Error descriptions distinguish stopped from disabled'
    $converted=ConvertTo-DriverFixDevice ([pscustomobject]@{Name='';PNPDeviceID='PCI\TEST';HardwareID=@('ID1','ID2');ConfigManagerErrorCode=28})
    Assert ($converted.InstanceId -eq 'PCI\TEST' -and $converted.HardwareIds.Count -eq 2 -and $converted.Name -eq 'PCI\TEST') 'Inventory preserves all IDs and falls back to instance name'
    $before=Snapshot @((Device 'parent' @('ACPI\INTC1055')), (Device 'removed' @('PCI\VEN_8086&DEV_0001')))
    $after=Snapshot @((Device 'parent' @('ACPI\INTC1055') 0),(Device 'child' @($audioId)),(Device 'disabled' @('USB\VID_1234&PID_5678') 22))
    $delta=Compare-DriverFixSnapshot $before $after
    Assert ($delta.Resolved.Count -eq 1 -and $delta.Disappeared.Count -eq 1 -and $delta.NewProblems.Count -eq 2 -and $delta.Disabled.Count -eq 1) 'Diff distinguishes healthy, absent, new, disabled'
    $profile=Get-DriverFixBuiltinProfileJson|ConvertFrom-Json;Assert-DriverFixProfile $profile
    $sourceJson=Join-Path $PSScriptRoot 'DriverFix.SingPC.json'
    if(Test-Path -LiteralPath $sourceJson){
        $json=Get-Content -LiteralPath $sourceJson -Raw|ConvertFrom-Json
        Assert (($json|ConvertTo-Json -Depth 15 -Compress) -ceq ($profile|ConvertTo-Json -Depth 15 -Compress)) 'Source JSON and updater-compatible built-in JSON are identical'
    }
    $machine=[pscustomobject]@{ComputerName='TEST-PC';Manufacturer='SingPC';Model='I5-12450H';Bios='5.32';CPU='Test CPU';RamGB=16;Board='Test <board>';BiosVendor='AMI';OS='Windows Test'}
    Assert (Test-DriverFixProfileMatch $profile $machine $before) 'SingPC matches all three fields'
    $other=$machine.PSObject.Copy();$other.Manufacturer='Another OEM'
    Assert (-not (Test-DriverFixProfileMatch $profile $other $before)) 'Common Intel ID on another OEM does not match SingPC'
    $other=$machine.PSObject.Copy();$other.Bios='5.33'
    Assert (-not (Test-DriverFixProfileMatch $profile $other $before)) 'An unverified BIOS does not silently inherit SingPC fixes'
    $custom=Get-DriverFixBuiltinProfileJson|ConvertFrom-Json
    $custom.id='custom-oem';$custom.match.anyOf=@([pscustomobject]@{hardwarePattern='ACPI\MYDEVICE*'})
    Assert-DriverFixProfile $custom
    Assert (Test-DriverFixProfileMatch $custom $other (Snapshot @((Device 'custom' @('ACPI\MYDEVICE'))))) 'Custom hardware-based profiles work on other models'
    $bad=Get-DriverFixBuiltinProfileJson|ConvertFrom-Json;$bad|Add-Member command 'Invoke-Expression anything'
    Throws {Assert-DriverFixProfile $bad} 'Profiles reject arbitrary commands'
    $bad=Get-DriverFixBuiltinProfileJson|ConvertFrom-Json;$bad.installOrder[0].links=@('file:///C:/danger.cmd')
    Throws {Assert-DriverFixProfile $bad} 'Profiles reject executable/file links'
    $bad=Get-DriverFixBuiltinProfileJson|ConvertFrom-Json;$bad.disable[0].hardwarePatterns=@('PCI\*')
    Throws {Assert-DriverFixProfile $bad} 'Profiles reject broad parent-controller disable patterns'
    $bad=Get-DriverFixBuiltinProfileJson|ConvertFrom-Json;$bad.powerActions[0].id='RunCommand'
    Throws {Assert-DriverFixProfile $bad} 'Only known power actions can run'
    $profiles=Get-DriverFixProfiles (Join-Path $root 'Profiles')
    Assert ($profiles.Items.Count -eq 1 -and (Test-Path (Join-Path $profiles.Directory 'SingPC-i5-12450H.json'))) 'First run materializes editable local JSON'
    $sample=Join-Path $profiles.Directory 'SingPC-i5-12450H.json'
    [IO.File]::WriteAllText($sample,((Get-DriverFixBuiltinProfileJson) -replace 'SingPC I5-12450H · BIOS 5.32','Custom local name'))
    $profiles=Get-DriverFixProfiles $profiles.Directory
    Assert ($profiles.Items[0].name -eq 'Custom local name') 'User profile edits survive module reopen'
    [IO.File]::WriteAllText((Join-Path $profiles.Directory 'broken.json'),'{bad')
    $profiles=Get-DriverFixProfiles $profiles.Directory
    Assert ($profiles.Errors.Count -eq 1 -and $profiles.Items.Count -eq 1) 'One invalid custom JSON does not block valid profiles'
    $repo=Join-Path $root "USB user's drivers";New-Item -ItemType Directory -Path $repo|Out-Null
    $specific='PCI\VEN_8086&DEV_51C8&SUBSYS_72708086';$generic='PCI\VEN_8086&DEV_51C8'
    [IO.File]::WriteAllText((Join-Path $repo 'wrong.inf'),"[Version]`r`nDriverVer=01/01/2026,99.0.0.0`r`n; $generic`r`nX=Install,PCI\VEN_8086&DEV_51C8&SUBSYS_OTHER`r`n")
    [IO.File]::WriteAllText((Join-Path $repo 'generic.inf'),"[Version]`nDriverVer=01/01/2025,9.0.0.0`nX=Install,`"$generic`"`n")
    [IO.File]::WriteAllText((Join-Path $repo 'specific.inf'),"[Version]`nDriverVer=01/01/2024,1.0.0.0`nX=Install,`"$specific`"`n",[Text.Encoding]::Unicode)
    $index=@(Get-DriverFixInfIndex $repo);$dev=Device 'test' @($specific,$generic)
    Assert ($index.Count -eq 3) 'INF discovery supports paths with spaces and apostrophes'
    $candidate=Get-DriverFixInfCandidate $dev $index $null @{}
    Assert ($candidate.Path -like '*specific.inf') 'A specific UTF16 INF outranks a newer generic one'
    Assert (-not (Test-DriverFixInfContainsId ($index|Where-Object Path -like '*wrong.inf').Text $generic)) 'Comment-only ID and foreign SUBSYS do not match'
    Assert (Test-DriverFixInfContainsId ('X=Install,"ACPI\INTC1055"') 'ACPI\INTC1055') 'Backslash and regex characters are escaped literally'
    $attempted=@{};$attempted[($dev.InstanceId+'|'+$candidate.Path+'|'+$candidate.Hash)]=$true
    Assert ((Get-DriverFixInfCandidate $dev $index $null $attempted).Path -like '*generic.inf') 'Already attempted INF/device/hash is not retried'
    $audioDev=Device 'sst-child' @($audioId -replace '&SUBSYS_72708086','')
    $audioIndex=@([pscustomobject]@{Path='new.inf';Version='20.1.0.0';Hash='a';Text=('X=I,"'+$audioDev.HardwareIds[0]+'"')},[pscustomobject]@{Path='matching.inf';Version='10.29.0.12181';Hash='b';Text=('X=I,"'+$audioDev.HardwareIds[0]+'"')})
    Assert ((Get-DriverFixInfCandidate $audioDev $audioIndex $profile @{}).Path -eq 'matching.inf') 'Verified profile keeps SST 10.29.0 branch'
    Assert ((Get-DriverFixInfCandidate $audioDev $audioIndex $null @{}).Path -eq 'new.inf') 'Generic machines are not constrained by SingPC driver versions'
    Assert ((ConvertTo-DriverFixNativeArgument 'C:\my drivers\') -ceq '"C:\my drivers\\"') 'Native quoting doubles a trailing backslash in quoted paths'
    Assert ((ConvertTo-DriverFixNativeArgument 'a"b') -ceq '"a\"b"') 'Native quoting handles embedded quotes without a shell'
    Throws {ConvertTo-DriverFixNativeArgument "bad`nargument"} 'Native arguments reject control characters'
    Assert (Test-DriverFixWmiDeviceMatch 'USB\VID_1234&PID_5678\A_0' 'USB\VID_1234&PID_5678\A') 'WMI mapping accepts only the exact instance with numeric suffix'
    Assert (-not (Test-DriverFixWmiDeviceMatch 'USB\VID_1234&PID_5678\AB_0' 'USB\VID_1234&PID_5678\A')) 'WMI mapping never matches a different USB instance prefix'
    foreach($id in 'UsbSelectiveSuspendAc','PcieLinkStateAc','SleepNeverAc'){Assert ((Get-DriverFixPowerSpec $id).Count -eq 2) "Fixed GUID power spec exists for $id"}
    Throws {Get-DriverFixPowerSpec 'anything'} 'Unknown power settings rejected'
    # All code below uses simulated inventory/native operations.
    $script:fixture=Snapshot @((Device 'one' @('ACPI\INTC1055')))
    function Get-DriverFixSnapshot {return $script:fixture}
    function Get-DriverFixMachine {return $machine}
    $session=New-DriverFixSession (Join-Path $root 'SessionHome')
    $script:admin=$false;$script:nativeCalls=New-Object Collections.ArrayList;$script:mode='normal';$script:stage=0
    function Test-DriverFixAdmin {return $script:admin}
    function Start-Sleep {param($Seconds)}
    function Invoke-DriverFixNative($Session,$Tool,[string[]]$Arguments){
        [void]$script:nativeCalls.Add([pscustomobject]@{Tool=$Tool;Arguments=$Arguments})
        if($script:mode -eq 'throw'){throw 'Mock native failure'}
        if($Tool -eq 'expand'){
            [IO.File]::WriteAllText((Join-Path $Arguments[2] 'fromcab.inf'),"[Version]`nDriverVer=01/01/2024,1.0.0.0`nX=I,ACPI\INTC1055")
        }
        if($Arguments[0] -eq '/add-driver' -and $script:mode -eq 'chain'){
            $script:stage++;$script:fixture=Snapshot @((Device ('child'+$script:stage) @('ACPI\CHAIN0001')))
        }
        if($Arguments[0] -eq '/disable-device'){$script:fixture=Snapshot @((Device $Arguments[1] $audioDev.HardwareIds 22))}
        $exit=if($script:mode -eq 'reboot'){3010}elseif($script:mode -eq 'failed'){5}else{0}
        [pscustomobject]@{ExitCode=$exit;Success=($exit -in 0,3010);RebootRequired=($exit -eq 3010);Output='Current AC Power Setting Index: 0x00000000';Error=''}
    }
    Throws {Invoke-DriverFixInstallSource $session $repo} 'Installer denies non-admin before invoking native tools'
    Throws {Invoke-DriverFixRepository $session $repo} 'Repository denies non-admin before scanning/installing'
    Throws {Invoke-DriverFixDisable $session 'one' @('ACPI\INTC1055')} 'Disable denies non-admin'
    Throws {Invoke-DriverFixPower $session @('SleepNeverAc')} 'Power changes deny non-admin'
    Assert ($script:nativeCalls.Count -eq 0 -and [IO.File]::ReadAllText($session.LogPath) -match 'denied') 'Admin denials are logged and execute nothing'
    $script:admin=$true
    $candidate=Get-DriverFixInfCandidate $dev $index $null @{}
    [IO.File]::AppendAllText($candidate.Path,"`n; changed")
    Throws {Invoke-DriverFixAddPackage $session $candidate.Path 'test' $candidate.Hash} 'An INF changed after matching is never installed'
    Assert ($script:nativeCalls.Count -eq 0) 'Hash mismatch executes no native command'
    $script:mode='reboot'
    $manual=Invoke-DriverFixInstallSource $session $repo
    Assert ($manual.Native.RebootRequired -and $session.Actions[-1].RebootRequired) 'pnputil 3010 is recorded as reboot-required, with no reboot command'
    Assert ($script:nativeCalls[0].Arguments[0] -eq '/add-driver' -and $script:nativeCalls[0].Arguments[1] -eq (Join-Path $repo '*.inf') -and '/subdirs' -in $script:nativeCalls[0].Arguments) 'Folder install passes wildcard and subdirs as arguments, not shell text'
    Assert ($session.Current.Problems.Count -eq 1 -and (Compare-DriverFixSnapshot $session.Before $session.Current).Resolved.Count -eq 0) 'Native success never falsely clears unresolved devices'
    $script:mode='normal'
    $cab=Join-Path $root 'downloaded driver.cab';[IO.File]::WriteAllText($cab,'test fixture, not a real CAB')
    $null=Invoke-DriverFixInstallSource $session $cab
    $expandCall=@($script:nativeCalls|Where-Object Tool -eq 'expand')[-1]
    Assert ($expandCall.Arguments[0] -ceq '-F:*' -and $expandCall.Arguments[1] -ceq $cab) 'CAB expands with separate safe arguments'
    Assert (-not (Test-Path -LiteralPath $expandCall.Arguments[2])) 'Owned temporary extraction directory is removed after installation'
    Assert ([IO.File]::ReadAllText($session.LogPath) -match 'cab-source' -and [IO.File]::ReadAllText($session.LogPath) -match 'inf-manifest') 'CAB hash and extracted INF manifest logged'
    $script:mode='failed';Throws {Invoke-DriverFixInstallSource $session $repo} 'Failed hardware rescan is surfaced after a failed install'
    Assert (-not $session.Actions[-1].Success) 'A nonzero native exit is retained as failure'
    $script:mode='normal';$script:fixture=Snapshot @((Device 'generic-parent' @('ACPI\CHAIN0001')))
    $machine.Manufacturer='Generic OEM';$machine.Model='Any board';$machine.Bios='1.0'
    $generic=New-DriverFixSession (Join-Path $root 'GenericHome')
    Assert ($null -eq $generic.Profile) 'Generic machine has no required profile'
    $chain=Join-Path $root 'chain';New-Item -ItemType Directory -Path $chain|Out-Null
    [IO.File]::WriteAllText((Join-Path $chain 'chain.inf'),"[Version]`nDriverVer=01/01/2024,1.0.0.0`nX=I,ACPI\CHAIN0001")
    $script:mode='chain';$script:stage=0
    $result=Invoke-DriverFixRepository $generic $chain
    Assert ($result.Rounds -eq 4 -and $result.Attempts -eq 4 -and $script:stage -eq 4) 'Generic OEM works through parent/child chain and never exceeds four rounds'
    Assert ($generic.Current.Problems[0].InstanceId -eq 'child4') 'Child exposed on last round stays visible for further work'
    $script:mode='normal';$static=New-DriverFixSession (Join-Path $root 'StaticHome')
    $result=Invoke-DriverFixRepository $static $chain
    Assert ($result.Attempts -eq 1) 'Same device/INF/hash is not repeatedly installed without progress'
    [IO.File]::WriteAllText($static.CancelPath,'cancel');$count=$script:nativeCalls.Count
    $result=Invoke-DriverFixRepository $static $chain
    Assert ($result.Cancelled -and $result.Attempts -eq 0 -and $count -eq $script:nativeCalls.Count) 'Cooperative cancellation runs no next package'
    Throws {Invoke-DriverFixDisable $generic 'child4' @('ACPI\CHAIN0001')} 'Model-specific disable cannot run on an unmatched generic machine'
    $machine.Manufacturer='SingPC';$machine.Model='I5-12450H';$machine.Bios='5.32'
    $script:fixture=Snapshot @($audioDev);$specificSession=New-DriverFixSession (Join-Path $root 'SpecificHome')
    Assert ([bool](Get-DriverFixDisableRule $audioDev $profile)) 'Verified audio endpoint is eligible for explicit disable'
    $parent=Device 'bus' @('PCI\VEN_8086&DEV_51C8');$parent.PnpClass='System'
    Assert (-not (Get-DriverFixDisableRule $parent $profile)) 'Parent SST bus is never disabled'
    Assert (-not (Get-DriverFixDisableRule (Device 'name-only' @('ACPI\UNKNOWN') 28 'Detection Verification') $profile)) 'Names alone never authorize disable'
    Throws {Invoke-DriverFixDisable $specificSession $audioDev.InstanceId @('WRONG')} 'Disable revalidates IDs after user confirmation'
    Invoke-DriverFixDisable $specificSession $audioDev.InstanceId $audioDev.HardwareIds
    Assert ($specificSession.Actions[-1].Success -and $specificSession.Current.Problems[0].ErrorCode -eq 22) 'Disable is successful only after Code22 readback'
    $callCount=$script:nativeCalls.Count
    Throws {Invoke-DriverFixPower $specificSession @('unknown')} 'Unlisted power action is refused'
    Assert ($script:nativeCalls.Count -eq $callCount) 'Unlisted power action executes no native commands'
    Invoke-DriverFixPower $specificSession @('SleepNeverAc','UsbSelectiveSuspendAc','PcieLinkStateAc')
    $sets=@($script:nativeCalls|Where-Object {$_.Tool -eq 'powercfg' -and $_.Arguments[0] -eq '/setacvalueindex'})
    Assert ($sets.Count -eq 3 -and -not @($script:nativeCalls|Where-Object {$_.Arguments[0] -match 'setdc|reboot'}).Count) 'Power tweaks use fixed AC settings and never change DC or reboot'
    $script:powerRows=@([pscustomobject]@{InstanceName='USB\VID_1234&PID_5678\A_0';Enable=$true},[pscustomobject]@{InstanceName='PCI\UNRELATED_0';Enable=$true})
    $script:fixture=Snapshot @((Device 'USB\VID_1234&PID_5678\A' @('USB\VID_1234&PID_5678') 0));$script:wmiChanged=0
    function Get-CimInstance {param($Namespace,$ClassName,$ErrorAction) return $script:powerRows}
    function Set-CimInstance {param($InputObject,$Property,$ErrorAction) $InputObject.Enable=$Property.Enable;$script:wmiChanged++}
    Invoke-DriverFixPower $specificSession @('UsbHidDevicePower')
    Assert ($script:wmiChanged -eq 1 -and -not $script:powerRows[0].Enable -and $script:powerRows[1].Enable) 'WMI power only touches the exact USB/HID device instance'
    $script:powerRows=@();Invoke-DriverFixPower $specificSession @('UsbHidDevicePower')
    Assert (-not $specificSession.Actions[-1].Success) 'Unsupported WMI is reported as failure instead of success'
    $generic.Current=$after
    $htmlPath=Export-DriverFixReport $generic;$html=[IO.File]::ReadAllText($htmlPath)
    Assert ((Split-Path -Leaf $htmlPath) -match '^TEST-PC_\d{8}-\d{4}\.html$') 'Report filename follows ComputerName_yyyyMMdd-HHmm'
    Assert ($html -match 'Test &lt;board&gt;' -and $html -notmatch 'Test <board>') 'Report escapes machine-provided markup'
    Assert ($html -match 'Hardware ID' -and $html -match 'InstanceId' -and $html -match '%26DEV_') 'Report includes before/after IDs and encoded Catalog links'
    $second=Export-DriverFixReport $generic
    Assert ($second -ne $htmlPath -and (Test-Path -LiteralPath $htmlPath)) 'Repeated exports preserve earlier reports'
    $payloads=@(& git -C (Split-Path -Parent $PSScriptRoot) ls-files '*.cab' '*.inf' '*.sys' '*.cat')
    Assert ($payloads.Count -eq 0) 'No redistributable driver payload is tracked'
    Write-Host "PASS: $checks Fix Driver assertions. All installation, disable, WMI and native operations were simulated."
}finally{if(Test-Path -LiteralPath $root){Remove-Item -LiteralPath $root -Recurse -Force}}
