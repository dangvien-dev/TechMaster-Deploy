# Compatibility with updater copies created before deferred reopening was added.
function Test-DeployUpdaterCommand([string]$command,[string]$root) {
    if($command -match '(?i)-EncodedCommand\s+"?([A-Za-z0-9+/=]{1,65536})'){
        try{$command=[Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($Matches[1]))}catch{return $false}
    }
    if($command -notmatch '(?i)\bUpdate-App\.ps1\b'){return $false}
    if($command -notmatch '(?i)(?:^|\s)-Root\s+(?:''((?:[^'']|'''')*)''|"([^"]*)"|(\S+))'){return $false}
    $target=if($Matches[1]){$Matches[1].Replace("''", "'")}elseif($Matches[2]){$Matches[2]}else{$Matches[3]}
    if(-not $target){return $false}
    try{return [IO.Path]::GetFullPath($target).TrimEnd([char[]]@('\','/')) -ieq [IO.Path]::GetFullPath($root).TrimEnd([char[]]@('\','/'))}catch{return $false}
}
function Wait-DeployUpdaterBeforeShow([string]$root) {
    try{
        $sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
        $candidates=@(Get-CimInstance Win32_Process -Filter "Name='powershell.exe' OR Name='pwsh.exe'" -OperationTimeoutSec 5 -ErrorAction Stop|Where-Object {$_.ProcessId -ne $PID -and (Test-DeployUpdaterCommand ([string]$_.CommandLine) $root)})
        foreach($candidate in $candidates){
            $process=$null
            try{
                $owner=Invoke-CimMethod -InputObject $candidate -MethodName GetOwnerSid -OperationTimeoutSec 5 -ErrorAction Stop
                if($owner.Sid -cne $sid){continue}
                $process=Get-Process -Id $candidate.ProcessId -ErrorAction Stop
                # Old updaters launch without waiting. Keep this window hidden
                # until that updater exits after the user closes its result.
                $process.WaitForExit()
            }catch{}finally{if($process){$process.Dispose()}}
        }
    }catch{}
}
