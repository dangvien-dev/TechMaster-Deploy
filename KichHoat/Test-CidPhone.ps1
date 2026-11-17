# Real loopback GET/POST against the production receiver; no license/browser/firewall mutation.
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Net.Http
. (Join-Path $PSScriptRoot 'Cid.Phone.Core.ps1')
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'App/Wpf.Runtime.ps1')
$checks=0
function Assert($condition,$message){if(-not $condition){throw "FAIL: $message"};$script:checks++}
$iid='1'*63
$page=New-CidPhonePage $iid 'PC & <sample>' 'Office' 'https://visualsupport.microsoft.com/'
Assert ($page.Contains('PC &amp; &lt;sample&gt;') -and $page.Contains($iid)) 'Phone page carries the current IID and escaped computer name'
Assert ($page.Contains('href="https://visualsupport.microsoft.com/"') -and $page.Contains('Sao chép Installation ID')) 'Official portal is directly clickable alongside Copy IID'
$caught='';try{New-CidPhonePage $iid 'PC' 'Office' 'javascript:bad'|Out-Null}catch{$caught=$_.Exception.Message}
Assert ($caught -match 'Portal') 'Unofficial portal addresses are rejected'
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'Kich-Hoat.ps1'),[ref]$tokens,[ref]$errors)
$functions=@(foreach($name in 'Send-Html','Wait-Cid'){
    $ast.Find({param($node)$node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name},$true).Extent.Text
}) -join "`n"
$tcp=[Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,0);$tcp.Start();$port=$tcp.LocalEndpoint.Port;$tcp.Stop()
$base="http://127.0.0.1:$port/phone-test/";$listener=[Net.HttpListener]::new();$listener.Prefixes.Add($base)
$client=[Net.Http.HttpClient]::new();$client.Timeout=[TimeSpan]::FromSeconds(10);$job=$null
try{
    $listener.Start()
    $job=Start-DeployWork @'
param($module,$source,$listener,$iid)
$ErrorActionPreference='Stop'
. $module
. ([scriptblock]::Create($source))
$Product='Office'
function Test-CidManualInput{return $false}
function Write-Warn($message){}
function Write-Ok($message){}
Wait-Cid @{Listener=$listener} $iid 'https://visualsupport.microsoft.com/'
'@ @((Join-Path $PSScriptRoot 'Cid.Phone.Core.ps1'),$functions,$listener,$iid)
    $get=$client.GetStringAsync($base).GetAwaiter().GetResult()
    Assert ($get.Contains($iid) -and $get.Contains('href="https://visualsupport.microsoft.com/"')) 'Actual GET serves IID and the official portal link'
    $invalid=[Net.Http.StringContent]::new('cid=123',[Text.Encoding]::UTF8,'application/x-www-form-urlencoded')
    try{$response=$client.PostAsync($base,$invalid).GetAwaiter().GetResult();$body=$response.Content.ReadAsStringAsync().GetAwaiter().GetResult()}finally{$invalid.Dispose();if($response){$response.Dispose()}}
    Assert ($body.Contains('Cần đủ 48 số') -and $body.Contains($iid)) 'Invalid CID shows an error and keeps the portal workflow available'
    $valid=[Net.Http.StringContent]::new(('cid='+('7'*48)),[Text.Encoding]::UTF8,'application/x-www-form-urlencoded')
    try{$response=$client.PostAsync($base,$valid).GetAwaiter().GetResult();$body=$response.Content.ReadAsStringAsync().GetAwaiter().GetResult()}finally{$valid.Dispose();if($response){$response.Dispose()}}
    Assert ($body.Contains('Đã gửi về máy tính')) 'Successful POST is acknowledged on the phone'
    $deadline=[DateTime]::UtcNow.AddSeconds(5)
    while(-not $job.Async.IsCompleted -and [DateTime]::UtcNow -lt $deadline){Start-Sleep -Milliseconds 10}
    if(-not $job.Async.IsCompleted){throw 'Receiver did not complete after valid CID'}
    $result=@(Receive-DeployWork $job);$job=$null
    Assert ($result[-1] -ceq ('7'*48)) 'Production receiver returns exactly the submitted CID'
}finally{
    $client.Dispose();$listener.Stop();$listener.Close()
    if($job){Request-DeployWorkCancel $job;while(-not $job.Async.IsCompleted){Start-Sleep -Milliseconds 10};try{Receive-DeployWork $job|Out-Null}catch{}}
}
Write-Host "PASS: $checks phone portal assertions; actual loopback GET, invalid CID, successful POST and no activation."
