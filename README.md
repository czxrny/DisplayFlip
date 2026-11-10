# DisplayFlip

A small Windows system tray app for switching monitor combinations with a menu or global hotkeys. Powered by the [DisplayConfig PowerShell module](https://github.com/MartinGC94/DisplayConfig).

## Requirements

- Windows with Windows PowerShell 5.1 and a desktop session.
- The DisplayConfig module installed for the current user:

```powershell
Install-Module DisplayConfig -Scope CurrentUser
```

## Setup

1. Run `Show-Diagnostics.cmd` to list your displays and their `DevicePath` values.
2. Edit `Monitors.psd1` to define your monitor identities, presets, hotkeys, and optional scaling. The included values describe the original setup; replace them before use. Use a full `DevicePath` if a model identifier matches multiple monitors.
3. Run `Start-DisplayFlip.cmd` and right-click the tray icon to choose a preset.

Keep `DisplayFlip.ps1`, `DisplayFlip.Hotkeys.cs`, `DisplayFlip.Configuration.ps1`, `Monitors.psd1`, and `icon.ico` together. The launchers and `Autostart.ps1` should remain in the same folder. `icon.png` is the source artwork for the tray icon.

## Presets and hotkeys

| Preset | Hotkey |
| --- | --- |
| OLED | Ctrl+Alt+F1 |
| LCD | Ctrl+Alt+F2 |
| OLED + LCD | Ctrl+Alt+F3 |
| Laptop + LCD | Ctrl+Alt+F4 |
| All displays | Ctrl+Alt+F5 |

Hotkeys work while other apps are active. Holding a hotkey does not repeat the command. If another app has registered a hotkey, DisplayFlip reports the conflict; the tray menu remains available.

Display identities are resolved again on each selection. Missing displays are skipped. If none of the requested displays are connected, the operation is blocked. Ambiguous or duplicate mappings also block the operation. Unconfigured displays are left unchanged.

Each preset enables its target displays and disables the other configured displays in one `Enable-Display` call. The menu may briefly stop responding while the command runs. There is no polling or background timer.

## Scaling

An optional `Scale` value on each monitor sets its scaling percentage at startup and after selecting a preset containing that monitor. The supplied configuration sets LCD to 100%. Omit `Scale` to leave scaling unchanged. Disconnected or inactive displays are skipped. Windows must support the requested scaling percentage for that display. The app does not explicitly set resolution, refresh rate, position, or the primary display.

## Configuration

All monitor and preset settings live in `Monitors.psd1`. Restart DisplayFlip after editing it.

```powershell
@{
    Monitors = @{
        Desk = @{ Identity = 'DISPLAY#YOUR_MODEL#'; Scale = 100 }
        Laptop = @{ Identity = 'DISPLAY#YOUR_PANEL#' }
    }
    Presets = @(
        @{ Label = 'Desk only'; Names = @('Desk'); Hotkey = 'Ctrl+Alt+F1' },
        @{ Label = 'Both'; Names = @('Desk', 'Laptop'); Hotkey = 'Ctrl+Alt+F2' }
    )
}
```

Monitor names are arbitrary keys shared by `Monitors` and preset `Names`. Preset order determines menu order. Each preset needs a label and at least one configured monitor. The app rejects unknown monitor names, repeated names, and duplicate hotkeys.

`Hotkey` is optional; omit it or use an empty string for a menu-only preset. Supported keys are F1-F24 with optional Ctrl, Alt, Shift, and Win modifiers, for example `Ctrl+Shift+F8`. Modifier order and capitalization do not matter.

`Scale` must be an integer from 100 to 500; actual supported percentages depend on the monitor and Windows. The supplied five presets preserve the original setup. There is no built-in limit of three monitors or five presets.

## Start with Windows

Run `Enable-Autostart.cmd` to start DisplayFlip at sign-in for your account. Run `Disable-Autostart.cmd` to disable it. Administrator access is not required. Disabled shortcuts are preserved under `%LOCALAPPDATA%\DisplayFlip\DisabledStartup`.

The startup shortcut points to the current application folder. If you move the folder, enable autostart again to update it.

### Upgrading from MonitorTray

Exit MonitorTray and disable its autostart before launching DisplayFlip. If you already renamed the files, move the old `MonitorTray.lnk` out of your Windows Startup folder (`shell:startup`) to a backup folder. Then run `Enable-Autostart.cmd` to create the new `DisplayFlip.lnk` shortcut.
