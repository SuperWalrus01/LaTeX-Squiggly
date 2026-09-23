# Developing the Windows app

How to set up a Windows machine, change the Windows app, and test the change
before sending it. For what the app does and why it is built the way it is,
read [README.md](README.md) first, particularly
[The thread this app lives or dies by](README.md#the-thread-this-app-lives-or-dies-by).
The rules for the repository as a whole are in
[CONTRIBUTING.md](../CONTRIBUTING.md).

## 1. Set up

You need Windows 10 or 11 and two things:

1. **The .NET 8 SDK**, from <https://dotnet.microsoft.com/download/dotnet/8.0>.
   The SDK, not the runtime. Check it installed:

   ```powershell
   dotnet --list-sdks
   ```

2. **Git**, to clone the repository and commit your change.

Then, in PowerShell:

```powershell
git clone https://github.com/SuperWalrus01/LaTeX-Squiggly.git
cd LaTeX-Squiggly
.\windows\build.ps1 -Check
```

`-Check` builds the engine and runs the conformance suite. It should end with
`4098 checks passed.` If it does, the machine is ready.

Nothing else is needed. Everything the Windows app is generated from (the
tables, the icons and the conformance reference) comes from the Swift engine
on a Mac, and all of it is committed, so this machine needs neither Swift nor
Python. If PowerShell refuses to run the script, allow local scripts for your
account once:

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

## 2. The loop

Run everything from the repository root.

```powershell
.\windows\build.ps1 -Run      # check the port, then build and launch it
.\windows\build.ps1 -Check    # run the conformance suite and stop
.\windows\build.ps1           # check the port, then publish one .exe
```

`-Run` is the loop to use while working: it builds in seconds and starts the
app straight from `bin\`. Publishing takes about a minute and produces a 63 MB
self-contained executable in `windows\dist\win-x64\`, which you only need to
hand a build to someone else. Every path runs the conformance suite first and
refuses to build if the port disagrees with the Swift engine.

**Quit the running copy before rebuilding.** Only one copy runs at a time, and
Windows will not let a build overwrite a running `.exe`. Quit from the tray menu
(the LS mark near the clock), or end **LaTeX Squiggly** in Task Manager.

**Keep the log open while you work.** Everything the app does is written to

```
%APPDATA%\LaTeXSquiggly\log.txt
```

Open it in an editor that reloads on change, or follow it in a second
PowerShell window:

```powershell
Get-Content "$env:APPDATA\LaTeXSquiggly\log.txt" -Wait -Tail 20
```

Settings are in `settings.json` in the same folder. Delete the folder to start
again as a first run.

## 3. How it is put together

```
windows/
  LaTeXSquiggly.Core/          the engine, with no Windows dependency
  LaTeXSquiggly.App/           the tray app: everything that touches Win32
    Platform/InputThread.cs    the keyboard hook, on a thread of its own
    Platform/...               the rest; README.md lists each file
  LaTeXSquiggly.Conformance/   checks Core against the Swift engine
  build.ps1                    build, check, run and publish on Windows
```

Two threads matter. The **input thread** owns the keyboard hook, the typing
buffer and the typing of replacements. Every keystroke on the machine waits for
it, so it never allocates, never locks and never waits for anything. The **UI
thread** owns the tray icon, the menu, the settings window and the notices. The
input thread reaches the UI only by posting to it, and the UI reaches the input
thread only by posting a message or swapping in a new snapshot of the rules.

## 4. Making a change

### Where it goes

| To change | Edit |
|---|---|
| what converts, and how | not here: change the Swift engine first, then port it, as [CONTRIBUTING.md](../CONTRIBUTING.md#changing-the-engine) describes |
| the default excluded apps and sites | `LaTeXSquiggly.Core/Suppression/DefaultExclusions.cs`, and the matching Swift and Chrome lists |
| how exclusions are matched | `LaTeXSquiggly.Core/Suppression/ExclusionList.cs` |
| how keystrokes are read, or when the buffer is forgotten | `LaTeXSquiggly.App/Platform/InputThread.cs` |
| what a key types under a keyboard layout | `LaTeXSquiggly.App/Platform/KeyboardLayoutTable.cs` |
| how the replacement is typed | `LaTeXSquiggly.App/Platform/TextReplacer.cs` |
| which app and page are in front | `LaTeXSquiggly.App/Platform/ForegroundWatcher.cs` |
| the tray icon and menu | `LaTeXSquiggly.App/Platform/TrayApplication.cs` |
| the settings window | `LaTeXSquiggly.App/Platform/SettingsWindow.cs` |
| the notice above the tray | `LaTeXSquiggly.App/Platform/NoticeWindow.cs` |
| what is written to the log | `LaTeXSquiggly.App/Platform/Diagnostics.cs` |
| a Win32 function or constant | `LaTeXSquiggly.App/Platform/NativeMethods.cs`, the only place they are declared |

Files under `LaTeXSquiggly.Core/Engine/` ending in `.g.cs` are generated from
the Swift engine. Never edit them; a check fails if you do.

### Rules for the input thread

Anything that runs on the input thread, which is most of `InputThread.cs` and
everything it calls, follows these. They exist because the thread sits in front
of every keystroke on the machine, and Windows silently removes a keyboard hook
that takes longer than 300 ms to answer.

- **Do not allocate on a keystroke.** No LINQ, no string building, no new
  arrays. Keep buffers as fields and reuse them.
- **Do not lock, and do not wait.** Not for the UI, not for a file, not for
  another thread. To tell the UI something, post it.
- **Do as little as possible inside the hook callback.** Anything slow, or
  anything that could fail to return, happens after the callback has answered.
  `ToUnicodeEx` called inside the hook is what hung the first release; see
  README.md.
- **Never let an exception escape a Windows callback.** Catch it, log it, and
  pass the keystroke through untouched.
- **Never log what was typed.** Counts, key codes of control keys and process
  names are fine; characters are not.

### Style

The same as the rest of the repository: 4-space indentation, and comments that
explain why rather than what. Match the code around you. Win32 names keep their
Win32 spelling (`WM_KEYDOWN`, `KBDLLHOOKSTRUCT`) so they can be looked up.

## 5. Testing

### The automatic check

```powershell
.\windows\build.ps1 -Check
```

It replays 2,030 fragments through the engine and requires the same answer the
Swift engine gave for each, and runs 38 checks on the exclusion rules. It proves
the engine. It cannot prove the keyboard hook, the typing or the tray, which is
what the next part is for.

### By hand

Run `.\windows\build.ps1 -Run`, open **Notepad**, and work through this list.
"Space" means pressing the space bar after the text. A change to
`InputThread.cs`, `KeyboardLayoutTable.cs` or `TextReplacer.cs` needs the whole
list; a change elsewhere needs the rows that touch it, plus the first three.

**Converting**

| Type in Notepad | Expected |
|---|---|
| `\alpha` space | `α ` |
| `\alpha\beta` space | `αβ ` |
| `\beta` Tab | `β` followed by a tab |
| `$x^2$` space | `x² ` |
| `\frac{1}{2}` space | `½ `, with no notice |
| `\frac{x+1}{2}` space | `(x+1)∕2 `, and a notice saying it was written on one line |
| `\vec{v}` space | left exactly as typed, and a notice saying why |
| `\E` space | `𝔼 `, a character outside the Basic Multilingual Plane, sent as a surrogate pair |
| `\R` space | `ℝ ` |

**Staying quiet**

| Do this | Expected |
|---|---|
| `C:\Users` space | nothing changes, and no notice |
| `\alpha` Enter | nothing changes: Return never converts |
| `\alphx`, Backspace, `a`, space | `α `: Backspace is followed |
| `\alp`, click somewhere else in the text, `ha` space | nothing converts |
| `\alp`, wait five seconds, `ha` space | nothing converts: the buffer expires after four |
| `\alp`, Left arrow, Right arrow, `ha` space | nothing converts |
| `\alp`, switch to another window and back, `ha` space | nothing converts |
| Ctrl+C, then `\alpha` space | `α `: a shortcut forgets the buffer but is not typing |

**Exclusions**

| Do this | Expected |
|---|---|
| `\alpha` space in Notepad++ or VS Code, if installed | nothing converts, and the tray icon turns grey |
| In a browser, open overleaf.com and type `\alpha` space in any text field | nothing converts |
| With Notepad in front, tray menu → **Do not convert in Notepad**, then `\alpha` space | nothing converts; untick it again and it converts |
| Tray menu → untick **Convert LaTeX as I type**, then `\alpha` space | nothing converts; tick it and it converts |

**Keyboards**

| Do this | Expected |
|---|---|
| Caps Lock on, type `$x^2$` (it appears as `$X^2$`), space | `X² ` |
| Add a German keyboard (Settings → Time & language → Language & region), switch to it with Win+Space, wait five seconds, type `\alpha` space, where `\` is AltGr+ß | `α ` |
| Same German keyboard: type `ä`, then `^` followed by `a` | `ä` and `â`, unchanged: ordinary keys and dead keys still work |

**Elevated windows**

| Do this | Expected |
|---|---|
| Right-click Notepad → **Run as administrator**, type `\alpha` space | either nothing happens, or a notice that Windows would not let the app type there. The text must never be half replaced. |

**The rest of the app**

| Do this | Expected |
|---|---|
| Double-click the tray icon | the settings window opens; the Symbols tab searches |
| Tray menu → untick **Show notices**, then `\vec{v}` space | no notice |
| Tray menu → **Copy diagnostics**, paste into Notepad | version, architecture, hook state, the executable in front, the log path; no window titles and nothing typed |
| Quit from the tray menu, start again | the log shows `exiting`, then a new `--- started` line |
| End the process in Task Manager, start again | the log shows `!!! the previous run was killed` |
| Type normally for a minute or two | the next heartbeat line's `slowest callback` is well under 10 ms, and there is no `a keyboard callback took` line |

If you have an ARM laptop, run the list on a `win-arm64` build as well. Publish
it with `.\windows\build.ps1 -Rid win-arm64`.

### Reading the log

| Line | Means |
|---|---|
| `--- started, version …` | a run began; the version and architecture follow |
| `keyboard hook installed` | the input thread is working |
| `hook installed, N key events, N conversions, slowest callback …` | the heartbeat, once a minute |
| `typing: N deletes, N chars` then `typed` | a replacement went through |
| `SendInput refused` | Windows would not accept the typing, usually an elevated window |
| `a keyboard callback took N ms` | a keystroke was slow to answer; worth investigating above 10 ms |
| `### SomeException: …` | an exception was thrown somewhere, even if it was caught |
| `conversion switched off` | the user, or something else, turned it off |
| `the input pump ended` | the input thread stopped: conversion has stopped |
| `!!! the previous run was killed` | the last run died without reaching `exiting` |
| `exiting` | a clean exit |

A crash also writes the full exception to `crash.log` in the same folder.

## 6. When something goes wrong

- **It closes as soon as it starts.** Look in `%APPDATA%\LaTeXSquiggly\` for
  `crash.log`, and at the end of `log.txt` for a `start-up failed` or
  `could not open the single-instance mutex` line. Then check the list in
  section 7, which covers every cause found so far. If there is no log folder
  at all, the app died before it could write one, which points at .NET itself:
  try the self-contained build rather than the small one.
- **It stops converting and the log is quiet.** Windows may have removed the
  hook without saying so. Switch conversion off and on from the tray menu, which
  installs it again. Detecting this automatically is an open task in README.md.
- **Typing lags.** Look at `slowest callback` in the heartbeat. Something on the
  input thread is doing too much; see the rules in section 4.
- **It stops responding.** Look in Task Manager before ending it: a hung process
  and a dead one are different faults, and Explorer removes the tray icon of a
  process that has stopped responding, so a missing icon does not mean it has
  gone. Send the end of the log with the report.
- **SmartScreen blocks a published build.** The executable is not code-signed:
  **More info**, then **Run anyway**. `-Run` builds are not affected.

## 7. Known and suspected bugs

Reported: the latest Windows build closed immediately after it was opened.
It could not be reproduced where these fixes were written, because that was a
Mac, so this list is every cause found by reading the start-up path, ranked by
how well it fits that report. Each fix is in the code, and each needs
confirming on a real Windows machine, using the step in its last column. When
you confirm or rule one out, update its status here.

**Fixed, waiting for confirmation on Windows**

| # | Symptom | Cause | Fix | How to confirm |
|---|---|---|---|---|
| 1 | Vanishes at launch with no message and no log line | `Main` created its single-instance mutex before it registered any error handler. Opening the mutex throws when another copy created it with different rights, such as a copy running as administrator, and the exception ended the process silently. | Error handlers are registered first; a mutex failure shows a message saying what to do. | Run a copy as administrator, then start a normal copy: it must explain, not vanish. |
| 2 | Closes at launch, sometimes with a generic error | Anything that threw while the tray app was being built happened before the message loop, where only the last-resort handler could see it. | Start-up is wrapped: the failure is written to `log.txt` as `start-up failed` and to `crash.log`, and explained in a message. | The log names the failure instead of ending mid-start. |
| 3 | Closes at launch after `settings.json` was edited or damaged | JSON can say `null` where the code expects a list. The file loaded without complaint, and the tray app then threw copying the rules at start-up. | `ExclusionList.Repair()` runs on every load: null lists become empty, and null or nameless entries are dropped. Reproduced and covered by 8 checks in the conformance suite. | Put `"TitleFragments": null` in a site in `settings.json`: it must start. |
| 4 | "LaTeX Squiggly hit an error" after clicking **Convert LaTeX as I type** or **Do not convert in …** | Both rebuilt the menu from inside their own Click handler, and the rebuild disposes the item being clicked while WinForms is still using it. | The rebuild is posted to run after the click has finished. | Click both items several times: no error. |
| 5 | Stops converting soon after starting, with nothing on screen | Log lines were written on the input thread, including every first-chance exception and the lines around each replacement. A slow disk, or antivirus scanning the new log file, can hold that thread past the 300 ms after which Windows removes the keyboard hook. | Everything the input thread logs is written from the thread pool; the exception logger never waits on the disk and cannot call itself. | Heartbeat lines keep coming, and `slowest callback` stays under 10 ms on first launch. |
| 6 | Stops converting, with the tray icon still there | If the input thread failed, its hook stayed installed on a thread that no longer answered, and nothing told the user. | The hook is removed first, the failure is logged, and a notice says to switch conversion off and on. | Hard to trigger by hand; the log would show `the input thread died`. |
| 7 | Later errors about a disposed icon, only if the artwork is missing | The fallback returned Windows' shared application icon, which was then disposed. | The fallback is a copy. | Only reachable with a broken build. |

**Not fixed: behaviour to know about**

| # | Symptom | Cause | Status |
|---|---|---|---|
| 8 | Starting it says "already running", but there is no tray icon | An earlier copy hung. Explorer removes the tray icon of a process that has stopped responding, but the process still holds the single-instance mutex. | The message now says to end it in Task Manager. The hang that caused it is the one this build fixes. |
| 9 | Stops converting and the log is quiet | Windows removed the hook without saying so. | Open task, in README.md: detect it and reinstall. Switching conversion off and on is the workaround. |
| 10 | A command typed in the first seconds after launch, or after switching keyboard layout, does not convert | The keyboard layout table is built in the background, within four seconds. Until it is ready, keys are not recorded, which is the safe way to be wrong. | By design. |
| 11 | Possibly, a character typed very fast after the space lands before the replacement | The replacement is typed just after the hook answers, and a keystroke arriving in that instant could be handled first. | Suspected, not seen. It would look like the command converting but the character typed right after the space being lost or appearing before the symbol. |
| 12 | Typing lags on an ARM laptop | The x64 build runs under emulation, which is several times slower inside the hook. | Use the ARM64 build; not yet tested on ARM. |
| 13 | Nothing converts in a window running as administrator | Windows does not let a normal program send input to an elevated one. | By design; the app says so. |

When you report a start-up failure, include `crash.log`, the end of
`log.txt`, and the Windows version and architecture.

## 8. Sending the change

1. Run `.\windows\build.ps1 -Check`; it must pass.
2. Work through the manual test list for what you changed.
3. Commit following [CONTRIBUTING.md](../CONTRIBUTING.md#commits): one logical
   change per commit, a short imperative subject, and a body explaining why.
4. Open a pull request. Say which Windows version, architecture and keyboard
   layout you tested on and which rows of the test list you ran, and paste the
   relevant lines of the log if the change is about behaviour.

CI checks the engine and every other platform on each pull request, but it
cannot run the Windows app. Your manual test is the only test the keyboard hook
gets, so say what you did.
