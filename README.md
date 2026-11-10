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
2. Edit `Monitors.psd1` to map `OLED`, `LCD`, and `LAPTOP` to your displays. The included values describe the original setup; replace them before use. Use a full `DevicePath` if a model identifier matches multiple monitors.
3. Run `Start-DisplayFlip.cmd` and right-click the tray icon to choose a preset.

Keep `DisplayFlip.ps1`, `DisplayFlip.Hotkeys.cs`, `Monitors.psd1`, and `icon.ico` together. The launchers and `Autostart.ps1` should remain in the same folder. `icon.png` is the source artwork for the tray icon.

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

At startup and after selecting a preset containing LCD, DisplayFlip sets the active LCD display to 100% scaling. Disconnected or inactive LCD displays are skipped. Other displays are not scaled. The app does not explicitly set resolution, refresh rate, position, or the primary display.

Monitor identities are read from `Monitors.psd1` without restarting. Presets, hotkeys, and the LCD scaling rule are currently defined in `DisplayFlip.ps1`.

## Start with Windows

Run `Enable-Autostart.cmd` to start DisplayFlip at sign-in for your account. Run `Disable-Autostart.cmd` to disable it. Administrator access is not required. Disabled shortcuts are preserved under `%LOCALAPPDATA%\DisplayFlip\DisabledStartup`.

The startup shortcut points to the current application folder. If you move the folder, enable autostart again to update it.

### Upgrading from MonitorTray

Exit MonitorTray and disable its autostart before launching DisplayFlip. If you already renamed the files, move the old `MonitorTray.lnk` out of your Windows Startup folder (`shell:startup`) to a backup folder. Then run `Enable-Autostart.cmd` to create the new `DisplayFlip.lnk` shortcut.
