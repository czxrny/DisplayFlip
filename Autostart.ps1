#requires -Version 5.1
[CmdletBinding()]
param(
    [ValidateSet('Enable', 'Disable')][string]$Action = 'Enable',
    [string]$StartupDirectory = [Environment]::GetFolderPath('Startup'),
    [string]$BackupDirectory = (Join-Path $env:LOCALAPPDATA 'DisplayFlip\DisabledStartup')
)

$ErrorActionPreference = 'Stop'
$shell = $null
$shortcut = $null
try {
    $startup = $StartupDirectory
    if (-not $startup) { throw 'The current user startup folder could not be found.' }
    $linkPath = Join-Path $startup 'DisplayFlip.lnk'
    $shell = New-Object -ComObject WScript.Shell
    $marker = 'DisplayFlip - DisplayConfig tray launcher'
    if (Test-Path -LiteralPath $linkPath) {
        $shortcut = $shell.CreateShortcut($linkPath)
        if ($shortcut.Description -ne $marker) {
            throw 'DisplayFlip.lnk already exists and was not created by this installer. The file was left unchanged.'
        }
    }
    if ($Action -eq 'Disable') {
        if (Test-Path -LiteralPath $linkPath) {
            # Preserve the shortcut outside the folder used at sign-in.
            [void][IO.Directory]::CreateDirectory($BackupDirectory)
            $disabled = Join-Path $BackupDirectory ('DisplayFlip-' + [Guid]::NewGuid().ToString('N') + '.lnk')
            Move-Item -LiteralPath $linkPath -Destination $disabled -ErrorAction Stop
            Write-Host "Autostart disabled. Shortcut preserved at: $disabled"
        }
        else { Write-Host 'Autostart is already disabled.' }
    }
    else {
        $scriptPath = Join-Path $PSScriptRoot 'DisplayFlip.ps1'
        if (-not (Test-Path -LiteralPath $scriptPath)) { throw 'DisplayFlip.ps1 was not found.' }
        if ($null -eq $shortcut) { $shortcut = $shell.CreateShortcut($linkPath) }
        $shortcut.TargetPath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $shortcut.Arguments = '-NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $scriptPath + '"'
        $shortcut.WorkingDirectory = $PSScriptRoot
        $shortcut.Description = $marker
        $shortcut.WindowStyle = 7
        $shortcut.Save()
        Write-Host "Autostart enabled: $linkPath"
        Write-Host 'If you move the application folder, enable autostart again to update the shortcut.'
    }
}
catch {
    Write-Error $_ -ErrorAction Continue
    exit 1
}
finally {
    if ($null -ne $shortcut) { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($shortcut) }
    if ($null -ne $shell) { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell) }
}
