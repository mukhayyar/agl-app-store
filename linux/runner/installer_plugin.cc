#define FLUTTER_PLUGIN_IMPL
#include "installer_plugin.h"

#include <flutter_linux/flutter_linux.h>
#include <glib.h>
#include <gtk/gtk.h>
#include <cstring>

// ---------------- Channel & Method Names ----------------
static const char *kChannelName = "com.example.flathub/installer";
static const char *kMethodInstall = "installFlatpak";
static const char *kMethodIsInstalled = "isInstalled";
static const char *kMethodListInstalled = "listInstalled";
static const char *kMethodUninstall = "uninstallFlatpak";
static const char *kMethodUpdate = "updateFlatpak";
static const char *kEventsChannelName = "com.example.flathub/installer_events";
static FlEventChannel *g_events_channel = nullptr;

static void send_event_json(const gchar *json);
// ---------------- Plugin Types ----------------
typedef struct _FlathubInstallerPlugin
{
    GObject parent_instance;
    FlMethodChannel *channel;
} FlathubInstallerPlugin;

typedef struct _FlathubInstallerPluginClass
{
    GObjectClass parent_class;
} FlathubInstallerPluginClass;

G_DEFINE_TYPE(FlathubInstallerPlugin, flathub_installer_plugin, G_TYPE_OBJECT)

typedef struct
{
    GPid pid;
    gchar *app_id;
} InstallContext;

static gboolean io_cb(GIOChannel *source, GIOCondition cond, gpointer user_data)
{
    const gchar *app_id = (const gchar *)user_data;
    if (cond & (G_IO_HUP | G_IO_ERR | G_IO_NVAL))
        return FALSE;

    gchar *line = nullptr;
    gsize len = 0;
    GError *err = nullptr;
    GIOStatus st = g_io_channel_read_line(source, &line, &len, nullptr, &err);
    if (st == G_IO_STATUS_NORMAL && line)
    {
        // kirim sebagai event JSON
        gchar *json = g_strdup_printf("{\"type\":\"stdout\",\"appId\":\"%s\",\"line\":%s}",
                                      app_id, g_strescape(line, nullptr));
        send_event_json(json);
        g_free(json);
        g_free(line);
    }
    if (err)
        g_error_free(err);
    return TRUE; // keep watching
}

static void child_watch_cb(GPid pid, gint status, gpointer user_data)
{
    const gchar *app_id = (const gchar *)user_data;
    gchar *json = g_strdup_printf("{\"type\":\"done\",\"appId\":\"%s\",\"status\":%d}",
                                  app_id, status);
    send_event_json(json);
    g_free(json);
    g_spawn_close_pid(pid);
    g_free((gpointer)app_id);
}

// ---------------- Helper: build argv & spawn ----------------
static void send_event_json(const gchar *json)
{
    if (!g_events_channel)
        return;
    FlValue *v = fl_value_new_string(json);
    fl_event_channel_send(g_events_channel, v, nullptr, nullptr);
}

static gboolean spawn_and_capture(char const *const *argv_in,
                                  gchar **stdout_out,
                                  gchar **stderr_out,
                                  gint *exit_status,
                                  GError **error)
{
    // g_spawn_sync but we need non-const gchar** argv; make a copy.
    GPtrArray *arr = g_ptr_array_new();
    for (int i = 0; argv_in[i] != nullptr; ++i)
    {
        g_ptr_array_add(arr, g_strdup(argv_in[i]));
    }
    g_ptr_array_add(arr, nullptr); // null-terminate

    gboolean ok = g_spawn_sync(
        /*working_directory=*/nullptr,
        /*argv=*/(gchar **)arr->pdata, // safe: our array is non-const copy
        /*envp=*/nullptr,
        /*flags=*/G_SPAWN_SEARCH_PATH,
        /*child_setup=*/nullptr,
        /*user_data=*/nullptr,
        /*standard_output=*/stdout_out,
        /*standard_error=*/stderr_out,
        /*exit_status=*/exit_status,
        /*error=*/error);

    // free argv copy
    for (guint i = 0; i + 1 < arr->len; ++i)
    {
        g_free(g_ptr_array_index(arr, i));
    }
    g_ptr_array_free(arr, TRUE);

    return ok;
}

// ---------------- Method Handler ----------------
static void method_call_cb(FlMethodChannel *channel,
                           FlMethodCall *method_call,
                           gpointer user_data)
{
    FlathubInstallerPlugin *self = (FlathubInstallerPlugin *)user_data;
    (void)self;

    const gchar *method = fl_method_call_get_name(method_call);

    // ---- installFlatpak(appId) ----
    if (g_strcmp0(method, kMethodInstall) == 0)
    {
        const gchar *app_id = nullptr;
        if (FlValue *args = fl_method_call_get_args(method_call))
        {
            if (fl_value_get_type(args) == FL_VALUE_TYPE_MAP)
            {
                FlValue *v = fl_value_lookup_string(args, "appId");
                if (v && fl_value_get_type(v) == FL_VALUE_TYPE_STRING)
                {
                    app_id = fl_value_get_string(v);
                }
            }
        }
        if (!app_id || std::strlen(app_id) == 0)
        {
            g_autoptr(FlMethodResponse) resp = FL_METHOD_RESPONSE(
                fl_method_error_response_new("INVALID_APP_ID", "App ID cannot be null", nullptr));
            fl_method_call_respond(method_call, resp, nullptr);
            return;
        }

        // --- ASYNC install, no freeze ---
        gchar *argv[] = {
            (gchar *)"flatpak", (gchar *)"install", (gchar *)"flathub",
            (gchar *)app_id, (gchar *)"-y", nullptr};

        GPid pid = 0;
        gint out_fd = -1, err_fd = -1;
        GError *error = nullptr;

        gboolean ok = g_spawn_async_with_pipes(
            /*working_directory=*/nullptr,
            /*argv=*/argv,
            /*envp=*/nullptr,
            /*flags=*/(GSpawnFlags)(G_SPAWN_SEARCH_PATH),
            /*child_setup=*/nullptr,
            /*user_data=*/nullptr,
            /*child_pid=*/&pid,
            /*stdin_fd=*/nullptr,
            /*stdout_fd=*/&out_fd,
            /*stderr_fd=*/&err_fd,
            /*error=*/&error);

        if (!ok)
        {
            const gchar *msg = error ? error->message : "Failed to spawn install";
            g_autoptr(FlMethodResponse) resp =
                FL_METHOD_RESPONSE(fl_method_error_response_new("SPAWN_FAILED", msg, nullptr));
            if (error)
                g_error_free(error);
            fl_method_call_respond(method_call, resp, nullptr);
            return;
        }

        // Watch stdout
        GIOChannel *out_ch = g_io_channel_unix_new(out_fd);
        g_io_channel_set_encoding(out_ch, nullptr, nullptr); // binary
        g_io_add_watch(out_ch,
                       (GIOCondition)(G_IO_IN | G_IO_HUP | G_IO_ERR | G_IO_NVAL),
                       io_cb,
                       g_strdup(app_id)); // freed in child_watch_cb

        // (opsional) watch stderr juga, bisa pakai callback sama
        GIOChannel *err_ch = g_io_channel_unix_new(err_fd);
        g_io_channel_set_encoding(err_ch, nullptr, nullptr);
        g_io_add_watch(err_ch,
                       (GIOCondition)(G_IO_IN | G_IO_HUP | G_IO_ERR | G_IO_NVAL),
                       io_cb,
                       g_strdup(app_id));

        // Watch proses selesai
        g_child_watch_add(pid, child_watch_cb, g_strdup(app_id));

        // Balas segera supaya UI tidak block
        g_autoptr(FlMethodResponse) resp =
            FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
        fl_method_call_respond(method_call, resp, nullptr);
        return;
    }

    // ---- isInstalled(appId) -> bool ----
    if (g_strcmp0(method, kMethodIsInstalled) == 0)
    {
        const gchar *app_id = nullptr;
        if (FlValue *args = fl_method_call_get_args(method_call))
        {
            if (fl_value_get_type(args) == FL_VALUE_TYPE_MAP)
            {
                FlValue *v = fl_value_lookup_string(args, "appId");
                if (v && fl_value_get_type(v) == FL_VALUE_TYPE_STRING)
                {
                    app_id = fl_value_get_string(v);
                }
            }
        }
        if (!app_id || std::strlen(app_id) == 0)
        {
            g_autoptr(FlMethodResponse) resp = FL_METHOD_RESPONSE(
                fl_method_error_response_new("INVALID_APP_ID", "App ID cannot be null", nullptr));
            fl_method_call_respond(method_call, resp, nullptr);
            return;
        }

        const char *argv[] = {"flatpak", "info", app_id, nullptr};
        gint status = -1;
        GError *error = nullptr;
        gchar *out = nullptr;
        gboolean ok = spawn_and_capture(argv, &out, nullptr, &status, &error);
        if (out)
            g_free(out);
        if (error)
            g_error_free(error);

        // status 0 jika app ditemukan/terpasang
        FlValue *result = fl_value_new_bool(ok && status == 0);
        g_autoptr(FlMethodResponse) resp =
            FL_METHOD_RESPONSE(fl_method_success_response_new(result));
        fl_method_call_respond(method_call, resp, nullptr);
        return;
    }

    // ---- listInstalled() -> List<String> app-ids ----
    if (g_strcmp0(method, kMethodListInstalled) == 0)
    {
        const char *argv[] = {"flatpak", "list", "--app", "--columns=application", nullptr};
        gint status = -1;
        GError *error = nullptr;
        gchar *out = nullptr;
        gboolean ok = spawn_and_capture(argv, &out, nullptr, &status, &error);

        if (!ok || status != 0)
        {
            const gchar *msg = error ? error->message : "Failed to list installed apps";
            g_autoptr(FlMethodResponse) resp = FL_METHOD_RESPONSE(
                fl_method_error_response_new("LIST_FAILED", msg, nullptr));
            if (error)
                g_error_free(error);
            if (out)
                g_free(out);
            fl_method_call_respond(method_call, resp, nullptr);
            return;
        }

        FlValue *list = fl_value_new_list();
        if (out)
        {
            gchar **lines = g_strsplit(out, "\n", -1);
            for (gchar **p = lines; p && *p; ++p)
            {
                if (**p)
                {
                    fl_value_append_take(list, fl_value_new_string(*p));
                }
            }
            g_strfreev(lines);
            g_free(out);
        }

        g_autoptr(FlMethodResponse) resp =
            FL_METHOD_RESPONSE(fl_method_success_response_new(list));
        fl_method_call_respond(method_call, resp, nullptr);
        return;
    }

    // ---- uninstallFlatpak(appId) ----
    if (g_strcmp0(method, kMethodUninstall) == 0)
    {
        const gchar *app_id = nullptr;
        if (FlValue *args = fl_method_call_get_args(method_call))
        {
            if (fl_value_get_type(args) == FL_VALUE_TYPE_MAP)
            {
                FlValue *v = fl_value_lookup_string(args, "appId");
                if (v && fl_value_get_type(v) == FL_VALUE_TYPE_STRING)
                {
                    app_id = fl_value_get_string(v);
                }
            }
        }
        if (!app_id || std::strlen(app_id) == 0)
        {
            g_autoptr(FlMethodResponse) resp = FL_METHOD_RESPONSE(
                fl_method_error_response_new("INVALID_APP_ID", "App ID cannot be null", nullptr));
            fl_method_call_respond(method_call, resp, nullptr);
            return;
        }

        const char *argv[] = {"flatpak", "uninstall", app_id, "-y", nullptr};
        gint status = -1;
        GError *error = nullptr;
        gboolean ok = spawn_and_capture(argv, nullptr, nullptr, &status, &error);

        if (!ok || status != 0)
        {
            const gchar *msg = error ? error->message : "Failed to uninstall";
            g_autoptr(FlMethodResponse) resp =
                FL_METHOD_RESPONSE(fl_method_error_response_new("UNINSTALL_FAILED", msg, nullptr));
            if (error)
                g_error_free(error);
            fl_method_call_respond(method_call, resp, nullptr);
            return;
        }

        g_autoptr(FlMethodResponse) resp =
            FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
        fl_method_call_respond(method_call, resp, nullptr);
        return;
    }

    // ---- updateFlatpak(appId) ----
    if (g_strcmp0(method, kMethodUpdate) == 0)
    {
        const gchar *app_id = nullptr;
        if (FlValue *args = fl_method_call_get_args(method_call))
        {
            if (fl_value_get_type(args) == FL_VALUE_TYPE_MAP)
            {
                FlValue *v = fl_value_lookup_string(args, "appId");
                if (v && fl_value_get_type(v) == FL_VALUE_TYPE_STRING)
                {
                    app_id = fl_value_get_string(v);
                }
            }
        }
        if (!app_id || std::strlen(app_id) == 0)
        {
            g_autoptr(FlMethodResponse) resp = FL_METHOD_RESPONSE(
                fl_method_error_response_new("INVALID_APP_ID", "App ID cannot be null", nullptr));
            fl_method_call_respond(method_call, resp, nullptr);
            return;
        }

        const char *argv[] = {"flatpak", "update", app_id, "-y", nullptr};
        gint status = -1;
        GError *error = nullptr;
        gboolean ok = spawn_and_capture(argv, nullptr, nullptr, &status, &error);

        if (!ok || status != 0)
        {
            const gchar *msg = error ? error->message : "Failed to update";
            g_autoptr(FlMethodResponse) resp =
                FL_METHOD_RESPONSE(fl_method_error_response_new("UPDATE_FAILED", msg, nullptr));
            if (error)
                g_error_free(error);
            fl_method_call_respond(method_call, resp, nullptr);
            return;
        }

        g_autoptr(FlMethodResponse) resp =
            FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
        fl_method_call_respond(method_call, resp, nullptr);
        return;
    }

    // ---- not implemented ----
    g_autoptr(FlMethodResponse) resp =
        FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
    fl_method_call_respond(method_call, resp, nullptr);
}

// ---------------- GObject plumbing ----------------
static void flathub_installer_plugin_dispose(GObject *object)
{
    FlathubInstallerPlugin *self = (FlathubInstallerPlugin *)object;
    if (self->channel)
    {
        g_object_unref(self->channel);
        self->channel = nullptr;
    }
    G_OBJECT_CLASS(flathub_installer_plugin_parent_class)->dispose(object);
}

static void flathub_installer_plugin_class_init(FlathubInstallerPluginClass *klass)
{
    G_OBJECT_CLASS(klass)->dispose = flathub_installer_plugin_dispose;
}

static void flathub_installer_plugin_init(FlathubInstallerPlugin *self) {}

// ---------------- Registrar ----------------
void flathub_installer_plugin_register_with_registrar(FlPluginRegistrar *registrar)
{
    FlBinaryMessenger *messenger = fl_plugin_registrar_get_messenger(registrar);
    g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();

    FlathubInstallerPlugin *plugin =
        (FlathubInstallerPlugin *)g_object_new(flathub_installer_plugin_get_type(), nullptr);

    plugin->channel = fl_method_channel_new(messenger, kChannelName, FL_METHOD_CODEC(codec));
    fl_method_channel_set_method_call_handler(plugin->channel, method_call_cb, g_object_ref(plugin), g_object_unref);

    // event channel
    g_autoptr(FlStandardMethodCodec) evcodec = fl_standard_method_codec_new();
    g_events_channel = fl_event_channel_new(messenger, kEventsChannelName, FL_METHOD_CODEC(evcodec));
    // tidak perlu handler khusus; kita hanya "send"

    g_object_unref(plugin);
}
