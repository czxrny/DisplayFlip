function Get-DisplayFlipConfig {
    $config = Import-PowerShellDataFile -LiteralPath (Join-Path $PSScriptRoot 'Monitors.psd1') -ErrorAction Stop
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

function ConvertTo-DisplayFlipHotkey {
    param([string]$Hotkey)

    $parts = @($Hotkey.Split('+') | ForEach-Object { $_.Trim() })
    $modifiers = 0
    $modifierValues = @{ Alt = 1; Ctrl = 2; Shift = 4; Win = 8 }
    for ($i = 0; $i -lt $parts.Count - 1; $i++) {
        $part = $parts[$i]
        if (-not $modifierValues.ContainsKey($part) -or ($modifiers -band $modifierValues[$part])) {
            throw "Invalid hotkey: $Hotkey. Use modifiers Ctrl, Alt, Shift, Win and a key F1-F24."
        }
        $modifiers = $modifiers -bor $modifierValues[$part]
    }
    if ($parts[-1] -notmatch '^F([1-9]|1[0-9]|2[0-4])$') {
        throw "Invalid hotkey: $Hotkey. Use a function key F1-F24."
    }
    return @{ Modifiers = [uint32]$modifiers; Key = [uint32](111 + [int]$Matches[1]) }
}
