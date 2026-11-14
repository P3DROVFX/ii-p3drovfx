# quickshell-build

Builds Quickshell with two startup patches and installs it as a native package,
`quickshell-ii-git`, in place of the distribution's `quickshell` / `quickshell-git`.

| | stock Quickshell | quickshell-ii-git |
|---|---|---|
| launch → "Configuration Loaded" | ~6–7 s | ~1 s |
| launch → bar on screen | ~5–9 s | ~1.9 s |

## The patches

| Patch | What it fixes |
|---|---|
| `0001-scanner-dedupe.patch` | The QML scanner checked "already scanned?" with `QVector<QDir>::contains`, and `QDir::operator==` resolves both real paths on every comparison: imports × directories `realpath` calls (~4 million for this config). Directories are now keyed by their canonical path once. The scanner's output is byte-identical. |
| `0002-file-vfs-disk-cache.patch` | The config is served through a `qs:` URL scheme, which Qt's QML disk cache refuses ("File has to be a local file"), so every file is recompiled on every start. The config is now mirrored as symlinks (plus the synthesized `qmldir` files) under the shell's runtime VFS directory and loaded from `file://`, so the cache works. `QS_NO_FILE_VFS=1` turns it off. |

Both apply to upstream Quickshell at the commit in `revision`.

## Usage

```bash
./qs-build.sh install    # build and install quickshell-ii-git (asks first)
./qs-build.sh rebuild    # the same, even when current — e.g. after a Qt update
./qs-build.sh restore    # put the distribution's quickshell-git back
./qs-build.sh status     # what is installed, patched or not, Qt match
```

`-y` answers every question. The setup script does the same through
`setup-ii-p3drovfx.sh quickshell [install|rebuild|restore|status]`, and `install`
runs it after the base dotfiles.

| Distribution | How |
|---|---|
| Arch and derivatives (CachyOS, EndeavourOS…) | Generates a PKGBUILD, `makepkg -s`, `pacman -U`. Run as your user. Qt packages the replaced package had pulled in are marked explicit so they are not orphaned. |
| Fedora | Generates a spec, `rpmbuild -bb`, `dnf install --allowerasing`. Drops the base install's `versionlock` on `quickshell-git`. |
| Anything else | Exits with status 3; apply `patches/` to the commit in `revision` and build it yourself. |

The crash handler (Quickshell restarts itself after a crash) needs `cpptrace`. Arch
has it in `extra`; on Fedora it only comes from the Quickshell COPRs. Without it the
build still works, only that handler is off.

A hand-built `qs` / `quickshell` earlier on `PATH` (in `~/.local/bin`, say) would
hide the package's; the builder offers to move those aside (renamed `*.hand-built`).

## After a Qt update

Quickshell built for one Qt does not start on another. The guard
(`../quickshell-guard`) notices: the pacman hook warns, and `qs-rebuild.sh` runs
`qs-build.sh rebuild` for this package.

## Moving to a new Quickshell commit

1. In a clone of quickshell, `git checkout <commit>` and `git apply --check` every patch.
2. Update `QS_COMMIT` and `QS_VERSION` in `revision` (`git describe --tags`,
   `v0.3.2-11-g9b0f339` → `0.3.2.r11.g9b0f339`); reset `QS_RELEASE` to 1.
3. `./qs-build.sh rebuild`, start the shell, and check the log has no new warnings.
