#requires -Version 5.1
[CmdletBinding()]
param([switch]$Diagnostics)

$ErrorActionPreference = 'Stop'

if ($Diagnostics) {
    Import-Module DisplayConfig -ErrorAction Stop
    Get-DisplayInfo | Format-List *
    exit
}

Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

$createdNew = $false
$mutex = [Threading.Mutex]::new($true, 'Local\DisplayFlip_DisplayConfig', [ref]$createdNew)
if (-not $createdNew) {
    $mutex.Dispose()
    exit
}

$script:tray = $null
$script:menu = $null
$script:hotkeys = $null
$script:icon = $null

function Set-LcdScale {
    $config = Import-PowerShellDataFile -LiteralPath (Join-Path $PSScriptRoot 'Monitors.psd1') -ErrorAction Stop
    $identity = [string]$config['LCD']
    if ([string]::IsNullOrWhiteSpace($identity)) { throw 'Missing LCD identifier in Monitors.psd1.' }
    $matches = @(Get-DisplayInfo -ErrorAction Stop | Where-Object {
        $_.DevicePath -and $_.DevicePath.IndexOf($identity, [StringComparison]::OrdinalIgnoreCase) -ge 0
    })
    if ($matches.Count -gt 1) { throw 'Multiple displays match LCD. Scaling was not changed.' }
    if ($matches.Count -eq 1 -and $matches[0].Active) {
        Set-DisplayScale -DisplayId ([uint32]$matches[0].DisplayId) -Scale 100 -ErrorAction Stop
    }
}
function Set-MonitorPreset {
    param([string[]]$DisplayNames)

    $config = Import-PowerShellDataFile -LiteralPath (Join-Path $PSScriptRoot 'Monitors.psd1') -ErrorAction Stop
    $info = @(Get-DisplayInfo -ErrorAction Stop)
    $resolved = @{}
    $usedIds = @{}
    foreach ($name in @('OLED', 'LCD', 'LAPTOP')) {
        $identity = [string]$config[$name]
        if ([string]::IsNullOrWhiteSpace($identity)) { throw "Missing identifier for $name in Monitors.psd1." }
        $matches = @($info | Where-Object {
            $_.DevicePath -and $_.DevicePath.IndexOf($identity, [StringComparison]::OrdinalIgnoreCase) -ge 0
        })
        if ($matches.Count -gt 1) { throw "Multiple displays match $name. Enter the full DevicePath in Monitors.psd1." }
        if ($matches.Count -eq 1) {
            $id = [uint32]$matches[0].DisplayId
            if ($id -eq 0 -or $usedIds.ContainsKey($id)) { throw 'Display mappings in the configuration are ambiguous.' }
            $resolved[$name] = $id
            $usedIds[$id] = $true
        }
    }
    $idsToEnable = [uint32[]]@(
        foreach ($name in $DisplayNames) {
            if ($resolved.ContainsKey($name)) { $resolved[$name] }
        }
    )
    if ($idsToEnable.Count -eq 0) { throw 'No displays in this preset are connected. The display configuration was not changed.' }
    $idsToDisable = [uint32[]]@($resolved.Values | Where-Object { $idsToEnable -notcontains $_ })
    if ($idsToDisable.Count -gt 0) {
        Enable-Display -DisplayId $idsToEnable -DisplayIdToDisable $idsToDisable -ErrorAction Stop
    }
    else {
        Enable-Display -DisplayId $idsToEnable -ErrorAction Stop
    }
    if ($DisplayNames -contains 'LCD') { Set-LcdScale }
}

try {
    Import-Module DisplayConfig -ErrorAction Stop
    [Windows.Forms.Application]::EnableVisualStyles()
    $script:menu = [Windows.Forms.ContextMenuStrip]::new()

    $presets = @(
        @{ Label = 'OLED'; Names = @('OLED') },
        @{ Label = 'LCD'; Names = @('LCD') },
        @{ Label = 'OLED + LCD'; Names = @('OLED', 'LCD') },
        @{ Label = 'Laptop + LCD'; Names = @('LCD', 'LAPTOP') },
        @{ Label = 'All displays'; Names = @('OLED', 'LCD', 'LAPTOP') }
    )
    Add-Type -Path (Join-Path $PSScriptRoot 'DisplayFlip.Hotkeys.cs') -ReferencedAssemblies System.Windows.Forms
    $script:hotkeys = [DisplayFlip.HotkeyWindow]::new()
    $hotkeyId = 0
    $hotkeyErrors = @()
    foreach ($preset in $presets) {
        $hotkeyId++
        $text = '{0} (Ctrl+Alt+F{1})' -f $preset.Label, $hotkeyId
        try { $script:hotkeys.Register($hotkeyId, 3, (111 + $hotkeyId)) }
        catch {
            $text = $preset.Label + ' (shortcut unavailable)'
            $hotkeyErrors += 'Ctrl+Alt+F' + $hotkeyId + ': ' + $_.Exception.Message
        }
        $item = [Windows.Forms.ToolStripMenuItem]::new($text)
        $item.Tag = $preset.Names
        $item.Add_Click({
            param($sender, $eventArgs)
            try {
                Set-MonitorPreset -DisplayNames ([string[]]$sender.Tag)
            }
            catch {
                [void][Windows.Forms.MessageBox]::Show($_.Exception.Message, 'DisplayFlip', 'OK', 'Warning')
            }
        })
        [void]$script:menu.Items.Add($item)
    }
    [void]$script:menu.Items.Add([Windows.Forms.ToolStripSeparator]::new())
    $exitItem = [Windows.Forms.ToolStripMenuItem]::new('Exit DisplayFlip')
    $exitItem.Add_Click({ [Windows.Forms.Application]::ExitThread() })
    [void]$script:menu.Items.Add($exitItem)

    $script:hotkeys.Add_Pressed({
        param($id)
        $script:menu.Items[[int]$id - 1].PerformClick()
    })
    if ($hotkeyErrors.Count -gt 0) {
        [void][Windows.Forms.MessageBox]::Show(($hotkeyErrors -join "`n"), 'DisplayFlip - hotkeys', 'OK', 'Warning')
    }
    $script:tray = [Windows.Forms.NotifyIcon]::new()
    $script:icon = [Drawing.Icon]::new((Join-Path $PSScriptRoot 'icon.ico'))
    $script:tray.Icon = $script:icon
    $script:tray.Text = 'DisplayFlip'
    $script:tray.ContextMenuStrip = $script:menu
    $script:tray.Visible = $true
    try { Set-LcdScale }
    catch {
        [void][Windows.Forms.MessageBox]::Show(('Could not set LCD scaling to 100%: ' + $_.Exception.Message), 'DisplayFlip', 'OK', 'Warning')
    }
    [Windows.Forms.Application]::Run()
}
catch {
    [void][Windows.Forms.MessageBox]::Show($_.Exception.Message, 'DisplayFlip', 'OK', 'Warning')
}
finally {
    if ($null -ne $script:tray) { $script:tray.Visible = $false; $script:tray.Dispose() }
    if ($null -ne $script:icon) { $script:icon.Dispose() }
    if ($null -ne $script:hotkeys) { $script:hotkeys.Dispose() }
    if ($null -ne $script:menu) { $script:menu.Dispose() }
    try { $mutex.ReleaseMutex() } finally { $mutex.Dispose() }
}