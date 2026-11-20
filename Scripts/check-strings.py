#!/usr/bin/env python3
"""Checks localization consistency.

1. en.lproj and ru.lproj contain exactly the same keys.
2. Every string literal passed to tr(...), Text(...), Button(...), Label(...), Toggle(...), Picker(...),
   Section(...) or MetricCard(title:...) in the app has a translation.

Exit status 1 on any problem, so it can run in CI. Usage: Scripts/check-strings.py
"""
import glob
import re
import sys

KEY = re.compile(r'^"((?:[^"\\]|\\.)*)" =', re.M)
CALL = re.compile(r'(?<![A-Za-z])(?:tr|Text|Button|Label|Toggle|Picker|Section|Alert|MetricCard)\(\s*(?:title:\s*)?"([^"\\]*(?:\\.[^"\\]*)*)"')


def keys(lang):
    with open(f"Resources/{lang}.lproj/Localizable.strings", encoding="utf-8") as handle:
        return set(KEY.findall(handle.read()))


def main():
    english, russian = keys("en"), keys("ru")
    problems = []

    for key in sorted(english - russian):
        problems.append(f"missing in ru: {key}")
    for key in sorted(russian - english):
        problems.append(f"missing in en: {key}")

    for path in glob.glob("Sources/MacControl/**/*.swift", recursive=True):
        with open(path, encoding="utf-8") as handle:
            for number, line in enumerate(handle, 1):
                for match in CALL.finditer(line):
                    text = match.group(1)
                    if "\\(" in text or "verbatim" in line[:match.start() + 8]:
                        continue                       # interpolated or verbatim: not a localization key
                    if re.search(r"[A-Za-z]{3}", text) and text not in russian:
                        problems.append(f"{path}:{number}: no translation for \"{text}\"")

    for problem in problems:
        print(problem)
    print(f"{len(english)} keys, {len(problems)} problems")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
