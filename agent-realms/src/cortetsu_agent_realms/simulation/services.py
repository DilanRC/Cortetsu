"""Fake system services on the realm's private bus (facade over power, network, bluetooth).

Only interfaces and members that Quickshell 0.3.2 and Cortetsu use are implemented,
with the real names, paths and D-Bus types.
"""
from .bluetooth import ADAPTER, BATTERY1, BLUEZ, DEVICE1, HCI, OM, BlueZ
from .dbus import PROPS, V, DBusFailure, Exported, Service, iface, method, node, prop, signal
from .network import (NM, NM_ACTIVE, NM_AP, NM_CONN, NM_DEV, NM_PATH, NM_SETTINGS, NM_WIFI, NM_WIRED,
                      NetworkManager)
from .power import DEVICE_IFACE, PP, PP_PATH, UPOWER, UPOWER_PATH, PowerProfiles, UPower

__all__ = ["ADAPTER", "BATTERY1", "BLUEZ", "DEVICE1", "HCI", "OM", "BlueZ", "PROPS", "V", "DBusFailure",
           "Exported", "Service", "iface", "method", "node", "prop", "signal", "NM", "NM_ACTIVE", "NM_AP",
           "NM_CONN", "NM_DEV", "NM_PATH", "NM_SETTINGS", "NM_WIFI", "NM_WIRED", "NetworkManager",
           "DEVICE_IFACE", "PP", "PP_PATH", "UPOWER", "UPOWER_PATH", "PowerProfiles", "UPower"]
