import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';

// Settings → Pantalla arrangement helpers.
const source = fs.readFileSync(new URL('../../cortetsu/modules/settings/display/DisplayLayout.js', import.meta.url), 'utf8');
const layout = vm.createContext({});
vm.runInContext(source.replace(/^\.pragma library$/m, ''), layout);
const plain = value => JSON.parse(JSON.stringify(value));

const modes = ['1920x1080@144.00Hz', '1920x1080@60.00Hz', '1680x1050@144.00Hz', '2560x1440@59.95Hz', '1280x720@60.00Hz'];
assert.deepEqual(plain(layout.parseMode('1920x1080@144.00Hz')), {width: 1920, height: 1080, refresh: 144});
assert.deepEqual(plain(layout.resolutions(modes)), ['2560x1440', '1920x1080', '1680x1050', '1280x720'], 'largest first, no repeats');
assert.deepEqual(plain(layout.rates(modes, '1920x1080')), [144, 60]);
assert.equal(layout.modeFor(modes, '1920x1080', 120), '1920x1080@144.00Hz', 'the nearest listed rate');
assert.equal(layout.modeFor(modes, '2560x1440', 144), '2560x1440@59.95Hz', 'never a rate the output did not list');
assert.equal(layout.currentMode({width: 1920, height: 1080, refresh_hz: 60.02, available_modes: modes}), '1920x1080@60.00Hz');

const panel = {name: 'eDP-1', enabled: true, mode: '1920x1080@144.00Hz', x: 1920, y: 0, scale: 1, transform: 0};
const hdmi = {name: 'HDMI-A-1', enabled: true, mode: '1920x1080@60.00Hz', x: 0, y: 0, scale: 1, transform: 0};
assert.deepEqual(plain(layout.logicalSize(Object.assign({}, hdmi, {transform: 1}))), {width: 1080, height: 1920}, 'rotation swaps sides');
assert.deepEqual(plain(layout.logicalSize(Object.assign({}, panel, {scale: 1.25}))), {width: 1536, height: 864});
assert.deepEqual(plain(layout.bounds([hdmi, panel])), {minX: 0, minY: 0, width: 3840, height: 1080});

// A drop 40 px short of the edge snaps to it; a drop far away stays put.
assert.deepEqual(plain(layout.snap([hdmi, panel], 1, 1880, 30)), {x: 1920, y: 0});
assert.deepEqual(plain(layout.snap([hdmi, panel], 1, 2400, 500)), {x: 2400, y: 500});

// Shrinking the left output keeps the right one touching it.
const smaller = [Object.assign({}, hdmi, {mode: '1600x900@60.00Hz'}), panel];
assert.equal(layout.reflow([hdmi, panel], smaller, 0)[1].x, 1600);
assert.equal(layout.reflow([hdmi, panel], [hdmi, Object.assign({}, panel, {scale: 2})], 1)[0].x, 0, 'outputs on the left do not move');

const extend = layout.preset([panel, hdmi], 'extend');
assert.ok(extend.ok && extend.selected === 1);
assert.deepEqual(plain(extend.outputs.map(o => [o.name, o.x, o.enabled])), [['eDP-1', 1920, true], ['HDMI-A-1', 0, true]]);
assert.deepEqual(plain(layout.preset([panel, hdmi], 'laptop').outputs.map(o => o.enabled)), [true, false]);
assert.equal(layout.preset([panel], 'external').ok, false, 'no external output, no external preset');
console.log('Settings display layout: 19 checks passed');
