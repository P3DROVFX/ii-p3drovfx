import QtQuick
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

Item {
    id: root

    required property string imageSource

    readonly property int status: imgAIsBack ? imgA.status : imgB.status
    // True from a source change until the new image is fully shown; `status` reports the
    // outgoing image until then.
    readonly property bool transitioning: pendingTransition || fadeAnim.running || shaderProgressAnim.running

    property int animationDuration: 1000
    property var fillMode: Image.PreserveAspectCrop
    property bool animated: true
    property bool imgAIsBack: true
    property bool lockAnimationActive: false

    property var sourceSize: Qt.size(0, 0)
    property bool cache: false
    property bool antialiasing: true
    property bool asynchronous: true
    property bool smooth: true
    property bool mipmap: true

    // Shader transition support
    property string transitionShader: ""
    property var shadersPath: ""
    property string activeShader: ""
    property real transitionProgress: 1.0

    readonly property Item fromImage: imgAIsBack ? imgA : imgB
    readonly property Item toImage: imgAIsBack ? imgB : imgA

    onImageSourceChanged: fadeTo(imageSource)
    Component.onCompleted: imgA.source = imageSource

    function fadeTo(newSrc) {
        // quietChange describes this change only, whichever path it takes.
        root._quietPending = root.quietChange;
        root.quietChange = false;
        var back = imgAIsBack ? imgA : imgB;
        var front = imgAIsBack ? imgB : imgA;

        // A real change outranks a re-decode of the picture it replaces.
        if (root.refreshing) {
            root.refreshing = false;
            front.source = "";
        }

        if (newSrc === back.source) {
            root.releasePins();
            return;
        }

        // No previous wallpaper loaded — load directly onto the back image
        // instead of crossfading, which would swap an empty image on top.
        if (back.source === "" || back.status === Image.Null) {
            back.source = newSrc;
            return;
        }

        root.pendingTransition = false;
        if (fadeAnim.running) {
            fadeAnim.stop();
            var oldBack = root.imgAIsBack ? imgA : imgB;
            oldBack.source = "";
            root.imgAIsBack = !root.imgAIsBack;
            back = root.imgAIsBack ? imgA : imgB;
            front = root.imgAIsBack ? imgB : imgA;
        }
        if (shaderProgressAnim.running) {
            shaderProgressAnim.stop();
            var oldBackShader = root.imgAIsBack ? imgA : imgB;
            oldBackShader.source = "";
            root.imgAIsBack = !root.imgAIsBack;
            back = root.imgAIsBack ? imgA : imgB;
            front = root.imgAIsBack ? imgB : imgA;
        }

        front.pinned = false;
        front.source = newSrc;
        front.z = 1;
        back.z = 0;

        if (!root.animated) {
            front.opacity = 1;
            var oldBackDirect = imgAIsBack ? imgA : imgB;
            oldBackDirect.source = "";
            root.imgAIsBack = !root.imgAIsBack;
            return;
        }

        // A full-size wallpaper decodes off-thread, often for longer than the
        // transition lasts. Started now, the animation would play against a
        // blank target and the picture would pop in after it: no change
        // animation at all. Wait for the decode; a cached image is ready now.
        front.opacity = 0;
        if (front.status === Image.Ready || front.status === Image.Error) {
            root.startTransition();
        } else {
            root.pendingTransition = true;
        }
    }

    property bool pendingTransition: false

    // ── Re-decoding the picture on screen ────────────────────────────────────
    // The decode is frozen at source-set (below), which is right for a plane
    // whose size only settles, and wrong for one the user zooms into: a
    // picture decoded at the plane's size and then shown at twice it is
    // visibly soft. refreshDecode() takes the current sourceSize anyway, the
    // way a change of wallpaper would - in the idle image, behind the shown
    // one - and swaps the two only once the new decode is ready. Same picture
    // on both sides, so the swap has nothing to animate and never blanks.
    property bool refreshing: false

    function refreshDecode() {
        if (root.refreshing || root.pendingTransition || fadeAnim.running || shaderProgressAnim.running || root.pinActive)
            return;
        const back = root.imgAIsBack ? imgA : imgB;
        const front = root.imgAIsBack ? imgB : imgA;
        if (String(back.source) === "" || back.status !== Image.Ready)
            return;
        const size = root._captureDecodeSize();
        if (size.width === back.frozenSize.width && size.height === back.frozenSize.height)
            return;
        root.refreshing = true;
        front.opacity = 0;
        front.z = 1;
        back.z = 0;
        front.source = back.source;
        if (front.status === Image.Ready)
            root._finishRefresh();
    }

    function _finishRefresh() {
        const back = root.imgAIsBack ? imgA : imgB;
        const front = root.imgAIsBack ? imgB : imgA;
        root.refreshing = false;
        front.opacity = 1;
        back.source = "";
        root.imgAIsBack = !root.imgAIsBack;
    }

    function onFrontStatusChanged(image) {
        if (root.refreshing && image === root.toImage) {
            if (image.status === Image.Ready) {
                root._finishRefresh();
            } else if (image.status === Image.Error) {
                // The shown picture is untouched; drop the attempt.
                root.refreshing = false;
                image.source = "";
            }
            return;
        }
        if (!root.pendingTransition || image !== root.toImage)
            return;
        if (image.status !== Image.Ready && image.status !== Image.Error)
            return;
        root.pendingTransition = false;
        root.startTransition();
    }

    // A preset holding motion: the transition would play through its stalls.
    // It starts once the hold releases.
    Connections {
        target: GlobalStates
        function onPresetHoldMotionChanged() {
            if (GlobalStates.presetHoldMotion || !root.pendingTransition)
                return;
            const image = root.toImage;
            if (image.status === Image.Ready || image.status === Image.Error) {
                root.pendingTransition = false;
                root.startTransition();
            }
        }
    }

    // The next change shows the same picture (a file rewritten in place):
    // swapped as soon as it has decoded, with no transition to play.
    property bool quietChange: false
    property bool _quietPending: false

    function startTransition() {
        if (root._quietPending) {
            root._quietPending = false;
            const shown = root.toImage;
            const old = root.fromImage;
            shown.opacity = 1;
            old.source = "";
            root.imgAIsBack = !root.imgAIsBack;
            return;
        }
        if (root.animated && GlobalStates.presetHoldMotion) {
            root.pendingTransition = true;
            return;
        }
        var front = root.toImage;
        var back = root.fromImage;
        if (root.animated) {
            if (root.transitionShader !== "") {
                if (root.transitionShader === "random") {
                    let list = ["circle", "circlePit", "circleSelect", "magic", "Peel", "transition", "pixelate", "stripes"];
                    root.activeShader = list[Math.floor(Math.random() * list.length)];
                } else {
                    root.activeShader = root.transitionShader;
                }
                // Standard crossfade animation is skipped; reset opacities to 1.0 so
                // ShaderEffectSource captures the complete images
                front.opacity = 1.0;
                back.opacity = 1.0;
                shaderProgressAnim.restart();
            } else {
                front.opacity = 0;
                fadeAnim.target = front;
                fadeAnim.restart();
            }
        }
    }

    NumberAnimation {
        id: fadeAnim
        property: "opacity"
        from: 0
        to: 1
        duration: root.animationDuration
        easing.type: Easing.InOutQuad

        onFinished: {
            var oldBack = root.imgAIsBack ? imgA : imgB;
            oldBack.source = "";
            root.imgAIsBack = !root.imgAIsBack;
        }
    }

    NumberAnimation {
        id: shaderProgressAnim
        target: root
        property: "transitionProgress"
        from: 0.0
        to: 1.0
        duration: root.animationDuration
        easing.type: Easing.InOutCubic
        onFinished: {
            var front = root.imgAIsBack ? imgB : imgA;
            var back = root.imgAIsBack ? imgA : imgB;
            front.opacity = 1;
            back.opacity = 0;
            back.source = "";
            root.imgAIsBack = !root.imgAIsBack;
            root.activeShader = "";
        }
    }

    // The two ShaderEffectSources keep their item-sized textures alive after a transition even
    // though they are non-live and invisible at rest, so they only exist while a shader
    // transition is in flight. They were never live before the animation started, so capture
    // timing is unchanged.
    Loader {
        id: transitionLoader
        anchors.fill: parent
        z: 2
        active: shaderProgressAnim.running || root.activeShader !== ""

        sourceComponent: Item {
            anchors.fill: parent

            ShaderEffectSource {
                id: fromSource
                // The slot, not the Image: a held picture is moved/turned
                // inside it, and only the slot's capture includes that.
                sourceItem: root.imgAIsBack ? slotA : slotB
                hideSource: shaderProgressAnim.running
                live: shaderProgressAnim.running
                visible: false
            }

            ShaderEffectSource {
                id: toSource
                sourceItem: root.imgAIsBack ? slotB : slotA
                hideSource: shaderProgressAnim.running
                live: shaderProgressAnim.running
                visible: false
            }

            ShaderEffect {
                id: transitionEffect
                anchors.fill: parent
                visible: root.animated && root.activeShader !== "" && shaderProgressAnim.running

                property var source: fromSource
                property var fromImage: fromSource
                property var toImage: toSource
                property real progress: root.transitionProgress
                property real aspectX: width / height
                property real aspectY: 1.0
                property vector2d aspectRatio: Qt.vector2d(aspectX, aspectY)
                property vector2d origin: Qt.vector2d(0.5, 0.5)

                fragmentShader: (root.activeShader !== "" && root.shadersPath !== "")
                    ? root.shadersPath + "/" + root.activeShader + ".frag.qsb"
                    : ""
            }
        }
    }

    // Each image decodes its source exactly once, at the size captured the
    // moment the source is set, and never re-decodes afterwards. A later
    // root.sourceSize change — the plane dimensions settling as a wallpaper
    // switches, briefly passing through 0x0 — must not re-decode an image that
    // is on screen: doing so blanks it to a black texture (the flicker) or
    // updates it in a visible band (the "stretched duplicate"). An empty size
    // falls back to native. sourceSize is already stable when the incoming image
    // is set, so it captures a sound size at once.
    //
    // mipmap is frozen the same way: a mid-flight change (the next wallpaper
    // using a different decode policy) would reload the image that is on
    // screen — the old layer blanking under the crossfade. Each image keeps
    // the value its own decode was taken with.
    function _captureDecodeSize() {
        const s = root.sourceSize;
        return (s && s.width !== 0 && s.height !== 0) ? s : Qt.size(-1, -1);
    }

    // ── Holding the outgoing picture where it is ─────────────────────────────
    // The plane this item fills is laid out from the wallpaper FILE's
    // dimensions, and those change the moment the new file's size is known -
    // before the new picture has decoded, and for the whole transition. Filling
    // the new plane, the old picture was re-cropped, zoomed and re-centred at
    // the click. pinOutgoing() records where each shown picture sits in
    // `pinReference`'s coordinates; until its source is cleared (the transition
    // that replaces it finishes) it is laid out back onto that spot, whatever
    // the plane does around it.
    property Item pinReference: null
    readonly property bool pinActive: imgA.pinned || imgB.pinned

    function pinOutgoing() {
        if (!root.pinReference)
            return;
        root._pin(imgA);
        root._pin(imgB);
        if (root.pinActive)
            pinSafety.restart();
    }

    function releasePins() {
        imgA.pinned = false;
        imgB.pinned = false;
        pinSafety.stop();
    }

    function _pin(img) {
        if (img.pinned || String(img.source) === "")
            return;
        // Three corners: enough for any move, scale, turn or mirror.
        img.pinO = img.mapToItem(root.pinReference, 0, 0);
        img.pinU = img.mapToItem(root.pinReference, img.width, 0);
        img.pinV = img.mapToItem(root.pinReference, 0, img.height);
        img.pinned = true;
    }

    // Everything between `pinReference` and this item that can move it: the
    // owner lists those values here so the held rect is re-mapped in the same
    // binding pass that moves the plane. Following them per frame instead let
    // a frame render between the plane's change and the correction (flicker).
    property var pinDependencies: null

    // The held corners in this item's coordinates, as a size and the matrix
    // that lays a picture of that size onto them.
    function _mapPin(img, deps) {
        if (!root.pinReference)
            return { "w": root.width, "h": root.height, "m": Qt.matrix4x4() };
        const o = root.pinReference.mapToItem(root, img.pinO.x, img.pinO.y);
        const u = root.pinReference.mapToItem(root, img.pinU.x, img.pinU.y);
        const v = root.pinReference.mapToItem(root, img.pinV.x, img.pinV.y);
        const w = Math.max(1e-3, Math.hypot(u.x - o.x, u.y - o.y));
        const h = Math.max(1e-3, Math.hypot(v.x - o.x, v.y - o.y));
        return {
            "w": w,
            "h": h,
            "m": Qt.matrix4x4((u.x - o.x) / w, (v.x - o.x) / h, 0, o.x,
                              (u.y - o.y) / w, (v.y - o.y) / h, 0, o.y,
                              0, 0, 1, 0,
                              0, 0, 0, 1)
        };
    }

    // A path change that never becomes a change of picture (same file, a video
    // painted elsewhere) must not leave the old picture held forever.
    Timer {
        id: pinSafety
        interval: 4000
        repeat: false
        onTriggered: {
            if (root.transitioning)
                restart();
            else
                root.releasePins();
        }
    }

    // Each picture in a slot of its own: the shader captures the slot, so a
    // held picture is captured where it is drawn.
    Item {
        id: slotA
        anchors.fill: parent
        z: imgA.z
        Image {
            id: imgA
            property bool pinned: false
            property point pinO
            property point pinU
            property point pinV
            readonly property var pin: pinned
                ? root._mapPin(imgA, [root.pinDependencies, root.width, root.height])
                : null
            width: pin ? pin.w : root.width
            height: pin ? pin.h : root.height
            transform: Matrix4x4 {
                matrix: imgA.pin ? imgA.pin.m : Qt.matrix4x4()
            }
            fillMode: root.fillMode
            property size frozenSize: Qt.size(-1, -1)
            property bool frozenMipmap: root.mipmap
            sourceSize: frozenSize
            mipmap: frozenMipmap
            onSourceChanged: {
                if (String(imgA.source) === "")
                    imgA.pinned = false;
                imgA.frozenSize = root._captureDecodeSize()
                imgA.frozenMipmap = root.mipmap
            }
            cache: root.cache
            antialiasing: root.antialiasing
            asynchronous: root.asynchronous
            smooth: root.smooth
            onStatusChanged: root.onFrontStatusChanged(imgA)
        }
    }

    Item {
        id: slotB
        anchors.fill: parent
        z: imgB.z
        Image {
            id: imgB
            property bool pinned: false
            property point pinO
            property point pinU
            property point pinV
            readonly property var pin: pinned
                ? root._mapPin(imgB, [root.pinDependencies, root.width, root.height])
                : null
            width: pin ? pin.w : root.width
            height: pin ? pin.h : root.height
            transform: Matrix4x4 {
                matrix: imgB.pin ? imgB.pin.m : Qt.matrix4x4()
            }
            opacity: 0
            fillMode: root.fillMode
            property size frozenSize: Qt.size(-1, -1)
            property bool frozenMipmap: root.mipmap
            sourceSize: frozenSize
            mipmap: frozenMipmap
            onSourceChanged: {
                if (String(imgB.source) === "")
                    imgB.pinned = false;
                imgB.frozenSize = root._captureDecodeSize()
                imgB.frozenMipmap = root.mipmap
            }
            cache: root.cache
            antialiasing: root.antialiasing
            asynchronous: root.asynchronous
            smooth: root.smooth
            onStatusChanged: root.onFrontStatusChanged(imgB)
        }
    }
}
