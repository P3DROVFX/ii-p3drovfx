#!/usr/bin/env python3
"""Hardware and frame-rate sampler for the performance overlay.

`perf_monitor.py run` prints one JSON object per line on stdout:

  {"t": "devices", ...}   once, right after start: CPU model and every GPU found
  {"t": "sample",  ...}   every --interval ms: CPU, RAM, the selected GPU, FPS

Everything is read from procfs/sysfs in-process; the only external work is
NVML (loaded through ctypes, with nvidia-smi as a fallback) for NVIDIA cards.
A dGPU that runtime PM has put to sleep is reported as "suspended" and never
touched, so a pinned overlay does not keep a laptop's dGPU awake.

Frame rate comes from MangoHud's CSV logger: MangoHud is told (see `setup`)
to log into a folder of our own, and the newest log there is tailed. Games
without MangoHud simply report no FPS.

`perf_monitor.py setup --dir D --interval MS [--hide-hud]` writes the logging
block into ~/.config/MangoHud/MangoHud.conf; `perf_monitor.py unsetup`
removes it again.
"""

import argparse
import ctypes
import glob
import json
import math
import os
import re
import shlex
import shutil
import subprocess
import sys
import time
from collections import deque

BLOCK_START = "# >>> ii performance overlay >>>"
BLOCK_END = "# <<< ii performance overlay <<<"
MANGOHUD_CONF = os.path.expanduser("~/.config/MangoHud/MangoHud.conf")

VENDORS = {"0x10de": "nvidia", "0x1002": "amd", "0x8086": "intel"}


def read(path, default=None):
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as f:
            return f.read().strip()
    except (OSError, ValueError):
        return default


def read_num(path, default=None):
    value = read(path)
    if value is None:
        return default
    try:
        return float(value)
    except ValueError:
        return default


def emit(obj):
    sys.stdout.write(json.dumps(obj, separators=(",", ":")) + "\n")
    sys.stdout.flush()


# ───────────────────────────────────────────────────────────── naming

def shorten_cpu_name(name):
    name = re.sub(r"\((R|TM|tm|r)\)", "", name)
    name = re.sub(r"@.*$", "", name)
    name = re.sub(r"\b(CPU|Processor|\d+-Core|with Radeon.*Graphics|w/ Radeon.*)\b", "", name, flags=re.I)
    name = re.sub(r"\b(Intel|AMD)\b", "", name)
    name = re.sub(r"\bCore\b\s*", "", name) if "Ultra" in name else name
    return re.sub(r"\s+", " ", name).strip() or "CPU"


def shorten_gpu_name(name):
    if not name:
        return "GPU"
    bracket = re.search(r"\[([^\]]+)\]", name)
    if bracket:
        name = bracket.group(1)
    name = re.sub(r"\b(NVIDIA|GeForce|AMD|ATI|Advanced Micro Devices, Inc\.|Intel Corporation|Corporation|Graphics Controller)\b", "", name)
    name = re.sub(r"\b(Laptop GPU|Mobile)\b", "", name, flags=re.I)
    name = name.split("/")[0]
    return re.sub(r"\s+", " ", name).strip() or "GPU"


def pci_ids_lookup(vendor, device):
    """Name a PCI device from the pci.ids database without touching it."""
    vendor = vendor.lower().replace("0x", "")
    device = device.lower().replace("0x", "")
    for path in ("/usr/share/hwdata/pci.ids", "/usr/share/misc/pci.ids", "/usr/share/pci.ids"):
        try:
            with open(path, "r", encoding="utf-8", errors="replace") as f:
                in_vendor = False
                for line in f:
                    if not line or line[0] == "#":
                        continue
                    if line[0] != "\t":
                        if in_vendor:
                            break
                        in_vendor = line.startswith(vendor + " ")
                        continue
                    if in_vendor and line.startswith("\t" + device + " "):
                        return line.strip()[len(device):].strip()
        except OSError:
            continue
    return ""


# ───────────────────────────────────────────────────────────── CPU

class Cpu:
    def __init__(self):
        self.prev = None
        self.model = "CPU"
        info = read("/proc/cpuinfo", "")
        match = re.search(r"^model name\s*:\s*(.+)$", info, re.M)
        if match:
            self.model = shorten_cpu_name(match.group(1))
        self.threads = len(re.findall(r"^processor\s*:", info, re.M)) or os.cpu_count() or 1
        self.freq_paths = sorted(glob.glob("/sys/devices/system/cpu/cpu[0-9]*/cpufreq/scaling_cur_freq"))
        self.temp_path = self._find_temp()
        self.energy = self._find_energy()
        self.prev_energy = None

    @staticmethod
    def _find_temp():
        preferred = {"k10temp": "Tctl", "zenpower": "Tdie", "coretemp": "Package"}
        for hw in sorted(glob.glob("/sys/class/hwmon/hwmon*")):
            name = read(os.path.join(hw, "name"), "")
            if name not in preferred:
                continue
            inputs = sorted(glob.glob(os.path.join(hw, "temp*_input")))
            for inp in inputs:
                label = read(inp.replace("_input", "_label"), "")
                if label.startswith(preferred[name]):
                    return inp
            if inputs:
                return inputs[0]
        for tz in sorted(glob.glob("/sys/class/thermal/thermal_zone*")):
            if read(os.path.join(tz, "type"), "") in ("x86_pkg_temp", "cpu-thermal", "cpu_thermal", "TCPU", "cpu", "acpitz"):
                return os.path.join(tz, "temp")
        return None

    @staticmethod
    def _find_energy():
        """Package energy counter in µJ: RAPL first, then AMD hwmon drivers."""
        for zone in sorted(glob.glob("/sys/class/powercap/*rapl*:[0-9]")):
            path = os.path.join(zone, "energy_uj")
            if read(os.path.join(zone, "name"), "").startswith("package") and read(path) is not None:
                wrap = read_num(os.path.join(zone, "max_energy_range_uj"), 0) or 0
                return ("energy", path, wrap)
        for hw in sorted(glob.glob("/sys/class/hwmon/hwmon*")):
            name = read(os.path.join(hw, "name"), "")
            if name == "zenpower":
                paths = [p for p in sorted(glob.glob(os.path.join(hw, "power*_input")))]
                if paths:
                    return ("power", paths, 0)
            if name == "amd_energy":
                for inp in sorted(glob.glob(os.path.join(hw, "energy*_input"))):
                    if read(inp.replace("_input", "_label"), "").startswith("Esocket") and read(inp) is not None:
                        return ("energy", inp, 0)
        return None

    def sample(self, now):
        out = {"model": self.model, "threads": self.threads}
        stat = read("/proc/stat", "")
        line = stat.split("\n", 1)[0].split()
        if line and line[0] == "cpu":
            values = [int(v) for v in line[1:8]]
            total = sum(values)
            idle = values[3] + values[4]
            if self.prev:
                dt = total - self.prev[0]
                di = idle - self.prev[1]
                out["usage"] = max(0.0, min(1.0, 1 - di / dt)) if dt > 0 else 0.0
            self.prev = (total, idle)

        freqs = [read_num(p) for p in self.freq_paths]
        freqs = [f for f in freqs if f]
        if freqs:
            out["clock"] = round(sum(freqs) / len(freqs) / 1000)
            out["clockMax"] = round(max(freqs) / 1000)

        if self.temp_path:
            temp = read_num(self.temp_path)
            if temp is not None:
                out["temp"] = round(temp / 1000 if temp > 1000 else temp, 1)

        power = self._power(now)
        if power is not None:
            out["power"] = round(power, 1)
        return out

    def _power(self, now):
        if not self.energy:
            return None
        kind, path, wrap = self.energy
        if kind == "power":
            values = [read_num(p) for p in path]
            values = [v for v in values if v is not None]
            return sum(values) / 1e6 if values else None
        energy = read_num(path)
        if energy is None:
            self.energy = None  # not readable (RAPL is root-only on most kernels)
            return None
        prev = self.prev_energy
        self.prev_energy = (now, energy)
        if not prev or now <= prev[0]:
            return None
        delta = energy - prev[1]
        if delta < 0:
            if not wrap:
                return None
            delta += wrap
        return delta / 1e6 / (now - prev[0])


# ───────────────────────────────────────────────────────────── memory

def memory_sample():
    info = read("/proc/meminfo", "")
    values = {}
    for line in info.splitlines():
        key, _, rest = line.partition(":")
        parts = rest.split()
        if parts:
            try:
                values[key] = int(parts[0]) * 1024
            except ValueError:
                pass
    total = values.get("MemTotal", 0)
    available = values.get("MemAvailable", values.get("MemFree", 0))
    swap_total = values.get("SwapTotal", 0)
    swap_free = values.get("SwapFree", 0)
    return {
        "used": total - available,
        "total": total,
        "swapUsed": swap_total - swap_free,
        "swapTotal": swap_total,
    }


# ───────────────────────────────────────────────────────────── GPUs

class Nvml:
    """Minimal NVML binding. Returns None everywhere when unavailable."""

    class Memory(ctypes.Structure):
        _fields_ = [("total", ctypes.c_ulonglong), ("free", ctypes.c_ulonglong), ("used", ctypes.c_ulonglong)]

    class Utilization(ctypes.Structure):
        _fields_ = [("gpu", ctypes.c_uint), ("memory", ctypes.c_uint)]

    def __init__(self):
        self.lib = None
        self.handles = {}
        try:
            self.lib = ctypes.CDLL("libnvidia-ml.so.1")
            if self.lib.nvmlInit_v2() != 0:
                self.lib = None
        except (OSError, AttributeError):
            self.lib = None

    def handle(self, bus_id):
        if not self.lib:
            return None
        if bus_id in self.handles:
            return self.handles[bus_id]
        handle = ctypes.c_void_p()
        if self.lib.nvmlDeviceGetHandleByPciBusId_v2(bus_id.encode(), ctypes.byref(handle)) != 0:
            return None
        self.handles[bus_id] = handle
        return handle

    def sample(self, bus_id):
        handle = self.handle(bus_id)
        if handle is None:
            return None
        lib = self.lib
        out = {}
        util = Nvml.Utilization()
        if lib.nvmlDeviceGetUtilizationRates(handle, ctypes.byref(util)) == 0:
            out["usage"] = util.gpu / 100
        value = ctypes.c_uint()
        if lib.nvmlDeviceGetTemperature(handle, 0, ctypes.byref(value)) == 0:
            out["temp"] = value.value
        if lib.nvmlDeviceGetClockInfo(handle, 0, ctypes.byref(value)) == 0:
            out["clock"] = value.value
        if lib.nvmlDeviceGetClockInfo(handle, 2, ctypes.byref(value)) == 0:
            out["memClock"] = value.value
        if lib.nvmlDeviceGetPowerUsage(handle, ctypes.byref(value)) == 0:
            out["power"] = round(value.value / 1000, 1)
        if lib.nvmlDeviceGetFanSpeed(handle, ctypes.byref(value)) == 0:
            out["fan"] = value.value
        mem = Nvml.Memory()
        if lib.nvmlDeviceGetMemoryInfo(handle, ctypes.byref(mem)) == 0:
            out["vramUsed"] = mem.used
            out["vramTotal"] = mem.total
        return out


def nvidia_smi_sample(bus_id):
    if not shutil.which("nvidia-smi"):
        return None
    fields = "utilization.gpu,temperature.gpu,clocks.gr,clocks.mem,power.draw,fan.speed,memory.used,memory.total"
    try:
        text = subprocess.run(
            ["nvidia-smi", "-i", bus_id, f"--query-gpu={fields}", "--format=csv,noheader,nounits"],
            capture_output=True, text=True, timeout=3).stdout
    except (OSError, subprocess.SubprocessError):
        return None
    parts = [p.strip() for p in text.strip().split(",")]
    if len(parts) < 8:
        return None

    def num(v):
        try:
            return float(v)
        except ValueError:
            return None

    usage, temp, clock, mem_clock, power, fan, used, total = map(num, parts[:8])
    out = {}
    if usage is not None: out["usage"] = usage / 100
    if temp is not None: out["temp"] = temp
    if clock is not None: out["clock"] = clock
    if mem_clock is not None: out["memClock"] = mem_clock
    if power is not None: out["power"] = power
    if fan is not None: out["fan"] = fan
    if used is not None: out["vramUsed"] = used * 1024 * 1024
    if total is not None: out["vramTotal"] = total * 1024 * 1024
    return out


class Gpu:
    def __init__(self, card):
        self.card = card
        self.dev = os.path.realpath(os.path.join(card, "device"))
        self.slot = os.path.basename(self.dev)
        vendor_id = read(os.path.join(self.dev, "vendor"), "")
        device_id = read(os.path.join(self.dev, "device"), "")
        self.vendor = VENDORS.get(vendor_id, "other")
        uevent = read(os.path.join(self.dev, "uevent"), "")
        match = re.search(r"^DRIVER=(\S+)", uevent, re.M)
        self.driver = match.group(1) if match else ""
        self.boot_vga = read(os.path.join(self.dev, "boot_vga"), "0") == "1"
        self.hwmon = next(iter(sorted(glob.glob(os.path.join(self.dev, "hwmon", "hwmon*")))), None)
        self.name = ""
        if self.vendor == "nvidia":
            info = read(f"/proc/driver/nvidia/gpus/{self.slot}/information", "")
            match = re.search(r"^Model:\s*(.+)$", info, re.M)
            if match:
                self.name = match.group(1)
        if not self.name:
            self.name = pci_ids_lookup(vendor_id, device_id) or f"{self.vendor.upper()} GPU"
        self.short_name = shorten_gpu_name(self.name)
        self.vram_total = read_num(os.path.join(self.dev, "mem_info_vram_total"), 0) or 0
        self.discrete = self._is_discrete()
        self.prev_energy = None
        self.prev_fdinfo = None
        self.nvml = None

    def _is_discrete(self):
        if self.vendor == "nvidia":
            return True
        if self.vendor == "amd":
            return not self.boot_vga or self.vram_total > 4 * 1024 ** 3
        if self.vendor == "intel":
            return self.driver == "xe" and bool(glob.glob(os.path.join(self.dev, "tile0", "vram*")))
        return False

    def describe(self):
        driver_version = ""
        if self.vendor == "nvidia":
            match = re.search(r"Kernel Module\s+(?:for\s+\S+\s+)?([\d.]+)", read("/proc/driver/nvidia/version", ""))
            driver_version = match.group(1) if match else ""
        else:
            driver_version = read(f"/sys/module/{self.driver}/version", "") if self.driver else ""
        return {
            "id": self.slot,
            "vendor": self.vendor,
            "name": self.short_name,
            "fullName": self.name,
            "driver": self.driver,
            "driverVersion": driver_version,
            "discrete": self.discrete,
            "vramTotal": self.vram_total,
        }

    def suspended(self):
        return read(os.path.join(self.dev, "power", "runtime_status"), "active") == "suspended"

    def sample(self, now):
        out = {"id": self.slot}
        if self.discrete and self.suspended():
            out["state"] = "suspended"
            return out
        out["state"] = "active"
        if self.vendor == "nvidia":
            # NVML attaches to the card, so it is only loaded once the card
            # is picked and already awake: a sleeping dGPU stays asleep.
            if self.nvml is None:
                self.nvml = Nvml()
            data = self.nvml.sample(self.slot) if self.nvml.lib else None
            if data is None:
                data = nvidia_smi_sample(self.slot)
            if data:
                out.update(data)
            return out
        if self.vendor == "amd":
            out.update(self._amd())
        elif self.vendor == "intel":
            out.update(self._intel(now))
        return out

    def _hwmon(self, name):
        return read_num(os.path.join(self.hwmon, name)) if self.hwmon else None

    def _amd(self):
        out = {}
        busy = read_num(os.path.join(self.dev, "gpu_busy_percent"))
        if busy is not None:
            out["usage"] = busy / 100
        used = read_num(os.path.join(self.dev, "mem_info_vram_used"))
        if used is not None:
            out["vramUsed"] = used
            out["vramTotal"] = self.vram_total
        temp = self._hwmon("temp2_input") if self.discrete else None  # junction on dGPUs
        temp = temp if temp is not None else self._hwmon("temp1_input")
        if temp is not None:
            out["temp"] = temp / 1000
        power = self._hwmon("power1_average")
        power = power if power is not None else self._hwmon("power1_input")
        if power is not None:
            out["power"] = round(power / 1e6, 1)
        sclk = self._hwmon("freq1_input")
        if sclk is not None:
            out["clock"] = round(sclk / 1e6)
        mclk = self._hwmon("freq2_input")
        if mclk is not None:
            out["memClock"] = round(mclk / 1e6)
        pwm = self._hwmon("pwm1")
        if pwm is not None:
            out["fan"] = round(pwm / 255 * 100)
        return out

    def _intel(self, now):
        out = {}
        freq = None
        for path in (os.path.join(self.card, "gt_act_freq_mhz"),
                     os.path.join(self.card, "gt", "gt0", "rps_act_freq_mhz"),
                     os.path.join(self.dev, "tile0", "gt0", "freq0", "act_freq")):
            freq = read_num(path)
            if freq is not None:
                break
        if freq is not None:
            out["clock"] = round(freq)
        temp = None
        if self.hwmon:
            for name in ("temp2_input", "temp1_input"):
                temp = self._hwmon(name)
                if temp is not None:
                    break
        if temp is None:
            for hw in glob.glob("/sys/class/hwmon/hwmon*"):
                if read(os.path.join(hw, "name")) == "coretemp":
                    temp = read_num(os.path.join(hw, "temp1_input"))
                    break
        if temp is not None:
            out["temp"] = temp / 1000
        energy = self._hwmon("energy1_input")
        if energy is not None:
            prev = self.prev_energy
            self.prev_energy = (now, energy)
            if prev and now > prev[0] and energy >= prev[1]:
                out["power"] = round((energy - prev[1]) / 1e6 / (now - prev[0]), 1)
        usage = self._intel_usage()
        if usage is not None:
            out["usage"] = usage
        return out

    def _intel_usage(self):
        """Busy ratio from per-client DRM fdinfo counters, like nvtop.

        xe exposes drm-cycles/drm-total-cycles per engine class; i915 exposes
        busy nanoseconds, measured against wall-clock time.
        """
        now_ns = time.monotonic_ns()
        clients = {}
        for fd_dir in glob.glob("/proc/[0-9]*/fd"):
            try:
                fds = os.listdir(fd_dir)
            except OSError:
                continue
            for fd in fds:
                try:
                    if not os.readlink(os.path.join(fd_dir, fd)).startswith("/dev/dri/"):
                        continue
                    with open(os.path.join(fd_dir[:-2], "fdinfo", fd), "r") as f:
                        text = f.read()
                except OSError:
                    continue
                pdev = re.search(r"^drm-pdev:\s*(\S+)", text, re.M)
                if pdev and pdev.group(1) != self.slot:
                    continue
                cid = re.search(r"^drm-client-id:\s*(\d+)", text, re.M)
                if not cid or cid.group(1) in clients:
                    continue
                busy, total = {}, {}
                for key, value in re.findall(r"^drm-(?:cycles|engine)-(\w+):\s*(\d+)", text, re.M):
                    if key != "capacity":
                        busy[key] = busy.get(key, 0) + int(value)
                for key, value in re.findall(r"^drm-total-cycles-(\w+):\s*(\d+)", text, re.M):
                    total[key] = max(total.get(key, 0), int(value))
                clients[cid.group(1)] = (busy, total)
        prev = self.prev_fdinfo
        self.prev_fdinfo = (now_ns, clients)
        if not prev:
            return None
        class_busy = {}
        for cid, (busy, total) in clients.items():
            if cid not in prev[1]:
                continue
            pbusy, ptotal = prev[1][cid]
            for cls, value in busy.items():
                db = value - pbusy.get(cls, 0)
                if self.driver == "xe":
                    dt = total.get(cls, 0) - ptotal.get(cls, 0)
                else:
                    dt = now_ns - prev[0]
                if db <= 0 or dt <= 0:
                    continue
                class_busy[cls] = class_busy.get(cls, 0) + db / dt
        return min(1.0, max(class_busy.values())) if class_busy else 0.0


def find_gpus():
    gpus = []
    seen = set()
    for card in sorted(glob.glob("/sys/class/drm/card[0-9]*")):
        if "-" in os.path.basename(card):
            continue
        dev_class = read(os.path.join(card, "device", "class"), "")
        if not dev_class.startswith("0x03"):
            continue
        gpu = Gpu(card)
        if gpu.slot in seen:
            continue
        seen.add(gpu.slot)
        gpus.append(gpu)
    return gpus


def pick_gpu(gpus, wanted):
    if not gpus:
        return None
    for gpu in gpus:
        if gpu.slot == wanted:
            return gpu
    rank = {"nvidia": 3, "amd": 2, "intel": 1}
    return max(gpus, key=lambda g: (g.discrete, rank.get(g.vendor, 0)))


# ───────────────────────────────────────────────────────────── MangoHud FPS

LOG_NAME = re.compile(r"^(.*)_(\d{4}-\d{2}-\d{2})_(\d{2}-\d{2}-\d{2})\.csv$")


def percentile(sorted_values, pct):
    if not sorted_values:
        return None
    k = (len(sorted_values) - 1) * pct
    lo = math.floor(k)
    hi = math.ceil(k)
    if lo == hi:
        return sorted_values[int(k)]
    return sorted_values[lo] + (sorted_values[hi] - sorted_values[lo]) * (k - lo)


class MangoLog:
    def __init__(self, folders, window, stale_after=3.0):
        self.folders = [f for f in folders if f]
        self.window = window
        self.stale_after = stale_after
        self.path = None
        self.handle = None
        self.buffer = ""
        self.columns = None
        self.sysinfo_keys = None
        self.sysinfo = {}
        self.samples = deque()
        self.last_row = {}
        self.last_fps = None
        self.last_frametime = None
        self.last_data_at = 0
        self.started_at = None
        self.process = ""
        self.frametimes = deque(maxlen=150)
        for folder in self.folders:
            try:
                os.makedirs(folder, exist_ok=True)
            except OSError:
                pass
        self.prune()

    def prune(self, max_age=2 * 86400):
        cutoff = time.time() - max_age
        for folder in self.folders:
            try:
                for entry in os.scandir(folder):
                    if entry.name.endswith(".csv") and entry.stat().st_mtime < cutoff:
                        os.unlink(entry.path)
            except OSError:
                pass

    def newest(self):
        best = None
        for folder in self.folders:
            try:
                for entry in os.scandir(folder):
                    if not entry.name.endswith(".csv") or "summary" in entry.name:
                        continue
                    mtime = entry.stat().st_mtime
                    if best is None or mtime > best[0]:
                        best = (mtime, entry.path, entry.name)
            except OSError:
                continue
        return best

    def open(self, path, name):
        if self.handle:
            self.handle.close()
        self.path = path
        self.handle = open(path, "rb")
        self.buffer = ""
        self.columns = None
        self.sysinfo_keys = None
        self.sysinfo = {}
        self.samples.clear()
        self.frametimes.clear()
        self.last_row = {}
        self.last_fps = None
        self.last_frametime = None
        match = LOG_NAME.match(name)
        self.process = match.group(1) if match else os.path.splitext(name)[0]
        self.skip_to_tail()
        self.started_at = None
        if match:
            try:
                stamp = time.strptime(f"{match.group(2)} {match.group(3)}", "%Y-%m-%d %H-%M-%S")
                self.started_at = time.mktime(stamp)
            except ValueError:
                pass

    def skip_to_tail(self, tail=32 * 1024):
        """Read the header, then jump near the end of a log opened mid-game.

        Old rows would otherwise all land in the statistics window at once.
        """
        header = self.handle.read(4096)
        cut = header.find(b"\nfps,")
        end = header.find(b"\n", cut + 1) if cut != -1 else -1
        if end == -1:
            self.handle.seek(0)
            return
        for line in header[:end].decode("utf-8", "replace").split("\n"):
            self._line(line.strip(), time.monotonic())
        size = os.fstat(self.handle.fileno()).st_size
        offset = max(end + 1, size - tail)
        self.handle.seek(offset)
        if offset > end + 1:
            self.handle.readline()  # drop the partial row we landed in

    def poll(self):
        if not self.folders:
            return {"active": False}
        newest = self.newest()
        now_wall = time.time()
        if newest is None or now_wall - newest[0] > self.stale_after:
            if self.handle:
                self.handle.close()
                self.handle = None
                self.path = None
            return {"active": False}
        if newest[1] != self.path:
            try:
                self.open(newest[1], newest[2])
            except OSError:
                return {"active": False}
        chunk = self.handle.read().decode("utf-8", "replace")
        if chunk:
            self.buffer += chunk
            lines = self.buffer.split("\n")
            self.buffer = lines.pop()
            now = time.monotonic()
            for line in lines:
                self._line(line.strip(), now)
        now = time.monotonic()
        while self.samples and now - self.samples[0][0] > self.window:
            self.samples.popleft()
        if self.last_fps is None:
            return {"active": False, "process": self.process}

        frametimes = sorted(ft for _, ft in self.samples if ft > 0)
        out = {
            "active": True,
            "process": self.process,
            "fps": self.last_fps,
            "frametime": self.last_frametime,
            "frametimes": [round(ft, 2) for ft in self.frametimes],
            "elapsed": round(now_wall - self.started_at) if self.started_at else None,
            "driver": self.sysinfo.get("driver", ""),
            "gpu": self.sysinfo.get("gpu", ""),
        }
        if frametimes:
            out["avg"] = 1000 * len(frametimes) / sum(frametimes)
            out["low1"] = 1000 / percentile(frametimes, 0.99)
            out["low01"] = 1000 / percentile(frametimes, 0.999)
            out["min"] = 1000 / frametimes[-1]
            out["max"] = 1000 / frametimes[0]
        extras = {}
        for key in ("cpu_power", "gpu_power", "cpu_temp", "gpu_temp", "gpu_core_clock", "gpu_mem_clock", "gpu_vram_used", "gpu_load", "cpu_load"):
            if key in self.last_row:
                extras[key] = self.last_row[key]
        out["extras"] = extras
        return out

    def _line(self, line, now):
        if not line or line.startswith("-"):
            return
        fields = line.split(",")
        if fields[0] == "os":
            self.sysinfo_keys = fields
            return
        if self.sysinfo_keys is not None and self.columns is None and fields[0] != "fps":
            self.sysinfo = dict(zip(self.sysinfo_keys, fields))
            self.sysinfo_keys = None
            return
        if fields[0] == "fps":
            self.columns = fields
            return
        if not self.columns:
            return
        row = {}
        for key, value in zip(self.columns, fields):
            try:
                row[key] = float(value)
            except ValueError:
                continue
        fps = row.get("fps")
        frametime = row.get("frametime")
        if fps is None:
            return
        if not frametime and fps > 0:
            frametime = 1000 / fps
        self.last_row = row
        self.last_fps = fps
        self.last_frametime = frametime
        if frametime and frametime > 0:
            self.samples.append((now, frametime))
            self.frametimes.append(frametime)


# ───────────────────────────────────────────────────────────── MangoHud config

STEAM_FLATPAK = "com.valvesoftware.Steam"
FLATPAK_LAYER = "org.freedesktop.Platform.VulkanLayer.MangoHud"
FLATPAK_ROOTS = ("/var/lib/flatpak", os.path.expanduser("~/.local/share/flatpak"))

def flatpak_installed(kind, ref):
    return any(os.path.isdir(os.path.join(root, kind, ref)) for root in FLATPAK_ROOTS)


def mangohud_targets(folder):
    """Every MangoHud config the HUD writes, with the folder its logs land in.

    Flatpak Steam runs MangoHud inside its sandbox: it reads the config from
    the app's own XDG dirs and can only write inside ~/.var/app/<id>, which
    the sandbox sees at the same path.
    """
    targets = [{"kind": "native", "conf": MANGOHUD_CONF, "dir": folder}]
    if folder and flatpak_installed("app", STEAM_FLATPAK):
        app_dir = os.path.expanduser(f"~/.var/app/{STEAM_FLATPAK}")
        targets.append({
            "kind": "steamFlatpak",
            "conf": os.path.join(app_dir, "config", "MangoHud", "MangoHud.conf"),
            "dir": os.path.join(app_dir, "cache", "ii-perf-overlay"),
        })
    return targets


def app_log_dir(app):
    return os.path.expanduser(f"~/.var/app/{app}/cache/ii-perf-overlay")


def app_mangohud_conf(app):
    return os.path.expanduser(f"~/.var/app/{app}/config/MangoHud/MangoHud.conf")


def log_dirs(folder):
    dirs = [t["dir"] for t in mangohud_targets(folder) if t["dir"]]
    # Flatpak games set up from the Games list log inside their own sandbox
    for path in glob.glob(app_log_dir("*")):
        if path not in dirs:
            dirs.append(path)
    return dirs


def os_release():
    info = read("/etc/os-release", "") or ""

    def field(key):
        match = re.search(rf"^{key}=\"?([^\"\n]*)\"?$", info, re.M)
        return match.group(1).lower() if match else ""

    return field("ID"), field("ID_LIKE").split()


def distro_install_command():
    """How to install MangoHud, grouped the way the ii setup groups distros
    (sdata/lib/dist-determine.sh): Arch, Gentoo, Fedora, openSUSE, Debian,
    and everything else through Nix."""
    distro, like = os_release()
    if os.path.exists("/run/ostree-booted"):
        return "rpm-ostree install mangohud"  # Fedora Atomic (Silverblue, Kinoite, Bazzite…)
    if distro in ("arch", "endeavouros", "cachyos") or "arch" in like:
        return "sudo pacman -S mangohud"
    if distro == "gentoo" or "gentoo" in like:
        return "sudo emerge --ask games-util/mangohud"
    if distro == "fedora" or "fedora" in like:
        return "sudo dnf install mangohud"
    if distro.startswith("opensuse") or "opensuse" in like or "suse" in like:
        return "sudo zypper install mangohud"
    if distro in ("debian", "ubuntu") or "debian" in like or "ubuntu" in like:
        return "sudo apt install mangohud"
    return "nix profile install nixpkgs#mangohud"


def block_of(text):
    return text.split(BLOCK_START, 1)[1] if BLOCK_START in text else ""


def mangohud_status(folder):
    targets = mangohud_targets(folder)
    native = targets[0]
    text = read(native["conf"], "") or ""
    configured = BLOCK_START in text and f"output_folder={native['dir']}" in text
    installed = (bool(shutil.which("mangohud"))
                 or bool(glob.glob("/usr/share/vulkan/implicit_layer.d/*[Mm]ango[Hh]ud*.json"))
                 or bool(glob.glob("/usr/lib*/mangohud")) or bool(glob.glob("/usr/lib/*/mangohud")))
    out = {
        "installed": installed,
        "configured": configured,
        "hidden": configured and re.search(r"^no_display\b", block_of(text), re.M) is not None,
        "interval": None,
        "confPath": native["conf"].replace(os.path.expanduser("~"), "~", 1),
        "installCommand": distro_install_command(),
        "steamFlatpak": len(targets) > 1,
        "flatpakLayer": flatpak_installed("runtime", FLATPAK_LAYER),
        "flatpakInstallCommand": f"flatpak install flathub {FLATPAK_LAYER}",
        "flatpakConfigured": False,
    }
    match = re.search(r"^log_interval=(\d+)", block_of(text), re.M)
    if match:
        out["interval"] = int(match.group(1))
    if len(targets) > 1:
        ftext = read(targets[1]["conf"], "") or ""
        out["flatpakConfigured"] = BLOCK_START in ftext and f"output_folder={targets[1]['dir']}" in ftext
    return out


def strip_block(text):
    return re.sub(re.escape(BLOCK_START) + r".*?" + re.escape(BLOCK_END) + r"\n?", "", text, flags=re.S).rstrip("\n")


def write_block(conf, folder, interval, hide):
    os.makedirs(folder, exist_ok=True)
    os.makedirs(os.path.dirname(conf), exist_ok=True)
    text = strip_block(read(conf, "") or "")
    lines = [BLOCK_START,
             f"output_folder={folder}",
             "autostart_log=1",
             f"log_interval={max(1, int(interval))}"]
    if hide:
        lines.append("no_display")
    lines.append(BLOCK_END)
    with open(conf, "w", encoding="utf-8") as f:
        f.write((text + "\n\n" if text else "") + "\n".join(lines) + "\n")


def setup(folder, interval, hide):
    for target in mangohud_targets(folder):
        write_block(target["conf"], target["dir"], interval, hide)


def unsetup(folder):
    for target in mangohud_targets(folder):
        text = read(target["conf"])
        if text is None or BLOCK_START not in text:
            continue
        with open(target["conf"], "w", encoding="utf-8") as f:
            stripped = strip_block(text)
            f.write(stripped + "\n" if stripped else "")


# ───────────────────────────────────────────────────────────── games
#
# MangoHud only runs inside a game that was started with it. The Games list
# makes that the shell's job instead of the user's:
#   steam    native Steam: its launcher entry gets MANGOHUD=1, so every
#            Vulkan / Proton game it starts carries the layer
#   flatpak  `flatpak override --user --env=MANGOHUD=1`, plus a MangoHud
#            config and log folder inside the app's sandbox (Sober, Steam…)
#   prism    Prism Launcher's global wrapper command (Minecraft is OpenGL,
#            which needs `mangohud --dlsym` in front of Java, not the layer)
#   wrap     any other game: its launcher entry runs through `mangohud`
#   guide    Lutris, Heroic, Bottles: they have their own MangoHud switch
# Launcher entries are overridden by a copy in ~/.local/share/applications
# marked with X-II-PerfHud, which `disable` removes again.

OVERRIDE_MARK = "X-II-PerfHud"
PRISM_APP = "org.prismlauncher.PrismLauncher"
PRISM_WRAPPER = "mangohud --dlsym"
GUIDED = ("lutris", "heroic", "bottles")


def data_home():
    return os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share")


def user_apps_dir():
    return os.path.join(data_home(), "applications")


def application_dirs():
    dirs = [user_apps_dir()]
    for base in (os.environ.get("XDG_DATA_DIRS") or "/usr/local/share:/usr/share").split(":"):
        dirs.append(os.path.join(base, "applications"))
    dirs += [os.path.join(data_home(), "flatpak/exports/share/applications"),
             "/var/lib/flatpak/exports/share/applications"]
    seen, out = set(), []
    for d in dirs:
        if d and d not in seen:
            seen.add(d)
            out.append(d)
    return out


def parse_desktop(path):
    entry = {}
    section = None
    for line in (read(path, "") or "").splitlines():
        line = line.strip()
        if line.startswith("["):
            section = line
            continue
        if section != "[Desktop Entry]" or "=" not in line or line.startswith("#"):
            continue
        key, _, value = line.partition("=")
        entry.setdefault(key.strip(), value.strip())
    return entry


def system_desktop(file_id):
    """The launcher entry a user override shadows."""
    for d in application_dirs()[1:]:
        path = os.path.join(d, file_id + ".desktop")
        if os.path.isfile(path):
            return path
    return None


def strip_field_codes(command):
    return re.sub(r"%[fFuUdDnNickvm]", "", command).replace("%%", "%").strip()


def game_method(file_id, entry):
    exec_line = entry.get("Exec", "")
    app = entry.get("X-Flatpak", "")
    lowered = (file_id + " " + exec_line).lower()
    if app == PRISM_APP:
        return "prism-flatpak", app
    if app:
        return "flatpak", app
    if file_id.startswith(PRISM_APP) or "prismlauncher" in lowered:
        return "prism", ""
    if file_id == "steam" or re.match(r"^(\S*/)?steam(\s|$)", strip_field_codes(exec_line)):
        return "steam", ""
    if any(name in lowered for name in GUIDED):
        return "guide", ""
    return "wrap", ""


def flatpak_override_enabled(app):
    for root in (os.path.join(data_home(), "flatpak"), "/var/lib/flatpak"):
        text = read(os.path.join(root, "overrides", app), "") or ""
        if re.search(r"^MANGOHUD=1$", text, re.M):
            return True
    return False


def prism_cfg_path(method):
    if method == "prism-flatpak":
        return os.path.expanduser(f"~/.var/app/{PRISM_APP}/data/PrismLauncher/prismlauncher.cfg")
    return os.path.join(data_home(), "PrismLauncher", "prismlauncher.cfg")


def prism_wrapper(path):
    match = re.search(r"^WrapperCommand=(.*)$", read(path, "") or "", re.M)
    return match.group(1).strip() if match else ""


def prism_running():
    try:
        return subprocess.run(["pgrep", "-xi", "prismlauncher"], capture_output=True).returncode == 0
    except OSError:
        return False


def game_enabled(file_id, method, app):
    if method in ("flatpak",):
        return flatpak_override_enabled(app)
    if method in ("prism", "prism-flatpak"):
        return prism_wrapper(prism_cfg_path(method)).startswith(PRISM_WRAPPER)
    if method in ("steam", "wrap"):
        return OVERRIDE_MARK in (read(os.path.join(user_apps_dir(), file_id + ".desktop"), "") or "")
    return False


def find_games():
    games, seen = [], set()
    for d in application_dirs():
        try:
            names = sorted(os.listdir(d))
        except OSError:
            continue
        for name in names:
            if not name.endswith(".desktop"):
                continue
            file_id = name[:-len(".desktop")]
            if file_id in seen:
                continue
            entry = parse_desktop(os.path.join(d, name))
            if not entry or entry.get("NoDisplay", "").lower() == "true" or entry.get("Hidden", "").lower() == "true":
                continue
            categories = entry.get("Categories", "").split(";")
            exec_line = entry.get("Exec", "")
            known = file_id in ("steam", "com.valvesoftware.Steam", "org.vinegarhq.Sober") or file_id.startswith(PRISM_APP)
            # Steam's per-game shortcuts are covered by Steam itself
            if "steam://rungameid" in exec_line or not (known or "Game" in categories):
                continue
            seen.add(file_id)
            method, app = game_method(file_id, entry)
            games.append({
                "id": file_id,
                "name": entry.get("Name", file_id),
                "icon": entry.get("Icon", ""),
                "method": method,
                "app": app,
                "enabled": game_enabled(file_id, method, app),
                "needsLayer": method in ("flatpak", "prism-flatpak") and not flatpak_installed("runtime", FLATPAK_LAYER),
            })
    order = {"steam": 0, "flatpak": 1, "prism": 1, "prism-flatpak": 1, "wrap": 2, "guide": 3}
    games.sort(key=lambda g: (order.get(g["method"], 9), g["name"].lower()))
    return games


def write_override(file_id, prefix):
    user = os.path.join(user_apps_dir(), file_id + ".desktop")
    existing = read(user)
    if existing is not None and OVERRIDE_MARK in existing:
        return
    source = existing if existing is not None else read(system_desktop(file_id) or "", None)
    if source is None:
        raise RuntimeError("no-entry")
    lines = []
    for line in source.splitlines():
        if line.startswith("Exec=") and not line[5:].startswith(prefix):
            line = "Exec=" + prefix + line[5:]
        lines.append(line)
        if line.strip() == "[Desktop Entry]" and not any(l.startswith(OVERRIDE_MARK) for l in lines[:-1]):
            lines.append(f"{OVERRIDE_MARK}={'created' if existing is None else 'edited'}")
    os.makedirs(user_apps_dir(), exist_ok=True)
    with open(user, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")


def remove_override(file_id, prefix):
    user = os.path.join(user_apps_dir(), file_id + ".desktop")
    text = read(user)
    if text is None or OVERRIDE_MARK not in text:
        return
    if f"{OVERRIDE_MARK}=created" in text:
        os.unlink(user)
        return
    lines = []
    for line in text.splitlines():
        if line.startswith(OVERRIDE_MARK):
            continue
        if line.startswith("Exec=" + prefix):
            line = "Exec=" + line[5 + len(prefix):]
        lines.append(line)
    with open(user, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")


def set_prism_wrapper(path, enable):
    text = read(path, "") or ""
    current = prism_wrapper(path)
    if enable:
        value = current if current.startswith(PRISM_WRAPPER) else f"{PRISM_WRAPPER} {current}".strip()
    else:
        value = current[len(PRISM_WRAPPER):].strip() if current.startswith(PRISM_WRAPPER) else current
    line = f"WrapperCommand={value}"
    if re.search(r"^WrapperCommand=", text, re.M):
        text = re.sub(r"^WrapperCommand=.*$", lambda _: line, text, count=1, flags=re.M)
    elif "[General]" in text:
        text = text.replace("[General]", "[General]\n" + line, 1)
    else:
        text = (text.rstrip("\n") + "\n" if text else "") + line + "\n"
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write(text if text.endswith("\n") else text + "\n")


def ensure_logging(folder):
    """Turn on the HUD's logging block if the user skipped that step."""
    if folder and not mangohud_status(folder)["configured"]:
        setup(folder, 100, True)


def native_block_settings(folder):
    text = block_of(read(MANGOHUD_CONF, "") or "")
    match = re.search(r"^log_interval=(\d+)", text, re.M)
    return (int(match.group(1)) if match else 100), re.search(r"^no_display\b", text, re.M) is not None


def set_game(file_id, enable, folder):
    game = next((g for g in find_games() if g["id"] == file_id), None)
    if game is None:
        raise RuntimeError("no-entry")
    method, app = game["method"], game["app"]
    if enable:
        ensure_logging(folder)
    interval, hide = native_block_settings(folder)
    if method == "steam":
        (write_override if enable else remove_override)(file_id, "env MANGOHUD=1 ")
    elif method == "wrap":
        (write_override if enable else remove_override)(file_id, "mangohud ")
    elif method in ("flatpak", "prism-flatpak"):
        if method == "flatpak":
            flag = "--env=MANGOHUD=1" if enable else "--unset-env=MANGOHUD"
            subprocess.run(["flatpak", "override", "--user", flag, app], check=True, capture_output=True)
        if enable:
            write_block(app_mangohud_conf(app), app_log_dir(app), interval, hide)
        else:
            text = read(app_mangohud_conf(app))
            if text and BLOCK_START in text:
                with open(app_mangohud_conf(app), "w", encoding="utf-8") as f:
                    stripped = strip_block(text)
                    f.write(stripped + "\n" if stripped else "")
    if method in ("prism", "prism-flatpak"):
        if prism_running():
            raise RuntimeError("prism-running")
        set_prism_wrapper(prism_cfg_path(method), enable)
    if method == "guide":
        raise RuntimeError("guided")


def launch_game(file_id, folder):
    game = next((g for g in find_games() if g["id"] == file_id), None)
    if game is None:
        raise RuntimeError("no-entry")
    ensure_logging(folder)
    if game["method"] in ("prism", "prism-flatpak", "flatpak") and not game["enabled"]:
        set_game(file_id, True, folder)
    path = os.path.join(user_apps_dir(), file_id + ".desktop")
    entry = parse_desktop(path if os.path.isfile(path) else system_desktop(file_id) or "")
    args = shlex.split(strip_field_codes(entry.get("Exec", "")))
    if not args:
        raise RuntimeError("no-entry")
    env = dict(os.environ, MANGOHUD="1")
    if game["method"] == "flatpak" and "run" in args:
        args.insert(args.index("run") + 1, "--env=MANGOHUD=1")
    elif game["method"] in ("wrap", "guide") and args[0] != "mangohud":
        args = ["mangohud"] + args
    subprocess.Popen(args, env=env, start_new_session=True,
                     stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


# ───────────────────────────────────────────────────────────── main

def run(args):
    parent = os.getppid()
    cpu = Cpu()
    gpus = find_gpus()
    gpu = pick_gpu(gpus, args.gpu)
    mango = MangoLog(log_dirs(args.mangohud_dir), args.window)

    emit({
        "t": "devices",
        "cpu": {"model": cpu.model, "threads": cpu.threads, "hasPower": cpu.energy is not None},
        "gpus": [g.describe() for g in gpus],
        "selectedGpu": gpu.slot if gpu else "",
        "mangohud": mangohud_status(args.mangohud_dir),
    })

    interval = max(250, args.interval) / 1000
    tick = 0
    while True:
        if os.getppid() != parent:
            return
        now = time.monotonic()
        sample = {
            "t": "sample",
            "cpu": cpu.sample(now),
            "ram": memory_sample(),
            "gpu": gpu.sample(now) if gpu else None,
            "fps": mango.poll(),
        }
        if tick % 10 == 0:
            sample["mangohud"] = mangohud_status(args.mangohud_dir)
        emit(sample)
        tick += 1
        elapsed = time.monotonic() - now
        time.sleep(max(0.05, interval - elapsed))


def main():
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="cmd", required=True)
    p_run = sub.add_parser("run")
    p_run.add_argument("--interval", type=int, default=1000)
    p_run.add_argument("--gpu", default="auto")
    p_run.add_argument("--mangohud-dir", default="")
    p_run.add_argument("--window", type=float, default=30)
    p_setup = sub.add_parser("setup")
    p_setup.add_argument("--dir", required=True)
    p_setup.add_argument("--interval", type=int, default=100)
    p_setup.add_argument("--hide-hud", action="store_true")
    p_unsetup = sub.add_parser("unsetup")
    p_unsetup.add_argument("--dir", default="")
    p_status = sub.add_parser("status")
    p_status.add_argument("--dir", required=True)
    p_games = sub.add_parser("games")
    p_games.add_argument("--dir", default="")
    for name in ("enable", "disable", "launch"):
        p_game = sub.add_parser(name)
        p_game.add_argument("id")
        p_game.add_argument("--dir", default="")
    args = parser.parse_args()

    try:
        if args.cmd == "run":
            run(args)
        elif args.cmd == "setup":
            setup(args.dir, args.interval, args.hide_hud)
            emit(mangohud_status(args.dir))
        elif args.cmd == "unsetup":
            unsetup(args.dir)
            emit(mangohud_status(args.dir))
        elif args.cmd == "status":
            emit(mangohud_status(args.dir))
        elif args.cmd in ("games", "enable", "disable", "launch"):
            error = ""
            try:
                if args.cmd in ("enable", "disable"):
                    set_game(args.id, args.cmd == "enable", args.dir)
                elif args.cmd == "launch":
                    launch_game(args.id, args.dir)
            except RuntimeError as e:
                error = str(e)
            except (OSError, subprocess.SubprocessError) as e:
                error = "failed"
                sys.stderr.write(f"{args.cmd} {getattr(args, 'id', '')}: {e}\n")
            emit({"games": find_games(), "error": error, "action": args.cmd,
                  "id": getattr(args, "id", ""), "layerCommand": f"flatpak install flathub {FLATPAK_LAYER}",
                  "mangohud": mangohud_status(args.dir) if args.dir else None})
    except (BrokenPipeError, KeyboardInterrupt):
        pass


if __name__ == "__main__":
    main()
