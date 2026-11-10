#!/usr/bin/env python3
"""
Scaffold a new Ketamine alternate app icon from one source image.

Generates the `<id>.appiconset` (home screen icon) and `<id>Preview.imageset`
(in-app picker thumbnail) asset catalogs, registers `<id>` as an alternate
icon in Info.plist, and appends {id, title, creator} to
Ketamine/Resources/AppIcons.json. Nothing else needs to change — the picker
UI (AppIconCatalog.swift / AppIconPickerView.swift) reads both at runtime.

Usage:
    scripts/add_app_icon.py <source-image> <Id> "<Title>" "<Creator>"

Example:
    scripts/add_app_icon.py ~/Downloads/wojak.png AppIconWojak "Wojak" "Slitzy"

Requires ImageMagick (`magick`, or the older `convert`) for the image work —
`apt install imagemagick` / `brew install imagemagick` / etc. Runs on Linux,
macOS, or anywhere else ImageMagick is available; no Xcode needed, since this
only touches files under Assets.xcassets, Info.plist, and AppIcons.json —
build/CI (e.g. a macOS GitHub Actions runner) picks them up from there.
"""

import json
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

APPICONSET_CONTENTS = """{
  "images" : [
    {
      "filename" : "icon_1024.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
"""

PREVIEW_IMAGESET_CONTENTS = """{
  "images" : [
    {
      "filename" : "preview.png",
      "idiom" : "universal"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
"""


def fail(message: str) -> None:
    print(f"error: {message}", file=sys.stderr)
    sys.exit(1)


def find_imagemagick() -> tuple[list, list]:
    """Returns (convert_cmd, identify_cmd) for whichever ImageMagick
    generation is installed: v7's `magick` (with `magick identify` as the
    inspection subcommand) or the legacy v6 standalone `convert`/`identify`
    binaries."""
    if shutil.which("magick"):
        return ["magick"], ["magick", "identify"]
    if shutil.which("convert") and shutil.which("identify"):
        return ["convert"], ["identify"]
    fail(
        "ImageMagick not found. Install it (e.g. `apt install imagemagick`, "
        "`brew install imagemagick`) and try again."
    )


def run(cmd: list) -> subprocess.CompletedProcess:
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        fail(f"{' '.join(cmd)} failed:\n{result.stdout}\n{result.stderr}")
    return result


def square_and_resize(source: Path, size: int, out: Path, tmp_dir: Path) -> None:
    """Pad `source` onto a white square canvas sized to its longest side (no
    distortion, no cropping), then downscale/upscale that square to `out`."""
    convert_cmd, identify_cmd = find_imagemagick()

    dims = run([*identify_cmd, "-format", "%w %h", str(source)])
    width, height = (int(n) for n in dims.stdout.split())
    side = max(width, height)

    squared = tmp_dir / f"{out.stem}_squared.png"
    run([
        *convert_cmd, str(source),
        "-background", "white",
        "-gravity", "center",
        "-extent", f"{side}x{side}",
        str(squared),
    ])
    run([*convert_cmd, str(squared), "-resize", f"{size}x{size}", str(out)])


def main() -> None:
    if len(sys.argv) != 5:
        print(__doc__)
        sys.exit(1 if len(sys.argv) > 1 else 0)

    source = Path(sys.argv[1]).expanduser()
    icon_id, title, creator = sys.argv[2], sys.argv[3], sys.argv[4]

    find_imagemagick()  # fail fast with a clear message if it's missing
    if not source.is_file():
        fail(f"source image not found: {source}")
    if not re.fullmatch(r"AppIcon[A-Za-z0-9]+", icon_id):
        fail(f"Id must look like 'AppIconFoo' (got '{icon_id}')")

    root = Path(__file__).resolve().parent.parent
    assets = root / "Ketamine" / "Assets" / "Assets.xcassets"
    icon_set = assets / f"{icon_id}.appiconset"
    preview_set = assets / f"{icon_id}Preview.imageset"
    info_plist = root / "Ketamine" / "App" / "Info.plist"
    manifest = root / "Ketamine" / "Resources" / "AppIcons.json"

    if icon_set.exists() or preview_set.exists():
        fail(f"{icon_id} already exists in Assets.xcassets")

    icon_set.mkdir(parents=True)
    preview_set.mkdir(parents=True)

    with tempfile.TemporaryDirectory() as tmp:
        tmp_dir = Path(tmp)

        print(f"Rendering {icon_id}.appiconset (1024x1024)...")
        square_and_resize(source, 1024, icon_set / "icon_1024.png", tmp_dir)
        (icon_set / "Contents.json").write_text(APPICONSET_CONTENTS)

        print(f"Rendering {icon_id}Preview.imageset (512x512)...")
        square_and_resize(source, 512, preview_set / "preview.png", tmp_dir)
        (preview_set / "Contents.json").write_text(PREVIEW_IMAGESET_CONTENTS)

    print(f"Registering {icon_id} in Info.plist...")
    with open(info_plist, "rb") as f:
        plist = plistlib.load(f)
    plist["CFBundleIcons"]["CFBundleAlternateIcons"][icon_id] = {
        "CFBundleIconFiles": [icon_id]
    }
    with open(info_plist, "wb") as f:
        plistlib.dump(plist, f)

    print(f"Adding {icon_id} to {manifest.relative_to(root)}...")
    icons = json.loads(manifest.read_text())
    icons = [entry for entry in icons if entry["id"] != icon_id]
    icons.append({"id": icon_id, "title": title, "creator": creator})
    manifest.write_text(json.dumps(icons, indent=2) + "\n")

    print(f"\nDone. {icon_id} (\"{title}\" by {creator}) is registered.")
    print("No Swift or project.yml changes needed — rebuild and it'll show up in Settings > App Icon.")


if __name__ == "__main__":
    main()
