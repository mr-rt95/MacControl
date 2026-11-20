# Contributing

Thanks for helping! Bug reports and sensor data from other Mac models are especially valuable.

## Reporting problems

- Run `build/bin/MacControlProbe --stats --all-keys` (or from the repository: `./build.sh` first) and attach the output
  when a temperature, fan or battery value is missing or wrong. Please mention your Mac model (`sysctl hw.model`) and macOS version.
- For UI problems, a screenshot helps.

## Development

```bash
./build.sh run          # build and launch
./build.sh test         # unit tests (needs Xcode)
Scripts/doctor.sh       # checks the toolchain, SwiftPM, signing
python3 Scripts/check-strings.py   # every UI string must be translated (en + ru)
```

Guidelines:

- Keep `MacControlCore` free of UI. Put pure logic in testable functions and add tests in `Tests/MacControlCoreTests`.
- **Safety first:** anything that deletes or changes files must go through `SafeTrasher` (Trash, preview, undo log) and
  respect `ProtectedPaths`. New destructive features need tests on a temporary folder, never on real user data.
- UI text lives in `Resources/*.lproj/Localizable.strings` (English text is the key); add both English and Russian.
- Code comments in English, user-facing text localized.
