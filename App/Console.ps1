# Shared console initialization; dot-sourcing alone does not change the host.
function Initialize-TechMasterConsole {
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { return }

    $utf8 = [Text.UTF8Encoding]::new($false)
    # PS5.1 uses OutputEncoding for text piped to native programs. Limit this
    # variable to the calling script, rather than changing the user's profile.
    try { Set-Variable -Name OutputEncoding -Value $utf8 -Scope 1 }
    catch { Write-Verbose 'Native pipeline encoding is controlled by the host.' }
    try { [Console]::OutputEncoding = $utf8 }
    catch { Write-Verbose 'Console output encoding is controlled by the host.' }
    try {
        if (-not [Console]::IsInputRedirected) { [Console]::InputEncoding = $utf8 }
    } catch { Write-Verbose 'Console input encoding is controlled by the host.' }

    # Use the real output handle, rather than inherited WT_SESSION metadata:
    # a new classic window can inherit that variable from Windows Terminal.
    # Terminal frontends that own the font may decline these Win32 operations.
    if ([Console]::IsOutputRedirected) { return }
    try {
        if (-not ('TechMaster.ConsoleFont' -as [type])) {
            Add-Type -Path (Join-Path $PSScriptRoot 'ConsoleFont.cs') -ErrorAction Stop
        }
        if (-not [TechMaster.ConsoleFont]::UseVietnameseFont()) {
            Write-Verbose 'The console host did not allow font selection.'
        }
    } catch { Write-Verbose ('Cannot initialize the console font: ' + $_.Exception.Message) }
}
