# wf-recorder-ii

`ii-wf-recorder`: wf-recorder with five patches, for ii link's second screen (the phone as a
monitor, `scripts/iiLink/ii_link_src/src/screen.rs`) and the shell's screen recorder
(`scripts/videos/record.sh`, which falls back to the distribution's `wf-recorder`). It is
installed beside that one.

| Patch | What it does |
|---|---|
| `0001-ii-control.patch` | `--ii-control` reads commands on stdin: `idr` makes the next frame a key frame (an IDR with VA-API, and with NVENC and x264 given `forced-idr=1`), `bitrate <bit/s>` sets the encoder's bitrate (NVENC and x264 reconfigure; VA-API keeps its rate). Neither restarts the encoder, which with the stock binary cost the phone a ~240 ms frozen picture each time. It also prints the first frame's capture time (`ii-base-usec=N` on stderr, the compositor's CLOCK_MONOTONIC presentation time), which times every frame from capture. `--ii-rate N` gives the encoder its frame rate without `-r`'s fps filter, which holds every frame back one frame (~7 ms at 120 Hz); without either, the time base is 1/1e6 and VA-API budgets the bitrate over a million frames a second (measured: 1.1 of 30 Mbit/s). |
| `0002-ffmpeg9-supported-config.patch` | FFmpeg 9 removed `AVCodec`'s `pix_fmts`, `sample_fmts` and `ch_layouts`; this reads them through `avcodec_get_supported_config()` (FFmpeg ≥ 7.1) and keeps the fields for older FFmpeg. Upstream v0.6.0 doesn't build against FFmpeg 9 without it. |
| `0003-ii-control-pipelined-capture.patch` | With `--ii-control`, the next screencopy request goes out a millisecond after the compositor should have committed the frame in flight (from the output's measured frame period), not once that frame's copy is ready. Hyprland copies pending requests right after a commit and says ready when the GPU is done, later still while the encoder shares the GPU: asked for only then, the next request missed the next frame's render whenever a copy ran late, which skipped 3–6 % of frames at 120 Hz (Intel Arc 140V; ~1 % with the patch) and more under load. A request early enough to share a commit gives a copy of the same frame, which is not encoded. |
| `0004-ii-control-rate-cap-in-capture.patch` | With `--ii-control`, `-r N` keeps the frames due on N's schedule (by their commit times) and drops the rest before the encoder, instead of adding FFmpeg's fps filter, which holds every frame until the next one arrives: capture → encoded at 60 fps of a 120 Hz output went from 21 to 11 ms. |
| `0005-capture-output-not-region.patch` | Without `-g`, the whole output is captured as an output, not as a region of itself (with or without `--ii-control`). Hyprland 0.57 keeps a region session's box in physical pixels and compares it with the logical box asked for, so on a scaled output it never found its session again: a new session and timer per frame, freed only when the output goes, walked by every surface it draws. Its CPU climbed from ~10 to ~100 % within minutes (the phone screen fell from 120 to 30 fps; a plain recording of the laptop screen at 1.5 took it from 6 to 26 % in 45 s); now flat at ~10 %. A `-g` region still hits the bug. |

All five apply, in order, to upstream wf-recorder at the commit in `revision` (tag v0.6.0).

## Install

| System | How |
|---|---|
| NixOS (the Dendritic flake) | `pkgs/ii-wf-recorder`, on PATH as `ii-wf-recorder` |
| Arch, Fedora, anything else | `./build.sh install`: builds it into `${XDG_DATA_HOME:-~/.local/share}/ii-wf-recorder/bin/` (`status`, `remove`) |

`build.sh` needs git, meson, ninja, a C++ compiler and the dev files of wayland,
wayland-protocols, FFmpeg, libdrm and gbm (the list is at the top of the script). Audio is
built out: the second screen streams the PC's sound itself.

ii link looks for `ii-wf-recorder` on PATH, then where `build.sh` installs it, and falls back
to the stock `wf-recorder` (key frames and bitrate changes then restart the encoder).

## Moving to a new wf-recorder

1. In a clone, `git checkout <tag>` and `git apply --check patches/*.patch`.
2. Update `WFR_COMMIT` and `WFR_VERSION` in `revision`, and the flake's copy of `patches/`.
3. `./build.sh install`, start a second-screen session, and check the shell's log shows
   `screen key: idr` (not `screen restart: idr`) after a dropped frame.
