import QtQuick
import QtTest
import "../../modules/ii/sidebarDashboard"

TestCase {
    name: "SidebarGroupAnimation"

    QtObject {
        id: canonicalSpec
        property int duration: 120
        property int type: Easing.BezierSpline
        property var bezierCurve: [0.2, 0.0, 0.0, 1.0, 1.0, 1.0]
    }

    Component {
        id: animationComponent
        SidebarGroupAnimation {
            animationSpec: canonicalSpec
        }
    }

    Component {
        id: animatedHostComponent
        Item {
            property real targetHeight: 20
            property real animatedHeight: targetHeight

            Behavior on animatedHeight {
                SidebarGroupAnimation {
                    animationSpec: canonicalSpec
                }
            }
        }
    }

    function test_tracks_dynamic_group_motion() {
        const animation = createTemporaryObject(animationComponent, this);
        verify(animation !== null);
        compare(animation.duration, canonicalSpec.duration);
        compare(animation.easing.type, canonicalSpec.type);
        compare(
            animation.easing.bezierCurve.join(","),
            canonicalSpec.bezierCurve.join(",")
        );

        canonicalSpec.duration = 360;
        compare(animation.duration, 360);

        canonicalSpec.type = Easing.Linear;
        compare(animation.easing.type, Easing.Linear);

        canonicalSpec.bezierCurve = [0.4, 0.0, 0.2, 1.0, 1.0, 1.0];
        compare(
            animation.easing.bezierCurve.join(","),
            canonicalSpec.bezierCurve.join(",")
        );
    }

    function test_animates_both_directions() {
        canonicalSpec.duration = 80;
        canonicalSpec.type = Easing.BezierSpline;
        canonicalSpec.bezierCurve = [0.2, 0.0, 0.0, 1.0, 1.0, 1.0];

        const host = createTemporaryObject(animatedHostComponent, this);
        verify(host !== null);
        compare(host.animatedHeight, 20);

        host.targetHeight = 80;
        verify(host.animatedHeight < 80);
        tryCompare(host, "animatedHeight", 80, 250);

        host.targetHeight = 10;
        verify(host.animatedHeight > 10);
        tryCompare(host, "animatedHeight", 10, 250);
    }
}
