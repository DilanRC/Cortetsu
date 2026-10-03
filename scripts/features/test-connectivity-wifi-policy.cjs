const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const path = require('node:path');
const context = vm.createContext({});
vm.runInContext(fs.readFileSync(path.join(__dirname, '../../cortetsu/services/ConnectivityPolicy.js'), 'utf8').replace(/^\.pragma library\s*/, ''), context);
const plain = value => JSON.parse(JSON.stringify(value));
assert.deepEqual(plain(context.splitFields('a\\:b:c\\\\d: trailing ')), ['a:b', 'c\\d', ' trailing ']);
assert.deepEqual(plain(context.splitFields('x:y\\')), ['x', 'y\\']);
const uuid = '12345678-abcd-1234-abcd-123456789012';
const uuid2 = '12345678-abcd-1234-abcd-123456789013';
assert.equal(context.validUuid(uuid), true);
assert.equal(context.validUuid('--help'), false);
const profiles = context.profiles(`${uuid}:Different profile name:802-11-wireless:yes:wlan0\n${uuid2}:Different profile name:802-11-wireless:no:\n${uuid2}:Wired:802-3-ethernet:yes:eno1\n`);
assert.equal(profiles.length, 3);
assert.equal(profiles[0].type, "802-11-wireless");
assert.notEqual(profiles[0].uuid, profiles[1].uuid);
assert.equal(profiles[2].type, "802-3-ethernet");
assert.equal(profiles[0].ssid, ''); // Profile names are not SSIDs.
assert.equal(profiles[1].autoconnect, false);
const aps = context.accessPoints('*:AA\\:BB\\:CC\\:DD\\:EE\\:FF: same SSID :82:5180 MHz:WPA2:wlan0\n:AA\\:BB\\:CC\\:DD\\:EE\\:00: same SSID :42:2412 MHz:WPA2:wlan0');
assert.equal(aps.length, 2);
assert.notEqual(aps[0].bssid, aps[1].bssid);
assert.equal(aps[0].ssid, ' same SSID ');
assert.equal(aps[0].frequency, 5180);
assert.equal(aps[1].active, false);
const props = context.properties('IP4.ADDRESS[1]:192.0.2.1/24\nIP4.DNS[1]:192.0.2.53\nIP4.DNS[2]:192.0.2.54\n802-11-wireless.ssid: trailing \n');
assert.deepEqual(plain(props['IP4.DNS']), ['192.0.2.53', '192.0.2.54']);
assert.equal(props['802-11-wireless.ssid'][0], ' trailing ');
for (const [input, expected] of [[0.83, 83], [83, 83], [-3, 0], [120, 100], [NaN, 0]]) assert.equal(context.strengthPercent(input), expected);
const connecting = context.operation(1, 'connect', {uuid}, 'connecting', 10);
assert.equal(context.confirmed(connecting, {connected: false, uuid}), false);
assert.equal(context.confirmed(connecting, {connected: true, uuid: uuid2}), false);
assert.equal(context.confirmed(connecting, {connected: true, uuid}), true);
assert.equal(connecting.state, 'connecting');
const forgetting = context.operation(2, 'forget', {uuid}, 'forgetting', 20);
assert.equal(context.confirmed(forgetting, {profiles}), false);
assert.equal(context.confirmed(forgetting, {profiles: []}), true);
const autoconnect = context.operation(3, 'autoconnect', {uuid, enabled: false}, 'changing', 30);
assert.equal(context.confirmed(autoconnect, {profiles}), false);
assert.equal(context.confirmed(autoconnect, {profiles: [{uuid, autoconnect: false}]}), true);
const radio = context.operation(4, 'enable', {enabled: false}, 'changing', 40);
assert.equal(context.confirmed(radio, {enabled: true}), false);
assert.equal(context.confirmed(radio, {enabled: false}), true);
const disconnect = context.operation(5, 'disconnect', {}, 'disconnecting', 50);
assert.equal(context.confirmed(disconnect, {connected: true}), false);
assert.equal(context.confirmed(disconnect, {connected: false}), true);
const failed = context.fail(connecting, 'password-required', 'Introduce la contraseña', true);
assert.equal(failed.state, 'auth-required');
assert.equal(failed.id, 1);
assert.equal(failed.startedAt, 10);
assert.equal(connecting.state, 'connecting');
assert.equal(context.commandError('Timeout expired', 3).code, 'timeout');
assert.equal(context.commandError('NetworkManager is not running', 8).code, 'service-unavailable');
assert.equal(context.commandError('unknown connection', 10).retryable, false);
console.log('PASS: Wi-Fi identity, escaped metadata and confirmed operation transitions');

const config = context.ipv4Config('manual', '192.0.2.1/24', '192.0.2.254', '192.0.2.53, 192.0.2.54');
assert.equal(config.addresses[0], '192.0.2.1/24');
assert.equal(config.dns.length, 2);
for (const args of [['manual', '999.1.1.1/24', '', ''], ['manual', '192.0.2.1', '', ''], ['manual', '192.0.2.1/33', '', ''], ['auto', '', '', '1.1.1.1 --help'], ['invalid', '', '', '']]) assert.equal(context.ipv4Config(...args), null);
assert.equal(context.ipv4Config('auto', '', '', '').method, 'auto');
const ipOperation = context.operation(9, 'ipv4', {uuid, config}, 'changing', 90);
assert.equal(context.confirmed(ipOperation, {profiles: [{uuid, ipv4: context.ipv4Config('auto', '', '', '')}]}), false);
assert.equal(context.confirmed(ipOperation, {profiles: [{uuid, ipv4: config}]}), true);

assert.equal(context.hiddenInput('Hidden', 'wpa-psk', 'example-only-passphrase'), true);
assert.equal(context.hiddenInput('Hidden', 'wpa-psk', 'password\nkey:value'), false);
assert.equal(context.hiddenInput('Hidden', 'open', ''), true);
assert.equal(context.hiddenInput('x'.repeat(33), 'open', ''), false);
assert.equal(context.hiddenInput('é'.repeat(17), 'open', ''), false);
assert.equal(context.hiddenInput('Hidden', 'enterprise', 'password'), false);
assert.equal(context.validUuid(context.newUuid()), true);

const wiredDevices = [{name: 'eno1', connected: true}, {name: 'eno2', connected: false}];
assert.equal(context.profileDevice(wiredDevices, {interface: ''}, 'eno2').name, 'eno2');
assert.equal(context.profileDevice(wiredDevices, {interface: 'eno1'}, 'eno2'), null);
assert.equal(context.profileDevice(wiredDevices, {interface: ''}, 'missing'), null);
assert.equal(context.profileDevice(wiredDevices, {interface: 'missing'}, ''), null);
assert.equal(context.profileDevice(wiredDevices, {interface: ''}, '').name, 'eno1');
const hiddenProfile = {uuid, type:'802-11-wireless', ssid:'Hidden', interface:'wlan0', hidden:true, security:'wpa-psk'};
const hiddenFailure = context.fail(context.operation(10, 'connect', {uuid, ssid:'Hidden', device:'wlan0', security:'wpa-psk', createdProfile:true}, 'connecting', 100), 'authentication-failed', 'failed', true);
assert.equal(context.hiddenRetryProfile(hiddenFailure, [hiddenProfile], 'Hidden', 'wlan0', 'wpa-psk').uuid, uuid);
for (const [ssid, device, security] of [['Other','wlan0','wpa-psk'], ['Hidden','wlan1','wpa-psk'], ['Hidden','wlan0','sae']]) assert.equal(context.hiddenRetryProfile(hiddenFailure, [hiddenProfile], ssid, device, security), null);
assert.equal(context.hiddenRetryProfile(hiddenFailure, [], 'Hidden','wlan0','wpa-psk'), null);
assert.equal(context.hiddenRetryProfile(hiddenFailure, [Object.assign({}, hiddenProfile, {ssid:'Changed'})], 'Hidden','wlan0','wpa-psk'), null);
assert.equal(context.hiddenRetryProfile(hiddenFailure, [Object.assign({}, hiddenProfile, {security:'sae'})], 'Hidden','wlan0','wpa-psk'), null);

// Execute the production dispatcher while its profile read is still queued.
const wifiSource = fs.readFileSync(path.join(__dirname, '../../cortetsu/services/ConnectivityWifi.qml'), 'utf8');
const dispatcher = wifiSource.match(/    function connectHidden\([\s\S]*?\n    function disconnectWired/)[0].replace(/\n    function disconnectWired$/, '');
let begins = 0, creations = 0, activations = 0;
const retryContext = vm.createContext({
    Policy: context, operation: plain(hiddenFailure), profiles: [], wifiDevices: [{name:'wlan0'}],
    wifiDevice: {name:'wlan0'}, wifiEnabled:true, hardwareEnabled:true,
    qsTr: text => text,
    begin: () => { begins++; return true; }, fail: () => { throw Error('unexpected failure'); },
    adapter: {profileReadsPending:true, createHidden:()=>{creations++;},
        saveAndActivate:(_id, target)=>{assert.equal(target,uuid);activations++;}}
});
vm.runInContext(dispatcher, retryContext);
retryContext.connectHidden('Hidden','wlan0','example-only-passphrase','wpa-psk');
assert.equal(begins,0);
assert.equal(creations,0);
assert.equal(retryContext.operation.target.uuid,uuid);
retryContext.profiles=[hiddenProfile];
retryContext.adapter.profileReadsPending=false;
retryContext.connectHidden('Hidden','wlan0','example-only-passphrase','wpa-psk');
assert.equal(begins,1);
assert.equal(creations,0);
assert.equal(activations,1);
console.log('PASS: hidden retry waits for metadata and reuses the confirmed UUID');


const connectBody = wifiSource.match(/function connectNetwork\(network, password, profile\) \{[\s\S]*?\n    \}/)[0];
let credentialCalls = [];
const credentialContext = vm.createContext({
    Object, qsTr: message => message, WifiSecurityType: {WpaPsk: 1, Wpa2Psk: 2, Sae: 3},
    containsNetwork: () => true, hardwareEnabled: true, wifiEnabled: true,
    begin: (kind, target) => { credentialContext.operation = {id: 12, target}; return true; },
    fail: code => credentialCalls.push(['fail', code]), observe: () => {},
    adapter: {saveAndActivate: (...args) => credentialCalls.push(['save', ...args]), mutate: (...args) => credentialCalls.push(['activate', ...args])},
});
vm.runInContext(connectBody, credentialContext);
const knownNetwork = {name: 'Fixture', security: 2, known: true, device: {name: 'wlan0'}, connectWithPsk: () => credentialCalls.push(['native-secret']), connect: () => credentialCalls.push(['native-connect'])};
const credentialProfile = {uuid, type: '802-11-wireless', ssid: 'Fixture', interface: 'wlan0'};
credentialContext.profiles = [credentialProfile];
credentialContext.connectNetwork(knownNetwork, 'test-secret', null);
assert.equal(credentialCalls[0][0], 'save');
assert.equal(credentialCalls[0][2], uuid);
assert.equal(credentialContext.operation.target.uuid, uuid);
credentialCalls = [];
credentialContext.profiles = [credentialProfile, Object.assign({}, credentialProfile, {uuid: uuid2})];
credentialContext.connectNetwork(knownNetwork, 'test-secret', null);
assert.deepEqual(credentialCalls, [['fail', 'ambiguous-profile']]);
credentialCalls = [];
credentialContext.profiles = [];
credentialContext.connectNetwork(knownNetwork, 'test-secret', null);
assert.deepEqual(credentialCalls, [['fail', 'ambiguous-profile']]);
credentialCalls = [];
credentialContext.connectNetwork(Object.assign({}, knownNetwork, {known: false}), 'test-secret', null);
assert.deepEqual(credentialCalls, [['native-secret']]);
console.log('PASS: known credentials persist through a unique UUID; ambiguous profiles cannot be overwritten');
