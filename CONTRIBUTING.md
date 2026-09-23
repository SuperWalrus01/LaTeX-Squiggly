# Contributing

This is the rulebook for the repository: where things go, what they are called,
how a change is made and checked, and how a release goes out. Follow it for
every change, including the maintainer's own. When a rule here stops fitting,
change the rule in the same pull request as the code, so this file never
describes a repository that no longer exists.

Bug reports and symbol requests are welcome as
[issues](https://github.com/SuperWalrus01/LaTeX-Squiggly/issues/new/choose).
For anything larger than a small fix, open an issue before a pull request, so
the approach can be agreed before the work is done.

## The three rules

1. **The Swift engine is the source of truth.** Every conversion rule and every
   table starts in `Sources/LaTeXUnicode` or `Sources/InputTracking`. The
   Windows and Chrome engines follow it; they never lead it.
2. **Generated files are never edited by hand.** Edit the generator, then
   regenerate. `scripts/check-all.sh` fails if a generated file differs from
   what its generator produces.
3. **Every port answers to `conformance/reference.json`.** A change that
   alters what the engine says about any fragment regenerates the reference,
   and every port must pass it again before the change is merged.

## Where things go

```
.github/            issue and pull request templates, CI and site deployment
Sources/, Tests/    the Swift package: engine, typing and suppression rules,
Package.swift       macOS app, command-line tools, test suite
windows/            the Windows port (.NET 8)
chrome/             the Chrome extension
conformance/        the reference every port is checked against
assets/             source artwork and the icons generated from it
scripts/            everything that is run by hand
site/               the website, served by GitHub Pages
docs/               documentation beyond the READMEs
```

A new file goes in the folder whose job it matches:

| You are adding | It goes in |
|---|---|
| engine logic, a table, a trigger rule | `Sources/LaTeXUnicode/` or `Sources/InputTracking/` |
| macOS-only behaviour | `Sources/LaTeXSquigglyApp/` |
| a rule about where to stay quiet | `Sources/AppSuppression/`, then the matching Windows and Chrome code |
| a check for the Swift code | `Sources/LaTeXUnicodeChecks/` (not `Tests/`, which is only a wrapper) |
| Windows-only behaviour | `windows/LaTeXSquiggly.App/Platform/` |
| extension behaviour | the matching folder in `chrome/`, which its README maps |
| a script someone runs by hand | `scripts/` |
| artwork | `assets/` |
| a web page | `site/` |
| documentation longer than a README section | `docs/` |

Nothing new goes at the top level without a reason it cannot live in one of
these. The top level holds only the conventional files: `README.md`,
`CHANGELOG.md`, `CONTRIBUTING.md`, `SECURITY.md`, `LICENSE`, `VERSION`,
`Package.swift` and the dotfiles.

## Naming

- **Folders and files are lowercase kebab-case** (`build-mac-app.sh`,
  `menu-icon.png`, `dmg-background.tiff`), except where a toolchain sets the
  convention:
  - Swift: `Sources/`, `Tests/`, and one `UpperCamelCase.swift` file per type.
  - .NET: `PascalCase` project folders and `.cs` files.
  - Conventional documents: `README.md`, `CHANGELOG.md`, `CONTRIBUTING.md`,
    `SECURITY.md`, `LICENSE`, `VERSION`, and `STORE.md` in `chrome/`.
- **Scripts start with a verb** that says what kind of script they are:

  | Verb | Meaning | Example |
  |---|---|---|
  | `build-` | produce something to run or ship | `build-mac-app.sh` |
  | `install-` | put it on this machine | `install-mac-app.sh` |
  | `setup-` | one-time machine setup | `setup-mac-signing.sh` |
  | `check-` | verify, change nothing | `check-all.sh` |
  | `generate-` | write committed files from the engine | `generate-js-tables.py` |
  | `make-` | write committed files from artwork or the site | `make-site.py` |
  | `package-` | produce an upload for a store | `package-chrome.sh` |

  Then the target, platform first where it matters: `build-windows.sh`,
  `make-chrome-icons.py`.
- **Generated C# files end in `.g.cs`.** Other generated files say so in their
  first lines, naming the script that wrote them.

## Style

- **Indentation and whitespace** follow `.editorconfig`: 4 spaces in Swift, C#,
  Python and shell; 2 in JavaScript, CSS, HTML, JSON and YAML; no tabs; a final
  newline; LF line endings.
- **Match the code around you.** Before adding a pattern, look for how the
  surrounding code already does it.
- **Comments explain why, not what.** Say what the code cannot: the constraint,
  the bug it prevents, the measurement behind a number. Every script opens with
  a comment saying what it does and how to run it.
- **Documentation is prose in British English**, written for someone who has
  not read the code. Measured facts say how they were measured.
- **No dependencies without a strong reason.** The Swift package has none, the
  extension has none, and the Windows port uses only .NET itself. Scripts may
  use Python's standard library; the image scripts that need Pillow say so.

## Making a change

### Changing the engine

1. Change the Swift code, or the table generator
   `scripts/generate-swift-tables.py` for a table change, and run it.
2. Add or update the expectation in `Sources/LaTeXUnicodeChecks/`.
3. `swift build`, then regenerate what the other platforms read:

   ```
   python3 scripts/generate-js-tables.py
   python3 scripts/generate-csharp-tables.py
   python3 scripts/generate-conformance-reference.py
   ```

4. Port the logic change to `windows/LaTeXSquiggly.Core/` and
   `chrome/engine/engine.js`, matching the Swift code's structure so the three
   stay comparable line by line.
5. Run `scripts/check-all.sh`. If the site's numbers or examples changed,
   `scripts/make-site.py` has already updated `site/`; commit that too.

### Adding a symbol

A symbol is a table change: add its command and Unicode character name to
`scripts/generate-swift-tables.py`, then follow the steps above. Never add a
symbol by typing the character into a table.

### Changing one platform

Platform code (the macOS app, the Windows tray app, the extension's page
script) can change on its own. Run that platform's checks, and update its
README if the behaviour a user sees has changed.

### Changing the artwork

Edit the source image in `assets/`, then run every image generator listed in
[docs/architecture.md](docs/architecture.md#generated-files) and commit their
output.

## Before you push

```
scripts/check-all.sh
```

It runs everything CI runs: the version check, the Swift build and suite, the
generated-file check, the Windows conformance run (needs the .NET 8 SDK) and
the extension's conformance run (needs Node). CI runs it again on every push
and pull request, and a change is not merged while it is red.

The extension also has a browser test that types into real pages; see
[chrome/README.md](chrome/README.md#tests).

## Commits

- **One logical change per commit**, and the checks pass at every commit.
- **Moves and edits go in separate commits.** Move files in one commit with no
  content changes, so git records exact renames and `git log --follow` keeps
  working, then change their contents in the next.
- **The subject line** is a short imperative sentence saying what the change
  does, with no prefix or trailing full stop: *Commit the extension's icons, and
  stop keeping copies of images*.
- **The body** explains why: the problem, what was wrong before, and anything a
  reviewer would otherwise have to rediscover. Wrap it at 72 columns.
- **Authorship is the committer's.** No `Co-authored-by` or other attribution
  trailers for tools.

## Versions and releases

`VERSION` holds the version, in `MAJOR.MINOR.PATCH`. Everything else reads it,
except two manifests that cannot read a file, which
`scripts/check-version.py` checks instead. The release process is in
[docs/releasing.md](docs/releasing.md). Every release gets an entry in
[CHANGELOG.md](CHANGELOG.md); add to its **Unreleased** section as changes are
merged, not at release time.

## Documentation map

| Question | Where the answer lives |
|---|---|
| What is this and how do I install it? | [README.md](README.md) |
| How is the repository organised, and how do I change it? | this file |
| How do the platforms fit together? | [docs/architecture.md](docs/architecture.md) |
| What does the engine convert, and why does it decide what it does? | [docs/engine.md](docs/engine.md) |
| How does the Mac app work? | [docs/macos.md](docs/macos.md) |
| How does the Windows app work? | [windows/README.md](windows/README.md) |
| How does the extension work? | [chrome/README.md](chrome/README.md) |
| How is the extension published? | [chrome/STORE.md](chrome/STORE.md) |
| How does the website work? | [site/README.md](site/README.md) |
| How is a release made? | [docs/releasing.md](docs/releasing.md) |
| What changed in each version? | [CHANGELOG.md](CHANGELOG.md) |
