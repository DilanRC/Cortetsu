import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import { test } from 'node:test';

const path = new URL('../../cortetsu/modules/CortetsuPolicyModel.js', import.meta.url);
const model = vm.createContext({});
if (fs.existsSync(path))
    vm.runInContext(fs.readFileSync(path, 'utf8').replace(/^\.pragma library\s*/, ''), model);
const plain = value => JSON.parse(JSON.stringify(value));
const descriptor = { protocol: 'cortetsu.ipc', session_id: 'session-a', session_epoch: 123,
    socket: '/run/user/1000/cortetsu/cortetsu-session-a.sock' };
const snapshot = { mode: 'coordinator', authoritative: true, stream_stale: false,
    activations: { gamemode: { enabled: true, owner_session: 'session-a', manual_override_until_unix_ms: 0 } },
    decisions: [{ rule_id: 'fullscreen-gamemode-on', resource: 'gamemode', operation: 'gamemode.set', outcome: 'applied', reason: '' }] };

test('descriptor is bound to the current session, socket and exact integer epoch', () => {
    assert.equal(typeof model.validDescriptor, 'function');
    assert.equal(model.validDescriptor(descriptor, 'session-a', '/run/user/1000'), true);
    for (const epoch of [0, -0, -1, 1.5, NaN, Infinity, 9007199254740992, '123'])
        assert.equal(model.validDescriptor({...descriptor, session_epoch: epoch}, 'session-a', '/run/user/1000'), false);
    assert.equal(model.validDescriptor(descriptor, 'session-b', '/run/user/1000'), false);
    assert.equal(model.validDescriptor({...descriptor, socket: '/tmp/foreign.sock'}, 'session-a', '/run/user/1000'), false);
    assert.equal(model.validSession('../outside', '/run/user/1000'), false);
    assert.equal(model.validSession('ok', 'relative'), false);
});

test('policy actions use only fixed argv and bounded allowed domains', () => {
    assert.equal(typeof model.commandFor, 'function');
    assert.deepEqual(plain(model.commandFor('enable', 'gamemode')), ['cortetsu-policy', 'enable', 'gamemode']);
    assert.deepEqual(plain(model.commandFor('disable', 'display')), ['cortetsu-policy', 'disable', 'display']);
    assert.deepEqual(plain(model.commandFor('override', 'power', 900)), ['cortetsu-policy', 'override', 'power', '900']);
    assert.deepEqual(plain(model.commandFor('override', 'power', 0)), ['cortetsu-policy', 'override', 'power', '0']);
    assert.deepEqual(plain(model.commandFor('revoke', 'power', 'expired-session')),
        ['cortetsu-policy', 'revoke', 'power', 'expired-session']);
    for (const owner of ['', '--option', '../session', 'old;touch', 'a'.repeat(129), 7, null])
        assert.equal(model.commandFor('revoke', 'power', owner), null);
    for (const domain of ['foo', '--help', 'power;touch /tmp/x', '__proto__', 'Power'])
        assert.equal(model.commandFor('enable', domain), null);
    for (const seconds of [-1, 0.5, '900', Infinity, 604801])
        assert.equal(model.commandFor('override', 'power', seconds), null);
    assert.equal(model.commandFor('eval', 'power'), null);
});

test('snapshot parsing keeps displayed state separate from another session ownership', () => {
    assert.equal(typeof model.normaliseSnapshot, 'function');
    const value = model.normaliseSnapshot(snapshot);
    assert.equal(value.activations.gamemode.enabled, true);
    assert.equal(model.ownedByAnother(value, 'gamemode', 'session-b'), true);
    assert.equal(model.ownedByAnother(value, 'gamemode', 'session-a'), false);
    assert.equal(model.activation(value, 'power').enabled, false);
    for (const body of [null, [], {}, {...snapshot, mode: 'observe'}, {...snapshot, stream_stale: 'false'},
        {...snapshot, activations: {gamemode: {enabled: 'true'}}}])
        assert.equal(model.normaliseSnapshot(body), null);
    assert.equal(model.normaliseSnapshot({...snapshot, decisions: Array(257).fill({})}), null);
    const suppressed = {...snapshot, decisions: [{rule_id: 'no-match', resource: 'power', outcome: 'suppressed', reason: 'NO_MATCH'}]};
    assert.equal(model.normaliseSnapshot(suppressed)?.decisions[0].operation, '');
});

test('hello and responses reject stale negotiation and unknown request ids', () => {
    assert.equal(typeof model.validHello, 'function');
    const ack = {...descriptor, type: 'hello_ack', version: {major: 1, minor: 0}, capabilities: ['snapshot', 'policy.observe', 'explain']};
    assert.equal(model.validHello(ack, descriptor), true);
    assert.equal(model.validHello({...ack, session_epoch: 124}, descriptor), false);
    assert.equal(model.validHello({...ack, capabilities: []}, descriptor), false);
    const reply = {protocol: 'cortetsu.ipc', version: {major: 1, minor: 0}, type: 'response', id: 'wanted', outcome: 'read', body: snapshot};
    assert.equal(model.matchingResponse(reply, 'wanted'), true);
    assert.equal(model.matchingResponse(reply, 'old'), false);
    assert.equal(model.matchingResponse({...reply, version: {major: 2, minor: 0}}, 'wanted'), false);
});

test('actions finish only after authoritative readback of the requested value', () => {
    assert.equal(typeof model.actionConfirmed, 'function');
    const action = {operation: 'enable', domain: 'gamemode', session: 'session-a'};
    assert.equal(model.actionConfirmed(action, snapshot), true);
    assert.equal(model.actionConfirmed({...action, session: 'session-b'}, snapshot), false);
    assert.equal(model.actionConfirmed({...action, operation: 'disable'}, snapshot), false);
    assert.equal(model.actionConfirmed({operation: 'override', domain: 'gamemode', until: 2000}, snapshot), false);
    assert.equal(model.actionConfirmed({operation: 'override', domain: 'gamemode', until: 0}, snapshot), true);
    const revoke = {operation: 'revoke', domain: 'gamemode', expectedOwner: 'expired-session', session: 'session-a'};
    const acknowledged = {domain: 'gamemode', enabled: false, owner_session: '',
        revoked_owner_session: 'expired-session', session_id: 'session-a'};
    assert.equal(model.commandAccepted(revoke, acknowledged), true);
    assert.equal(model.commandAccepted(revoke, {...acknowledged, revoked_owner_session: 'different-owner'}), false);
    assert.equal(model.commandAccepted(revoke, {...acknowledged, owner_session: 'session-a'}), false);
    assert.equal(model.commandAccepted(revoke, {...acknowledged, session_id: 'foreign-caller'}), false);
    const revoked = {...snapshot, activations: {gamemode: {enabled: false, owner_session: '', manual_override_until_unix_ms: 0}}};
    assert.equal(model.actionConfirmed(revoke, revoked), true);
    assert.equal(model.actionConfirmed(revoke, snapshot), false, 'revocation cannot silently transfer consent to caller');
    assert.equal(model.actionConfirmed(revoke, {...revoked, activations: {gamemode: {enabled: true, owner_session: 'new-owner'}}}), false);
});

test('read request builder cannot request mutation or command execution', () => {
    assert.equal(typeof model.readRequest, 'function');
    const req = model.readRequest('snapshot.get', 'req-id', descriptor);
    assert.deepEqual(plain(req.body), {domains: ['coordinator']});
    assert.equal(req.session_id, 'session-a');
    assert.equal(req.session_epoch, 123);
    assert.equal(model.readRequest('system.exec', 'req-id', descriptor), null);
    assert.equal(model.readRequest('explain.get', 'req-id', descriptor, ';bad'), null);
    assert.equal(model.utf8Length('á😀'), 6);
});
