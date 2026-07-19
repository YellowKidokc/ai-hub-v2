#Requires AutoHotkey v2.0+
; ============================================================
; Module: Keep Going — safe "continue work" nudger
; ============================================================
; A deliberate keepalive, NOT a runaway auto-sender.
;   Nudge Now      — paste (or paste+send) the prompt once, right now
;   Start KeepGoing— repeat on an interval (5/10/15/30 min)
;   Stop           — emergency stop, always available
;
; Safety rules baked in:
;   - Auto-send is OFF by default. With it off, the timer only PASTES the
;     prompt into the target and leaves you to press Send.
;   - A visible countdown shows when the next nudge fires.
;   - A per-session "max sends" cap auto-stops the loop.
;   - Sending confirms the target window exists before touching the keyboard.
;
; Hotkeys:
;   Ctrl+Alt+N        Nudge Now
;   Ctrl+Alt+J        Start / Stop KeepGoing
;   Ctrl+Alt+Shift+J  Emergency Stop
; ============================================================

global KA_DEFAULT_PROMPT := "Continue from the last checkpoint. Give me:`n"
    . "1. current status`n"
    . "2. next concrete action`n"
    . "3. anything blocking you`n"
    . "Then proceed if safe."

; ---- Runtime state ----
global gKA_Active     := false
global gKA_SendsUsed  := 0
global gKA_NextFire   := 0      ; A_TickCount (ms) of the next scheduled nudge
global gKA_IntervalMs := 600000 ; captured at Start so mid-run edits don't surprise you

; ---- Register tab (hub mode only) ----
if IsSet(HUB_CORE_LOADED)
    RegisterTab("Keep Going", Build_KeepAliveTab, 48)

Build_KeepAliveTab() {
    global gShell, DARK_TEXT, KA_DEFAULT_PROMPT

    gShell.gui.SetFont("s13 Bold c" DARK_TEXT, "Segoe UI")
    gShell.gui.Add("Text", "xm+15 ym+45", "Keep Going")
    gShell.gui.SetFont("s9 Norm c888888", "Segoe UI")
    gShell.gui.Add("Text", "xm+15 y+7 w620", "Nudge an AI to continue working. Auto-send is OFF by default — the timer only "
        . "pastes your prompt unless you explicitly turn Auto-send on. Stop is always available.")

    ; ---- Target ----
    gShell.gui.SetFont("s9 Norm c" DARK_TEXT, "Segoe UI")
    gShell.gui.Add("Text", "xm+15 y+18 w120", "Target window")
    gShell.kaTargetCombo := gShell.gui.Add("ComboBox", "xm+140 yp-3 w300",
        ["Claude", "Claude Code", "ChatGPT", "Kimi", "Codex", "Gemini", "TopMind"])
    gShell.kaTargetCombo.Text := "Claude"
    ApplyDarkTheme(gShell.kaTargetCombo)
    ApplyInputTheme(gShell.kaTargetCombo)
    gShell.gui.SetFont("s8 c888888")
    gShell.gui.Add("Text", "xm+140 y+3 w300", "Matches any window whose title contains this text.")

    ; ---- Interval ----
    gShell.gui.SetFont("s9 Norm c" DARK_TEXT, "Segoe UI")
    gShell.gui.Add("Text", "xm+15 y+12 w120", "Interval")
    gShell.kaIntervalDDL := gShell.gui.Add("DropDownList", "xm+140 yp-3 w120 Choose2", ["5 min", "10 min", "15 min", "30 min"])
    ApplyDarkTheme(gShell.kaIntervalDDL)
    ApplyInputTheme(gShell.kaIntervalDDL)

    ; ---- Send mode ----
    gShell.gui.Add("Text", "xm+15 y+12 w120", "Send mode")
    gShell.kaModeDDL := gShell.gui.Add("DropDownList", "xm+140 yp-3 w160 Choose1", ["Paste only", "Paste + Send"])
    ApplyDarkTheme(gShell.kaModeDDL)
    ApplyInputTheme(gShell.kaModeDDL)

    ; ---- Auto-send gate ----
    gShell.gui.Add("Text", "xm+15 y+12 w120", "Auto-send on timer")
    gShell.kaAutoSend := gShell.gui.Add("CheckBox", "xm+140 yp-2 c" DARK_TEXT, " Let the timer press Enter automatically")
    gShell.kaAutoSend.Value := 0

    ; ---- Max sends ----
    gShell.gui.Add("Text", "xm+15 y+14 w120", "Max sends / session")
    gShell.kaMaxEdit := gShell.gui.Add("Edit", "xm+140 yp-3 w80 Number", "10")
    ApplyDarkTheme(gShell.kaMaxEdit)
    ApplyInputTheme(gShell.kaMaxEdit)
    gShell.gui.SetFont("s8 c888888")
    gShell.gui.Add("Text", "x+12 yp+3 w220", "0 = unlimited (not recommended)")

    ; ---- Prompt template ----
    gShell.gui.SetFont("s9 Norm c" DARK_TEXT, "Segoe UI")
    gShell.gui.Add("Text", "xm+15 y+16", "Prompt template")
    gShell.kaPromptEdit := gShell.gui.Add("Edit", "xm+15 y+6 w560 r5", KA_DEFAULT_PROMPT)
    ApplyDarkTheme(gShell.kaPromptEdit)
    ApplyInputTheme(gShell.kaPromptEdit)

    ; ---- Buttons ----
    gShell.kaBtnNudge := gShell.gui.Add("Button", "xm+15 y+12 w130", "Nudge Now")
    gShell.kaBtnNudge.OnEvent("Click", (*) => KA_Nudge(false))
    ApplyDarkTheme(gShell.kaBtnNudge)

    gShell.kaBtnStart := gShell.gui.Add("Button", "x+10 w150", "Start KeepGoing")
    gShell.kaBtnStart.OnEvent("Click", KA_Start)
    ApplyDarkTheme(gShell.kaBtnStart)

    gShell.kaBtnStop := gShell.gui.Add("Button", "x+10 w120", "Stop")
    gShell.kaBtnStop.OnEvent("Click", KA_Stop)
    ApplyDarkTheme(gShell.kaBtnStop)

    ; ---- Status + hotkey hint ----
    gShell.gui.SetFont("s10 Bold c" DARK_TEXT, "Segoe UI")
    gShell.kaStatus := gShell.gui.Add("Text", "xm+15 y+18 w560", "KEEPGOING OFF")
    gShell.gui.SetFont("s8 Norm c888888", "Segoe UI")
    gShell.gui.Add("Text", "xm+15 y+10 w560", "Hotkeys:  Ctrl+Alt+N Nudge Now   ·   Ctrl+Alt+J Start/Stop   ·   Ctrl+Alt+Shift+J Emergency Stop")

    KA_UpdateButtons()
}

; ---- Read interval (ms) from the dropdown ----
KA_IntervalMs() {
    global gShell
    n := 10
    if IsSet(gShell) && RegExMatch(gShell.kaIntervalDDL.Text, "\d+", &m)
        n := Integer(m[0])
    return n * 60000
}

; ---- Read max-sends cap (0 = unlimited) ----
KA_MaxSends() {
    global gShell
    v := Trim(gShell.kaMaxEdit.Value)
    if (v = "" || !IsInteger(v))
        return 0
    return Integer(v)
}

KA_SetStatus(text) {
    global gShell
    if IsSet(gShell)
        try gShell.kaStatus.Text := text
}

KA_UpdateButtons() {
    global gShell, gKA_Active
    if !IsSet(gShell)
        return
    try {
        gShell.kaBtnStart.Text := gKA_Active ? "Running…" : "Start KeepGoing"
        gShell.kaBtnStart.Enabled := !gKA_Active
        gShell.kaBtnStop.Enabled := gKA_Active
    }
}

; ---- Core send: paste the prompt into the target, optionally press Enter ----
KA_DoSend(allowEnter) {
    global gShell
    title := Trim(gShell.kaTargetCombo.Text)
    if (title = "") {
        KA_SetStatus("No target window set")
        return false
    }
    prompt := gShell.kaPromptEdit.Value
    if (Trim(prompt) = "") {
        KA_SetStatus("Prompt template is empty")
        return false
    }
    hwnd := WinExist(title)
    if !hwnd {
        KA_SetStatus("Target not found: " title)
        TrayTip("KeepGoing: no window matching '" title "'", "Keep Going", 2)
        return false
    }

    saved := ClipboardAll()
    A_Clipboard := prompt
    ClipWait(1)
    sent := false
    try {
        WinActivate("ahk_id " hwnd)
        WinWaitActive("ahk_id " hwnd, , 1)
        Sleep(120)
        Send("^v")
        Sleep(80)
        if allowEnter
            Send("{Enter}")
        sent := true
    }
    Sleep(150)
    A_Clipboard := saved
    return sent
}

; ---- One nudge. fromTimer gates auto-send. ----
KA_Nudge(fromTimer := false) {
    global gShell, gKA_SendsUsed
    if !IsSet(gShell)
        return false
    allowEnter := (gShell.kaModeDDL.Text = "Paste + Send")
    if fromTimer
        allowEnter := allowEnter && (gShell.kaAutoSend.Value = 1)
    if KA_DoSend(allowEnter) {
        gKA_SendsUsed += 1
        verb := allowEnter ? "sent" : "pasted"
        KA_SetStatus("Nudge " verb "  ·  " gKA_SendsUsed " this session")
        return true
    }
    return false
}

KA_Start(*) {
    global gShell, gKA_Active, gKA_NextFire, gKA_IntervalMs
    if !IsSet(gShell) || gKA_Active
        return
    if (Trim(gShell.kaTargetCombo.Text) = "") {
        MsgBox("Set a target window first.", "Keep Going", "Icon!")
        return
    }
    gKA_Active := true
    gKA_IntervalMs := KA_IntervalMs()
    gKA_NextFire := A_TickCount + gKA_IntervalMs
    SetTimer(KA_Tick, gKA_IntervalMs)
    SetTimer(KA_Countdown, 1000)
    KA_UpdateButtons()
    KA_Countdown()
}

KA_Stop(*) {
    global gKA_Active
    gKA_Active := false
    SetTimer(KA_Tick, 0)
    SetTimer(KA_Countdown, 0)
    KA_UpdateButtons()
    KA_SetStatus("KEEPGOING OFF")
}

KA_Toggle(*) {
    global gKA_Active
    if gKA_Active
        KA_Stop()
    else
        KA_Start()
}

KA_Tick() {
    global gKA_Active, gKA_SendsUsed, gKA_NextFire, gKA_IntervalMs
    if !gKA_Active
        return
    maxSends := KA_MaxSends()
    if (maxSends > 0 && gKA_SendsUsed >= maxSends) {
        KA_Stop()
        KA_SetStatus("Stopped: hit max " maxSends " sends this session")
        TrayTip("KeepGoing stopped — max sends reached", "Keep Going", 1)
        return
    }
    KA_Nudge(true)
    gKA_NextFire := A_TickCount + gKA_IntervalMs
}

KA_Countdown() {
    global gKA_Active, gKA_NextFire, gKA_SendsUsed
    if !gKA_Active
        return
    remain := gKA_NextFire - A_TickCount
    if (remain < 0)
        remain := 0
    secs := Integer(Round(remain / 1000))
    mm := Format("{:02}", secs // 60)
    ss := Format("{:02}", Mod(secs, 60))
    KA_SetStatus("KEEPGOING ON  ·  next nudge in " mm ":" ss "  ·  sends: " gKA_SendsUsed)
}

; ============================================================
; Global hotkeys (hub mode)
; ============================================================
^!n:: {
    global gShell
    if IsSet(gShell)
        KA_Nudge(false)
}
^!j:: {
    global gShell
    if IsSet(gShell)
        KA_Toggle()
}
^!+j:: {
    global gShell
    if IsSet(gShell)
        KA_Stop()
}
