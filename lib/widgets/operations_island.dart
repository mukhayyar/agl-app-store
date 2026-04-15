import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../bloc/flatpak_bloc.dart';
import '../services/user_log.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// Floating overlay that surfaces ongoing install / uninstall operations
/// across all pages. Shows a small pill at the top of the screen when
/// any operation is in flight; tapping expands it into a card listing
/// every active operation with its progress.
///
/// Placed as the top child of a Stack alongside the page body so it
/// floats above page chrome (like Apple's Dynamic Island).
class OperationsIsland extends StatefulWidget {
  const OperationsIsland({super.key});

  @override
  State<OperationsIsland> createState() => _OperationsIslandState();
}

class _OperationsIslandState extends State<OperationsIsland>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;
  // Cache the last-known op snapshot so the island stays visible
  // through transient non-FlatpakLoaded states (e.g. while the bloc
  // emits FlatpakLoading during a source switch). Without this the
  // island would briefly disappear and re-appear, looking like the
  // operation was lost.
  List<_Op> _lastOps = const [];

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<FlatpakBloc, FlatpakState>(
      buildWhen: (p, c) {
        // Rebuild on FlatpakLoaded transitions (so we refresh cached
        // ops AND react to isLoading / pendingSource flips for the
        // source-switch indicator).
        if (c is FlatpakLoaded) {
          if (p is! FlatpakLoaded) return true;
          return p.installingIds != c.installingIds ||
              p.uninstallingIds != c.uninstallingIds ||
              p.installProgress != c.installProgress ||
              p.installPhase != c.installPhase ||
              p.isLoading != c.isLoading ||
              p.pendingSource != c.pendingSource;
        }
        return false;
      },
      builder: (context, state) {
        // Refresh cache when we have a loaded state; otherwise keep
        // showing the last snapshot through the transient state.
        if (state is FlatpakLoaded) {
          _lastOps = _buildOps(state);
        }
        final ops = _lastOps;
        final showing = ops.isNotEmpty;

        // Auto-collapse when the queue empties so the next time something
        // starts the user sees the compact pill first.
        if (!showing && _expanded) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _expanded = false);
          });
        }

        return SafeArea(
          bottom: false,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.92, end: 1.0).animate(anim),
                alignment: Alignment.topCenter,
                child: child,
              ),
            ),
            child: !showing
                ? const SizedBox.shrink(key: ValueKey('hidden'))
                : Padding(
                    key: const ValueKey('shown'),
                    padding: const EdgeInsets.fromLTRB(
                        AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, 0),
                    child: _Island(
                      ops: ops,
                      expanded: _expanded,
                      onTap: () {
                        UserLog.tap('island.toggle', {
                          'to': _expanded ? 'collapsed' : 'expanded',
                          'ops': ops.length,
                        });
                        setState(() => _expanded = !_expanded);
                      },
                      onClose: () {
                        UserLog.tap('island.collapse');
                        setState(() => _expanded = false);
                      },
                    ),
                  ),
          ),
        );
      },
    );
  }

  /// Build the list of currently-running operations from bloc state.
  /// Resolves a friendly name when the package is in the loaded items
  /// list; otherwise falls back to the flatpak id.
  List<_Op> _buildOps(FlatpakLoaded s) {
    final byId = <String, String>{};
    for (final p in s.items) {
      // Both id and flatpakId can match incoming installingIds entries
      byId[p.id] = p.name;
      byId[p.flatpakId] = p.name;
    }
    final out = <_Op>[];

    // Source switch op goes first so it's always the primary pill
    if (s.isLoading && s.pendingSource != null) {
      out.add(_Op(
        id: '__switch__',
        name: s.pendingSource!.label,
        kind: _OpKind.switching,
      ));
    }

    for (final id in s.installingIds) {
      out.add(_Op(
        id: id,
        name: byId[id] ?? id,
        kind: _OpKind.install,
        progress: s.installProgress[id],
        phase: s.installPhase[id],
      ));
    }
    for (final id in s.uninstallingIds) {
      out.add(_Op(
        id: id,
        name: byId[id] ?? id,
        kind: _OpKind.uninstall,
      ));
    }
    return out;
  }
}

// ───────────────────────── Island shell ──────────────────────────────
class _Island extends StatelessWidget {
  final List<_Op> ops;
  final bool expanded;
  final VoidCallback onTap;
  final VoidCallback onClose;

  const _Island({
    required this.ops,
    required this.expanded,
    required this.onTap,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final base = dark ? const Color(0xFF11141F) : const Color(0xFF101218);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Material(
          color: Colors.transparent,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              decoration: BoxDecoration(
                color: base,
                borderRadius: BorderRadius.circular(expanded ? 22 : 28),
                // Tight shadow — blur 18 was causing 30 fps drops on
                // the Pi 4's VideoCore VI whenever the pill animated;
                // blur area scales quadratically so blur 6 costs ~9×
                // less fill per frame and still reads as elevated.
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x55000000),
                    blurRadius: 6,
                    offset: Offset(0, 3),
                  ),
                ],
              ),
              child: AnimatedSize(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: expanded
                    ? _ExpandedBody(ops: ops, onClose: onClose)
                    : _CollapsedPill(ops: ops),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ───────────────────────── Collapsed pill ────────────────────────────
class _CollapsedPill extends StatelessWidget {
  final List<_Op> ops;
  const _CollapsedPill({required this.ops});

  @override
  Widget build(BuildContext context) {
    final primary = ops.first;
    final extras = ops.length - 1;
    final percent = primary.progress;
    final hasProgress = percent != null && percent > 0;

    final verb = primary.verb;

    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: 10),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Spinner / progress ring
          SizedBox(
            width: 22,
            height: 22,
            child: hasProgress
                ? Stack(
                    alignment: Alignment.center,
                    children: [
                      CircularProgressIndicator(
                        value: percent / 100,
                        strokeWidth: 2.5,
                        valueColor: const AlwaysStoppedAnimation(
                            AppColors.accentCyan),
                        backgroundColor:
                            Colors.white.withValues(alpha: 0.18),
                      ),
                      Text('$percent',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 8,
                              fontWeight: FontWeight.w800)),
                    ],
                  )
                : const CircularProgressIndicator(
                    strokeWidth: 2.5,
                    valueColor:
                        AlwaysStoppedAnimation(AppColors.accentCyan),
                  ),
          ),
          const SizedBox(width: 10),
          // Verb + name
          Flexible(
            child: Text(
              extras > 0
                  ? '$verb ${primary.name} +$extras'
                  : '$verb ${primary.name}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Icon(Icons.expand_more_rounded,
              color: Colors.white.withValues(alpha: 0.7), size: 18),
        ],
      ),
    );
  }
}

// ───────────────────────── Expanded body ─────────────────────────────
class _ExpandedBody extends StatelessWidget {
  final List<_Op> ops;
  final VoidCallback onClose;

  const _ExpandedBody({required this.ops, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.md, AppSpacing.sm, AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Row(
            children: [
              const Icon(Icons.bolt_rounded,
                  color: AppColors.accentCyan, size: 18),
              const SizedBox(width: 6),
              const Text('Active operations',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.3,
                  )),
              const Spacer(),
              IconButton(
                tooltip: 'Collapse',
                onPressed: onClose,
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(),
                icon: Icon(Icons.expand_less_rounded,
                    color: Colors.white.withValues(alpha: 0.7), size: 22),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          // Operation rows
          for (int i = 0; i < ops.length; i++) ...[
            _OpRow(op: ops[i]),
            if (i != ops.length - 1)
              Container(
                margin: const EdgeInsets.symmetric(vertical: 6),
                height: 1,
                color: Colors.white.withValues(alpha: 0.06),
              ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────── Op row ──────────────────────────────────
class _OpRow extends StatelessWidget {
  final _Op op;
  const _OpRow({required this.op});

  @override
  Widget build(BuildContext context) {
    final tint = switch (op.kind) {
      _OpKind.install => AppColors.accentCyan,
      _OpKind.uninstall => AppColors.accentOrange,
      _OpKind.switching => AppColors.accentViolet,
    };
    final percent = op.progress;
    final hasProgress = percent != null && percent > 0;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(op.kind.icon, color: tint, size: 16),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(op.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    )),
                const SizedBox(height: 2),
                Text(
                  op.kind == _OpKind.switching
                      ? 'Loading catalog…'
                      : hasProgress
                          ? '${op.verb} • $percent%'
                          : '${op.verb}…',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.65),
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 5),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: SizedBox(
                    height: 4,
                    child: hasProgress
                        ? LinearProgressIndicator(
                            value: percent / 100,
                            backgroundColor:
                                Colors.white.withValues(alpha: 0.10),
                            valueColor: AlwaysStoppedAnimation(tint),
                          )
                        : LinearProgressIndicator(
                            backgroundColor:
                                Colors.white.withValues(alpha: 0.10),
                            valueColor: AlwaysStoppedAnimation(tint),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────── Models ──────────────────────────────────
enum _OpKind {
  install(verb: 'Installing', icon: Icons.download_rounded),
  uninstall(verb: 'Uninstalling', icon: Icons.delete_outline_rounded),
  switching(verb: 'Switching to', icon: Icons.swap_horiz_rounded);

  final String verb;
  final IconData icon;
  const _OpKind({required this.verb, required this.icon});
}

class _Op {
  final String id;
  final String name;
  final _OpKind kind;
  final int? progress;
  final InstallPhase? phase;
  const _Op({
    required this.id,
    required this.name,
    required this.kind,
    this.progress,
    this.phase,
  });

  /// Verb that respects the current install phase so the pill reads
  /// "Downloading {app}" while flatpak is pulling refs and flips to
  /// "Installing {app}" once it starts deploying. Falls back to the
  /// kind's default verb when no phase is reported (desktop / native).
  String get verb {
    if (kind == _OpKind.install && phase == InstallPhase.downloading) {
      return 'Downloading';
    }
    return kind.verb;
  }
}
