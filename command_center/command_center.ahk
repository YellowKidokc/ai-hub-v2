#Requires AutoHotkey v2.0+
#SingleInstance Force
#Warn

; AI-HUB Command Center standalone hotkey layer.
; Press Ctrl+Alt+W to capture the active window and open the Python picker.

global CommandCenterDir := A_ScriptDir
global RuntimeDir := CommandCenterDir "\runtime"

DirCreate(RuntimeDir)

^!w::OpenCommandCenter()

OpenCommandCenter() {
    contextPath := RuntimeDir "\last_window.json"
    FileDeleteSafe(contextPath)
    FileAppend(GetActiveWindowContextJson(), contextPath, "UTF-8")

    picker := CommandCenterDir "\command_picker.py"
    if !FileExist(picker) {
        MsgBox("Missing command picker:`n" picker, "AI-HUB Command Center", "Iconx")
        return
    }

    py := FindPythonLauncher()
    if py = "" {
        MsgBox("Python was not found. Install Python or add it to PATH.", "AI-HUB Command Center", "Iconx")
        return
    }

    Run('"' py '" "' picker '" --context "' contextPath '"', CommandCenterDir)
}

FindPythonLauncher() {
    candidates := [
        A_LocalAppData "\Programs\Python\Python312\pythonw.exe",
        A_LocalAppData "\Programs\Python\Python311\pythonw.exe",
        A_LocalAppData "\Programs\Python\Python310\pythonw.exe",
        "pythonw.exe",
        "python.exe"
    ]

    for candidate in candidates {
        if InStr(candidate, "\") {
            if FileExist(candidate)
                return candidate
        } else {
            return candidate
        }
    }
    return ""
}

GetActiveWindowContextJson() {
    hwnd := WinExist("A")
    title := ""
    className := ""
    processName := ""
    processPath := ""
    pid := ""

    try title := WinGetTitle("ahk_id " hwnd)
    try className := WinGetClass("ahk_id " hwnd)
    try processName := WinGetProcessName("ahk_id " hwnd)
    try processPath := WinGetProcessPath("ahk_id " hwnd)
    try pid := WinGetPID("ahk_id " hwnd)

    return "{`n"
        . '  "captured_at": "' JsonEscape(A_Now) '",' "`n"
        . '  "hwnd": "' JsonEscape(String(hwnd)) '",' "`n"
        . '  "title": "' JsonEscape(title) '",' "`n"
        . '  "class": "' JsonEscape(className) '",' "`n"
        . '  "process_name": "' JsonEscape(processName) '",' "`n"
        . '  "process_path": "' JsonEscape(processPath) '",' "`n"
        . '  "pid": "' JsonEscape(String(pid)) '"' "`n"
        . "}`n"
}

JsonEscape(value) {
    value := StrReplace(value, "\", "\\")
    value := StrReplace(value, '"', '\"')
    value := StrReplace(value, "`r", "\r")
    value := StrReplace(value, "`n", "\n")
    value := StrReplace(value, "`t", "\t")
    return value
}

FileDeleteSafe(path) {
    try {
        if FileExist(path)
            FileDelete(path)
    }
}

