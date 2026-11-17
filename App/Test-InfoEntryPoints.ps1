# Run first in a fresh Windows PowerShell process. Exercise real main-window clicks,
# before Update-App.ps1 (which used to hide the missing dependency) is imported.
$ErrorActionPreference='Stop'
if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT){throw 'Run the entry-point regression on Windows in STA.'}
if(Get-Command Get-DeployVersion -ErrorAction SilentlyContinue){throw 'Run in a fresh shell without preloaded update functions.'}
$main=. (Join-Path $PSScriptRoot 'TechMaster-Deploy.ps1') -ValidateOnly
$expectedVersion=([IO.File]::ReadAllText((Join-Path (Split-Path -Parent $PSScriptRoot) 'version.txt'))).Trim()
$checks=0
function Assert($condition,$message){if(-not $condition){throw "FAIL: $message"};$script:checks++}
try{
    foreach($entry in @(
        @{Button='changeLogUpdate';Heading='Có gì mới';Content='Phiên bản'},
        @{Button='btnQuickGuide';Heading='Hướng dẫn nhanh';Content='Bắt đầu'},
        @{Button='btnContact';Heading='Hướng dẫn nhanh';Content='Liên hệ / góp ý'}
    )){
        $script:infoCapture=$null
        $deadline=[DateTime]::UtcNow.AddSeconds(15)
        $closer=New-DeployTimer 100 {
            if([DateTime]::UtcNow -gt $deadline){$closer.Stop();throw 'Timed out waiting for the information dialog.'}
            foreach($source in @([Windows.Interop.HwndSource]::CurrentSources)){
                $view=$source.RootVisual
                if($view -is [Windows.Window] -and $view.FindName('Sections') -and $view.FindName('ContentTitle')){
                    $script:infoCapture=@{Heading=$view.FindName('Heading').Text;Content=$view.FindName('ContentTitle').Text;Version=$view.FindName('VersionInfo').Text;Notes=$view.FindName('Notes').Items.Count}
                    $closer.Stop();$view.Close();break
                }
            }
        }
        $closer.Start()
        try{$main.FindName($entry.Button).RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))}
        finally{$closer.Stop()}
        Assert ($script:infoCapture -and $script:infoCapture.Heading -eq $entry.Heading) ($entry.Button+' opens the actual information dialog')
        Assert ($script:infoCapture.Content -like ($entry.Content+'*') -and $script:infoCapture.Notes -gt 0) ($entry.Button+' displays the expected topic')
        Assert ($script:infoCapture.Version -like ('*'+$expectedVersion)) ($entry.Button+' reads the installed version without opening the updater')
    }
}finally{$main.Close()}
Write-Host "PASS: $checks fresh-start info assertions; actual What's New, Guide and Contact button handlers and modal dialogs."
