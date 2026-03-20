#Requires AutoHotkey v2.0+
#SingleInstance Force
Persistent()

; ============================================================
; CLIPBOARD MANAGER - Entry Point
; ============================================================
; Hotkey: Ctrl+Shift+V to toggle window
; Fast paste: Hold Ctrl+Shift, type slot number, press Enter
;             Supports unlimited slots (1-999+)
; ============================================================

#include .\clipboard_core.ahk
#include .\clipboard_gui.ahk

; Load saved history
CB_LoadHistory()

; Build and show the GUI
CB_BuildGUI()

; ---- Global Hotkey: Toggle clipboard window ----
^+v:: {
    global cbGui
    if WinExist("ahk_id " cbGui.Hwnd) {
        if DllCall("IsWindowVisible", "Ptr", cbGui.Hwnd)
            cbGui.Hide()
        else
            cbGui.Show()
    }
}

; ============================================================
; FAST PASTE - Hold Ctrl+Shift, type slot number, press Enter
; Works for any slot 1-999+
; Tooltip shows current number while typing
; Escape or 3s timeout = silent abort
; ============================================================

For _k in ["1","2","3","4","5","6","7","8","9","0"] {
    Hotkey("^+" _k, CB_SlotEntry)
}

CB_SlotEntry(thisHotkey) {
    firstDigit := SubStr(thisHotkey, StrLen(thisHotkey))

    ToolTip("Slot: " firstDigit)

    ih := InputHook("L3 T3", "{Enter}{Escape}")
    ih.Start()
    ih.Wait()
    ToolTip()

    fullInput := firstDigit . ih.Input

    if ih.EndReason = "EndKey" && InStr(ih.EndKey, "Enter") {
        if RegExMatch(fullInput, "^\d+$")
            CB_PasteItem(Integer(fullInput))
    }
}
