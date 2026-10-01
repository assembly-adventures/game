#!/usr/bin/env python3
"""Export a clean release copy without editor MCP services or database files."""

import argparse
import os
from pathlib import Path
import shutil
import subprocess
import tempfile


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=os.environ.get("GODOT_BIN", "godot"))
    parser.add_argument("--template", type=Path, help="Matching web_nothreads_release.zip")
    args = parser.parse_args()
    if args.template and args.template.name != "web_nothreads_release.zip":
        parser.error("This export requires web_nothreads_release.zip; web_release.zip uses threads.")
    root = Path(__file__).resolve().parents[1]
    output = root / "build" / "web"
    output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="aa-export-", dir=root / "build") as temp:
        stage = Path(temp)
        for directory in ("assets", "images", "levels", "ui"):
            shutil.copytree(root / directory, stage / directory)
        for pattern in ("*.gd", "*.uid", "*.tscn", "*.tres", "*.gdshader"):
            for source in root.glob(pattern):
                shutil.copy2(source, stage / source.name)
        project = (root / "project.godot").read_text()
        project = "\n".join(
            line for line in project.splitlines()
            if not line.startswith(("MCPScreenshot=", "MCPInputService=", "MCPGameInspector="))
        )
        project = project.replace('run/main_scene="uid://b6kxuuh8l2spo"',
                                  'run/main_scene="res://start_page.tscn"')
        project = project.replace('PlayerData="*uid://cqtg04jdlnjhc"',
                                  'PlayerData="*res://player_data.gd"')
        project = project.replace('PackedStringArray("4.7", "Forward Plus")',
                                  'PackedStringArray("4.7", "GL Compatibility")')
        project = project.replace('enabled=PackedStringArray("res://addons/godot_mcp/plugin.cfg")',
                                  'enabled=PackedStringArray()')
        project = project.replace('[rendering]', '[rendering]\n\nrenderer/rendering_method="gl_compatibility"\nrenderer/rendering_method.mobile="gl_compatibility"')
        (stage / "project.godot").write_text(project + "\n")
        preset = (root / "export_presets.cfg").read_text()
        if args.template:
            template = args.template.resolve(strict=True)
            preset = preset.replace('custom_template/release=""',
                                    f'custom_template/release="{template.as_posix()}"')
        (stage / "export_presets.cfg").write_text(preset)
        subprocess.run([args.godot, "--headless", "--path", str(stage),
                        "--editor", "--import", "--log-file", str(root / "build/import.log")], check=True)
        subprocess.run([args.godot, "--headless", "--path", str(stage),
                        "--log-file", str(root / "build/export.log"),
                        "--export-release", "Web", str(output / "index.html")], check=True)
        for log in (root / "build/import.log", root / "build/export.log"):
            if "SCRIPT ERROR:" in log.read_text() or "Parse Error:" in log.read_text():
                raise RuntimeError(f"Godot reported script errors; inspect {log}")
    for name in ("index.html", "index.js", "index.wasm", "index.pck"):
        if not (output / name).is_file():
            raise RuntimeError(f"Export did not produce {name}")
    print(f"Web release: {output}")


if __name__ == "__main__":
    main()
