#include <gio/gio.h>
#include <glib-unix.h>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cerrno>
#include <fcntl.h>
#include <unistd.h>
#include <string>
#include <string_view>
#include <unordered_set>
#include <iostream>

static constexpr const char* BUS_NAME = "org.bluez";
static constexpr const char* AGENT_PATH = "/org/quickshell/ii/btagent";
static constexpr const char* AGENT_MANAGER_IFACE = "org.bluez.AgentManager1";
static constexpr const char* DEVICE_IFACE = "org.bluez.Device1";
static constexpr const char* PROPS_IFACE = "org.freedesktop.DBus.Properties";

static const char* AGENT_XML = R"(
<node>
  <interface name="org.bluez.Agent1">
    <method name="Release"/>
    <method name="RequestPinCode">
      <arg name="device" type="o" direction="in"/>
      <arg name="pincode" type="s" direction="out"/>
    </method>
    <method name="DisplayPinCode">
      <arg name="device" type="o" direction="in"/>
      <arg name="pincode" type="s" direction="in"/>
    </method>
    <method name="RequestPasskey">
      <arg name="device" type="o" direction="in"/>
      <arg name="passkey" type="u" direction="out"/>
    </method>
    <method name="DisplayPasskey">
      <arg name="device" type="o" direction="in"/>
      <arg name="passkey" type="u" direction="in"/>
      <arg name="entered" type="q" direction="in"/>
    </method>
    <method name="RequestConfirmation">
      <arg name="device" type="o" direction="in"/>
      <arg name="passkey" type="u" direction="in"/>
    </method>
    <method name="RequestAuthorization">
      <arg name="device" type="o" direction="in"/>
    </method>
    <method name="AuthorizeService">
      <arg name="device" type="o" direction="in"/>
      <arg name="uuid" type="s" direction="in"/>
    </method>
    <method name="Cancel"/>
  </interface>
</node>
)";

static std::string json_escape(std::string_view s) {
    std::string out;
    out.reserve(s.size() + 16);
    for (char c : s) {
        switch (c) {
            case '"':  out += "\\\""; break;
            case '\\': out += "\\\\"; break;
            case '\b': out += "\\b"; break;
            case '\f': out += "\\f"; break;
            case '\n': out += "\\n"; break;
            case '\r': out += "\\r"; break;
            case '\t': out += "\\t"; break;
            default:
                if (static_cast<unsigned char>(c) < 0x20) {
                    char buf[8];
                    snprintf(buf, sizeof(buf), "\\u%04x", static_cast<unsigned char>(c));
                    out += buf;
                } else {
                    out += c;
                }
                break;
        }
    }
    return out;
}

static void emit_json(const std::string& line) {
    fputs(line.c_str(), stdout);
    fputc('\n', stdout);
    fflush(stdout);
}

struct DeviceMeta {
    std::string device;
    std::string address;
    std::string name;
    std::string icon;
    bool paired = false;
    bool trusted = false;
};

static std::string meta_to_json_fields(const DeviceMeta& meta) {
    std::string s;
    s += ",\"device\":\"" + json_escape(meta.device) + "\"";
    s += ",\"address\":\"" + json_escape(meta.address) + "\"";
    s += ",\"name\":\"" + json_escape(meta.name) + "\"";
    s += ",\"icon\":\"" + json_escape(meta.icon) + "\"";
    s += ",\"paired\":" + std::string(meta.paired ? "true" : "false");
    s += ",\"trusted\":" + std::string(meta.trusted ? "true" : "false");
    return s;
}

static DeviceMeta get_device_meta(GDBusConnection* conn, const std::string& device_path) {
    DeviceMeta meta;
    meta.device = device_path;

    std::string last_component;
    auto last_slash = device_path.rfind('/');
    if (last_slash != std::string::npos && last_slash + 1 < device_path.size()) {
        last_component = device_path.substr(last_slash + 1);
    } else {
        last_component = device_path;
    }

    std::string alias_str;
    std::string name_str;

    GError* err = nullptr;
    GVariant* res = g_dbus_connection_call_sync(
        conn,
        BUS_NAME,
        device_path.c_str(),
        PROPS_IFACE,
        "GetAll",
        g_variant_new("(s)", DEVICE_IFACE),
        G_VARIANT_TYPE("(a{sv})"),
        G_DBUS_CALL_FLAGS_NONE,
        2000,
        nullptr,
        &err
    );

    if (res) {
        GVariant* dict = g_variant_get_child_value(res, 0);
        if (dict) {
            GVariantIter iter;
            g_variant_iter_init(&iter, dict);
            const gchar* key = nullptr;
            GVariant* val_variant = nullptr;
            while (g_variant_iter_next(&iter, "{&sv}", &key, &val_variant)) {
                if (key && val_variant) {
                    if (strcmp(key, "Address") == 0 && g_variant_is_of_type(val_variant, G_VARIANT_TYPE_STRING)) {
                        meta.address = g_variant_get_string(val_variant, nullptr);
                    } else if (strcmp(key, "Alias") == 0 && g_variant_is_of_type(val_variant, G_VARIANT_TYPE_STRING)) {
                        alias_str = g_variant_get_string(val_variant, nullptr);
                    } else if (strcmp(key, "Name") == 0 && g_variant_is_of_type(val_variant, G_VARIANT_TYPE_STRING)) {
                        name_str = g_variant_get_string(val_variant, nullptr);
                    } else if (strcmp(key, "Icon") == 0 && g_variant_is_of_type(val_variant, G_VARIANT_TYPE_STRING)) {
                        meta.icon = g_variant_get_string(val_variant, nullptr);
                    } else if (strcmp(key, "Paired") == 0 && g_variant_is_of_type(val_variant, G_VARIANT_TYPE_BOOLEAN)) {
                        meta.paired = g_variant_get_boolean(val_variant);
                    } else if (strcmp(key, "Trusted") == 0 && g_variant_is_of_type(val_variant, G_VARIANT_TYPE_BOOLEAN)) {
                        meta.trusted = g_variant_get_boolean(val_variant);
                    }
                }
                if (val_variant) {
                    g_variant_unref(val_variant);
                }
            }
            g_variant_unref(dict);
        }
        g_variant_unref(res);
    } else {
        if (err) g_error_free(err);
    }

    if (!alias_str.empty()) {
        meta.name = alias_str;
    } else if (!name_str.empty()) {
        meta.name = name_str;
    } else if (!meta.address.empty()) {
        meta.name = meta.address;
    } else {
        meta.name = last_component;
    }

    return meta;
}

struct PendingRequest {
    uint64_t id = 0;
    std::string kind;
    GDBusMethodInvocation* invocation = nullptr;
    guint timer_id = 0;
};

static GDBusConnection* g_connection = nullptr;
static GMainLoop* g_loop = nullptr;
static uint64_t g_next_req_id = 0;
static bool g_has_pending = false;
static PendingRequest g_pending;

static void finish_pending() {
    if (g_has_pending) {
        if (g_pending.timer_id > 0) {
            g_source_remove(g_pending.timer_id);
            g_pending.timer_id = 0;
        }
        g_has_pending = false;
        g_pending.invocation = nullptr;
    }
}

static gboolean on_request_timeout(gpointer user_data) {
    uint64_t req_id = reinterpret_cast<uintptr_t>(user_data);
    if (g_has_pending && g_pending.id == req_id) {
        GDBusMethodInvocation* inv = g_pending.invocation;
        finish_pending();
        g_dbus_method_invocation_return_dbus_error(
            inv,
            "org.bluez.Error.Rejected",
            "Timed out waiting for a response"
        );
        emit_json("{\"event\":\"resolved\",\"id\":" + std::to_string(req_id) + ",\"outcome\":\"rejected\"}");
    }
    return G_SOURCE_REMOVE;
}

static void park_request(
    const std::string& kind,
    GDBusMethodInvocation* invocation,
    const std::string& device_path,
    const std::string& extra_json = ""
) {
    if (g_has_pending) {
        uint64_t old_id = g_pending.id;
        GDBusMethodInvocation* old_inv = g_pending.invocation;
        finish_pending();
        g_dbus_method_invocation_return_dbus_error(
            old_inv,
            "org.bluez.Error.Rejected",
            "Superseded by a new request"
        );
        emit_json("{\"event\":\"superseded\",\"id\":" + std::to_string(old_id) + "}");
    }

    uint64_t req_id = ++g_next_req_id;
    g_has_pending = true;
    g_pending.id = req_id;
    g_pending.kind = kind;
    g_pending.invocation = invocation;
    g_pending.timer_id = g_timeout_add_seconds(
        120,
        on_request_timeout,
        reinterpret_cast<gpointer>(static_cast<uintptr_t>(req_id))
    );

    DeviceMeta meta = get_device_meta(g_connection, device_path);

    std::string evt = "{\"event\":\"request\",\"id\":" + std::to_string(req_id) + ",\"type\":\"" + json_escape(kind) + "\"";
    if (!extra_json.empty()) {
        evt += extra_json;
    }
    evt += meta_to_json_fields(meta);
    evt += "}";
    emit_json(evt);
}

static void on_method_call(
    GDBusConnection*       /*connection*/,
    const gchar*           /*sender*/,
    const gchar*           /*object_path*/,
    const gchar*           /*interface_name*/,
    const gchar*           method_name,
    GVariant*              parameters,
    GDBusMethodInvocation* invocation,
    gpointer               /*user_data*/
) {
    if (strcmp(method_name, "Release") == 0) {
        if (g_has_pending) {
            GDBusMethodInvocation* inv = g_pending.invocation;
            finish_pending();
            g_dbus_method_invocation_return_dbus_error(
                inv,
                "org.bluez.Error.Rejected",
                "Agent released"
            );
        }
        emit_json("{\"event\":\"released\"}");
        g_dbus_method_invocation_return_value(invocation, nullptr);
        if (g_loop) {
            g_main_loop_quit(g_loop);
        }
        return;
    }

    if (strcmp(method_name, "Cancel") == 0) {
        if (g_has_pending) {
            uint64_t req_id = g_pending.id;
            GDBusMethodInvocation* inv = g_pending.invocation;
            finish_pending();
            g_dbus_method_invocation_return_dbus_error(
                inv,
                "org.bluez.Error.Canceled",
                "Request canceled by remote device or BlueZ"
            );
            emit_json("{\"event\":\"canceled\",\"id\":" + std::to_string(req_id) + "}");
        } else {
            emit_json("{\"event\":\"canceled\",\"id\":0}");
        }
        g_dbus_method_invocation_return_value(invocation, nullptr);
        return;
    }

    if (strcmp(method_name, "RequestPinCode") == 0) {
        const gchar* dev_path = nullptr;
        g_variant_get(parameters, "(&o)", &dev_path);
        park_request("pin", invocation, dev_path ? dev_path : "");
        return;
    }

    if (strcmp(method_name, "RequestPasskey") == 0) {
        const gchar* dev_path = nullptr;
        g_variant_get(parameters, "(&o)", &dev_path);
        park_request("passkey", invocation, dev_path ? dev_path : "");
        return;
    }

    if (strcmp(method_name, "RequestConfirmation") == 0) {
        const gchar* dev_path = nullptr;
        guint32 passkey = 0;
        g_variant_get(parameters, "(&ou)", &dev_path, &passkey);
        char passkey_buf[16];
        snprintf(passkey_buf, sizeof(passkey_buf), "%06u", passkey);
        std::string extra = ",\"passkey\":\"" + std::string(passkey_buf) + "\",\"passkey_num\":" + std::to_string(passkey);
        park_request("confirm", invocation, dev_path ? dev_path : "", extra);
        return;
    }

    if (strcmp(method_name, "RequestAuthorization") == 0) {
        const gchar* dev_path = nullptr;
        g_variant_get(parameters, "(&o)", &dev_path);
        park_request("authorize", invocation, dev_path ? dev_path : "");
        return;
    }

    if (strcmp(method_name, "AuthorizeService") == 0) {
        const gchar* dev_path = nullptr;
        const gchar* uuid_str = nullptr;
        g_variant_get(parameters, "(&o&s)", &dev_path, &uuid_str);
        std::string path = dev_path ? dev_path : "";
        std::string uuid = uuid_str ? uuid_str : "";
        DeviceMeta meta = get_device_meta(g_connection, path);
        if (meta.trusted) {
            g_dbus_method_invocation_return_value(invocation, nullptr);
            emit_json("{\"event\":\"auto_authorized\",\"uuid\":\"" + json_escape(uuid) + "\",\"device\":\"" + json_escape(path) + "\"}");
        } else {
            std::string extra = ",\"uuid\":\"" + json_escape(uuid) + "\"";
            park_request("service", invocation, path, extra);
        }
        return;
    }

    if (strcmp(method_name, "DisplayPinCode") == 0) {
        const gchar* dev_path = nullptr;
        const gchar* pincode = nullptr;
        g_variant_get(parameters, "(&o&s)", &dev_path, &pincode);
        std::string path = dev_path ? dev_path : "";
        std::string pin = pincode ? pincode : "";
        DeviceMeta meta = get_device_meta(g_connection, path);
        std::string evt = "{\"event\":\"display_pin\",\"type\":\"pincode\",\"pincode\":\"" + json_escape(pin) + "\",\"pin\":\"" + json_escape(pin) + "\"";
        evt += meta_to_json_fields(meta);
        evt += "}";
        emit_json(evt);
        g_dbus_method_invocation_return_value(invocation, nullptr);
        return;
    }

    if (strcmp(method_name, "DisplayPasskey") == 0) {
        const gchar* dev_path = nullptr;
        guint32 passkey = 0;
        guint16 entered = 0;
        g_variant_get(parameters, "(&ouq)", &dev_path, &passkey, &entered);
        std::string path = dev_path ? dev_path : "";
        char passkey_buf[16];
        snprintf(passkey_buf, sizeof(passkey_buf), "%06u", passkey);
        DeviceMeta meta = get_device_meta(g_connection, path);
        std::string evt = "{\"event\":\"display_passkey\",\"type\":\"passkey\",\"passkey\":\"" + std::string(passkey_buf) + "\",\"passkey_num\":" + std::to_string(passkey) + ",\"entered\":" + std::to_string(entered);
        evt += meta_to_json_fields(meta);
        evt += "}";
        emit_json(evt);
        g_dbus_method_invocation_return_value(invocation, nullptr);
        return;
    }

    g_dbus_method_invocation_return_dbus_error(
        invocation,
        "org.bluez.Error.Rejected",
        "Unsupported method"
    );
}

struct Command {
    int64_t id = -1;
    bool has_id = false;
    std::string action;
    std::string value;
};

static void skip_ws(const std::string& s, size_t& i) {
    while (i < s.size() && (s[i] == ' ' || s[i] == '\t' || s[i] == '\r' || s[i] == '\n')) {
        i++;
    }
}

static bool parse_json_string(const std::string& s, size_t& i, std::string& out) {
    out.clear();
    if (i >= s.size() || s[i] != '"') return false;
    i++;
    while (i < s.size()) {
        char c = s[i++];
        if (c == '"') return true;
        if (c == '\\' && i < s.size()) {
            char esc = s[i++];
            switch (esc) {
                case '"': out += '"'; break;
                case '\\': out += '\\'; break;
                case '/': out += '/'; break;
                case 'b': out += '\b'; break;
                case 'f': out += '\f'; break;
                case 'n': out += '\n'; break;
                case 'r': out += '\r'; break;
                case 't': out += '\t'; break;
                default: out += esc; break;
            }
        } else {
            out += c;
        }
    }
    return false;
}

static bool parse_json_command(const std::string& json_str, Command& cmd) {
    cmd = Command{};
    size_t i = 0;
    skip_ws(json_str, i);
    if (i >= json_str.size() || json_str[i] != '{') return false;
    i++;
    while (i < json_str.size()) {
        skip_ws(json_str, i);
        if (i < json_str.size() && json_str[i] == '}') {
            i++;
            return true;
        }
        std::string key;
        if (!parse_json_string(json_str, i, key)) return false;
        skip_ws(json_str, i);
        if (i >= json_str.size() || json_str[i] != ':') return false;
        i++;
        skip_ws(json_str, i);
        if (i >= json_str.size()) return false;

        if (json_str[i] == '"') {
            std::string str_val;
            if (!parse_json_string(json_str, i, str_val)) return false;
            if (key == "id") {
                try {
                    cmd.id = std::stoll(str_val);
                    cmd.has_id = true;
                } catch (...) {}
            } else if (key == "action") {
                cmd.action = str_val;
            } else if (key == "value") {
                cmd.value = str_val;
            }
        } else if (json_str[i] == '-' || (json_str[i] >= '0' && json_str[i] <= '9')) {
            size_t start = i;
            while (i < json_str.size() && (json_str[i] == '-' || (json_str[i] >= '0' && json_str[i] <= '9') || json_str[i] == '.')) {
                i++;
            }
            std::string num_str = json_str.substr(start, i - start);
            if (key == "id") {
                try {
                    cmd.id = std::stoll(num_str);
                    cmd.has_id = true;
                } catch (...) {}
            } else if (key == "action") {
                cmd.action = num_str;
            } else if (key == "value") {
                cmd.value = num_str;
            }
        } else if (json_str.compare(i, 4, "true") == 0) {
            i += 4;
            if (key == "value") cmd.value = "true";
        } else if (json_str.compare(i, 5, "false") == 0) {
            i += 5;
            if (key == "value") cmd.value = "false";
        } else if (json_str.compare(i, 4, "null") == 0) {
            i += 4;
            if (key == "value") cmd.value = "";
        } else {
            while (i < json_str.size() && json_str[i] != ',' && json_str[i] != '}') {
                i++;
            }
        }

        skip_ws(json_str, i);
        if (i < json_str.size() && json_str[i] == ',') {
            i++;
        }
    }
    return cmd.has_id || !cmd.action.empty();
}

static void handle_stdin_line(const std::string& line) {
    Command cmd;
    if (!parse_json_command(line, cmd)) {
        return;
    }

    if (!g_has_pending) {
        if (cmd.has_id) {
            emit_json("{\"event\":\"stale_response\",\"id\":" + std::to_string(cmd.id) + "}");
        }
        return;
    }

    if (cmd.has_id && static_cast<uint64_t>(cmd.id) != g_pending.id) {
        emit_json("{\"event\":\"stale_response\",\"id\":" + std::to_string(cmd.id) + "}");
        return;
    }

    uint64_t req_id = g_pending.id;
    std::string kind = g_pending.kind;
    GDBusMethodInvocation* inv = g_pending.invocation;

    if (cmd.action == "reject" || cmd.action == "cancel") {
        finish_pending();
        g_dbus_method_invocation_return_dbus_error(
            inv,
            "org.bluez.Error.Rejected",
            "Rejected by user"
        );
        emit_json("{\"event\":\"resolved\",\"id\":" + std::to_string(req_id) + ",\"outcome\":\"rejected\"}");
        return;
    }

    if (cmd.action == "accept" || cmd.action == "value") {
        if (kind == "confirm" || kind == "authorize" || kind == "service") {
            finish_pending();
            g_dbus_method_invocation_return_value(inv, nullptr);
            emit_json("{\"event\":\"resolved\",\"id\":" + std::to_string(req_id) + ",\"outcome\":\"accepted\"}");
            return;
        }

        if (kind == "pin") {
            if (cmd.value.length() >= 1 && cmd.value.length() <= 16) {
                finish_pending();
                g_dbus_method_invocation_return_value(
                    inv,
                    g_variant_new("(s)", cmd.value.c_str())
                );
                emit_json("{\"event\":\"resolved\",\"id\":" + std::to_string(req_id) + ",\"outcome\":\"pin\"}");
            } else {
                finish_pending();
                g_dbus_method_invocation_return_dbus_error(
                    inv,
                    "org.bluez.Error.Rejected",
                    "Invalid PIN length"
                );
                emit_json("{\"event\":\"resolved\",\"id\":" + std::to_string(req_id) + ",\"outcome\":\"rejected\"}");
            }
            return;
        }

        if (kind == "passkey") {
            bool ok = false;
            uint32_t pk = 0;
            if (!cmd.value.empty()) {
                char* endptr = nullptr;
                unsigned long val = strtoul(cmd.value.c_str(), &endptr, 10);
                if (endptr && *endptr == '\0' && val <= 999999) {
                    pk = static_cast<uint32_t>(val);
                    ok = true;
                }
            }
            if (ok) {
                finish_pending();
                g_dbus_method_invocation_return_value(
                    inv,
                    g_variant_new("(u)", static_cast<guint32>(pk))
                );
                emit_json("{\"event\":\"resolved\",\"id\":" + std::to_string(req_id) + ",\"outcome\":\"passkey\"}");
            } else {
                finish_pending();
                g_dbus_method_invocation_return_dbus_error(
                    inv,
                    "org.bluez.Error.Rejected",
                    "Invalid passkey"
                );
                emit_json("{\"event\":\"resolved\",\"id\":" + std::to_string(req_id) + ",\"outcome\":\"rejected\"}");
            }
            return;
        }
    }
}

static std::string g_stdin_buf;

static gboolean on_stdin_fd(gint fd, GIOCondition condition, gpointer /*user_data*/) {
    if (condition & G_IO_IN) {
        while (true) {
            char buf[4096];
            ssize_t bytes_read = read(fd, buf, sizeof(buf));
            if (bytes_read > 0) {
                g_stdin_buf.append(buf, static_cast<size_t>(bytes_read));
            } else if (bytes_read == 0) {
                // EOF
                if (g_loop) {
                    g_main_loop_quit(g_loop);
                }
                return G_SOURCE_REMOVE;
            } else {
                if (errno == EAGAIN || errno == EWOULDBLOCK) {
                    break;
                } else if (errno == EINTR) {
                    continue;
                } else {
                    if (g_loop) {
                        g_main_loop_quit(g_loop);
                    }
                    return G_SOURCE_REMOVE;
                }
            }
        }

        size_t newline_pos;
        while ((newline_pos = g_stdin_buf.find('\n')) != std::string::npos) {
            std::string line = g_stdin_buf.substr(0, newline_pos);
            g_stdin_buf.erase(0, newline_pos + 1);

            while (!line.empty() && (line.back() == '\r' || line.back() == ' ' || line.back() == '\t')) {
                line.pop_back();
            }
            size_t start = 0;
            while (start < line.size() && (line[start] == ' ' || line[start] == '\t')) {
                start++;
            }
            if (start > 0) {
                line = line.substr(start);
            }

            if (!line.empty()) {
                handle_stdin_line(line);
            }
        }
    }

    if (condition & (G_IO_HUP | G_IO_ERR)) {
        if (g_loop) {
            g_main_loop_quit(g_loop);
        }
        return G_SOURCE_REMOVE;
    }

    return G_SOURCE_CONTINUE;
}

static gboolean on_unix_signal(gpointer /*user_data*/) {
    if (g_loop) {
        g_main_loop_quit(g_loop);
    }
    return G_SOURCE_REMOVE;
}

int main(int argc, char* argv[]) {
    std::string capability = "DisplayYesNo";
    if (argc > 1 && argv[1] != nullptr && argv[1][0] != '\0') {
        std::string cap = argv[1];
        static const std::unordered_set<std::string> valid_caps = {
            "DisplayOnly", "DisplayYesNo", "KeyboardOnly", "NoInputNoOutput", "KeyboardDisplay"
        };
        if (valid_caps.contains(cap)) {
            capability = cap;
        } else {
            std::cerr << "Warning: invalid capability '" << cap << "', defaulting to DisplayYesNo\n";
        }
    }

    GError* error = nullptr;
    g_connection = g_bus_get_sync(G_BUS_TYPE_SYSTEM, nullptr, &error);
    if (!g_connection) {
        std::string msg = error && error->message ? error->message : "Failed to connect to system bus";
        emit_json("{\"event\":\"error\",\"stage\":\"bus\",\"message\":\"" + json_escape(msg) + "\"}");
        if (error) g_error_free(error);
        return 1;
    }

    GDBusNodeInfo* node_info = g_dbus_node_info_new_for_xml(AGENT_XML, &error);
    if (!node_info) {
        std::string msg = error && error->message ? error->message : "Invalid agent XML";
        emit_json("{\"event\":\"error\",\"stage\":\"xml\",\"message\":\"" + json_escape(msg) + "\"}");
        if (error) g_error_free(error);
        g_object_unref(g_connection);
        return 1;
    }

    static const GDBusInterfaceVTable agent_vtable = {
        .method_call = on_method_call,
        .get_property = nullptr,
        .set_property = nullptr,
        .padding = { nullptr }
    };

    guint registration_id = g_dbus_connection_register_object(
        g_connection,
        AGENT_PATH,
        node_info->interfaces[0],
        &agent_vtable,
        nullptr,
        nullptr,
        &error
    );

    if (registration_id == 0) {
        std::string msg = error && error->message ? error->message : "Failed to export agent object";
        emit_json("{\"event\":\"error\",\"stage\":\"export\",\"message\":\"" + json_escape(msg) + "\"}");
        if (error) g_error_free(error);
        g_dbus_node_info_unref(node_info);
        g_object_unref(g_connection);
        return 1;
    }

    // Call RegisterAgent
    GError* reg_err = nullptr;
    GVariant* reg_res = g_dbus_connection_call_sync(
        g_connection,
        BUS_NAME,
        "/org/bluez",
        AGENT_MANAGER_IFACE,
        "RegisterAgent",
        g_variant_new("(os)", AGENT_PATH, capability.c_str()),
        nullptr,
        G_DBUS_CALL_FLAGS_NONE,
        5000,
        nullptr,
        &reg_err
    );

    if (!reg_res) {
        bool already_exists = false;
        if (reg_err) {
            if (g_dbus_error_is_remote_error(reg_err)) {
                char* remote_err = g_dbus_error_get_remote_error(reg_err);
                if (remote_err) {
                    if (strcmp(remote_err, "org.bluez.Error.AlreadyExists") == 0) {
                        already_exists = true;
                    }
                    g_free(remote_err);
                }
            }
            if (!already_exists && reg_err->message && strstr(reg_err->message, "AlreadyExists") != nullptr) {
                already_exists = true;
            }
        }

        if (already_exists) {
            g_clear_error(&reg_err);
            GVariant* unreg_res = g_dbus_connection_call_sync(
                g_connection,
                BUS_NAME,
                "/org/bluez",
                AGENT_MANAGER_IFACE,
                "UnregisterAgent",
                g_variant_new("(o)", AGENT_PATH),
                nullptr,
                G_DBUS_CALL_FLAGS_NONE,
                5000,
                nullptr,
                &reg_err
            );
            if (unreg_res) g_variant_unref(unreg_res);
            if (reg_err) g_clear_error(&reg_err);

            reg_res = g_dbus_connection_call_sync(
                g_connection,
                BUS_NAME,
                "/org/bluez",
                AGENT_MANAGER_IFACE,
                "RegisterAgent",
                g_variant_new("(os)", AGENT_PATH, capability.c_str()),
                nullptr,
                G_DBUS_CALL_FLAGS_NONE,
                5000,
                nullptr,
                &reg_err
            );
        }
    }

    if (!reg_res) {
        std::string msg = reg_err && reg_err->message ? reg_err->message : "Failed to register agent";
        emit_json("{\"event\":\"error\",\"stage\":\"register\",\"message\":\"" + json_escape(msg) + "\"}");
        if (reg_err) g_error_free(reg_err);
        g_dbus_connection_unregister_object(g_connection, registration_id);
        g_dbus_node_info_unref(node_info);
        g_object_unref(g_connection);
        return 1;
    }
    g_variant_unref(reg_res);

    // Call RequestDefaultAgent
    bool is_default = false;
    GError* def_err = nullptr;
    GVariant* def_res = g_dbus_connection_call_sync(
        g_connection,
        BUS_NAME,
        "/org/bluez",
        AGENT_MANAGER_IFACE,
        "RequestDefaultAgent",
        g_variant_new("(o)", AGENT_PATH),
        nullptr,
        G_DBUS_CALL_FLAGS_NONE,
        5000,
        nullptr,
        &def_err
    );

    if (def_res) {
        g_variant_unref(def_res);
        is_default = true;
    } else {
        std::string wmsg = def_err && def_err->message ? def_err->message : "RequestDefaultAgent failed";
        emit_json("{\"event\":\"warning\",\"stage\":\"default\",\"message\":\"" + json_escape(wmsg) + "\"}");
        if (def_err) g_error_free(def_err);
        is_default = false;
    }

    emit_json("{\"event\":\"ready\",\"capability\":\"" + json_escape(capability) + "\",\"default\":" + (is_default ? "true" : "false") + "}");

    g_loop = g_main_loop_new(nullptr, FALSE);

    // Setup signal handling
    g_unix_signal_add(SIGINT, on_unix_signal, nullptr);
    g_unix_signal_add(SIGTERM, on_unix_signal, nullptr);
    g_unix_signal_add(SIGHUP, on_unix_signal, nullptr);

    // Non-blocking stdin setup
    int fl = fcntl(STDIN_FILENO, F_GETFL, 0);
    if (fl >= 0) {
        fcntl(STDIN_FILENO, F_SETFL, fl | O_NONBLOCK);
    }
    g_unix_fd_add(STDIN_FILENO, static_cast<GIOCondition>(G_IO_IN | G_IO_HUP | G_IO_ERR), on_stdin_fd, nullptr);

    g_main_loop_run(g_loop);

    // Clean shutdown
    if (g_has_pending) {
        GDBusMethodInvocation* inv = g_pending.invocation;
        finish_pending();
        g_dbus_method_invocation_return_dbus_error(
            inv,
            "org.bluez.Error.Rejected",
            "Agent stopped"
        );
    }

    // Call UnregisterAgent
    GError* unreg_err = nullptr;
    GVariant* unreg_res = g_dbus_connection_call_sync(
        g_connection,
        BUS_NAME,
        "/org/bluez",
        AGENT_MANAGER_IFACE,
        "UnregisterAgent",
        g_variant_new("(o)", AGENT_PATH),
        nullptr,
        G_DBUS_CALL_FLAGS_NONE,
        2000,
        nullptr,
        &unreg_err
    );
    if (unreg_res) g_variant_unref(unreg_res);
    if (unreg_err) g_error_free(unreg_err);

    if (registration_id > 0) {
        g_dbus_connection_unregister_object(g_connection, registration_id);
    }
    g_dbus_node_info_unref(node_info);
    g_main_loop_unref(g_loop);
    g_object_unref(g_connection);

    return 0;
}
