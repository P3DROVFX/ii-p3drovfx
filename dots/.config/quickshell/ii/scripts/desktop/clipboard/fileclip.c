#define _POSIX_C_SOURCE 200809L
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <wayland-client.h>
#include "wlr-data-control-unstable-v1-client-protocol.h"

static struct zwlr_data_control_manager_v1 *manager;
static struct wl_seat *seat;

static char *payload;
static size_t payload_len;
static int is_cut;

static void write_all(int fd, const char *b, size_t n) {
    size_t o = 0;
    while (o < n) {
        ssize_t w = write(fd, b + o, n - o);
        if (w <= 0)
            break;
        o += (size_t)w;
    }
}

static void src_send(void *d, struct zwlr_data_control_source_v1 *s, const char *mime, int fd) {
    if (!strcmp(mime, "text/uri-list")) {
        write_all(fd, payload, payload_len);
    } else if (!strcmp(mime, "application/x-kde-cutselection")) {
        write_all(fd, "1", 1);
    } else if (!strcmp(mime, "x-special/gnome-copied-files")) {
        const char *op = is_cut ? "cut\n" : "copy\n";
        write_all(fd, op, strlen(op));
        write_all(fd, payload, payload_len);
    }
    close(fd);
}
static void src_cancelled(void *d, struct zwlr_data_control_source_v1 *s) {
    exit(0);
}
static const struct zwlr_data_control_source_v1_listener src_listener = {
    .send = src_send,
    .cancelled = src_cancelled,
};

static void offer_offer(void *d, struct zwlr_data_control_offer_v1 *o, const char *m) {}
static const struct zwlr_data_control_offer_v1_listener offer_listener = {.offer = offer_offer};

static void dev_data_offer(void *d, struct zwlr_data_control_device_v1 *dev, struct zwlr_data_control_offer_v1 *o) {
    zwlr_data_control_offer_v1_add_listener(o, &offer_listener, NULL);
}
static void dev_selection(void *d, struct zwlr_data_control_device_v1 *dev, struct zwlr_data_control_offer_v1 *o) {}
static void dev_finished(void *d, struct zwlr_data_control_device_v1 *dev) {
    exit(0);
}
static void dev_primary(void *d, struct zwlr_data_control_device_v1 *dev, struct zwlr_data_control_offer_v1 *o) {}
static const struct zwlr_data_control_device_v1_listener dev_listener = {
    .data_offer = dev_data_offer,
    .selection = dev_selection,
    .finished = dev_finished,
    .primary_selection = dev_primary,
};

static void reg_global(void *d, struct wl_registry *r, uint32_t name, const char *iface, uint32_t ver) {
    if (!strcmp(iface, zwlr_data_control_manager_v1_interface.name))
        manager = wl_registry_bind(r, name, &zwlr_data_control_manager_v1_interface, 1);
    else if (!strcmp(iface, wl_seat_interface.name) && !seat)
        seat = wl_registry_bind(r, name, &wl_seat_interface, 1);
}
static void reg_remove(void *d, struct wl_registry *r, uint32_t name) {}
static const struct wl_registry_listener reg_listener = {.global = reg_global, .global_remove = reg_remove};

int main(int argc, char **argv) {
    if (argc < 3)
        return 2;
    is_cut = !strcmp(argv[1], "cut");
    payload = argv[2];
    payload_len = strlen(payload);
    if (payload_len == 0)
        return 1;

    struct wl_display *dpy = wl_display_connect(NULL);
    if (!dpy)
        return 1;
    struct wl_registry *reg = wl_display_get_registry(dpy);
    wl_registry_add_listener(reg, &reg_listener, NULL);
    wl_display_roundtrip(dpy);
    if (!manager || !seat)
        return 1;

    struct zwlr_data_control_device_v1 *dev = zwlr_data_control_manager_v1_get_data_device(manager, seat);
    zwlr_data_control_device_v1_add_listener(dev, &dev_listener, NULL);

    struct zwlr_data_control_source_v1 *src = zwlr_data_control_manager_v1_create_data_source(manager);
    zwlr_data_control_source_v1_add_listener(src, &src_listener, NULL);
    zwlr_data_control_source_v1_offer(src, "text/uri-list");
    if (is_cut)
        zwlr_data_control_source_v1_offer(src, "application/x-kde-cutselection");
    zwlr_data_control_source_v1_offer(src, "x-special/gnome-copied-files");
    zwlr_data_control_device_v1_set_selection(dev, src);

    wl_display_roundtrip(dpy);
    while (wl_display_dispatch(dpy) != -1) {
    }
    return 0;
}
