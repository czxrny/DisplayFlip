# Save changes, then exit and restart DisplayFlip.
# Monitors: Identity identifies the display; optional Scale sets its scaling percentage.
# Presets: Label is tray text; Names lists monitor keys to enable; others are disabled.
# Hotkey is optional: Ctrl, Alt, Shift, Win plus F1-F24. Keep Names consistent with monitor keys.
@{
    Monitors = @{
        OLED = @{ Identity = 'DISPLAY#CND3CF8#' }
        LCD = @{ Identity = 'DISPLAY#HPN375A#'; Scale = 100 }
        LAPTOP = @{ Identity = 'DISPLAY#AUO51ED#' }
    }
    Presets = @(
        @{ Label = 'OLED'; Names = @('OLED'); Hotkey = 'Ctrl+Alt+F1' },
        @{ Label = 'LCD'; Names = @('LCD'); Hotkey = 'Ctrl+Alt+F2' },
        @{ Label = 'OLED + LCD'; Names = @('OLED', 'LCD'); Hotkey = 'Ctrl+Alt+F3' },
        @{ Label = 'Laptop + LCD'; Names = @('LCD', 'LAPTOP'); Hotkey = 'Ctrl+Alt+F4' },
        @{ Label = 'All displays'; Names = @('OLED', 'LCD', 'LAPTOP'); Hotkey = 'Ctrl+Alt+F5' }
    )
}
