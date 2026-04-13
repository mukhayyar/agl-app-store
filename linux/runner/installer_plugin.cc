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
static const char *kMethodEnsureRemote = "ensureRemote";
static const char *kMethodRefreshAppstream = "refreshAppstream";
static const char *kEventsChannelName = "com.pens.flatpak/installer_events";

static const char *kFlatpakRemote = "penshub";
static const char *kFlatpakRepoUrl = "https://repo.agl-store.cyou";
static const char *kFlatpakGpgUrl = "https://repo.agl-store.cyou/public.gpg";
static const char *kGpgTmpPath = "/tmp/penshub.gpg";

static const char *kFlathubRemote = "flathub";
static const char *kFlathubRepoUrl = "https://dl.flathub.org/repo/flathub.flatpakrepo";

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
            g_print("[flatpak:%s] %s", app_id, line);
            int step = -1;
            int total = -1;
            int percent = -1;

            if (extract_progress(line, &step, &total, &percent))
            {
                FlValue *map = fl_value_new_map();
                fl_value_set_string_take(map, "type", fl_value_new_string("progress"));
                fl_value_set_string_take(map, "appId", fl_value_new_string(app_id));

                if (step > 0 && total > 0)
                {
                    fl_value_set_string_take(map, "step", fl_value_new_int(step));
                    fl_value_set_string_take(map, "total", fl_value_new_int(total));
                }

                fl_value_set_string_take(map, "percent", fl_value_new_int(percent));
                send_event_map(map);
            }
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

static gboolean extract_progress(
    const gchar *line,
    int *step,
    int *total,
    int *percent)
{
    if (!line) return FALSE;

    *step = -1;
    *total = -1;
    *percent = -1;

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
    GPtrArray *arr = g_ptr_array_new();
    for (int i = 0; argv_in[i] != nullptr; ++i)
    {
        g_ptr_array_add(arr, g_strdup(argv_in[i]));
    }
    g_ptr_array_add(arr, nullptr);

    gboolean ok = g_spawn_sync(
        nullptr,
        (gchar **)arr->pdata,
        nullptr,
        G_SPAWN_SEARCH_PATH,
        nullptr,
        nullptr,
        stdout_out,
        stderr_out,
        exit_status,
        error);

    for (guint i = 0; i + 1 < arr->len; ++i)
    {
        g_free(g_ptr_array_index(arr, i));
    }
    g_ptr_array_free(arr, TRUE);

    return ok;
}

// ---------------- ensureRemote helper ----------------
// Returns nullptr on success, or an error string (must g_free).
static gchar *ensure_penshub_remote()
{
    // 1. Check if penshub remote already exists
    const char *list_argv[] = {"flatpak", "remote-list", "--user", nullptr};
    gchar *list_out = nullptr;
    spawn_and_capture(list_argv, &list_out, nullptr, nullptr, nullptr);

    gboolean exists = list_out && (strstr(list_out, kFlatpakRemote) != nullptr);
    g_free(list_out);

    if (exists)
        return nullptr; // already set up

    // 2. Download GPG key
    const char *curl_argv[] = {
        "curl", "-s", "--max-time", "30",
        kFlatpakGpgUrl, "-o", kGpgTmpPath, nullptr};
    gint curl_status = -1;
    gboolean curl_ok = spawn_and_capture(curl_argv, nullptr, nullptr, &curl_status, nullptr);

    if (!curl_ok || curl_status != 0)
    {
        return g_strdup_printf("Failed to download GPG key from %s (exit %d)", kFlatpakGpgUrl, curl_status);
    }

    // 3. Add remote with GPG verification
    gchar *gpg_arg = g_strdup_printf("--gpg-import=%s", kGpgTmpPath);
    const char *add_argv[] = {
        "flatpak", "remote-add", "--user", "--if-not-exists",
        gpg_arg, kFlatpakRemote, kFlatpakRepoUrl, nullptr};
    gint add_status = -1;
    gchar *add_err = nullptr;
    gboolean add_ok = spawn_and_capture(add_argv, nullptr, &add_err, &add_status, nullptr);
    g_free(gpg_arg);

    if (!add_ok || add_status != 0)
    {
        gchar *msg = g_strdup_printf("Failed to add remote '%s' (exit %d): %s",
                                     kFlatpakRemote, add_status,
                                     add_err ? add_err : "unknown error");
        g_free(add_err);
        return msg;
    }
    g_free(add_err);

    // 4. Refresh appstream cache (background — don't block startup)
    const char *appstream_argv[] = {
        "flatpak", "update", "--appstream", "--user", kFlatpakRemote, nullptr};
    g_spawn_async(nullptr, (gchar **)appstream_argv, nullptr,
                  G_SPAWN_SEARCH_PATH, nullptr, nullptr, nullptr, nullptr);

    remove(kGpgTmpPath); // cleanup temp key file
    return nullptr;        // success
}

// ---------------- ensureFlathub helper ----------------
// Adds the Flathub remote if not already present. Simpler than PensHub
// because Flathub uses a .flatpakrepo file that bundles GPG info.
// Returns nullptr on success, or an error string (must g_free).
static gchar *ensure_flathub_remote()
{
    // 1. Check if flathub remote already exists
    const char *list_argv[] = {"flatpak", "remote-list", "--user", nullptr};
    gchar *list_out = nullptr;
    spawn_and_capture(list_argv, &list_out, nullptr, nullptr, nullptr);

    gboolean exists = list_out && (strstr(list_out, kFlathubRemote) != nullptr);
    g_free(list_out);

    if (exists)
        return nullptr; // already set up

    // 2. Add remote — the .flatpakrepo URL bundles the GPG key
    const char *add_argv[] = {
        "flatpak", "remote-add", "--user", "--if-not-exists",
        kFlathubRemote, kFlathubRepoUrl, nullptr};
    gint add_status = -1;
    gchar *add_err = nullptr;
    gboolean add_ok = spawn_and_capture(add_argv, nullptr, &add_err, &add_status, nullptr);

    if (!add_ok || add_status != 0)
    {
        gchar *msg = g_strdup_printf("Failed to add remote '%s' (exit %d): %s",
                                     kFlathubRemote, add_status,
                                     add_err ? add_err : "unknown error");
        g_free(add_err);
        return msg;
    }
    g_free(add_err);
    return nullptr;
}

// ---------------- Method Handler ----------------
static void method_call_cb(FlMethodChannel *channel,
                           FlMethodCall *method_call,
                           gpointer user_data)
{
    FlathubInstallerPlugin *self = (FlathubInstallerPlugin *)user_data;
    (void)self;

    const gchar *method = fl_method_call_get_name(method_call);

    // ---- ensureRemote() -> {added: bool, error: string?} ----
    // Sets up BOTH penshub and flathub remotes so the user can switch
    // sources without manual flatpak configuration.
    if (g_strcmp0(method, kMethodEnsureRemote) == 0)
    {
        // Check if penshub already existed before setup
        const char *list_argv[] = {"flatpak", "remote-list", "--user", nullptr};
        gchar *list_out = nullptr;
        spawn_and_capture(list_argv, &list_out, nullptr, nullptr, nullptr);
        gboolean penshub_existed = list_out && (strstr(list_out, kFlatpakRemote) != nullptr);
        g_free(list_out);

        // Set up PensHub (GPG key + remote)
        gchar *penshub_err = ensure_penshub_remote();

        // Set up Flathub (.flatpakrepo — simpler, no separate GPG download)
        gchar *flathub_err = ensure_flathub_remote();

        // Combine errors if both failed
        gchar *combined_err = nullptr;
        if (penshub_err && flathub_err)
        {
            combined_err = g_strdup_printf("penshub: %s | flathub: %s", penshub_err, flathub_err);
            g_free(penshub_err);
            g_free(flathub_err);
        }
        else if (penshub_err)
        {
            combined_err = penshub_err;
        }
        else if (flathub_err)
        {
            combined_err = flathub_err;
        }

        FlValue *result = fl_value_new_map();
        fl_value_set_string_take(result, "added",
            fl_value_new_bool(!penshub_existed && combined_err == nullptr));
        fl_value_set_string_take(result, "alreadyExists",
            fl_value_new_bool(penshub_existed));

        if (combined_err)
        {
            fl_value_set_string_take(result, "error", fl_value_new_string(combined_err));
            g_free(combined_err);
        }
        else
        {
            fl_value_set_string_take(result, "error", fl_value_new_null());
        }

        g_autoptr(FlMethodResponse) resp =
            FL_METHOD_RESPONSE(fl_method_success_response_new(result));
        fl_method_call_respond(method_call, resp, nullptr);
        return;
    }

    // ---- refreshAppstream() ----
    // Fires `flatpak update --appstream --user <remote>` for both penshub
    // and flathub in the background. Non-blocking — returns immediately
    // while the updates run asynchronously. Called on every app launch so
    // the driver never needs to touch a terminal.
    if (g_strcmp0(method, kMethodRefreshAppstream) == 0)
    {
        const char *pens_argv[] = {
            "flatpak", "update", "--appstream", "--user", kFlatpakRemote, nullptr};
        g_spawn_async(nullptr, (gchar **)pens_argv, nullptr,
                      G_SPAWN_SEARCH_PATH, nullptr, nullptr, nullptr, nullptr);

        const char *flat_argv[] = {
            "flatpak", "update", "--appstream", "--user", kFlathubRemote, nullptr};
        g_spawn_async(nullptr, (gchar **)flat_argv, nullptr,
                      G_SPAWN_SEARCH_PATH, nullptr, nullptr, nullptr, nullptr);

        g_autoptr(FlMethodResponse) resp =
            FL_METHOD_RESPONSE(fl_method_success_response_new(fl_value_new_bool(TRUE)));
        fl_method_call_respond(method_call, resp, nullptr);
        return;
    }

    // ---- installFlatpak(appId, remote?) ----
    if (g_strcmp0(method, kMethodInstall) == 0)
    {
        const gchar *app_id = nullptr;
        const gchar *remote = kFlatpakRemote;
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

        gchar *argv[] = {
            (gchar *)"flatpak", (gchar *)"install", (gchar *)remote,
            (gchar *)app_id, (gchar *)"-y", nullptr};

        GPid pid = 0;
        gint out_fd = -1, err_fd = -1;
        GError *error = nullptr;

        gboolean ok = g_spawn_async_with_pipes(
            nullptr, argv, nullptr,
            (GSpawnFlags)(G_SPAWN_SEARCH_PATH | G_SPAWN_DO_NOT_REAP_CHILD),
            nullptr, nullptr, &pid, nullptr, &out_fd, &err_fd, &error);

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

        GIOChannel *out_ch = g_io_channel_unix_new(out_fd);
        g_io_channel_set_encoding(out_ch, nullptr, nullptr);
        g_io_add_watch(out_ch,
                       (GIOCondition)(G_IO_IN | G_IO_HUP | G_IO_ERR | G_IO_NVAL),
                       io_cb, g_strdup(app_id));

        GIOChannel *err_ch = g_io_channel_unix_new(err_fd);
        g_io_channel_set_encoding(err_ch, nullptr, nullptr);
        g_io_add_watch(err_ch,
                       (GIOCondition)(G_IO_IN | G_IO_HUP | G_IO_ERR | G_IO_NVAL),
                       io_cb, g_strdup(app_id));

        g_child_watch_add(pid, child_watch_cb, g_strdup(app_id));

        g_autoptr(FlMethodResponse) resp =
            FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
        fl_method_call_respond(method_call, resp, nullptr);
        return;
    }

    // ---- launchFlatpak(appId) ----
    // Launches the app and watches the child PID. When the child exits,
    // we re-present our GTK window and restore cursor focus so the
    // driver doesn't get stuck with an invisible cursor.
    if (g_strcmp0(method, kMethodLaunch) == 0)
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
            fl_method_call_respond(method_call, FL_METHOD_RESPONSE(fl_method_error_response_new("INVALID_ID", "No ID provided", nullptr)), nullptr);
            return;
        }

        // Launch via `setsid flatpak run --user <id>` so the child gets
        // its own session and doesn't inherit/disrupt our EGL display
        // connection. This prevents "Lost connection to device".
        gchar *cmd = g_strdup_printf(
            "setsid flatpak run --user %s &", app_id);
        int ret = system(cmd);
        g_free(cmd);

        if (ret != 0)
        {
            fl_method_call_respond(method_call,
                FL_METHOD_RESPONSE(fl_method_error_response_new(
                    "LAUNCH_FAILED", "system() returned non-zero", nullptr)),
                nullptr);
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
        if (out) g_free(out);
        if (error) g_error_free(error);

        FlValue *result = fl_value_new_bool(ok && status == 0);
        g_autoptr(FlMethodResponse) resp =
            FL_METHOD_RESPONSE(fl_method_success_response_new(result));
        fl_method_call_respond(method_call, resp, nullptr);
        return;
    }

    // ---- listInstalled() -> List<Map> ----
    if (g_strcmp0(method, kMethodListInstalled) == 0)
    {
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
                    gchar **cols = g_strsplit(*p, "\t", -1);
                    if (cols)
                    {
                        const gchar *id = cols[0];
                        const gchar *name = (g_strv_length(cols) > 1) ? cols[1] : id;

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
                FL_METHOD_RESPONSE(fl_method_error_response_new("INVALID_APP_ID", "App ID cannot be null", nullptr)),
                nullptr);
            return;
        }

        gchar *argv[] = {
            (gchar *)"flatpak", (gchar *)"uninstall",
            (gchar *)app_id, (gchar *)"-y", nullptr};

        GPid pid = 0;
        gint out_fd = -1, err_fd = -1;
        GError *error = nullptr;

        gboolean ok = g_spawn_async_with_pipes(
            nullptr, argv, nullptr,
            (GSpawnFlags)(G_SPAWN_SEARCH_PATH | G_SPAWN_DO_NOT_REAP_CHILD),
            nullptr, nullptr, &pid, nullptr, &out_fd, &err_fd, &error);

        if (!ok)
        {
            const gchar *msg = error ? error->message : "Failed to uninstall";
            fl_method_call_respond(
                method_call,
                FL_METHOD_RESPONSE(fl_method_error_response_new("SPAWN_FAILED", msg, nullptr)),
                nullptr);
            if (error) g_error_free(error);
            return;
        }

        GIOChannel *out_ch = g_io_channel_unix_new(out_fd);
        g_io_channel_set_encoding(out_ch, nullptr, nullptr);
        g_io_add_watch(out_ch,
                       (GIOCondition)(G_IO_IN | G_IO_HUP | G_IO_ERR | G_IO_NVAL),
                       io_cb, g_strdup(app_id));

        GIOChannel *err_ch = g_io_channel_unix_new(err_fd);
        g_io_channel_set_encoding(err_ch, nullptr, nullptr);
        g_io_add_watch(err_ch,
                       (GIOCondition)(G_IO_IN | G_IO_HUP | G_IO_ERR | G_IO_NVAL),
                       io_cb, g_strdup(app_id));

        g_child_watch_add(pid, child_watch_cb, g_strdup(app_id));

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
            if (error) g_error_free(error);
            fl_method_call_respond(method_call, resp, nullptr);
            return;
        }

        g_autoptr(FlMethodResponse) resp =
            FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
        fl_method_call_respond(method_call, resp, nullptr);
        return;
    }

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

    g_autoptr(FlStandardMethodCodec) evcodec = fl_standard_method_codec_new();
    g_events_channel = fl_event_channel_new(messenger, kEventsChannelName, FL_METHOD_CODEC(evcodec));

    g_object_unref(plugin);
}
