import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
pragma Singleton
pragma ComponentBehavior: Bound

/**
 * Handles EasyEffects active state and presets.
 */
Singleton {
    id: root

    property bool available: false
    property bool active: false

    // Detecção se é flatpak ou nativo
    property bool isFlatpak: false

    function fetchAvailability() {
        fetchAvailabilityProc.running = true
    }

    function fetchActiveState() {
        fetchActiveStateProc.running = true
    }

    function disable() {
        disableProc.running = true
    }

    function enable() {
        enableProc.running = true
    }

    function toggle() {
        if (root.active) {
            root.disable()
        } else {
            root.enable()
        }
    }

    // Verifica se EasyEffects está disponível (e se é flatpak)
    Process {
        id: fetchAvailabilityProc
        running: true
        command: ["bash", "-c", "command -v easyeffects 2>/dev/null && echo 'native' || (flatpak info com.github.wwmm.easyeffects > /dev/null 2>&1 && echo 'flatpak') || echo 'none'"]
        stdout: SplitParser {
            onRead: data => {
                const trimmed = data.trim()
                if (trimmed === "flatpak") {
                    root.available = true
                    root.isFlatpak = true
                } else if (trimmed !== "none" && trimmed !== "") {
                    root.available = true
                    root.isFlatpak = false
                }
            }
        }
        onExited: (exitCode, exitStatus) => {
            // Depois de detectar se está disponível, verifica se está ativo
            if (root.available) {
                root.fetchActiveState()
            }
        }
    }

    // Verifica se o processo está rodando
    Process {
        id: fetchActiveStateProc
        running: false
        command: ["bash", "-c", "pgrep -x easyeffects > /dev/null 2>&1"]
        onExited: (exitCode, exitStatus) => {
            root.active = exitCode === 0
        }
    }

    // Processo para desabilitar
    Process {
        id: disableProc
        running: false
        command: ["bash", "-c", root.isFlatpak
            ? "flatpak kill com.github.wwmm.easyeffects 2>/dev/null; pkill -f easyeffects 2>/dev/null; true"
            : "pkill easyeffects 2>/dev/null; true"
        ]
        onExited: (exitCode, exitStatus) => {
            // Aguarda um instante e verifica o estado real
            verifyAfterActionTimer.start()
        }
    }

    // Processo para habilitar
    Process {
        id: enableProc
        running: false
        command: ["bash", "-c", root.isFlatpak
            ? "flatpak run com.github.wwmm.easyeffects --gapplication-service &"
            : "easyeffects --gapplication-service &"
        ]
        onExited: (exitCode, exitStatus) => {
            // Aguarda o processo iniciar e verifica o estado
            verifyAfterActionTimer.start()
        }
    }

    // Timer para verificar estado após ação (enable/disable)
    // Dá tempo para o processo iniciar ou morrer
    Timer {
        id: verifyAfterActionTimer
        interval: 1500
        repeat: false
        onTriggered: {
            root.fetchActiveState()
        }
    }

    // Polling periódico para manter o estado sincronizado com a realidade
    Timer {
        id: pollingTimer
        interval: 5000
        running: root.available
        repeat: true
        onTriggered: {
            root.fetchActiveState()
        }
    }
}
