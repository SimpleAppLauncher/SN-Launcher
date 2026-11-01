# SN-Launcher promo

An 18-second, silent 1920×1080 promo built with Remotion.

## Run it

```bash
npm install
npm run start      # Remotion Studio
npm run render     # video/out/sn-launcher.mp4
npm run still      # video/out/cover.png
```

The rendered files in `out/` are ignored. The tracked copy of the final render is
`sn-launcher.mp4`, with `poster.jpg` as its poster frame.

## What is on screen

- `public/home.jpg` — real launcher home capture.
- `public/sheet.jpg` — real dock capture.
- `public/now-playing.png` — the launcher’s now-playing card, rendered from the
  widget with a real Spotify session’s metadata. It is not a mock-up of a
  different app.
- No audio track. The video is deliberately silent.

## Structure

- `src/Video.tsx` — scenes and timing.
- `src/Root.tsx` — the 1920×1080, 30 fps, 540-frame composition.
- `remotion.config.ts` — JPEG frames, H.264 output settings.
