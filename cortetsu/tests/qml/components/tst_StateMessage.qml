import QtQuick
import QtQuick.Layouts
import QtTest
import "../../../components"

// A state message used to derive its width from its own content. Inside a
// Layout that gave it no room, the two resized each other without end and
// the window never finished polishing.
TestCase {
    id: testCase
    name: "StateMessage"
    when: windowShown
    visible: true
    width: 400
    height: 300

    Component {
        id: squeezed
        ColumnLayout {
            property alias message: message
            width: 0
            CortetsuStateMessage {
                id: message
                Layout.fillWidth: true
                Layout.fillHeight: true
                title: "No hay redes visibles"
                detail: "Pulsa Actualizar para volver a escanear las redes cercanas"
            }
        }
    }

    Component {
        id: free
        CortetsuStateMessage {
            title: "Sin resultados"
            detail: "Prueba con una categoría, dispositivo o función"
        }
    }

    function test_a_layout_without_room_settles() {
        const layout = createTemporaryObject(squeezed, testCase);
        verify(layout);
        // Reaching this line at all is the regression check: the old
        // component kept the event loop inside polishItems().
        wait(50);
        compare(layout.message.width, 0);
        layout.width = 320;
        tryCompare(layout.message, "width", 320);
    }

    function test_width_is_given_and_height_follows_the_text() {
        const message = createTemporaryObject(free, testCase);
        compare(message.width, 280);
        const tall = message.height;
        verify(tall > 0);
        message.width = 140;
        tryVerify(() => message.height > tall, 1000, "a narrower message wraps onto more lines");
    }
}
