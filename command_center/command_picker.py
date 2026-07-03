from __future__ import annotations

import argparse
import json
import subprocess
import sys
import tkinter as tk
from pathlib import Path
from tkinter import messagebox, ttk


ROOT = Path(__file__).resolve().parent
MANIFEST = ROOT / "commands.json"
RUNNER = ROOT / "run_command.py"


def load_json(path: Path, default):
    if not path.exists():
        return default
    with path.open("r", encoding="utf-8-sig") as handle:
        return json.load(handle)


def command_text(command: dict) -> str:
    parts = [
        command.get("id", ""),
        command.get("title", ""),
        command.get("category", ""),
        command.get("type", ""),
        " ".join(command.get("tags", [])),
    ]
    return " ".join(parts).lower()


class CommandPicker(tk.Tk):
    def __init__(self, commands: list[dict], context_path: Path | None):
        super().__init__()
        self.title("AI-HUB Command Center")
        self.geometry("860x520")
        self.minsize(720, 420)

        self.commands = sorted(commands, key=lambda item: (item.get("category", ""), item.get("title", "")))
        self.filtered = list(self.commands)
        self.context_path = context_path

        self.search_var = tk.StringVar()
        self.status_var = tk.StringVar(value="Type to filter. Enter runs. Escape closes.")

        self._build_ui()
        self._bind_events()
        self.refresh()

        self.search_entry.focus_set()

    def _build_ui(self) -> None:
        frame = ttk.Frame(self, padding=12)
        frame.pack(fill=tk.BOTH, expand=True)

        ttk.Label(frame, text="Search commands").pack(anchor=tk.W)
        self.search_entry = ttk.Entry(frame, textvariable=self.search_var)
        self.search_entry.pack(fill=tk.X, pady=(4, 10))

        columns = ("title", "category", "type", "risk")
        self.tree = ttk.Treeview(frame, columns=columns, show="headings", height=15)
        self.tree.heading("title", text="Command")
        self.tree.heading("category", text="Category")
        self.tree.heading("type", text="Type")
        self.tree.heading("risk", text="Risk")
        self.tree.column("title", width=410)
        self.tree.column("category", width=150)
        self.tree.column("type", width=80, anchor=tk.CENTER)
        self.tree.column("risk", width=110, anchor=tk.CENTER)
        self.tree.pack(fill=tk.BOTH, expand=True)

        detail = ttk.Frame(frame)
        detail.pack(fill=tk.X, pady=(10, 0))
        ttk.Button(detail, text="Run", command=self.run_selected).pack(side=tk.LEFT)
        ttk.Button(detail, text="Close", command=self.destroy).pack(side=tk.LEFT, padx=(8, 0))
        ttk.Label(detail, textvariable=self.status_var).pack(side=tk.LEFT, padx=(16, 0))

    def _bind_events(self) -> None:
        self.search_var.trace_add("write", lambda *_: self.refresh())
        self.search_entry.bind("<Return>", lambda _event: self.run_selected())
        self.tree.bind("<Return>", lambda _event: self.run_selected())
        self.tree.bind("<Double-1>", lambda _event: self.run_selected())
        self.bind("<Escape>", lambda _event: self.destroy())
        self.bind("<Down>", self.focus_tree)

    def focus_tree(self, _event=None):
        self.tree.focus_set()
        children = self.tree.get_children()
        if children:
            self.tree.selection_set(children[0])
            self.tree.focus(children[0])
        return "break"

    def refresh(self) -> None:
        query = self.search_var.get().strip().lower()
        terms = [term for term in query.split() if term]

        if terms:
            self.filtered = [
                command for command in self.commands
                if all(term in command_text(command) for term in terms)
            ]
        else:
            self.filtered = list(self.commands)

        self.tree.delete(*self.tree.get_children())
        for index, command in enumerate(self.filtered):
            self.tree.insert(
                "",
                tk.END,
                iid=str(index),
                values=(
                    command.get("title", command.get("id", "")),
                    command.get("category", ""),
                    command.get("type", ""),
                    command.get("risk", "safe"),
                ),
            )

        if self.filtered:
            self.tree.selection_set("0")
            self.tree.focus("0")

        self.status_var.set(f"{len(self.filtered)} command(s)")

    def selected_command(self) -> dict | None:
        selection = self.tree.selection()
        if not selection:
            return None
        index = int(selection[0])
        if index >= len(self.filtered):
            return None
        return self.filtered[index]

    def run_selected(self) -> None:
        command = self.selected_command()
        if not command:
            self.status_var.set("No command selected.")
            return

        risk = command.get("risk", "safe")
        requires_confirm = command.get("requires_confirm", False) or risk in {"destructive", "admin"}
        confirmed = False
        if requires_confirm:
            confirmed = messagebox.askyesno(
                "Confirm command",
                f"Run '{command.get('title', command.get('id'))}'?\n\nRisk: {risk}",
            )
            if not confirmed:
                self.status_var.set("Cancelled.")
                return

        args = [
            sys.executable,
            str(RUNNER),
            "--id",
            command["id"],
            "--manifest",
            str(MANIFEST),
        ]
        if self.context_path:
            args.extend(["--context", str(self.context_path)])
        if confirmed:
            args.append("--confirmed")

        try:
            subprocess.Popen(args, cwd=str(ROOT))
            self.status_var.set(f"Started: {command.get('title', command['id'])}")
            if command.get("close_picker", True):
                self.after(150, self.destroy)
        except Exception as exc:
            messagebox.showerror("Command failed to start", str(exc))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--context", type=Path)
    args = parser.parse_args()

    manifest = load_json(MANIFEST, {"commands": []})
    commands = manifest.get("commands", [])

    app = CommandPicker(commands=commands, context_path=args.context)
    app.mainloop()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

