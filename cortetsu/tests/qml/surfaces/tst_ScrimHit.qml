import QtQuick
import QtTest
import "../../../modules/ScrimHit.js" as ScrimHit

// The retained-surfaces scrim forwards a click to the Bottom Hub bell only
// where no panel is: these are the shapes RetainedSurfacesHost hosts.
TestCase {
    name: "ScrimHit"
    width: 400
    height: 300
    // childAt skips items that are not visible, so the scene must be.
    visible: true
    when: windowShown

    Item {
        id: surfaces
        width: 400
        height: 300

        // An open surface: scrim, outside-click area and a centred panel.
        Item {
            id: open
            anchors.fill: parent
            Rectangle { anchors.fill: parent; color: "black"; opacity: 0.3 }
            Item {
                anchors.fill: parent
                MouseArea { anchors.fill: parent }
                Rectangle { id: panel; x: 100; y: 100; width: 200; height: 100 }
            }
        }
        // A closed surface whose panel would cover the bottom-right corner.
        Item {
            id: closed
            anchors.fill: parent
            visible: false
            Rectangle { x: 300; y: 250; width: 100; height: 50 }
        }
        // Calendar: anchored at the bottom centre, smaller than the screen.
        Rectangle {
            id: bottomCentre
            x: 150; y: 260; width: 100; height: 40
            visible: false
        }
    }

    function init() {
        open.visible = true;
        closed.visible = false;
        bottomCentre.visible = false;
    }

    function test_outsidePanelIsBackdrop() {
        verify(ScrimHit.backdropOnly(surfaces, 380, 290));
        verify(ScrimHit.backdropOnly(surfaces, 5, 5));
    }

    function test_panelIsNotBackdrop() {
        verify(!ScrimHit.backdropOnly(surfaces, 150, 150));
        verify(!ScrimHit.backdropOnly(surfaces, panel.x, panel.y));
        verify(ScrimHit.backdropOnly(surfaces, panel.x + panel.width + 1, panel.y + panel.height + 1));
    }

    function test_invisibleSurfaceIsIgnored() {
        verify(ScrimHit.backdropOnly(surfaces, 350, 275));
        closed.visible = true;
        verify(!ScrimHit.backdropOnly(surfaces, 350, 275));
    }

    function test_smallSurfaceCovers() {
        bottomCentre.visible = true;
        verify(!ScrimHit.backdropOnly(surfaces, 200, 280));
        verify(ScrimHit.backdropOnly(surfaces, 380, 280));
    }

    // Guards the test itself: with an invisible scene childAt finds nothing
    // and every point would look like backdrop.
    function test_sceneIsHitTestable() {
        verify(surfaces.childAt(150, 150) === open);
    }

    function test_nothingOpen() {
        open.visible = false;
        verify(ScrimHit.backdropOnly(surfaces, 200, 150));
    }
}
