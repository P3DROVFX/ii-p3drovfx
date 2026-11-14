#include <gio/gio.h>
#include <glib-unix.h>
#include <csignal>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <string>
#include <string_view>
#include <memory>
#include <unordered_map>

// JSON string escaping helper
static std::string json_escape(std::string_view s) {
    std::string out;
    out.reserve(s.size() + 16);
    for (size_t i = 0; i < s.size(); ++i) {
        unsigned char c = static_cast<unsigned char>(s[i]);
        switch (c) {
            case '"': out += "\\\""; break;
            case '\\': out += "\\\\"; break;
            case '\b': out += "\\b"; break;
            case '\f': out += "\\f"; break;
            case '\n': out += "\\n"; break;
            case '\r': out += "\\r"; break;
            case '\t': out += "\\t"; break;
            default:
                if (c < 0x20) {
                    char buf[8];
                    snprintf(buf, sizeof(buf), "\\u%04x", c);
                    out += buf;
                } else {
                    out += static_cast<char>(c);
                }
                break;
        }
    }
    return out;
}

// JSON Protocol emitters
static void emit_update(const std::string &id,
                        const std::string &app_name,
                        const std::string &app_icon,
                        const std::string &state,
                        uint32_t percent,
                        const std::string &message,
                        int64_t speed,
                        int64_t processed,
                        int64_t total,
                        const std::string &unit)
{
    std::string out;
    out.reserve(256);
    out += "{\"event\":\"update\",\"id\":\"";
    out += json_escape(id);
    out += "\",\"appName\":\"";
    out += json_escape(app_name);
    out += "\",\"appIcon\":\"";
    out += json_escape(app_icon);
    out += "\",\"state\":\"";
    out += json_escape(state);
    out += "\",\"percent\":";
    out += std::to_string(percent);
    out += ",\"message\":\"";
    out += json_escape(message);
    out += "\",\"infoMessage\":\"";
    out += json_escape(message);
    out += "\",\"speed\":";
    out += std::to_string(speed);
    out += ",\"processed\":";
    out += std::to_string(processed);
    out += ",\"total\":";
    out += std::to_string(total);
    out += ",\"unit\":\"";
    out += json_escape(unit);
    out += "\"}\n";

    fputs(out.c_str(), stdout);
    fflush(stdout);
}

static void emit_terminate(const std::string &id, const std::string &error) {
    std::string out;
    out.reserve(128);
    out += "{\"event\":\"terminate\",\"id\":\"";
    out += json_escape(id);
    out += "\",\"error\":\"";
    out += json_escape(error);
    out += "\"}\n";

    fputs(out.c_str(), stdout);
    fflush(stdout);
}

static void emit_status(const std::string &status) {
    std::string out;
    out.reserve(64);
    out += "{\"event\":\"status\",\"status\":\"";
    out += json_escape(status);
    out += "\"}\n";

    fputs(out.c_str(), stdout);
    fflush(stdout);
}

static void emit_error(const std::string &message) {
    std::string out;
    out.reserve(128);
    out += "{\"event\":\"error\",\"message\":\"";
    out += json_escape(message);
    out += "\"}\n";

    fputs(out.c_str(), stdout);
    fflush(stdout);
}

// Introspection XML definitions
static const char *g_server_introspection_xml = R"XML(
<!DOCTYPE node PUBLIC "-//freedesktop//DTD D-BUS Object Introspection 1.0//EN"
"http://www.freedesktop.org/standards/dbus/1.0/introspect.dtd">
<node>
  <interface name="org.kde.JobViewServer">
    <method name="requestView">
      <arg name="appName" type="s" direction="in"/>
      <arg name="appIconName" type="s" direction="in"/>
      <arg name="capabilities" type="i" direction="in"/>
      <arg name="jobPath" type="o" direction="out"/>
    </method>
    <method name="UpdateProgress">
      <arg name="job_id" type="s" direction="in"/>
      <arg name="app_name" type="s" direction="in"/>
      <arg name="app_icon" type="s" direction="in"/>
      <arg name="percent" type="u" direction="in"/>
      <arg name="info_message" type="s" direction="in"/>
    </method>
    <method name="TerminateProgress">
      <arg name="job_id" type="s" direction="in"/>
    </method>
  </interface>
</node>
)XML";

static const char *g_job_introspection_xml = R"XML(
<!DOCTYPE node PUBLIC "-//freedesktop//DTD D-BUS Object Introspection 1.0//EN"
"http://www.freedesktop.org/standards/dbus/1.0/introspect.dtd">
<node>
  <interface name="org.kde.JobViewV2">
    <method name="setPercent">
      <arg name="percent" type="u" direction="in"/>
    </method>
    <method name="setInfoMessage">
      <arg name="message" type="s" direction="in"/>
    </method>
    <method name="setProcessedAmount">
      <arg name="amount" type="x" direction="in"/>
      <arg name="unit" type="s" direction="in"/>
    </method>
    <method name="setTotalAmount">
      <arg name="amount" type="x" direction="in"/>
      <arg name="unit" type="s" direction="in"/>
    </method>
    <method name="setSpeed">
      <arg name="bytesPerSecond" type="x" direction="in"/>
    </method>
    <method name="terminate">
      <arg name="errorMessage" type="s" direction="in"/>
    </method>
    <method name="clear">
    </method>
    <method name="setSuspended">
      <arg name="suspended" type="b" direction="in"/>
    </method>
    <method name="setDescriptionField">
      <arg name="number" type="u" direction="in"/>
      <arg name="name" type="s" direction="in"/>
      <arg name="value" type="s" direction="in"/>
    </method>
    <method name="clearDescriptionField">
      <arg name="number" type="u" direction="in"/>
    </method>
    <method name="cancel">
    </method>
    <method name="suspend">
    </method>
    <method name="resume">
    </method>
    <method name="setDestUrl">
      <arg name="url" type="s" direction="in"/>
    </method>
  </interface>
  <interface name="org.kde.JobView">
    <method name="setPercent">
      <arg name="percent" type="u" direction="in"/>
    </method>
    <method name="setInfoMessage">
      <arg name="message" type="s" direction="in"/>
    </method>
    <method name="setProcessedAmount">
      <arg name="amount" type="x" direction="in"/>
      <arg name="unit" type="s" direction="in"/>
    </method>
    <method name="setTotalAmount">
      <arg name="amount" type="x" direction="in"/>
      <arg name="unit" type="s" direction="in"/>
    </method>
    <method name="setSpeed">
      <arg name="bytesPerSecond" type="x" direction="in"/>
    </method>
    <method name="terminate">
      <arg name="errorMessage" type="s" direction="in"/>
    </method>
    <method name="clear">
    </method>
    <method name="setSuspended">
      <arg name="suspended" type="b" direction="in"/>
    </method>
    <method name="setDescriptionField">
      <arg name="number" type="u" direction="in"/>
      <arg name="name" type="s" direction="in"/>
      <arg name="value" type="s" direction="in"/>
    </method>
    <method name="clearDescriptionField">
      <arg name="number" type="u" direction="in"/>
    </method>
    <method name="cancel">
    </method>
    <method name="suspend">
    </method>
    <method name="resume">
    </method>
    <method name="setDestUrl">
      <arg name="url" type="s" direction="in"/>
    </method>
  </interface>
</node>
)XML";

// Job State
struct JobState {
    std::string id;
    std::string path;
    std::string app_name;
    std::string app_icon;
    int32_t capabilities = 0;
    uint32_t percent = 0;
    std::string message;
    int64_t speed = 0;
    int64_t processed = 0;
    int64_t total = 0;
    std::string unit;
    bool terminating = false;
    guint reg_id_v2 = 0;
    guint reg_id_v1 = 0;
};

// Global context
static GMainLoop *g_main_loop = nullptr;
static guint64 g_next_job_id = 0;
static std::unordered_map<std::string, std::unique_ptr<JobState>> g_active_jobs;

static GDBusNodeInfo *g_server_node_info = nullptr;
static GDBusInterfaceInfo *g_jobview_server_interface_info = nullptr;
static GDBusNodeInfo *g_job_node_info = nullptr;
static GDBusInterfaceInfo *g_jobview_v2_interface_info = nullptr;
static GDBusInterfaceInfo *g_jobview_v1_interface_info = nullptr;

static guint g_server_reg_id = 0;
static guint g_progress_server_reg_id = 0;

static void emit_job_update(const JobState *job, const std::string &state) {
    emit_update(
        job->id,
        job->app_name,
        job->app_icon,
        state,
        job->percent,
        job->message,
        job->speed,
        job->processed,
        job->total,
        job->unit
    );
}

// Cleanup job on idle
struct JobCleanupContext {
    GDBusConnection *connection;
    std::string job_id;
};

static gboolean on_job_cleanup_idle(gpointer user_data) {
    auto *ctx = static_cast<JobCleanupContext*>(user_data);
    auto it = g_active_jobs.find(ctx->job_id);
    if (it != g_active_jobs.end()) {
        JobState *job = it->second.get();
        if (job->reg_id_v2 > 0) {
            g_dbus_connection_unregister_object(ctx->connection, job->reg_id_v2);
            job->reg_id_v2 = 0;
        }
        if (job->reg_id_v1 > 0) {
            g_dbus_connection_unregister_object(ctx->connection, job->reg_id_v1);
            job->reg_id_v1 = 0;
        }
        g_active_jobs.erase(it);
    }
    delete ctx;
    return G_SOURCE_REMOVE;
}

static void schedule_job_cleanup(GDBusConnection *conn, const std::string &job_id) {
    auto *ctx = new JobCleanupContext{conn, job_id};
    g_idle_add(on_job_cleanup_idle, ctx);
}

// JobView and JobViewV2 method call handler
static void job_method_call(GDBusConnection *connection,
                            const gchar *sender,
                            const gchar *object_path,
                            const gchar *interface_name,
                            const gchar *method_name,
                            GVariant *parameters,
                            GDBusMethodInvocation *invocation,
                            gpointer user_data)
{
    (void)sender;
    (void)object_path;
    (void)interface_name;
    auto *job = static_cast<JobState*>(user_data);
    if (!job) {
        g_dbus_method_invocation_return_error(
            invocation,
            G_DBUS_ERROR,
            G_DBUS_ERROR_FAILED,
            "Internal error: missing job state"
        );
        return;
    }

    if (g_strcmp0(method_name, "setPercent") == 0) {
        guint32 percent = 0;
        if (g_variant_is_of_type(parameters, G_VARIANT_TYPE("(u)"))) {
            g_variant_get(parameters, "(u)", &percent);
        }
        job->percent = percent;
        if (!job->terminating) {
            emit_job_update(job, "running");
        }
        g_dbus_method_invocation_return_value(invocation, nullptr);
        return;
    }

    if (g_strcmp0(method_name, "setInfoMessage") == 0) {
        const gchar *msg = "";
        if (g_variant_is_of_type(parameters, G_VARIANT_TYPE("(s)"))) {
            g_variant_get(parameters, "(&s)", &msg);
        }
        job->message = msg ? msg : "";
        if (!job->terminating) {
            emit_job_update(job, "running");
        }
        g_dbus_method_invocation_return_value(invocation, nullptr);
        return;
    }

    if (g_strcmp0(method_name, "setProcessedAmount") == 0) {
        gint64 amount = 0;
        const gchar *unit = "";
        if (g_variant_is_of_type(parameters, G_VARIANT_TYPE("(xs)"))) {
            g_variant_get(parameters, "(x&s)", &amount, &unit);
            job->unit = unit ? unit : "";
        } else if (g_variant_is_of_type(parameters, G_VARIANT_TYPE("(ts)"))) {
            guint64 uamount = 0;
            g_variant_get(parameters, "(t&s)", &uamount, &unit);
            amount = static_cast<gint64>(uamount);
            job->unit = unit ? unit : "";
        } else if (g_variant_is_of_type(parameters, G_VARIANT_TYPE("(x)"))) {
            g_variant_get(parameters, "(x)", &amount);
        } else if (g_variant_is_of_type(parameters, G_VARIANT_TYPE("(t)"))) {
            guint64 uamount = 0;
            g_variant_get(parameters, "(t)", &uamount);
            amount = static_cast<gint64>(uamount);
        }
        job->processed = amount;
        if (!job->terminating) {
            emit_job_update(job, "running");
        }
        g_dbus_method_invocation_return_value(invocation, nullptr);
        return;
    }

    if (g_strcmp0(method_name, "setTotalAmount") == 0) {
        gint64 amount = 0;
        const gchar *unit = "";
        if (g_variant_is_of_type(parameters, G_VARIANT_TYPE("(xs)"))) {
            g_variant_get(parameters, "(x&s)", &amount, &unit);
            job->unit = unit ? unit : "";
        } else if (g_variant_is_of_type(parameters, G_VARIANT_TYPE("(ts)"))) {
            guint64 uamount = 0;
            g_variant_get(parameters, "(t&s)", &uamount, &unit);
            amount = static_cast<gint64>(uamount);
            job->unit = unit ? unit : "";
        } else if (g_variant_is_of_type(parameters, G_VARIANT_TYPE("(x)"))) {
            g_variant_get(parameters, "(x)", &amount);
        } else if (g_variant_is_of_type(parameters, G_VARIANT_TYPE("(t)"))) {
            guint64 uamount = 0;
            g_variant_get(parameters, "(t)", &uamount);
            amount = static_cast<gint64>(uamount);
        }
        job->total = amount;
        if (!job->terminating) {
            emit_job_update(job, "running");
        }
        g_dbus_method_invocation_return_value(invocation, nullptr);
        return;
    }

    if (g_strcmp0(method_name, "setSpeed") == 0) {
        gint64 speed = 0;
        if (g_variant_is_of_type(parameters, G_VARIANT_TYPE("(x)"))) {
            g_variant_get(parameters, "(x)", &speed);
        } else if (g_variant_is_of_type(parameters, G_VARIANT_TYPE("(t)"))) {
            guint64 uspeed = 0;
            g_variant_get(parameters, "(t)", &uspeed);
            speed = static_cast<gint64>(uspeed);
        }
        job->speed = speed;
        if (!job->terminating) {
            emit_job_update(job, "running");
        }
        g_dbus_method_invocation_return_value(invocation, nullptr);
        return;
    }

    if (g_strcmp0(method_name, "terminate") == 0) {
        const gchar *err = "";
        if (g_variant_is_of_type(parameters, G_VARIANT_TYPE("(s)"))) {
            g_variant_get(parameters, "(&s)", &err);
        }
        std::string error_msg = err ? err : "";
        if (!job->terminating) {
            job->terminating = true;
            emit_terminate(job->id, error_msg);
            schedule_job_cleanup(connection, job->id);
        }
        g_dbus_method_invocation_return_value(invocation, nullptr);
        return;
    }

    if (g_strcmp0(method_name, "clear") == 0) {
        if (!job->terminating) {
            job->terminating = true;
            emit_terminate(job->id, "");
            schedule_job_cleanup(connection, job->id);
        }
        g_dbus_method_invocation_return_value(invocation, nullptr);
        return;
    }

    // Fallback for optional/extra KDE JobView methods:
    // setSuspended(b), setDescriptionField(uss), clearDescriptionField(u), cancel(), suspend(), resume(), setDestUrl(s)
    g_dbus_method_invocation_return_value(invocation, nullptr);
}

static const GDBusInterfaceVTable g_job_vtable = {
    job_method_call,
    nullptr,
    nullptr,
    { 0 }
};

// Server (/JobViewServer and /ProgressServer) method call handler
static void server_method_call(GDBusConnection *connection,
                               const gchar *sender,
                               const gchar *object_path,
                               const gchar *interface_name,
                               const gchar *method_name,
                               GVariant *parameters,
                               GDBusMethodInvocation *invocation,
                               gpointer user_data)
{
    (void)sender;
    (void)object_path;
    (void)interface_name;
    (void)user_data;

    if (g_strcmp0(method_name, "requestView") == 0) {
        const gchar *app_name = "";
        const gchar *app_icon = "";
        gint32 capabilities = 0;
        if (g_variant_is_of_type(parameters, G_VARIANT_TYPE("(ssi)"))) {
            g_variant_get(parameters, "(&s&si)", &app_name, &app_icon, &capabilities);
        } else if (g_variant_is_of_type(parameters, G_VARIANT_TYPE("(ssu)"))) {
            guint32 ucaps = 0;
            g_variant_get(parameters, "(&s&su)", &app_name, &app_icon, &ucaps);
            capabilities = static_cast<gint32>(ucaps);
        }

        guint64 id_num = ++g_next_job_id;
        std::string job_id = "job_" + std::to_string(id_num);
        std::string job_path = "/JobViewServer/" + job_id;

        auto job = std::make_unique<JobState>();
        job->id = job_id;
        job->path = job_path;
        job->app_name = app_name ? app_name : "";
        job->app_icon = app_icon ? app_icon : "";
        job->capabilities = capabilities;
        job->percent = 0;
        job->message = "";
        job->speed = 0;
        job->processed = 0;
        job->total = 0;
        job->unit = "";
        job->terminating = false;

        // Emit initial update event
        emit_job_update(job.get(), "created");

        GError *error = nullptr;
        job->reg_id_v2 = g_dbus_connection_register_object(
            connection,
            job_path.c_str(),
            g_jobview_v2_interface_info,
            &g_job_vtable,
            job.get(),
            nullptr,
            &error
        );
        if (error) {
            emit_error(std::string("Register JobViewV2 on ") + job_path + " failed: " + error->message);
            g_clear_error(&error);
        }

        job->reg_id_v1 = g_dbus_connection_register_object(
            connection,
            job_path.c_str(),
            g_jobview_v1_interface_info,
            &g_job_vtable,
            job.get(),
            nullptr,
            &error
        );
        if (error) {
            emit_error(std::string("Register JobView on ") + job_path + " failed: " + error->message);
            g_clear_error(&error);
        }

        g_active_jobs[job_id] = std::move(job);

        g_dbus_method_invocation_return_value(invocation, g_variant_new("(o)", job_path.c_str()));
        return;
    }

    if (g_strcmp0(method_name, "UpdateProgress") == 0) {
        const gchar *job_id = "";
        const gchar *app_name = "";
        const gchar *app_icon = "";
        guint32 percent = 0;
        const gchar *message = "";
        if (g_variant_is_of_type(parameters, G_VARIANT_TYPE("(sssus)"))) {
            g_variant_get(parameters, "(&s&s&su&s)", &job_id, &app_name, &app_icon, &percent, &message);
        }
        std::string state = (percent < 100) ? "running" : "completed";
        emit_update(
            job_id ? job_id : "",
            app_name ? app_name : "",
            app_icon ? app_icon : "",
            state,
            percent,
            message ? message : "",
            0, 0, 0, ""
        );
        g_dbus_method_invocation_return_value(invocation, nullptr);
        return;
    }

    if (g_strcmp0(method_name, "TerminateProgress") == 0) {
        const gchar *job_id = "";
        if (g_variant_is_of_type(parameters, G_VARIANT_TYPE("(s)"))) {
            g_variant_get(parameters, "(&s)", &job_id);
        }
        emit_terminate(job_id ? job_id : "", "");
        g_dbus_method_invocation_return_value(invocation, nullptr);
        return;
    }

    g_dbus_method_invocation_return_error(
        invocation,
        G_DBUS_ERROR,
        G_DBUS_ERROR_UNKNOWN_METHOD,
        "Unknown method %s on %s",
        method_name ? method_name : "(null)",
        interface_name ? interface_name : "(null)"
    );
}

static const GDBusInterfaceVTable g_server_vtable = {
    server_method_call,
    nullptr,
    nullptr,
    { 0 }
};

// D-Bus Name Ownership Handlers
static void on_bus_acquired(GDBusConnection *connection,
                            const gchar *name,
                            gpointer user_data)
{
    (void)name;
    (void)user_data;
    GError *error = nullptr;

    g_server_reg_id = g_dbus_connection_register_object(
        connection,
        "/JobViewServer",
        g_jobview_server_interface_info,
        &g_server_vtable,
        connection,
        nullptr,
        &error
    );
    if (error) {
        emit_error(std::string("Register /JobViewServer error: ") + error->message);
        g_clear_error(&error);
    }

    g_progress_server_reg_id = g_dbus_connection_register_object(
        connection,
        "/ProgressServer",
        g_jobview_server_interface_info,
        &g_server_vtable,
        connection,
        nullptr,
        &error
    );
    if (error) {
        emit_error(std::string("Register /ProgressServer error: ") + error->message);
        g_clear_error(&error);
    }
}

static void on_name_acquired(GDBusConnection *connection,
                             const gchar *name,
                             gpointer user_data)
{
    (void)connection;
    (void)name;
    (void)user_data;
    emit_status("running");
}

static void on_name_lost(GDBusConnection *connection,
                         const gchar *name,
                         gpointer user_data)
{
    (void)name;
    auto *loop = static_cast<GMainLoop*>(user_data);
    if (!connection) {
        emit_error("Failed to connect to D-Bus session bus");
    } else {
        emit_error("Lost or failed to acquire D-Bus name org.kde.JobViewServer");
    }
    if (loop && g_main_loop_is_running(loop)) {
        g_main_loop_quit(loop);
    }
}

// Unix signal handler for graceful shutdown
static gboolean on_signal(gpointer user_data) {
    auto *loop = static_cast<GMainLoop*>(user_data);
    if (loop && g_main_loop_is_running(loop)) {
        g_main_loop_quit(loop);
    }
    return G_SOURCE_REMOVE;
}

int main(int argc, char **argv) {
    (void)argc;
    (void)argv;

    // Line buffered stdout
    setvbuf(stdout, nullptr, _IOLBF, 0);

    GError *error = nullptr;
    g_server_node_info = g_dbus_node_info_new_for_xml(g_server_introspection_xml, &error);
    if (!g_server_node_info || error) {
        emit_error(std::string("Failed to parse server introspection XML: ") + (error ? error->message : "unknown"));
        return 1;
    }
    g_jobview_server_interface_info = g_dbus_node_info_lookup_interface(g_server_node_info, "org.kde.JobViewServer");

    g_job_node_info = g_dbus_node_info_new_for_xml(g_job_introspection_xml, &error);
    if (!g_job_node_info || error) {
        emit_error(std::string("Failed to parse job introspection XML: ") + (error ? error->message : "unknown"));
        return 1;
    }
    g_jobview_v2_interface_info = g_dbus_node_info_lookup_interface(g_job_node_info, "org.kde.JobViewV2");
    g_jobview_v1_interface_info = g_dbus_node_info_lookup_interface(g_job_node_info, "org.kde.JobView");

    g_main_loop = g_main_loop_new(nullptr, FALSE);

    // Clean exit on SIGINT and SIGTERM
    g_unix_signal_add(SIGINT, on_signal, g_main_loop);
    g_unix_signal_add(SIGTERM, on_signal, g_main_loop);

    guint owner_id = g_bus_own_name(
        G_BUS_TYPE_SESSION,
        "org.kde.JobViewServer",
        static_cast<GBusNameOwnerFlags>(G_BUS_NAME_OWNER_FLAGS_REPLACE | G_BUS_NAME_OWNER_FLAGS_ALLOW_REPLACEMENT),
        on_bus_acquired,
        on_name_acquired,
        on_name_lost,
        g_main_loop,
        nullptr
    );

    g_main_loop_run(g_main_loop);

    g_bus_unown_name(owner_id);

    g_active_jobs.clear();

    if (g_server_node_info) {
        g_dbus_node_info_unref(g_server_node_info);
    }
    if (g_job_node_info) {
        g_dbus_node_info_unref(g_job_node_info);
    }
    if (g_main_loop) {
        g_main_loop_unref(g_main_loop);
    }

    return 0;
}
