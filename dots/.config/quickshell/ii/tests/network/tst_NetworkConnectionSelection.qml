import QtQuick
import QtTest
import "../../services/network/NetworkConnectionSelection.js" as ConnectionSelection

TestCase {
    name: "NetworkConnectionSelection"

    function test_wired_profile_wins_when_both_transports_are_connected() {
        compare(ConnectionSelection.preferredConnectionName(
            true, "Wired connection 2", true, "DTEL_PEDRO"
        ), "Wired connection 2");
    }

    function test_wifi_profile_is_used_without_an_active_wired_connection() {
        compare(ConnectionSelection.preferredConnectionName(
            false, "", true, "DTEL_PEDRO"
        ), "DTEL_PEDRO");
    }

    function test_wired_interface_wins_when_both_transports_are_connected() {
        compare(ConnectionSelection.preferredInterface(
            true, "enp0s20f0u11", true, "wlp0s20f3"
        ), "enp0s20f0u11");
    }

    function test_wifi_interface_is_used_without_an_active_wired_connection() {
        compare(ConnectionSelection.preferredInterface(
            false, "", true, "wlp0s20f3"
        ), "wlp0s20f3");
    }

    function test_startup_seed_uses_the_wired_profile_before_wifi() {
        compare(ConnectionSelection.seededConnectionName([
            "Wired connection 2:802-3-ethernet",
            "DTEL_PEDRO:802-11-wireless"
        ]), "Wired connection 2");
    }

    function test_startup_seed_preserves_escaped_colons_in_profile_names() {
        compare(ConnectionSelection.seededConnectionName([
            "Office\\: LAN:802-3-ethernet"
        ]), "Office: LAN");
    }
}
