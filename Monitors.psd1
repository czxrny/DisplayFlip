# DisplayFlip settings: use Settings > Save & Apply to apply changes without restarting.
# Monitors: Identity is the device path; add Scale = 100 (or another supported percentage) to set scaling.
# Presets: Label is tray text; Names lists monitor keys to enable; other configured monitors are disabled.
# Hotkey is optional: Ctrl, Alt, Shift, Win plus A-Z or F1-F24, for example Ctrl+Alt+M.
# Keep monitor keys and preset Names consistent. Every preset must enable at least one monitor.
@{
    Monitors = @{
        'LAPTOP' = @{ Identity = 'DISPLAY#AUO51ED#' }
        'LCD' = @{ Identity = 'DISPLAY#HPN375A#'; Scale = 100 }
        'OLED' = @{ Identity = 'DISPLAY#CND3CF8#' }
    }
    Presets = @(
        @{ Label = 'OLED'; Names = @('OLED'); Hotkey = 'Ctrl+Alt+F1' },
        @{ Label = 'LCD'; Names = @('LCD'); Hotkey = 'Ctrl+Alt+F2' },
        @{ Label = 'OLED + LCD'; Names = @('OLED', 'LCD'); Hotkey = 'Ctrl+Alt+F3' },
        @{ Label = 'Laptop + LCD'; Names = @('LCD', 'LAPTOP'); Hotkey = 'Ctrl+Alt+F4' },
        @{ Label = 'All displays'; Names = @('OLED', 'LCD', 'LAPTOP'); Hotkey = 'Ctrl+Alt+F5' }
    )
}
