#!/usr/bin/env python3
"""
Exercise the rotation pools against the live Wikimedia Commons API.

The pools in `lib/src/services/photo_album.dart` are hardcoded lists of
Commons filenames. That is only safe if every entry actually resolves and is
still licence-clean, because a stale entry means the rotation silently skips a
photo every cycle — or, worse, installs something under a licence we would not
accept.

This checks, for every entry in every album:
  * the file still exists on Commons
  * the licence is still one of public domain / CC0 / CC-BY
  * a 1600px thumbnail is actually offered

    python3 tool/verify_photo_pool.py

Exits non-zero if any entry fails, so it can be run in CI.

Titles are queried in batches: the MediaWiki API takes up to 50 titles per
request, and asking for them one at a time gets the caller rate-limited.
"""
import json
import os
import re
import subprocess
import sys
import time
import urllib.parse

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
ALBUM = os.path.join(ROOT, "lib", "src", "services", "photo_album.dart")

FORBIDDEN = ("-nc", "-nd", "-sa", "sharealike", "share alike", "share-alike",
             "fair use", "non-free")
ALLOWED_PREFIXES = ("public domain", "cc0", "cc by")

# The pools, in the order they are defined in photo_album.dart.
POOLS = ("landscapePool", "racingPool", "alonsoCarPool", "alonsoSubjectPool")

# Titles per API request. 50 is the limit for an anonymous caller.
BATCH = 25


def pool_titles(name):
    """The Commons filenames in one `static const List<AlbumPhoto> <name>`."""
    src = open(ALBUM, encoding="utf-8").read()
    marker = "static const List<AlbumPhoto> %s = [" % name
    start = src.index(marker) + len(marker)
    block = src[start:]
    block = block[:block.index("\n  ];")]
    return re.findall(r"AlbumPhoto\(\s*\n?\s*'((?:[^'\\]|\\.)*)'", block)


def normalise(title):
    """Mirror the API's title normalisation so lookups line up.

    Commons turns underscores into spaces and upper-cases the first
    character, so "xsara wrc.jpg" comes back as "Xsara WRC.JPG".
    """
    t = title.replace("_", " ").strip()
    if t.startswith("File:"):
        t = t[5:]
    return t[:1].upper() + t[1:]


def api(titles):
    """One API request for a batch of titles. Returns {normalised: page}."""
    q = urllib.parse.urlencode({
        "action": "query",
        "titles": "|".join("File:" + t for t in titles),
        "prop": "imageinfo",
        "iiprop": "url|extmetadata|size",
        "iiurlwidth": "1600",
        "format": "json",
    })
    url = "https://commons.wikimedia.org/w/api.php?" + q
    for attempt in range(5):
        out = subprocess.run(
            ["curl", "-sSL", "--max-time", "90", "-H",
             "User-Agent: SNLauncher/0.2 (pool verifier)", url],
            capture_output=True, text=True).stdout
        try:
            d = json.loads(out)
        except Exception:
            time.sleep(2 + attempt * 3)
            continue
        if isinstance(d, dict) and "error" in d:
            # Rate limited or otherwise refused — back off and try again.
            time.sleep(5 + attempt * 10)
            continue
        pages = ((d.get("query") or {}).get("pages")) or {}
        return {normalise(str(p.get("title", ""))): p for p in pages.values()
                if isinstance(p, dict)}
    return {}


def main():
    pools = [(p, pool_titles(p)) for p in POOLS]
    total = sum(len(t) for _, t in pools)
    print(f"checking {total} pool entries against Commons\n")

    failures = []
    for pool, titles in pools:
        print(f"{pool} — {len(titles)} entries")
        for i in range(0, len(titles), BATCH):
            batch = titles[i:i + BATCH]
            pages = api([t.replace("\\'", "'") for t in batch])
            for raw in batch:
                title = raw.replace("\\'", "'")
                page = pages.get(normalise(title))
                if page is None:
                    # Fall back to a case-insensitive match: Commons also
                    # capitalises the first letter of a file name.
                    wanted = normalise(title).lower()
                    for key, value in pages.items():
                        if key.lower() == wanted:
                            page = value
                            break
                if page is None:
                    print(f"  MISSING                {title[:52]}")
                    failures.append(title)
                    continue
                if "missing" in page:
                    print(f"  MISSING                {title[:52]}")
                    failures.append(title)
                    continue
                info = ((page.get("imageinfo") or [{}])[0])
                em = info.get("extmetadata") or {}
                lic = ((em.get("LicenseShortName") or {}).get("value") or "")
                low = lic.lower().strip()
                if not low or any(b in low for b in FORBIDDEN) or \
                        not low.startswith(ALLOWED_PREFIXES):
                    print(f"  BAD LICENCE {lic[:18]:<19} {title[:40]}")
                    failures.append(title)
                    continue
                if not info.get("thumburl"):
                    print(f"  NO THUMB               {title[:52]}")
                    failures.append(title)
                    continue
                print(f"  ok  {lic[:18]:<20} {title[:48]}")
            time.sleep(1.0)
        print()

    if failures:
        print(f"FAIL: {len(failures)} of {total} unusable")
        for f in failures:
            print(f"  - {f}")
        return 1
    print(f"PASS: all {total} entries resolve and are licence-clean")
    return 0


if __name__ == "__main__":
    sys.exit(main())
