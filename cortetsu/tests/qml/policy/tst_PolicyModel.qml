import QtQuick
import QtTest
import "../../../modules/CortetsuPolicyModel.js" as Model

TestCase {
    name: "CortetsuPolicyModel"

    readonly property var descriptor: ({protocol: "cortetsu.ipc", session_id: "fixture-session", session_epoch: 10,
        socket: "/run/user/1000/cortetsu/cortetsu-fixture-session.sock"})

    function test_epoch_and_socket_are_bound_to_the_session() {
        verify(Model.validDescriptor(descriptor, "fixture-session", "/run/user/1000"));
        verify(!Model.validDescriptor(descriptor, "other-session", "/run/user/1000"));
        verify(!Model.validDescriptor(Object.assign({}, descriptor, {session_epoch: 9007199254740992}), "fixture-session", "/run/user/1000"));
        verify(!Model.validDescriptor(Object.assign({}, descriptor, {socket: "/tmp/socket"}), "fixture-session", "/run/user/1000"));
    }
    function test_argv_contains_only_an_allowlisted_domain() {
        compare(Model.commandFor("enable", "notifications"), ["cortetsu-policy", "enable", "notifications"]);
        compare(Model.commandFor("override", "display", 900), ["cortetsu-policy", "override", "display", "900"]);
        compare(Model.commandFor("enable", "notifications; exit"), null);
        compare(Model.commandFor("override", "display", 1.5), null);
        compare(Model.commandFor("revoke", "power", "expired-session"), ["cortetsu-policy", "revoke", "power", "expired-session"]);
        compare(Model.commandFor("revoke", "power", "../session"), null);
    }
    function test_revocation_requires_empty_owner_readback() {
        const action = {operation: "revoke", domain: "power", expectedOwner: "expired-session", session: "fixture-session"};
        const reply = {domain: "power", enabled: false, owner_session: "", revoked_owner_session: "expired-session", session_id: "fixture-session"};
        verify(Model.commandAccepted(action, reply));
        verify(!Model.commandAccepted(action, Object.assign({}, reply, {revoked_owner_session: "new-session"})));
        verify(Model.actionConfirmed(action, {activations: {power: {enabled: false, owner_session: ""}}}));
        verify(!Model.actionConfirmed(action, {activations: {power: {enabled: true, owner_session: "fixture-session"}}}));
    }
    function test_readback_cannot_confirm_another_sessions_activation() {
        const snapshot = Model.normaliseSnapshot({mode: "coordinator", authoritative: true, stream_stale: false,
            activations: {gamemode: {enabled: true, owner_session: "other-session", manual_override_until_unix_ms: 0}}, decisions: []});
        verify(snapshot !== null);
        verify(Model.ownedByAnother(snapshot, "gamemode", "fixture-session"));
        verify(!Model.actionConfirmed({operation: "enable", domain: "gamemode", session: "fixture-session"}, snapshot));
        verify(!Model.actionConfirmed({operation: "disable", domain: "gamemode", session: "fixture-session"}, snapshot));
    }
    function test_only_read_operations_can_cross_the_socket() {
        compare(Model.readRequest("snapshot.get", "id", descriptor).body.domains, ["coordinator"]);
        compare(Model.readRequest("policy.list", "id", descriptor).body, ({}));
        compare(Model.readRequest("notifications.dnd.set", "id", descriptor), null);
        compare(Model.readRequest("explain.get", "id", descriptor, "invalid"), null);
    }
}
