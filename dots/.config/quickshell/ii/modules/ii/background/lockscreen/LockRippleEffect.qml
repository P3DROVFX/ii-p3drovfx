import QtQuick
import qs.modules.common

Item {
    id: lockScreenRippleEffect
    anchors.fill: parent
    z: 100
    clip: true
    visible: rippleAnim.running || activeTimer.running

    property real centerX: width / 2
    property real centerY: height / 2
    property real maxRadius: 0
    property real rippleProgress: 0.0
    property var particles: []

    onRippleProgressChanged: canvas.requestPaint()

    Timer {
        id: activeTimer
        interval: 1900
        repeat: false
    }

    function startRipple(x, y) {
        centerX = width / 2;
        centerY = height / 2;
        maxRadius = Math.sqrt(centerX * centerX + centerY * centerY) * 1.15;

        // Clear particles from previous unlock
        particles = [];

        rippleAnim.restart();
        activeTimer.restart();
    }

    SequentialAnimation {
        id: rippleAnim

        ParallelAnimation {
            NumberAnimation {
                target: lockScreenRippleEffect
                property: "rippleProgress"
                from: 0.0
                to: 1.0
                duration: 1500
                easing.type: Easing.OutQuart
            }
        }
    }

    Canvas {
        id: canvas
        anchors.fill: parent
        renderTarget: Canvas.FramebufferObject

        onPaint: {
            var ctx = getContext("2d");
            ctx.reset();

            var currentRadius = maxRadius * rippleProgress;
            if (currentRadius <= 0) return;

            // 1. Draw Wave (Radial Gradient)
            var grad = ctx.createRadialGradient(centerX, centerY, 0, centerX, centerY, currentRadius);
            grad.addColorStop(0.0, "rgba(255, 255, 255, 0.10)");
            grad.addColorStop(0.65, "rgba(255, 255, 255, 0.10)"); // filled interior
            grad.addColorStop(0.80, "rgba(255, 255, 255, 0.10)");
            grad.addColorStop(0.95, "rgba(255, 255, 255, 0.13)"); // wavefront peak (reduced to 0.25)
            grad.addColorStop(1.0, "rgba(255, 255, 255, 0.0)");

            ctx.fillStyle = grad;
            ctx.globalAlpha = 1.0 - rippleProgress; // Fade out the entire wave as it expands
            ctx.beginPath();
            ctx.arc(centerX, centerY, currentRadius, 0, Math.PI * 2);
            ctx.fill();

            // 2. Spawn particles precisely along the wavefront
            if (rippleProgress < 0.95) {
                var spawnCount = 320; // High count of microscopic sparkles
                for (var i = 0; i < spawnCount; i++) {
                    var angle = Math.random() * Math.PI * 2;
                    // Position particles inside the thick wavefront crest zone
                    var radialVariance = (Math.random() - 0.5) * (currentRadius * 0.12);
                    var r = currentRadius * 0.96 + radialVariance;
                    
                    particles.push({
                        x: centerX + Math.cos(angle) * r,
                        y: centerY + Math.sin(angle) * r,
                        life: 1.0,
                        decay: 0.12 + Math.random() * 0.12, // Disappear almost instantly (4-8 frames)
                        size: 0.3 + Math.random() * 0.7,    // Microscopic size
                        vx: (Math.random() - 0.5) * 0.25,   // Extremely slow drift
                        vy: (Math.random() - 0.5) * 0.25
                    });
                }
            }

            // 3. Update and draw existing particles (using highly optimized fillRect to prevent lag)
            ctx.globalAlpha = 1.0;
            var aliveParticles = [];
            
            for (var j = 0; j < particles.length; j++) {
                var p = particles[j];
                p.x += p.vx;
                p.y += p.vy;
                p.life -= p.decay;

                if (p.life > 0) {
                    ctx.fillStyle = "rgba(255, 255, 255, " + (p.life * 0.35).toFixed(2) + ")";
                    // Using fillRect instead of path creation (beginPath/arc) for massive performance gains
                    ctx.fillRect(p.x - p.size, p.y - p.size, p.size * 2, p.size * 2);
                    aliveParticles.push(p);
                }
            }
            particles = aliveParticles;
        }
    }
}



