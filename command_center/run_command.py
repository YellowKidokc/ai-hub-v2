from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import webbrowser
from datetime import datetime, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parent


def utc_stamp() -> str:
    return datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")


def load_json(path: Path, default):
    if not path.exists():
        return default
    with path.open("r", encoding="utf-8-sig") as handle:
        return json.load(handle)


def expand_path(value: str | None) -> Path | None:
    if not value:
        return None
    expanded = value.replace("{root}", str(ROOT))
    expanded = os.path.expandvars(expanded)
    path = Path(expanded)
    if not path.is_absolute():
        path = ROOT / path
    return path


def find_command(manifest: dict, command_id: str) -> dict:
    for command in manifest.get("commands", []):
        if command.get("id") == command_id:
            return command
    raise KeyError(f"Command not found: {command_id}")


def build_process_args(command: dict, context_path: Path | None) -> list[str] | None:
    command_type = command.get("type")
    path = expand_path(command.get("path"))
    raw_args = [str(item) for item in command.get("args", [])]

    if command.get("pass_context") and context_path:
        raw_args.extend(["--context", str(context_path)])

    if command_type in {"folder", "url"}:
        return None

    if command_type == "bat" or command_type == "cmd":
        return ["cmd.exe", "/c", str(path), *raw_args]

    if command_type == "ps1":
        return [
            "powershell.exe",
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            str(path),
            *raw_args,
        ]

    if command_type == "py":
        return [sys.executable, str(path), *raw_args]

    if command_type == "ahk":
        ahk = command.get("ahk_exe") or r"C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe"
        return [ahk, str(path), *raw_args]

    if command_type == "app":
        return [str(path), *raw_args]

    raise ValueError(f"Unsupported command type: {command_type}")


def ensure_path_exists(command: dict) -> None:
    command_type = command.get("type")
    if command_type == "url":
        return

    path = expand_path(command.get("path"))
    if not path or not path.exists():
        raise FileNotFoundError(f"Missing command path: {path}")


def run_command(command: dict, context_path: Path | None, confirmed: bool) -> dict:
    risk = command.get("risk", "safe")
    if (command.get("requires_confirm", False) or risk in {"destructive", "admin"}) and not confirmed:
        raise PermissionError(f"Command requires confirmation: {command.get('id')}")

    ensure_path_exists(command)

    log_root = ROOT / "logs" / datetime.now().strftime("%Y-%m-%d")
    log_root.mkdir(parents=True, exist_ok=True)
    safe_id = "".join(ch if ch.isalnum() or ch in "-_." else "_" for ch in command["id"])
    stamp = utc_stamp()
    stdout_path = log_root / f"{stamp}_{safe_id}.stdout.txt"
    stderr_path = log_root / f"{stamp}_{safe_id}.stderr.txt"
    json_path = log_root / f"{stamp}_{safe_id}.json"

    started_at = datetime.now(timezone.utc).isoformat()
    context = load_json(context_path, {}) if context_path else {}

    command_type = command.get("type")
    path = expand_path(command.get("path"))
    cwd = expand_path(command.get("working_dir")) or (path.parent if path and path.is_file() else ROOT)

    result = {
        "id": command["id"],
        "title": command.get("title"),
        "category": command.get("category"),
        "type": command_type,
        "risk": risk,
        "started_at": started_at,
        "finished_at": None,
        "exit_code": None,
        "path": str(path) if path else command.get("path"),
        "working_dir": str(cwd),
        "stdout": str(stdout_path),
        "stderr": str(stderr_path),
        "context": context,
    }

    if command_type == "folder":
        os.startfile(str(path))  # noqa: S606 - intentional local launcher
        result["exit_code"] = 0
    elif command_type == "url":
        webbrowser.open(command["path"])
        result["exit_code"] = 0
    else:
        process_args = build_process_args(command, context_path)
        show_console = bool(command.get("show_console", False))
        creationflags = subprocess.CREATE_NEW_CONSOLE if show_console and os.name == "nt" else 0

        if show_console:
            process = subprocess.Popen(process_args, cwd=str(cwd), creationflags=creationflags)
            result["pid"] = process.pid
            result["exit_code"] = None
        else:
            completed = subprocess.run(
                process_args,
                cwd=str(cwd),
                capture_output=True,
                text=True,
                encoding="utf-8",
                errors="replace",
                check=False,
            )
            stdout_path.write_text(completed.stdout or "", encoding="utf-8")
            stderr_path.write_text(completed.stderr or "", encoding="utf-8")
            result["exit_code"] = completed.returncode

    result["finished_at"] = datetime.now(timezone.utc).isoformat()
    json_path.write_text(json.dumps(result, indent=2, ensure_ascii=False), encoding="utf-8")
    return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--id", required=True)
    parser.add_argument("--manifest", type=Path, default=ROOT / "commands.json")
    parser.add_argument("--context", type=Path)
    parser.add_argument("--confirmed", action="store_true")
    args = parser.parse_args()

    manifest = load_json(args.manifest, {"commands": []})
    command = find_command(manifest, args.id)
    result = run_command(command, args.context, args.confirmed)

    if result.get("exit_code") not in (0, None):
        return int(result["exit_code"])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

