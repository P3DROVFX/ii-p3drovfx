# health_watch

The helper behind the System Health app (`modules/ii/health/`, `services/HealthService.qml`).

It watches the things that break quietly on a Linux desktop and reports them to the
shell as one JSON object per line:

- failed system and user units, restart loops and failed app launches (systemd over D-Bus)
- crashes recorded by systemd-coredump, grouped by program, with the stack trace and
  the package update that came before them
- new journal error groups, with known noise (seen on 3 of the last 5 boots) kept quiet
- drive SMART from UDisks2, filesystems filling up, memory/IO/CPU pressure, CPU
  throttling, an unsynchronised clock
- firmware upgrades and the Host Security ID from fwupd
- update chores: a kernel replaced under the running one, `.pacnew` files, orphans,
  programs still using deleted libraries

Everything is read as your user, without root. Restarting a system unit or starting a
drive self-test goes through systemd's and UDisks' own polkit check. Core dumps are
never opened by the helper, only checked for readability, and nothing it answers can
contain a dump's bytes.

The message format is [PROTOCOL.md](PROTOCOL.md).

## Rebuilding from source

The helper ships as source and is compiled on the machine that runs it. Nothing
compiled is committed: the binary, `target/` and `Cargo.lock` are gitignored.

```bash
yay -S --needed rust
~/.config/quickshell/ii/scripts/rust-helpers.sh build health_watch
```

`rust-helpers.sh` installs the binary at `scripts/health/health_watch` with a rename (so
a rebuild over the running helper is safe) and writes a stamp of the sources it was
built from, which the updater uses to tell when the helper has fallen behind.
`rust-helpers.sh status health_watch` prints `ok`, `stale`, `unknown` or `missing`.

Run it by hand to see what it sees:

```bash
scripts/health/health_watch --once --state-dir /tmp/health-test | jq -c .t
```

Unit tests: `cargo test` inside `health_watch_src/`.

Optional system packages: `fwupd` (firmware and HSI) and `udisks2` (drive SMART).
Without them the matching sections stay hidden.

## Reading crash dumps of system programs

Crashes of programs that run as root (fprintd, for example) are shown from the
journal, which members of `wheel`, `adm` or `systemd-journal` can read. Their dump
files stay readable by root only. `crash-access.sh` lets one account read them, so
`coredumpctl gdb` works without sudo:

```bash
sudo crash-access.sh grant  "$USER"   # or through pkexec from the app's Settings
sudo crash-access.sh revoke "$USER"
crash-access.sh status "$USER"        # granted | denied, no root needed
```

`grant` writes `/etc/tmpfiles.d/ii-system-health.conf`:

```
A+ /var/lib/systemd/coredump - - - - u:<user>:rX,d:u:<user>:r
```

and applies it at once; systemd-tmpfiles re-applies it at every boot. `revoke` deletes
that file and removes the user's ACL entries from the directory and every dump in it.

**What this grants.** A core dump is a full copy of a program's memory at the moment
it crashed. A root program's dump can hold passwords, keys or fingerprint templates.
The grant covers every root dump systemd keeps, now and in the future (systemd deletes
them after 3 days, or sooner when they pass 10 % of the disk). It is per user, never
for a group. The dumps never leave the computer: the helper reports only the journal's
stack trace text, and the assistant can only ever see that text, redacted.
