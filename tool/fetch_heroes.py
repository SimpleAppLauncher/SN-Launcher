#!/usr/bin/env python3
"""Fetches the bundled *first* photographs of the racing and Alonso albums.

Why a bundled photograph at all: the launcher has to paint something the
moment it starts, on a tablet that may have no network, and the wall must
never be blank. So each album ships one photograph in the APK; the rest of
the rotation is fetched from Wikimedia Commons at runtime by
`lib/src/services/photo_frame_service.dart`.

The licence rules are the same ones `tool/fetch_photo.py` applies, and the
same ones the app applies at fetch time: public domain, CC0 or plain CC-BY
only. Share-alike is refused — a launcher cannot honour the viral-licensing
obligation — and this script refuses to write a file whose live licence is
not in that set.

    python3 tool/fetch_heroes.py            # verify, download, write all outputs
    python3 tool/fetch_heroes.py --check    # verify licence + decode only

Writes:
    assets/photo/racing.jpg / racing.json   the first photograph of *Cars*
    assets/photo/alonso.jpg / alonso.json   the first photograph of *Alonso*
    assets/photo/ATTRIBUTION.md             regenerated from every sidecar
"""
from __future__ import annotations

import argparse
import html
import json
import re
import ssl
import sys
import urllib.error
import urllib.parse
import urllib.request
from io import BytesIO
from pathlib import Path

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
import attribution  # noqa: E402

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
OUT_DIR = ROOT / "assets" / "photo"

# The bundled first photographs.
#
# `racing` is the Renault R25 from 2005 — the car that took Alonso to his
# first two world titles, and the clearest possible "racing car" for an album
# that has to say what it is in one glance.
#
# `alonso` is Alonso himself at the 2005 Chinese Grand Prix, the season he
# won his first championship. The Alonso album is half about the car and half
# about the driver, and this one is the driver.
HEROES = (
    {
        "slug": "racing",
        "commons_filename": "Renault R25 2005 United States GP (19887965).jpg",
        "display_title": "Renault R25 — United States Grand Prix 2005",
        "author": "Ryosuke Yagi",
    },
    {
        "slug": "alonso",
        "commons_filename": "Fernando Alonso 2005 China.jpg",
        "display_title": "Fernando Alonso — Chinese Grand Prix 2005",
        "author": "Tinou Bao",
    },
)

ACCEPT_EXACT = {"public domain", "cc0", "cc0 1.0"}
FORBIDDEN = ("nc", "nd", "-sa", "fair use", "non-free", "noncommercial")
ACCEPT_SUBSTR = ("public domain", "cc0", "cc by ", "cc-by ", "cc-zero")

FETCH_WIDTH = 2400
MAX_WIDTH = 1920
JPEG_QUALITY = 80

COMMONS_API = "https://commons.wikimedia.org/w/api.php"
USER_AGENT = "NestLaunchPhotoFetcher/1.0 (educational launcher; attribution recorded)"

_CA_CANDIDATES = (
    "/etc/ssl/cert.pem",
    "/etc/pki/tls/certs/ca-bundle.crt",
    "/etc/ssl/certs/ca-certificates.crt",
)


def http_get(url: str, timeout: int = 90) -> bytes:
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    contexts = [ssl.create_default_context(cafile=ca)
                for ca in _CA_CANDIDATES if Path(ca).exists()]
    contexts.append(ssl.create_default_context())

    last_err = None
    for ctx in contexts:
        try:
            with urllib.request.urlopen(req, context=ctx, timeout=timeout) as resp:
                return resp.read()
        except urllib.error.URLError as err:
            last_err = err
            continue

    print("  ! every verified TLS context failed; retrying with an unverified "
          "context (host CA bundle missing?).", file=sys.stderr)
    ctx = ssl._create_unverified_context()
    with urllib.request.urlopen(req, context=ctx, timeout=timeout) as resp:
        return resp.read()


def strip_html(s) -> str:
    return re.sub(r"<[^>]+>", "", str(s or "")).strip()


def is_allowed_license(name: str) -> bool:
    n = html.unescape(strip_html(name)).lower().strip()
    if not n:
        return False
    if any(bad in n for bad in FORBIDDEN):
        return False
    return n in ACCEPT_EXACT or any(tok in n for tok in ACCEPT_SUBSTR)


def fetch_metadata(hero: dict) -> dict:
    title = "File:" + hero["commons_filename"]
    params = {
        "action": "query",
        "titles": title,
        "prop": "imageinfo",
        "iiprop": "url|extmetadata|size",
        "iiurlwidth": str(FETCH_WIDTH),
        "format": "json",
    }
    url = COMMONS_API + "?" + urllib.parse.urlencode(params)
    data = json.loads(http_get(url).decode("utf-8"))
    pages = (data.get("query") or {}).get("pages") or {}
    for page in pages.values():
        if "missing" in page:
            sys.exit("Commons file not found: %s" % title)
        info = (page.get("imageinfo") or [{}])[0]
        meta = info.get("extmetadata") or {}

        license_name = strip_html(
            (meta.get("LicenseShortName") or {}).get("value")
            or (meta.get("UsageTerms") or {}).get("value")
        )
        if not license_name:
            sys.exit("Commons returned no licence for %s; refusing to write." % title)

        license_url = strip_html((meta.get("LicenseUrl") or {}).get("value"))

        return {
            "title": hero["display_title"],
            "author": hero["author"],
            "license": license_name,
            "licenseUrl": license_url,
            "sourceUrl": info.get("descriptionurl", ""),
            "url": info.get("thumburl") or info.get("url", ""),
        }
    sys.exit("no imageinfo in the Commons response for %s" % title)


def build_image(raw: bytes) -> Image.Image:
    im = Image.open(BytesIO(raw)).convert("RGB")
    if im.width > MAX_WIDTH:
        h = round(im.height * MAX_WIDTH / im.width)
        im = im.resize((MAX_WIDTH, h), Image.LANCZOS)
    return im


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description="Fetch the album hero photographs.")
    ap.add_argument("--check", action="store_true",
                    help="verify licence + decode only; write nothing")
    args = ap.parse_args(argv)

    OUT_DIR.mkdir(parents=True, exist_ok=True)

    for hero in HEROES:
        meta = fetch_metadata(hero)
        if not is_allowed_license(meta["license"]):
            sys.exit(
                "licence %r for %s is not in the allowed set (public domain / "
                "CC0 / plain CC-BY only); refusing to write."
                % (meta["license"], hero["commons_filename"])
            )
        print("  %s  (%s)" % (meta["title"], hero["commons_filename"]))
        print("  by %s — %s" % (meta["author"], meta["license"]))

        raw = http_get(meta["url"])
        if len(raw) < 10_000:
            sys.exit("download failed or produced a suspiciously small file")
        im = build_image(raw)

        if args.check:
            print("  --check: licence verified (%s), decoded %s. Nothing written."
                  % (meta["license"], im.size))
            continue

        dest = OUT_DIR / ("%s.jpg" % hero["slug"])
        im.save(dest, "JPEG", quality=JPEG_QUALITY, optimize=True, progressive=True)

        with open(OUT_DIR / ("%s.json" % hero["slug"]), "w") as f:
            json.dump({
                "title": meta["title"],
                "author": meta["author"],
                "license": meta["license"],
                "licenseUrl": meta["licenseUrl"],
                "sourceUrl": meta["sourceUrl"],
                "width": im.width,
                "height": im.height,
            }, f, indent=2)
            f.write("\n")

        print("  -> assets/photo/%s.jpg (%dx%d, %.0f KB)"
              % (hero["slug"], im.width, im.height, dest.stat().st_size / 1024))

    dest = attribution.write(OUT_DIR)
    print("  -> %s" % dest.relative_to(ROOT))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
