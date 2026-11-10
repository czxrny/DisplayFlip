#requires -Version 5.1
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path -LiteralPath $compiler)) { throw '.NET Framework 4 compiler was not found.' }
$module = Get-Module -ListAvailable DisplayConfig | Sort-Object Version -Descending | Select-Object -First 1
if (-not $module) { throw 'Install-Module DisplayConfig -Scope CurrentUser before building.' }
$output = Join-Path $PSScriptRoot ('dist\DisplayFlip-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [Guid]::NewGuid().ToString('N').Substring(0, 6))
[void][IO.Directory]::CreateDirectory($output)
foreach ($file in @('Autostart.ps1', 'DisplayFlip.ps1', 'DisplayFlip.Hotkeys.cs', 'icon.ico', 'Monitors.Example.psd1', 'README.md')) {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot $file) -Destination $output
}
$moduleDestination = Join-Path $output 'Modules\DisplayConfig'
[void][IO.Directory]::CreateDirectory($moduleDestination)
Copy-Item -LiteralPath $module.ModuleBase -Destination $moduleDestination -Recurse
& $compiler /nologo /target:winexe /platform:x64 /reference:System.Windows.Forms.dll "/win32icon:$PSScriptRoot\icon.ico" "/out:$output\DisplayFlip.exe" (Join-Path $PSScriptRoot 'DisplayFlip.Launcher.cs')
if ($LASTEXITCODE -ne 0) { throw 'Executable compilation failed.' }
Compress-Archive -LiteralPath $output -DestinationPath ($output + '.zip')
Write-Output "Executable: $output\DisplayFlip.exe"
Write-Output "Package: $output.zip"
