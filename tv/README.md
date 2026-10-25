# TV web fallback

This is the hand-written browser/Tizen web version of the TV shell, not the
Flutter app and not a third version. The primary TV target is the Flutter TPK
in `build/tizen/tpk/`; this folder exists so the remote-first focus model can be
previewed without Xcode or a TV.

Run it from the repository root:

```bash
cd ~/nestlaunch
python3 -m http.server 8088 --bind 127.0.0.1
# open http://127.0.0.1:8088/tv/
```

Keys: **←/→** pages, **↑/↓** focus, **Enter** select, **Esc** back.

Select the feature set with the same JSON files the Flutter app uses:

```bash
tv/scripts/use-build.sh ef
tv/scripts/use-build.sh reduced
```

That regenerates `js/features.generated.js`. The file currently committed is
the `ef` build.

This fallback has **not** been installed on the TV. It is not evidence that the
TPK works, and it is not in the release flow.
