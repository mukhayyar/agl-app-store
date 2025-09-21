import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../data/flatpak_repository.dart';
import '../models/flatpak_package.dart';

/// EVENTS
abstract class FlatpakEvent extends Equatable {
  const FlatpakEvent();
  @override
  List<Object?> get props => [];
}

class RefreshAll extends FlatpakEvent {
  const RefreshAll();
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
  final String appId;
  const InstallApp(this.appId);
  @override
  List<Object?> get props => [appId];
}

class UninstallApp extends FlatpakEvent {
  final String appId;
  const UninstallApp(this.appId);
  @override
  List<Object?> get props => [appId];
}

class UpdateApp extends FlatpakEvent {
  final String appId;
  const UpdateApp(this.appId);
  @override
  List<Object?> get props => [appId];
}

/// STATES
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
  final Set<String> installed;

  const FlatpakLoaded({
    required this.items,
    required this.page,
    required this.pageSize,
    required this.hasMore,
    required this.installed,
    this.query,
  });

  FlatpakLoaded copyWith({
    List<FlatpakPackage>? items,
    int? page,
    int? pageSize,
    bool? hasMore,
    String? query,
    Set<String>? installed,
  }) {
    return FlatpakLoaded(
      items: items ?? this.items,
      page: page ?? this.page,
      pageSize: pageSize ?? this.pageSize,
      hasMore: hasMore ?? this.hasMore,
      query: query ?? this.query,
      installed: installed ?? this.installed,
    );
  }

  @override
  List<Object?> get props => [items, page, pageSize, hasMore, query, installed];
}

class FlatpakError extends FlatpakState {
  final String message;
  const FlatpakError(this.message);
  @override
  List<Object?> get props => [message];
}

/// BLOC
class FlatpakBloc extends Bloc<FlatpakEvent, FlatpakState> {
  final FlatpakRepository repo;
  static const _pageSize = 50;

  FlatpakBloc({required this.repo}) : super(FlatpakLoading()) {
    on<RefreshAll>((e, emit) async {
      try {
        emit(FlatpakLoading());
        await repo.init();
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
          ),
        );
        // trigger enrich tanpa blocking UI
        add(const EnrichCurrentPage());
      } catch (err) {
        emit(FlatpakError('Gagal memuat paket: $err'));
      }
    });

    on<LoadFirstPage>((e, emit) async {
      try {
        emit(FlatpakLoading());
        await repo.init();
        final installed = await repo.installedIds();
        final first = await repo.getPage(
          page: 1,
          pageSize: _pageSize,
          query: e.query,
        );
        final total = await repo.totalCount(query: e.query);
        emit(
          FlatpakLoaded(
            items: first,
            page: 1,
            pageSize: _pageSize,
            hasMore: first.length < total,
            query: e.query,
            installed: installed,
          ),
        );
        add(const EnrichCurrentPage());
      } catch (err) {
        emit(FlatpakError('Gagal memuat paket: $err'));
      }
    });

    on<EnrichCurrentPage>((e, emit) async {
      final s = state;
      if (s is! FlatpakLoaded) return;
      // ambil salinan item halaman saat ini, encrich, lalu reload dari cache agar UI update
      await repo.enrichMissingDetails(s.items);
      final refreshed = await repo.getPage(
        page: s.page,
        pageSize: s.pageSize,
        query: s.query,
      );
      emit(s.copyWith(items: refreshed));
    });

    on<LoadNextPage>((e, emit) async {
      final s = state;
      if (s is! FlatpakLoaded || !s.hasMore) return;
      try {
        final nextPage = s.page + 1;
        final next = await repo.getPage(
          page: nextPage,
          pageSize: s.pageSize,
          query: s.query,
        );
        final total = await repo.totalCount(query: s.query);
        emit(
          s.copyWith(
            items: [...s.items, ...next],
            page: nextPage,
            hasMore: (nextPage * s.pageSize) < total,
          ),
        );
      } catch (err) {
        emit(FlatpakError('Gagal memuat halaman berikutnya: $err'));
      }
    });

    on<InstallApp>((e, emit) async {
      final s = state;
      if (s is! FlatpakLoaded) return;
      try {
        await repo.install(e.appId);
        emit(s.copyWith(installed: {...s.installed}..add(e.appId)));
      } catch (err) {
        emit(FlatpakError('Gagal menginstal: $err'));
      }
    });

    on<UninstallApp>((e, emit) async {
      final s = state;
      if (s is! FlatpakLoaded) return;
      try {
        await repo.uninstall(e.appId);
        emit(s.copyWith(installed: {...s.installed}..remove(e.appId)));
      } catch (err) {
        emit(FlatpakError('Gagal menghapus: $err'));
      }
    });

    on<UpdateApp>((e, emit) async {
      final s = state;
      if (s is! FlatpakLoaded) return;
      try {
        await repo.update(e.appId);
        emit(s); // state tetap, bisa trigger snackbar di UI
      } catch (err) {
        emit(FlatpakError('Gagal memperbarui: $err'));
      }
    });
  }
}

class EnrichCurrentPage extends FlatpakEvent {
  const EnrichCurrentPage();
  @override
  List<Object?> get props => [];
}

class InstallProgressEvent extends FlatpakEvent {
  // kiriman dari EventChannel native
  final String appId;
  final String type; // 'stdout' | 'stderr' | 'done'
  final int? status; // hanya ada saat type == 'done'
  final String? line; // untuk stdout/stderr
  const InstallProgressEvent({
    required this.appId,
    required this.type,
    this.status,
    this.line,
  });
  @override
  List<Object?> get props => [appId, type, status, line];
}
