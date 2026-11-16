import QtQuick
import Quickshell
import "../services"

Scope {
    Component.onCompleted: {
        CortetsuAudio;
        CortetsuPower;
        Audio;
        Brightness;
        Players;
        Time;
        CortetsuNotifications;
        CortetsuSpectrum;
        // Applies the saved curve when the opt-in filter-chain node exists;
        // starts no process otherwise.
        CortetsuEqualizer;
    }
}
