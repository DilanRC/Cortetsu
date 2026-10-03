#!/usr/bin/env python3
"""Validate secret persistence payload and readback without modifying NetworkManager."""
import importlib.util
from pathlib import Path
import subprocess
import sys
import gi

gi.require_version('NM', '1.0')
from gi.repository import NM

repo = Path(__file__).resolve().parents[2]
path = repo / 'cortetsu/services/ConnectivitySecret.py'
spec = importlib.util.spec_from_file_location('connectivity_secret', path)
helper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helper)
uuid = '12345678-abcd-1234-abcd-123456789012'
secret = 'fixture-only-password'
connection = NM.SimpleConnection.new()
settings = NM.SettingConnection.new()
settings.set_property('id', 'Same name, different SSID')
settings.set_property('uuid', uuid)
settings.set_property('type', '802-11-wireless')
settings.set_property('interface-name', 'wlan2')
connection.add_setting(settings)
wireless = NM.SettingWireless.new()
wireless.set_property('ssid', __import__('gi').repository.GLib.Bytes.new(b'Actual SSID'))
connection.add_setting(wireless)
security = NM.SettingWirelessSecurity.new()
security.set_property('key-mgmt', 'wpa-psk')
security.set_property('psk-flags', NM.SettingSecretFlags.AGENT_OWNED | NM.SettingSecretFlags.NOT_SAVED)
connection.add_setting(security)
ipv4 = NM.SettingIP4Config.new()
ipv4.set_property('method', 'manual')
ipv4.add_address(NM.IPAddress.new(2, '192.0.2.2', 24))
connection.add_setting(ipv4)
helper.validate(uuid, secret)
payload = helper.settings_with_password(NM, connection, secret).unpack()
assert payload['802-11-wireless-security'].get('psk-flags', 0) == 0
assert payload['802-11-wireless-security']['psk'] == secret
assert payload['connection']['uuid'] == uuid
assert payload['connection']['interface-name'] == 'wlan2'
assert payload['ipv4']['method'] == 'manual'
assert connection.get_setting_wireless_security().get_psk() is None
assert int(connection.get_setting_wireless_security().get_psk_flags()) == 3
helper.verify_readback(payload, {'802-11-wireless-security': {'psk': secret}}, secret)
for malformed in [{'802-11-wireless-security': {'psk': 'wrong'}}, {}]:
    try:
        helper.verify_readback(payload, malformed, secret)
        raise AssertionError('unconfirmed secret accepted')
    except helper.CredentialError as error:
        assert error.code == 'credential-save-failed'
try:
    helper.verify_readback({'802-11-wireless-security': {'psk-flags': 2}}, {'802-11-wireless-security': {'psk': secret}}, secret)
    raise AssertionError('nonpersistent flag accepted')
except helper.CredentialError:
    pass
for invalid in ['--help', 'profile name']:
    result = subprocess.run([sys.executable, str(path), invalid], input=secret, text=True, capture_output=True, timeout=3)
    assert result.returncode == 2 and result.stderr.strip() == 'profile-invalid'
    assert secret not in result.stdout + result.stderr
security.set_property('key-mgmt', 'wpa-eap')
try:
    helper.settings_with_password(NM, connection, secret)
    raise AssertionError('enterprise secret overwritten')
except helper.CredentialError:
    pass
print('PASS: native libnm serialisation persists PSK flags, preserves profile and requires readback')
