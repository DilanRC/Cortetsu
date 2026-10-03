pragma Singleton

import ".."
import "../.."
import QtQuick
import Quickshell
import "../../../utils"

Searcher {
    id: root

    function transformSearch(search: string): string {
        return search.slice(`${CortetsuConfig.actionPrefix}variant `.length);
    }

    list: [
        Variant {
            variant: "vibrant"
            icon: "sentiment_very_dissatisfied"
            name: qsTr("Vibrant")
            description: qsTr("Una paleta de croma alto. El croma de la paleta primaria está al máximo.")
        },
        Variant {
            variant: "tonalspot"
            icon: "android"
            name: qsTr("Tonal Spot")
            description: qsTr("Predeterminada para temas Material. Una paleta pastel de croma bajo.")
        },
        Variant {
            variant: "expressive"
            icon: "compare_arrows"
            name: qsTr("Expressive")
            description: qsTr("Una paleta de croma medio. El tono primario cambia respecto al color semilla.")
        },
        Variant {
            variant: "fidelity"
            icon: "compare"
            name: qsTr("Fidelity")
            description: qsTr("Coincide con el color semilla, incluso si es muy brillante y tiene croma alto.")
        },
        Variant {
            variant: "content"
            icon: "sentiment_calm"
            name: qsTr("Content")
            description: qsTr("Casi idéntica a Fidelidad.")
        },
        Variant {
            variant: "fruitsalad"
            icon: "nutrition"
            name: qsTr("Fruit Salad")
            description: qsTr("Un tema divertido. El tono del color semilla no aparece en el tema.")
        },
        Variant {
            variant: "rainbow"
            icon: "looks"
            name: qsTr("Rainbow")
            description: qsTr("Un tema divertido. El tono del color semilla no aparece en el tema.")
        },
        Variant {
            variant: "neutral"
            icon: "contrast"
            name: qsTr("Neutral")
            description: qsTr("Cercana a la escala de grises, con un toque de croma.")
        },
        Variant {
            variant: "monochrome"
            icon: "filter_b_and_w"
            name: qsTr("Monochrome")
            description: qsTr("Todos los colores están en escala de grises, sin croma.")
        }
    ]
    useFuzzy: CortetsuConfig.useFuzzyApps

    component Variant: QtObject {
        required property string variant
        required property string icon
        required property string name
        required property string description

        function onClicked(list: AppList): void {
            list.screenState.launcher = false;
            Quickshell.execDetached(["cortetsu-scheme", "set", "-v", variant]);
        }
    }
}
