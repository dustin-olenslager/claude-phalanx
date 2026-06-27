# Contributing

## Supported platforms

- **Linux is the primary, tested target.** The installer, hooks, and scripts are
  developed and CI-verified on Linux.
- **macOS / BSD: best-effort, with caveats.** Some scripts assume GNU coreutils
  behavior. Watch for:
  - **GNU `sed`** semantics (in-place `-i` flags, regex extensions) differ from
    BSD `sed` on macOS. Prefer portable constructs or install `gnu-sed` (`gsed`).
  - **Bash-isms** — scripts target Bash, not POSIX `sh`. macOS ships an old Bash
    (3.2); install a current Bash via Homebrew when a feature needs it.
- **Windows** is served by the separate `install.ps1` / `run-work.ps1` path.

## How to test

Run the installer against a throwaway `CLAUDE_DIR` so your real `~/.claude` is
never touched. The installer runs an embedded self-test of the gates and the
verify simulations:

```sh
CLAUDE_DIR="$(mktemp -d)" PHALANX_NO_CRON=1 PHALANX_NO_GUARDS=1 ./install.sh
```

- `PHALANX_NO_CRON=1` — never touch `crontab`.
- `PHALANX_NO_GUARDS=1` — skip the leak-guard git-hook setup.

The self-test exits non-zero on any failure (`==> SELF-TEST FAILED`).

## Shellcheck

All shell scripts are expected to pass `shellcheck`. Run it locally before
opening a PR:

```sh
shellcheck install.sh uninstall.sh hooks/anchors/*.sh scripts/*.sh
```

## CI

CI runs the embedded installer self-test and `shellcheck` on every push and pull
request; both must be green to merge.
