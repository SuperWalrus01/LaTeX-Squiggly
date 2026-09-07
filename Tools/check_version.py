#!/usr/bin/env python3
"""
Asserts that every place carrying a version number agrees with VERSION.

The version used to be a default inside Scripts/make-app.sh, which meant a
release built without setting an environment variable was stamped with whatever
the last person had typed there. That is the kind of mistake nothing catches:
the app runs, the disk image mounts, and only the About box is wrong.

Most places now read VERSION directly. The two that cannot are checked here
instead, because a manifest is a source file worth being able to read.

Run:  python3 Tools/check_version.py
"""

import os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def read(*parts):
    with open(os.path.join(ROOT, *parts), encoding="utf-8") as handle:
        return handle.read()


def main():
    version = read("VERSION").strip()
    if not re.fullmatch(r"\d+\.\d+\.\d+", version):
        sys.exit(f"VERSION is {version!r}, which is not a three-part version")

    problems = []

    # The Windows assembly manifest wants a four-part version, and cannot read
    # a file, so it is the one literal left.
    manifest = read("windows", "LaTeXSquiggly.App", "app.manifest")
    found = re.search(r'assemblyIdentity version="([\d.]+)"', manifest)
    if not found:
        problems.append("app.manifest has no assemblyIdentity version")
    elif found.group(1) != version + ".0":
        problems.append(
            f"app.manifest says {found.group(1)}, expected {version}.0")

    # Nothing should carry a hardcoded version any more. This catches one being
    # reintroduced, which is exactly how the last one survived.
    for relative in ["Scripts/make-app.sh", "Scripts/install.sh"]:
        path = os.path.join(ROOT, relative)
        if not os.path.exists(path):
            continue
        for number, line in enumerate(read(relative).splitlines(), 1):
            if line.lstrip().startswith("#"):
                continue
            if re.search(r"VERSION\s*=.*\d+\.\d+\.\d+", line):
                problems.append(
                    f"{relative}:{number} hardcodes a version; read VERSION instead")

    if problems:
        for problem in problems:
            print("  " + problem, file=sys.stderr)
        sys.exit(f"version mismatch: VERSION says {version}")

    print(f"version {version}, consistent everywhere")


if __name__ == "__main__":
    main()
