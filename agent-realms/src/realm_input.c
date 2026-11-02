#define _GNU_SOURCE
#include <errno.h>
#include <sys/mman.h>
#include <limits.h>
#include <linux/input-event-codes.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <wayland-client.h>
#include "virtual-keyboard-unstable-v1-client-protocol.h"
#include "wlr-virtual-pointer-unstable-v1-client-protocol.h"

struct realm_input {
    struct wl_display *display;
    struct wl_registry *registry;
    struct wl_seat *seat;
    struct zwlr_virtual_pointer_manager_v1 *manager;
    struct zwlr_virtual_pointer_v1 *pointer;
    struct zwp_virtual_keyboard_manager_v1 *keyboard_manager;
};

static void fail(const char *message) {
    fprintf(stderr, "agent-realm pointer: %s\n", message);
    exit(2);
}

static void on_global(void *data, struct wl_registry *registry, uint32_t name,
                      const char *interface, uint32_t version) {
    struct realm_input *state = data;
    if (!strcmp(interface, wl_seat_interface.name) && !state->seat) {
        state->seat = wl_registry_bind(registry, name, &wl_seat_interface,
                                       version < 1 ? version : 1);
    } else if (!strcmp(interface, zwlr_virtual_pointer_manager_v1_interface.name) && !state->manager) {
        uint32_t supported = version < 2 ? version : 2;
        state->manager = wl_registry_bind(registry, name,
                                          &zwlr_virtual_pointer_manager_v1_interface,
                                          supported);
    } else if (!strcmp(interface, zwp_virtual_keyboard_manager_v1_interface.name) && !state->keyboard_manager) {
        state->keyboard_manager = wl_registry_bind(registry, name,
                                                   &zwp_virtual_keyboard_manager_v1_interface, 1);
    }
}

// The realm has no physical keyboard. Each `type`/`key` brings its own
// short-lived virtual keyboard; when it goes away Hyprland is left with no
// keyboard at all and the next one hands focus back to the window instead of
// an Exclusive layer (a launcher lost every key after the first command). An
// idle keyboard held for the realm's lifetime plays the part of the built-in one.
static void keep_idle_keyboard(struct realm_input *state) {
    static const char keymap[] =
        "xkb_keymap { xkb_keycodes { include \"evdev\" }; xkb_types { include \"complete\" }; "
        "xkb_compat { include \"complete\" }; xkb_symbols { include \"pc+us+inet(evdev)\" }; };";
    if (!state->keyboard_manager) {
        fputs("agent-realm pointer: sin zwp_virtual_keyboard_manager_v1; no hay teclado inactivo\n", stderr);
        return;
    }
    int fd = memfd_create("agent-realm-keymap", MFD_CLOEXEC);
    if (fd < 0 || write(fd, keymap, sizeof keymap) != (ssize_t)sizeof keymap)
        fail("no se pudo preparar el keymap del teclado inactivo");
    struct zwp_virtual_keyboard_v1 *keyboard =
        zwp_virtual_keyboard_manager_v1_create_virtual_keyboard(state->keyboard_manager, state->seat);
    zwp_virtual_keyboard_v1_keymap(keyboard, WL_KEYBOARD_KEYMAP_FORMAT_XKB_V1, fd, sizeof keymap);
    close(fd);
}

static void on_global_remove(void *data, struct wl_registry *registry, uint32_t name) {
    (void)data;
    (void)registry;
    (void)name;
}

static uint32_t now_ms(void) {
    struct timespec ts;
    if (clock_gettime(CLOCK_MONOTONIC, &ts) != 0)
        fail("clock_gettime failed");
    return (uint32_t)(((uint64_t)ts.tv_sec * 1000u) + (uint64_t)ts.tv_nsec / 1000000u);
}

static void pause_ms(long ms) {
    struct timespec req = { .tv_sec = ms / 1000, .tv_nsec = (ms % 1000) * 1000000L };
    while (nanosleep(&req, &req) != 0 && errno == EINTR) {}
}

static uint32_t button_code(const char *value) {
    if (!strcmp(value, "left")) return BTN_LEFT;
    if (!strcmp(value, "right")) return BTN_RIGHT;
    if (!strcmp(value, "middle")) return BTN_MIDDLE;
    if (!strcmp(value, "back")) return BTN_SIDE;
    if (!strcmp(value, "forward")) return BTN_EXTRA;
    fail("botón inválido; usa left, right, middle, back o forward");
    return BTN_LEFT;
}

static long number(const char *value, const char *label) {
    char *end = NULL;
    errno = 0;
    long parsed = strtol(value, &end, 10);
    if (errno || !end || *end || parsed < 0)
        fail(label);
    return parsed;
}

static void motion(struct realm_input *state, long x, long y, long width, long height) {
    if (width < 1 || height < 1 || x >= width || y >= height)
        fail("coordenadas fuera del tamaño del escritorio");
    zwlr_virtual_pointer_v1_motion_absolute(state->pointer, now_ms(), (uint32_t)x, (uint32_t)y,
                                            (uint32_t)width, (uint32_t)height);
    zwlr_virtual_pointer_v1_frame(state->pointer);
}

static void button(struct realm_input *state, uint32_t code, uint32_t pressed) {
    zwlr_virtual_pointer_v1_button(state->pointer, now_ms(), code, pressed);
    zwlr_virtual_pointer_v1_frame(state->pointer);
}

static void scroll_axis(struct realm_input *state, uint32_t axis, long value) {
    if (!value) return;
    if (value > INT32_MAX / 256 || value < INT32_MIN / 256)
        fail("desplazamiento fuera del rango Wayland");
    zwlr_virtual_pointer_v1_axis_source(state->pointer, WL_POINTER_AXIS_SOURCE_WHEEL);
    zwlr_virtual_pointer_v1_axis(state->pointer, now_ms(), axis, wl_fixed_from_int((int)value));
    long steps = value / 120;
    if (!steps) steps = value > 0 ? 1 : -1;
    if (steps > INT_MAX) steps = INT_MAX;
    if (steps < INT_MIN) steps = INT_MIN;
    zwlr_virtual_pointer_v1_axis_discrete(state->pointer, now_ms(), axis,
                                         wl_fixed_from_int((int)value), (int32_t)steps);
}

static void sync_or_fail(struct realm_input *state) {
    if (wl_display_roundtrip(state->display) < 0)
        fail("la sesión Wayland virtual cerró la conexión");
}

static void usage(void) {
    fputs("uso: realm-input move X Y W H | click X Y W H BUTTON [COUNT] | "
          "drag X1 Y1 X2 Y2 W H BUTTON | scroll X Y W H DX DY | keep\n", stderr);
    exit(2);
}

int main(int argc, char **argv) {
    if (argc < 2) usage();
    struct realm_input state = {0};
    state.display = wl_display_connect(NULL);
    if (!state.display)
        fail("no se pudo conectar a WAYLAND_DISPLAY del realm");
    state.registry = wl_display_get_registry(state.display);
    if (!state.registry)
        fail("wl_display_get_registry falló");
    static const struct wl_registry_listener listener = {
        .global = on_global,
        .global_remove = on_global_remove,
    };
    wl_registry_add_listener(state.registry, &listener, &state);
    sync_or_fail(&state);
    if (!state.seat || !state.manager)
        fail("la sesión no ofrece wl_seat y zwlr_virtual_pointer_manager_v1");
    state.pointer = zwlr_virtual_pointer_manager_v1_create_virtual_pointer(state.manager, state.seat);
    if (!state.pointer)
        fail("no se pudo crear un puntero virtual");
    sync_or_fail(&state);

    const char *action = argv[1];
    if (!strcmp(action, "keep")) {
        if (argc != 2) usage();
        keep_idle_keyboard(&state);
        sync_or_fail(&state);
        puts("READY");
        fflush(stdout);
        for (;;) pause();
    } else if (!strcmp(action, "move")) {
        if (argc != 6) usage();
        motion(&state, number(argv[2], "X inválido"), number(argv[3], "Y inválido"),
               number(argv[4], "ancho inválido"), number(argv[5], "alto inválido"));
    } else if (!strcmp(action, "click")) {
        if (argc < 7 || argc > 8) usage();
        long x = number(argv[2], "X inválido"), y = number(argv[3], "Y inválido");
        long width = number(argv[4], "ancho inválido"), height = number(argv[5], "alto inválido");
        uint32_t code = button_code(argv[6]);
        long count = argc == 8 ? number(argv[7], "cantidad inválida") : 1;
        if (count < 1 || count > 20) fail("la cantidad debe estar entre 1 y 20");
        for (long i = 0; i < count; i++) {
            motion(&state, x, y, width, height);
            button(&state, code, WL_POINTER_BUTTON_STATE_PRESSED);
            sync_or_fail(&state);
            pause_ms(45);
            button(&state, code, WL_POINTER_BUTTON_STATE_RELEASED);
            sync_or_fail(&state);
            if (i + 1 < count) pause_ms(90);
        }
    } else if (!strcmp(action, "drag")) {
        if (argc != 9) usage();
        long x1 = number(argv[2], "X1 inválido"), y1 = number(argv[3], "Y1 inválido");
        long x2 = number(argv[4], "X2 inválido"), y2 = number(argv[5], "Y2 inválido");
        long width = number(argv[6], "ancho inválido"), height = number(argv[7], "alto inválido");
        uint32_t code = button_code(argv[8]);
        motion(&state, x1, y1, width, height);
        button(&state, code, WL_POINTER_BUTTON_STATE_PRESSED);
        sync_or_fail(&state);
        for (int i = 1; i <= 24; i++) {
            long x = x1 + ((x2 - x1) * i) / 24;
            long y = y1 + ((y2 - y1) * i) / 24;
            motion(&state, x, y, width, height);
            sync_or_fail(&state);
            pause_ms(12);
        }
        button(&state, code, WL_POINTER_BUTTON_STATE_RELEASED);
        sync_or_fail(&state);
    } else if (!strcmp(action, "scroll")) {
        if (argc != 8) usage();
        long x = number(argv[2], "X inválido"), y = number(argv[3], "Y inválido");
        long width = number(argv[4], "ancho inválido"), height = number(argv[5], "alto inválido");
        long dx = strtol(argv[6], NULL, 10), dy = strtol(argv[7], NULL, 10);
        motion(&state, x, y, width, height);
        scroll_axis(&state, WL_POINTER_AXIS_VERTICAL_SCROLL, dy);
        scroll_axis(&state, WL_POINTER_AXIS_HORIZONTAL_SCROLL, dx);
        zwlr_virtual_pointer_v1_frame(state.pointer);
    } else {
        usage();
    }
    sync_or_fail(&state);
    zwlr_virtual_pointer_v1_destroy(state.pointer);
    zwlr_virtual_pointer_manager_v1_destroy(state.manager);
    wl_seat_destroy(state.seat);
    wl_registry_destroy(state.registry);
    if (wl_display_roundtrip(state.display) < 0)
        fail("error al cerrar la conexión Wayland virtual");
    wl_display_disconnect(state.display);
    return 0;
}
