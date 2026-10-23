import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import {test} from 'node:test';

const path = new URL('../../cortetsu/modules/CortetsuNotificationModel.js', import.meta.url);
const model = vm.createContext({});
if (fs.existsSync(path))
    vm.runInContext(fs.readFileSync(path, 'utf8').replace(/^\.pragma library\s*/, ''), model);
const plain = value => JSON.parse(JSON.stringify(value));
const entry = id => ({id, summary: id});

test('merge freezes the sent base and reconciles concurrent dismissal before advancing saved IDs', () => {
    assert.equal(typeof model.prepareBatch, 'function');
    const base = ['a'];
    const sent = [entry('a'), entry('b')];
    const batch = model.prepareBatch(base, sent);
    base.push('later-base');
    sent.push(entry('after-send'));
    assert.deepEqual(plain(batch), {base_ids: ['a'], entries: [entry('a'), entry('b')]});
    // The native owner saw a concurrent dismissal of a. b was new in this
    // request, and c arrived locally after the request was already sent.
    const result = model.reconcile(batch, [entry('b')]);
    assert.deepEqual(plain(result), {removed: ['a'], savedIds: ['b']});
    assert.deepEqual(['a', 'b', 'c'].filter(id => !result.removed.includes(id)), ['b', 'c']);
});

test('empty owner readback closes only the frozen request and preserves later arrivals', () => {
    assert.equal(typeof model.reconcile, 'function');
    const result = model.reconcile({base_ids: ['a'], entries: [entry('a'), entry('b')]}, []);
    assert.deepEqual(plain(result), {removed: ['a', 'b'], savedIds: []});
    assert.deepEqual(['a', 'b', 'c'].filter(id => !result.removed.includes(id)), ['c']);
    // A successful save of an already cleared list also returns []. It must
    // not turn a notification arriving during that write into a dismissal.
    assert.deepEqual(plain(model.reconcile({base_ids: [], entries: []}, [])), {removed: [], savedIds: []});
});

test('a prior clear does not erase a new notification when the old array is reread', () => {
    assert.equal(typeof model.externalEdit, 'function');
    const result = model.externalEdit([], []);
    assert.deepEqual(plain(result), {removed: [], savedIds: []});
    assert.deepEqual(['after-clear'].filter(id => !result.removed.includes(id)), ['after-clear']);
    assert.deepEqual(plain(model.externalEdit(['a', 'b'], [entry('b')])), {removed: ['a'], savedIds: ['b']});
});

test('malformed history and readback are failures instead of empty successful saves', () => {
    assert.equal(typeof model.parseHistory, 'function');
    for (const text of ['', '{}', 'null', '[{"summary":"no id"}]', '[{"id":"a"},{"id":"a"}]', '[{"id":{}}]'])
        assert.equal(model.parseHistory(text), null, text);
    assert.deepEqual(plain(model.parseHistory('[{"id":7,"summary":"legacy"}]')), [{id: '7', summary: 'legacy'}]);
    assert.equal(model.reconcile({base_ids: [], entries: []}, null), null);
    assert.equal(model.reconcile({base_ids: [], entries: []}, [{id: false}]), null);
    assert.equal(model.parseHistory(JSON.stringify(Array(2049).fill(entry('x')))), null);
});

test('DND accepts only confirmed booleans and exact optional revisions', () => {
    assert.equal(typeof model.parseDnd, 'function');
    assert.deepEqual(plain(model.parseDnd('{"dnd":true}')), {dnd: true});
    assert.deepEqual(plain(model.parseDnd('{"dnd":false,"revision":8}')), {dnd: false, revision: 8});
    for (const text of ['', '{}', '[]', '{"dnd":"false"}', '{"dnd":1}', '{"dnd":true,"revision":1.5}', '{"dnd":false,"revision":9007199254740992}'])
        assert.equal(model.parseDnd(text), null, text);
});

test('clear revisions identify explicit clears without replaying an old clear after restart', () => {
    assert.equal(typeof model.observeClear, 'function');
    const baseline = {revision: 7, pending: false};
    assert.deepEqual(plain(model.observeClear(null, baseline)), {clear: false, state: baseline});
    const pending = {revision: 8, pending: true};
    assert.deepEqual(plain(model.observeClear(baseline, pending)), {clear: true, state: pending});
    const complete = {revision: 8, pending: false};
    assert.deepEqual(plain(model.observeClear(pending, complete)), {clear: false, state: complete});
    assert.equal(model.observeClear(complete, baseline), null);
    for (const invalid of [{revision: -1}, {revision: 0.5}, {revision: 9007199254740992}, {revision: 8, pending: 'false'}])
        assert.equal(model.observeClear(baseline, invalid), null);
    assert.deepEqual(plain(model.prepareBatch(['a'], [entry('a')], 8)),
        {base_ids: ['a'], entries: [entry('a')], clear_revision: 8});
    assert.equal(model.prepareBatch([], [], -1), null);
});

test('popup timeout: -1 means the server default, 0 never expires, positive values are kept', () => {
    assert.equal(typeof model.popupTimeout, 'function');
    // notify-send and most clients send -1 ("let the server decide").
    assert.equal(model.popupTimeout(-1, 5000), 5000);
    assert.equal(model.popupTimeout(-1, 7000), 7000);
    assert.equal(model.popupTimeout(0, 5000), 0);
    assert.equal(model.popupTimeout(1200, 5000), 1200);
    // A broken preference must not turn every default popup into a resident one.
    assert.equal(model.popupTimeout(-1, -3), 5000);
    assert.equal(model.popupTimeout(-1, undefined), 5000);
    assert.equal(model.popupTimeout(undefined, 4000), 4000);
    // "Expire automatically" off: -1 never expires, explicit timeouts still apply.
    assert.equal(model.popupTimeout(-1, 5000, false), 0);
    assert.equal(model.popupTimeout(1200, 5000, false), 1200);
    assert.equal(model.popupTimeout(-1, 5000, true), 5000);
});
