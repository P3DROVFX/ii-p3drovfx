import QtQuick
import QtTest
import "../../services/network/NmcliDeviceStatus.js" as Nmcli

/**
 * Covers the nmcli reading NetworkFallback publishes on machines whose native
 * NetworkManager backend enumerates no adapter.
 */
TestCase {
    name: "NmcliDeviceStatus"

    readonly property string deviceOutput: [
        "GENERAL.DEVICE:wlp0s20f3",
        "GENERAL.TYPE:wifi",
        "GENERAL.STATE:100 (connected)",
        "GENERAL.CONNECTION:DTEL_PEDRO",
        "GENERAL.HWADDR:66:09:F9:2B:D5:9D",
        "",
        "GENERAL.DEVICE:enp4s0",
        "GENERAL.TYPE:ethernet",
        "GENERAL.STATE:20 (unavailable)",
        "GENERAL.CONNECTION:",
        "GENERAL.HWADDR:04:BF:1B:9C:02:F3",
        "",
        "GENERAL.DEVICE:lo",
        "GENERAL.TYPE:loopback",
        "GENERAL.STATE:100 (connected (externally))",
        "GENERAL.CONNECTION:lo",
        "GENERAL.HWADDR:00:00:00:00:00:00"
    ].join("\n")

    function test_radio_reports_the_software_switch() {
        const radio = Nmcli.parseRadio("enabled:enabled\n");
        compare(radio.enabled, true);
        compare(radio.hardwareEnabled, true);
    }

    function test_radio_off_is_still_hardware_unblocked() {
        const radio = Nmcli.parseRadio("disabled:enabled");
        compare(radio.enabled, false);
        compare(radio.hardwareEnabled, true);
    }

    function test_hardware_block_is_only_the_disabled_rfkill() {
        compare(Nmcli.parseRadio("disabled:disabled").hardwareEnabled, false);
        // "missing" is a machine with no radio, not a block software can lift.
        compare(Nmcli.parseRadio("disabled:missing").hardwareEnabled, true);
    }

    function test_state_drops_the_scale_nmcli_prints_it_on() {
        compare(Nmcli.stateWord("100 (connected)"), "connected");
        compare(Nmcli.stateWord("30 (disconnected)"), "disconnected");
        compare(Nmcli.stateWord("20 (unavailable)"), "unavailable");
        compare(Nmcli.stateWord("10 (unmanaged)"), "unmanaged");
    }

    function test_state_of_a_connection_in_progress_is_still_connecting() {
        compare(Nmcli.stateWord("70 (connecting (getting IP configuration))"), "connecting");
    }

    function test_state_of_an_externally_managed_link_is_still_connected() {
        compare(Nmcli.stateWord("100 (connected (externally))"), "connected");
    }

    function test_devices_are_read_one_block_at_a_time() {
        const rows = Nmcli.parseDevices(deviceOutput);
        compare(rows.length, 3);
        compare(rows[0].device, "wlp0s20f3");
        compare(rows[0].type, "wifi");
        compare(rows[0].state, "connected");
        compare(rows[0].connection, "DTEL_PEDRO");
    }

    function test_hardware_address_keeps_the_colons_nmcli_leaves_unescaped() {
        const rows = Nmcli.parseDevices(deviceOutput);
        compare(rows[0].mac, "66:09:F9:2B:D5:9D");
    }

    function test_a_port_with_no_connection_reports_an_empty_name() {
        const rows = Nmcli.parseDevices(deviceOutput);
        compare(rows[1].connection, "");
        compare(rows[1].state, "unavailable");
    }

    function test_escaped_colons_in_a_profile_name_are_restored() {
        const rows = Nmcli.parseDevices([
            "GENERAL.DEVICE:wlp3s0",
            "GENERAL.TYPE:wifi",
            "GENERAL.STATE:100 (connected)",
            "GENERAL.CONNECTION:Office\\: Guest",
            "GENERAL.HWADDR:AA:BB:CC:DD:EE:FF"
        ].join("\n"));
        compare(rows[0].connection, "Office: Guest");
    }

    function test_a_field_nmcli_drops_does_not_shift_the_next_device() {
        // nmcli leaves a field out entirely rather than printing it empty.
        const rows = Nmcli.parseDevices([
            "GENERAL.DEVICE:p2p-dev-wlp3s0",
            "GENERAL.TYPE:wifi-p2p",
            "GENERAL.STATE:30 (disconnected)",
            "",
            "GENERAL.DEVICE:wlp3s0",
            "GENERAL.TYPE:wifi",
            "GENERAL.STATE:100 (connected)",
            "GENERAL.CONNECTION:Home",
            "GENERAL.HWADDR:AA:BB:CC:DD:EE:FF"
        ].join("\n"));
        compare(rows.length, 2);
        compare(rows[0].connection, "");
        compare(rows[1].device, "wlp3s0");
        compare(rows[1].connection, "Home");
    }

    function test_the_adapter_carrying_the_connection_is_the_one_picked() {
        const rows = Nmcli.parseDevices([
            "GENERAL.DEVICE:wlan0",
            "GENERAL.TYPE:wifi",
            "GENERAL.STATE:30 (disconnected)",
            "GENERAL.CONNECTION:",
            "GENERAL.HWADDR:AA:AA:AA:AA:AA:AA",
            "",
            "GENERAL.DEVICE:wlan1",
            "GENERAL.TYPE:wifi",
            "GENERAL.STATE:100 (connected)",
            "GENERAL.CONNECTION:Home",
            "GENERAL.HWADDR:BB:BB:BB:BB:BB:BB"
        ].join("\n"));
        compare(Nmcli.pickDevice(rows, "wifi").device, "wlan1");
    }

    function test_a_disconnected_adapter_is_still_an_adapter() {
        const rows = Nmcli.parseDevices([
            "GENERAL.DEVICE:wlan0",
            "GENERAL.TYPE:wifi",
            "GENERAL.STATE:30 (disconnected)",
            "GENERAL.CONNECTION:",
            "GENERAL.HWADDR:AA:AA:AA:AA:AA:AA"
        ].join("\n"));
        compare(Nmcli.pickDevice(rows, "wifi").device, "wlan0");
    }

    function test_a_machine_without_the_adapter_reports_none() {
        compare(Nmcli.pickDevice(Nmcli.parseDevices(deviceOutput), "wifi-p2p"), null);
    }

    function test_wifi_p2p_is_not_mistaken_for_the_wifi_adapter() {
        const rows = Nmcli.parseDevices([
            "GENERAL.DEVICE:p2p-dev-wlp3s0",
            "GENERAL.TYPE:wifi-p2p",
            "GENERAL.STATE:30 (disconnected)",
            "GENERAL.CONNECTION:",
            "GENERAL.HWADDR:"
        ].join("\n"));
        compare(Nmcli.pickDevice(rows, "wifi"), null);
    }
}
