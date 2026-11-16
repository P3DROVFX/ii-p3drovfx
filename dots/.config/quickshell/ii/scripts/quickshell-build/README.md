# quickshell-build

Builds Quickshell with five startup patches, four memory patches and one crash fix and installs it as a native package,
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
| `0003-intercept-resolve-config-root-once.patch` | 0002's URL interceptor built `{configRoot.path(), configRoot.canonicalPath()}` on every call, so every type lookup of the QML loader thread paid a `realpath` + `readlink` (the config dir is a symlink) — ~16% of the loader thread. The config root's paths are resolved once, and URLs already inside the mirror return right away. |
| `0004-register-synthesized-qs-modules.patch` | Qt runs `matchingQmldirVersion` — an O(n²) duplicate check over a `qmldir`'s components — for every library import of every file unless a `QQmlTypeModule` exists for the URI. `qs.services` (~200 types) and `qs.modules.common.widgets` (~220) are imported by most files, so that was ~14% of the loader thread. Every synthesized `qs.*` module is now registered with `qmlRegisterModule(uri, 1, 0)` before the root loads. |
| `0005-only-named-composite-singletons.patch` | Qt's `QQmlTypeData::resolveTypes` resolves, adds as a dependency and caches **every** composite singleton of every imported module in every document (~200 from `qs.services` × ~2000 files), which also forces every singleton to load at boot. The executable now interposes `QQmlImports::resolvedCompositeSingletons()` (libQt6Qml calls it through the PLT; exported with `--export-dynamic-symbol`) and drops the singletons whose name does not appear in the document's text. Fails open (unfiltered) for non-local URLs or unreadable files; `QS_NO_SINGLETON_FILTER=1` turns it off. Limit: a singleton used only from a non-library `.js` imported by the document, or through a name built at runtime, would be dropped (none in this config). |
| `0006-compiled-in-jemalloc-narenas.patch` | jemalloc's default is 4 arenas per CPU (32 on 8 CPUs), and Quickshell's ~50 threads each pin one, every arena keeping its own dirty pages and part-used slabs; `MALLOC_CONF=narenas:1` saved ~100 MB, but only for shells started by a launcher that sets it. The executable now defines jemalloc's `malloc_conf` (`narenas:1`, CMake cache variable `JEMALLOC_MALLOC_CONF`, empty to drop it) and exports it with `--export-dynamic-symbol=malloc_conf`, so the shared libjemalloc's weak `malloc_conf` resolves to it. jemalloc reads it before `MALLOC_CONF`, which still overrides it option by option. To go back to jemalloc's own count at run time, set it explicitly (`MALLOC_CONF=narenas:<4 × CPUs>`); `narenas:0` is rejected ("Out-of-range conf value"), so only a build with `JEMALLOC_MALLOC_CONF=""` drops the default entirely. A `//@ pragma Env MALLOC_CONF=…` cannot do this: jemalloc has initialised long before pragmas are applied, so the pragma only reached a crash-relaunched shell (where it replaced `narenas:1`) and children not started through `Process`. |
| `0007-idle-gc-and-allocator-purge.patch` | Closing a panel frees thousands of objects, but nothing returns the memory: the JS wrappers wait for the next allocation-driven GC, and jemalloc only decays its dirty pages while something allocates. Qt's `QHooks::RemoveQObject` hook (present in release builds) now counts QObject destructions; at least 500 within ~2 s (`QS_IDLE_TRIM_BURST`) arm a one-shot timer, and 10 s (`QS_IDLE_TRIM_DELAY_MS`) after the last burst with no pointer, key, tablet, gesture or input-method (IME, on-screen keyboard) input to the shell, and at most once a minute (counted from the start of the trim, so the objects the collection itself frees do not arm another), it runs `collectGarbage()` and then `thread.tcache.flush` + `arena.<all>.purge` (found with `dlsym` and used only when `malloc` resolves into the same library, i.e. jemalloc is the allocator in use; otherwise glibc's `malloc_trim(0)`). No periodic timer: an idle shell is never woken, and hidden-but-loaded panels trigger nothing. `QS_NO_IDLE_TRIM=1` turns it off; `--log-rules quickshell.memtrim.debug=true` logs each trim (the before/after statistics are only gathered then). |
| `0008-idle-trim-component-cache.patch` | Adds `QQmlEngine::trimComponentCache()` to that trim, after the GC, so the compiled types of closed panels are dropped too. **Off by default** (`QS_IDLE_TRIM_COMPONENTS=1` turns it on): measured, the call blocked the GUI thread for 34–71 ms whenever it had types to drop, the first reopen of a trimmed panel was ~10–16 ms slower (median, right sidebar 151 → 167 ms), and settled PSS showed no measurable gain. | |
| `0009-idle-buffer-trim.patch` | Mesa's EGL Wayland platform keeps up to 4 colour buffers per surface and frees a spare one only while drawing, once it has gone unused for more than 20 swaps (`BUFFER_TRIM_AGE_HYSTERESIS` in `platform_wayland.c`), so a window that stops after an animation keeps its third buffer — 19.8 MB at 2880×1800 — for as long as it stays idle. A window of at least 4 MiB per buffer (full-screen windows at 1080p, 7.9 MiB, included) now redraws its unchanged scene 22 times (`QS_IDLE_BUFFER_TRIM_FRAMES`), 500 ms apart (`QS_IDLE_BUFFER_TRIM_PACE_MS`; back to back the compositor still holds the previous buffer and the spare is reused instead of aged, and 500 ms keeps a burst at ≤ 10 frames per 5 s), once it and the user have been idle 2 s (`QS_IDLE_BUFFER_TRIM_DELAY_MS`) after at least 3 animation frames. At most once per 120 s per window (`QS_IDLE_BUFFER_TRIM_INTERVAL_MS`, at least 1 s), doubling up to 10 min while the window keeps animating right after; abandoned on input. Only with OpenGL on Mesa under Wayland, detected once from the first scene graph (`GL_VERSION`); under Vulkan, the software renderer, X11 or another driver the trimmers remove themselves. **Cost:** each redraw is a commit the compositor recomposites (with blur): in the rig a burst on the island added ~25k shell and ~350k Hyprland `drm-cycles-rcs` to the 20 s after a sidebar close (about +100 % over the ~20k / ~280k of that window without it); the first version (50 ms pace, 30 s interval) added ~50–110k / ~250k–1.3M and burst the island every half minute. Shares 0007's input tracking. `QS_NO_IDLE_BUFFER_TRIM=1` turns it off; the default is one constant (`BUFFER_TRIM_DEFAULT_ON`), and with it off `QS_IDLE_BUFFER_TRIM=1` turns it on. |
| `0010-pin-openssl-default-provider.patch` | Fixes a crash 6–8 s after launch (SIGSEGV inside libcrypto: `collect_keymgmt`, `ossl_provider_free`, `ossl_provider_find`, `ENGINE_init`). Qt 6.12.0's `QCryptographicHash` loads OpenSSL's "default" provider for every hash and unloads it afterwards. When a hash is the first thing in the process to use OpenSSL, as in Quickshell, OpenSSL also adds its own fallback "default" (openssl/openssl#32079, seen with 3.5.9), and Qt's copy then drops to zero activations after nearly every hash: about 12,000 times during one start of this config, since the QML loader hashes every file for the disk cache. Each drop frees that provider's methods or flushes the decoder cache while another thread decodes certificates (the main thread loading the CA bundle for the first https request, or Qt's HTTP thread in a TLS handshake): a use-after-free. `main()` now loads the provider once and keeps it for the life of the process, so the count never reaches zero. That is what Qt's own fix does (a64dfe20a4b4, QTBUG-148575, on the 6.12 branch but not in 6.12.0). The function is looked up with `dlsym`, so the build needs no OpenSSL headers or link dependency, and it does nothing when QtCore is not linked against libcrypto (in which case `QCryptographicHash` does not use OpenSSL either). Measured on NixOS (Qt 6.12.0, OpenSSL 3.5.9): a two-thread program making the same calls crashed in 30 of 30 runs within 0.2 s, and in 0 of 30 with the provider held; in the shell the provider reached zero ~12,180 times per start before and never after. The crash itself was too rare in the test rig (0 in 107 starts) to measure a before/after rate. Drop this patch once the distribution's Qt has a64dfe20a4b4 or its OpenSSL has the #32079 fix. |

They apply in order to upstream Quickshell at the commit in `revision`. Measured on this config (restart, warm cache, 4 runs each): with 0003+0004 the first panel appears in 1.5–1.7 s instead of 2.8–3.2 s; the QML loader thread drops from ~1.9 s to ~0.7 s of CPU before it. 0005 on top (separate warm caches, 4 runs each): first panel 1.92–2.00 s → 1.57–1.65 s, loader thread 830 → 490 ms, settled anonymous memory 702–705 → 658–662 MB (PSS −43 MB), same log warnings. All five build and run against Qt 6.12.0 (Fedora rawhide container). 0006–0008 were measured on NixOS (Qt 6.12.0, jemalloc 5.4.0) in an isolated nested Hyprland with this config: 0006 gives `opt.narenas: 1` with `MALLOC_CONF` unset (32 before), and `MALLOC_CONF=narenas:4` still yields 4; same warning set at start as 0001–0005 (2 runs each). 0007 frees little here: right after closing the right sidebar and the cheatsheet the purge returned 1–3 MiB per trim (10 MiB once), PSS 15 s after a close fell 4.5 MB with it against 1.5 MB without, and 70 s later PSS was within run-to-run noise (547 vs 557 MB); each trim costs one 10–34 ms GC on the GUI thread, run only after 10 s with no input. First reopen after a trim (6 runs, medians, first presented frame): right sidebar 151 → 160 ms, cheatsheet 162 → 121 ms; the same sidebar measured 127 ms in an earlier untrimmed run, so differences under ~25 ms are within this rig's noise.

0009 in the same rig (wl_buffers counted from `WAYLAND_DEBUG`, GPU from DRM fdinfo): only `floatingNotch` held a spare there (3 full-screen buffers, the others 2). A paced burst freed it (live wl_buffers 150.6 → 130.8 MiB, shared GPU memory 174 → 152 MB); redraws back to back on frame callbacks freed nothing. The island ticks once every 3 s while idle and draws two frames at each minute change: the minute allocates the spare again and its own 3 s ticks age it out about 50 s later, so in the rig the burst only shortens that by ~40 s at most once per 2 min. Screenshots are identical before and after a burst apart from one 16×20 px area that changes on its own (same area in a control without a burst); no new warnings. Under `QT_QUICK_BACKEND=software` it logs "not in effect" and does nothing. The live session (about 5 buffers per surface against 2.6 in the rig) has to show the real gain.

Releasing the graphics of hidden windows needs no patch at this commit: `PanelWindow` and `PopupWindow` already destroy their `QQuickWindow` when hidden (`deleteOnInvisible()`), which frees the window's scene graph, render thread and GL context; a hidden `FloatingWindow` keeps its window, but the shell's are destroyed by their loaders after their retain time.

## The build

Arch builds `RelWithDebInfo` unstripped (`options=(!strip !debug)`), Fedora `Release` without a debuginfo package, and the Nix package keeps nixpkgs' `RelWithDebInfo` with `separateDebugInfo`. `QS_CMAKE_OPTIONS` at the top of `qs-build.sh` holds the options both recipes add (the Nix package sets the same):

- **Modules nothing imports are off.** `-DX11=OFF -DI3=OFF -DSERVICE_GREETD=OFF`: no QML file in this config (every panel family, the three entry files, the lock screen; the SDDM theme runs in sddm-greeter, not Quickshell) imports `Quickshell.X11`, `Quickshell.I3` or `Quickshell.Services.Greetd`. The X11 plugin also only ever applies on the xcb platform. Every other module is imported somewhere and stays on. The package replaces the system's `/usr/bin/quickshell`, so these modules are gone for every Quickshell config on the machine, not only this one: a config of your own that imports one of them needs the distribution's package back (`./qs-build.sh restore`). With X11 off nothing in Quickshell links libxcb, so the PKGBUILD no longer lists it (Qt still pulls it in).

A Release + LTO build was measured on NixOS (Qt 6.12.0, GCC 16.2, all nine patches; nested-Hyprland rig, warm `.qmlc` cache, 5 interleaved runs each) and gave nothing outside run-to-run noise: launch → first frame 1.62 → 1.58 s, PSS at 110 s 498.8 → 497.4 MiB, only `.text` shrank (6.64 → 6.13 MB). It was dropped.

NixOS's Qt 6.12.0 `libQt6Qml` calls `resolvedCompositeSingletons()` directly, not through the PLT, so 0005's filter never runs there: no "singleton filter active" in the log. Whether a distribution's Qt goes through the PLT shows in `objdump -d libQt6Qml.so.6 | grep 'call.*resolvedCompositeSingletonsEv'`: `@plt` means it does.

### Rebuilds happen by themselves

Each package records a *build stamp* in `/usr/share/quickshell-ii-git/build-stamp`: a SHA-256 of this distribution's generated PKGBUILD or spec (commit, version, CMake options, dependencies, patch list, packaging) and of every patch's bytes. Machine-dependent parts (whether the crash handler is built) are left out, so the same checkout gives the same stamp everywhere. `qs-build.sh check` prints `current`, `outdated` or `absent`, and `install` builds only when the stamp differs (or Qt changed). A package from before stamps has none and counts as outdated.

Each package also records the directory it was built from (`source <dir>`, printed by `./qs-build.sh source`).

`setup-ii-p3drovfx.sh` runs `check` on the staged config during every deployment (`update`, `switch`, `apply`), before it restarts the shell: when the installed `quickshell-ii-git` is `outdated` it runs `qs-build.sh install` from that staged tree, so the restart that follows runs the new build. It never passes `--yes`, not even when the updater itself got one (Settings' branch and fork switches do): replacing a system package is asked about in the terminal, and declined where there is none. Every package from before stamps has none and reads `outdated`, so each existing installation is rebuilt once, on its first update after stamps arrived.

An update made by an older updater, which has no such step, is caught by the start guard (`../quickshell-guard/qs-guard.sh`): once the shell is up it runs `check` in the background and, when `outdated`, opens a terminal on `qs-build.sh install` (or, with `health.guard.openTerminal` off or no terminal installed, says the command in a notification). The offer is keyed on the build stamp in `~/.local/state/quickshell/qs-build-offered`: the same build is offered again at most once every 7 days, a different one at once, and an offer nobody saw (no terminal, no notification daemon) is not recorded. A "no" in the updater is written there too, so the restart does not ask a second time. The guard says nothing when the installed build came from another checkout that still exists (a developer's tree with its own patches): offering this tree's set would undo it.

`install`, `rebuild`, `build` and `restore` take a lock (`$XDG_RUNTIME_DIR/quickshell-ii-git-build.lock`); a second one waits and then finds the package current. Before installing, the freshly built binary is run with `--private-check-compat`: a build that no longer matches the installed Qt (Qt updated during the build) is not installed. The question names the build dependencies it would install.

## Usage

```bash
./qs-build.sh install    # build and install quickshell-ii-git (asks first); nothing when current
./qs-build.sh rebuild    # the same, even when current — e.g. after a Qt update
./qs-build.sh restore    # put the distribution's quickshell-git back
./qs-build.sh status     # what is installed, patched or not, built from these patches, Qt match
./qs-build.sh check      # one word: current, outdated or absent
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
   (Patch and option changes need no bump: the build stamp catches them.)
3. `./qs-build.sh rebuild`, start the shell, and check the log has no new warnings.
