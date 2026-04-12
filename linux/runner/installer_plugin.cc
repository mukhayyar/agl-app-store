#define FLUTTER_PLUGIN_IMPL
#include "installer_plugin.h"

#include <flutter_linux/flutter_linux.h>
#include <glib.h>
#include <gtk/gtk.h>
#include <cstring>

// ---------------- Channel & Method Names ----------------
static const char *kChannelName = "com.pens.flatpak/installer";
static const char *kMethodInstall = "installFlatpak";
static const char *kMethodLaunch = "launchFlatpak";
static const char *kMethodIsInstalled = "isInstalled";
static const char *kMethodListInstalled = "listInstalled";
static const char *kMethodUninstall = "uninstallFlatpak";
static const char *kMethodUpdate = "updateFlatpak";
static const char *kEventsChannelName = "com.pens.flatpak/installer_events";

// Flatpak remote that holds the AGL App Store (PensHub) packages.
// The remote must already be added on the device:
//   flatpak remote-add --if-not-exists \
//     --gpg-import=<(curl -s https://repo.agl-store.cyou/public.gpg) \
//     penshub https://repo.agl-store.cyou
//
// Once added, install with:
//   flatpak install penshub com.pens.AppName
static const char *kFlatpakRemote = "penshub";

static FlEventChannel *g_events_channel = nullptr;

static void send_event_map(FlValue *map);
static gboolean extract_progress(const gchar *line, int *step, int *total, int *percent);
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

    if (cond & G_IO_IN)
    {
        gchar *line = nullptr;
        gsize len = 0;
        GError *err = nullptr;

        GIOStatus st = g_io_channel_read_line(source, &line, &len, nullptr, &err);
        if (st == G_IO_STATUS_NORMAL && line)
        {

            // 🔥 PRINT TO TERMINAL (YOU WILL SEE INSTALL PROCESS)
            g_print("[flatpak:%s] %s", app_id, line);
            // Inside io_cb
            int step = -1;
            int total = -1;
            int percent = -1;

            if (extract_progress(line, &step, &total, &percent))
            {
                FlValue *map = fl_value_new_map();
                fl_value_set_string_take(map, "type", fl_value_new_string("progress"));
                fl_value_set_string_take(map, "appId", fl_value_new_string(app_id));

                // Only send if valid (optional, but clean)
                if (step > 0 && total > 0)
                {
                    fl_value_set_string_take(map, "step", fl_value_new_int(step));
                    fl_value_set_string_take(map, "total", fl_value_new_int(total));
                }

                fl_value_set_string_take(map, "percent", fl_value_new_int(percent));
                send_event_map(map);
            }
            // Send to Flutter
            FlValue *map = fl_value_new_map();
            fl_value_set_string_take(map, "type", fl_value_new_string("stdout"));
            fl_value_set_string_take(map, "appId", fl_value_new_string(app_id));
            fl_value_set_string_take(map, "line", fl_value_new_string(line));
            send_event_map(map);

            g_free(line);
        }
        if (err)
            g_error_free(err);
    }

    if (cond & (G_IO_HUP | G_IO_ERR | G_IO_NVAL))
    {
        return FALSE;
    }

    return TRUE;
}

// 2. UPDATED CHILD WATCH CALLBACK (The Standard Way)
static void child_watch_cb(GPid pid, gint status, gpointer user_data)
{
    const gchar *app_id = (const gchar *)user_data;

    FlValue *map = fl_value_new_map();
    fl_value_set_string_take(map, "type", fl_value_new_string("done"));
    fl_value_set_string_take(map, "appId", fl_value_new_string(app_id));
    fl_value_set_string_take(map, "status", fl_value_new_int(status));

    send_event_map(map);

    g_spawn_close_pid(pid);
    g_free((gpointer)app_id);
}

// ---------------- Helper: build argv & spawn ----------------
// 1. Updated Function Signature
static gboolean extract_progress(
    const gchar *line,
    int *step,
    int *total,
    int *percent)
{
    if (!line) return FALSE;

    // reset defaults
    *step = -1;
    *total = -1;
    *percent = -1;

    // --------- parse percent ---------
    const gchar *p = strchr(line, '%');
    if (p)
    {
        const gchar *start = p;
        while (start > line && g_ascii_isdigit(*(start - 1)))
            start--;

        if (start < p)
        {
            char buf[4] = {0};
            int len = MIN((int)(p - start), 3);
            strncpy(buf, start, len);
            *percent = atoi(buf);
        }
    }

    // --------- parse step/total (n/m) ---------
    const gchar *slash = strchr(line, '/');
    if (slash)
    {
        const gchar *l = slash;
        while (l > line && g_ascii_isdigit(*(l - 1)))
            l--;

        const gchar *r = slash + 1;
        while (g_ascii_isdigit(*r))
            r++;

        if (l < slash && r > slash + 1)
        {
            char a[8] = {0}, b[8] = {0};
            strncpy(a, l, slash - l);
            strncpy(b, slash + 1, r - (slash + 1));

            *step = atoi(a);
            *total = atoi(b);
        }
    }

    return (*percent >= 0);
}


static void send_event_map(FlValue *map)
{
    if (!g_events_channel || !map)
        return;
    fl_event_channel_send(g_events_channel, map, nullptr, nullptr);
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

    // ---- installFlatpak(appId, remote?) ----
    if (g_strcmp0(method, kMethodInstall) == 0)
    {
        const gchar *app_id = nullptr;
        const gchar *remote = kFlatpakRemote; // default: PensHub
        if (FlValue *args = fl_method_call_get_args(method_call))
        {
            if (fl_value_get_type(args) == FL_VALUE_TYPE_MAP)
            {
                FlValue *v = fl_value_lookup_string(args, "appId");
                if (v && fl_value_get_type(v) == FL_VALUE_TYPE_STRING)
                {
                    app_id = fl_value_get_string(v);
                }
                FlValue *r = fl_value_lookup_string(args, "remote");
                if (r && fl_value_get_type(r) == FL_VALUE_TYPE_STRING)
                {
                    const gchar *override_remote = fl_value_get_string(r);
                    if (override_remote && std::strlen(override_remote) > 0)
                    {
                        remote = override_remote;
                    }
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
            (gchar *)"flatpak", (gchar *)"install", (gchar *)remote,
            (gchar *)app_id, (gchar *)"-y", nullptr};

        GPid pid = 0;
        gint out_fd = -1, err_fd = -1;
        GError *error = nullptr;

        gboolean ok = g_spawn_async_with_pipes(
            /*working_directory=*/nullptr,
            /*argv=*/argv,
            /*envp=*/nullptr,
            /*flags=*/(GSpawnFlags)(G_SPAWN_SEARCH_PATH | G_SPAWN_DO_NOT_REAP_CHILD),
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

    // ---- launchFlatpak(appId) [NEW] ----
    if (g_strcmp0(method, kMethodLaunch) == 0)
    {
        // 1. Declare and Extract app_id locally to ensure it exists in this scope
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

        // 2. Validate it
        if (!app_id || std::strlen(app_id) == 0)
        {
            fl_method_call_respond(method_call, FL_METHOD_RESPONSE(fl_method_error_response_new("INVALID_ID", "No ID provided", nullptr)), nullptr);
            return;
        }

        // 3. Run flatpak command
        gchar *argv[] = {(gchar *)"flatpak", (gchar *)"run", (gchar *)app_id, nullptr};
        GError *error = nullptr;

        gboolean ok = g_spawn_async(
            nullptr,
            argv,
            nullptr,
            G_SPAWN_SEARCH_PATH,
            nullptr,
            nullptr,
            nullptr,
            &error);

        if (!ok)
        {
            const gchar *msg = error ? error->message : "Failed to launch";
            g_autoptr(FlMethodResponse) resp = FL_METHOD_RESPONSE(fl_method_error_response_new("LAUNCH_FAILED", msg, nullptr));
            if (error)
                g_error_free(error);
            fl_method_call_respond(method_call, resp, nullptr);
            return;
        }

        fl_method_call_respond(method_call, FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr)), nullptr);
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
        // We request 'application' (ID) and 'name' columns
        const char *argv[] = {"flatpak", "list", "--app", "--columns=application,name", nullptr};
        gchar *out = nullptr;
        spawn_and_capture(argv, &out, nullptr, nullptr, nullptr);

        FlValue *list = fl_value_new_list();
        if (out)
        {
            gchar **lines = g_strsplit(out, "\n", -1);
            for (gchar **p = lines; p && *p; ++p)
            {
                if (**p)
                {
                    // Split by tab (default flatpak output separator)
                    gchar **cols = g_strsplit(*p, "\t", -1);
                    if (cols)
                    {
                        // Safe extraction
                        const gchar *id = cols[0];
                        const gchar *name = (g_strv_length(cols) > 1) ? cols[1] : id;

                        // Create a Map { "id": "...", "name": "..." }
                        FlValue *map = fl_value_new_map();
                        fl_value_set_string_take(map, "id", fl_value_new_string(id));
                        fl_value_set_string_take(map, "name", fl_value_new_string(name));

                        fl_value_append_take(list, map);
                        g_strfreev(cols);
                    }
                }
            }
            g_strfreev(lines);
            g_free(out);
        }
        fl_method_call_respond(method_call, FL_METHOD_RESPONSE(fl_method_success_response_new(list)), nullptr);
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
            fl_method_call_respond(
                method_call,
                FL_METHOD_RESPONSE(
                    fl_method_error_response_new("INVALID_APP_ID", "App ID cannot be null", nullptr)),
                nullptr);
            return;
        }

        // 🔥 ASYNC uninstall (NO UI FREEZE)
        gchar *argv[] = {
            (gchar *)"flatpak",
            (gchar *)"uninstall",
            (gchar *)app_id,
            (gchar *)"-y",
            nullptr};

        GPid pid = 0;
        gint out_fd = -1, err_fd = -1;
        GError *error = nullptr;

        gboolean ok = g_spawn_async_with_pipes(
            nullptr,
            argv,
            nullptr,
            (GSpawnFlags)(G_SPAWN_SEARCH_PATH | G_SPAWN_DO_NOT_REAP_CHILD),
            nullptr,
            nullptr,
            &pid,
            nullptr,
            &out_fd,
            &err_fd,
            &error);

        if (!ok)
        {
            const gchar *msg = error ? error->message : "Failed to uninstall";
            fl_method_call_respond(
                method_call,
                FL_METHOD_RESPONSE(
                    fl_method_error_response_new("SPAWN_FAILED", msg, nullptr)),
                nullptr);
            if (error)
                g_error_free(error);
            return;
        }

        // stdout
        GIOChannel *out_ch = g_io_channel_unix_new(out_fd);
        g_io_channel_set_encoding(out_ch, nullptr, nullptr);
        g_io_add_watch(
            out_ch,
            (GIOCondition)(G_IO_IN | G_IO_HUP | G_IO_ERR | G_IO_NVAL),
            io_cb,
            g_strdup(app_id));

        // stderr
        GIOChannel *err_ch = g_io_channel_unix_new(err_fd);
        g_io_channel_set_encoding(err_ch, nullptr, nullptr);
        g_io_add_watch(
            err_ch,
            (GIOCondition)(G_IO_IN | G_IO_HUP | G_IO_ERR | G_IO_NVAL),
            io_cb,
            g_strdup(app_id));

        // process exit
        g_child_watch_add(pid, child_watch_cb, g_strdup(app_id));

        // 🔥 respond immediately → UI does NOT block
        fl_method_call_respond(
            method_call,
            FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr)),
            nullptr);
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
