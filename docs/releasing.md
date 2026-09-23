# Releasing

A release is a version number, a tag, a GitHub release with the desktop builds
attached, and, when the extension changed, a Chrome Web Store upload. Work
through this list in order.

## Choosing the version

`VERSION` holds `MAJOR.MINOR.PATCH`.

- **Patch** (0.2.1 to 0.2.2): fixes only, nothing a user must learn.
- **Minor** (0.2.x to 0.3.0): new behaviour, a new platform, or a new setting.
- **Major**: reserved for 1.0, and after that for a change that breaks how
  existing users work.

Not every platform has to ship in every release. A release that only touches
the Mac app says so at the top of its notes and points Windows users at the
last release that had a Windows build.

## 1. Prepare

1. Set the new version in `VERSION`, and in the two manifests that cannot read
   it: `windows/LaTeXSquiggly.App/app.manifest` (as `x.y.z.0`) and
   `chrome/manifest.json`. `scripts/check-version.py` fails until all three
   agree.
2. In `CHANGELOG.md`, rename **Unreleased** to the new version and date, and
   start a new empty **Unreleased** section above it.
3. Run `scripts/check-all.sh`. Everything passes, or nothing ships.
4. Commit: *Release x.y.z*.

## 2. Build

Build only the platforms that changed.

```
DMG=1 scripts/build-mac-app.sh     # build/LaTeX-Squiggly-x.y.z.dmg
scripts/build-windows.sh           # windows/dist/win-x64/LaTeX Squiggly.exe
scripts/package-chrome.sh          # build/LaTeX-Squiggly-x.y.z-chrome.zip
```

Rename the Windows executable to `LaTeX-Squiggly-x.y.z-windows-x64.exe` before
attaching it, so downloads from different releases cannot be confused.

Try each build on a real machine before publishing: install it, grant the
permissions, and type `\alpha` and a space into another app.

## 3. Publish

1. Tag and push:

   ```
   git tag vx.y.z
   git push origin main vx.y.z
   ```

2. Create the GitHub release from the tag, titled **LaTeX Squiggly x.y.z**, with
   the builds attached. The notes follow the shape of the earlier releases:
   a one-line summary, a download table (platform, file, what it needs), what
   changed for users, and the warnings each platform shows on first run.
3. If the extension changed, upload the zip in the
   [Chrome Web Store dashboard](https://chrome.google.com/webstore/devconsole)
   (**Package → Upload new package**, then **Submit for review**). See
   [chrome/STORE.md](../chrome/STORE.md). Adding a permission shows every
   existing user a warning and disables the extension until they accept it,
   so avoid it unless a feature cannot work without it.

## 4. After

- Check that the website's download links reach the new release. They point at
  `releases/latest`, so they update themselves.
- If a published build turns out to be broken, replace its asset on the same
  release and say so at the top of the notes, with the date, rather than
  silently swapping it.
