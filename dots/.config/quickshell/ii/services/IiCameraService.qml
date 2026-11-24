pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.services

/**
 * Phone webcam over ii link (ROADMAP 4.6): streams H.264 from the active
 * ii tools phone through the link helper into a v4l2loopback device, or into a
 * PipeWire camera node when there is no loopback module (`iiTools.camera.output`).
 *
 * Dependency probes run once when the backend becomes relevant (active ii phone
 * with camera enabled and DroidCam override off) and on refresh(), never polling.
 */
Singleton {
    id: root

    // ── Config & active phone ───────────────────────────────────────────
    readonly property bool enabled: Config.options?.iiTools?.camera?.enable ?? true
    readonly property bool useDroidcam: Config.options?.iiTools?.camera?.useDroidcam ?? false
    readonly property string outputPref: Config.options?.iiTools?.camera?.output ?? "auto"
    readonly property bool activeIsIi: KdeConnectService.activeIsIi
    readonly property string activeDev: {
        if (!root.activeIsIi)
            return "";
        const active = String(KdeConnectService.activeDeviceId ?? "");
        if (active.startsWith("iitools:"))
            return active.slice(8);
        return String(IiLinkService.peers[0]?.id ?? "");
    }
    readonly property bool connected: root.activeDev !== ""
        && IiLinkService.connections[root.activeDev] !== undefined
    readonly property bool hasCameraCap: root.connected
        && (IiLinkService.phoneCaps[root.activeDev] ?? []).includes("camera")
    readonly property bool relevant: (Config.options?.policies?.phone ?? 1) !== 0
        && root.enabled && !root.useDroidcam && root.activeIsIi

    // ── Session & phone state ───────────────────────────────────────────
    property var phoneStatus: ({})
    property bool asking: false
    /// "idle" | "asking" | "starting" | "live"
    property string state: "idle"
    property string videoDevice: ""
    property string lastError: ""
    property int sid: 0
    property string dev: ""
    property int elapsedMs: 0

    signal errorOccurred(string message)

    onStateChanged: {
        if (root.state !== "live")
            root.elapsedMs = 0;
    }

    Timer {
        id: elapsedTicker
        interval: 1000
        repeat: true
        running: root.state === "live"
        onTriggered: root.elapsedMs += 1000
    }

    // ── Live PC-side transform config ───────────────────────────────────
    // The mirror is the phone's own setting (`set {mirror}`, sent in its meta): the PC
    // adds none of its own here, so the app and the sidebar show one switch.
    readonly property bool _mirror: false
    readonly property int _rotate: Config.options?.phone?.webcam?.rotateDegrees ?? 0
    on_RotateChanged: root._pushConfig()
    /// The video rides the USB cable (`adb reverse` of the link's port) when it is plugged.
    property bool _usb: false

    function _pushConfig(): void {
        if (root.state === "live" || root.state === "starting")
            IiLinkService.send({ op: "camera", a: "config", mirror: root._mirror, rotate: root._rotate });
    }

    // ── Dependency checks (one-shot when relevant + on refresh()) ───────
    property bool ffmpegPresent: false
    property bool ffmpegHasH264: false
    property bool v4l2loopbackLoaded: false
    property bool v4l2loopbackInstalled: false
    property bool v4l2loopbackCtlPresent: false
    property bool pkexecPresent: false
    property bool hasIiDevice: false
    /// GStreamer with pipewiresink and rawvideoparse: the PipeWire output.
    property bool gstPipewirePresent: false
    property string detectedDistro: "unknown"
    property bool _depsChecked: false
    property bool _hadSession: false

    readonly property bool ffmpegReady: root.ffmpegPresent && root.ffmpegHasH264
    readonly property bool v4l2Ready: root.ffmpegReady && (root.v4l2loopbackLoaded || root.v4l2loopbackInstalled)
    /// "v4l2" | "pipewire": where the picture goes. Auto prefers the loopback device,
    /// which every app lists; PipeWire needs no kernel module but fewer apps read it.
    readonly property string output: root.outputPref === "pipewire" ? "pipewire"
        : root.outputPref === "v4l2" ? "v4l2"
        : (root.v4l2Ready || !root.gstPipewirePresent ? "v4l2" : "pipewire")
    // ffmpeg decodes for both outputs; the PipeWire one only swaps the writer.
    readonly property bool available: root.output === "pipewire" ? (root.ffmpegReady && root.gstPipewirePresent) : root.v4l2Ready

    readonly property var _ffmpegInstallCommands: ({
        arch: "sudo pacman -S ffmpeg",
        fedora: "sudo dnf install https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm\nsudo dnf swap ffmpeg-free ffmpeg --allowerasing",
        debian: "sudo apt install ffmpeg",
        opensuse: "sudo zypper install ffmpeg-7  # or ffmpeg from Packman"
    })
    readonly property var _v4l2loopbackInstallCommands: ({
        arch: "sudo pacman -S v4l2loopback-dkms v4l2loopback-utils \"$(pacman -Qqo /usr/lib/modules/$(uname -r)/vmlinuz)-headers\"\necho v4l2loopback | sudo tee /etc/modules-load.d/v4l2loopback.conf && echo 'options v4l2loopback devices=1 exclusive_caps=1 card_label=\"ii tools camera\"' | sudo tee /etc/modprobe.d/ii-tools-camera.conf && sudo modprobe v4l2loopback",
        fedora: "sudo dnf install akmod-v4l2loopback v4l2loopback\necho v4l2loopback | sudo tee /etc/modules-load.d/v4l2loopback.conf && echo 'options v4l2loopback devices=1 exclusive_caps=1 card_label=\"ii tools camera\"' | sudo tee /etc/modprobe.d/ii-tools-camera.conf && sudo modprobe v4l2loopback",
        debian: "sudo apt install v4l2loopback-dkms v4l2loopback-utils\necho v4l2loopback | sudo tee /etc/modules-load.d/v4l2loopback.conf && echo 'options v4l2loopback devices=1 exclusive_caps=1 card_label=\"ii tools camera\"' | sudo tee /etc/modprobe.d/ii-tools-camera.conf && sudo modprobe v4l2loopback",
        opensuse: "sudo zypper install v4l2loopback-kmp-default v4l2loopback-utils\necho v4l2loopback | sudo tee /etc/modules-load.d/v4l2loopback.conf && echo 'options v4l2loopback devices=1 exclusive_caps=1 card_label=\"ii tools camera\"' | sudo tee /etc/modprobe.d/ii-tools-camera.conf && sudo modprobe v4l2loopback"
    })
    readonly property var _gstInstallCommands: ({
        arch: "sudo pacman -S gst-plugin-pipewire gst-plugins-base gst-plugins-bad",
        fedora: "sudo dnf install pipewire-gstreamer gstreamer1-plugins-base gstreamer1-plugins-bad-free",
        debian: "sudo apt install gstreamer1.0-pipewire gstreamer1.0-plugins-base gstreamer1.0-plugins-bad",
        opensuse: "sudo zypper install gstreamer-plugin-pipewire gstreamer-plugins-base gstreamer-plugins-bad"
    })
    readonly property var _v4l2loopbackCtlInstallCommands: ({
        arch: "sudo pacman -S v4l2loopback-utils",
        fedora: "sudo dnf install v4l2loopback",
        debian: "sudo apt install v4l2loopback-utils",
        opensuse: "sudo zypper install v4l2loopback-utils"
    })
    readonly property var _pkexecInstallCommands: ({
        arch: "sudo pacman -S polkit",
        fedora: "sudo dnf install polkit",
        debian: "sudo apt install pkexec",
        opensuse: "sudo zypper install polkit"
    })

    readonly property var missingDeps: {
        const deps = [];
        if (!root.ffmpegPresent) {
            deps.push({
                key: "ffmpeg",
                name: Translation.tr("FFmpeg"),
                description: Translation.tr("Decodes the phone's H.264 camera stream."),
                present: false,
                installCommands: root._ffmpegInstallCommands,
                packages: {
                    arch: "ffmpeg",
                    fedora: "ffmpeg (RPM Fusion)",
                    debian: "ffmpeg",
                    opensuse: "ffmpeg / ffmpeg-7",
                    unknown: "ffmpeg"
                }
            });
        } else if (!root.ffmpegHasH264) {
            deps.push({
                key: "ffmpeg-h264",
                name: Translation.tr("FFmpeg cannot decode H.264"),
                description: Translation.tr("The installed FFmpeg build has no H.264 decoder (such as Fedora's ffmpeg-free without OpenH264). Replace it with a full FFmpeg build."),
                present: false,
                installCommands: root._ffmpegInstallCommands,
                packages: {
                    arch: "ffmpeg",
                    fedora: "ffmpeg (RPM Fusion)",
                    debian: "ffmpeg",
                    opensuse: "ffmpeg / ffmpeg-7",
                    unknown: "ffmpeg (with H.264)"
                }
            });
        }
        if (root.output === "pipewire") {
            if (!root.gstPipewirePresent) {
                deps.push({
                    key: "gst-pipewire",
                    name: Translation.tr("GStreamer PipeWire plugins"),
                    description: Translation.tr("Make the phone a PipeWire camera (pipewiresink and rawvideoparse), with no kernel module. Apps that read cameras through PipeWire see it."),
                    present: false,
                    installCommands: root._gstInstallCommands,
                    packages: {
                        arch: "gst-plugin-pipewire, gst-plugins-base, gst-plugins-bad",
                        fedora: "pipewire-gstreamer, gstreamer1-plugins-base, gstreamer1-plugins-bad-free",
                        debian: "gstreamer1.0-pipewire, gstreamer1.0-plugins-base, gstreamer1.0-plugins-bad",
                        opensuse: "gstreamer-plugin-pipewire, gstreamer-plugins-base, gstreamer-plugins-bad",
                        unknown: "gst-plugin-pipewire, gst-plugins-base, gst-plugins-bad"
                    }
                });
            }
            return deps;
        }
        if (!root.v4l2loopbackLoaded && !root.v4l2loopbackInstalled) {
            deps.push({
                key: "v4l2loopback",
                name: Translation.tr("v4l2loopback kernel module"),
                description: Translation.tr("Creates the virtual /dev/videoN camera device. With Secure Boot enabled, the DKMS/akmod module must be signed (MOK). DroidCam already needs the same module."),
                present: false,
                installCommands: root._v4l2loopbackInstallCommands,
                packages: {
                    arch: "v4l2loopback-dkms, v4l2loopback-utils, headers for the running kernel (linux-zen-headers, linux-lts-headers…)",
                    fedora: "akmod-v4l2loopback, v4l2loopback",
                    debian: "v4l2loopback-dkms, v4l2loopback-utils",
                    opensuse: "v4l2loopback-kmp-default, v4l2loopback-utils",
                    unknown: "v4l2loopback"
                }
            });
        }
        if (!root.v4l2loopbackCtlPresent && !root.hasIiDevice) {
            deps.push({
                key: "v4l2loopback-ctl",
                name: Translation.tr("v4l2loopback-ctl"),
                description: Translation.tr("Creates an \"ii tools camera\" loopback device on demand if one is not configured at boot (requires v4l2loopback-ctl with add support)."),
                present: false,
                installCommands: root._v4l2loopbackCtlInstallCommands,
                packages: {
                    arch: "v4l2loopback-utils",
                    fedora: "v4l2loopback",
                    debian: "v4l2loopback-utils",
                    opensuse: "v4l2loopback-utils",
                    unknown: "v4l2loopback-utils"
                }
            });
        }
        if (!root.pkexecPresent && (!root.hasIiDevice || !root.v4l2loopbackLoaded)) {
            deps.push({
                key: "pkexec",
                name: Translation.tr("polkit (pkexec)"),
                description: Translation.tr("Prompts for administrator permission to load v4l2loopback or create the virtual camera device on demand."),
                present: false,
                installCommands: root._pkexecInstallCommands,
                packages: {
                    arch: "polkit",
                    fedora: "polkit",
                    debian: "pkexec",
                    opensuse: "polkit",
                    unknown: "polkit (pkexec)"
                }
            });
        }
        return deps;
    }

    readonly property string missingPackageSummary: {
        const distro = root.detectedDistro || "unknown";
        const seen = {};
        const names = [];
        for (const dep of root.missingDeps) {
            // Only include hard requirements when summarizing missing packages for Settings.
            if (dep.key === "v4l2loopback-ctl" || dep.key === "pkexec")
                continue;
            const raw = dep.packages?.[distro] || dep.packages?.unknown || dep.name;
            for (const part of String(raw).split(",")) {
                const pkg = part.trim();
                if (pkg && !seen[pkg]) {
                    seen[pkg] = true;
                    names.push(pkg);
                }
            }
        }
        return names.join(", ");
    }

    Component.onCompleted: {
        if (root.relevant && !root._depsChecked)
            root.refresh();
    }

    onRelevantChanged: {
        if (root.relevant && !root._depsChecked)
            root.refresh();
    }

    function refresh(): void {
        checkDepsProc.running = false;
        checkDepsProc.running = true;
    }

    Process {
        id: checkDepsProc
        running: false
        command: ["bash", "-c",
            "PATH=\"$PATH:/sbin:/usr/sbin\"; " +
            "if command -v ffmpeg >/dev/null 2>&1; then " +
            "  echo 'ffmpeg=1'; " +
            "  ffmpeg -hide_banner -decoders 2>/dev/null | grep -Eq '[[:space:]](h264|libopenh264)[[:space:]]' && echo 'ffmpeg_h264=1' || echo 'ffmpeg_h264=0'; " +
            "else echo 'ffmpeg=0'; echo 'ffmpeg_h264=0'; fi; " +
            "[ -d /sys/module/v4l2loopback ] && echo 'v4l2loopback_loaded=1' || echo 'v4l2loopback_loaded=0'; " +
            "modinfo v4l2loopback >/dev/null 2>&1 && echo 'v4l2loopback_installed=1' || echo 'v4l2loopback_installed=0'; " +
            "if command -v v4l2loopback-ctl >/dev/null 2>&1 && v4l2loopback-ctl --help 2>&1 | grep -qw add; then " +
            "  echo 'v4l2loopback_ctl=1'; else echo 'v4l2loopback_ctl=0'; fi; " +
            "command -v pkexec >/dev/null 2>&1 && echo 'pkexec=1' || echo 'pkexec=0'; " +
            "ii_dev=0; for n in /sys/devices/virtual/video4linux/video*/name; do " +
            "  [ -r \"$n\" ] || continue; " +
            "  case \"$(cat \"$n\" 2>/dev/null | tr '[:upper:]' '[:lower:]')\" in *\"ii tools\"*) ii_dev=1; break;; esac; " +
            "done; echo \"ii_device=$ii_dev\"; " +
            "gst-inspect-1.0 pipewiresink >/dev/null 2>&1 && gst-inspect-1.0 rawvideoparse >/dev/null 2>&1 " +
            "  && echo 'gst=1' || echo 'gst=0'; " +
            "distro=unknown; " +
            "if [ -r /etc/os-release ]; then " +
            "  os_info=$(ID=\"\"; ID_LIKE=\"\"; . /etc/os-release 2>/dev/null; printf '%s %s' \"$ID\" \"$ID_LIKE\" | tr '[:upper:]' '[:lower:]'); " +
            "  for tok in $os_info; do " +
            "    case \"$tok\" in " +
            "      arch|manjaro|endeavouros|cachyos|garuda|artix|arcolinux) distro=arch; break;; " +
            "      fedora|nobara|bazzite|ultramarine) distro=fedora; break;; " +
            "      debian|ubuntu|linuxmint|pop|neon|elementary|zorin) distro=debian; break;; " +
            "      opensuse*|suse|sles|sled) distro=opensuse; break;; " +
            "    esac; " +
            "  done; " +
            "fi; " +
            "echo \"distro=$distro\""]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = String(this.text);
                root.ffmpegPresent = out.indexOf("ffmpeg=1") >= 0;
                root.ffmpegHasH264 = out.indexOf("ffmpeg_h264=1") >= 0;
                root.v4l2loopbackLoaded = out.indexOf("v4l2loopback_loaded=1") >= 0;
                root.v4l2loopbackInstalled = out.indexOf("v4l2loopback_installed=1") >= 0;
                root.v4l2loopbackCtlPresent = out.indexOf("v4l2loopback_ctl=1") >= 0;
                root.pkexecPresent = out.indexOf("pkexec=1") >= 0;
                root.hasIiDevice = out.indexOf("ii_device=1") >= 0;
                root.gstPipewirePresent = out.indexOf("gst=1") >= 0;
                const m = /distro=(arch|fedora|debian|opensuse|unknown)/.exec(out);
                if (m)
                    root.detectedDistro = m[1];
                root._depsChecked = true;
            }
        }
    }

    // ── Session cleanup on device/config changes ────────────────────────
    onActiveDevChanged: {
        if (root.dev !== "" && root.dev !== root.activeDev)
            root.stop();
        root._hadSession = false;
        root.phoneStatus = ({});
    }

    onEnabledChanged: {
        if (!root.enabled && root.state !== "idle")
            root.stop();
    }

    onUseDroidcamChanged: {
        if (root.useDroidcam && root.state !== "idle")
            root.stop();
    }

    onHasCameraCapChanged: {
        if (!root.hasCameraCap) {
            if (root.state !== "idle")
                root.stop();
            root.phoneStatus = ({});
        }
    }

    // ── Public API ──────────────────────────────────────────────────────
    function start(): void {
        if (!root.enabled || root.useDroidcam)
            return;
        if (!root.available) {
            root._fail(root._depsErrorMessage());
            return;
        }
        if (!root.connected) {
            root._fail(Translation.tr("Phone is offline — open ii tools on your phone or check the connection"));
            return;
        }
        if (!root.hasCameraCap) {
            root._fail(Translation.tr("Update ii tools on your phone to use its camera"));
            return;
        }
        if (root.state !== "idle") {
            if (root.dev !== "" && root.dev !== root.activeDev)
                root._fail(Translation.tr("Another phone is already streaming — stop it first"));
            return;
        }

        root.lastError = "";
        root._hadSession = true;
        root.dev = root.activeDev;
        root.asking = true;
        root.state = "asking";
        IiLinkService.sendTo(root.dev, { t: "camera", a: "request" });
    }

    function stop(): void {
        const targetDev = root.dev !== "" ? root.dev : root.activeDev;
        const wasHelperArmed = root.state === "starting" || root.state === "live";
        const wasActive = root.state !== "idle";

        root.sid += 1;
        root._hadSession = false;
        root.state = "idle";
        root.asking = false;
        root.videoDevice = "";
        root.elapsedMs = 0;
        root.dev = "";

        if (wasHelperArmed)
            IiLinkService.send({ op: "camera", a: "stop" });
        if (wasActive && targetDev !== "")
            IiLinkService.sendTo(targetDev, { t: "camera", a: "stop" });
    }

    function set(obj): void {
        const targetDev = root.dev !== "" ? root.dev : root.activeDev;
        if (targetDev === "" || !root.connected)
            return;
        IiLinkService.sendTo(targetDev, Object.assign({ t: "camera", a: "set" }, obj));
    }

    function _fail(message: string): void {
        root.lastError = message;
        root.errorOccurred(message);
    }

    function _resetSession(): void {
        root.state = "idle";
        root.asking = false;
        root.videoDevice = "";
        root.elapsedMs = 0;
        root.dev = "";
    }

    function _depsErrorMessage(): string {
        if (!root.ffmpegPresent)
            return root.output === "pipewire"
                ? Translation.tr("Install FFmpeg and GStreamer's PipeWire plugin to use the phone webcam")
                : Translation.tr("Install FFmpeg and v4l2loopback to use the phone webcam");
        if (!root.ffmpegHasH264)
            return Translation.tr("Your FFmpeg build cannot decode H.264 — install a full FFmpeg build");
        if (root.output === "pipewire")
            return Translation.tr("Install GStreamer's PipeWire and bad plugins to use PipeWire webcam output");
        return Translation.tr("Install the v4l2loopback kernel module to use the phone webcam");
    }

    function _deviceErrorMessage(code: int, devPath: string): string {
        switch (code) {
        case 3:
            return Translation.tr("v4l2loopback-ctl is missing or too old to create a virtual camera device — install or update v4l2loopback-utils");
        case 4:
            return Translation.tr("polkit (pkexec) is needed to load v4l2loopback or create the virtual camera device");
        case 5:
            return Translation.tr("Your user cannot write %1: log out and in, or add yourself to the video group").arg(devPath || "/dev/videoN");
        case 6:
            return Translation.tr("Administrator authentication was dismissed — approve it to create the virtual camera device");
        case 7:
            return Translation.tr("No free virtual camera device found — close apps using existing virtual cameras or install v4l2loopback-utils");
        case 8:
            return Translation.tr("Could not load the v4l2loopback kernel module — if Secure Boot is enabled, sign the module (MOK)");
        default:
            return Translation.tr("Could not prepare the virtual camera device");
        }
    }

    function _reasonMessage(reason: string): string {
        switch (reason) {
        case "timeout":
            return Translation.tr("Phone did not connect to the camera stream in time — keep ii tools open and try again");
        case "decoder":
            return Translation.tr("FFmpeg failed to decode the camera stream — check that your FFmpeg build supports H.264");
        case "device":
            return Translation.tr("The virtual camera stopped taking the video, even after reopening it — the shell's log says why (qs log -c ii | grep camera)");
        case "busy":
            return Translation.tr("Another phone is already streaming — stop it first");
        default:
            return reason;
        }
    }

    function _phoneErrorMessage(code: string): string {
        switch (code) {
        case "permission":
            return Translation.tr("Camera permission denied — allow Camera access for ii tools on your phone");
        case "camera":
            return Translation.tr("Phone camera could not be opened — close other apps using it on your phone and try again");
        case "encoder":
            return Translation.tr("Phone video encoder failed — try switching quality to 720p or restarting ii tools");
        case "network":
            return Translation.tr("Camera stream network error — check Wi-Fi or connect the phone over USB");
        default:
            // The PC's own reasons, which the phone reports back as its error.
            return root._reasonMessage(code);
        }
    }

    // ── Loopback device lookup / creation ───────────────────────────────
    Process {
        id: resolveDeviceProc
        property int targetSid: 0
        property string targetDev: ""
        running: false
        command: ["bash", "-c",
            "PATH=\"$PATH:/sbin:/usr/sbin\"; " +
            "find_ii_dev() { " +
            "  for n in /sys/devices/virtual/video4linux/video*/name; do " +
            "    [ -r \"$n\" ] || continue; " +
            "    case \"$(cat \"$n\" 2>/dev/null | tr '[:upper:]' '[:lower:]')\" in " +
            "      *\"ii tools\"*) " +
            "        d=${n%/name}; dev=\"/dev/${d##*/}\"; " +
            "        [ -c \"$dev\" ] && { printf '%s\\n' \"$dev\"; return 0; };; " +
            "    esac; " +
            "  done; " +
            "  return 1; " +
            "}; " +
            "wait_writable() { " +
            "  local dev=\"$1\" i; " +
            "  for i in $(seq 30); do [ -w \"$dev\" ] && return 0; sleep 0.1; done; " +
            "  return 1; " +
            "}; " +
            "in_use() { " +
            "  local dev=\"$1\"; " +
            "  if command -v fuser >/dev/null 2>&1; then " +
            "    fuser \"$dev\" >/dev/null 2>&1 && return 0; " +
            "    return 1; " +
            "  fi; " +
            "  [ -n \"$(find /proc/[0-9]*/fd -lname \"$dev\" -print -quit 2>/dev/null)\" ]; " +
            "}; " +
            "find_free_loopback() { " +
            "  local n d dev name_lc cam_cand=\"\" other_cand=\"\"; " +
            "  for n in /sys/devices/virtual/video4linux/video*/name; do " +
            "    [ -r \"$n\" ] || continue; " +
            "    d=${n%/name}; " +
            "    [ -e \"$d/format\" ] || [ -e \"$d/buffers\" ] || continue; " +
            "    dev=\"/dev/${d##*/}\"; " +
            "    [ -c \"$dev\" ] || continue; " +
            "    name_lc=$(cat \"$n\" 2>/dev/null | tr '[:upper:]' '[:lower:]'); " +
            "    case \"$name_lc\" in *droidcam*|*scrcpy*) continue;; esac; " +
            "    in_use \"$dev\" && continue; " +
            "    case \"$name_lc\" in " +
            "      *camera*|*webcam*) [ -z \"$cam_cand\" ] && cam_cand=\"$dev\";; " +
            "      *) [ -z \"$other_cand\" ] && other_cand=\"$dev\";; " +
            "    esac; " +
            "  done; " +
            "  if [ -n \"$cam_cand\" ]; then printf '%s\\n' \"$cam_cand\"; return 0; fi; " +
            "  if [ -n \"$other_cand\" ]; then printf '%s\\n' \"$other_cand\"; return 0; fi; " +
            "  return 1; " +
            "}; " +
            "if dev=$(find_ii_dev); then " +
            "  wait_writable \"$dev\" && { printf '%s\\n' \"$dev\"; exit 0; }; " +
            "  printf '%s\\n' \"$dev\"; exit 5; " +
            "fi; " +
            "if [ ! -d /sys/module/v4l2loopback ]; then " +
            "  command -v pkexec >/dev/null 2>&1 || exit 4; " +
            "  pkexec modprobe v4l2loopback >/dev/null 2>&1; rc=$?; " +
            "  if [ $rc -ne 0 ]; then " +
            "    [ $rc -eq 126 ] || [ $rc -eq 127 ] && exit 6; " +
            "    exit 8; " +
            "  fi; " +
            "  for i in $(seq 10); do " +
            "    if dev=$(find_ii_dev); then " +
            "      wait_writable \"$dev\" && { printf '%s\\n' \"$dev\"; exit 0; }; " +
            "      printf '%s\\n' \"$dev\"; exit 5; " +
            "    fi; " +
            "    sleep 0.1; " +
            "  done; " +
            "fi; " +
            "fail_code=7; " +
            "if ! command -v v4l2loopback-ctl >/dev/null 2>&1 || ! v4l2loopback-ctl --help 2>&1 | grep -qw add; then " +
            "  fail_code=3; " +
            "elif ! command -v pkexec >/dev/null 2>&1; then " +
            "  fail_code=4; " +
            "else " +
            "  out=$(pkexec v4l2loopback-ctl add -n 'ii tools camera' -x 1 2>/dev/null); rc=$?; " +
            "  if [ $rc -eq 0 ]; then " +
            "    dev=${out%%$'\\n'*}; dev=${dev%$'\\r'}; " +
            "    if [ -n \"$dev\" ] && [ -c \"$dev\" ]; then " +
            "      wait_writable \"$dev\" && { printf '%s\\n' \"$dev\"; exit 0; }; " +
            "      printf '%s\\n' \"$dev\"; exit 5; " +
            "    fi; " +
            "  elif [ $rc -eq 126 ] || [ $rc -eq 127 ]; then " +
            "    fail_code=6; " +
            "  fi; " +
            "fi; " +
            "if dev=$(find_free_loopback); then " +
            "  wait_writable \"$dev\" && { printf '%s\\n' \"$dev\"; exit 0; }; " +
            "  printf '%s\\n' \"$dev\"; exit 5; " +
            "fi; " +
            "exit $fail_code"]
        stdout: StdioCollector {
            id: resolveDeviceOut
        }
        onExited: (code, status) => {
            if (resolveDeviceProc.targetSid !== root.sid || root.state !== "starting")
                return;
            const devPath = String(resolveDeviceOut.text ?? "").trim().split("\n")[0].trim();
            if (code !== 0 || !devPath.startsWith("/dev/video")) {
                const targetDev = resolveDeviceProc.targetDev;
                root._resetSession();
                root._hadSession = false;
                root._fail(root._deviceErrorMessage(code, devPath));
                if (targetDev !== "")
                    IiLinkService.sendTo(targetDev, { t: "camera", err: "device" });
                return;
            }
            root.v4l2loopbackLoaded = true;
            root.videoDevice = devPath;
            IiLinkService.send({
                op: "camera",
                a: "arm",
                dev: root.dev,
                sid: root.sid,
                device: devPath,
                mirror: root._mirror,
                rotate: root._rotate
            });
        }
    }

    // ── USB route ───────────────────────────────────────────────────────
    // The phone on a USB cable with debugging allowed: `adb reverse` of the link's
    // port, so the video goes over the cable (Wi-Fi jitters by tens of milliseconds).
    // Wireless adb lists the same phone again without `usb:`; the model picks it among
    // several. No adb, no cable: the link's own route, silently.
    Process {
        id: usbProc
        property int targetSid: 0
        property string model: ""
        running: false
        command: ["bash", "-c",
            "command -v adb >/dev/null 2>&1 || exit 1; " +
            "list=$(timeout 3 adb devices -l) || exit 1; " +
            "serial=$(printf '%s\n' \"$list\" | awk -v w=\"model:$1\" '$2==\"device\" && /usb:/ { for (i = 3; i <= NF; i++) if ($i == w) { print $1; exit } }'); " +
            "[ -n \"$serial\" ] || serial=$(printf '%s\n' \"$list\" | awk '$2==\"device\" && /usb:/ { n++; s = $1 } END { if (n == 1) print s }'); " +
            "[ -n \"$serial\" ] || exit 1; " +
            "timeout 3 adb -s \"$serial\" reverse tcp:$2 tcp:$2 >/dev/null 2>&1 && echo usb",
            "ii-camera-usb", usbProc.model, String(IiLinkService.port)]
        stdout: StdioCollector {
            id: usbOut
        }
        onExited: (code, status) => {
            if (usbProc.targetSid !== root.sid || root.state !== "starting")
                return;
            root._usb = code === 0 && String(usbOut.text ?? "").trim() === "usb";
            root._prepareOutput(root.dev);
        }
    }

    /// After the route: arm the helper straight away (PipeWire) or find the device first.
    function _prepareOutput(dev: string): void {
        if (root.output === "pipewire") {
            root.videoDevice = "PipeWire";
            IiLinkService.send({ op: "camera", a: "arm", dev: dev, sid: root.sid, sink: "pipewire",
                mirror: root._mirror, rotate: root._rotate });
            return;
        }
        resolveDeviceProc.targetSid = root.sid;
        resolveDeviceProc.targetDev = dev;
        resolveDeviceProc.running = false;
        resolveDeviceProc.running = true;
    }

    // ── Wire message & event handlers (called by IiLinkService) ─────────
    function handleMessage(dev: string, m: var): void {
        if (m.status && typeof m.status === "object") {
            if (dev === root.activeDev) {
                root.phoneStatus = m.status;
                const stState = String(m.status.state ?? "");
                const stErr = String(m.status.error ?? "");
                if (stState === "error" && stErr !== "" && ((root.state !== "idle" && dev === root.dev) || root._hadSession)) {
                    root._hadSession = false;
                    root._fail(root._phoneErrorMessage(stErr));
                    if (root.state === "asking" && dev === root.dev)
                        root._resetSession();
                } else if (stState === "idle" && root.state === "idle") {
                    root._hadSession = false;
                }
            }
        }

        if (m.asking !== undefined) {
            if (dev !== root.activeDev && dev !== root.dev)
                return;
            if (m.asking === true) {
                root.asking = true;
                if (root.state === "idle") {
                    root.dev = dev;
                    root.state = "asking";
                }
            } else {
                root.asking = false;
                if (root.state === "asking" && dev === root.dev)
                    root._resetSession();
                // The phone could not ask: the app's notifications are off.
                if (String(m.reason ?? "") === "notifications")
                    root._fail(Translation.tr("Open the webcam in ii tools on the phone and press Start: its notifications are off, so it cannot ask you"));
            }
            return;
        }

        switch (String(m.a ?? "")) {
        case "start": {
            if (!root.enabled || root.useDroidcam) {
                IiLinkService.sendTo(dev, { t: "camera", err: "disabled" });
                return;
            }
            if (!root.available) {
                IiLinkService.sendTo(dev, { t: "camera", err: "deps" });
                root._fail(root._depsErrorMessage());
                return;
            }
            if (root.state !== "idle" && root.dev !== dev) {
                IiLinkService.sendTo(dev, { t: "camera", err: "busy" });
                if (dev === root.activeDev)
                    root._fail(Translation.tr("Another phone is already streaming — stop it first"));
                return;
            }
            if (root.state === "starting" || root.state === "live")
                IiLinkService.send({ op: "camera", a: "stop" });

            root.sid += 1;
            root._hadSession = true;
            root.dev = dev;
            root.asking = false;
            root.lastError = "";
            root.elapsedMs = 0;
            root.videoDevice = "";
            root.state = "starting";

            root._usb = false;
            usbProc.targetSid = root.sid;
            usbProc.model = String(IiLinkService.connections[dev]?.model ?? "").replace(/[^A-Za-z0-9]/g, "_");
            usbProc.running = false;
            usbProc.running = true;
            return;
        }
        case "stop":
            if (dev === root.dev && root.state !== "idle") {
                const wasArmed = root.state === "starting" || root.state === "live";
                root.sid += 1;
                root._resetSession();
                if (wasArmed)
                    IiLinkService.send({ op: "camera", a: "stop" });
            }
            return;
        }
    }

    function handleEvent(ev: var): void {
        if (Number(ev?.sid ?? -1) !== root.sid || root.state === "idle")
            return;
        switch (String(ev.ev ?? "")) {
        case "camera":
            if (root.state !== "starting" || String(ev.dev ?? "") !== root.dev)
                return;
            IiLinkService.sendTo(root.dev, {
                t: "camera",
                state: "ready",
                token: String(ev.token ?? ""),
                sid: root.sid,
                usb: root._usb
            });
            return;
        case "cameraLive":
            if (String(ev.dev ?? "") !== root.dev)
                return;
            root.state = "live";
            root.elapsedMs = 0;
            root.lastError = "";
            IiLinkService.sendTo(root.dev, {
                t: "camera",
                state: "live",
                device: root.videoDevice,
                sid: root.sid
            });
            return;
        case "cameraEnd": {
            const reason = String(ev.reason ?? "");
            const targetDev = root.dev;
            const endedSid = root.sid;
            root._resetSession();
            if (targetDev !== "") {
                IiLinkService.sendTo(targetDev, {
                    t: "camera",
                    state: "stopped",
                    reason: reason,
                    sid: endedSid
                });
            }
            if (reason !== "" && reason !== "stopped" && reason !== "closed")
                root._fail(root._reasonMessage(reason));
            return;
        }
        }
    }

    // A live stream has its own socket, often over the USB cable while the link is on
    // Wi-Fi: it outlives a link drop (the helper ends it if the video stops for good).
    function handleDisconnect(dev: string): void {
        if (dev === root.dev && root.state !== "idle" && root.state !== "live") {
            const wasArmed = root.state === "starting" || root.state === "live";
            root.sid += 1;
            root._resetSession();
            if (wasArmed)
                IiLinkService.send({ op: "camera", a: "stop" });
        }
        if (dev === root.activeDev || root.activeDev === "")
            root.phoneStatus = ({});
    }
}
