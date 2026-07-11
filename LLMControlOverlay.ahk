#Requires AutoHotkey v2.0+
#SingleInstance Force
#Warn

; LLM Control Overlay for desktop LLM applications.
; Run with AutoHotkey v2. Settings are stored in config\llm_overlay.ini.

class App {
    static ConfigPath := A_ScriptDir "\config\llm_overlay.ini"
    static Store := ""
    static Tracker := ""
    static Overlay := ""
    static Dispatcher := ""
    static Api := ""
    static Log := ""
    static Suspended := false

    static Start() {
        DirCreate(A_ScriptDir "\config")
        DirCreate(A_ScriptDir "\logs")
        App.Log := Logger(A_ScriptDir "\logs\llm_overlay.log")
        App.Store := ProfileStore(App.ConfigPath, App.Log)
        App.Store.Load()
        App.Api := ApiClient(App.Store, App.Log)
        App.Tracker := WindowTracker(App.Store, App.Log)
        App.Dispatcher := ActionDispatcher(App.Store, App.Tracker, App.Api, App.Log)
        App.Overlay := OverlayGui(App.Store, App.Tracker, App.Dispatcher, App.Log)
        App.Tracker.OnTargetChanged := ObjBindMethod(App.Overlay, "OnTargetChanged")
        App.Tracker.OnTargetGone := ObjBindMethod(App.Overlay, "OnTargetGone")
        App.Tracker.OnTargetClosed := ObjBindMethod(App.Overlay, "OnTargetClosed")
        App.Tracker.OnGeometryChanged := ObjBindMethod(App.Overlay, "AttachToTarget")
        App.Overlay.Show()
        App.Tracker.Start()
        Hotkey(App.Store.Get("Hotkeys", "ToggleOverlay", "^!o"), (*) => App.Overlay.Toggle())
        Hotkey(App.Store.Get("Hotkeys", "BindWindow", "^!b"), (*) => App.Overlay.BeginBind())
        Hotkey(App.Store.Get("Hotkeys", "Calibrate", "^!k"), (*) => App.Overlay.BeginCalibration())
        Hotkey(App.Store.Get("Hotkeys", "Submit", "^!Enter"), (*) => App.Dispatcher.RunButton("Submit"))
        Hotkey(App.Store.Get("Hotkeys", "EmergencyStop", "^!Esc"), (*) => App.EmergencyStop())
        App.Log.Info("LLM overlay started")
    }

    static EmergencyStop() {
        App.Suspended := !App.Suspended
        Suspend(App.Suspended)
        if IsObject(App.Overlay)
            App.Overlay.SetStatus(App.Suspended ? "Automation suspended" : "Automation resumed", App.Suspended ? "warn" : "ok")
        App.Log.Warn("Emergency suspend toggled: " App.Suspended)
    }
}

class Logger {
    __New(path) => (this.Path := path)
    Info(msg) => this.Write("INFO", msg)
    Warn(msg) => this.Write("WARN", msg)
    Error(msg) => this.Write("ERROR", msg)
    Write(level, msg) {
        safe := RegExReplace(msg, "(?i)(api[_ -]?key|authorization|bearer)\s*[:= ]+[^\s,;]+", "$1=***")
        FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss") " [" level "] " safe "`n", this.Path, "UTF-8")
    }
}

class ProfileStore {
    __New(path, log) {
        this.Path := path, this.Log := log, this.Profile := "Default", this.Buttons := Map(), this.Controls := Map(), this.Templates := Map()
    }
    Load() {
        if !FileExist(this.Path)
            this.CreateDefaults()
        this.Profile := IniRead(this.Path, "General", "ActiveProfile", "Default")
        this.LoadButtons(), this.LoadControls(), this.LoadTemplates()
    }
    Save() {
        IniWrite(this.Profile, this.Path, "General", "ActiveProfile")
        for label, spec in this.Buttons
            IniWrite(spec, this.Path, this.Section("Buttons"), label)
        for name, spec in this.Controls
            IniWrite(spec, this.Path, this.Section("Controls"), name)
        for name, val in this.Templates
            IniWrite(StrReplace(val, "`n", "\n"), this.Path, this.Section("Templates"), name)
    }
    CreateDefaults() {
        defaults := Map(
            "Send Prompt", "type=text|value=Hello, please help me with this task.",
            "Insert Template", "type=function|value=InsertTemplate",
            "Submit", "type=shortcut|value=^Enter",
            "Copy Response", "type=shortcut|value=^c",
            "Clear Input", "type=shortcut|value=^a,{Backspace}",
            "Stop Generation", "type=controlclick|control=stop",
            "New Chat", "type=shortcut|value=^n",
            "Custom Action 1", "type=api|value=/v1/chat/completions",
            "Custom Action 2", "type=clipboardsubmit|value=" )
        IniWrite("Default", this.Path, "General", "ActiveProfile")
        IniWrite("", this.Path, this.Section("Target"), "Hwnd")
        IniWrite("", this.Path, this.Section("Target"), "ProcessName")
        IniWrite("", this.Path, this.Section("Target"), "ExePath")
        IniWrite("", this.Path, this.Section("Target"), "Title")
        IniWrite("", this.Path, this.Section("Target"), "TitlePattern")
        IniWrite("", this.Path, this.Section("Target"), "TargetExecutable")
        IniWrite("https://api.openai.com", this.Path, this.Section("Api"), "Endpoint")
        IniWrite(Obscure(""), this.Path, this.Section("Api"), "ApiKey")
        IniWrite("gpt-4.1-mini", this.Path, this.Section("Api"), "Model")
        IniWrite("0.90", this.Path, this.Section("Overlay"), "Opacity")
        IniWrite("0.02", this.Path, this.Section("Overlay"), "RelX")
        IniWrite("0.05", this.Path, this.Section("Overlay"), "RelY")
        IniWrite("0.20", this.Path, this.Section("Overlay"), "RelW")
        IniWrite("0.45", this.Path, this.Section("Overlay"), "RelH")
        IniWrite("^!o", this.Path, "Hotkeys", "ToggleOverlay")
        IniWrite("^!b", this.Path, "Hotkeys", "BindWindow")
        IniWrite("^!k", this.Path, "Hotkeys", "Calibrate")
        IniWrite("^!Enter", this.Path, "Hotkeys", "Submit")
        IniWrite("^!Esc", this.Path, "Hotkeys", "EmergencyStop")
        for k, v in defaults
            IniWrite(v, this.Path, this.Section("Buttons"), k)
        IniWrite("Write a concise response:", this.Path, this.Section("Templates"), "Default")
    }
    Section(name) => "Profile:" this.Profile ":" name
    Get(section, key, def := "") => IniRead(this.Path, section = "Hotkeys" || section = "General" ? section : this.Section(section), key, def)
    Set(section, key, val) => IniWrite(val, this.Path, section = "Hotkeys" || section = "General" ? section : this.Section(section), key)
    LoadButtons() {
        this.Buttons := Map()
        raw := IniRead(this.Path, this.Section("Buttons"), , "")
        for line in StrSplit(raw, "`n", "`r") {
            if !InStr(line, "=")
                continue
            p := StrSplit(line, "=", , 2), this.Buttons[p[1]] := p[2]
        }
    }
    LoadControls() {
        this.Controls := Map()
        raw := IniRead(this.Path, this.Section("Controls"), , "")
        for line in StrSplit(raw, "`n", "`r") {
            if InStr(line, "=") {
                p := StrSplit(line, "=", , 2), this.Controls[p[1]] := p[2]
            }
        }
    }
    LoadTemplates() {
        this.Templates := Map()
        raw := IniRead(this.Path, this.Section("Templates"), , "")
        for line in StrSplit(raw, "`n", "`r") {
            if InStr(line, "=") {
                p := StrSplit(line, "=", , 2), this.Templates[p[1]] := StrReplace(p[2], "\n", "`n")
            }
        }
    }
    ParseSpec(spec) {
        out := Map()
        for part in StrSplit(spec, "|") {
            if InStr(part, "=") {
                p := StrSplit(part, "=", , 2), out[p[1]] := p[2]
            }
        }
        return out
    }
}

class WindowTracker {
    OnTargetChanged := "", OnTargetGone := "", OnTargetClosed := "", OnGeometryChanged := ""
    __New(store, log) {
        this.Store := store, this.Log := log, this.Hwnd := (store.Get("Target", "Hwnd", "") ? Integer(store.Get("Target", "Hwnd", 0)) : 0), this.Last := ""
    }
    Start() => SetTimer(ObjBindMethod(this, "Tick"), 250)
    Stop() => SetTimer(ObjBindMethod(this, "Tick"), 0)
    Bind(hwnd) {
        if !WinExist("ahk_id " hwnd)
            throw Error("Selected target window no longer exists")
        WinGetPos(&x, &y, &w, &h, "ahk_id " hwnd)
        this.Hwnd := hwnd
        this.Store.Set("Target", "Hwnd", hwnd)
        this.Store.Set("Target", "ProcessName", WinGetProcessName("ahk_id " hwnd))
        this.Store.Set("Target", "ExePath", WinGetProcessPath("ahk_id " hwnd))
        this.Store.Set("Target", "Title", WinGetTitle("ahk_id " hwnd))
        this.Store.Set("Target", "TargetExecutable", WinGetProcessName("ahk_id " hwnd))
        this.Log.Info("Bound to hwnd=" hwnd " process=" WinGetProcessName("ahk_id " hwnd))
        if IsObject(this.OnTargetChanged)
            this.OnTargetChanged.Call(hwnd)
    }
    FindAgain() {
        exe := this.Store.Get("Target", "TargetExecutable", "")
        pat := this.Store.Get("Target", "TitlePattern", "")
        proc := this.Store.Get("Target", "ProcessName", "")
        query := exe ? "ahk_exe " exe : (proc ? "ahk_exe " proc : "")
        if query {
            for hwnd in WinGetList(query) {
                title := WinGetTitle("ahk_id " hwnd)
                if !pat || RegExMatch(title, pat) {
                    this.Hwnd := hwnd, this.Store.Set("Target", "Hwnd", hwnd)
                    return hwnd
                }
            }
        }
        return 0
    }
    Exists() {
        if this.Hwnd && WinExist("ahk_id " this.Hwnd)
            return this.Hwnd
        return this.FindAgain()
    }
    IsMinimized(hwnd) => WinGetMinMax("ahk_id " hwnd) = -1
    IsVisible(hwnd) => DllCall("IsWindowVisible", "ptr", hwnd, "int")
    GetClientRect(hwnd := 0) {
        hwnd := hwnd || this.Exists()
        if !hwnd
            throw Error("Target window not found")
        rc := Buffer(16, 0), pt := Buffer(8, 0)
        DllCall("GetClientRect", "ptr", hwnd, "ptr", rc)
        DllCall("ClientToScreen", "ptr", hwnd, "ptr", pt)
        x := NumGet(pt, 0, "int"), y := NumGet(pt, 4, "int")
        return {x:x, y:y, w:NumGet(rc, 8, "int"), h:NumGet(rc, 12, "int")}
    }
    Tick() {
        hwnd := this.Exists()
        if !hwnd {
            if IsObject(this.OnTargetClosed)
                this.OnTargetClosed.Call()
            return
        }
        if this.IsMinimized(hwnd) || !this.IsVisible(hwnd) {
            if IsObject(this.OnTargetGone)
                this.OnTargetGone.Call("hidden")
            return
        }
        try rc := this.GetClientRect(hwnd)
        catch as e {
            this.Log.Error(e.Message), this.OnTargetGone.Call("error")
            return
        }
        sig := rc.x "," rc.y "," rc.w "," rc.h
        if sig != this.Last {
            this.Last := sig
            if IsObject(this.OnGeometryChanged)
                this.OnGeometryChanged.Call()
        }
    }
}

class OverlayGui {
    __New(store, tracker, dispatcher, log) {
        this.Store := store, this.Tracker := tracker, this.Dispatcher := dispatcher, this.Log := log, this.Visible := false
        this.Gui := Gui("+AlwaysOnTop +Resize +MinSize260x220", "LLM Control Overlay")
        this.Gui.BackColor := "202020"
        this.Gui.SetFont("s9 cFFFFFF", "Segoe UI")
        this.Status := this.Gui.AddText("xm ym w330 h24", "Unbound")
        this.ApiStatus := this.Gui.AddText("x+8 yp w90 h24", "API ?")
        this.Gui.AddButton("xm y+4 w110", "Bind to Window").OnEvent("Click", (*) => this.BeginBind())
        this.Gui.AddButton("x+6 yp w90", "Settings").OnEvent("Click", (*) => SettingsGui(this.Store, this).Show())
        this.Gui.AddButton("x+6 yp w90", "Calibrate").OnEvent("Click", (*) => this.BeginCalibration())
        this.Gui.AddButton("x+6 yp w80", "Inspect").OnEvent("Click", (*) => UIAutomationHelper(this.Log).InspectUnderMouse())
        this.ButtonPanel := this.Gui.AddText("xm y+8 w1 h1", "")
        this.ButtonCtrls := []
        this.BuildButtons()
        this.Gui.OnEvent("Size", ObjBindMethod(this, "OnSize"))
        this.Gui.OnEvent("Close", (*) => this.Hide())
        this.Gui.OnEvent("Escape", (*) => this.Hide())
    }
    BuildButtons() {
        for ctrl in this.ButtonCtrls
            try ctrl.Destroy()
        this.ButtonCtrls := []
        x := 12, y := 85, col := 0
        for label, spec in this.Store.Buttons {
            btn := this.Gui.AddButton("x" x " y" y " w130 h30", label)
            btn.OnEvent("Click", ObjBindMethod(this.Dispatcher, "RunButton", label))
            this.ButtonCtrls.Push(btn)
            col++, x += 138
            if col = 2
                col := 0, x := 12, y += 38
        }
    }
    Show() {
        this.Visible := true
        try this.AttachToTarget()
        catch
            this.Gui.Show("w430 h300")
    }
    Hide() => (this.Visible := false, this.Gui.Hide())
    Toggle() => this.Visible ? this.Hide() : this.Show()
    SetStatus(text, kind := "info") {
        this.Status.Text := text
        this.Status.SetFont("c" (kind="error" ? "FF6060" : kind="ok" ? "70FF70" : kind="warn" ? "FFD166" : "FFFFFF"))
    }
    OnTargetChanged(hwnd) => (this.SetStatus("Bound: " WinGetProcessName("ahk_id " hwnd), "ok"), this.AttachToTarget())
    OnTargetGone(reason) => (this.Gui.Hide(), this.SetStatus("Target " reason, "warn"))
    OnTargetClosed() => (this.Gui.Hide(), this.SetStatus("Target not found", "error"))
    AttachToTarget(*) {
        if !this.Visible
            return
        rc := this.Tracker.GetClientRect()
        rx := Number(this.Store.Get("Overlay", "RelX", 0.02)), ry := Number(this.Store.Get("Overlay", "RelY", 0.05))
        rw := Number(this.Store.Get("Overlay", "RelW", 0.20)), rh := Number(this.Store.Get("Overlay", "RelH", 0.45))
        x := rc.x + Round(rc.w * rx), y := rc.y + Round(rc.h * ry), w := Max(260, Round(rc.w * rw)), h := Max(220, Round(rc.h * rh))
        this.Gui.Show("x" x " y" y " w" w " h" h " NoActivate")
        WinSetTransparent(Round(255 * Number(this.Store.Get("Overlay", "Opacity", 0.90))), "ahk_id " this.Gui.Hwnd)
    }
    OnSize(guiObj, minMax, w, h) {
        if minMax = -1
            return
        try rc := this.Tracker.GetClientRect()
        catch
            return
        WinGetPos(&x, &y, &ow, &oh, "ahk_id " this.Gui.Hwnd)
        this.Store.Set("Overlay", "RelX", Round((x - rc.x) / rc.w, 4))
        this.Store.Set("Overlay", "RelY", Round((y - rc.y) / rc.h, 4))
        this.Store.Set("Overlay", "RelW", Round(ow / rc.w, 4))
        this.Store.Set("Overlay", "RelH", Round(oh / rc.h, 4))
    }
    BeginBind() {
        this.SetStatus("Click the target window...", "warn")
        KeyWait("LButton", "D")
        MouseGetPos(,, &hwnd)
        if hwnd = this.Gui.Hwnd
            return this.SetStatus("Binding cancelled: overlay clicked", "error")
        try this.Tracker.Bind(hwnd)
        catch as e
            this.SetStatus(e.Message, "error")
    }
    BeginCalibration() {
        if !this.Tracker.Exists()
            return this.SetStatus("Cannot calibrate: target not found", "error")
        ib := InputBox("Control name to save (example: prompt, submit, stop):", "Calibration", "w360 h130", "prompt")
        if ib.Result != "OK" || !ib.Value
            return
        this.SetStatus("Click target control: " ib.Value, "warn")
        KeyWait("LButton", "D")
        MouseGetPos(&mx, &my)
        try rc := this.Tracker.GetClientRect()
        catch as e
            return this.SetStatus(e.Message, "error")
        nx := Round((mx - rc.x) / rc.w, 5), ny := Round((my - rc.y) / rc.h, 5)
        acc := UIAutomationHelper(this.Log).ElementSummaryAt(mx, my)
        this.Store.Controls[ib.Value] := "x=" nx "|y=" ny "|uia=" acc
        this.Store.Set("Controls", ib.Value, this.Store.Controls[ib.Value])
        this.SetStatus("Calibrated " ib.Value " @ " nx "," ny, "ok")
    }
}

class SettingsGui {
    __New(store, overlay) {
        this.Store := store, this.Overlay := overlay
        this.Gui := Gui("+Owner" overlay.Gui.Hwnd, "LLM Overlay Settings")
        this.Gui.SetFont("s9", "Segoe UI")
        this.Gui.AddText("xm ym", "Target executable")
        this.Exe := this.Gui.AddEdit("xm y+2 w360", store.Get("Target", "TargetExecutable", ""))
        this.Gui.AddText("xm y+8", "Target title regex pattern")
        this.Pattern := this.Gui.AddEdit("xm y+2 w360", store.Get("Target", "TitlePattern", ""))
        this.Gui.AddText("xm y+8", "API endpoint")
        this.Endpoint := this.Gui.AddEdit("xm y+2 w360", store.Get("Api", "Endpoint", ""))
        this.Gui.AddText("xm y+8", "API key (obscured on save)")
        this.ApiKey := this.Gui.AddEdit("xm y+2 w360 Password", Reveal(store.Get("Api", "ApiKey", "")))
        this.Gui.AddText("xm y+8", "Model")
        this.Model := this.Gui.AddEdit("xm y+2 w360", store.Get("Api", "Model", ""))
        this.Gui.AddText("xm y+8", "Overlay opacity 0.20-1.00")
        this.Opacity := this.Gui.AddEdit("xm y+2 w120", store.Get("Overlay", "Opacity", "0.90"))
        this.Gui.AddText("xm y+8", "Button/action lines: Label=type=text|value=...")
        txt := ""
        for k, v in store.Buttons
            txt .= k "=" v "`n"
        this.Buttons := this.Gui.AddEdit("xm y+2 w560 h180", txt)
        this.Gui.AddButton("xm y+10 w90", "Save").OnEvent("Click", (*) => this.Save())
        this.Gui.AddButton("x+8 yp w90", "Cancel").OnEvent("Click", (*) => this.Gui.Destroy())
    }
    Show() => this.Gui.Show()
    Save() {
        this.Store.Set("Target", "TargetExecutable", this.Exe.Value)
        this.Store.Set("Target", "TitlePattern", this.Pattern.Value)
        this.Store.Set("Api", "Endpoint", this.Endpoint.Value)
        this.Store.Set("Api", "ApiKey", Obscure(this.ApiKey.Value))
        this.Store.Set("Api", "Model", this.Model.Value)
        this.Store.Set("Overlay", "Opacity", this.Opacity.Value)
        this.Store.Buttons := Map()
        for line in StrSplit(this.Buttons.Value, "`n", "`r") {
            if InStr(line, "=") {
                p := StrSplit(line, "=", , 2)
                this.Store.Buttons[p[1]] := p[2]
                this.Store.Set("Buttons", p[1], p[2])
            }
        }
        this.Overlay.BuildButtons()
        this.Overlay.SetStatus("Settings saved", "ok")
        this.Gui.Destroy()
    }
}

class ActionDispatcher {
    __New(store, tracker, api, log) => (this.Store := store, this.Tracker := tracker, this.Api := api, this.Log := log)
    RunButton(label, *) {
        if !this.Store.Buttons.Has(label)
            return
        spec := this.Store.ParseSpec(this.Store.Buttons[label])
        try {
            actionType := spec.Has("type") ? spec["type"] : "shortcut"
            if actionType = "text"
                this.SendText(spec.Get("value", ""))
            else if actionType = "shortcut"
                this.SendShortcut(spec.Get("value", ""))
            else if actionType = "controlclick"
                CoordinateFallback(this.Tracker, this.Log).ClickControl(spec.Get("control", ""))
            else if actionType = "api"
                this.Api.Post(spec.Get("value", "/v1/chat/completions"), A_Clipboard)
            else if actionType = "function"
                this.CallFunction(spec.Get("value", ""))
            else if actionType = "clipboardsubmit"
                this.SendText(this.GetClipboardText()), this.SendShortcut("^Enter")
            App.Overlay.SetStatus("Ran: " label, "ok")
        } catch as e {
            this.Log.Error("Action failed: " label " - " e.Message)
            App.Overlay.SetStatus("Error: " e.Message, "error")
        }
    }
    FocusTarget() {
        hwnd := this.Tracker.Exists()
        if !hwnd
            throw Error("Target window not found")
        try WinActivate("ahk_id " hwnd)
        if !WinWaitActive("ahk_id " hwnd, , 1)
            throw Error("Target may be running as administrator; run this script as administrator too")
    }
    SendText(text) {
        this.FocusTarget()
        try ControlSendText(text, , "ahk_id " this.Tracker.Hwnd)
        catch
            SendText(text)
    }
    SendShortcut(keys) {
        this.FocusTarget()
        for key in StrSplit(keys, ",") {
            Send(key)
            Sleep(60)
        }
    }
    GetClipboardText() {
        if !ClipWait(0.2)
            throw Error("Clipboard unavailable or empty")
        return A_Clipboard
    }
    CallFunction(name) {
        if name = "InsertTemplate" {
            val := this.Store.Templates.Has("Default") ? this.Store.Templates["Default"] : ""
            return this.SendText(val)
        }
        if name = "InspectMouse"
            return UIAutomationHelper(this.Log).InspectUnderMouse()
        throw Error("Unknown AutoHotkey function: " name)
    }
}

class CoordinateFallback {
    __New(tracker, log) => (this.Tracker := tracker, this.Log := log)
    ClickControl(name) {
        if !this.Tracker.Store.Controls.Has(name)
            throw Error("Control not calibrated: " name)
        spec := this.Tracker.Store.ParseSpec(this.Tracker.Store.Controls[name])
        rc := this.Tracker.GetClientRect()
        x := rc.x + Round(rc.w * Number(spec["x"])), y := rc.y + Round(rc.h * Number(spec["y"]))
        hwnd := this.Tracker.Exists()
        WinActivate("ahk_id " hwnd)
        ControlClick("x" (x - rc.x) " y" (y - rc.y), "ahk_id " hwnd, , "Left", 1, "NA")
    }
}

class UIAutomationHelper {
    __New(log) => this.Log := log
    ElementSummaryAt(x, y) {
        ; Lightweight built-in inspection: records HWND/class/title under the cursor.
        ; Full UIA identifiers vary per app; use Inspect.exe or Accessibility Insights for AutomationId/Name/ClassName when available.
        MouseGetPos(,, &hwnd, &ctrl, 2)
        title := hwnd ? WinGetTitle("ahk_id " hwnd) : ""
        cls := hwnd ? WinGetClass("ahk_id " hwnd) : ""
        return StrReplace("hwnd:" hwnd ",class:" cls ",control:" ctrl ",title:" title, "|", "/")
    }
    InspectUnderMouse() {
        MouseGetPos(&x, &y)
        msg := this.ElementSummaryAt(x, y)
        this.Log.Info("Inspect: " msg)
        MsgBox("Control under mouse:`n" msg "`n`nFor richer UI Automation identifiers, inspect the app with Microsoft Inspect.exe or Accessibility Insights and paste AutomationId/Name/ClassName into the control notes in config\llm_overlay.ini.", "LLM Overlay Inspector")
    }
}

class ApiClient {
    __New(store, log) => (this.Store := store, this.Log := log)
    Post(path, prompt) {
        endpoint := RTrim(this.Store.Get("Api", "Endpoint", ""), "/")
        key := Reveal(this.Store.Get("Api", "ApiKey", ""))
        model := this.Store.Get("Api", "Model", "")
        if !endpoint
            throw Error("API endpoint is not configured")
        if !key
            throw Error("Invalid API key: missing")
        url := endpoint path
        body := '{"model":"' JsonEscape(model) '","messages":[{"role":"user","content":"' JsonEscape(prompt) '"}]}'
        http := ComObject("WinHttp.WinHttpRequest.5.1")
        try {
            http.Open("POST", url, false)
            http.SetRequestHeader("Content-Type", "application/json")
            http.SetRequestHeader("Authorization", "Bearer " key)
            http.Send(body)
        } catch as e {
            throw Error("API request failure: " e.Message)
        }
        if http.Status = 401 || http.Status = 403
            throw Error("Invalid API key or unauthorized API request")
        if http.Status < 200 || http.Status >= 300
            throw Error("API request failure: HTTP " http.Status)
        A_Clipboard := http.ResponseText
        return http.ResponseText
    }
}

Obscure(text) {
    if !text || SubStr(text, 1, 4) = "b64:"
        return text
    return "b64:" Base64Encode(text)
}
Reveal(text) {
    if SubStr(text, 1, 4) = "b64:"
        return Base64Decode(SubStr(text, 5))
    return text
}
Base64Encode(s) {
    bytes := Buffer(StrPut(s, "UTF-8") - 1), StrPut(s, bytes, "UTF-8")
    chars := 0
    DllCall("Crypt32\CryptBinaryToString", "ptr", bytes, "uint", bytes.Size, "uint", 0x40000001, "ptr", 0, "uint*", &chars)
    out := Buffer(chars * 2)
    DllCall("Crypt32\CryptBinaryToString", "ptr", bytes, "uint", bytes.Size, "uint", 0x40000001, "ptr", out, "uint*", &chars)
    return StrGet(out)
}
Base64Decode(s) {
    bytes := 0
    DllCall("Crypt32\CryptStringToBinary", "str", s, "uint", 0, "uint", 1, "ptr", 0, "uint*", &bytes, "ptr", 0, "ptr", 0)
    buf := Buffer(bytes)
    DllCall("Crypt32\CryptStringToBinary", "str", s, "uint", 0, "uint", 1, "ptr", buf, "uint*", &bytes, "ptr", 0, "ptr", 0)
    return StrGet(buf, bytes, "UTF-8")
}
JsonEscape(s) {
    s := StrReplace(s, "\", "\\")
    s := StrReplace(s, '"', '\"')
    s := StrReplace(s, "`r", "")
    s := StrReplace(s, "`n", "\n")
    return s
}

App.Start()
