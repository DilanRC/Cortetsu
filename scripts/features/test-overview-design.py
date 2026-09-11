from pathlib import Path

repo = Path(__file__).resolve().parents[2]
overview = repo / "cortetsu/modules/overview"
overview_content = (overview / "Content.qml").read_text()
legacy = ("Caelestia", "qs.components", "Colours.", "Tokens.", "StyledRect", "StyledText", "StyledClippingRect", "MaterialIcon")

for name in ("Wrapper.qml", "WindowCard.qml", "Content.qml"):
    text = (overview / name).read_text()
    for symbol in legacy:
        assert symbol not in text, f"{name}: {symbol}"

card = (overview / "WindowCard.qml").read_text()
assert "CortetsuDesign.colorSurface" in card
assert "CortetsuText" in card and "CortetsuIcon" in card
assert 'text: qsTr("Selected")' in card and "visible: root.selected" in card
assert "activeFocusOnTab: true" in card
assert 'ToolTip.text: qsTr("Close window")' in card
assert "onPressed: parent.forceActiveFocus()" in card
assert "property real visualScale" in card
assert "scale: 1" in card
assert card.count("scale: root.visualScale") >= 3
assert "Behavior on visualScale" in card
assert "duration: CortetsuDesign.motionFastMs" in card
content_window = (repo / "cortetsu/modules/drawers/ContentWindow.qml").read_text()
assert "color: CortetsuDesign.colorScrim" in content_window
assert "id: viewportBackground" in overview_content
assert "acceptedButtons: Qt.LeftButton" in overview_content
assert "Keys.onSpacePressed" in overview_content
assert "DragHandler" in card
assert "dragHandler.active" in card
assert "CanTakeOverFromAnything" in card

print("PASS: Overview wrapper and window cards use Cortetsu visual primitives")
