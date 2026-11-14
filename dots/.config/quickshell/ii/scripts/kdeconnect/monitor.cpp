#include <gio/gio.h>
#include <gio/gunixconnection.h>
#include <glib-unix.h>

#include <algorithm>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <iostream>
#include <sstream>
#include <string>
#include <string_view>
#include <unordered_map>
#include <unordered_set>
#include <vector>

namespace {

// ─── D-Bus Constants ─────────────────────────────────────────

constexpr const char *SERVICE           = "org.kde.kdeconnect";
constexpr const char *DAEMON_PATH       = "/modules/kdeconnect";
constexpr const char *DAEMON_IFACE      = "org.kde.kdeconnect.daemon";
constexpr const char *DEV_IFACE         = "org.kde.kdeconnect.device";
constexpr const char *BATT_IFACE        = "org.kde.kdeconnect.device.battery";
constexpr const char *CONN_IFACE        = "org.kde.kdeconnect.device.connectivity_report";
constexpr const char *NOTIF_IFACE       = "org.kde.kdeconnect.device.notifications";
constexpr const char *NOTIF_LEAF_IFACE  = "org.kde.kdeconnect.device.notifications.notification";
constexpr const char *SHARE_IFACE       = "org.kde.kdeconnect.device.share";
constexpr const char *TEL_IFACE         = "org.kde.kdeconnect.device.telephony";
constexpr const char *RKB_IFACE         = "org.kde.kdeconnect.device.remotekeyboard";
constexpr const char *PROPS_IFACE       = "org.freedesktop.DBus.Properties";
constexpr const char *DBUS_SERVICE      = "org.freedesktop.DBus";
constexpr const char *DBUS_PATH         = "/org/freedesktop/DBus";
constexpr const char *DBUS_IFACE        = "org.freedesktop.DBus";

// ─── Global State ────────────────────────────────────────────

GMainLoop *g_loop = nullptr;
GDBusConnection *g_conn = nullptr;
std::unordered_set<std::string> g_attached_devices;
std::unordered_map<std::string, std::vector<guint>> g_device_subscriptions;
std::vector<guint> g_daemon_subscriptions;

// ─── JSON Helpers ────────────────────────────────────────────

void emit(std::string_view json_str) {
    std::cout << json_str << "\n" << std::flush;
}

std::string json_escape(std::string_view s) {
    std::string out;
    out.reserve(s.size() + 8);
    for (unsigned char c : s) {
        switch (c) {
            case '"':  out += "\\\""; break;
            case '\\': out += "\\\\"; break;
            case '\b': out += "\\b"; break;
            case '\f': out += "\\f"; break;
            case '\n': out += "\\n"; break;
            case '\r': out += "\\r"; break;
            case '\t': out += "\\t"; break;
            default:
                if (c < 0x20) {
                    char buf[8];
                    std::snprintf(buf, sizeof(buf), "\\u%04x", c);
                    out += buf;
                } else {
                    out += static_cast<char>(c);
                }
                break;
        }
    }
    return out;
}

std::string format_string_array(const std::vector<std::string> &vec) {
    std::string out = "[";
    for (size_t i = 0; i < vec.size(); ++i) {
        if (i > 0) out += ",";
        out += "\"" + json_escape(vec[i]) + "\"";
    }
    out += "]";
    return out;
}

std::vector<std::string> extract_string_array(GVariant *v) {
    std::vector<std::string> result;
    if (!v) return result;
    if (g_variant_is_of_type(v, G_VARIANT_TYPE_STRING_ARRAY) ||
        g_variant_is_of_type(v, G_VARIANT_TYPE("a*"))) {
        gsize n = g_variant_n_children(v);
        result.reserve(n);
        for (gsize i = 0; i < n; ++i) {
            GVariant *child = g_variant_get_child_value(v, i);
            if (g_variant_is_of_type(child, G_VARIANT_TYPE_STRING)) {
                result.emplace_back(g_variant_get_string(child, nullptr));
            }
            g_variant_unref(child);
        }
    }
    return result;
}

std::string extract_package(const std::string &internal_id) {
    if (internal_id.rfind("0|", 0) == 0) {
        size_t next_bar = internal_id.find('|', 2);
        if (next_bar != std::string::npos) {
            return internal_id.substr(2, next_bar - 2);
        }
        return internal_id.substr(2);
    }
    return "";
}

// ─── Data Structures ─────────────────────────────────────────

struct DeviceProps {
    std::string id;
    std::string name;
    std::string type = "phone";
    std::string icon = "phone";
    std::string statusIconName = "phone";
    bool reachable = false;
    bool paired = false;
    bool isPairRequested = false;
    bool isPairRequestedByPeer = false;
    int32_t pairState = 0;
    std::string verificationKey;
    std::vector<std::string> supportedPlugins;
    std::vector<std::string> loadedPlugins;
    std::vector<std::string> reachableAddresses;
};

struct NotificationItem {
    std::string id;
    std::string publicId;
    std::string appName;
    std::string title;
    std::string summary;
    std::string text;
    std::string body;
    std::string ticker;
    bool isClearable = true;
    bool dismissable = true;
    bool silent = false;
    std::string replyId;
    bool hasIcon = false;
    std::string iconPath;
    std::string internalId;
    std::string package;
};

std::string notification_to_json(const NotificationItem &item) {
    std::ostringstream ss;
    ss << "{"
       << R"("id":")" << json_escape(item.id) << R"(",)"
       << R"("publicId":")" << json_escape(item.publicId) << R"(",)"
       << R"("appName":")" << json_escape(item.appName) << R"(",)"
       << R"("title":")" << json_escape(item.title) << R"(",)"
       << R"("summary":")" << json_escape(item.summary) << R"(",)"
       << R"("text":")" << json_escape(item.text) << R"(",)"
       << R"("body":")" << json_escape(item.body) << R"(",)"
       << R"("ticker":")" << json_escape(item.ticker) << R"(",)"
       << R"("isClearable":)" << (item.isClearable ? "true" : "false") << ","
       << R"("dismissable":)" << (item.dismissable ? "true" : "false") << ","
       << R"("silent":)" << (item.silent ? "true" : "false") << ","
       << R"("replyId":")" << json_escape(item.replyId) << R"(",)"
       << R"("hasIcon":)" << (item.hasIcon ? "true" : "false") << ","
       << R"("iconPath":")" << json_escape(item.iconPath) << R"(",)"
       << R"("internalId":")" << json_escape(item.internalId) << R"(",)"
       << R"("package":")" << json_escape(item.package) << R"(",)"
       << R"("actions":[])"
       << "}";
    return ss.str();
}

// ─── Forward Declarations ────────────────────────────────────

DeviceProps fetch_device_props(GDBusConnection *conn, const std::string &dev_id, bool is_attach);
void fetch_battery(GDBusConnection *conn, const std::string &dev_id);
void fetch_connectivity(GDBusConnection *conn, const std::string &dev_id);
void fetch_remote_keyboard(GDBusConnection *conn, const std::string &dev_id);
NotificationItem fetch_notification(GDBusConnection *conn, const std::string &dev_id, const std::string &notif_id);
void sync_notifications(GDBusConnection *conn, const std::string &dev_id);
std::vector<std::string> list_devices(GDBusConnection *conn);
void emit_pairing_requests(GDBusConnection *conn);
void attach_device(GDBusConnection *conn, const std::string &dev_id);
void detach_device(GDBusConnection *conn, const std::string &dev_id);

// ─── D-Bus Operations ────────────────────────────────────────

std::vector<std::string> list_devices(GDBusConnection *conn) {
    GError *error = nullptr;
    GVariant *res = g_dbus_connection_call_sync(
        conn, SERVICE, DAEMON_PATH, DAEMON_IFACE, "devices",
        nullptr, G_VARIANT_TYPE("(as)"),
        G_DBUS_CALL_FLAGS_NONE, -1, nullptr, &error
    );
    if (!res) {
        if (error) g_error_free(error);
        return {};
    }
    GVariant *child = g_variant_get_child_value(res, 0);
    std::vector<std::string> ids = extract_string_array(child);
    g_variant_unref(child);
    g_variant_unref(res);
    return ids;
}

void emit_pairing_requests(GDBusConnection *conn) {
    GError *error = nullptr;
    GVariant *res = g_dbus_connection_call_sync(
        conn, SERVICE, DAEMON_PATH, PROPS_IFACE, "Get",
        g_variant_new("(ss)", DAEMON_IFACE, "pairingRequests"),
        G_VARIANT_TYPE("(v)"),
        G_DBUS_CALL_FLAGS_NONE, -1, nullptr, &error
    );

    if (!res) {
        if (error) g_error_free(error);
        return;
    }

    GVariant *v = g_variant_get_child_value(res, 0);
    GVariant *inner = g_variant_get_variant(v);
    std::vector<std::string> pair_ids = extract_string_array(inner);
    g_variant_unref(inner);
    g_variant_unref(v);
    g_variant_unref(res);

    for (const auto &dev_id : pair_ids) {
        std::string dev_path = std::string("/modules/kdeconnect/devices/") + dev_id;
        std::string name;
        error = nullptr;
        GVariant *name_res = g_dbus_connection_call_sync(
            conn, SERVICE, dev_path.c_str(), PROPS_IFACE, "Get",
            g_variant_new("(ss)", DEV_IFACE, "name"),
            G_VARIANT_TYPE("(v)"),
            G_DBUS_CALL_FLAGS_NONE, -1, nullptr, &error
        );
        if (name_res) {
            GVariant *nv = g_variant_get_child_value(name_res, 0);
            GVariant *n_inner = g_variant_get_variant(nv);
            if (g_variant_is_of_type(n_inner, G_VARIANT_TYPE_STRING)) {
                name = g_variant_get_string(n_inner, nullptr);
            }
            g_variant_unref(n_inner);
            g_variant_unref(nv);
            g_variant_unref(name_res);
        } else if (error) {
            g_error_free(error);
        }

        std::ostringstream ss;
        ss << R"({"event":"pairing_request","id":")" << json_escape(dev_id)
           << R"(","name":")" << json_escape(name) << R"("})";
        emit(ss.str());
    }
}

DeviceProps fetch_device_props(GDBusConnection *conn, const std::string &dev_id, bool is_attach) {
    DeviceProps props;
    props.id = dev_id;
    std::string dev_path = std::string("/modules/kdeconnect/devices/") + dev_id;

    GError *error = nullptr;
    GVariant *res = g_dbus_connection_call_sync(
        conn, SERVICE, dev_path.c_str(), PROPS_IFACE, "GetAll",
        g_variant_new("(s)", DEV_IFACE),
        G_VARIANT_TYPE("(a{sv})"),
        G_DBUS_CALL_FLAGS_NONE, -1, nullptr, &error
    );

    bool has_supported_plugins = false;
    bool has_loaded_plugins = false;

    if (res) {
        GVariant *dict = g_variant_get_child_value(res, 0);
        GVariantIter iter;
        g_variant_iter_init(&iter, dict);
        const gchar *key = nullptr;
        GVariant *val = nullptr;

        while (g_variant_iter_loop(&iter, "{&sv}", &key, &val)) {
            if (std::strcmp(key, "name") == 0) {
                if (g_variant_is_of_type(val, G_VARIANT_TYPE_STRING))
                    props.name = g_variant_get_string(val, nullptr);
            } else if (std::strcmp(key, "type") == 0) {
                if (g_variant_is_of_type(val, G_VARIANT_TYPE_STRING))
                    props.type = g_variant_get_string(val, nullptr);
            } else if (std::strcmp(key, "iconName") == 0) {
                if (g_variant_is_of_type(val, G_VARIANT_TYPE_STRING))
                    props.icon = g_variant_get_string(val, nullptr);
            } else if (std::strcmp(key, "statusIconName") == 0) {
                if (g_variant_is_of_type(val, G_VARIANT_TYPE_STRING))
                    props.statusIconName = g_variant_get_string(val, nullptr);
            } else if (std::strcmp(key, "isReachable") == 0) {
                if (g_variant_is_of_type(val, G_VARIANT_TYPE_BOOLEAN))
                    props.reachable = g_variant_get_boolean(val);
            } else if (std::strcmp(key, "isPaired") == 0) {
                if (g_variant_is_of_type(val, G_VARIANT_TYPE_BOOLEAN))
                    props.paired = g_variant_get_boolean(val);
            } else if (std::strcmp(key, "isPairRequested") == 0) {
                if (g_variant_is_of_type(val, G_VARIANT_TYPE_BOOLEAN))
                    props.isPairRequested = g_variant_get_boolean(val);
            } else if (std::strcmp(key, "isPairRequestedByPeer") == 0) {
                if (g_variant_is_of_type(val, G_VARIANT_TYPE_BOOLEAN))
                    props.isPairRequestedByPeer = g_variant_get_boolean(val);
            } else if (std::strcmp(key, "pairState") == 0) {
                if (g_variant_is_of_type(val, G_VARIANT_TYPE_INT32))
                    props.pairState = g_variant_get_int32(val);
                else if (g_variant_is_of_type(val, G_VARIANT_TYPE_UINT32))
                    props.pairState = static_cast<int32_t>(g_variant_get_uint32(val));
            } else if (std::strcmp(key, "verificationKey") == 0 || std::strcmp(key, "VerificationKey") == 0) {
                if (g_variant_is_of_type(val, G_VARIANT_TYPE_STRING))
                    props.verificationKey = g_variant_get_string(val, nullptr);
            } else if (std::strcmp(key, "supportedPlugins") == 0) {
                props.supportedPlugins = extract_string_array(val);
                has_supported_plugins = true;
            } else if (std::strcmp(key, "loadedPlugins") == 0) {
                props.loadedPlugins = extract_string_array(val);
                has_loaded_plugins = true;
            } else if (std::strcmp(key, "reachableAddresses") == 0) {
                props.reachableAddresses = extract_string_array(val);
            }
        }
        g_variant_unref(dict);
        g_variant_unref(res);
    } else if (error) {
        g_error_free(error);
        error = nullptr;
    }

    if (props.statusIconName.empty()) {
        props.statusIconName = !props.icon.empty() ? props.icon : "phone";
    }

    // Call supportedPlugins() method if not in GetAll
    if (!has_supported_plugins) {
        error = nullptr;
        GVariant *sp_res = g_dbus_connection_call_sync(
            conn, SERVICE, dev_path.c_str(), DEV_IFACE, "supportedPlugins",
            nullptr, G_VARIANT_TYPE("(as)"),
            G_DBUS_CALL_FLAGS_NONE, -1, nullptr, &error
        );
        if (sp_res) {
            GVariant *child = g_variant_get_child_value(sp_res, 0);
            props.supportedPlugins = extract_string_array(child);
            g_variant_unref(child);
            g_variant_unref(sp_res);
        } else if (error) {
            g_error_free(error);
            error = nullptr;
        }
    }

    // Call loadedPlugins() method if not in GetAll
    if (!has_loaded_plugins) {
        error = nullptr;
        GVariant *lp_res = g_dbus_connection_call_sync(
            conn, SERVICE, dev_path.c_str(), DEV_IFACE, "loadedPlugins",
            nullptr, G_VARIANT_TYPE("(as)"),
            G_DBUS_CALL_FLAGS_NONE, -1, nullptr, &error
        );
        if (lp_res) {
            GVariant *child = g_variant_get_child_value(lp_res, 0);
            props.loadedPlugins = extract_string_array(child);
            g_variant_unref(child);
            g_variant_unref(lp_res);
        } else if (error) {
            g_error_free(error);
            error = nullptr;
        }
    }

    if (props.supportedPlugins.empty() && !props.loadedPlugins.empty()) {
        props.supportedPlugins = props.loadedPlugins;
    }

    std::string supp_json = format_string_array(props.supportedPlugins);
    std::string load_json = format_string_array(props.loadedPlugins);
    std::string addrs_json = format_string_array(props.reachableAddresses);

    // If initial attach, emit device_added for QML _mergeDevice
    if (is_attach) {
        std::ostringstream ss_add;
        ss_add << "{"
               << R"("event":"device_added",)"
               << R"("id":")" << json_escape(props.id) << R"(",)"
               << R"("name":")" << json_escape(props.name) << R"(",)"
               << R"("type":")" << json_escape(props.type) << R"(",)"
               << R"("icon":")" << json_escape(props.icon) << R"(",)"
               << R"("reachable":)" << (props.reachable ? "true" : "false") << ","
               << R"("paired":)" << (props.paired ? "true" : "false") << ","
               << R"("supported_plugins":)" << supp_json << ","
               << R"("loaded_plugins":)" << load_json << ","
               << R"("supportedPlugins":)" << supp_json << ","
               << R"("loadedPlugins":)" << load_json << ","
               << R"("reachableAddresses":)" << addrs_json
               << "}";
        emit(ss_add.str());
    }

    // Emit device_props with exact requirement keys and "changed" object
    std::ostringstream ss_props;
    ss_props << "{"
             << R"("event":"device_props",)"
             << R"("id":")" << json_escape(props.id) << R"(",)"
             << R"("name":")" << json_escape(props.name) << R"(",)"
             << R"("type":")" << json_escape(props.type) << R"(",)"
             << R"("isReachable":)" << (props.reachable ? "true" : "false") << ","
             << R"("isPaired":)" << (props.paired ? "true" : "false") << ","
             << R"("isPairRequested":)" << (props.isPairRequested ? "true" : "false") << ","
             << R"("isPairRequestedByPeer":)" << (props.isPairRequestedByPeer ? "true" : "false") << ","
             << R"("VerificationKey":")" << json_escape(props.verificationKey) << R"(",)"
             << R"("verificationKey":")" << json_escape(props.verificationKey) << R"(",)"
             << R"("statusIconName":")" << json_escape(props.statusIconName) << R"(",)"
             << R"("loadedPlugins":)" << load_json << ","
             << R"("supportedPlugins":)" << supp_json << ","
             << R"("changed":{)"
             << R"("name":")" << json_escape(props.name) << R"(",)"
             << R"("type":")" << json_escape(props.type) << R"(",)"
             << R"("iconName":")" << json_escape(props.icon) << R"(",)"
             << R"("statusIconName":")" << json_escape(props.statusIconName) << R"(",)"
             << R"("isReachable":)" << (props.reachable ? "true" : "false") << ","
             << R"("isPaired":)" << (props.paired ? "true" : "false") << ","
             << R"("pairState":)" << props.pairState << ","
             << R"("loadedPlugins":)" << load_json << ","
             << R"("supportedPlugins":)" << supp_json << ","
             << R"("reachableAddresses":)" << addrs_json
             << "}"
             << "}";
    emit(ss_props.str());

    return props;
}

void fetch_battery(GDBusConnection *conn, const std::string &dev_id) {
    std::string path = std::string("/modules/kdeconnect/devices/") + dev_id + "/battery";
    GError *error = nullptr;
    GVariant *res = g_dbus_connection_call_sync(
        conn, SERVICE, path.c_str(), PROPS_IFACE, "GetAll",
        g_variant_new("(s)", BATT_IFACE),
        G_VARIANT_TYPE("(a{sv})"),
        G_DBUS_CALL_FLAGS_NONE, -1, nullptr, &error
    );

    int charge = -1;
    bool is_charging = false;

    if (res) {
        GVariant *dict = g_variant_get_child_value(res, 0);
        GVariantIter iter;
        g_variant_iter_init(&iter, dict);
        const gchar *key = nullptr;
        GVariant *val = nullptr;

        while (g_variant_iter_loop(&iter, "{&sv}", &key, &val)) {
            if (std::strcmp(key, "charge") == 0) {
                if (g_variant_is_of_type(val, G_VARIANT_TYPE_INT32))
                    charge = g_variant_get_int32(val);
                else if (g_variant_is_of_type(val, G_VARIANT_TYPE_INT64))
                    charge = static_cast<int>(g_variant_get_int64(val));
                else if (g_variant_is_of_type(val, G_VARIANT_TYPE_UINT32))
                    charge = static_cast<int>(g_variant_get_uint32(val));
            } else if (std::strcmp(key, "isCharging") == 0) {
                if (g_variant_is_of_type(val, G_VARIANT_TYPE_BOOLEAN))
                    is_charging = g_variant_get_boolean(val);
            }
        }
        g_variant_unref(dict);
        g_variant_unref(res);
    } else if (error) {
        g_error_free(error);
    }

    std::ostringstream ss;
    ss << "{"
       << R"("event":"battery",)"
       << R"("id":")" << json_escape(dev_id) << R"(",)"
       << R"("charge":)" << charge << ","
       << R"("isCharging":)" << (is_charging ? "true" : "false") << ","
       << R"("charging":)" << (is_charging ? "true" : "false")
       << "}";
    emit(ss.str());
}

void fetch_connectivity(GDBusConnection *conn, const std::string &dev_id) {
    std::string path = std::string("/modules/kdeconnect/devices/") + dev_id + "/connectivity_report";
    GError *error = nullptr;
    GVariant *res = g_dbus_connection_call_sync(
        conn, SERVICE, path.c_str(), PROPS_IFACE, "GetAll",
        g_variant_new("(s)", CONN_IFACE),
        G_VARIANT_TYPE("(a{sv})"),
        G_DBUS_CALL_FLAGS_NONE, -1, nullptr, &error
    );

    std::string net_type;
    int strength = 0;

    if (res) {
        GVariant *dict = g_variant_get_child_value(res, 0);
        GVariantIter iter;
        g_variant_iter_init(&iter, dict);
        const gchar *key = nullptr;
        GVariant *val = nullptr;

        while (g_variant_iter_loop(&iter, "{&sv}", &key, &val)) {
            if (std::strcmp(key, "cellularNetworkType") == 0) {
                if (g_variant_is_of_type(val, G_VARIANT_TYPE_STRING))
                    net_type = g_variant_get_string(val, nullptr);
            } else if (std::strcmp(key, "cellularNetworkStrength") == 0) {
                if (g_variant_is_of_type(val, G_VARIANT_TYPE_INT32))
                    strength = g_variant_get_int32(val);
                else if (g_variant_is_of_type(val, G_VARIANT_TYPE_INT64))
                    strength = static_cast<int>(g_variant_get_int64(val));
                else if (g_variant_is_of_type(val, G_VARIANT_TYPE_UINT32))
                    strength = static_cast<int>(g_variant_get_uint32(val));
            }
        }
        g_variant_unref(dict);
        g_variant_unref(res);
    } else if (error) {
        g_error_free(error);
    }

    std::ostringstream ss;
    ss << "{"
       << R"("event":"connectivity",)"
       << R"("id":")" << json_escape(dev_id) << R"(",)"
       << R"("type":")" << json_escape(net_type) << R"(",)"
       << R"("strength":)" << strength << ","
       << R"("networkType":")" << json_escape(net_type) << R"(",)"
       << R"("signalStrength":)" << strength
       << "}";
    emit(ss.str());
}

void fetch_remote_keyboard(GDBusConnection *conn, const std::string &dev_id) {
    std::string path = std::string("/modules/kdeconnect/devices/") + dev_id + "/remotekeyboard";
    GError *error = nullptr;
    GVariant *res = g_dbus_connection_call_sync(
        conn, SERVICE, path.c_str(), PROPS_IFACE, "Get",
        g_variant_new("(ss)", RKB_IFACE, "remoteState"),
        G_VARIANT_TYPE("(v)"),
        G_DBUS_CALL_FLAGS_NONE, -1, nullptr, &error
    );

    bool active = false;
    bool found = false;

    if (res) {
        GVariant *v = g_variant_get_child_value(res, 0);
        GVariant *inner = g_variant_get_variant(v);
        if (g_variant_is_of_type(inner, G_VARIANT_TYPE_BOOLEAN)) {
            active = g_variant_get_boolean(inner);
            found = true;
        }
        g_variant_unref(inner);
        g_variant_unref(v);
        g_variant_unref(res);
    } else {
        if (error) {
            g_error_free(error);
            error = nullptr;
        }
        res = g_dbus_connection_call_sync(
            conn, SERVICE, path.c_str(), RKB_IFACE, "remoteState",
            nullptr, G_VARIANT_TYPE("(b)"),
            G_DBUS_CALL_FLAGS_NONE, -1, nullptr, &error
        );
        if (res) {
            GVariant *child = g_variant_get_child_value(res, 0);
            active = g_variant_get_boolean(child);
            found = true;
            g_variant_unref(child);
            g_variant_unref(res);
        } else if (error) {
            g_error_free(error);
        }
    }

    if (found) {
        std::ostringstream ss1, ss2;
        ss1 << R"({"event":"remote_keyboard","id":")" << json_escape(dev_id)
            << R"(","active":)" << (active ? "true" : "false") << "}";
        ss2 << R"({"event":"remote_kb_state","id":")" << json_escape(dev_id)
            << R"(","active":)" << (active ? "true" : "false") << "}";
        emit(ss1.str());
        emit(ss2.str());
    }
}

NotificationItem fetch_notification(GDBusConnection *conn, const std::string &dev_id, const std::string &notif_id) {
    NotificationItem item;
    item.id = notif_id;
    item.publicId = notif_id;

    std::string leaf_path = std::string("/modules/kdeconnect/devices/") + dev_id + "/notifications/" + notif_id;
    GError *error = nullptr;
    GVariant *res = g_dbus_connection_call_sync(
        conn, SERVICE, leaf_path.c_str(), PROPS_IFACE, "GetAll",
        g_variant_new("(s)", NOTIF_LEAF_IFACE),
        G_VARIANT_TYPE("(a{sv})"),
        G_DBUS_CALL_FLAGS_NONE, -1, nullptr, &error
    );

    if (res) {
        GVariant *dict = g_variant_get_child_value(res, 0);
        GVariantIter iter;
        g_variant_iter_init(&iter, dict);
        const gchar *key = nullptr;
        GVariant *val = nullptr;

        while (g_variant_iter_loop(&iter, "{&sv}", &key, &val)) {
            if (std::strcmp(key, "id") == 0) {
                if (g_variant_is_of_type(val, G_VARIANT_TYPE_STRING))
                    item.id = g_variant_get_string(val, nullptr);
            } else if (std::strcmp(key, "appName") == 0) {
                if (g_variant_is_of_type(val, G_VARIANT_TYPE_STRING))
                    item.appName = g_variant_get_string(val, nullptr);
            } else if (std::strcmp(key, "title") == 0) {
                if (g_variant_is_of_type(val, G_VARIANT_TYPE_STRING)) {
                    item.title = g_variant_get_string(val, nullptr);
                    item.summary = item.title;
                }
            } else if (std::strcmp(key, "text") == 0) {
                if (g_variant_is_of_type(val, G_VARIANT_TYPE_STRING)) {
                    item.text = g_variant_get_string(val, nullptr);
                    item.body = item.text;
                }
            } else if (std::strcmp(key, "ticker") == 0) {
                if (g_variant_is_of_type(val, G_VARIANT_TYPE_STRING))
                    item.ticker = g_variant_get_string(val, nullptr);
            } else if (std::strcmp(key, "isClearable") == 0) {
                if (g_variant_is_of_type(val, G_VARIANT_TYPE_BOOLEAN))
                    item.isClearable = g_variant_get_boolean(val);
            } else if (std::strcmp(key, "dismissable") == 0) {
                if (g_variant_is_of_type(val, G_VARIANT_TYPE_BOOLEAN))
                    item.dismissable = g_variant_get_boolean(val);
            } else if (std::strcmp(key, "silent") == 0) {
                if (g_variant_is_of_type(val, G_VARIANT_TYPE_BOOLEAN))
                    item.silent = g_variant_get_boolean(val);
            } else if (std::strcmp(key, "replyId") == 0) {
                if (g_variant_is_of_type(val, G_VARIANT_TYPE_STRING))
                    item.replyId = g_variant_get_string(val, nullptr);
            } else if (std::strcmp(key, "hasIcon") == 0) {
                if (g_variant_is_of_type(val, G_VARIANT_TYPE_BOOLEAN))
                    item.hasIcon = g_variant_get_boolean(val);
            } else if (std::strcmp(key, "iconPath") == 0) {
                if (g_variant_is_of_type(val, G_VARIANT_TYPE_STRING))
                    item.iconPath = g_variant_get_string(val, nullptr);
            } else if (std::strcmp(key, "internalId") == 0) {
                if (g_variant_is_of_type(val, G_VARIANT_TYPE_STRING)) {
                    item.internalId = g_variant_get_string(val, nullptr);
                    item.package = extract_package(item.internalId);
                }
            }
        }
        g_variant_unref(dict);
        g_variant_unref(res);
    } else if (error) {
        g_error_free(error);
    }

    if (item.id.empty()) item.id = notif_id;
    if (item.publicId.empty()) item.publicId = notif_id;

    return item;
}

void sync_notifications(GDBusConnection *conn, const std::string &dev_id) {
    std::string notif_path = std::string("/modules/kdeconnect/devices/") + dev_id + "/notifications";
    GError *error = nullptr;
    GVariant *res = g_dbus_connection_call_sync(
        conn, SERVICE, notif_path.c_str(), NOTIF_IFACE, "activeNotifications",
        nullptr, G_VARIANT_TYPE("(as)"),
        G_DBUS_CALL_FLAGS_NONE, -1, nullptr, &error
    );

    std::vector<std::string> public_ids;
    if (res) {
        GVariant *child = g_variant_get_child_value(res, 0);
        public_ids = extract_string_array(child);
        g_variant_unref(child);
        g_variant_unref(res);
    } else if (error) {
        g_error_free(error);
    }

    std::vector<NotificationItem> items;
    items.reserve(public_ids.size());
    for (const auto &pid : public_ids) {
        if (pid.empty()) continue;
        auto item = fetch_notification(conn, dev_id, pid);
        items.push_back(std::move(item));
    }

    std::ostringstream notifs_json;
    notifs_json << "[";
    for (size_t i = 0; i < items.size(); ++i) {
        if (i > 0) notifs_json << ",";
        notifs_json << notification_to_json(items[i]);
    }
    notifs_json << "]";

    std::string arr_str = notifs_json.str();
    // Emit sync_notifications (consumed by KdeConnectService.qml) and notifications_sync
    std::ostringstream ss1, ss2;
    ss1 << "{"
        << R"("event":"sync_notifications",)"
        << R"("id":")" << json_escape(dev_id) << R"(",)"
        << R"("notifications":)" << arr_str << ","
        << R"("items":)" << arr_str
        << "}";
    ss2 << "{"
        << R"("event":"notifications_sync",)"
        << R"("id":")" << json_escape(dev_id) << R"(",)"
        << R"("items":)" << arr_str << ","
        << R"("notifications":)" << arr_str
        << "}";
    emit(ss1.str());
    emit(ss2.str());
}

// ─── Signal Callbacks ────────────────────────────────────────

static void on_device_props_changed(GDBusConnection *conn,
                                    const gchar *sender_name,
                                    const gchar *object_path,
                                    const gchar *interface_name,
                                    const gchar *signal_name,
                                    GVariant *parameters,
                                    gpointer user_data) {
    (void)sender_name;
    (void)object_path;
    (void)interface_name;
    (void)signal_name;
    const auto *dev_id = static_cast<const std::string*>(user_data);
    if (!dev_id || !parameters || g_variant_n_children(parameters) < 1) return;

    GVariant *iface_v = g_variant_get_child_value(parameters, 0);
    const gchar *iface = g_variant_get_string(iface_v, nullptr);
    if (iface && (std::strcmp(iface, DEV_IFACE) == 0 ||
                  std::string_view(iface).starts_with(std::string(DEV_IFACE) + "."))) {
        fetch_device_props(conn, *dev_id, false);
    }
    g_variant_unref(iface_v);
}

static void on_battery_refreshed(GDBusConnection *conn,
                                 const gchar *sender_name,
                                 const gchar *object_path,
                                 const gchar *interface_name,
                                 const gchar *signal_name,
                                 GVariant *parameters,
                                 gpointer user_data) {
    (void)conn;
    (void)sender_name;
    (void)object_path;
    (void)interface_name;
    (void)signal_name;
    const auto *dev_id = static_cast<const std::string*>(user_data);
    if (!dev_id || !parameters || g_variant_n_children(parameters) < 2) return;

    GVariant *v0 = g_variant_get_child_value(parameters, 0);
    GVariant *v1 = g_variant_get_child_value(parameters, 1);
    bool is_charging = g_variant_get_boolean(v0);
    int charge = g_variant_get_int32(v1);
    g_variant_unref(v0);
    g_variant_unref(v1);

    std::ostringstream ss;
    ss << "{"
       << R"("event":"battery",)"
       << R"("id":")" << json_escape(*dev_id) << R"(",)"
       << R"("charge":)" << charge << ","
       << R"("isCharging":)" << (is_charging ? "true" : "false") << ","
       << R"("charging":)" << (is_charging ? "true" : "false")
       << "}";
    emit(ss.str());
}

static void on_battery_props_changed(GDBusConnection *conn,
                                     const gchar *sender_name,
                                     const gchar *object_path,
                                     const gchar *interface_name,
                                     const gchar *signal_name,
                                     GVariant *parameters,
                                     gpointer user_data) {
    (void)sender_name;
    (void)object_path;
    (void)interface_name;
    (void)signal_name;
    const auto *dev_id = static_cast<const std::string*>(user_data);
    if (!dev_id || !parameters || g_variant_n_children(parameters) < 1) return;

    GVariant *iface_v = g_variant_get_child_value(parameters, 0);
    const gchar *iface = g_variant_get_string(iface_v, nullptr);
    if (iface && std::strcmp(iface, BATT_IFACE) == 0) {
        fetch_battery(conn, *dev_id);
    }
    g_variant_unref(iface_v);
}

static void on_connectivity_refreshed(GDBusConnection *conn,
                                      const gchar *sender_name,
                                      const gchar *object_path,
                                      const gchar *interface_name,
                                      const gchar *signal_name,
                                      GVariant *parameters,
                                      gpointer user_data) {
    (void)conn;
    (void)sender_name;
    (void)object_path;
    (void)interface_name;
    (void)signal_name;
    const auto *dev_id = static_cast<const std::string*>(user_data);
    if (!dev_id || !parameters || g_variant_n_children(parameters) < 2) return;

    GVariant *v0 = g_variant_get_child_value(parameters, 0);
    GVariant *v1 = g_variant_get_child_value(parameters, 1);
    std::string net_type = g_variant_get_string(v0, nullptr);
    int strength = g_variant_get_int32(v1);
    g_variant_unref(v0);
    g_variant_unref(v1);

    std::ostringstream ss;
    ss << "{"
       << R"("event":"connectivity",)"
       << R"("id":")" << json_escape(*dev_id) << R"(",)"
       << R"("type":")" << json_escape(net_type) << R"(",)"
       << R"("strength":)" << strength << ","
       << R"("networkType":")" << json_escape(net_type) << R"(",)"
       << R"("signalStrength":)" << strength
       << "}";
    emit(ss.str());
}

static void on_notif_posted(GDBusConnection *conn,
                            const gchar *sender_name,
                            const gchar *object_path,
                            const gchar *interface_name,
                            const gchar *signal_name,
                            GVariant *parameters,
                            gpointer user_data) {
    (void)sender_name;
    (void)object_path;
    (void)interface_name;
    (void)signal_name;
    const auto *dev_id = static_cast<const std::string*>(user_data);
    if (!dev_id || !parameters || g_variant_n_children(parameters) < 1) return;

    GVariant *v0 = g_variant_get_child_value(parameters, 0);
    std::string notif_id = g_variant_get_string(v0, nullptr);
    g_variant_unref(v0);

    auto item = fetch_notification(conn, *dev_id, notif_id);
    std::ostringstream ss;
    ss << "{"
       << R"("event":"notif_posted",)"
       << R"("id":")" << json_escape(*dev_id) << R"(",)"
       << R"("public_id":")" << json_escape(notif_id) << R"(",)"
       << R"("notifId":")" << json_escape(notif_id) << R"(",)"
       << R"("notif":)" << notification_to_json(item)
       << "}";
    emit(ss.str());
    sync_notifications(conn, *dev_id);
}

static void on_notif_updated(GDBusConnection *conn,
                             const gchar *sender_name,
                             const gchar *object_path,
                             const gchar *interface_name,
                             const gchar *signal_name,
                             GVariant *parameters,
                             gpointer user_data) {
    (void)sender_name;
    (void)object_path;
    (void)interface_name;
    (void)signal_name;
    const auto *dev_id = static_cast<const std::string*>(user_data);
    if (!dev_id || !parameters || g_variant_n_children(parameters) < 1) return;

    GVariant *v0 = g_variant_get_child_value(parameters, 0);
    std::string notif_id = g_variant_get_string(v0, nullptr);
    g_variant_unref(v0);

    auto item = fetch_notification(conn, *dev_id, notif_id);
    std::ostringstream ss;
    ss << "{"
       << R"("event":"notif_updated",)"
       << R"("id":")" << json_escape(*dev_id) << R"(",)"
       << R"("public_id":")" << json_escape(notif_id) << R"(",)"
       << R"("notifId":")" << json_escape(notif_id) << R"(",)"
       << R"("notif":)" << notification_to_json(item)
       << "}";
    emit(ss.str());
    sync_notifications(conn, *dev_id);
}

static void on_notif_removed(GDBusConnection *conn,
                             const gchar *sender_name,
                             const gchar *object_path,
                             const gchar *interface_name,
                             const gchar *signal_name,
                             GVariant *parameters,
                             gpointer user_data) {
    (void)conn;
    (void)sender_name;
    (void)object_path;
    (void)interface_name;
    (void)signal_name;
    const auto *dev_id = static_cast<const std::string*>(user_data);
    if (!dev_id || !parameters || g_variant_n_children(parameters) < 1) return;

    GVariant *v0 = g_variant_get_child_value(parameters, 0);
    std::string notif_id = g_variant_get_string(v0, nullptr);
    g_variant_unref(v0);

    std::ostringstream ss;
    ss << "{"
       << R"("event":"notif_removed",)"
       << R"("id":")" << json_escape(*dev_id) << R"(",)"
       << R"("public_id":")" << json_escape(notif_id) << R"(",)"
       << R"("notifId":")" << json_escape(notif_id) << R"(")"
       << "}";
    emit(ss.str());
    sync_notifications(conn, *dev_id);
}

static void on_notifs_cleared(GDBusConnection *conn,
                              const gchar *sender_name,
                              const gchar *object_path,
                              const gchar *interface_name,
                              const gchar *signal_name,
                              GVariant *parameters,
                              gpointer user_data) {
    (void)sender_name;
    (void)object_path;
    (void)interface_name;
    (void)signal_name;
    (void)parameters;
    const auto *dev_id = static_cast<const std::string*>(user_data);
    if (!dev_id) return;

    emit(R"({"event":"notif_cleared","id":")" + json_escape(*dev_id) + R"("})");
    emit(R"({"event":"notifs_cleared","id":")" + json_escape(*dev_id) + R"("})");
    sync_notifications(conn, *dev_id);
}

static void on_share_received(GDBusConnection *conn,
                              const gchar *sender_name,
                              const gchar *object_path,
                              const gchar *interface_name,
                              const gchar *signal_name,
                              GVariant *parameters,
                              gpointer user_data) {
    (void)conn;
    (void)sender_name;
    (void)object_path;
    (void)interface_name;
    (void)signal_name;
    const auto *dev_id = static_cast<const std::string*>(user_data);
    if (!dev_id || !parameters || g_variant_n_children(parameters) < 1) return;

    GVariant *v0 = g_variant_get_child_value(parameters, 0);
    std::string url = g_variant_get_string(v0, nullptr);
    g_variant_unref(v0);

    std::ostringstream ss;
    ss << "{"
       << R"("event":"share_received",)"
       << R"("id":")" << json_escape(*dev_id) << R"(",)"
       << R"("url":")" << json_escape(url) << R"(")"
       << "}";
    emit(ss.str());
}

static void on_call_received(GDBusConnection *conn,
                             const gchar *sender_name,
                             const gchar *object_path,
                             const gchar *interface_name,
                             const gchar *signal_name,
                             GVariant *parameters,
                             gpointer user_data) {
    (void)conn;
    (void)sender_name;
    (void)object_path;
    (void)interface_name;
    (void)signal_name;
    const auto *dev_id = static_cast<const std::string*>(user_data);
    if (!dev_id || !parameters || g_variant_n_children(parameters) < 2) return;

    GVariant *v0 = g_variant_get_child_value(parameters, 0);
    GVariant *v1 = g_variant_get_child_value(parameters, 1);
    std::string event = g_variant_get_string(v0, nullptr);
    std::string number = g_variant_get_string(v1, nullptr);
    std::string contact;
    if (g_variant_n_children(parameters) >= 3) {
        GVariant *v2 = g_variant_get_child_value(parameters, 2);
        contact = g_variant_get_string(v2, nullptr);
        g_variant_unref(v2);
    }
    g_variant_unref(v0);
    g_variant_unref(v1);

    if (event != "ringing" && event != "talking" && event != "missedCall") return;

    std::ostringstream ss1, ss2;
    ss1 << "{"
        << R"("event":"call",)"
        << R"("id":")" << json_escape(*dev_id) << R"(",)"
        << R"("state":")" << json_escape(event) << R"(",)"
        << R"("number":")" << json_escape(number) << R"(",)"
        << R"("contact":")" << json_escape(contact) << R"(",)"
        << R"("eventType":")" << json_escape(event) << R"(",)"
        << R"("phoneNumber":")" << json_escape(number) << R"(",)"
        << R"("contactName":")" << json_escape(contact) << R"(")"
        << "}";
    ss2 << "{"
        << R"("event":"telephony",)"
        << R"("id":")" << json_escape(*dev_id) << R"(",)"
        << R"("eventType":")" << json_escape(event) << R"(",)"
        << R"("phoneNumber":")" << json_escape(number) << R"(",)"
        << R"("contactName":")" << json_escape(contact) << R"(",)"
        << R"("state":")" << json_escape(event) << R"(",)"
        << R"("number":")" << json_escape(number) << R"(",)"
        << R"("contact":")" << json_escape(contact) << R"(")"
        << "}";
    emit(ss1.str());
    emit(ss2.str());
}

static void on_remote_state_changed(GDBusConnection *conn,
                                    const gchar *sender_name,
                                    const gchar *object_path,
                                    const gchar *interface_name,
                                    const gchar *signal_name,
                                    GVariant *parameters,
                                    gpointer user_data) {
    (void)conn;
    (void)sender_name;
    (void)object_path;
    (void)interface_name;
    (void)signal_name;
    const auto *dev_id = static_cast<const std::string*>(user_data);
    if (!dev_id || !parameters || g_variant_n_children(parameters) < 1) return;

    GVariant *v0 = g_variant_get_child_value(parameters, 0);
    bool active = g_variant_get_boolean(v0);
    g_variant_unref(v0);

    std::ostringstream ss1, ss2;
    ss1 << R"({"event":"remote_keyboard","id":")" << json_escape(*dev_id)
        << R"(","active":)" << (active ? "true" : "false") << "}";
    ss2 << R"({"event":"remote_kb_state","id":")" << json_escape(*dev_id)
        << R"(","active":)" << (active ? "true" : "false") << "}";
    emit(ss1.str());
    emit(ss2.str());
}

static void on_pair_state_changed(GDBusConnection *conn,
                                  const gchar *sender_name,
                                  const gchar *object_path,
                                  const gchar *interface_name,
                                  const gchar *signal_name,
                                  GVariant *parameters,
                                  gpointer user_data) {
    (void)sender_name;
    (void)object_path;
    (void)interface_name;
    (void)signal_name;
    const auto *dev_id = static_cast<const std::string*>(user_data);
    if (!dev_id || !parameters || g_variant_n_children(parameters) < 1) return;

    GVariant *v0 = g_variant_get_child_value(parameters, 0);
    int pair_state = g_variant_get_int32(v0);
    g_variant_unref(v0);

    auto props = fetch_device_props(conn, *dev_id, false);
    if (pair_state == 2) {
        std::ostringstream ss;
        ss << R"({"event":"pairing_request","id":")" << json_escape(*dev_id)
           << R"(","name":")" << json_escape(props.name) << R"("})";
        emit(ss.str());
    }
}

// ─── Attach / Detach Device ──────────────────────────────────

void attach_device(GDBusConnection *conn, const std::string &dev_id) {
    if (g_attached_devices.find(dev_id) != g_attached_devices.end()) {
        return;
    }
    g_attached_devices.insert(dev_id);

    // 1. Initial properties fetch (emits device_added and device_props)
    fetch_device_props(conn, dev_id, true);

    // 2. Initial battery fetch
    fetch_battery(conn, dev_id);

    // 3. Initial connectivity fetch
    fetch_connectivity(conn, dev_id);

    // 4. Initial notification sync
    sync_notifications(conn, dev_id);

    // 5. Initial remote keyboard state
    fetch_remote_keyboard(conn, dev_id);

    // 6. Subscribe to per-device signals
    std::string dev_path = std::string("/modules/kdeconnect/devices/") + dev_id;
    std::vector<guint> subs;

    auto make_str_copy = [&dev_id]() {
        return new std::string(dev_id);
    };
    auto free_str = [](gpointer data) {
        delete static_cast<std::string*>(data);
    };

    // PropertiesChanged on device path
    subs.push_back(g_dbus_connection_signal_subscribe(
        conn, SERVICE, PROPS_IFACE, "PropertiesChanged",
        dev_path.c_str(), nullptr, G_DBUS_SIGNAL_FLAGS_NONE,
        on_device_props_changed, make_str_copy(), free_str
    ));

    // refreshed on battery path
    std::string batt_path = dev_path + "/battery";
    subs.push_back(g_dbus_connection_signal_subscribe(
        conn, SERVICE, BATT_IFACE, "refreshed",
        batt_path.c_str(), nullptr, G_DBUS_SIGNAL_FLAGS_NONE,
        on_battery_refreshed, make_str_copy(), free_str
    ));

    // PropertiesChanged on battery path
    subs.push_back(g_dbus_connection_signal_subscribe(
        conn, SERVICE, PROPS_IFACE, "PropertiesChanged",
        batt_path.c_str(), nullptr, G_DBUS_SIGNAL_FLAGS_NONE,
        on_battery_props_changed, make_str_copy(), free_str
    ));

    // refreshed on connectivity_report path
    std::string conn_path = dev_path + "/connectivity_report";
    subs.push_back(g_dbus_connection_signal_subscribe(
        conn, SERVICE, CONN_IFACE, "refreshed",
        conn_path.c_str(), nullptr, G_DBUS_SIGNAL_FLAGS_NONE,
        on_connectivity_refreshed, make_str_copy(), free_str
    ));

    // Notification signals
    std::string notif_path = dev_path + "/notifications";
    subs.push_back(g_dbus_connection_signal_subscribe(
        conn, SERVICE, NOTIF_IFACE, "notificationPosted",
        notif_path.c_str(), nullptr, G_DBUS_SIGNAL_FLAGS_NONE,
        on_notif_posted, make_str_copy(), free_str
    ));
    subs.push_back(g_dbus_connection_signal_subscribe(
        conn, SERVICE, NOTIF_IFACE, "notificationUpdated",
        notif_path.c_str(), nullptr, G_DBUS_SIGNAL_FLAGS_NONE,
        on_notif_updated, make_str_copy(), free_str
    ));
    subs.push_back(g_dbus_connection_signal_subscribe(
        conn, SERVICE, NOTIF_IFACE, "notificationRemoved",
        notif_path.c_str(), nullptr, G_DBUS_SIGNAL_FLAGS_NONE,
        on_notif_removed, make_str_copy(), free_str
    ));
    subs.push_back(g_dbus_connection_signal_subscribe(
        conn, SERVICE, NOTIF_IFACE, "allNotificationsRemoved",
        notif_path.c_str(), nullptr, G_DBUS_SIGNAL_FLAGS_NONE,
        on_notifs_cleared, make_str_copy(), free_str
    ));

    // Share received
    std::string share_path = dev_path + "/share";
    subs.push_back(g_dbus_connection_signal_subscribe(
        conn, SERVICE, SHARE_IFACE, "shareReceived",
        share_path.c_str(), nullptr, G_DBUS_SIGNAL_FLAGS_NONE,
        on_share_received, make_str_copy(), free_str
    ));

    // Telephony call received
    std::string tel_path = dev_path + "/telephony";
    subs.push_back(g_dbus_connection_signal_subscribe(
        conn, SERVICE, TEL_IFACE, "callReceived",
        tel_path.c_str(), nullptr, G_DBUS_SIGNAL_FLAGS_NONE,
        on_call_received, make_str_copy(), free_str
    ));

    // Remote keyboard state changed
    std::string rkb_path = dev_path + "/remotekeyboard";
    subs.push_back(g_dbus_connection_signal_subscribe(
        conn, SERVICE, RKB_IFACE, "remoteStateChanged",
        rkb_path.c_str(), nullptr, G_DBUS_SIGNAL_FLAGS_NONE,
        on_remote_state_changed, make_str_copy(), free_str
    ));

    // Pair state changed
    subs.push_back(g_dbus_connection_signal_subscribe(
        conn, SERVICE, DEV_IFACE, "pairStateChanged",
        dev_path.c_str(), nullptr, G_DBUS_SIGNAL_FLAGS_NONE,
        on_pair_state_changed, make_str_copy(), free_str
    ));

    g_device_subscriptions[dev_id] = std::move(subs);
}

void detach_device(GDBusConnection *conn, const std::string &dev_id) {
    if (g_attached_devices.find(dev_id) == g_attached_devices.end()) {
        return;
    }
    g_attached_devices.erase(dev_id);

    auto it = g_device_subscriptions.find(dev_id);
    if (it != g_device_subscriptions.end()) {
        for (guint sub_id : it->second) {
            g_dbus_connection_signal_unsubscribe(conn, sub_id);
        }
        g_device_subscriptions.erase(it);
    }

    emit(R"({"event":"device_removed","id":")" + json_escape(dev_id) + R"("})");
}

// ─── Daemon Signal Callbacks ─────────────────────────────────

static void on_daemon_device_added(GDBusConnection *conn,
                                   const gchar *sender_name,
                                   const gchar *object_path,
                                   const gchar *interface_name,
                                   const gchar *signal_name,
                                   GVariant *parameters,
                                   gpointer user_data) {
    (void)sender_name;
    (void)object_path;
    (void)interface_name;
    (void)signal_name;
    (void)user_data;
    if (!parameters || g_variant_n_children(parameters) < 1) return;

    GVariant *v0 = g_variant_get_child_value(parameters, 0);
    std::string dev_id = g_variant_get_string(v0, nullptr);
    g_variant_unref(v0);

    emit(R"({"event":"device_added_signal","id":")" + json_escape(dev_id) + R"("})");
    attach_device(conn, dev_id);
}

static void on_daemon_device_removed(GDBusConnection *conn,
                                     const gchar *sender_name,
                                     const gchar *object_path,
                                     const gchar *interface_name,
                                     const gchar *signal_name,
                                     GVariant *parameters,
                                     gpointer user_data) {
    (void)sender_name;
    (void)object_path;
    (void)interface_name;
    (void)signal_name;
    (void)user_data;
    if (!parameters || g_variant_n_children(parameters) < 1) return;

    GVariant *v0 = g_variant_get_child_value(parameters, 0);
    std::string dev_id = g_variant_get_string(v0, nullptr);
    g_variant_unref(v0);

    detach_device(conn, dev_id);
}

static void on_daemon_visibility_changed(GDBusConnection *conn,
                                         const gchar *sender_name,
                                         const gchar *object_path,
                                         const gchar *interface_name,
                                         const gchar *signal_name,
                                         GVariant *parameters,
                                         gpointer user_data) {
    (void)sender_name;
    (void)object_path;
    (void)interface_name;
    (void)signal_name;
    (void)user_data;
    if (!parameters || g_variant_n_children(parameters) < 2) return;

    GVariant *v0 = g_variant_get_child_value(parameters, 0);
    GVariant *v1 = g_variant_get_child_value(parameters, 1);
    std::string dev_id = g_variant_get_string(v0, nullptr);
    bool is_visible = g_variant_get_boolean(v1);
    g_variant_unref(v0);
    g_variant_unref(v1);

    std::ostringstream ss;
    ss << "{"
       << R"("event":"device_visibility",)"
       << R"("id":")" << json_escape(dev_id) << R"(",)"
       << R"("reachable":)" << (is_visible ? "true" : "false")
       << "}";
    emit(ss.str());

    fetch_device_props(conn, dev_id, false);
}

static void on_daemon_pairing_requests_changed(GDBusConnection *conn,
                                               const gchar *sender_name,
                                               const gchar *object_path,
                                               const gchar *interface_name,
                                               const gchar *signal_name,
                                               GVariant *parameters,
                                               gpointer user_data) {
    (void)sender_name;
    (void)object_path;
    (void)interface_name;
    (void)signal_name;
    (void)parameters;
    (void)user_data;

    emit_pairing_requests(conn);
    auto devs = list_devices(conn);
    for (const auto &id : devs) {
        fetch_device_props(conn, id, false);
    }
}

static void on_name_owner_changed(GDBusConnection *conn,
                                  const gchar *sender_name,
                                  const gchar *object_path,
                                  const gchar *interface_name,
                                  const gchar *signal_name,
                                  GVariant *parameters,
                                  gpointer user_data) {
    (void)sender_name;
    (void)object_path;
    (void)interface_name;
    (void)signal_name;
    (void)user_data;
    if (!parameters || g_variant_n_children(parameters) < 3) return;

    GVariant *v0 = g_variant_get_child_value(parameters, 0);
    GVariant *v2 = g_variant_get_child_value(parameters, 2);
    const gchar *name = g_variant_get_string(v0, nullptr);
    const gchar *new_owner = g_variant_get_string(v2, nullptr);

    if (name && std::strcmp(name, SERVICE) == 0) {
        if (!new_owner || new_owner[0] == '\0') {
            emit(R"({"event":"daemon_vanished"})");
            auto devs = g_attached_devices;
            for (const auto &id : devs) {
                detach_device(conn, id);
            }
        } else {
            emit(R"({"event":"daemon_appeared"})");
            auto devs = list_devices(conn);
            for (const auto &id : devs) {
                attach_device(conn, id);
            }
            emit_pairing_requests(conn);
        }
    }

    g_variant_unref(v0);
    g_variant_unref(v2);
}

// ─── Unix Signals ────────────────────────────────────────────

static gboolean on_unix_signal(gpointer user_data) {
    (void)user_data;
    if (g_loop && g_main_loop_is_running(g_loop)) {
        g_main_loop_quit(g_loop);
    }
    return G_SOURCE_REMOVE;
}

} // namespace

// ─── Main ────────────────────────────────────────────────────

int main() {
    GError *error = nullptr;
    g_conn = g_bus_get_sync(G_BUS_TYPE_SESSION, nullptr, &error);
    if (!g_conn) {
        std::string detail = error ? error->message : "unknown error";
        emit(R"({"event":"fatal","error":"no_session_bus","message":"Could not connect to D-Bus session bus","detail":")"
             + json_escape(detail) + R"("})");
        if (error) g_error_free(error);
        return 1;
    }

    // Call devices on daemon to verify KDE Connect is present
    error = nullptr;
    GVariant *devices_res = g_dbus_connection_call_sync(
        g_conn, SERVICE, DAEMON_PATH, DAEMON_IFACE, "devices",
        nullptr, G_VARIANT_TYPE("(as)"),
        G_DBUS_CALL_FLAGS_NONE, -1, nullptr, &error
    );

    if (!devices_res) {
        std::string detail = error ? error->message : "daemon call failed";
        emit(R"({"event":"fatal","error":"no_daemon","message":"KDE Connect daemon not found via D-Bus","detail":")"
             + json_escape(detail) + R"("})");
        if (error) g_error_free(error);
        g_object_unref(g_conn);
        return 1;
    }

    GVariant *child = g_variant_get_child_value(devices_res, 0);
    std::vector<std::string> initial_devices = extract_string_array(child);
    g_variant_unref(child);
    g_variant_unref(devices_res);

    // Subscribe to daemon signals
    g_daemon_subscriptions.push_back(g_dbus_connection_signal_subscribe(
        g_conn, SERVICE, DAEMON_IFACE, "deviceAdded",
        DAEMON_PATH, nullptr, G_DBUS_SIGNAL_FLAGS_NONE,
        on_daemon_device_added, nullptr, nullptr
    ));
    g_daemon_subscriptions.push_back(g_dbus_connection_signal_subscribe(
        g_conn, SERVICE, DAEMON_IFACE, "deviceRemoved",
        DAEMON_PATH, nullptr, G_DBUS_SIGNAL_FLAGS_NONE,
        on_daemon_device_removed, nullptr, nullptr
    ));
    g_daemon_subscriptions.push_back(g_dbus_connection_signal_subscribe(
        g_conn, SERVICE, DAEMON_IFACE, "deviceVisibilityChanged",
        DAEMON_PATH, nullptr, G_DBUS_SIGNAL_FLAGS_NONE,
        on_daemon_visibility_changed, nullptr, nullptr
    ));
    g_daemon_subscriptions.push_back(g_dbus_connection_signal_subscribe(
        g_conn, SERVICE, DAEMON_IFACE, "pairingRequestsChanged",
        DAEMON_PATH, nullptr, G_DBUS_SIGNAL_FLAGS_NONE,
        on_daemon_pairing_requests_changed, nullptr, nullptr
    ));

    // Watch DBus NameOwnerChanged for org.kde.kdeconnect
    g_daemon_subscriptions.push_back(g_dbus_connection_signal_subscribe(
        g_conn, DBUS_SERVICE, DBUS_IFACE, "NameOwnerChanged",
        DBUS_PATH, SERVICE, G_DBUS_SIGNAL_FLAGS_NONE,
        on_name_owner_changed, nullptr, nullptr
    ));

    // Setup signal handlers for clean shutdown
    g_unix_signal_add(SIGINT, on_unix_signal, nullptr);
    g_unix_signal_add(SIGTERM, on_unix_signal, nullptr);

    // Emit ready event
    emit(R"({"event":"ready"})");

    // Attach all initial devices
    for (const auto &dev_id : initial_devices) {
        attach_device(g_conn, dev_id);
    }

    // Emit any pending pairing requests
    emit_pairing_requests(g_conn);

    // Run the main loop
    g_loop = g_main_loop_new(nullptr, FALSE);
    g_main_loop_run(g_loop);

    // Clean up
    for (const auto &dev_id : g_attached_devices) {
        auto it = g_device_subscriptions.find(dev_id);
        if (it != g_device_subscriptions.end()) {
            for (guint sub_id : it->second) {
                g_dbus_connection_signal_unsubscribe(g_conn, sub_id);
            }
        }
    }
    g_device_subscriptions.clear();
    g_attached_devices.clear();

    for (guint sub_id : g_daemon_subscriptions) {
        g_dbus_connection_signal_unsubscribe(g_conn, sub_id);
    }
    g_daemon_subscriptions.clear();

    g_main_loop_unref(g_loop);
    g_object_unref(g_conn);

    return 0;
}
