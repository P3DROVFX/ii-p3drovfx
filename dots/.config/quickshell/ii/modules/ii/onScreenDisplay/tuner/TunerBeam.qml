import QtQuick

/**
 * The Tuner's fixed marker: a thin line of light through the tick band, soft sideways and
 * at both ends. Painted once into a texture and again only when its colour changes.
 */
Canvas {
    id: root

    property color color: "white"

    onColorChanged: root.requestPaint()
    onWidthChanged: root.requestPaint()
    onHeightChanged: root.requestPaint()

    onPaint: {
        const ctx = getContext("2d");
        ctx.reset();
        if (root.width <= 0 || root.height <= 0)
            return;
        const c = root.color;
        const tint = a => Qt.rgba(c.r, c.g, c.b, a);

        const across = ctx.createLinearGradient(0, 0, root.width, 0);
        across.addColorStop(0, tint(0));
        across.addColorStop(0.3, tint(0.08));
        across.addColorStop(0.47, tint(0.55));
        across.addColorStop(0.5, tint(1));
        across.addColorStop(0.53, tint(0.55));
        across.addColorStop(0.7, tint(0.08));
        across.addColorStop(1, tint(0));
        ctx.fillStyle = across;
        ctx.fillRect(0, 0, root.width, root.height);

        // Fade both ends of the line.
        ctx.globalCompositeOperation = "destination-in";
        const along = ctx.createLinearGradient(0, 0, 0, root.height);
        along.addColorStop(0, Qt.rgba(0, 0, 0, 0));
        along.addColorStop(0.3, Qt.rgba(0, 0, 0, 1));
        along.addColorStop(0.7, Qt.rgba(0, 0, 0, 1));
        along.addColorStop(1, Qt.rgba(0, 0, 0, 0));
        ctx.fillStyle = along;
        ctx.fillRect(0, 0, root.width, root.height);
    }
}
