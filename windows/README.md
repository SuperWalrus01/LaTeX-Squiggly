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
for itself. `scripts/build-windows.sh win-arm64` produces a native one if you want it.

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

## Removing it, and installing a newer one

There is no installer, so there is nothing to uninstall — but the app is running
while you try to replace it, and Windows will not let you overwrite a running
`.exe`. So the order matters.

1. **Quit it first.** Right-click the mark in the tray, near the clock, and
   choose **Quit LaTeX Squiggly**. If you cannot find the mark, click the arrow
   that shows hidden icons; failing that, Task Manager, find **LaTeX Squiggly**,
   End task.
2. **Delete the old `.exe`.** Wherever you put it. That is the app gone.
3. **Put the new one in the same place** and double-click it.

SmartScreen will warn again about the new file: it is a different file, and it
is still unsigned. **More info**, then **Run anyway**.

Two things deliberately survive this, because losing them is worse than keeping
them.

Your settings and your exclusion list live in `%APPDATA%\LaTeXSquiggly\`
(paste that into the File Explorer address bar). A new version reads them, so
the apps you excluded stay excluded and the ones you removed stay removed.
**Delete that folder only if you want the app to forget everything** and come
back to you like a first run.

If you had **Open at login** ticked, it points at the old path. If the new `.exe`
is in the same place, it keeps working and there is nothing to do. If you moved
it, untick and re-tick **Open at login** in the tray menu. To remove it entirely,
untick it before you quit — or delete the `LaTeX Squiggly` value under
`HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Run`, which is
the only thing this app ever writes outside its own folder.

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

## The thread this app lives or dies by

Worth stating plainly, because it is the difference between this app being
invisible and this app making a laptop feel broken.

Windows delivers a low-level keyboard hook by posting to the message queue of
the thread that installed it and then **waiting for that thread to answer**.
Until it answers, the keystroke has not reached anybody: not the app in front,
not the desktop, not anything. So whichever thread installs the hook is, for as
long as the app runs, part of the path every keystroke on the machine takes.

The first Windows build installed both hooks from the UI thread — the thread
that also lays out the settings window, draws the tray menu, shows a modal
message box and stops for garbage collection. Every one of those things put the
whole machine's input on hold. And Windows drops a hook whose owner takes longer
than `LowLevelHooksTimeout` (300 ms by default) without telling anyone, which is
why it would work for a while and then quietly stop.

So the hooks now live on a thread of their own, created for them, running
nothing else. It has no window, no WinForms message loop, no synchronisation
context, and never touches a file or a control. It runs a bare Win32 pump and
the callbacks, and it talks to the UI by posting, never by waiting. Three
further rules follow from that, and they are the reason for most of what looks
fussy in `Platform/`:

- **Nothing on the hot path allocates.** The key event is read through its
  pointer rather than marshalled; the keyboard-state and character buffers are
  fields, not locals; the exclusion checks are loops rather than LINQ. A
  collection triggered inside a hook callback is a pause in everybody's typing.
- **Nothing on the hot path locks.** The exclusion rules reach the hook as an
  immutable snapshot, replaced wholesale when you change them, so the settings
  window can never be in front of your keyboard. The thread has its own process
  name cache for the same reason.
- **The expensive question is asked rarely.** Working out whether to stay quiet
  needs a process name and, in a browser, a window title. That used to run on
  every keystroke. It is now cached for 200 ms — shorter than any app switch a
  person can perform — invalidated the instant the foreground window changes,
  and always asked again, uncached, in the moment before anything is typed. The
  guarantee that it never converts in TeXstudio is unchanged; only the number of
  times it asks is.

Two things fall out of this for free. The app used to poll every 1.5 seconds to
notice you had changed apps; it now gets told, by `SetWinEventHook`, which is
both instant and one fewer reason for a laptop to wake up. And it used to not
reset its buffer on an app switch at all, so a half-typed command in one window
could finish itself in the next one. It does now.

### There is no mouse hook

The app has to notice a click, because a click puts the caret somewhere the
buffer knows nothing about, and completing a command against a stale buffer
deletes characters you meant to keep. The obvious way is `WH_MOUSE_LL`. It was
the wrong way twice over.

It fires on every mouse **movement**, with no way to filter, so it put this app
in front of every pixel of pointer movement anybody made. And mouse and keyboard
callbacks queue on the same thread, so a flood of the first delays the second,
and a keyboard callback that answers too slowly is one Windows removes without
telling anybody. An attempt to have it both ways, by installing the hook only
while a command was half-typed, meant installing and removing a hook from inside
a hook callback, which is surgery on the hook chain from inside the hook chain.
That is not a clever trade, it is a bad idea with a good excuse.

So the app installs exactly one hook now: the keyboard. What replaces the mouse
hook costs the rest of the machine nothing:

- **A four second buffer lifetime.** A half-typed command with no keystroke for
  four seconds is not a command any more. Longer than anyone takes to type
  `\alpha`, shorter than the pause involved in reaching for the trackpad.
- **`GetAsyncKeyState` on the mouse buttons**, checked on our own thread, and
  only when the buffer holds a backslash or a dollar, which is the only time a
  stale buffer can do harm. Its "pressed since you last asked" bit is shared
  across processes, so another program polling the same button can clear it
  before we see it. It can miss a click; it cannot invent one. The four second
  lifetime is what covers the ones it misses.

### ToUnicodeEx is never called while a keystroke is in flight

The most expensive thing this port got wrong, and the log that found it is worth
keeping.

Working out what a keystroke means under the current layout is `ToUnicodeEx`, and
the obvious place to call it is inside the keyboard hook, where the keystroke is.
Three separate runs ended on the line written immediately before that call and
never reached the line written immediately after it. The hook thread went into
`ToUnicodeEx` and did not come out.

That is not a surprising place to deadlock. While a low-level hook is pending the
system holds the input path waiting for it to answer, and `ToUnicodeEx` reaches
into the keyboard layout that the same input path is using: a lock taken in one
order by us and the other order by Windows. The consequence is as bad as it gets
for an app that lives in the input path. A hook that never returns does not stop
this app, it stops **every keystroke on the machine**, and a few seconds later the
UI thread blocks behind the same lock and the whole process is gone from the tray.
Every "the laptop lags and then it disappears" report was this.

So the call happens where it is safe: on the pump thread, at startup and whenever
the layout changes, 256 virtual keys against 8 combinations of Shift, AltGr and
Caps Lock. `Platform/KeyboardLayoutTable.cs` holds the answers. What is left on
the path every keystroke takes is an array index: no syscall, no lock, and
nothing that can fail to return.

The general rule, which the mouse hook broke in its own way and this broke in a
worse one: **inside a low-level hook callback, do as little as can possibly be
done, and never anything that takes a lock the input path might already hold.**

### Injected input is never read

The app types its replacements with `SendInput`, and those keystrokes come
straight back round through its own keyboard hook. Recognising them was
originally done with `dwExtraInfo`, a field the sender stamps and the hook reads.

That is not enough, and the way it fails is instructive. A `KEYEVENTF_UNICODE`
character arrives at the hook as `VK_PACKET`, and `ToUnicodeEx` on a `VK_PACKET`
does not merely return nothing useful, it **consumes the packet**: the character
is translated for us and never delivered to the app in front. So a marker that
does not survive the round trip turns into a command whose source is deleted and
whose replacement never appears, which is a corrupted document rather than a
missing feature.

Three checks now, not one. `dwExtraInfo` still identifies our own events, but
`LLKHF_INJECTED` is set by the system rather than by the sender and cannot be
lost on the way round, and `VK_PACKET` is refused outright whoever sent it. The
cost is that text injected by other automation is not converted, which is the
right answer anyway: this app converts what a person types.

### If it still misbehaves

**Read `%APPDATA%\LaTeXSquiggly\log.txt`.** The app writes to it on purpose and
without being asked. Every run opens with a `--- started` line carrying the
version and the architecture, says whether the hook installed, writes a
heartbeat every minute, and closes with `exiting`. A run that stops without an
`exiting` line ended because the process died; a `the input pump ended` line
means the hook thread stopped; a `conversion switched off` line means something
turned it off. Those are three different faults that look identical from the
outside, and this is what tells them apart.

**Tray menu → Copy diagnostics** puts the same summary on the clipboard, plus
which executable is in front. No window titles, no page titles, nothing you have
typed.

The number that matters is the slowest callback. Windows drops a hook at 300 ms.
Anything over 10 ms is already far outside what this code should cost, and the
app writes a line to `%APPDATA%\LaTeXSquiggly\log.txt` when it sees one, at most
once every ten seconds.

**On an ARM laptop, use the ARM build.** `dist/win-arm64/` is native;
`dist/win-x64/` runs under Windows' x64 emulation, and emulated code inside a
low-level hook callback is several times slower than native. That is fine for
most software and is not fine here, because this particular code runs in front
of the keyboard. `scripts/build-windows.sh win-arm64` produces it.

One failure is still silent: a hook Windows has removed looks exactly like an
app that is working fine, except that nothing converts. If that happens, switch
conversion off and on again from the tray menu, which installs the hook afresh,
and send the log. Detecting it automatically is an open task; see
[Working on it](#working-on-it).

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

The Windows app can be built on the Mac this was written on, but not run, so
"looks right" was not going to be good enough. Two things stand in for a machine
to test on.

**The tables are generated, not transcribed.** `latex-squiggly --dump-tables`
prints the tables the Swift engine actually uses at runtime, and
`scripts/generate-csharp-tables.py` turns that into C#. All 202 symbols, 40
superscripts, 32 subscripts, 19 fractions, 33 operators and 49 refusal messages
come from one source. A symbol added to the Mac cannot go missing here.

**The port is diffed against the original.** `scripts/generate-conformance-reference.py`
asks the Swift engine about 2,030 fragments, covering every symbol, every script
character, every refusal, every fraction shape, the dollar rule, and everything
that must stay silent. `LaTeXSquiggly.Conformance` replays all of them through
the C# engine and checks that every answer is identical: same text, same reason,
same delete count, same decision to stay quiet. The suppression rules, which
have no Swift counterpart to compare against because they were genuinely
rewritten, get 38 checks of their own, including repairing a damaged settings file.

```
PASS  engine       4060 checks over 2030 fragments,
                   every answer identical to the Swift engine
PASS  suppression  38 checks on the Windows rules
      4098 checks passed.
```

`scripts/build-windows.sh` runs the whole pipeline and refuses to publish if any of it
disagrees.

What this does **not** cover is the part only a Windows machine can answer:
whether the keyboard hook sees your keystrokes, whether `SendInput` lands the
replacement in the app you are typing into, and whether the tray icon and
windows look right. That is what your laptop is for.

## Building it yourself

On Windows, with the .NET 8 SDK, from the repository root:

```powershell
.\windows\build.ps1 -Run      # check the port, then build and launch it
.\windows\build.ps1 -Check    # run the conformance suite and stop
.\windows\build.ps1           # check the port, then publish one .exe
```

On a Mac, the whole pipeline, which also regenerates the tables and icons from
the Swift engine first:

```
scripts/build-windows.sh              # x64, which also runs on ARM laptops
scripts/build-windows.sh win-arm64    # native ARM64, if you want it
```

Either way the executable lands in `windows/dist/<runtime>/`.

## Working on it

Anyone can work on the Windows app from a Windows machine with only the .NET 8
SDK: everything generated from the Swift engine is committed.
[DEVELOPING.md](DEVELOPING.md) is the guide to setting up, changing and
testing it.

Where a change goes:

| To change | Edit |
|---|---|
| what converts, and how | not here: the engine is changed in Swift first and ported, as [CONTRIBUTING.md](../CONTRIBUTING.md#changing-the-engine) describes |
| which apps and sites are excluded by default | `LaTeXSquiggly.Core/Suppression/DefaultExclusions.cs`, then the matching Swift and Chrome lists |
| how keystrokes are read, or when the buffer is forgotten | `LaTeXSquiggly.App/Platform/InputThread.cs` |
| how the replacement is typed | `LaTeXSquiggly.App/Platform/TextReplacer.cs` |
| the tray icon and menu | `LaTeXSquiggly.App/Platform/TrayApplication.cs` |
| the settings window | `LaTeXSquiggly.App/Platform/SettingsWindow.cs` |

Anything on the input thread follows the rules in
[The thread this app lives or dies by](#the-thread-this-app-lives-or-dies-by):
no allocation, no locks, no waiting on the UI, and nothing inside the hook
callback that could fail to return. A change there is worth testing with the
log open, watching the slowest callback in its heartbeat line.

Before a pull request, run `.\windows\build.ps1 -Check` (or
`scripts/check-all.sh` on a Mac), and try the change by hand on a real Windows
machine: the checks prove the engine, not the keyboard hook.

Open tasks, each a good place to start:

- **Notice a hook Windows has removed.** The input thread could compare
  `GetLastInputInfo` with the last keystroke its hook saw, and reinstall the
  hook when the system has had input the hook never received.
- **A native ARM64 release.** It builds (`scripts/build-windows.sh win-arm64`)
  but has not been tested on an ARM laptop.
- **Typing in elevated windows.** Windows does not let a normal program send
  input to one running as administrator. The app says so; it could say so
  before the user types, not after.

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
      InputThread.cs          the keyboard hook and the thread it lives on
      KeyboardLayoutTable.cs  what each key types, worked out off the hook
      TextReplacer.cs         one SendInput call per replacement
      ForegroundWatcher.cs    which app is in front, and which page
      TrayApplication.cs      the tray icon, the menu, the wiring
      SettingsWindow.cs       switches, the exclusion editor, the symbol table
      NoticeWindow.cs         the transient message above the tray
      Settings.cs             persistence, and open-at-login
      Diagnostics.cs          the log, for the failures a user cannot see
      AppIcon.cs              the mark, drawn from the Mac artwork
  LaTeXSquiggly.Conformance/  the proof, runnable anywhere
  build.ps1                   build, check and run it on Windows
  DEVELOPING.md               how to change and test it on Windows
```

The full pipeline, which needs a Mac, is `scripts/build-windows.sh`.
