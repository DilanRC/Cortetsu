# Sourced by install-cortetsu.sh. See docs/NOTIFICATIONS.md.
# Masks only mako's user unit so its D-Bus activation cannot win
# org.freedesktop.Notifications. Revert: systemctl --user unmask --now mako.service
mask_rival_notification_daemon() {
    local state was_active
    state="$(systemctl --user is-enabled mako.service 2>/dev/null || true)"
    if [[ "$state" == masked ]] || ! systemctl --user cat mako.service >/dev/null 2>&1; then
        return 0
    fi
    was_active="$(systemctl --user is-active mako.service 2>/dev/null || true)"
    if ! systemctl --user mask --now mako.service >/dev/null 2>&1; then
        printf 'WARN: no se pudo enmascarar mako.service; puede competir por las notificaciones\n' >&2
        return 0
    fi
    printf 'Notificaciones: mako.service enmascarada; Cortetsu es el servidor\n'
    if [[ "$was_active" == active ]]; then
        printf 'Notificaciones: reinicia cortetsu-shell para que tome el bus (systemctl --user restart cortetsu-shell)\n'
    fi
}
