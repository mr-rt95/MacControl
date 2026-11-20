# Security

## Reporting a vulnerability

Please report security problems privately through GitHub: **Security ▸ Report a vulnerability** on this repository
(a private advisory). Do not open a public issue for them. You will get an answer as soon as possible.

## Scope and design

MacControl runs as a normal user app. The optional **administrator helper** (`MacControlHelper`, a launchd daemon
installed through `SMAppService`) is the security-sensitive part. Its design:

- exposes a short fixed list of operations over XPC; it never runs arbitrary commands or paths;
- re-validates every request itself (name formats, allowed folders, protected processes) and does not trust the app;
- accepts connections only from a client signed by the same signer (Team ID or pinned certificate hash); a build
  without a signer refuses every connection;
- moves removed system files into a root-owned quarantine instead of deleting them;
- refuses protected items: `/System`, Apple labels and bundle identifiers, symlinks leaving `/Library`, pid 1, `kernel_task`, …

Details and the list of what is verified are in [docs/HELPER.md](docs/HELPER.md). The app does not use the network.
