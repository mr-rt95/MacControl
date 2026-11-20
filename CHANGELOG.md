# Changelog

All notable changes to MacControl are listed here. The format follows [Keep a Changelog](https://keepachangelog.com/).

## [0.1.0] — 2026-11-21

First public release.

### Added
- **Monitoring:** CPU per core, memory, disk, network, SMC temperatures and fans, menu bar item.
- **Diagnostics in plain language:** overheating, throttling (including `kernel_task`), CPU overload, memory pressure, low disk space, cooling problems, heavy window drawing, SSD (SMART and NVMe wear) and battery wear. Every conclusion shows its data.
- **History** (hour / day / week) and a **journal** of slowdowns.
- **Quiet / Performance modes** (process priority only, nothing is terminated).
- **Cleanup**, **process quit**, **app removal with leftovers**, **startup items and services**, **tuning with restore**, **large files and duplicates**, with a protected-path list, Trash-only deletion and an undo log.
- **Notifications** with anti-spam, **report export** (Markdown/HTML), launch at login.
- **Permissions screen** and an optional **administrator helper** (XPC daemon, signer-pinned, fixed whitelist of actions).
- Russian and English interface.

### Known limitations
- Intel Macs only; developed and tested on a MacBook Pro 14,1 with macOS 13.7.
- The build is signed but not notarized: macOS asks to confirm the first launch.
