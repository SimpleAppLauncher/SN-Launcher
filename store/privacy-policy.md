# SN-Launcher privacy policy

**Effective: 2026-11-02**

**Applies to: SN-Launcher 0.3.0 (reduced and ef builds)**

SN-Launcher is an Android home-screen replacement. It is a local-first app: no
account, no analytics SDK, no advertising, and no developer-operated server.

## What stays on the device

- Settings, the to-do list, the time-based theme schedule, cached photos and
  photo credits are stored in the app's private storage.
- If you grant Notification access, the app reads media-session metadata —
  title, artist, album, artwork, playback state and the actions the player
  advertises — so it can draw the now-playing strip and its controls. That
  metadata is processed locally and is not uploaded by the app.
- Installed-app names, labels and icons are read through Android's
  `PackageManager` so the app drawer can show the real apps on the device. That
  data stays on the device.

## Network requests

The app makes direct requests only for features that are used:

- **Weather** — coordinates rounded to three decimal places are sent to
  Open-Meteo (`api.open-meteo.com`) to fetch a forecast.
- **Approximate location fallback** — if a location is not available, the app
  requests `ipwho.is`. That service sees the device's IP address and returns an
  approximate location, which the app stores locally.
- **Photos** — the Wikimedia Commons API (`commons.wikimedia.org`) is queried for
  public-domain or Creative Commons photos, and the selected image is downloaded
  and cached. The request's User-Agent identifies SN-Launcher.
- **NCS-SMLauncher** — if you configure a music server, requests go directly to
  the LAN address you entered.
- **Home Assistant** — if you configure a Home Assistant base URL, requests go
  directly to that address.
- **Optional assistant** — if an assistant backend is enabled and configured,
  requests go to the endpoint configured for it. The assistant is not part of
  the verified 0.3.0 release.
- **Radio** — SomaFM endpoints are used only on the Home control page, which is
  disabled in both shipped builds.

The developer does not operate a server that receives these requests, does not
sell data, and does not receive your settings, to-do list, photo cache or
notification metadata. Third-party services receive the request data and IP
address needed to answer the request, under their own privacy policies.

## Permissions

- **Internet** — weather, photos and optional LAN services.
- **Notification access** — optional; used for the now-playing strip and
  transport controls.
- **Location** — optional; used for weather. If denied, weather may not resolve
  a place.
- **Optional sensitive-permission build** — a separate build can opt into
  microphone and calendar permissions. Those permissions are not part of the
  default reduced or ef build. If that build is used, microphone and calendar
  data are processed locally for the features that request them.
- **Foreground media playback service** — declared for media playback support;
  it does not collect data.

## Retention and deletion

Uninstalling the app or clearing its app data removes the local settings,
to-do list, theme schedule and photo cache. There is no account or
developer-held data to delete. Requests already made to third-party services are
outside the developer's control.

## Children

SN-Launcher is a general-purpose launcher and is not directed to children under
13. It has no account system and does not knowingly collect personal
information from children.

## Changes and contact

Changes to this policy will be published in the repository with a new effective
date. Questions or privacy requests can be opened at
<https://github.com/SimpleAppLauncher/SN-Launcher/issues>.

This policy describes the app's actual local and network behavior as of the
0.3.0 release. It is not a substitute for a legal review before publishing to a
store.
