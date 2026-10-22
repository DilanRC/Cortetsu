pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../../../theme"
import "../controls"

ColumnLayout {
    id: root
    required property var context
    readonly property var bridge: context.policies
    readonly property var domains: [
        {id: "notifications", title: qsTr("Notificaciones automáticas"), detail: qsTr("Activa No molestar en pantalla completa y lo desactiva al salir")},
        {id: "gamemode", title: qsTr("Modo de juego automático"), detail: qsTr("Activa el modo de juego en pantalla completa y lo desactiva al salir")},
        {id: "power", title: qsTr("Energía automática"), detail: qsTr("Ahorra energía con batería baja y restaura el perfil equilibrado al conectar la corriente")},
        {id: "display", title: qsTr("Reglas de pantalla"), detail: qsTr("Permite las reglas de pantalla que hayas configurado; no incluye reglas predeterminadas")}
    ]
    spacing: CortetsuDesign.spacingSection

    function domainTitle(domain: string): string {
        return domains.find(item => item.id === domain)?.title || domain;
    }
    function decisionLabel(decision: var): string {
        const outcome = String(decision.outcome || "").toUpperCase();
        return outcome === "APPLIED" ? qsTr("Aplicada")
            : outcome === "UNCHANGED" ? qsTr("Ya aplicado")
            : outcome === "SELECTED" ? qsTr("Seleccionada")
            : outcome === "BLOCKED" ? qsTr("En espera")
            : outcome === "OBSERVED" ? qsTr("Observada") : decision.outcome;
    }
    function decisionReason(decision: var): string {
        const reason = decision.reason;
        return reason === "MANUAL_OVERRIDE" ? qsTr("Pausada para respetar tu ajuste manual")
            : reason === "NO_VERIFIED_RUST_OWNER" || reason === "OWNER_UNAVAILABLE" ? qsTr("El servicio no está disponible o falta activación")
            : reason === "STATE_STALE" || reason === "EVENT_EXPIRED" ? qsTr("Esperando información actualizada")
            : reason === "STABILIZING" ? qsTr("Esperando que se estabilice el cambio")
            : reason === "COOLDOWN" ? qsTr("Esperando antes de repetir la acción")
            : reason === "CONSENT_REVOKED" ? qsTr("La automatización se ha desactivado")
            : reason === "RUST_READBACK_VERIFIED" || reason === "OWNER_REVISION_VERIFIED" ? qsTr("El servicio confirmó el resultado")
            : reason === "ALREADY_SATISFIED" ? qsTr("El ajuste ya tenía el valor solicitado")
            : reason === "APPLY_VERIFICATION_FAILED" ? qsTr("No se pudo confirmar el resultado")
            : reason || decision.rule_id;
    }

    SettingsGroup {
        title: qsTr("Coordinador")
        detail: qsTr("La activación pertenece a esta sesión")
        SettingValueRow {
            objectName: "policyConnection"
            title: qsTr("Conexión")
            value: root.bridge?.statusText || qsTr("No disponible")
            detail: qsTr("Cada dominio requiere tu activación. Los ajustes manuales conservan prioridad")
            attention: !root.bridge?.usable
        }
        SettingActionRow {
            objectName: "policyRefresh"
            title: qsTr("Actualizar estado y reglas")
            actionLabel: qsTr("Actualizar")
            actionIcon: "refresh"
            disabled: !root.bridge
            onActivated: root.bridge.refreshStatus()
        }
        SettingValueRow {
            objectName: "policyError"
            visible: (root.bridge?.lastError || root.bridge?.readError || "").length > 0
            title: qsTr("Último intento")
            detail: root.bridge?.lastError || root.bridge?.readError || ""
            attention: true
        }
    }

    Repeater {
        model: root.domains
        delegate: SettingsGroup {
            id: domainGroup
            required property var modelData
            readonly property var activation: root.bridge?.activation(modelData.id)
                || {enabled: false, owner_session: "", manual_override_until_unix_ms: 0}
            readonly property bool foreignOwner: root.bridge?.ownedByAnother(modelData.id) || false
            readonly property bool busy: root.bridge?.pendingDomain === modelData.id
            readonly property bool paused: activation.manual_override_until_unix_ms > Date.now()
            readonly property int ruleCount: (root.bridge?.rules || []).filter(rule => rule && rule.resource === modelData.id && rule.enabled).length
            title: modelData.title
            detail: root.bridge?.rulesLoaded ? qsTr("%1 reglas disponibles").arg(ruleCount) : ""

            SettingToggleRow {
                objectName: `policy-${domainGroup.modelData.id}`
                title: qsTr("Automatizar en esta sesión")
                Accessible.name: qsTr("Activar %1 en esta sesión").arg(domainGroup.modelData.title)
                Accessible.description: detail
                detail: domainGroup.foreignOwner ? qsTr("Autorizado en otra sesión. Puedes revocar esa autorización antes de activar esta sesión")
                    : domainGroup.modelData.detail
                checked: domainGroup.activation.enabled
                disabled: !root.bridge?.canChange || domainGroup.foreignOwner
                status: domainGroup.busy ? "busy" : root.bridge?.actionErrorDomain === domainGroup.modelData.id ? "error" : ""
                statusText: domainGroup.busy ? qsTr("Comprobando el estado guardado") : root.bridge?.lastError || ""
                onToggled: value => root.bridge.setDomainEnabled(domainGroup.modelData.id, value)
            }
            SettingActionRow {
                objectName: `policy-revoke-${domainGroup.modelData.id}`
                visible: domainGroup.foreignOwner
                title: qsTr("Revocar autorización de esa sesión")
                detail: qsTr("Mantiene los ajustes actuales. Después puedes activar la automatización en esta sesión")
                actionLabel: qsTr("Revocar")
                accessibleName: qsTr("Revocar autorización de %1 en la otra sesión").arg(domainGroup.modelData.title)
                actionIcon: "link_off"
                disabled: !root.bridge?.canChange
                onActivated: root.bridge.revokeDomain(domainGroup.modelData.id, domainGroup.activation.owner_session)
            }
            SettingActionRow {
                objectName: `policy-pause-${domainGroup.modelData.id}`
                title: domainGroup.paused ? qsTr("Pausa manual hasta %1").arg(Qt.formatTime(new Date(domainGroup.activation.manual_override_until_unix_ms), "HH:mm"))
                    : qsTr("Pausar quince minutos")
                detail: qsTr("Mantiene tus ajustes actuales mientras está en pausa")
                actionLabel: domainGroup.paused ? qsTr("Reanudar") : qsTr("Pausar")
                accessibleName: (domainGroup.paused ? qsTr("Reanudar %1") : qsTr("Pausar %1 durante quince minutos")).arg(domainGroup.modelData.title)
                actionIcon: domainGroup.paused ? "play_arrow" : "pause"
                disabled: !root.bridge?.canChange || !domainGroup.activation.enabled || domainGroup.foreignOwner
                onActivated: root.bridge.overrideDomain(domainGroup.modelData.id, domainGroup.paused ? 0 : 900)
            }
        }
    }

    SettingsGroup {
        title: qsTr("Decisiones recientes")
        detail: qsTr("Qué ocurrió y por qué")
        SettingValueRow {
            objectName: "policyNoDecisions"
            visible: (root.bridge?.snapshot?.decisions || []).length === 0
            title: qsTr("Sin decisiones recientes")
            detail: qsTr("Las decisiones aparecerán al cambiar el estado del escritorio")
        }
        Repeater {
            model: (root.bridge?.snapshot?.decisions || []).slice(-12).reverse()
            delegate: SettingValueRow {
                required property var modelData
                title: root.domainTitle(modelData.resource)
                value: root.decisionLabel(modelData)
                detail: root.decisionReason(modelData)
                attention: modelData.reason === "APPLY_VERIFICATION_FAILED"
            }
        }
    }
}
