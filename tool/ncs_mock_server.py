#!/usr/bin/env python3
"""A stand-in for NCS-SMLauncher, so the launcher's music page can be built and
looked at before the real player exists.

It speaks the same protocol the client in `lib/src/services/ncs_client.dart`
speaks:

    GET  /state                 the snapshot
    POST /control               {"action": ..., "value": ..., "id": ...}
    GET  /browse                the library
    GET  /art/<id>.png          generated artwork

Run it on the machine that is on the same network as the tablet:

    python3 tool/ncs_mock_server.py --port 8737

Then open the launcher's music page and enter the address it printed. It draws
the artwork itself, so there is nothing to download and no dependency.

This file is a test fixture, not the product. It exists because "the other
player is not ready" must not be a reason the UI cannot be finished, and
because a mock that speaks the real wire format catches shape mistakes that a
mock that speaks function calls never will.
"""

from __future__ import annotations

import argparse
import binascii
import json
import socket
import struct
import threading
import time
import zlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse

# A small NCS-flavoured library. Metadata only: there is no audio here, and the
# player says so rather than pretending.
LIBRARY = [
    {"id": "on-and-on", "title": "On & On", "artist": "Cartoon",
     "album": "NCS", "durationMs": 207000, "hue": 12},
    {"id": "sky-high", "title": "Sky High", "artist": "Elektronomia",
     "album": "NCS", "durationMs": 202000, "hue": 205},
    {"id": "fade", "title": "Fade", "artist": "Alan Walker",
     "album": "NCS", "durationMs": 262000, "hue": 260},
    {"id": "invincible", "title": "Invincible", "artist": "DEAF KEV",
     "album": "NCS", "durationMs": 249000, "hue": 320},
    {"id": "heroes-tonight", "title": "Heroes Tonight", "artist": "Janji",
     "album": "NCS", "durationMs": 198000, "hue": 36},
    {"id": "force", "title": "Force", "artist": "Alan Walker",
     "album": "NCS", "durationMs": 240000, "hue": 150},
    {"id": "my-heart", "title": "My Heart", "artist": "Different Heaven",
     "album": "NCS", "durationMs": 232000, "hue": 95},
    {"id": "candyland", "title": "Candyland", "artist": "Tobu",
     "album": "NCS", "durationMs": 216000, "hue": 285},
]

BY_ID = {track["id"]: track for track in LIBRARY}


class Player:
    """The playback state, and the arithmetic that moves it with the clock."""

    def __init__(self) -> None:
        self.lock = threading.Lock()
        self.index = 0
        self.playing = True
        self.offset_ms = 42000
        self.anchor = time.monotonic()
        self.volume = 0.75

    def position_ms(self) -> int:
        track = LIBRARY[self.index]
        if not self.playing:
            return self.offset_ms
        elapsed = int((time.monotonic() - self.anchor) * 1000)
        total = track["durationMs"]
        position = self.offset_ms + elapsed
        # A real player moves on when a track ends. Not moving on would make the
        # progress bar sit pinned at the end, which looks broken.
        if position >= total:
            self._next()
            return self.offset_ms
        return position

    def _next(self) -> None:
        self.index = (self.index + 1) % len(LIBRARY)
        self.offset_ms = 0
        self.anchor = time.monotonic()

    def _previous(self) -> None:
        self.index = (self.index - 1) % len(LIBRARY)
        self.offset_ms = 0
        self.anchor = time.monotonic()

    def snapshot(self) -> dict:
        with self.lock:
            position = self.position_ms()
            track = LIBRARY[self.index]
            queue = [
                {
                    "id": LIBRARY[(self.index + step) % len(LIBRARY)]["id"],
                    "title": LIBRARY[(self.index + step) % len(LIBRARY)]["title"],
                    "artist": LIBRARY[(self.index + step) % len(LIBRARY)]["artist"],
                    "durationMs": LIBRARY[(self.index + step) % len(LIBRARY)]["durationMs"],
                    "artwork": f"/art/{LIBRARY[(self.index + step) % len(LIBRARY)]['id']}.png",
                }
                for step in range(1, 5)
            ]
            return {
                "playing": self.playing,
                "server": "NCS-SMLauncher (mock)",
                "positionMs": position,
                "durationMs": track["durationMs"],
                "volume": self.volume,
                "track": {
                    "id": track["id"],
                    "title": track["title"],
                    "artist": track["artist"],
                    "album": track["album"],
                    "durationMs": track["durationMs"],
                    "artwork": f"/art/{track['id']}.png",
                },
                "queue": queue,
            }

    def control(self, action: str, value=None, track_id=None) -> None:
        with self.lock:
            if action == "play" and track_id in BY_ID:
                self.index = LIBRARY.index(BY_ID[track_id])
                self.offset_ms = 0
                self.anchor = time.monotonic()
                self.playing = True
                return
            if action == "play":
                self.playing = True
                self.anchor = time.monotonic()
            elif action == "pause":
                self.offset_ms = self.position_ms()
                self.playing = False
            elif action == "next":
                self._next()
                self.playing = True
            elif action in ("previous", "prev"):
                self._previous()
                self.playing = True
            elif action == "seek" and value is not None:
                self.offset_ms = max(0, int(value))
                self.anchor = time.monotonic()
            elif action == "volume" and value is not None:
                self.volume = min(1.0, max(0.0, float(value)))
            elif action == "shuffle":
                import random

                self.index = random.randrange(len(LIBRARY))
                self.offset_ms = 0
                self.anchor = time.monotonic()
            # repeat, and anything else, is accepted and ignored: a control
            # surface that rejects unknown verbs breaks when the other side
            # learns a new one.


PLAYER = Player()


def make_art(hue: float) -> bytes:
    """A 512×512 PNG: two colours and a diagonal band.

    Generated rather than shipped, so this file has no binary assets and no
    licence questions. It is deliberately not a photograph — nobody should
    mistake a test fixture for a real album cover.
    """
    width = height = 512

    def hsl_to_rgb(h: float, s: float, light: float) -> tuple[int, int, int]:
        c = (1 - abs(2 * light - 1)) * s
        x = c * (1 - abs((h / 60) % 2 - 1))
        m = light - c / 2
        if h < 60:
            r, g, b = c, x, 0
        elif h < 120:
            r, g, b = x, c, 0
        elif h < 180:
            r, g, b = 0, c, x
        elif h < 240:
            r, g, b = 0, x, c
        elif h < 300:
            r, g, b = x, 0, c
        else:
            r, g, b = c, 0, x
        return tuple(int((v + m) * 255) for v in (r, g, b))

    start = hsl_to_rgb(hue % 360, 0.55, 0.38)
    end = hsl_to_rgb((hue + 40) % 360, 0.6, 0.14)

    rows = bytearray()
    for y in range(height):
        rows.append(0)  # filter: none
        for x in range(width):
            t = (x + y) / (width + height)
            # A light diagonal band across the middle, so the tiles do not read
            # as flat colour swatches.
            band = 0.10 if abs(((x - y) % 512) - 256) < 26 else 0.0
            r = int(start[0] * (1 - t) + end[0] * t + band * 255)
            g = int(start[1] * (1 - t) + end[1] * t + band * 255)
            b = int(start[2] * (1 - t) + end[2] * t + band * 255)
            rows += bytes((min(255, r), min(255, g), min(255, b), 255))

    def chunk(kind: bytes, data: bytes) -> bytes:
        return (
            struct.pack(">I", len(data))
            + kind
            + data
            + struct.pack(">I", binascii.crc32(kind + data) & 0xFFFFFFFF)
        )

    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(bytes(rows), 6))
        + chunk(b"IEND", b"")
    )


_ART_CACHE: dict[str, bytes] = {}


def art_for(track_id: str) -> bytes:
    if track_id not in _ART_CACHE:
        track = BY_ID.get(track_id)
        hue = float(track["hue"]) if track else 200.0
        _ART_CACHE[track_id] = make_art(hue)
    return _ART_CACHE[track_id]


class Handler(BaseHTTPRequestHandler):
    server_version = "NCSMock/1.0"

    def log_message(self, fmt: str, *args) -> None:
        # One line per request, so the launcher opening a page is visible.
        print(f"  {self.address_string()}  {fmt % args}")

    def _json(self, payload: dict, status: int = 200) -> None:
        body = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self) -> None:  # noqa: N802 — the name is the base class's
        path = urlparse(self.path).path
        if path == "/state":
            self._json(PLAYER.snapshot())
        elif path == "/browse":
            tracks = [
                {
                    "id": t["id"],
                    "title": t["title"],
                    "artist": t["artist"],
                    "album": t["album"],
                    "durationMs": t["durationMs"],
                    "artwork": f"/art/{t['id']}.png",
                }
                for t in LIBRARY
            ]
            self._json({"tracks": tracks})
        elif path.startswith("/art/"):
            track_id = path[len("/art/"):].rsplit(".", 1)[0]
            body = art_for(track_id)
            self.send_response(200)
            self.send_header("Content-Type", "image/png")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        else:
            self._json({"error": "not found"}, status=404)

    def do_POST(self) -> None:  # noqa: N802
        path = urlparse(self.path).path
        if path != "/control":
            self._json({"error": "not found"}, status=404)
            return
        length = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(length) if length else b"{}"
        try:
            payload = json.loads(raw or b"{}")
        except json.JSONDecodeError:
            self._json({"error": "bad json"}, status=400)
            return
        action = payload.get("action")
        if not isinstance(action, str) or not action:
            self._json({"error": "no action"}, status=400)
            return
        PLAYER.control(action, payload.get("value"), payload.get("id"))
        self.send_response(204)
        self.end_headers()


def local_ip() -> str:
    """The address the tablet should use, not 127.0.0.1."""
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        sock.connect(("192.0.2.1", 9))  # TEST-NET-1: no packet ever leaves
        return sock.getsockname()[0]
    except OSError:
        return "127.0.0.1"
    finally:
        sock.close()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=8737)
    parser.add_argument("--host", default="0.0.0.0")
    args = parser.parse_args()

    server = ThreadingHTTPServer((args.host, args.port), Handler)
    ip = local_ip()
    print("NCS-SMLauncher mock player")
    print(f"  listening on http://0.0.0.0:{args.port}")
    print(f"  enter this in the launcher:  http://{ip}:{args.port}")
    print(f"  the library is {len(LIBRARY)} tracks; no audio is played")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n  stopped")


if __name__ == "__main__":
    main()
