import QtQuick
import QtTest
import "../../modules/common/functions/wallpaper_framing.js" as Framing

TestCase {
    name: "WallpaperFraming"

    // Whether every corner of the plane lies inside the drawn picture - the
    // one promise the wallpaper surface needs from layout().
    function covers(planeWidth, planeHeight, frame) {
        const radians = frame.angle * Math.PI / 180;
        const c = Math.cos(radians);
        const s = Math.sin(radians);
        for (const sx of [-1, 1]) {
            for (const sy of [-1, 1]) {
                const px = sx * planeWidth / 2 - frame.x;
                const py = sy * planeHeight / 2 - frame.y;
                const u = px * c + py * s;
                const v = -px * s + py * c;
                if (Math.abs(u) > frame.width / 2 + 1e-6 || Math.abs(v) > frame.height / 2 + 1e-6)
                    return false;
            }
        }
        return true;
    }

    // ── Normalising ───────────────────────────────────────────────────────

    function test_normalize_clamps_everything() {
        const f = Framing.normalize({ "zoom": 0.2, "x": 4, "y": -9, "rotation": 450, "flipH": "yes" });
        compare(f.zoom, Framing.ZOOM_MIN);
        compare(f.x, 1);
        compare(f.y, -1);
        compare(f.rotation, 90);
        compare(f.flipH, false);
    }

    function test_normalize_survives_garbage() {
        const f = Framing.normalize({ "zoom": NaN, "x": "left", "rotation": null });
        verify(Framing.isIdentity(f));
        verify(Framing.isIdentity(Framing.normalize(undefined)));
    }

    function test_rotation_snaps_to_quarters() {
        compare(Framing.snapRotation(-90), 270);
        compare(Framing.snapRotation(89), 90);
        compare(Framing.snapRotation(720), 0);
    }

    // ── Layout ────────────────────────────────────────────────────────────

    // The plane the shell already draws: the picture at its own aspect ratio,
    // exactly the plane's size. An untouched framing must not move a pixel.
    function test_identity_fills_an_image_shaped_plane() {
        const frame = Framing.layout(3840 / 2160 * 1155, 1155, 3840, 2160, Framing.defaults());
        fuzzyCompare(frame.width, 3840 / 2160 * 1155, 1e-6);
        fuzzyCompare(frame.height, 1155, 1e-6);
        compare(frame.x, 0);
        compare(frame.y, 0);
    }

    function test_quarter_turn_swaps_the_cover_axis() {
        // A landscape picture on its side, on a landscape plane: its HEIGHT
        // now has to span the plane's width.
        const frame = Framing.layout(1920, 1080, 1920, 1080, { "rotation": 90 });
        fuzzyCompare(frame.height, 1920, 1e-6);
        compare(frame.angle, 90);
        verify(covers(1920, 1080, frame));
    }

    function test_zoom_and_pan_always_cover() {
        const planes = [[1920, 1080], [2560, 1440], [1080, 1920], [3440, 1440]];
        const images = [[3840, 2160], [1600, 1200], [1080, 1920], [6000, 1000]];
        for (const plane of planes) {
            for (const image of images) {
                for (const rotation of [0, 90, 180, 270]) {
                    for (const pan of [-1, -0.4, 0, 0.7, 1]) {
                        const f = { "zoom": 1.8, "x": pan, "y": -pan, "rotation": rotation };
                        const frame = Framing.layout(plane[0], plane[1], image[0], image[1], f);
                        verify(covers(plane[0], plane[1], frame), JSON.stringify([plane, image, f]));
                    }
                }
            }
        }
    }

    // Half-way through an animated turn a square-on fit no longer reaches the
    // corners; the correction has to.
    function test_mid_turn_is_corrected_to_cover() {
        for (let angle = 0; angle <= 90; angle += 7.5) {
            const frame = Framing.layout(1920, 1080, 3000, 2000, { "zoom": 1.2, "x": 0.8 }, angle);
            verify(covers(1920, 1080, frame), String(angle));
        }
    }

    // ── Gestures ──────────────────────────────────────────────────────────

    function test_pan_drag_right_shows_the_left() {
        const next = Framing.panTo({ "zoom": 2 }, 50, 0, 100, 100, 0);
        compare(next.x, -0.5);
        compare(next.y, 0);
    }

    function test_pan_stops_at_the_wall() {
        const next = Framing.panTo({ "zoom": 2 }, 5000, 0, 100, 100, 0);
        compare(next.x, -1);
        verify(next.atLeft);
    }

    function test_pan_snaps_to_centre() {
        const next = Framing.panTo({ "zoom": 2, "x": 0.5 }, 48, 0, 100, 100, 4);
        compare(next.x, 0);
        verify(next.snappedX);
    }

    function test_pan_snaps_to_the_nearest_target() {
        // Centre at -x * range: x = 0.33 puts it at -33, a target at -30.
        const next = Framing.panTo({ "zoom": 2, "x": 0.5 }, 17, 0, 100, 100, 4, { "x": [-30, 0, 30], "y": [] });
        compare(next.snapIndexX, 0);
        compare(next.x, 0.3);
        verify(!next.snappedY);
    }

    function test_pan_ignores_targets_out_of_reach() {
        const next = Framing.panTo({ "zoom": 2, "x": 0 }, 0, 0, 100, 100, 400, { "x": [500], "y": [500] });
        verify(!next.snappedX);
        verify(!next.snappedY);
    }

    function test_point_offset_turns_then_mirrors() {
        const frame = { "width": 200, "height": 100, "angle": 90, "scaleX": -1, "scaleY": 1 };
        // The picture's right edge, turned a quarter clockwise, points down;
        // the horizontal mirror leaves that alone.
        const p = Framing.pointOffset(frame, 1, 0.5);
        fuzzyCompare(p.x, 0, 1e-9);
        fuzzyCompare(p.y, 100, 1e-9);
        const q = Framing.pointOffset(Object.assign({}, frame, { "angle": 0 }), 1, 0.5);
        fuzzyCompare(q.x, -100, 1e-9);
    }

    function test_pan_without_room_keeps_the_value() {
        const next = Framing.panTo({ "x": 0.3 }, 80, 0, 0, 0, 0);
        compare(next.x, 0.3);
    }

    function test_zoom_keeps_the_point_under_the_pointer() {
        const start = { "zoom": 1.5, "x": 0.2, "y": -0.3 };
        const before = Framing.layout(1920, 1080, 1920, 1080, start);
        const pointer = [300, -120];
        const next = Framing.zoomAt(1920, 1080, 1920, 1080, start, 2.0, pointer[0], pointer[1]);
        const after = Framing.layout(1920, 1080, 1920, 1080, next);
        fuzzyCompare((pointer[0] - before.x) / before.scale, (pointer[0] - after.x) / after.scale, 1e-6);
        fuzzyCompare((pointer[1] - before.y) / before.scale, (pointer[1] - after.y) / after.scale, 1e-6);
    }

    function test_zoom_never_below_cover() {
        compare(Framing.zoomAt(1920, 1080, 1920, 1080, { "zoom": 1.3 }, 0.5, 0, 0).zoom, Framing.ZOOM_MIN);
    }

    function test_four_turns_come_back() {
        let f = { "zoom": 2, "x": 0.4, "y": -0.2 };
        for (let i = 0; i < 4; i++)
            f = Framing.rotateBy(1920, 1080, 3000, 2000, f, 1);
        compare(f.rotation, 0);
        fuzzyCompare(f.x, 0.4, 1e-6);
        fuzzyCompare(f.y, -0.2, 1e-6);
    }

    function test_flip_twice_is_nothing() {
        verify(Framing.isIdentity(Framing.flip(Framing.flip({}, "vertical"), "vertical")));
    }

    function test_animation_takes_the_short_way() {
        compare(Framing.animationTarget(270, 0), 360);
        compare(Framing.animationTarget(0, 270), -90);
        compare(Framing.animationTarget(360, 90), 450);
    }
}
