# AI-HUB Command Center

Standalone pilot for a manifest-driven Windows command picker.

## Goal

Press `Ctrl+Alt+W` to open a searchable launcher for local workflows:

- `.bat` / `.cmd`
- `.ps1`
- `.py`
- `.ahk`
- folders
- URLs
- apps
- preference-capture workflows

This starts standalone so it can prove itself before being merged into the main
AI-HUB v2 process.

## Files

```text
command_center.ahk      AutoHotkey v2 hotkey layer
command_picker.py       Tkinter searchable picker GUI
run_command.py          Safe manifest runner
commands.json           Command manifest
scripts/py/             Built-in Python workflows
logs/                   Per-run logs, gitignored by default if added later
data/preferences/       Preference-engine JSONL captures
```

## Launch

Run:

```powershell
AutoHotkey64.exe D:\GitHub\ai-hub-v2\command_center\command_center.ahk
```

Then press:

```text
Ctrl+Alt+W
```

## Important Hotkey Note

The existing AI-HUB README currently documents `Ctrl+Alt+W` as "Toggle Always
On Top." This pilot intentionally uses David's requested `Ctrl+Alt+W`, but it
should remain standalone until the old binding is moved or the command center
officially owns that shortcut.

## Preference Capture

The sample command `Capture Active Window Preference` records the active window
context plus a like/dislike/neutral decision to:

```text
command_center/data/preferences/window_preferences.jsonl
```

That is the first small backbone for the preference engine.

