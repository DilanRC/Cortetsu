#!/usr/bin/env node
// Exercise the actual QML function bodies with a deterministic close timer.
const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const path = require('node:path');
const root = path.resolve(__dirname, '../..');
const read = p => fs.readFileSync(path.join(root, 'cortetsu/modules', p), 'utf8');
const wrapper = read('bar/popouts/Wrapper.qml');
function body(source, name) {
    const start = source.indexOf('function ' + name + '(');
    assert(start >= 0, name);
    const open = source.indexOf('{', start);
    let depth = 1, end = open + 1;
    while (depth) { if (source[end] === '{') depth++; if (source[end] === '}') depth--; end++; }
    return source.slice(open + 1, end - 1);
}
for (const mode of ['network', 'audio', 'traymenu0']) {
    let pending = true;
    const popup = { hasCurrent: true, closing: true, detachedMode: 'any' };
    const context = vm.createContext({ ...popup, closeTimer: { stop() { pending = false; } } });
    popup.cancelClose = () => { vm.runInContext(body(wrapper, 'cancelClose'), context); popup.closing = context.closing; };
    const open = vm.createContext({ popouts: popup, screen: {}, mode, anchorCenter: 720,
        CortetsuShellState: { componentsFor: () => ({ popouts: popup }) },
        closeAllLaunchers() {}, closeAllPanels() {} });
    vm.runInContext('(function() {' + body(read('BottomHub.qml'), 'openAttachedControlNow') + '})()', open);
    assert.equal(pending, false, 'old close must be cancelled even when hasCurrent was already true');
    assert.equal(popup.closing, false);
    assert.equal(popup.currentName, mode);
    assert.equal(popup.detachedMode, '');
    assert.equal(popup.bottomAnchorCenter, 720);
    assert.equal(popup.hasCurrent, true);
}
assert(body(wrapper, 'detach').includes('cancelClose();'), 'detached opening must cancel pending close');
const clip = read('bar/popouts/ClipWrapper.qml');
assert(!clip.includes('scale: 1 - root.offsetScale'), 'never collapse text to zero scale');
assert(clip.includes('content.closing ? CortetsuDesign.motionFastMs'));
assert(wrapper.includes('interval: CortetsuDesign.motionFastMs'));
console.log('PASS: actual opening functions cancel stale close for network, audio and tray; anchors and bounded motion preserved');
