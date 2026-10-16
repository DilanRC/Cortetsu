/* Virtual keyboard + pointer for nested-compositor tests.
 *
 * Connects to $WAYLAND_DISPLAY only (the nested compositor the test starts),
 * so it can never inject input into the desktop session. Reads commands from
 * stdin, one per line, and answers "ok" after each one is flushed:
 *   key <evdev-code> <1|0>     press/release; modifiers follow xkb state
 *   move <x> <y> <w> <h>       absolute pointer position inside w x h
 *   button <code> <1|0>        e.g. 272 = BTN_LEFT
 */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>
#include <wayland-client.h>
#include <xkbcommon/xkbcommon.h>
#include "virtual-keyboard-unstable-v1-client-protocol.h"
#include "wlr-virtual-pointer-unstable-v1-client-protocol.h"

static struct wl_seat *seat;
static struct zwp_virtual_keyboard_manager_v1 *kb_manager;
static struct zwlr_virtual_pointer_manager_v1 *ptr_manager;

static void global(void *data, struct wl_registry *registry, uint32_t name, const char *interface, uint32_t version) {
    (void)data; (void)version;
    if (!strcmp(interface, wl_seat_interface.name))
        seat = wl_registry_bind(registry, name, &wl_seat_interface, 1);
    else if (!strcmp(interface, zwp_virtual_keyboard_manager_v1_interface.name))
        kb_manager = wl_registry_bind(registry, name, &zwp_virtual_keyboard_manager_v1_interface, 1);
    else if (!strcmp(interface, zwlr_virtual_pointer_manager_v1_interface.name))
        ptr_manager = wl_registry_bind(registry, name, &zwlr_virtual_pointer_manager_v1_interface, 1);
}
static void global_remove(void *data, struct wl_registry *registry, uint32_t name) { (void)data; (void)registry; (void)name; }
static const struct wl_registry_listener registry_listener = { global, global_remove };

static uint32_t now_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint32_t)(ts.tv_sec * 1000 + ts.tv_nsec / 1000000);
}

int main(void) {
    struct wl_display *display = wl_display_connect(NULL);
    if (!display) { fprintf(stderr, "no display\n"); return 1; }
    struct wl_registry *registry = wl_display_get_registry(display);
    wl_registry_add_listener(registry, &registry_listener, NULL);
    wl_display_roundtrip(display);
    if (!seat || !kb_manager || !ptr_manager) { fprintf(stderr, "missing globals\n"); return 1; }

    struct xkb_context *ctx = xkb_context_new(XKB_CONTEXT_NO_FLAGS);
    struct xkb_rule_names names = { .layout = "us" };
    struct xkb_keymap *keymap = xkb_keymap_new_from_names(ctx, &names, XKB_KEYMAP_COMPILE_NO_FLAGS);
    struct xkb_state *state = xkb_state_new(keymap);
    char *text = xkb_keymap_get_as_string(keymap, XKB_KEYMAP_FORMAT_TEXT_V1);
    size_t size = strlen(text) + 1;
    int fd = memfd_create("keymap", MFD_CLOEXEC);
    if (fd < 0 || write(fd, text, size) != (ssize_t)size) { perror("keymap"); return 1; }

    struct zwp_virtual_keyboard_v1 *kb = zwp_virtual_keyboard_manager_v1_create_virtual_keyboard(kb_manager, seat);
    zwp_virtual_keyboard_v1_keymap(kb, WL_KEYBOARD_KEYMAP_FORMAT_XKB_V1, fd, size);
    struct zwlr_virtual_pointer_v1 *ptr = zwlr_virtual_pointer_manager_v1_create_virtual_pointer(ptr_manager, seat);
    wl_display_roundtrip(display);
    puts("ready");
    fflush(stdout);

    char line[256];
    while (fgets(line, sizeof line, stdin)) {
        unsigned a = 0, b = 0, c = 0, d = 0;
        if (sscanf(line, "key %u %u", &a, &b) == 2) {
            zwp_virtual_keyboard_v1_key(kb, now_ms(), a, b);
            xkb_state_update_key(state, a + 8, b ? XKB_KEY_DOWN : XKB_KEY_UP);
            zwp_virtual_keyboard_v1_modifiers(kb,
                xkb_state_serialize_mods(state, XKB_STATE_MODS_DEPRESSED),
                xkb_state_serialize_mods(state, XKB_STATE_MODS_LATCHED),
                xkb_state_serialize_mods(state, XKB_STATE_MODS_LOCKED),
                xkb_state_serialize_layout(state, XKB_STATE_LAYOUT_EFFECTIVE));
        } else if (sscanf(line, "move %u %u %u %u", &a, &b, &c, &d) == 4) {
            zwlr_virtual_pointer_v1_motion_absolute(ptr, now_ms(), a, b, c, d);
            zwlr_virtual_pointer_v1_frame(ptr);
        } else if (sscanf(line, "button %u %u", &a, &b) == 2) {
            zwlr_virtual_pointer_v1_button(ptr, now_ms(), a, b);
            zwlr_virtual_pointer_v1_frame(ptr);
        } else {
            fprintf(stderr, "bad command: %s", line);
            return 2;
        }
        if (wl_display_roundtrip(display) < 0) { fprintf(stderr, "display error\n"); return 1; }
        puts("ok");
        fflush(stdout);
    }
    return 0;
}
