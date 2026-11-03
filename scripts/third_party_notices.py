#!/usr/bin/env python3
"""Writes apps/desktop/src-tauri/THIRD-PARTY-NOTICES.txt: the license text of every Rust crate the desktop app
builds with, plus the protocol notices in licenses/. The desktop bundle ships it; see docs/licenses.md.

    python3 scripts/third_party_notices.py
"""
import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TAURI = ROOT / "apps/desktop/src-tauri"
OUT = TAURI / "THIRD-PARTY-NOTICES.txt"


def license_texts(package):
    folder = Path(package["manifest_path"]).parent
    files = sorted(p for p in folder.iterdir()
                   if p.is_file() and p.name.upper().startswith(("LICENSE", "LICENCE", "COPYING", "NOTICE")))
    if package.get("license_file"):
        files.append(folder / package["license_file"])
    return [(f.name, f.read_text(encoding="utf-8", errors="replace").strip()) for f in dict.fromkeys(files)]


def main():
    meta = json.loads(subprocess.check_output(
        ["cargo", "metadata", "--format-version", "1", "--locked"], cwd=TAURI))
    own = {p["id"] for p in meta["packages"] if p["source"] is None}
    parts = ["Third-party notices for Ferry (desktop).\n", (ROOT / "licenses/protocol.txt").read_text(encoding="utf-8").strip()]
    missing = []
    for p in sorted(meta["packages"], key=lambda p: (p["name"], p["version"])):
        if p["id"] in own:
            continue
        texts = license_texts(p)
        if not texts:
            missing.append(p["name"])
        header = f"{p['name']} {p['version']} ({p.get('license') or 'see repository'})"
        if p.get("repository"):
            header += f"\n{p['repository']}"
        parts.append(header + "\n\n" + "\n\n".join(t for _, t in texts))
    OUT.write_text(("\n\n" + "-" * 72 + "\n\n").join(parts) + "\n", encoding="utf-8")
    print(f"wrote {OUT.relative_to(ROOT)}: {len(parts) - 2} crates")
    if missing:
        print("no license file in the crate (license named in Cargo.toml only):", ", ".join(missing))


if __name__ == "__main__":
    main()
