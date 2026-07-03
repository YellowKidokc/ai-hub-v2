from __future__ import annotations

import argparse
import json
import tkinter as tk
from datetime import datetime, timezone
from pathlib import Path
from tkinter import ttk


ROOT = Path(__file__).resolve().parents[2]
PREFERENCE_LOG = ROOT / "data" / "preferences" / "window_preferences.jsonl"


def load_json(path: Path | None) -> dict:
    if not path or not path.exists():
        return {}
    with path.open("r", encoding="utf-8-sig") as handle:
        return json.load(handle)


class PreferenceCapture(tk.Tk):
    def __init__(self, context: dict):
        super().__init__()
        self.context = context
        self.title("Capture Window Preference")
        self.geometry("620x360")
        self.minsize(520, 300)

        self.choice_var = tk.StringVar(value="neutral")
        self.note = tk.Text(self, height=6, wrap=tk.WORD)
        self.status_var = tk.StringVar(value="Choose like, dislike, or neutral, then save.")

        self._build_ui()

    def _build_ui(self) -> None:
        frame = ttk.Frame(self, padding=14)
        frame.pack(fill=tk.BOTH, expand=True)

        title = self.context.get("title") or "(no active window title)"
        process = self.context.get("process_name") or "(unknown process)"

        ttk.Label(frame, text="Active window", font=("", 12, "bold")).pack(anchor=tk.W)
        ttk.Label(frame, text=title, wraplength=560).pack(anchor=tk.W, pady=(4, 0))
        ttk.Label(frame, text=f"Process: {process}").pack(anchor=tk.W, pady=(2, 12))

        choices = ttk.Frame(frame)
        choices.pack(anchor=tk.W, pady=(0, 12))
        for label, value in [("Like", "like"), ("Dislike", "dislike"), ("Neutral", "neutral")]:
            ttk.Radiobutton(choices, text=label, value=value, variable=self.choice_var).pack(side=tk.LEFT, padx=(0, 12))

        ttk.Label(frame, text="Why / what should the preference engine learn?").pack(anchor=tk.W)
        self.note.pack(fill=tk.BOTH, expand=True, pady=(4, 12))

        footer = ttk.Frame(frame)
        footer.pack(fill=tk.X)
        ttk.Button(footer, text="Save", command=self.save).pack(side=tk.LEFT)
        ttk.Button(footer, text="Cancel", command=self.destroy).pack(side=tk.LEFT, padx=(8, 0))
        ttk.Label(footer, textvariable=self.status_var).pack(side=tk.LEFT, padx=(16, 0))

    def save(self) -> None:
        PREFERENCE_LOG.parent.mkdir(parents=True, exist_ok=True)
        entry = {
            "captured_at": datetime.now(timezone.utc).isoformat(),
            "preference": self.choice_var.get(),
            "note": self.note.get("1.0", tk.END).strip(),
            "window": self.context,
        }
        with PREFERENCE_LOG.open("a", encoding="utf-8") as handle:
            handle.write(json.dumps(entry, ensure_ascii=False) + "\n")
        self.status_var.set(f"Saved to {PREFERENCE_LOG}")
        self.after(500, self.destroy)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--context", type=Path)
    args = parser.parse_args()

    app = PreferenceCapture(load_json(args.context))
    app.mainloop()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

