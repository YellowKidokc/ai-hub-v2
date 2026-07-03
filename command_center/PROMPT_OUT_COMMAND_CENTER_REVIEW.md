# Prompt-Out: AI-HUB Command Center Review / Extension

You are reviewing and extending a Windows automation pilot called **AI-HUB Command Center**.

## Existing Local Scaffold

The current pilot lives at:

```text
D:\GitHub\ai-hub-v2\command_center\
```

Current files:

```text
command_center.ahk      AutoHotkey v2 hotkey layer
command_picker.py       Tkinter searchable command picker
run_command.py          Manifest-driven safe runner
commands.json           Sample command registry
scripts/py/preference_capture.py
README.md
.gitignore
```

## What It Does Now

- `Ctrl+Alt+W` launches the command picker through AutoHotkey v2.
- AHK captures the active window context to `runtime/last_window.json`.
- Python picker searches commands from `commands.json`.
- Runner supports command types:
  - `bat`
  - `cmd`
  - `ps1`
  - `py`
  - `ahk`
  - `folder`
  - `url`
  - `app`
- Runner writes per-run JSON/log metadata.
- Preference command captures active-window like/dislike/neutral feedback to:

```text
command_center\data\preferences\window_preferences.jsonl
```

## Mission

Harden this into a reliable standalone command center that can later become part of AI-HUB v2 and the Preference Engine.

Do **not** rewrite the whole AI-HUB app. Keep this standalone until the pilot is stable.

## Requirements

### 1. Keep AHK v2

This machine uses AutoHotkey v2. Do not depend on AutoHotkey v1.

### 2. Preserve `Ctrl+Alt+W`

David wants `Ctrl+Alt+W` as the command picker hotkey.

Note: existing AI-HUB docs list `Ctrl+Alt+W` as Always-On-Top. If integrating later, resolve the hotkey conflict explicitly.

### 3. Manifest-First Design

All commands should come from `commands.json`.

Command schema should support:

```json
{
  "id": "unique.command.id",
  "title": "Human Command Name",
  "category": "Category",
  "type": "bat|cmd|ps1|py|ahk|folder|url|app",
  "path": "absolute path or {root}\\relative",
  "working_dir": "optional working directory",
  "args": [],
  "tags": [],
  "risk": "safe|writes_files|network|destructive|admin",
  "requires_confirm": false,
  "show_console": false,
  "pass_context": false,
  "window_policy": "none|active|restore|target_class|target_process"
}
```

### 4. No Unsafe Shell Habits

Avoid `shell=True` for Python subprocesses except where `.bat`/`.cmd` is intentionally wrapped through `cmd.exe /c`.

### 5. Window Context Matters

The active window context is not decoration. It is the first preference-engine signal.

Preserve or improve:

- active window title
- process name
- process path
- window class
- HWND
- PID
- capture timestamp

### 6. Preference Engine Direction

The preference capture workflow should eventually answer:

- Did David like this window/content/context?
- Why?
- Which app/process/window class was involved?
- What should future automation infer?
- Should this preference apply globally, per app, or per workflow?

If you extend it, add fields carefully rather than making it bloated.

### 7. Logging

Each run should produce machine-readable logs:

```text
logs/YYYY-MM-DD/<timestamp>_<command-id>.json
logs/YYYY-MM-DD/<timestamp>_<command-id>.stdout.txt
logs/YYYY-MM-DD/<timestamp>_<command-id>.stderr.txt
```

### 8. Risk Gates

Commands marked `destructive` or `admin` must require confirmation.

Commands marked `network` should be visible as networked but do not necessarily require confirmation.

### 9. Good First Extensions

Add or improve these only if you can do so safely:

- command validation script
- manifest schema documentation
- install/start BAT
- tray icon / reload command
- better search scoring
- category filters
- command editor stub
- recent commands
- favorites
- active-window restore after command
- more real workflow samples

### 10. Do Not Overbuild

Avoid:

- rewriting AI-HUB core
- installing new frameworks unnecessarily
- making this dependent on a web server
- hiding logs
- making commands invisible or magical
- adding destructive workflows as samples

## Desired Output

Return:

1. Summary of what you changed or recommend.
2. Exact files changed.
3. Any commands needed to test it.
4. Any risks or unresolved design choices.
5. If you cannot edit files directly, provide a patch or replacement file contents.

## Current Strategic Intent

This command center should become the local execution backbone for:

- BAT workflows
- PowerShell workflows
- Python workflows
- AHK workflows
- AI-HUB launchers
- Lean / proof builds
- comms shortcuts
- preference feedback capture
- future automation routing

The central design principle:

```text
One hotkey. Searchable commands. Safe runner. Window-aware preference capture.
```

