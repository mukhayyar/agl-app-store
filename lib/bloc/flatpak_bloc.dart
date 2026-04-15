import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../data/flatpak_repository.dart';
import '../models/app_source.dart';
import '../models/flatpak_package.dart';
import '../platform/flatpak_platform.dart';

/// Phase of an in-flight install, used by the UI to show
/// "Downloading…" vs "Installing…". Reported by the AGL dart fallback
/// path; null on the desktop native plugin (which only emits %).
enum InstallPhase { downloading, installing }

/// =====================
/// EVENTS
/// =====================
abstract class FlatpakEvent extends Equatable {
  const FlatpakEvent();
  @override
  List<Object?> get props => [];
}

class RefreshAll extends FlatpakEvent {
  const RefreshAll();
}

/// Switch the active catalog source (PensHub ↔ Flathub).
///
/// Wipes the local cache, resets pagination, and re-fetches the home feed.
class SwitchSource extends FlatpakEvent {
  final AppSource source;
  const SwitchSource(this.source);
  @override
  List<Object?> get props => [source];
}

class LoadFirstPage extends FlatpakEvent {
  final String? query;
  const LoadFirstPage({this.query});
  @override
  List<Object?> get props => [query];
}

class LoadNextPage extends FlatpakEvent {
  const LoadNextPage();
}

class InstallApp extends FlatpakEvent {
  final String flatpakId;
  const InstallApp(this.flatpakId);
  @override
  List<Object?> get props => [flatpakId];
}

class UninstallApp extends FlatpakEvent {
  final String flatpakId;
  const UninstallApp(this.flatpakId);
  @override
  List<Object?> get props => [flatpakId];
}

class EnrichCurrentPage extends FlatpakEvent {
  const EnrichCurrentPage();
}

class InstallProgressEvent extends FlatpakEvent {
  final String appId;
  final int percent;
  final InstallPhase? phase;
  const InstallProgressEvent(this.appId, this.percent, {this.phase});
  @override
  List<Object?> get props => [appId, percent, phase];
}

class _InstallFinished extends FlatpakEvent {
  final String appId;
  final bool success;
  const _InstallFinished(this.appId, this.success);
}

class _UninstallFinished extends FlatpakEvent {
  final String appId;
  final bool success;
  const _UninstallFinished(this.appId, this.success);
}

/// =====================
/// STATES
/// =====================
abstract class FlatpakState extends Equatable {
  const FlatpakState();
  @override
  List<Object?> get props => [];
}

class FlatpakLoading extends FlatpakState {}

class FlatpakLoaded extends FlatpakState {
  final List<FlatpakPackage> items;
  final int page;
  final int pageSize;
  final bool hasMore;
  final String? query;
  final AppSource source;

  final Set<String> installed;
  final Set<String> installingIds;
  final Set<String> uninstallingIds;
  final Map<String, int> installProgress;
  final Map<String, InstallPhase> installPhase;

  /// True while a transient, long-running refresh is underway on top of
  /// the currently-rendered data (e.g. catalog source switch). The UI
  /// can keep showing existing items with a skeleton overlay instead of
  /// blanking the whole screen, and the dynamic island can show a
  /// "Switching to X" op.
  final bool isLoading;

  /// When [isLoading] is true because of a source switch, this is the
  /// source we're switching *to*. Null otherwise.
  final AppSource? pendingSource;

  const FlatpakLoaded({
    required this.items,
    required this.page,
    required this.pageSize,
    required this.hasMore,
    required this.installed,
    required this.source,
    this.query,
    this.installingIds = const {},
    this.uninstallingIds = const {},
    this.installProgress = const {},
    this.installPhase = const {},
    this.isLoading = false,
    this.pendingSource,
  });

  FlatpakLoaded copyWith({
    List<FlatpakPackage>? items,
    int? page,
    int? pageSize,
    bool? hasMore,
    String? query,
    AppSource? source,
    Set<String>? installed,
    Set<String>? installingIds,
    Set<String>? uninstallingIds,
    Map<String, int>? installProgress,
    Map<String, InstallPhase>? installPhase,
    bool? isLoading,
    AppSource? pendingSource,
    bool clearPendingSource = false,
  }) {
    return FlatpakLoaded(
      items: items ?? this.items,
      page: page ?? this.page,
      pageSize: pageSize ?? this.pageSize,
      hasMore: hasMore ?? this.hasMore,
      query: query ?? this.query,
      source: source ?? this.source,
      installed: installed ?? this.installed,
      installingIds: installingIds ?? this.installingIds,
      uninstallingIds: uninstallingIds ?? this.uninstallingIds,
      installProgress: installProgress ?? this.installProgress,
      installPhase: installPhase ?? this.installPhase,
      isLoading: isLoading ?? this.isLoading,
      pendingSource:
          clearPendingSource ? null : (pendingSource ?? this.pendingSource),
    );
  }

  @override
  List<Object?> get props => [
    items,
    page,
    pageSize,
    hasMore,
    query,
    source,
    installed,
    installingIds,
    uninstallingIds,
    installProgress,
    installPhase,
    isLoading,
    pendingSource,
  ];
}

class FlatpakError extends FlatpakState {
  final String message;
  const FlatpakError(this.message);
  @override
  List<Object?> get props => [message];
}

/// =====================
/// BLOC
/// =====================
class FlatpakBloc extends Bloc<FlatpakEvent, FlatpakState> {
  final FlatpakRepository repo;
  static const _pageSize = 20;

  StreamSubscription? _installSub;

  // Static RegExp — compiled once, reused across all instances
  static final _stageRe = RegExp(
    r'\[flatpak:(?<id>[^\]]+)\]\s+.*?\s+(?<step>\d+)\/(?<total>\d+)'
    r'[\s\W\D\S]+?'
    r'(?<percent>\d{1,3})%',
  );
  static final _simpleRe = RegExp(
    r'\[flatpak:(?<id>[^\]]+)\].*?(?<percent>\d{1,3})%',
  );
  static final _installDoneRe = RegExp(
    r'\[flatpak:(?<id>[^\]]+)\]\s+Installation complete\.?',
  );
  static final _uninstallDoneRe = RegExp(
    r'\[flatpak:(?<id>[^\]]+)\]\s+Uninstall complete\.?',
  );

  FlatpakBloc({required this.repo}) : super(FlatpakLoading()) {
    /// ---------------------
    /// ENRICH PAGE
    /// ---------------------
    on<EnrichCurrentPage>((event, emit) async {
      final s = state;
      if (s is! FlatpakLoaded) return;

      try {
        await repo.enrichMissingDetails(s.items);
        final refreshed = await repo.getPage(
          page: s.page,
          pageSize: s.pageSize,
          query: s.query,
        );
        emit(s.copyWith(items: refreshed));
      } catch (e) {
        debugPrint('Enrich failed: $e');
      }
    });

    /// ---------------------
    /// LOAD FIRST PAGE
    /// ---------------------
    on<LoadFirstPage>((event, emit) async {
      emit(FlatpakLoading());

      try {
        final installed = await repo.installedIds();
        final items = await repo.getPage(
          page: 1,
          pageSize: _pageSize,
          query: event.query,
        );
        final total = await repo.totalCount(query: event.query);

        emit(
          FlatpakLoaded(
            items: items,
            page: 1,
            pageSize: _pageSize,
            hasMore: items.length < total,
            query: event.query,
            installed: installed,
            source: repo.currentSource,
          ),
        );

        add(const EnrichCurrentPage());
      } catch (e) {
        emit(FlatpakError('Search failed: $e'));
      }
    });

    /// ---------------------
    /// LOAD NEXT PAGE — with debounce to prevent rapid-fire pagination
    /// ---------------------
    on<LoadNextPage>(
      (event, emit) async {
        final s = state;
        if (s is! FlatpakLoaded || !s.hasMore) return;

        try {
          final nextPage = s.page + 1;
          final nextItems = await repo.getPage(
            page: nextPage,
            pageSize: s.pageSize,
            query: s.query,
          );
          final total = await repo.totalCount(query: s.query);

          emit(
            s.copyWith(
              items: [...s.items, ...nextItems],
              page: nextPage,
              hasMore: (nextPage * s.pageSize) < total,
            ),
          );
        } catch (e) {
          emit(FlatpakError('Load more failed: $e'));
        }
      },
      transformer: _debounce(const Duration(milliseconds: 300)),
    );

    /// ---------------------
    /// INSTALL PROGRESS — throttle to avoid excessive UI rebuilds
    /// ---------------------
    on<InstallProgressEvent>(
      (e, emit) {
        final s = state;
        if (s is! FlatpakLoaded) return;

        emit(
          s.copyWith(
            installProgress: {...s.installProgress, e.appId: e.percent},
            installPhase: e.phase != null
                ? {...s.installPhase, e.appId: e.phase!}
                : s.installPhase,
          ),
        );
      },
      transformer: _debounce(const Duration(milliseconds: 200)),
    );

    /// ---------------------
    /// REFRESH ALL
    /// ---------------------
    on<RefreshAll>((event, emit) async {
      emit(FlatpakLoading());
      await repo.init();
      await repo.fixCorruptedIds();
      await repo.refreshAllApps();

      final installed = await repo.installedIds();
      final first = await repo.getPage(page: 1, pageSize: _pageSize);
      final total = await repo.totalCount();

      emit(
        FlatpakLoaded(
          items: first,
          page: 1,
          pageSize: _pageSize,
          hasMore: first.length < total,
          installed: installed,
          source: repo.currentSource,
        ),
      );

      add(const EnrichCurrentPage());
    });

    /// ---------------------
    /// SWITCH SOURCE (PensHub ↔ Flathub)
    /// ---------------------
    on<SwitchSource>((event, emit) async {
      if (repo.currentSource == event.source) return;

      // Stay in FlatpakLoaded with isLoading=true and pendingSource set
      // so the UI can show skeleton placeholders over the existing list
      // and the dynamic island can surface "Switching to X". Install /
      // uninstall ops are global to the device and are preserved
      // automatically by copyWith since we don't touch those fields.
      final prev = state;
      if (prev is FlatpakLoaded) {
        emit(prev.copyWith(
          isLoading: true,
          pendingSource: event.source,
        ));
      } else {
        // Cold start fallback (no prior loaded state to sit on)
        emit(FlatpakLoading());
      }

      await repo.setSource(event.source); // wipes cache internally
      await repo.refreshAllApps();

      final installed = await repo.installedIds();
      final first = await repo.getPage(page: 1, pageSize: _pageSize);
      final total = await repo.totalCount();

      // Re-read ops from current state (may have changed during await)
      final cur = state;
      final keepInstalling =
          cur is FlatpakLoaded ? cur.installingIds : const <String>{};
      final keepUninstalling =
          cur is FlatpakLoaded ? cur.uninstallingIds : const <String>{};
      final keepProgress = cur is FlatpakLoaded
          ? cur.installProgress
          : const <String, int>{};
      final keepPhase = cur is FlatpakLoaded
          ? cur.installPhase
          : const <String, InstallPhase>{};

      emit(
        FlatpakLoaded(
          items: first,
          page: 1,
          pageSize: _pageSize,
          hasMore: first.length < total,
          installed: installed,
          installingIds: keepInstalling,
          uninstallingIds: keepUninstalling,
          installProgress: keepProgress,
          installPhase: keepPhase,
          source: repo.currentSource,
          // isLoading: false, pendingSource: null (defaults)
        ),
      );

      add(const EnrichCurrentPage());
    });

    /// ---------------------
    /// INSTALL START
    /// ---------------------
    on<InstallApp>((e, emit) async {
      final s = state;
      if (s is! FlatpakLoaded) {
        debugPrint('[FLATPAK-BLOC] InstallApp dropped — state is not FlatpakLoaded');
        return;
      }

      final id = FlatpakRepository.normalizeFlatpakId(e.flatpakId);
      debugPrint('[FLATPAK-BLOC] InstallApp raw="${e.flatpakId}" normalized="$id"');
      if (s.installingIds.contains(id)) {
        debugPrint('[FLATPAK-BLOC] InstallApp ignored — $id already installing');
        return;
      }

      // Seed phase to 'downloading' immediately so the UI flips off
      // the download CTA the moment the user taps Install — even
      // before any progress event arrives from the platform layer.
      emit(
        s.copyWith(
          installingIds: {...s.installingIds, id},
          installProgress: {...s.installProgress, id: 0},
          installPhase: {...s.installPhase, id: InstallPhase.downloading},
        ),
      );

      // The 'done' event arrives via the install events stream — from
      // the native plugin's EventChannel (desktop) or from a synthetic
      // event emitted by the Dart fallback in FlatpakPlatform (AGL).
      // We only need to handle outright failure here.
      repo.install(id).catchError((err) {
        debugPrint('[FLATPAK-BLOC] repo.install threw for $id: $err');
        add(_InstallFinished(id, false));
      });
    });

    /// ---------------------
    /// INSTALL FINISHED
    /// ---------------------
    on<_InstallFinished>((e, emit) async {
      debugPrint('[FLATPAK-BLOC] _InstallFinished appId=${e.appId} '
          'success=${e.success}');
      final s = state;
      if (s is! FlatpakLoaded) {
        debugPrint('[FLATPAK-BLOC] _InstallFinished dropped — state not FlatpakLoaded');
        return;
      }

      final fromList = await repo.installedIds();
      final hitFromList = fromList.contains(e.appId);
      // Defensive union: if the install reported success, trust it and
      // ensure the id is in the installed set even if listInstalled()
      // is stale or normalizes ids slightly differently.
      final installed = e.success ? {...fromList, e.appId} : fromList;

      // Drop the specific event id AND self-heal any ghost entries: an
      // installingId whose app is now in `installed` must be finished
      // — even if the done event's id shape didn't match ours. This
      // is what stops "Installing X" pills from sticking around after
      // the install actually completed under a different id form.
      final newInstalling = <String>{};
      final newProgress = Map<String, int>.from(s.installProgress);
      final newPhase = Map<String, InstallPhase>.from(s.installPhase);
      newProgress.remove(e.appId);
      newPhase.remove(e.appId);
      for (final id in s.installingIds) {
        if (id == e.appId) continue;
        if (installed.contains(id)) {
          debugPrint('[FLATPAK-BLOC] self-heal: dropping ghost installingId=$id '
              '(now in installed set)');
          newProgress.remove(id);
          newPhase.remove(id);
          continue;
        }
        newInstalling.add(id);
      }

      debugPrint('[FLATPAK-BLOC] _InstallFinished appId=${e.appId} '
          'listInstalledHit=$hitFromList listSize=${fromList.length} '
          'finalInstalledHit=${installed.contains(e.appId)} '
          'installingIds: ${s.installingIds.length} → ${newInstalling.length}');

      emit(
        s.copyWith(
          installingIds: newInstalling,
          installed: installed,
          installProgress: newProgress,
          installPhase: newPhase,
        ),
      );
    });

    /// ---------------------
    /// UNINSTALL START
    /// ---------------------
    on<UninstallApp>((e, emit) async {
      final s = state;
      if (s is! FlatpakLoaded) return;

      final id = FlatpakRepository.normalizeFlatpakId(e.flatpakId);
      if (s.uninstallingIds.contains(id)) return;

      emit(s.copyWith(uninstallingIds: {...s.uninstallingIds, id}));

      repo.uninstall(id).catchError((_) {
        add(_UninstallFinished(id, false));
      });
    });

    /// ---------------------
    /// UNINSTALL FINISHED
    /// ---------------------
    on<_UninstallFinished>((e, emit) async {
      debugPrint('[FLATPAK-BLOC] _UninstallFinished appId=${e.appId} '
          'success=${e.success}');
      final s = state;
      if (s is! FlatpakLoaded) {
        debugPrint('[FLATPAK-BLOC] _UninstallFinished dropped — state not FlatpakLoaded');
        return;
      }

      final fromList = await repo.installedIds();
      // Defensive: trust a successful uninstall even if the id is still
      // briefly returned by `flatpak list` due to caching.
      final installed = e.success
          ? fromList.difference({e.appId})
          : fromList;

      // Drop the event id AND self-heal any ghost uninstallingIds whose
      // app is no longer in `installed`. This is what stops the dynamic
      // island from showing "Uninstalling X" forever when flatpak
      // actually removed the app under a slightly different id form
      // than what we added to uninstallingIds (which happens when the
      // UI dispatches app.id from cached PensHub metadata instead of
      // app.flatpakId).
      final newUninstalling = <String>{};
      for (final id in s.uninstallingIds) {
        if (id == e.appId) continue;
        if (!installed.contains(id)) {
          debugPrint('[FLATPAK-BLOC] self-heal: dropping ghost uninstallingId=$id '
              '(no longer in installed set)');
          continue;
        }
        newUninstalling.add(id);
      }

      debugPrint('[FLATPAK-BLOC] _UninstallFinished appId=${e.appId} '
          'uninstallingIds: ${s.uninstallingIds.length} → ${newUninstalling.length}');

      emit(s.copyWith(uninstallingIds: newUninstalling, installed: installed));
    });

    /// ---------------------
    /// FLATPAK EVENT STREAM
    /// ---------------------
    _installSub = FlatpakPlatform.installEvents().listen((event) {
      try {
        // =============================
        // 1. STRUCTURED MAP EVENTS (MAIN)
        // =============================
        if (event is Map) {
          final m = Map<String, dynamic>.from(event);

          final type = m['type'];
          final appId = FlatpakRepository.normalizeFlatpakId(m['appId']);

          if (type == 'progress') {
            final step = m['step'] as int?;
            final total = m['total'] as int?;
            final p = m['percent'] as int;
            final phase = switch (m['phase']) {
              'downloading' => InstallPhase.downloading,
              'installing' => InstallPhase.installing,
              _ => null,
            };

            int finalPercent;

            if (step != null && total != null && total > 0) {
              finalPercent = (((step - 1) + (p / 100)) / total * 100).round();
            } else {
              finalPercent = p.clamp(0, 100);
            }

            add(InstallProgressEvent(appId, finalPercent, phase: phase));
            return;
          }

          if (type == 'done') {
            // Native plugin and synthetic fallback both emit a generic
            // 'done' event without declaring install vs uninstall.
            // Disambiguate by checking which set the id is currently in.
            // Fall back to both if we can't tell (idempotent).
            final ok = m['status'] == 0;
            final s = state;
            debugPrint('[FLATPAK-BLOC] done event appId=$appId ok=$ok '
                'stateType=${s.runtimeType}');
            if (s is FlatpakLoaded) {
              if (s.uninstallingIds.contains(appId)) {
                debugPrint('[FLATPAK-BLOC] routing done → _UninstallFinished');
                add(_UninstallFinished(appId, ok));
              } else if (s.installingIds.contains(appId)) {
                debugPrint('[FLATPAK-BLOC] routing done → _InstallFinished');
                add(_InstallFinished(appId, ok));
              } else {
                debugPrint('[FLATPAK-BLOC] done for $appId not in either set — '
                    'firing safety-net both. installingIds=${s.installingIds} '
                    'uninstallingIds=${s.uninstallingIds}');
                // Safety net: fire both so nothing is left hanging if
                // the state was transiently out of sync.
                add(_InstallFinished(appId, ok));
                add(_UninstallFinished(appId, ok));
              }
            }
            return;
          }

          return;
        }

        // =============================
        // 2. RAW STDOUT STRING (FALLBACK)
        // =============================
        if (event is String) {
          final line = event;

          final installDone = _installDoneRe.firstMatch(line);
          if (installDone != null) {
            add(
              _InstallFinished(
                FlatpakRepository.normalizeFlatpakId(
                  installDone.namedGroup('id')!,
                ),
                true,
              ),
            );
            return;
          }

          final uninstallDone = _uninstallDoneRe.firstMatch(line);
          if (uninstallDone != null) {
            add(
              _UninstallFinished(
                FlatpakRepository.normalizeFlatpakId(
                  uninstallDone.namedGroup('id')!,
                ),
                true,
              ),
            );
            return;
          }

          final staged = _stageRe.firstMatch(line);
          if (staged != null) {
            final id = FlatpakRepository.normalizeFlatpakId(
              staged.namedGroup('id')!,
            );
            final step = int.parse(staged.namedGroup('step')!);
            final total = int.parse(staged.namedGroup('total')!);
            final p = int.parse(staged.namedGroup('percent')!);

            final percent = (((step - 1) + (p / 100)) / total * 100).round();
            add(InstallProgressEvent(id, percent));
            return;
          }

          final simple = _simpleRe.firstMatch(line);
          if (simple != null) {
            final id = FlatpakRepository.normalizeFlatpakId(
              simple.namedGroup('id')!,
            );
            final p = int.parse(simple.namedGroup('percent')!);
            add(InstallProgressEvent(id, p));
          }
        }
      } catch (e) {
        debugPrint('Install stream parse error: $e');
      }
    });
  }

  /// Debounce transformer for events that fire rapidly
  static EventTransformer<E> _debounce<E>(Duration duration) {
    return (events, mapper) =>
        events.transform(_DebounceTransformer(duration)).asyncExpand(mapper);
  }

  @override
  Future<void> close() {
    _installSub?.cancel();
    return super.close();
  }
}

/// Lightweight debounce StreamTransformer
class _DebounceTransformer<T> extends StreamTransformerBase<T, T> {
  final Duration duration;
  const _DebounceTransformer(this.duration);

  @override
  Stream<T> bind(Stream<T> stream) {
    Timer? timer;
    late StreamController<T> controller;

    controller = StreamController<T>(
      onListen: () {
        final sub = stream.listen(
          (data) {
            timer?.cancel();
            timer = Timer(duration, () => controller.add(data));
          },
          onError: controller.addError,
          onDone: () {
            timer?.cancel();
            controller.close();
          },
        );
        controller.onCancel = () {
          timer?.cancel();
          sub.cancel();
        };
      },
    );

    return controller.stream;
  }
}
