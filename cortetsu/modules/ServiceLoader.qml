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
    }
}
