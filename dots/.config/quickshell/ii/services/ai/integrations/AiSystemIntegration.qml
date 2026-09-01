pragma ComponentBehavior: Bound

import QtQuick
import qs.services
import qs.modules.common

/**
 * Safe, read-only projections of live shell state.
 *
 * The assistant receives status, not identifiers: no IP address, SSID, device
 * serial, environment, process argv or full process table leaves these
 * helpers. ResourceUsage owns sampling; this adapter only bounds its DTO.
 */
QtObject {
    id: root

    readonly property int maximumTopProcesses: 5

    function percent(value: var): int {
        const number = Number(value);
        return Number.isFinite(number) ? Math.max(0, Math.min(100, Math.round(number * 100))) : 0;
    }

    function gigabytesFromKilobytes(value: var): real {
        const number = Number(value);
        return Number.isFinite(number) && number > 0 ? Math.round(number / (1024 * 1024) * 10) / 10 : 0;
    }

    function gigabytesFromBytes(value: var): real {
        const number = Number(value);
        return Number.isFinite(number) && number > 0 ? Math.round(number / (1024 * 1024 * 1024) * 10) / 10 : 0;
    }

    function status(): var {
        const hasBattery = Battery.available === true;
        const isWifi = Network.wifiStatus === "connected" || Network.wifiStatus === "connecting";
        return {
            battery: {
                available: hasBattery,
                percent: hasBattery ? root.percent(Battery.percentage) : null,
                charging: hasBattery ? Battery.isCharging === true : false,
                pluggedIn: hasBattery ? Battery.isPluggedIn === true : false
            },
            network: {
                connected: Network.ethernet === true || Network.wifiStatus === "connected",
                type: Network.ethernet === true ? "ethernet" : (isWifi ? "wifi" : "none"),
                status: String(Network.wifiStatus ?? "unknown"),
                wifiEnabled: Network.wifiEnabled === true,
                strength: isWifi ? Math.max(0, Math.min(100, Number(Network.networkStrength ?? 0))) : null
            },
            audio: {
                ready: Audio.ready === true,
                muted: Audio.muted === true,
                volumePercent: root.percent(Audio.value)
            },
            dnd: Notifications.effectiveSilent === true,
            media: {
                available: MprisController.activePlayer !== null,
                playing: MprisController.isPlaying === true
            }
        };
    }

    function health(): var {
        const processes = Array.from(ResourceUsage.topProcesses ?? []).slice(0, root.maximumTopProcesses).map(process => ({
                    name: String(process?.name ?? "").slice(0, 80),
                    cpuPercent: Math.max(0, Number(process?.cpuPercent ?? 0))
                })).filter(process => process.name.length > 0);
        const temp = Number(ResourceUsage.cpuTemp);
        return {
            cpuPercent: root.percent(ResourceUsage.cpuUsage),
            cpuTemperatureC: Number.isFinite(temp) && temp > 0 ? Math.round(temp) : null,
            memory: {
                usedGiB: root.gigabytesFromKilobytes(ResourceUsage.memoryUsed),
                totalGiB: root.gigabytesFromKilobytes(ResourceUsage.memoryTotal),
                percent: root.percent(ResourceUsage.memoryUsedPercentage)
            },
            swap: {
                usedGiB: root.gigabytesFromKilobytes(ResourceUsage.swapUsed),
                totalGiB: root.gigabytesFromKilobytes(ResourceUsage.swapTotal),
                percent: root.percent(ResourceUsage.swapUsedPercentage)
            },
            disk: {
                usedGiB: root.gigabytesFromBytes(ResourceUsage.diskUsed),
                totalGiB: root.gigabytesFromBytes(ResourceUsage.diskTotal),
                percent: root.percent(ResourceUsage.diskUsedPercentage)
            },
            topProcesses: processes
        };
    }

    function bindingKey(binding: var): string {
        return `${Array.from(binding?.mods ?? []).join("+")}+${String(binding?.key ?? "")}`;
    }

    function flattenKeybinds(nodes: var, source: string, section: string, output: var, unbinds: var): void {
        for (const node of Array.from(nodes ?? [])) {
            const currentSection = String(node?.name ?? "").trim() || section;
            for (const binding of Array.from(node?.keybinds ?? [])) {
                if (source === "default" && unbinds.indexOf(root.bindingKey(binding)) >= 0)
                    continue;
                const keys = Array.from(binding?.mods ?? []).concat([String(binding?.key ?? "")])
                    .filter(part => part.length > 0).join("+");
                const action = String(binding?.comment ?? "").trim()
                    || `${String(binding?.dispatcher ?? "").trim()} ${String(binding?.params ?? "").trim()}`.trim();
                if (keys.length > 0 && action.length > 0)
                    output.push({ keys: keys, action: action, section: currentSection, source: source });
            }
            root.flattenKeybinds(node?.children, source, currentSection, output, unbinds);
        }
    }

    function collectUnbinds(nodes: var, output: var): void {
        for (const node of Array.from(nodes ?? [])) {
            for (const binding of Array.from(node?.unbinds ?? []))
                output.push(root.bindingKey(binding));
            root.collectUnbinds(node?.children, output);
        }
    }

    function keybinds(query: var, limit = 12): var {
        const search = String(query ?? "").trim().toLocaleLowerCase();
        if (search.length === 0)
            return [];
        const unbinds = [];
        if (Config.options?.cheatsheet?.filterUnbinds === true) {
            for (const binding of Array.from(HyprlandKeybinds.userKeybinds?.unbinds ?? []))
                unbinds.push(root.bindingKey(binding));
            root.collectUnbinds(HyprlandKeybinds.userKeybinds?.children, unbinds);
        }

        const all = [];
        root.flattenKeybinds(HyprlandKeybinds.defaultKeybinds?.children, "default", "", all, unbinds);
        root.flattenKeybinds(HyprlandKeybinds.userKeybinds?.children, "user", "", all, unbinds);
        return all.filter(binding => `${binding.keys} ${binding.action} ${binding.section}`.toLocaleLowerCase().includes(search))
            .slice(0, Math.max(1, Math.min(20, Number(limit) || 12)));
    }
}
