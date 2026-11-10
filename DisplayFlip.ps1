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

function Get-DisplayFlipConfig {
    param([string]$Path = (Join-Path $PSScriptRoot 'Monitors.psd1'))

    if (Test-Path -LiteralPath $Path) {
        $config = Import-PowerShellDataFile -LiteralPath $Path -ErrorAction Stop
    }
    else {
        $config = New-DisplayFlipConfig -Displays @(Get-DisplayInfo -ErrorAction Stop)
        Save-DisplayFlipConfig -Config $config -Path $Path
    }
    if ($config.Monitors -isnot [hashtable] -or $config.Monitors.Count -eq 0) {
        throw 'Monitors.psd1 must define a non-empty Monitors table.'
    }
    foreach ($name in $config.Monitors.Keys) {
        $monitor = $config.Monitors[$name]
        if ($monitor -isnot [hashtable] -or [string]::IsNullOrWhiteSpace($monitor.Identity)) {
            throw "Monitor $name must define an Identity."
        }
        if ($monitor.ContainsKey('Scale') -and ($monitor.Scale -isnot [int] -or $monitor.Scale -lt 100 -or $monitor.Scale -gt 500)) {
            throw "Monitor $name Scale must be an integer between 100 and 500."
        }
    }
    if (@($config.Presets).Count -eq 0) { throw 'Define at least one preset in Monitors.psd1.' }
    $hotkeys = @{}
    foreach ($preset in $config.Presets) {
        if ($preset -isnot [hashtable] -or [string]::IsNullOrWhiteSpace($preset.Label) -or @($preset.Names).Count -eq 0) {
            throw 'Each preset must define a Label and a non-empty Names array.'
        }
        $names = @{}
        foreach ($name in $preset.Names) {
            if (-not $config.Monitors.ContainsKey($name)) { throw "Preset $($preset.Label) references unknown monitor $name." }
            if ($names.ContainsKey($name)) { throw "Preset $($preset.Label) repeats monitor $name." }
            $names[$name] = $true
        }
        if (-not [string]::IsNullOrWhiteSpace($preset.Hotkey)) {
            $binding = ConvertTo-DisplayFlipHotkey $preset.Hotkey
            $key = '{0}:{1}' -f $binding.Modifiers, $binding.Key
            if ($hotkeys.ContainsKey($key)) { throw "Duplicate hotkey: $($preset.Hotkey)." }
            $hotkeys[$key] = $true
        }
    }
    return $config
}

function Save-DisplayFlipConfig {
    param([hashtable]$Config, [string]$Path, [switch]$Replace)

    $lines = @(
        '# DisplayFlip settings: use Settings > Save & Apply to apply changes without restarting.'
        '# Monitors: Identity is the device path; add Scale = 100 (or another supported percentage) to set scaling.'
        '# Presets: Label is tray text; Names lists monitor keys to enable; other configured monitors are disabled.'
        '# Hotkey is optional: Ctrl, Alt, Shift, Win plus A-Z or F1-F24, for example Ctrl+Alt+M.'
        '# Keep monitor keys and preset Names consistent. Every preset must enable at least one monitor.'
        '@{', '    Monitors = @{'
    )
    foreach ($name in ($Config.Monitors.Keys | Sort-Object)) {
        $identity = $Config.Monitors[$name].Identity.Replace("'", "''")
        $escapedName = $name.Replace("'", "''")
        $scale = if ($Config.Monitors[$name].ContainsKey('Scale')) { '; Scale = ' + $Config.Monitors[$name].Scale } else { '' }
        $lines += "        '$escapedName' = @{ Identity = '$identity'$scale }"
    }
    $lines += '    }', '    Presets = @('
    foreach ($preset in $Config.Presets) {
        $label = $preset.Label.Replace("'", "''")
        $names = @($preset.Names | ForEach-Object { "'$($_.Replace("'", "''"))'" }) -join ', '
        $line = "        @{ Label = '$label'; Names = @($names)"
        if ($preset.Hotkey) { $line += "; Hotkey = '$($preset.Hotkey.Replace("'", "''"))'" }
        $lines += $line + ' },'
    }
    $lines[-1] = $lines[-1].TrimEnd(',')
    $lines += '    )', '}'
    if ($Replace) {
        $temporary = $Path + '.' + [Guid]::NewGuid().ToString('N') + '.tmp'
        Save-DisplayFlipConfig -Config $Config -Path $temporary
        if (Test-Path -LiteralPath $Path) {
            [IO.File]::Replace($temporary, $Path, ($Path + '.' + [Guid]::NewGuid().ToString('N') + '.bak'))
        }
        else { [IO.File]::Move($temporary, $Path) }
        return
    }
    # CreateNew prevents overwriting a configuration created since discovery started.
    $stream = [IO.File]::Open($Path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write)
    try {
        $bytes = [Text.UTF8Encoding]::new($true).GetPreamble() + [Text.Encoding]::UTF8.GetBytes(($lines -join "`r`n") + "`r`n")
        $stream.Write($bytes, 0, $bytes.Length)
    }
    finally { $stream.Dispose() }
}

function New-DisplayFlipConfig {
    param([object[]]$Displays)

    $displaysWithPaths = @($Displays | Where-Object { -not [string]::IsNullOrWhiteSpace($_.DevicePath) } | Sort-Object DevicePath)
    if ($displaysWithPaths.Count -eq 0) { throw 'No displays with device paths were detected. Connect a display and restart DisplayFlip.' }
    $monitors = @{}
    $paths = @{}
    $presets = @()
    $names = @()
    foreach ($display in $displaysWithPaths) {
        if ($paths.ContainsKey($display.DevicePath)) { throw 'Duplicate display device paths were detected. Automatic configuration is ambiguous.' }
        $paths[$display.DevicePath] = $true
        $name = 'Display{0}' -f ($names.Count + 1)
        $names += $name
        $label = [string]$display.DisplayName
        if ([string]::IsNullOrWhiteSpace($label)) { $label = 'Display' }
        $monitors[$name] = @{ Identity = [string]$display.DevicePath }
        $preset = @{ Label = '{0} ({1})' -f $label, $names.Count; Names = @($name) }
        if ($names.Count -le 23) { $preset.Hotkey = 'Ctrl+Alt+F{0}' -f $names.Count }
        $presets += $preset
    }
    if ($names.Count -gt 1) {
        $key = [Math]::Min($names.Count + 1, 24)
        $presets += @{ Label = 'All displays'; Names = $names; Hotkey = 'Ctrl+Alt+F{0}' -f $key }
    }
    # Bound exponential growth so large display setups still have a usable tray menu.
    if ($names.Count -ge 3 -and $names.Count -le 8) {
        $labels = @($presets | Select-Object -First $names.Count | ForEach-Object { $_.Label })
        $combinations = @(
            for ($mask = 1; $mask -lt ([int][Math]::Pow(2, $names.Count) - 1); $mask++) {
                $selectedNames = @()
                $selectedLabels = @()
                for ($index = 0; $index -lt $names.Count; $index++) {
                    if ($mask -band (1 -shl $index)) {
                        $selectedNames += $names[$index]
                        $selectedLabels += $labels[$index]
                    }
                }
                if ($selectedNames.Count -gt 1) {
                    @{ Label = $selectedLabels -join ' + '; Names = $selectedNames }
                }
            }
        )
        $presets += @($combinations | Sort-Object @{ Expression = { $_.Names.Count } }, Label)
    }
    return @{ Monitors = $monitors; Presets = $presets }
}

function ConvertTo-DisplayFlipHotkey {
    param([string]$Hotkey)

    $parts = @($Hotkey.Split('+') | ForEach-Object { $_.Trim() })
    $modifiers = 0
    $modifierValues = @{ Alt = 1; Ctrl = 2; Shift = 4; Win = 8 }
    for ($i = 0; $i -lt $parts.Count - 1; $i++) {
        $part = $parts[$i]
        if (-not $modifierValues.ContainsKey($part) -or ($modifiers -band $modifierValues[$part])) {
            throw "Invalid hotkey: $Hotkey. Use modifiers Ctrl, Alt, Shift, Win and a key A-Z or F1-F24."
        }
        $modifiers = $modifiers -bor $modifierValues[$part]
    }
    if ($parts[-1] -match '^[A-Z]$') {
        $key = [uint32][char]$parts[-1].ToUpperInvariant()
    }
    elseif ($parts[-1] -match '^F([1-9]|1[0-9]|2[0-4])$') {
        $key = [uint32](111 + [int]$Matches[1])
    }
    else {
        throw "Invalid hotkey: $Hotkey. Use a letter A-Z or function key F1-F24."
    }
    return @{ Modifiers = [uint32]$modifiers; Key = $key }
}

function Set-MonitorScale {
    param([hashtable]$Config, [string[]]$DisplayNames)

    $info = @(Get-DisplayInfo -ErrorAction Stop)
    foreach ($name in $DisplayNames) {
        $monitor = $Config.Monitors[$name]
        if (-not $monitor.ContainsKey('Scale')) { continue }
        $matches = @($info | Where-Object {
            $_.DevicePath -and $_.DevicePath.IndexOf($monitor.Identity, [StringComparison]::OrdinalIgnoreCase) -ge 0
        })
        if ($matches.Count -gt 1) { throw "Multiple displays match $name. Scaling was not changed for this monitor." }
        if ($matches.Count -eq 1 -and $matches[0].Active) {
            Set-DisplayScale -DisplayId ([uint32]$matches[0].DisplayId) -Scale $monitor.Scale -ErrorAction Stop
        }
    }
}
function Update-DisplayFlipChecks {
    param($Items, [hashtable]$Config, [object[]]$Displays)

    $activeNames = @()
    $ambiguous = $false
    foreach ($name in $Config.Monitors.Keys) {
        $identity = $Config.Monitors[$name].Identity
        $matches = @($Displays | Where-Object {
            $_.DevicePath -and $_.DevicePath.IndexOf($identity, [StringComparison]::OrdinalIgnoreCase) -ge 0
        })
        if ($matches.Count -gt 1) { $ambiguous = $true }
        if ($matches.Count -eq 1 -and $matches[0].Active) { $activeNames += $name }
    }
    foreach ($item in $Items) {
        if ($item.Tag -isnot [hashtable]) { continue }
        $names = @($item.Tag.Names)
        $item.Checked = -not $ambiguous -and $names.Count -eq $activeNames.Count -and @($names | Where-Object { $activeNames -notcontains $_ }).Count -eq 0
    }
}

function Set-MonitorPreset {
    param([hashtable]$Preset)

    $config = $script:config
    $DisplayNames = [string[]]$Preset.Names
    $info = @(Get-DisplayInfo -ErrorAction Stop)
    $resolved = @{}
    $usedIds = @{}
    foreach ($name in $config.Monitors.Keys) {
        $identity = [string]$config.Monitors[$name].Identity
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
    Set-MonitorScale -Config $config -DisplayNames $DisplayNames
}

function Show-DisplayFlipSettings {
    $form = [Windows.Forms.Form]::new()
    $form.Text = 'DisplayFlip settings'
    $form.Size = [Drawing.Size]::new(850, 600)
    $form.MinimumSize = $form.Size
    $form.StartPosition = 'CenterScreen'
    $layout = [Windows.Forms.TableLayoutPanel]::new()
    $layout.Dock = 'Fill'
    $layout.ColumnCount = 1
    $layout.RowCount = 5
    foreach ($height in @(45, 150, 40, 230, 45)) {
        [void]$layout.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Absolute, $height))
    }
    $form.Controls.Add($layout)
    $help = [Windows.Forms.Label]::new()
    $help.Text = 'Monitors: leave Scale blank to preserve scaling. Presets: enter monitor keys separated by commas. Hotkeys: Ctrl/Alt/Shift/Win + A-Z or F1-F24.'
    $help.Dock = 'Fill'
    $layout.Controls.Add($help, 0, 0)
    $monitors = [Windows.Forms.DataGridView]::new()
    $monitors.Dock = 'Fill'
    $monitors.AllowUserToAddRows = $false
    $monitors.AllowUserToDeleteRows = $false
    $monitors.AutoSizeColumnsMode = 'Fill'
    foreach ($column in @('Key', 'Identity', 'Scale')) { [void]$monitors.Columns.Add($column, $column) }
    $monitors.Columns['Key'].ReadOnly = $true
    $monitors.Columns['Identity'].ReadOnly = $true
    foreach ($name in ($script:config.Monitors.Keys | Sort-Object)) {
        $monitor = $script:config.Monitors[$name]
        [void]$monitors.Rows.Add([object[]]@($name, $monitor.Identity, $monitor.Scale))
    }
    $layout.Controls.Add($monitors, 0, 1)
    $presetHelp = [Windows.Forms.Label]::new()
    $presetHelp.Text = 'Edit preset names, combinations, and shortcuts below. Use the last row to add a preset; select a row and press Delete to remove it.'
    $presetHelp.Dock = 'Fill'
    $layout.Controls.Add($presetHelp, 0, 2)
    $presets = [Windows.Forms.DataGridView]::new()
    $presets.Dock = 'Fill'
    $presets.AutoSizeColumnsMode = 'Fill'
    foreach ($column in @('Label', 'Names', 'Hotkey')) { [void]$presets.Columns.Add($column, $column) }
    foreach ($preset in $script:config.Presets) {
        [void]$presets.Rows.Add([object[]]@($preset.Label, ($preset.Names -join ', '), $preset.Hotkey))
    }
    $layout.Controls.Add($presets, 0, 3)
    $save = [Windows.Forms.Button]::new()
    $save.Text = 'Save & Apply'
    $save.UseMnemonic = $false
    $save.AutoSize = $true
    $layout.Controls.Add($save, 0, 4)
    $save.Add_Click({
        try {
            [void]$monitors.EndEdit()
            [void]$presets.EndEdit()
            $config = @{ Monitors = @{}; Presets = @() }
            foreach ($row in $monitors.Rows) {
                $monitor = @{ Identity = [string]$row.Cells['Identity'].Value }
                $scale = [string]$row.Cells['Scale'].Value
                if (-not [string]::IsNullOrWhiteSpace($scale)) { $monitor.Scale = [int]$scale }
                $config.Monitors[[string]$row.Cells['Key'].Value] = $monitor
            }
            foreach ($row in $presets.Rows) {
                if ($row.IsNewRow) { continue }
                $config.Presets += @{
                    Label = [string]$row.Cells['Label'].Value
                    Names = @(([string]$row.Cells['Names'].Value).Split(',') | ForEach-Object { $_.Trim() })
                    Hotkey = [string]$row.Cells['Hotkey'].Value
                }
            }
            $configPath = Join-Path $PSScriptRoot 'Monitors.psd1'
            $validationPath = Join-Path ([IO.Path]::GetTempPath()) ('DisplayFlip-' + [Guid]::NewGuid().ToString('N') + '.psd1')
            Save-DisplayFlipConfig -Config $config -Path $validationPath
            $config = Get-DisplayFlipConfig -Path $validationPath
            Save-DisplayFlipConfig -Config $config -Path $configPath -Replace
            $script:config = $config
            Initialize-DisplayFlipMenu
            try { Set-MonitorScale -Config $config -DisplayNames @($config.Monitors.Keys) }
            catch {
                [void][Windows.Forms.MessageBox]::Show(('Settings saved, but scaling could not be applied: ' + $_.Exception.Message), 'DisplayFlip', 'OK', 'Warning')
            }
            $form.Close()
        }
        catch {
            [void][Windows.Forms.MessageBox]::Show($_.Exception.Message, 'DisplayFlip settings', 'OK', 'Warning')
        }
    })
    try { [void]$form.ShowDialog() }
    finally { $form.Dispose() }
}

function Initialize-DisplayFlipMenu {
    if ($script:hotkeys) { $script:hotkeys.Dispose() }
    $oldMenu = $script:menu
    $script:menu = [Windows.Forms.ContextMenuStrip]::new()
    $presets = $script:config.Presets

    $script:hotkeys = [DisplayFlip.HotkeyWindow]::new()
    $hotkeyId = 0
    $hotkeyErrors = @()
    foreach ($preset in $presets) {
        $hotkeyId++
        $text = $preset.Label
        if (-not [string]::IsNullOrWhiteSpace($preset.Hotkey)) {
            $binding = ConvertTo-DisplayFlipHotkey $preset.Hotkey
            $text = '{0} ({1})' -f $preset.Label, $preset.Hotkey
            try { $script:hotkeys.Register($hotkeyId, $binding.Modifiers, $binding.Key) }
            catch {
                $text = $preset.Label + ' (shortcut unavailable)'
                $hotkeyErrors += $preset.Hotkey + ': ' + $_.Exception.Message
            }
        }
        $item = [Windows.Forms.ToolStripMenuItem]::new($text)
        $item.Tag = $preset
        $item.Add_Click({
            param($sender, $eventArgs)
            try {
                Set-MonitorPreset -Preset $sender.Tag
            }
            catch {
                [void][Windows.Forms.MessageBox]::Show($_.Exception.Message, 'DisplayFlip', 'OK', 'Warning')
            }
        })
        [void]$script:menu.Items.Add($item)
    }
    [void]$script:menu.Items.Add([Windows.Forms.ToolStripSeparator]::new())
    $editItem = [Windows.Forms.ToolStripMenuItem]::new('Settings...')
    $editItem.Add_Click({
        try {
            Show-DisplayFlipSettings
        }
        catch {
            [void][Windows.Forms.MessageBox]::Show($_.Exception.Message, 'DisplayFlip', 'OK', 'Warning')
        }
    })
    [void]$script:menu.Items.Add($editItem)
    $script:menu.Add_Opening({
        try {
            Update-DisplayFlipChecks -Items $script:menu.Items -Config $script:config -Displays @(Get-DisplayInfo -ErrorAction Stop)
        }
        catch {
            foreach ($item in $script:menu.Items) {
                if ($item.Tag -is [hashtable]) { $item.Checked = $false }
            }
        }
    })
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
    if ($script:tray) { $script:tray.ContextMenuStrip = $script:menu }
    if ($oldMenu) { $oldMenu.Dispose() }
}

try {
    Import-Module DisplayConfig -ErrorAction Stop
    [Windows.Forms.Application]::EnableVisualStyles()
    $script:menu = [Windows.Forms.ContextMenuStrip]::new()

    $script:config = Get-DisplayFlipConfig
    Add-Type -Path (Join-Path $PSScriptRoot 'DisplayFlip.Hotkeys.cs') -ReferencedAssemblies System.Windows.Forms
    Initialize-DisplayFlipMenu
    $script:tray = [Windows.Forms.NotifyIcon]::new()
    $script:icon = [Drawing.Icon]::new((Join-Path $PSScriptRoot 'icon.ico'))
    $script:tray.Icon = $script:icon
    $script:tray.Text = 'DisplayFlip'
    $script:tray.ContextMenuStrip = $script:menu
    $script:tray.Visible = $true
    try { Set-MonitorScale -Config $script:config -DisplayNames @($script:config.Monitors.Keys) }
    catch {
        [void][Windows.Forms.MessageBox]::Show(('Could not apply configured display scaling: ' + $_.Exception.Message), 'DisplayFlip', 'OK', 'Warning')
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
