# Mocked LocalAccounts cmdlets, LSA rights, group lookups and registry; no real account is created.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'LanAccounts.Core.ps1')
$checks=0
function Assert($c,$m){if(-not $c){throw "FAIL: $m"};$script:checks++}
function Throws([scriptblock]$action,$m){$failed=$false;try{& $action | Out-Null}catch{$failed=$true};Assert $failed $m}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('tm-lan-'+[guid]::NewGuid().ToString('N'));New-Item -ItemType Directory $temp | Out-Null
try{
    $log=Join-Path $temp 'lan.jsonl'
    $secret='Kt@2026scan'
    $password=ConvertTo-SecureString $secret -AsPlainText -Force
    $script:admin=$true;$script:policyFails=$false;$script:rightsFail=$false;$script:rightsIgnored=$false;$script:nextSid=1001
    $script:users=@{};$script:groups=@{};$script:rights=@{};$script:hidden=@{}
    $script:calls=New-Object Collections.ArrayList
    function Assert-DeployLanAdmin {if(-not $script:admin){throw 'admin required'}}
    function New-TestUser($Name,$Description,$Enabled=$true){[pscustomobject]@{Name=$Name;Description=$Description;Enabled=$Enabled;SID=[pscustomobject]@{Value=('S-1-5-21-1-2-3-'+($script:nextSid++))};PasswordExpires=$null}}
    function Get-LocalUser {param($ErrorAction)@($script:users.Values)}
    function New-LocalUser {param($Name,$Password,$FullName,$Description,[switch]$PasswordNeverExpires,[switch]$UserMayNotChangePassword,[switch]$AccountNeverExpires,$ErrorAction)
        [void]$script:calls.Add('New:'+$Name)
        Assert ($Password -is [Security.SecureString] -and $Password.Length -gt 0 -and $PasswordNeverExpires -and $UserMayNotChangePassword -and $AccountNeverExpires -and $Description.StartsWith('TechMaster LAN:') -and $Description.Length -le 48) 'New account is marked, never expires and receives the password only as SecureString'
        if($script:policyFails){throw 'The password does not meet the password policy requirements.'}
        $script:users[$Name]=New-TestUser $Name $Description;$script:groups[$Name]=@()
        $script:users[$Name]
    }
    function Set-LocalUser {param($Name,$Password,$PasswordNeverExpires,$UserMayChangePassword,[switch]$AccountNeverExpires,$ErrorAction)
        [void]$script:calls.Add('Set:'+$Name)
        Assert ($Password -is [Security.SecureString] -and $Password.Length -gt 0 -and $PasswordNeverExpires -eq $true -and $UserMayChangePassword -eq $false) 'Update sets the new password and keeps it from expiring'
        $script:users[$Name].PasswordExpires=$null
    }
    function Enable-LocalUser {param($Name,$ErrorAction)[void]$script:calls.Add('Enable:'+$Name);$script:users[$Name].Enabled=$true}
    function Remove-LocalUser {param($Name,$ErrorAction)[void]$script:calls.Add('Remove:'+$Name);$script:users.Remove($Name)}
    function Add-LocalGroupMember {param($SID,$Member,$ErrorAction)
        [void]$script:calls.Add('Group:'+$Member)
        Assert ($SID -ceq 'S-1-5-32-545') 'Accounts only join the built-in Users group, addressed by SID for any Windows language'
        $script:groups[$Member]=@($script:groups[$Member] | Where-Object {$_})+$SID
    }
    function Get-DeployLanGroupSids([string]$Name){@($script:groups[$Name] | Where-Object {$_})}
    function Get-DeployLanAccountRights([string]$Sid){@($script:rights[$Sid] | Where-Object {$_})}
    function Add-DeployLanAccountRights([string]$Sid,[string[]]$Rights){
        [void]$script:calls.Add('Rights:'+$Sid)
        if($script:rightsFail){throw 'LSA access denied'}
        if(-not $script:rightsIgnored){$script:rights[$Sid]=@($script:rights[$Sid] | Where-Object {$_})+$Rights}
    }
    function Remove-DeployLanAccountRights([string]$Sid){[void]$script:calls.Add('Unrights:'+$Sid);$script:rights.Remove($Sid)}
    function Get-DeployLanHidden([string]$Name){[bool]$script:hidden[$Name]}
    function Set-DeployLanHidden([string]$Name){$script:hidden[$Name]=$true}
    function Remove-DeployLanHidden([string]$Name){[void]$script:calls.Add('Unhide:'+$Name);$script:hidden.Remove($Name)}
    $deny='SeDenyInteractiveLogonRight','SeDenyRemoteInteractiveLogonRight','SeDenyBatchLogonRight','SeDenyServiceLogonRight'

    $states=@(Get-DeployLanAccountState)
    Assert ($states.Count -eq 3 -and ($states.Name -join ',') -ceq 'scan,share,print' -and -not @($states | Where-Object {-not $_.CanApply}).Count -and $states[0].Status -match 'Chưa có') 'Three function accounts named scan / share / print, all creatable on a clean machine'

    $r=Invoke-DeployLanAccounts @([pscustomobject]@{Role='Scan';Password=$password}) $log
    $scan=$script:users['scan'];$sid=$scan.SID.Value
    Assert ($r.Kind -eq 'Success' -and $scan -and $scan.Description -ceq 'TechMaster LAN: scan' -and $r.Message.Contains($env:COMPUTERNAME+'\scan')) 'Scan account is created and the network sign-in name is shown'
    Assert (@($script:groups['scan']) -contains 'S-1-5-32-545' -and -not (@($script:groups['scan']) -contains 'S-1-5-32-544')) 'New account is a standard user, never an administrator'
    Assert (-not @($deny | Where-Object {@($script:rights[$sid]) -notcontains $_}).Count -and $script:hidden['scan']) 'Local, Remote Desktop, batch and service sign-in are denied and the account is hidden from the sign-in screen'
    Assert (-not ([IO.File]::ReadAllText($log).Contains($secret))) 'The password never reaches the log'
    $states=@(Get-DeployLanAccountState)
    Assert ($states[0].Exists -and $states[0].Owned -and $states[0].Locked -and $states[0].Hidden -and $states[0].CanApply -and $states[0].Status -match 'TechMaster tạo') 'State reads back the created account as complete'

    $script:users['share']=New-TestUser 'share' 'Tài khoản kế toán'
    $states=@(Get-DeployLanAccountState)
    Assert (-not $states[1].CanApply -and $states[1].Status -match 'không do TechMaster') 'An existing account TechMaster did not create is shown as untouchable'
    $r=Invoke-DeployLanAccounts @([pscustomobject]@{Role='Share';Password=$password}) $log
    Assert ($r.Kind -eq 'Error' -and $r.Message -match 'không do TechMaster' -and -not ($script:calls -contains 'Set:share') -and $script:users['share'].Description -ceq 'Tài khoản kế toán') 'An account not created by TechMaster is never changed'

    $script:users['print']=New-TestUser 'print' 'TechMaster LAN: print' $false;$script:groups['print']=@('S-1-5-32-545')
    $states=@(Get-DeployLanAccountState)
    Assert ($states[2].CanApply -and $states[2].Status -match 'đang bị tắt' -and $states[2].Status -match 'chưa chặn' -and $states[2].Status -match 'chưa ẩn') 'An incomplete TechMaster account lists what is missing'
    $r=Invoke-DeployLanAccounts @([pscustomobject]@{Role='Print';Password=$password}) $log
    $printSid=$script:users['print'].SID.Value
    Assert ($r.Kind -eq 'Success' -and $script:calls -contains 'Set:print' -and $script:calls -contains 'Enable:print' -and -not ($script:calls -contains 'New:print') -and $script:users['print'].Enabled -and $script:hidden['print'] -and @($script:rights[$printSid]).Count -eq 4 -and $r.Message -match 'đã cập nhật') 'An existing TechMaster account gets the new password, is re-enabled, locked down and hidden'

    $script:groups['print']=@('S-1-5-32-545','S-1-5-32-544');$before=$script:calls.Count
    $states=@(Get-DeployLanAccountState)
    $r=Invoke-DeployLanAccounts @([pscustomobject]@{Role='Print';Password=$password}) $log
    Assert (-not $states[2].CanApply -and $r.Kind -eq 'Error' -and $r.Message -match 'Administrators' -and $script:calls.Count -eq $before) 'An account in Administrators is refused before any change'
    $script:groups['print']=@('S-1-5-32-545')

    $r=Invoke-DeployLanAccounts @([pscustomobject]@{Role='Scan';Password=(New-Object Security.SecureString)}) $log
    Assert ($r.Kind -eq 'Error' -and $r.Message -match 'Nhập mật khẩu') 'A blank password is refused: Windows blocks network sign-in with blank passwords'

    $script:users.Remove('share');$script:policyFails=$true
    $r=Invoke-DeployLanAccounts @([pscustomobject]@{Role='Share';Password=$password}) $log
    Assert ($r.Kind -eq 'Error' -and $r.Message -match 'chính sách mật khẩu' -and -not $script:users.ContainsKey('share')) 'A password rejected by Windows policy is explained and creates nothing'
    $script:policyFails=$false

    $script:rightsFail=$true
    $r=Invoke-DeployLanAccounts @([pscustomobject]@{Role='Share';Password=$password}) $log
    Assert ($r.Kind -eq 'Error' -and -not $script:users.ContainsKey('share') -and $script:calls -contains 'Remove:share' -and @($script:calls | Where-Object {$_ -like 'Unrights:*'}).Count -ge 1 -and $script:calls -contains 'Unhide:share' -and $r.Message -match 'Đã xoá tài khoản vừa tạo') 'A new account that cannot be locked down is removed again'
    $script:rightsFail=$false

    $script:rights.Remove($sid);$script:rightsIgnored=$true
    $r=Invoke-DeployLanAccounts @([pscustomobject]@{Role='Scan';Password=$password}) $log
    Assert ($r.Kind -eq 'Error' -and $r.Message -match 'chưa xác nhận đủ' -and $script:users.ContainsKey('scan')) 'Rights that Windows does not confirm are reported; an existing account is not deleted'
    $script:rightsIgnored=$false

    $r=Invoke-DeployLanAccounts @([pscustomobject]@{Role='Scan';Password=$password},[pscustomobject]@{Role='Share';Password=(New-Object Security.SecureString)}) $log
    Assert ($r.Kind -eq 'Attention' -and $r.Message -match '✓ scan' -and $r.Message -match '✗ share') 'Each account is reported separately when only some succeed'

    $script:admin=$false
    Throws {Invoke-DeployLanAccounts @([pscustomobject]@{Role='Scan';Password=$password}) $log} 'Administrator rights are required'
    $script:admin=$true
    Throws {Invoke-DeployLanAccounts @() $log} 'An empty request is rejected'
    $entries=@(Get-Content $log | ForEach-Object {$_ | ConvertFrom-Json})
    Assert (@($entries | Where-Object Event -eq 'lan-account-verified').Count -ge 3 -and @($entries | Where-Object Event -eq 'lan-account-rolled-back').Count -eq 1 -and -not ([IO.File]::ReadAllText($log).Contains($secret))) 'Every change, verification and rollback is logged without the password'
    Write-Host "PASS: $checks LAN account assertions; scan/share/print, network-only lockdown, ownership guard, admin guard, password policy, rollback and logging."
}finally{if(Test-Path $temp){Remove-Item -LiteralPath $temp -Recurse -Force}}
