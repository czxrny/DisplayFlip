$ErrorActionPreference = 'Stop'
$tokens = $null; $errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile("$PSScriptRoot\DisplayFlip.ps1", [ref]$tokens, [ref]$errors)
if ($errors) { throw ($errors | Out-String) }
$ast.FindAll({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] }, $false) | ForEach-Object { Invoke-Expression $_.Extent.Text }
$script:config = Get-DisplayFlipConfig -Path "$PSScriptRoot\Monitors.Example.psd1"
if ($script:config.Presets.Count -ne 5) { throw 'Unexpected default presets.' }
$binding = ConvertTo-DisplayFlipHotkey 'Shift+Ctrl+F24'
if ($binding.Modifiers -ne 6 -or $binding.Key -ne 135) { throw 'Incorrect hotkey mapping.' }
foreach ($value in @('Ctrl+Ctrl+F1', 'Alt+Enter', 'Ctrl+F25', 'Ctrl+AB', 'Ctrl+1')) {
    $rejected = $false
    try { ConvertTo-DisplayFlipHotkey $value | Out-Null } catch { $rejected = $true }
    if (-not $rejected) { throw "Invalid hotkey accepted: $value" }
}
foreach ($letter in @('a', 'M', 'z')) {
    $binding = ConvertTo-DisplayFlipHotkey "Ctrl+Shift+$letter"
    if ($binding.Modifiers -ne 6 -or $binding.Key -ne [uint32][char]$letter.ToUpperInvariant()) { throw 'Incorrect letter hotkey mapping.' }
}
function Get-DisplayInfo {
    [pscustomobject]@{ DevicePath = 'DISPLAY#CND3CF8#test'; DisplayId = 1; Active = $true }
    [pscustomobject]@{ DevicePath = 'DISPLAY#HPN375A#test'; DisplayId = 2; Active = $true }
    [pscustomobject]@{ DevicePath = 'unknown'; DisplayId = 9; Active = $true }
}
function Enable-Display {
    param($DisplayId, $DisplayIdToDisable, $ErrorAction)
    if (@($DisplayId).Count -ne 1 -or $DisplayId[0] -ne 2 -or @($DisplayIdToDisable).Count -ne 1 -or $DisplayIdToDisable[0] -ne 1) { throw 'Incorrect display targets.' }
    $script:enabled = $true
}
function Set-DisplayScale {
    param($DisplayId, $Scale, $ErrorAction)
    if ($DisplayId -ne 2 -or $Scale -ne 100) { throw 'Incorrect scaling.' }
    $script:scaled = $true
}
Set-MonitorPreset -Preset $script:config.Presets[1]
if (-not $script:enabled -or -not $script:scaled) { throw 'Expected display calls were not made.' }
$rejected = $false
try { Set-MonitorPreset -Preset @{ Names = @('LAPTOP') } } catch { $rejected = $true }
if (-not $rejected) { throw 'Disconnected preset accepted.' }
$automatic = New-DisplayFlipConfig -Displays @(
    [pscustomobject]@{ DevicePath = 'path-b'; DisplayName = 'Same' },
    [pscustomobject]@{ DevicePath = 'path-a'; DisplayName = 'Same' },
    [pscustomobject]@{ DevicePath = 'path-c'; DisplayName = '' }
)
if ($automatic.Monitors.Count -ne 3 -or $automatic.Presets.Count -ne 7) { throw 'Automatic presets are incomplete.' }
if ($automatic.Monitors.Display1.Identity -ne 'path-a') { throw 'Device paths were not assigned deterministically.' }
if ($automatic.Presets[0].Label -ne 'Same (1)' -or $automatic.Presets[1].Label -ne 'Same (2)' -or $automatic.Presets[2].Label -ne 'Display (3)') { throw 'Ambiguous or empty display names were not handled.' }
if ($automatic.Presets[3].Names.Count -ne 3 -or $automatic.Presets[3].Hotkey -ne 'Ctrl+Alt+F4') { throw 'Incorrect all-displays preset.' }
if ($automatic.Monitors.Display1.ContainsKey('Scale')) { throw 'Automatic configuration must preserve scaling.' }
foreach ($displays in @(@(), @([pscustomobject]@{ DevicePath = 'same' }, [pscustomobject]@{ DevicePath = 'same' }))) {
    $rejected = $false
    try { New-DisplayFlipConfig -Displays $displays | Out-Null } catch { $rejected = $true }
    if (-not $rejected) { throw 'Empty or ambiguous discovery accepted.' }
}
$single = New-DisplayFlipConfig -Displays @([pscustomobject]@{ DevicePath = 'single'; DisplayName = 'Desk' })
if ($single.Presets.Count -ne 1) { throw 'Single display should have one preset.' }
foreach ($count in @(2, 3, 4, 8, 9)) {
    $displays = @(1..$count | ForEach-Object { [pscustomobject]@{ DevicePath = "path-$_"; DisplayName = 'Same' } })
    $generated = New-DisplayFlipConfig -Displays $displays
    $expectedCount = if ($count -le 8) { [int][Math]::Pow(2, $count) - 1 } else { $count + 1 }
    if ($generated.Presets.Count -ne $expectedCount) { throw "Incorrect combination count for $count displays." }
    $unique = @($generated.Presets | ForEach-Object { ($_.Names | Sort-Object) -join ',' } | Select-Object -Unique)
    if ($unique.Count -ne $expectedCount) { throw 'Duplicate combinations generated.' }
    foreach ($preset in $generated.Presets) {
        if ($preset.Names.Count -eq 0) { throw 'All-off preset generated.' }
        if ($preset.Names.Count -gt 1 -and $preset.Names.Count -lt $count -and $preset.ContainsKey('Hotkey')) { throw 'Combination must not override existing hotkeys.' }
    }
}
$savedPath = Join-Path ([IO.Path]::GetTempPath()) ('DisplayFlip-' + [Guid]::NewGuid().ToString('N') + '.psd1')
if ((Get-DisplayFlipConfig -Path $savedPath).Monitors.Count -ne 3) { throw 'Missing config did not use discovery.' }
if (-not (Test-Path -LiteralPath $savedPath)) { throw 'Discovered config was not saved.' }
$savedText = [IO.File]::ReadAllText($savedPath)
$edited = Import-PowerShellDataFile -LiteralPath $savedPath
$edited.Monitors.Display1.Scale = 125
$edited.Presets[0].Label = "Desk's display"
$edited.Presets[0].Hotkey = 'Ctrl+Alt+M'
Save-DisplayFlipConfig -Config $edited -Path $savedPath -Replace
$reloaded = Get-DisplayFlipConfig -Path $savedPath
if ($reloaded.Monitors.Display1.Scale -ne 125 -or $reloaded.Presets[0].Label -ne "Desk's display" -or $reloaded.Presets[0].Hotkey -ne 'Ctrl+Alt+M') { throw 'Edited settings did not round-trip.' }
if (@(Get-ChildItem -LiteralPath ([IO.Path]::GetDirectoryName($savedPath)) -Filter (([IO.Path]::GetFileName($savedPath)) + '.*.bak')).Count -ne 1) { throw 'Previous settings were not backed up.' }
$savedText = [IO.File]::ReadAllText($savedPath)
if ($savedText -notmatch '# Presets:' -or $savedText -notmatch '# Hotkey') { throw 'Generated configuration lacks editing instructions.' }
$checkConfig = @{ Monitors = @{ A = @{ Identity = 'path-a' }; B = @{ Identity = 'path-b' } } }
$items = @(
    [pscustomobject]@{ Tag = @{ Names = @('A') }; Checked = $false },
    [pscustomobject]@{ Tag = @{ Names = @('A', 'B') }; Checked = $true }
)
Update-DisplayFlipChecks -Items $items -Config $checkConfig -Displays @(
    [pscustomobject]@{ DevicePath = 'path-a'; Active = $true },
    [pscustomobject]@{ DevicePath = 'path-b'; Active = $false }
)
if (-not $items[0].Checked -or $items[1].Checked) { throw 'Active preset checkmarks are incorrect.' }
Update-DisplayFlipChecks -Items $items -Config $checkConfig -Displays @()
if ($items[0].Checked -or $items[1].Checked) { throw 'Stale checkmarks were retained.' }
function Get-DisplayInfo { throw 'Discovery must not run when a configuration file exists.' }
if ((Get-DisplayFlipConfig -Path $savedPath).Presets.Count -ne 7) { throw 'Saved configuration did not round-trip.' }
if ([IO.File]::ReadAllText($savedPath) -ne $savedText) { throw 'Existing configuration was modified.' }
if ((Get-DisplayFlipConfig -Path "$PSScriptRoot\Monitors.psd1").Presets.Count -ne 5) { throw 'Existing config was not loaded.' }
function Import-PowerShellDataFile { param($LiteralPath, $ErrorAction) return $script:invalidConfig }
foreach ($value in @(@{}, @{ AutoConfigure = $true })) {
    $script:invalidConfig = $value
    $rejected = $false
    try { Get-DisplayFlipConfig -Path "$PSScriptRoot\Monitors.psd1" | Out-Null } catch { $rejected = $true }
    if (-not $rejected) { throw 'Invalid existing configuration accepted.' }
}
$script:invalidConfig = @{ Monitors = @{ Desk = @{ Identity = 'test' } }; Presets = @(@{ Label = 'Bad'; Names = @('Missing') }) }
$rejected = $false
try { Get-DisplayFlipConfig -Path "$PSScriptRoot\Monitors.psd1" | Out-Null } catch { $rejected = $true }
if (-not $rejected) { throw 'Unknown monitor accepted.' }
$script:invalidConfig.Presets = @(@{ Label = 'A'; Names = @('Desk'); Hotkey = 'Ctrl+Alt+F1' }, @{ Label = 'B'; Names = @('Desk'); Hotkey = 'Alt+Ctrl+F1' })
$rejected = $false
try { Get-DisplayFlipConfig -Path "$PSScriptRoot\Monitors.psd1" | Out-Null } catch { $rejected = $true }
if (-not $rejected) { throw 'Duplicate hotkey accepted.' }
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms
$settingsFunction = $ast.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Show-DisplayFlipSettings' }, $false).Extent.Text
$settingsFunction = $settingsFunction.Replace('function Show-DisplayFlipSettings', 'function Test-SettingsConstruction').Replace('[void]$form.ShowDialog()', @'
if ($monitors.Rows.Count -ne $script:config.Monitors.Count) { throw 'Settings monitor rows are incomplete.' }
if ($presets.Rows.Count -ne $script:config.Presets.Count + 1) { throw 'Settings preset rows are incomplete.' }
if ($save.Text -ne 'Save & Apply') { throw 'Save action is missing.' }
'@)
Invoke-Expression $settingsFunction
Test-SettingsConstruction
'PASS: discovery, configuration validation, hotkeys, mocked switching, scaling, and disconnected displays.'
