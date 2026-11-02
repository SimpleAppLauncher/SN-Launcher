# Data safety worksheet — SN-Launcher 0.3.0

This is a review worksheet for the Play Console Data safety form, not a claim
that the form has been submitted. The app is a local-first Android launcher. It
has no account, no analytics SDK, no advertising SDK, and no developer-operated
server.

## What the app stores on the device

| Data | Where | Why |
| --- | --- | --- |
| Settings, brightness, theme, theme schedule, to-do list | App-private local storage | Keep the launcher configured |
| Photo cache and photo credits | App-private cache/storage | Avoid re-downloading the rotating photo frame and keep attribution visible |
| Media-session title/artist/album/artwork/actions | Memory only, from the optional Notification access grant | Draw the now-playing strip and offer only the transport actions the session advertises |
| Installed-app names, package names and icons | Memory only, from Android `PackageManager` | Draw the app row and searchable drawer |

Clearing app data or uninstalling the app removes the app-private local data.
The developer has no account or server from which to delete it.

## What leaves the device

The app makes direct requests to third-party services. It does not route them
through a developer-operated backend.

| Destination | Data sent | When |
| --- | --- | --- |
| `api.open-meteo.com` | Latitude/longitude rounded to three decimals, plus the weather query | Weather page |
| `ipwho.is` | The device's public IP address, used for approximate location fallback | When location is needed and the device location path is unavailable |
| `commons.wikimedia.org` | Place coordinates/query and normal HTTP request metadata, including the app's User-Agent | Rotating photo frame and place-photo lookup |
| User-configured NCS-SMLauncher address (LAN) | Music commands and the configured address | Only when the user connects the ef music page to their own player |
| User-configured Home Assistant address | Requests to the user's own Home Assistant instance | Only when the user configures it in an enabled build |
| Optional assistant backend | The user's prompt, only if the user configures and uses that backend | Assistant path; not verified in 0.3.0 |
| `somafm.com` / `ice1.somafm.com` / `ice2.somafm.com` | Normal stream/song-info requests | Only on the disabled Home control page |

The developer does not receive, sell or share the local settings, to-do list,
photo cache or notification metadata. Third-party services receive the request
data and network metadata described above under their own privacy policies.

## Play Console answers to review

- **Does the app collect or share data?** The developer operates no collection
  backend. The app does transmit approximate location/coordinates to
  Open-Meteo and the device IP to `ipwho.is` for weather/location. If Play's
  definition treats those direct third-party requests as sharing, declare
  **approximate location** and the relevant network/diagnostic data, and link
  the privacy policy. Do not submit the form until this is reviewed against the
  current Play definition.
- **Is data encrypted in transit?** The public weather, geolocation and
  Wikimedia requests use HTTPS. User-configured LAN services may be HTTP; that
  is the user's own network choice and is disclosed.
- **Can users request deletion?** There is no developer account or server.
  Uninstalling the app or clearing its data deletes local data. Requests to
  third-party services are outside the app's control.
- **Is data used for advertising or tracking?** No advertising SDK and no
  cross-app tracking. No analytics SDK.
- **Children?** The launcher is a general-purpose utility, not directed to
  children under 13.

## Permissions to explain

- **Internet** — weather, photos, optional assistant, user-configured LAN
  services.
- **Notification access** — optional; reads media-session metadata to draw the
  now-playing strip. It is not used to read ordinary notifications.
- **Location** — optional; weather. The app can fall back to IP-based
  approximate location.
- **Microphone / calendar** — only in the sensitive opt-in build, not the normal
  release. The assistant is not verified in 0.3.0.
- **Foreground media playback service** — declared for the music path; no
  shipped page currently starts playback.
