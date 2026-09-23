# Testing on Windows

Notes for driving this from the Windows machine rather than across a USB stick.

## What to install

**The .NET 8 SDK.** <https://dotnet.microsoft.com/download/dotnet/8.0> — the
SDK, not the runtime. Check it took:

```
dotnet --list-sdks
```

Nothing else is required to build the app. `scripts/build-windows.sh` is macOS-only, but
what it does there that cannot happen here — building the Swift engine,
generating the C# tables from it, generating the icons, recording Swift's answers
to 2,030 fragments — has all been done already and every output is committed. So
this machine has the tables, the icons and the reference file, and needs neither
Swift nor Python.

Optional: **Git**, if you want to commit from here rather than carry changes back.

## Building and running

```powershell
.\windows\build.ps1 -Run      # build and launch, seconds
.\windows\build.ps1 -Check    # run the conformance suite and stop
.\windows\build.ps1           # publish one self-contained .exe, about a minute
```

`-Run` is the loop worth using while chasing a bug: it starts the app straight
out of `bin\` instead of producing 63 MB you do not need. Every path runs the
conformance suite first and refuses to build if the port disagrees with the Swift
engine.

## While testing

The log is the point of all this:

```
%APPDATA%\LaTeXSquiggly\log.txt
```

Its first line names the build, from a literal compiled into the binary rather
than the file's timestamp, which Windows rewrites whenever the file is copied.

To quit a running copy: the tray menu, or Task Manager. Windows will not let a
build overwrite a running `.exe`, so quit before rebuilding.

**If it stops responding, look in Task Manager before killing it.** A hung
process and a dead one are different faults, and Explorer removes the tray icon
of a process that has stopped responding, so a missing icon does not mean the
process has gone.
