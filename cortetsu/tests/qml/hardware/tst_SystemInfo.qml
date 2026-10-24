import QtQuick
import QtTest
import "../../../modules/hardware/SystemInfo.js" as SystemInfo

// The Sistema page of the Hardware Center (Fn+Esc).
TestCase {
    name: "SystemInfo"

    function test_firmware_placeholders_read_as_missing() {
        compare(SystemInfo.clean("  HP \n"), "HP");
        compare(SystemInfo.clean("To Be Filled By O.E.M."), "");
        compare(SystemInfo.clean("Default string"), "");
        compare(SystemInfo.clean(undefined), "");
    }

    function test_bios_date_is_day_first() {
        compare(SystemInfo.biosDate("04/27/2026\n"), "27/04/2026");
        compare(SystemInfo.biosDate("2026-04-27"), "2026-04-27", "unknown formats pass through");
        compare(SystemInfo.biosDate(""), "");
    }

    function test_chassis_names() {
        compare(SystemInfo.chassis("10\n"), "Portátil");
        compare(SystemInfo.chassis("3"), "Sobremesa");
        compare(SystemInfo.chassis("17"), "", "server and rack types stay unnamed");
    }

    function test_report_skips_missing_values() {
        compare(SystemInfo.report([
            { label: "Modelo", value: "Victus" },
            { label: "SKU", value: "" },
            null,
            { label: "BIOS", value: " AMI F.15 " }
        ]), "Modelo: Victus\nBIOS: AMI F.15");
        compare(SystemInfo.report(undefined), "");
    }
}
