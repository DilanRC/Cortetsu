#define _GNU_SOURCE
#include <dlfcn.h>
#include <wayland-server-core.h>
#include <wayland-server-protocol.h>
#include <string.h>

typedef struct wl_global *(*global_create_fn)(struct wl_display *, const struct wl_interface *, int,
                                              void *, wl_global_bind_func_t);

static void inert_seat_release(struct wl_client *client, struct wl_resource *resource) {
    (void)client;
    wl_resource_destroy(resource);
}

static const struct wl_seat_interface inert_seat_implementation = {
    .release = inert_seat_release,
};

static void bind_inert_seat(struct wl_client *client, void *data, uint32_t version, uint32_t id) {
    struct wl_resource *resource = wl_resource_create(client, &wl_seat_interface, (int)version, id);
    if (!resource) {
        wl_client_post_no_memory(client);
        return;
    }
    wl_resource_set_implementation(resource, &inert_seat_implementation, data, NULL);
    wl_seat_send_capabilities(resource, 0);
}

struct wl_global *wl_global_create(struct wl_display *display, const struct wl_interface *interface,
                                   int version, void *data, wl_global_bind_func_t bind) {
    static global_create_fn next_create;
    if (!next_create)
        next_create = (global_create_fn)dlsym(RTLD_NEXT, "wl_global_create");
    if (!next_create)
        return NULL;
    /* Aquamarine 0.15.1 binds these globals at v6. Weston 15 caps them at v5,
       and neither interface adds a request in v6. */
    if (interface && strcmp(interface->name, "wl_compositor") == 0 && version == 5)
        version = 6;
    if (interface && strcmp(interface->name, "xdg_wm_base") == 0 && version == 5)
        version = 6;
    struct wl_global *global = next_create(display, interface, version, data, bind);
    /* Headless Weston publishes no wl_seat. Aquamarine requires a seat global,
       but this fixture intentionally advertises no physical or virtual devices. */
    if (global && interface && strcmp(interface->name, "wl_compositor") == 0)
        next_create(display, &wl_seat_interface, 9, data, bind_inert_seat);
    return global;
}
