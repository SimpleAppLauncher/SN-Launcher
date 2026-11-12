#!/usr/bin/env python3
"""Writes `assets/photo/ATTRIBUTION.md` from the bundled photographs' sidecars.

The sidecar JSON next to each bundled photograph is the single source of
truth: it is what the app reads to print the photographer's name on the wall,
and it is what this module reads to write the human-readable attribution file.

Keeping one writer means the attribution file cannot drift from what actually
ships — if a photograph is replaced and its sidecar updated, re-running the
fetch scripts regenerates a correct `ATTRIBUTION.md`.
"""
from __future__ import annotations

import datetime as _dt
import json
from pathlib import Path

# The sidecars that make up a bundled background, in the order they are shown.
SIDECARS = ("landscape.json", "racing.json", "alonso.json")

# A sentence about each photograph that the table cannot say.
NOTES = {
    "landscape": (
        "Public domain as a work of the US National Park Service. Credited\n"
        "anyway, because the photographer took the picture."
    ),
    "racing": (
        "The first photograph of the *Cars* album. The rest of that album's\n"
        "photographs are fetched from Wikimedia Commons at runtime — each one\n"
        "carries its own licence and its own credit, printed on screen."
    ),
    "alonso": (
        "The first photograph of the *Fernando Alonso* album. The rest of that\n"
        "album's photographs are fetched from Wikimedia Commons at runtime —\n"
        "each one carries its own licence and its own credit, printed on\n"
        "screen."
    ),
}

HEADER = """# Background photographs

Every photograph this app bundles or fetches carries a licence that permits
redistribution: public domain, CC0, or plain CC-BY. Share-alike, non-commercial
and no-derivatives files are refused — see `licenceAllowsRedistribution` in
`lib/src/services/photo_frame_service.dart` — and nothing may be written
around that check.

The photographer's name is rendered on screen next to the album title in
`lib/src/widgets/clock_block.dart`, fed by the sidecar JSON beside each
image.

"""


def write(out_dir: Path) -> Path:
    """Regenerate ATTRIBUTION.md from the sidecars in `out_dir`."""
    out_dir = Path(out_dir)
    rows = []
    for name in SIDECARS:
        path = out_dir / name
        if not path.exists():
            continue
        with open(path) as f:
            row = json.load(f)
        row["slug"] = path.stem
        rows.append(row)

    lines = [HEADER]
    for row in rows:
        lines.append("## %s\n" % row.get("title", "(untitled)"))
        lines.append("| Field | Value |")
        lines.append("| --- | --- |")
        lines.append("| Author (photographer) | %s |" % row.get("author", ""))
        lines.append("| Licence | %s |" % row.get("license", ""))
        if row.get("licenseUrl"):
            lines.append("| Licence URL | %s |" % row["licenseUrl"])
        if row.get("sourceUrl"):
            lines.append("| Source (Commons) | %s |" % row["sourceUrl"])
        if row.get("width") and row.get("height"):
            lines.append(
                "| Rendered size | %s × %s px |" % (row["width"], row["height"])
            )
        lines.append("")
        note = NOTES.get(row.get("slug", ""))
        if note:
            lines.append(note + "\n")

    lines.append(
        "*Fetched %s from Wikimedia Commons via `tool/fetch_photo.py` and\n"
        "`tool/fetch_heroes.py` (re-run to reproduce).*\n"
        % _dt.date.today().isoformat()
    )

    dest = out_dir / "ATTRIBUTION.md"
    dest.write_text("\n".join(lines))
    return dest
