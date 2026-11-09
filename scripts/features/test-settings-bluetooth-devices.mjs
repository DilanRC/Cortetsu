import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';

// The Settings Bluetooth helpers: grouping, filters, order, icons and battery.
const source = fs.readFileSync(new URL('../../cortetsu/modules/settings/bluetooth/BluetoothDevices.js', import.meta.url), 'utf8');
const devices = vm.createContext({});
vm.runInContext(source.replace(/^\.pragma library$/m, ''), devices);

const phones = {name: 'Teléfono', address: 'AA', icon: 'phone', paired: true, connected: false};
const buds = {name: 'Auriculares', address: 'BB', icon: 'audio-headphones', paired: true, connected: true,
    batteryAvailable: true, battery: 0.82};
const pad = {name: 'Mando', address: 'CC', icon: 'input-gaming', paired: false, connected: false};
const bare = {name: '', address: '5C:BA:37:01:9E:44', icon: '', paired: false, connected: false};
const bonded = {name: 'Altavoz', address: 'DD', icon: 'audio-card', paired: false, bonded: true, connected: false};
const all = [bare, pad, phones, buds, bonded];

assert.equal(devices.group(buds), 'connected');
assert.equal(devices.group(bonded), 'paired', 'a bonded device counts as paired');
assert.equal(devices.group(pad), 'available');
assert.deepEqual(Array.from(devices.visible(all, 'all', ''), d => d.address), ['BB', 'DD', 'AA', 'CC', '5C:BA:37:01:9E:44'],
    'connected first, then paired, then new; unnamed devices last in their group');
assert.deepEqual(Array.from(devices.visible(all, 'paired', ''), d => d.address), ['BB', 'DD', 'AA']);
assert.deepEqual(Array.from(devices.visible(all, 'new', ''), d => d.address), ['CC', '5C:BA:37:01:9E:44']);
assert.deepEqual(Array.from(devices.visible(all, 'all', '9e:44'), d => d.address), ['5C:BA:37:01:9E:44'], 'search matches the address');
assert.deepEqual(Array.from(devices.visible(all, 'all', 'MANDO'), d => d.address), ['CC'], 'search ignores case');
assert.equal(devices.count(all, 'all'), 5);
assert.equal(devices.count(all, 'paired'), 3);
assert.equal(devices.count(all, 'new'), 2);
assert.equal(devices.displayName(bare), '5C:BA:37:01:9E:44', 'a device without a name shows its address');
assert.equal(devices.icon(buds), 'headphones');
assert.equal(devices.icon(bare), 'bluetooth', 'an unknown class keeps the generic icon');
assert.equal(devices.kind(bare), '', 'an unknown class has no invented kind');
assert.equal(devices.batteryPercent(buds), 82);
assert.equal(devices.batteryPercent(phones), -1, 'no Battery1 interface, no battery');
assert.equal(devices.batteryPercent({batteryAvailable: true, battery: 82}), -1, 'an out-of-range reading is not shown');
assert.equal(devices.batteryPercent(null), -1);
console.log('Settings Bluetooth devices: 19 checks passed');
