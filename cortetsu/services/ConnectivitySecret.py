#!/usr/bin/env python3
"""Persist a personal Wi-Fi credential by UUID, with the secret only on stdin."""
import re
import sys


class CredentialError(Exception):
    def __init__(self, code, status):
        self.code = code
        self.status = status


def validate(uuid, password):
    if not re.fullmatch(r'[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}', uuid):
        raise CredentialError('profile-invalid', 2)
    if not password or len(password.encode('utf-8')) > 256 or any(c in password for c in '\0\r\n'):
        raise CredentialError('password-invalid', 2)


def settings_with_password(nm, connection, password):
    wireless = connection.get_setting_wireless()
    security = connection.get_setting_wireless_security()
    if not wireless or not security or security.get_key_mgmt() not in ('wpa-psk', 'sae'):
        raise CredentialError('profile-invalid', 2)
    clone = nm.SimpleConnection.new_clone(connection)
    setting = clone.get_setting_wireless_security()
    setting.set_property('psk', password)
    setting.set_property('psk-flags', nm.SettingSecretFlags.NONE)
    try:
        clone.verify()
    except Exception:
        raise CredentialError('profile-invalid', 2) from None
    # Preserve every other setting. libnm omits default zero flags in its payload.
    return clone.to_dbus(nm.ConnectionSerializationFlags.ALL)


def verify_readback(settings, secrets, password):
    security = settings.get('802-11-wireless-security', {})
    stored = secrets.get('802-11-wireless-security', {})
    if int(security.get('psk-flags', 0)) != 0 or stored.get('psk') != password:
        raise CredentialError('credential-save-failed', 4)


def save(uuid, password):
    try:
        import gi
        gi.require_version('NM', '1.0')
        from gi.repository import NM, Gio, GLib
    except (ImportError, ValueError):
        raise CredentialError('service-unavailable', 3) from None
    try:
        client = NM.Client.new(None)
        connection = client.get_connection_by_uuid(uuid)
        if not connection:
            raise CredentialError('profile-invalid', 2)
        settings = settings_with_password(NM, connection, password)
        loop = GLib.MainLoop()
        cancellation = Gio.Cancellable()
        result = {'complete': False, 'failed': False, 'timed_out': False}

        def completed(remote, async_result, _data):
            try:
                remote.update2_finish(async_result)
                result['complete'] = True
            except GLib.Error:
                result['failed'] = True
            loop.quit()

        def deadline():
            result['timed_out'] = True
            cancellation.cancel()
            loop.quit()
            return False

        timer = GLib.timeout_add_seconds(10, deadline)
        connection.update2(settings, NM.SettingsUpdate2Flags.TO_DISK, None, cancellation, completed, None)
        loop.run()
        if not result['timed_out']:
            GLib.source_remove(timer)
        if result['timed_out']:
            raise CredentialError('timeout', 3)
        if not result['complete'] or result['failed']:
            raise CredentialError('credential-save-failed', 4)

        # Read authoritative daemon settings rather than the client's cached copy.
        bus = Gio.bus_get_sync(Gio.BusType.SYSTEM, None)
        reply = bus.call_sync('org.freedesktop.NetworkManager', connection.get_path(),
            'org.freedesktop.NetworkManager.Settings.Connection', 'GetSettings', None,
            GLib.VariantType.new('(a{sa{sv}})'), Gio.DBusCallFlags.NONE, 3000, None)
        secrets = connection.get_secrets('802-11-wireless-security', None)
        verify_readback(reply.unpack()[0], secrets.unpack(), password)
    except CredentialError:
        raise
    except Exception:
        # API/daemon exceptions may contain property values; never print them.
        raise CredentialError('credential-save-failed', 4) from None


def main():
    try:
        if len(sys.argv) != 2:
            raise CredentialError('profile-invalid', 2)
        password = sys.stdin.read(257)
        validate(sys.argv[1], password)
        save(sys.argv[1], password)
        password = ''
        print('CREDENTIAL_SAVED')
        return 0
    except CredentialError as error:
        print(error.code, file=sys.stderr)
        return error.status


if __name__ == '__main__':
    sys.exit(main())
