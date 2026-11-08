import QtQuick
import QtTest
import "../../../modules/AudioPolicy.js" as AudioPolicy

TestCase {
    name: "AudioProtection"
    function test_limit_increases_but_allows_decreases() {
        compare(AudioPolicy.request(0.2, 1, 1.5, true, 0.1), 0.3);
        compare(AudioPolicy.request(1, 0.1, 1.5, true, 0.1), 0.1);
        compare(AudioPolicy.request(0.2, 1, 1.5, false, 0.1), 1);
        compare(AudioPolicy.request(0.9, 1.8, 1, true, 0.2), 1);
        compare(AudioPolicy.request(0.2, NaN, 1, true, 0.1), 0.2);
    }
}
