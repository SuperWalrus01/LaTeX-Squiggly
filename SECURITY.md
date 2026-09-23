# Security

LaTeX Squiggly reads what you type in order to convert it, so a flaw in it can
matter more than in most small tools. Reports are taken seriously.

## Reporting a problem

Report security and privacy problems privately, through GitHub's
[private vulnerability reporting](https://github.com/SuperWalrus01/LaTeX-Squiggly/security/advisories/new),
not as a public issue. Include the platform, the version, and the steps to
reproduce it. You will get a reply within a week, and a fix is released as soon
as it is ready, with credit to you in the changelog if you want it.

Examples of what to report:

- anything typed being kept longer than needed to recognise a command, written
  to disk, logged or sent anywhere;
- text being changed in a place it should have been left alone, in a way that
  could be triggered on purpose by a web page or another app;
- the extension reading more of a page than the text field being typed in.

## What is supported

Only the latest release of each platform receives fixes.

## What the software does with your data

The short version: the last 64 characters typed are held in memory to
recognise a command and cleared on every click, arrow key and focus change;
only settings are stored; nothing makes a network request. The full statement
is the [privacy policy](https://superwalrus01.github.io/LaTeX-Squiggly/privacy.html).
