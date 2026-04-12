/// Which Flatpak catalog the app is currently browsing.
///
/// Default for the AGL App Store is [pensHub] (the in-house repo at
/// `repo.agl-store.cyou`). [flathub] is provided as a secondary source so
/// users can also browse the public Flathub catalog without leaving the app.
enum AppSource {
  pensHub,
  flathub;

  /// Human-readable label shown in the UI toggle.
  String get label => switch (this) {
        AppSource.pensHub => 'PensHub',
        AppSource.flathub => 'Flathub',
      };

  /// Subtitle / longer label for places where space allows it.
  String get description => switch (this) {
        AppSource.pensHub => 'AGL App Store',
        AppSource.flathub => 'flathub.org',
      };

  /// API base URL for catalog queries (apps, details, categories).
  String get apiBaseUrl => switch (this) {
        AppSource.pensHub => 'https://api.agl-store.cyou',
        AppSource.flathub => 'https://flathub.org/api/v2',
      };

  /// The flatpak remote name used by `flatpak install <remote> <app-id>`.
  ///
  /// Both remotes must be configured on the device:
  ///
  ///   flatpak remote-add --if-not-exists \
  ///     --gpg-import=<(curl -s https://repo.agl-store.cyou/public.gpg) \
  ///     penshub https://repo.agl-store.cyou
  ///
  ///   flatpak remote-add --if-not-exists flathub \
  ///     https://flathub.org/repo/flathub.flatpakrepo
  String get flatpakRemote => switch (this) {
        AppSource.pensHub => 'penshub',
        AppSource.flathub => 'flathub',
      };
}
