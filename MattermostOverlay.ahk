#Requires AutoHotkey v2.0+
#SingleInstance Force
#Warn

; Mattermost Dispatch Panel for AI-HUB v2 / POF 2828.
; Phase 1 goal: fast, reliable API-only posting to Mattermost via WinHttp COM.
; Config: config\mm_config.ini

class MMApp {
    static ConfigPath := A_ScriptDir "\config\mm_config.ini"
    static LogPath := A_ScriptDir "\logs\mattermost_overlay.log"
    static Config := ""
    static Client := ""
    static UI := ""
    static ChannelIds := Map()

    static Start() {
        DirCreate(A_ScriptDir "\config")
        DirCreate(A_ScriptDir "\logs")
        MMApp.Config := MMConfig(MMApp.ConfigPath)
        MMApp.Config.Load()
        MMApp.Client := MattermostClient(MMApp.Config, MMApp.LogPath)
        MMApp.UI := MattermostOverlayGui(MMApp.Config, MMApp.Client)
        MMApp.RegisterHotkeys()
        MMApp.UI.Show()
        SetTimer(() => MMApp.ResolveConfiguredChannels(), -150)
    }

    static RegisterHotkeys() {
        Hotkey(MMApp.Config.ToggleHotkey, (*) => MMApp.UI.Toggle())
        Hotkey(MMApp.Config.PostDefaultHotkey, (*) => MMApp.UI.PostClipboardTo(MMApp.Config.DefaultChannel))
        Hotkey(MMApp.Config.InputBoxHotkey, (*) => MMApp.UI.PostInputBox())
        Hotkey(MMApp.Config.CheckUnreadHotkey, (*) => MMApp.UI.CheckUnread())
        Hotkey(MMApp.Config.EmergencyStopHotkey, (*) => MMApp.UI.SuspendAutomation())
    }

    static ResolveConfiguredChannels() {
        MMApp.UI.SetStatus("Resolving channels...", "warn")
        MMApp.ChannelIds := Map()
        ok := 0, failed := []
        for channel in MMApp.Config.Channels {
            try {
                id := MMApp.Client.ResolveChannelId(channel)
                MMApp.ChannelIds[channel] := id
                ok += 1
            } catch as e {
                failed.Push(channel)
                MMLog(MMApp.LogPath, "WARN", "Could not resolve " channel ": " e.Message)
            }
        }
        MMApp.Client.ChannelIds := MMApp.ChannelIds
        if ok = 0
            MMApp.UI.SetStatus("HUB OFFLINE", "error")
        else if failed.Length
            MMApp.UI.SetStatus("Resolved " ok "; missing " failed.Length, "warn")
        else
            MMApp.UI.SetStatus("Ready: " ok " channels", "ok")
    }
}

class MMConfig {
    __New(path) {
        this.Path := path
        this.BaseURL := "http://192.168.1.93:8065"
        this.BotToken := ""
        this.TeamID := ""
        this.ChannelCsv := "session-logs,codex-lab,gather-pipeline,opus,gemini,gpt,kimi,haiku"
        this.DefaultChannel := "session-logs"
        this.PosX := 120, this.PosY := 120, this.Width := 405, this.Height := 310
        this.AlwaysOnTop := true
        this.ToggleHotkey := "^!m"
        this.PostDefaultHotkey := "^+s"
        this.InputBoxHotkey := "^+i"
        this.CheckUnreadHotkey := "^+u"
        this.EmergencyStopHotkey := "^!Esc"
        this.Channels := []
    }

    Load() {
        if !FileExist(this.Path)
            this.CreateDefaultFile()
        this.BaseURL := RTrim(IniRead(this.Path, "Mattermost", "BaseURL", this.BaseURL), "/")
        this.BotToken := IniRead(this.Path, "Mattermost", "BotToken", this.BotToken)
        this.TeamID := IniRead(this.Path, "Mattermost", "TeamID", this.TeamID)
        this.ChannelCsv := IniRead(this.Path, "Mattermost", "Channels", this.ChannelCsv)
        this.DefaultChannel := IniRead(this.Path, "Mattermost", "DefaultChannel", this.DefaultChannel)
        this.PosX := Integer(IniRead(this.Path, "Window", "X", this.PosX))
        this.PosY := Integer(IniRead(this.Path, "Window", "Y", this.PosY))
        this.Width := Integer(IniRead(this.Path, "Window", "W", this.Width))
        this.Height := Integer(IniRead(this.Path, "Window", "H", this.Height))
        this.AlwaysOnTop := IniRead(this.Path, "Window", "AlwaysOnTop", "1") = "1"
        this.ToggleHotkey := IniRead(this.Path, "Hotkeys", "ToggleOverlay", this.ToggleHotkey)
        this.PostDefaultHotkey := IniRead(this.Path, "Hotkeys", "PostDefault", this.PostDefaultHotkey)
        this.InputBoxHotkey := IniRead(this.Path, "Hotkeys", "InputBox", this.InputBoxHotkey)
        this.CheckUnreadHotkey := IniRead(this.Path, "Hotkeys", "CheckUnread", this.CheckUnreadHotkey)
        this.EmergencyStopHotkey := IniRead(this.Path, "Hotkeys", "EmergencyStop", this.EmergencyStopHotkey)
        this.Channels := ParseCsv(this.ChannelCsv)
    }

    SaveWindow(x, y, w, h) {
        IniWrite(x, this.Path, "Window", "X")
        IniWrite(y, this.Path, "Window", "Y")
        IniWrite(w, this.Path, "Window", "W")
        IniWrite(h, this.Path, "Window", "H")
    }

    CreateDefaultFile() {
        IniWrite(this.BaseURL, this.Path, "Mattermost", "BaseURL")
        IniWrite("<PAT>", this.Path, "Mattermost", "BotToken")
        IniWrite("<TEAM_ID>", this.Path, "Mattermost", "TeamID")
        IniWrite(this.ChannelCsv, this.Path, "Mattermost", "Channels")
        IniWrite(this.DefaultChannel, this.Path, "Mattermost", "DefaultChannel")
        IniWrite(this.PosX, this.Path, "Window", "X")
        IniWrite(this.PosY, this.Path, "Window", "Y")
        IniWrite(this.Width, this.Path, "Window", "W")
        IniWrite(this.Height, this.Path, "Window", "H")
        IniWrite("1", this.Path, "Window", "AlwaysOnTop")
        IniWrite(this.ToggleHotkey, this.Path, "Hotkeys", "ToggleOverlay")
        IniWrite(this.PostDefaultHotkey, this.Path, "Hotkeys", "PostDefault")
        IniWrite(this.InputBoxHotkey, this.Path, "Hotkeys", "InputBox")
        IniWrite(this.CheckUnreadHotkey, this.Path, "Hotkeys", "CheckUnread")
        IniWrite(this.EmergencyStopHotkey, this.Path, "Hotkeys", "EmergencyStop")
    }
}

class MattermostOverlayGui {
    __New(config, client) {
        this.Config := config
        this.Client := client
        this.Visible := false
        this.Suspended := false
        opts := config.AlwaysOnTop ? "+AlwaysOnTop +Resize +MinSize340x250" : "+Resize +MinSize340x250"
        this.Gui := Gui(opts, "Mattermost Dispatch Panel")
        this.Gui.BackColor := "1E1F22"
        this.Gui.SetFont("s9 cFFFFFF", "Segoe UI")
        this.Header := this.Gui.AddText("xm ym w370 h24", "Mattermost Overlay")
        this.Status := this.Gui.AddText("xm y+2 w370 h24", "Starting...")
        this.Status.SetFont("cFFD166")
        this.Gui.AddButton("xm y+8 w118 h32", "Session Logs").OnEvent("Click", (*) => this.PostClipboardTo("session-logs"))
        this.Gui.AddButton("x+8 yp w118 h32", "Codex Lab").OnEvent("Click", (*) => this.PostClipboardTo("codex-lab"))
        this.Gui.AddButton("x+8 yp w118 h32", "Broadcast").OnEvent("Click", (*) => this.BroadcastClipboard())
        this.Gui.AddButton("xm y+8 w118 h32", "Check Unread").OnEvent("Click", (*) => this.CheckUnread())
        this.Gui.AddButton("x+8 yp w118 h32", "Read Last 5").OnEvent("Click", (*) => this.ReadLastFive())
        this.Gui.AddButton("x+8 yp w118 h32", "Input Box").OnEvent("Click", (*) => this.PostInputBox())
        this.ChannelDrop := this.Gui.AddDropDownList("xm y+10 w180", this.Config.Channels)
        this.ChannelDrop.Text := this.Config.DefaultChannel
        this.Gui.AddButton("x+8 yp-1 w94 h26", "Post Clip").OnEvent("Click", (*) => this.PostClipboardTo(this.ChannelDrop.Text))
        this.Gui.AddButton("x+8 yp w80 h26", "Resolve").OnEvent("Click", (*) => MMApp.ResolveConfiguredChannels())
        this.LastResult := this.Gui.AddEdit("xm y+10 w370 h88 ReadOnly -Wrap", "")
        this.Gui.OnEvent("Close", (*) => this.Hide())
        this.Gui.OnEvent("Escape", (*) => this.Hide())
        this.Gui.OnEvent("Size", ObjBindMethod(this, "OnSize"))
    }

    Show() {
        this.Visible := true
        this.Gui.Show("x" this.Config.PosX " y" this.Config.PosY " w" this.Config.Width " h" this.Config.Height)
    }
    Hide() => (this.Visible := false, this.Gui.Hide())
    Toggle() => this.Visible ? this.Hide() : this.Show()

    OnSize(guiObj, minMax, w, h) {
        if minMax = -1
            return
        WinGetPos(&x, &y, &ww, &hh, "ahk_id " this.Gui.Hwnd)
        this.Config.SaveWindow(x, y, ww, hh)
    }

    SetStatus(text, state := "info") {
        color := state = "error" ? "FF5A5F" : state = "ok" ? "70FF70" : state = "warn" ? "FFD166" : "D7DAE0"
        this.Status.Text := text
        this.Status.SetFont("c" color)
        MMLog(MMApp.LogPath, state = "error" ? "ERROR" : "INFO", text)
    }

    SuspendAutomation() {
        this.Suspended := !this.Suspended
        this.SetStatus(this.Suspended ? "SUSPENDED" : "Ready", this.Suspended ? "warn" : "ok")
    }

    GuardReady() {
        if this.Suspended {
            this.SetStatus("SUSPENDED", "warn")
            return false
        }
        if !this.Config.BotToken || this.Config.BotToken = "<PAT>" {
            this.SetStatus("AUTH FAILED", "error")
            return false
        }
        if !this.Config.TeamID || this.Config.TeamID = "<TEAM_ID>" {
            this.SetStatus("TEAM ID MISSING", "error")
            return false
        }
        return true
    }

    GetClipboardText() {
        if !ClipWait(0.2)
            throw Error("Clipboard unavailable")
        txt := A_Clipboard
        if !Trim(txt)
            throw Error("Clipboard empty")
        return txt
    }

    PostClipboardTo(channel) {
        if !this.GuardReady()
            return
        try {
            text := this.GetClipboardText()
            postId := this.Client.PostToChannel(channel, FormatOverlayMessage(text))
            this.SetStatus("Posted to #" channel, "ok")
            this.LastResult.Value := "post_id=" postId "`nchannel=#" channel "`n" SubStr(text, 1, 500)
        } catch as e {
            this.ReportError(e)
        }
    }

    BroadcastClipboard() {
        if !this.GuardReady()
            return
        try text := this.GetClipboardText()
        catch as e
            return this.ReportError(e)
        sent := 0, failed := []
        for channel in this.Config.Channels {
            try {
                this.Client.PostToChannel(channel, FormatOverlayMessage(text))
                sent += 1
            } catch as e {
                failed.Push(channel)
                MMLog(MMApp.LogPath, "WARN", "Broadcast failed for " channel ": " e.Message)
            }
        }
        if sent = 0
            this.SetStatus("BROADCAST FAILED", "error")
        else if failed.Length
            this.SetStatus("Broadcast " sent "; failed " failed.Length, "warn")
        else
            this.SetStatus("Broadcast to " sent " channels", "ok")
        this.LastResult.Value := "Broadcast sent=" sent " failed=" failed.Length
    }

    CheckUnread() {
        if !this.GuardReady()
            return
        lines := [], total := 0, mentions := 0
        for channel in this.Config.Channels {
            try {
                counts := this.Client.GetUnread(channel)
                total += counts.msg_count, mentions += counts.mention_count
                lines.Push("#" channel ": " counts.msg_count " unread, " counts.mention_count " mentions")
            } catch as e {
                lines.Push("#" channel ": " e.Message)
            }
        }
        this.LastResult.Value := JoinLines(lines)
        this.SetStatus("Unread " total " | Mentions " mentions, total || mentions ? "warn" : "ok")
    }

    ReadLastFive() {
        if !this.GuardReady()
            return
        channel := this.ChannelDrop.Text ? this.ChannelDrop.Text : this.Config.DefaultChannel
        try {
            posts := this.Client.GetLastPosts(channel, 5)
            tip := JoinLines(posts)
            if !tip
                tip := "No posts returned"
            this.LastResult.Value := tip
            ToolTip(tip, , , 12)
            SetTimer(() => ToolTip(,,,12), -6000)
            this.SetStatus("Read last 5 from #" channel, "ok")
        } catch as e {
            this.ReportError(e)
        }
    }

    PostInputBox() {
        if !this.GuardReady()
            return
        channel := this.ChannelDrop.Text ? this.ChannelDrop.Text : this.Config.DefaultChannel
        ib := InputBox("Message for #" channel, "Mattermost Overlay", "w520 h170")
        if ib.Result != "OK" || !Trim(ib.Value)
            return this.SetStatus("Input cancelled", "warn")
        try {
            postId := this.Client.PostToChannel(channel, FormatOverlayMessage(ib.Value))
            this.SetStatus("Posted typed message to #" channel, "ok")
            this.LastResult.Value := "post_id=" postId "`n" ib.Value
        } catch as e {
            this.ReportError(e)
        }
    }

    ReportError(e) {
        msg := e.Message
        if InStr(msg, "HTTP 401") || InStr(msg, "HTTP 403")
            this.SetStatus("AUTH FAILED", "error")
        else if InStr(msg, "HTTP 404") || InStr(msg, "CHANNEL NOT FOUND")
            this.SetStatus("CHANNEL NOT FOUND", "error")
        else if InStr(msg, "offline") || InStr(msg, "timed out") || InStr(msg, "could not be resolved")
            this.SetStatus("HUB OFFLINE", "error")
        else
            this.SetStatus(msg, "error")
        this.LastResult.Value := msg
    }
}

class MattermostClient {
    __New(config, logPath) {
        this.Config := config
        this.LogPath := logPath
        this.ChannelIds := Map()
    }

    ResolveChannelId(channelName) {
        name := NormalizeChannelName(channelName)
        url := this.Config.BaseURL "/api/v4/teams/" UrlEncode(this.Config.TeamID) "/channels/name/" UrlEncode(name)
        resp := this.Request("GET", url)
        id := JsonString(resp, "id")
        if !id
            throw Error("CHANNEL NOT FOUND: " name)
        return id
    }

    ChannelId(channelName) {
        name := NormalizeChannelName(channelName)
        if this.ChannelIds.Has(name)
            return this.ChannelIds[name]
        id := this.ResolveChannelId(name)
        this.ChannelIds[name] := id
        return id
    }

    PostToChannel(channelName, message) {
        channelId := this.ChannelId(channelName)
        body := '{"channel_id":"' JsonEscape(channelId) '","message":"' JsonEscape(message) '"}'
        resp := this.Request("POST", this.Config.BaseURL "/api/v4/posts", body)
        id := JsonString(resp, "id")
        return id ? id : "unknown"
    }

    GetUnread(channelName) {
        channelId := this.ChannelId(channelName)
        url := this.Config.BaseURL "/api/v4/users/me/channels/" UrlEncode(channelId) "/unread"
        resp := this.Request("GET", url)
        return {msg_count: JsonNumber(resp, "msg_count"), mention_count: JsonNumber(resp, "mention_count")}
    }

    GetLastPosts(channelName, perPage := 5) {
        channelId := this.ChannelId(channelName)
        url := this.Config.BaseURL "/api/v4/channels/" UrlEncode(channelId) "/posts?per_page=" perPage
        resp := this.Request("GET", url)
        return ExtractMattermostMessages(resp, perPage)
    }

    Request(method, url, body := "") {
        whr := ComObject("WinHttp.WinHttpRequest.5.1")
        try {
            whr.Open(method, url, false)
            whr.SetTimeouts(2500, 2500, 5000, 8000)
            whr.SetRequestHeader("Authorization", "Bearer " this.Config.BotToken)
            if method = "POST"
                whr.SetRequestHeader("Content-Type", "application/json")
            whr.Send(body)
        } catch as e {
            MMLog(this.LogPath, "ERROR", "HTTP failure " method " " url " :: " e.Message)
            throw Error("Mattermost hub offline or request failed")
        }
        status := whr.Status
        text := whr.ResponseText
        MMLog(this.LogPath, "INFO", method " " url " -> HTTP " status)
        if status < 200 || status >= 300
            throw Error("HTTP " status ": " SubStr(text, 1, 240))
        return text
    }
}

FormatOverlayMessage(text) => "[David via Overlay | " FormatTime(, "HH:mm") "] " text
NormalizeChannelName(name) => StrReplace(Trim(name), "#", "")

ParseCsv(csv) {
    out := []
    for raw in StrSplit(csv, ",") {
        item := NormalizeChannelName(raw)
        if item
            out.Push(item)
    }
    return out
}

JoinLines(arr) {
    out := ""
    for item in arr
        out .= (out ? "`n" : "") item
    return out
}

JsonEscape(s) {
    s := StrReplace(s, "\", "\\")
    s := StrReplace(s, '"', '\"')
    s := StrReplace(s, "`r", "")
    s := StrReplace(s, "`n", "\n")
    s := StrReplace(s, "`t", "\t")
    return s
}

JsonString(json, key) {
    if RegExMatch(json, '"' key '"\s*:\s*"((?:\\.|[^"\\])*)"', &m)
        return JsonUnescape(m[1])
    return ""
}

JsonNumber(json, key) {
    if RegExMatch(json, '"' key '"\s*:\s*(-?\d+)', &m)
        return Integer(m[1])
    return 0
}

JsonUnescape(s) {
    s := StrReplace(s, '\n', "`n")
    s := StrReplace(s, '\t', "`t")
    s := StrReplace(s, '\"', '"')
    s := StrReplace(s, '\\', "\")
    return s
}

ExtractMattermostMessages(json, limit := 5) {
    lines := []
    pos := 1
    while lines.Length < limit {
        found := RegExMatch(json, '"message"\s*:\s*"((?:\\.|[^"\\])*)"', &m, pos)
        if !found
            break
        msg := JsonUnescape(m[1])
        msg := RegExReplace(msg, "\s+", " ")
        lines.Push(SubStr(msg, 1, 220))
        pos := found + StrLen(m[0])
    }
    return lines
}

UrlEncode(str) {
    out := ""
    Loop Parse str {
        ch := A_LoopField
        code := Ord(ch)
        if (code >= 0x30 && code <= 0x39) || (code >= 0x41 && code <= 0x5A) || (code >= 0x61 && code <= 0x7A) || InStr("-_.~", ch)
            out .= ch
        else
            out .= "%" Format("{:02X}", code)
    }
    return out
}

MMLog(path, level, msg) {
    safe := RegExReplace(msg, "(?i)(authorization|bearer|bottoken|token)\s*[:= ]+[^\s,;]+", "$1=***")
    FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss") " [" level "] " safe "`n", path, "UTF-8")
}

MMApp.Start()
