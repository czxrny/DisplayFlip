$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\DisplayFlip.Configuration.ps1"
$script:config = Get-DisplayFlipConfig -Path "$PSScriptRoot\Monitors.Example.psd1"
if ($script:config.Presets.Count -ne 5) { throw 'Unexpected default presets.' }
$binding = ConvertTo-DisplayFlipHotkey 'Shift+Ctrl+F24'
if ($binding.Modifiers -ne 6 -or $binding.Key -ne 135) { throw 'Incorrect hotkey mapping.' }
foreach ($value in @('Ctrl+Ctrl+F1', 'Alt+X', 'Ctrl+F25')) {
    $rejected = $false
    try { ConvertTo-DisplayFlipHotkey $value | Out-Null } catch { $rejected = $true }
    if (-not $rejected) { throw "Invalid hotkey accepted: $value" }
}
$tokens = $null; $errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile("$PSScriptRoot\DisplayFlip.ps1", [ref]$tokens, [ref]$errors)
if ($errors) { throw ($errors | Out-String) }
$ast.FindAll({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] }, $false) | ForEach-Object { Invoke-Expression $_.Extent.Text }
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
if ($automatic.Monitors.Count -ne 3 -or $automatic.Presets.Count -ne 4) { throw 'Automatic presets are incomplete.' }
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
function Import-PowerShellDataFile { param($LiteralPath, $ErrorAction) return $script:invalidConfig }
$script:invalidConfig = @{ AutoConfigure = $true }
if ((Get-DisplayFlipConfig).Monitors.Count -ne 3) { throw 'Automatic configuration was not loaded.' }
$script:invalidConfig = @{ Monitors = @{ Desk = @{ Identity = 'test' } }; Presets = @(@{ Label = 'Bad'; Names = @('Missing') }) }
$rejected = $false
try { Get-DisplayFlipConfig | Out-Null } catch { $rejected = $true }
if (-not $rejected) { throw 'Unknown monitor accepted.' }
$script:invalidConfig.Presets = @(@{ Label = 'A'; Names = @('Desk'); Hotkey = 'Ctrl+Alt+F1' }, @{ Label = 'B'; Names = @('Desk'); Hotkey = 'Alt+Ctrl+F1' })
$rejected = $false
try { Get-DisplayFlipConfig | Out-Null } catch { $rejected = $true }
if (-not $rejected) { throw 'Duplicate hotkey accepted.' }
'PASS: discovery, configuration validation, hotkeys, mocked switching, scaling, and disconnected displays.'
