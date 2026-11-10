$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\DisplayFlip.Configuration.ps1"
$script:config = Get-DisplayFlipConfig
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
function Import-PowerShellDataFile { param($LiteralPath, $ErrorAction) return $script:invalidConfig }
$script:invalidConfig = @{ Monitors = @{ Desk = @{ Identity = 'test' } }; Presets = @(@{ Label = 'Bad'; Names = @('Missing') }) }
$rejected = $false
try { Get-DisplayFlipConfig | Out-Null } catch { $rejected = $true }
if (-not $rejected) { throw 'Unknown monitor accepted.' }
$script:invalidConfig.Presets = @(@{ Label = 'A'; Names = @('Desk'); Hotkey = 'Ctrl+Alt+F1' }, @{ Label = 'B'; Names = @('Desk'); Hotkey = 'Alt+Ctrl+F1' })
$rejected = $false
try { Get-DisplayFlipConfig | Out-Null } catch { $rejected = $true }
if (-not $rejected) { throw 'Duplicate hotkey accepted.' }
'PASS: configuration validation, hotkeys, mocked switching, scaling, and disconnected displays.'
