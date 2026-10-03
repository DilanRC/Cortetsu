import QtQuick
import QtTest
import "../../../modules/hardware/Health.js" as Health
import "../../../modules/hardware/Navigation.js" as HardwareNavigation

TestCase {
    name: "HardwareHealth"

    function reading(overrides) {
        return Object.assign({
            cpu: { usage: 12, temp_c: 55 },
            memory: { usage: 40 },
            disk: { usage: 50 },
            battery: { present: true, percent: 80, status: "Discharging" },
            gpus: [{ vendor: "AMD", temp_c: 50 }, { vendor: "NVIDIA", temp_c: 48 }]
        }, overrides || {});
    }

    function test_no_reading_is_unknown_not_ok() {
        compare(Health.evaluate({}).level, "unknown");
        compare(Health.evaluate(null).level, "unknown");
        compare(Health.evaluate({}).issues.length, 0);
    }

    function test_ordinary_reading_is_ok() {
        const result = Health.evaluate(reading());
        compare(result.level, "ok");
        compare(result.issues.length, 0);
    }

    function test_thresholds_are_inclusive() {
        compare(Health.evaluate(reading({ disk: { usage: 89.9 } })).level, "ok");
        const warning = Health.evaluate(reading({ disk: { usage: 90 } }));
        compare(warning.level, "attention");
        compare(warning.issues[0].severity, "warning");
        compare(Health.evaluate(reading({ disk: { usage: 96 } })).level, "critical");
    }

    function test_issue_names_metric_value_and_destination() {
        const issue = Health.evaluate(reading({ disk: { usage: 93.4 } })).issues[0];
        compare(issue.id, "disk");
        compare(issue.kind, "disk");
        compare(issue.value, 93.4);
        compare(issue.target, "io");
        verify(HardwareNavigation.pages[issue.target] !== undefined);
    }

    function test_every_target_is_a_page() {
        const result = Health.evaluate(reading({
            cpu: { temp_c: 99 },
            memory: { usage: 97 },
            disk: { usage: 97 },
            battery: { present: true, percent: 5, status: "Discharging" },
            gpus: [{ vendor: "AMD", temp_c: 95 }]
        }));
        compare(result.issues.length, 5);
        for (const issue of result.issues)
            verify(HardwareNavigation.pages[issue.target] !== undefined, issue.id);
    }

    function test_missing_sensor_is_not_an_issue() {
        const result = Health.evaluate(reading({
            cpu: { usage: 10, temp_c: null },
            gpus: [{ vendor: "AMD" }]
        }));
        compare(result.level, "ok");
    }

    function test_each_gpu_is_reported_on_its_own() {
        const result = Health.evaluate(reading({
            gpus: [{ vendor: "AMD", temp_c: 60 }, { vendor: "NVIDIA", temp_c: 88 }]
        }));
        compare(result.issues.length, 1);
        compare(result.issues[0].id, "gpu-temp-1");
        compare(result.issues[0].label, "NVIDIA");
    }

    function test_low_battery_only_matters_while_discharging() {
        const low = { present: true, percent: 8, status: "Charging" };
        compare(Health.evaluate(reading({ battery: low })).level, "ok");
        low.status = "Discharging";
        compare(Health.evaluate(reading({ battery: low })).level, "critical");
        compare(Health.evaluate(reading({ battery: { present: false } })).level, "ok");
    }

    function test_critical_issues_come_first() {
        const result = Health.evaluate(reading({
            cpu: { temp_c: 91 },
            disk: { usage: 97 }
        }));
        compare(result.level, "critical");
        compare(result.issues[0].id, "disk");
        compare(result.issues[1].id, "cpu-temp");
    }
}
