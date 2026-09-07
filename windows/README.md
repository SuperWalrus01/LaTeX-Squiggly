# LaTeX Squiggly for Windows

The same app, on Windows. Type `\alpha`, press space, get a Greek alpha.

## Running it

Copy the exe to the Windows machine and double-click it. That is the whole
installation: one file, no installer, no admin rights. It puts a mark in the
system tray, near the clock.

There are two builds, and they behave identically once running.

| | Size | Needs |
|---|---|---|
| `dist/win-x64/LaTeX Squiggly.exe` | 63 MB | nothing at all |
| `dist/win-x64-needs-dotnet/...exe` | 456 KB | the [.NET 8 Desktop Runtime](https://dotnet.microsoft.com/download/dotnet/8.0) |

Take the big one unless the file size is a problem. It carries its own copy of
.NET, which is why it is large and why it needs nothing installed. The small one
is the same program without that copy, so Windows will tell you what is missing
and where to get it if the runtime is not already there.

Either build runs on an ARM laptop too, through the x64 emulation Windows does
for itself. `./windows/build.sh win-arm64` produces a native one if you want it.

Two things will happen the first time, and neither means anything is wrong.

**Windows will say "Windows protected your PC".** The exe is not code-signed, so
SmartScreen warns about it. Click **More info**, then **Run anyway**. A signing
certificate costs a few hundred pounds a year and is the only thing that removes
this; there is no way around it for an unsigned build.

**Your antivirus may take an interest.** The app installs a low-level keyboard
hook, which is the same mechanism a keylogger uses, so a scanner that judges by
behaviour has a fair reason to look twice. It reads keystrokes, holds at most 64
characters in memory, and discards them the moment a command completes. There is
no networking code anywhere in the project and nothing is ever written to disk
except your settings.

## Trying it

Open Notepad and type `\alpha` followed by a space.

```
\alpha          ->  a Greek alpha
\int_5^6        ->  an integral sign with limits
\frac{1}{2}     ->  a one-half character
\frac{\alpha}{2} ->  a linear fraction, with a notice explaining why
$x^2$           ->  x squared
\vec{v}         ->  nothing, and a notice saying why not
```

The tray menu says what it is doing and why. If it has gone quiet, the menu is
where it tells you which rule it is obeying.

## What is different from the Mac version

The engine is not different. It is generated from the same tables and checked,
fragment by fragment, against the Mac build: see "How this is checked" below.

The parts that touch the operating system had to be rewritten, and three
decisions came out differently.

**No permissions to grant.** macOS needs Accessibility and Input Monitoring
before the app can do anything. Windows asks for neither, so the whole
permission flow is gone. The cost is that the app cannot type into a window
running as administrator, because Windows does not let a normal program send
input to an elevated one. This is the right trade: an app that reads your
keystrokes should ask for the least it can.

**Apps are identified by their executable.** The Mac uses a bundle identifier.
Windows has no equivalent, so `texstudio.exe` is the name a rule matches on,
which is also what you see in Task Manager and what an installer cannot quietly
change.

**Browser tabs are identified by their window title.** The Mac reads the page
URL out of the accessibility tree. There is no cheap, reliable equivalent that
works across every Windows browser, so this port uses the window title, which
every browser sets to the page title. An Overleaf tab still says "Overleaf" in
its title, so it is still recognised. This is the same path the Mac app already
takes for Firefox, and the same trade: a title match can fire on a page that
merely mentions Overleaf, which costs one unconverted command, far less than the
miss it prevents.

One thing is better here. The Mac has to space out its synthetic keystrokes and
sleep between them, which puts about 46 milliseconds of blocked main thread
behind a long replacement. Windows takes the whole replacement as a single
`SendInput` call, queued atomically and in order, so there are no pauses and no
window in which your next keystroke can land in the middle of one.

## What it excludes out of the box

The same rule as the Mac: anywhere LaTeX source is plausibly written, stay
quiet, because an app that corrupts your source is worse than no app at all.

TeX editors (TeXstudio, Texmaker, TeXworks, WinEdt, LyX, TeXnicCenter), code
editors (VS Code, Cursor, Sublime, Notepad++, Vim, Emacs, Visual Studio,
RStudio, the JetBrains IDEs, Obsidian, Typora), every terminal, and Overleaf and
its cousins in any browser.

Anything missed is one click to fix, from **Do not convert in ...** in the tray
menu. Anything you remove stays removed, including across upgrades.

## How this is checked

The Windows app cannot be built or run on the Mac this was written on, so
"looks right" was not going to be good enough. Two things stand in for a machine
to test on.

**The tables are generated, not transcribed.** `latex-squiggly --dump-tables`
prints the tables the Swift engine actually uses at runtime, and
`Tools/generate_csharp_tables.py` turns that into C#. All 202 symbols, 40
superscripts, 32 subscripts, 19 fractions, 33 operators and 49 refusal messages
come from one source. A symbol added to the Mac cannot go missing here.

**The port is diffed against the original.** `Tools/generate_conformance_corpus.py`
asks the Swift engine about 2,030 fragments, covering every symbol, every script
character, every refusal, every fraction shape, the dollar rule, and everything
that must stay silent. `LaTeXSquiggly.Conformance` replays all of them through
the C# engine and checks that every answer is identical: same text, same reason,
same delete count, same decision to stay quiet. The suppression rules, which
have no Swift counterpart to compare against because they were genuinely
rewritten, get 30 checks of their own.

```
PASS  engine       4060 checks over 2030 fragments,
                   every answer identical to the Swift engine
PASS  suppression  30 checks on the Windows rules
      4090 checks passed.
```

`windows/build.sh` runs the whole pipeline and refuses to publish if any of it
disagrees.

What this does **not** cover is the part only a Windows machine can answer:
whether the keyboard hook sees your keystrokes, whether `SendInput` lands the
replacement in the app you are typing into, and whether the tray icon and
windows look right. That is what your laptop is for.

## Building it yourself

From a Mac or Linux box with the .NET 8 SDK:

```
./windows/build.sh              # x64, which also runs on ARM laptops
./windows/build.sh win-arm64    # native ARM64, if you want it
```

From Windows, the same `dotnet publish` line in `build.sh` works unchanged.

## Layout

```
windows/
  LaTeXSquiggly.Core/         no platform dependency, checked against Swift
    Engine/                   the converter: tokenizer, renderer, tables
    Input/                    the buffer, the trigger rules, what counts as a command
    Suppression/              where to stay quiet, and why
  LaTeXSquiggly.App/          everything that touches Win32
    Platform/
      NativeMethods.cs        every P/Invoke, in one place
      KeyboardHook.cs         the hook: buffering, terminators, suppression
      TextReplacer.cs         one SendInput call per replacement
      ForegroundWatcher.cs    which app is in front, and which page
      TrayApplication.cs      the tray icon, the menu, the wiring
      SettingsWindow.cs       switches, the exclusion editor, the symbol table
      NoticeWindow.cs         the transient message above the tray
      Settings.cs             persistence, and open-at-login
      AppIcon.cs              the mark, drawn from the Mac artwork
  LaTeXSquiggly.Conformance/  the proof, runnable anywhere
  build.sh                    the whole pipeline
```
