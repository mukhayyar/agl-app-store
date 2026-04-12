import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../data/flatpak_repository.dart';
import '../models/app_source.dart';
import '../models/flatpak_package.dart';
import '../platform/flatpak_platform.dart';

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
  const InstallProgressEvent(this.appId, this.percent);
  @override
  List<Object?> get props => [appId, percent];
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

      emit(FlatpakLoading());
      await repo.setSource(event.source); // wipes cache internally
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
    /// INSTALL START
    /// ---------------------
    on<InstallApp>((e, emit) async {
      final s = state;
      if (s is! FlatpakLoaded) return;

      final id = FlatpakRepository.normalizeFlatpakId(e.flatpakId);
      if (s.installingIds.contains(id)) return;

      emit(
        s.copyWith(
          installingIds: {...s.installingIds, id},
          installProgress: {...s.installProgress, id: 0},
        ),
      );

      repo.install(id).catchError((_) {
        add(_InstallFinished(id, false));
      });
    });

    /// ---------------------
    /// INSTALL FINISHED
    /// ---------------------
    on<_InstallFinished>((e, emit) async {
      final s = state;
      if (s is! FlatpakLoaded) return;

      final newInstalling = Set<String>.from(s.installingIds)..remove(e.appId);
      final installed = await repo.installedIds();

      emit(
        s.copyWith(
          installingIds: newInstalling,
          installed: installed,
          installProgress: Map.of(s.installProgress)..remove(e.appId),
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
      final s = state;
      if (s is! FlatpakLoaded) return;

      final newUninstalling = Set<String>.from(s.uninstallingIds)
        ..remove(e.appId);
      final installed = await repo.installedIds();

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

            int finalPercent;

            if (step != null && total != null && total > 0) {
              finalPercent = (((step - 1) + (p / 100)) / total * 100).round();
            } else {
              finalPercent = p.clamp(0, 100);
            }

            add(InstallProgressEvent(appId, finalPercent));
            return;
          }

          if (type == 'done') {
            add(_InstallFinished(appId, m['status'] == 0));
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
