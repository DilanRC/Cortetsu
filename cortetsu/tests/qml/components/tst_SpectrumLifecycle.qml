import QtQuick
import QtTest
import "../../../services"
import "../../../modules"

// The analyzer is optional and disabled by default. Creating the singleton
// must not spawn cava simply because ServiceLoader eagerly owns it.
TestCase {
    name: "SpectrumLifecycle"
    when: windowShown
    visible: true
    width: 300
    height: 100

    function test_idle_does_not_spawn_cava() {
        verify(!CortetsuConfig.visualiserEnabled);
        verify(!CortetsuSpectrum.shouldRun);
        verify(!CortetsuSpectrum.cavaProcess.running);
        verify(!CortetsuSpectrum.available);
    }
}
