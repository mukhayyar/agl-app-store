import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/log_service.dart';
import '../services/system_monitor.dart';
import '../widgets/gauge_widget.dart';
import '../widgets/line_chart_widget.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

class MonitorPage extends StatelessWidget {
  const MonitorPage({super.key});

  @override
  Widget build(BuildContext context) {
    final mon = context.watch<SystemMonitor>();
    final ramPct = mon.ramTotalMb > 0
        ? (mon.ramUsedMb / mon.ramTotalMb * 100)
        : 0.0;
    final diskPct = mon.diskTotalGb > 0
        ? (mon.diskUsedGb / mon.diskTotalGb * 100)
        : 0.0;
    final netTotalBps = mon.rxBytesPerSec + mon.txBytesPerSec;

    final cpuStatus = _statusFor(mon.cpu, warn: 60, crit: 85);
    final ramStatus = _statusFor(ramPct, warn: 70, crit: 90);
    final diskStatus = _statusFor(diskPct, warn: 80, crit: 95);

    return Scaffold(
      backgroundColor: context.colors.bg,
      body: SafeArea(
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            // ── Header ────────────────────────────────────────────
            SliverToBoxAdapter(
              child: _Header(),
            ),

            // ── At-a-glance summary strip ────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.pageH),
                child: LayoutBuilder(builder: (context, box) {
                  final tiles = [
                    _SummaryTile(
                      label: 'CPU',
                      value: '${mon.cpu.toStringAsFixed(0)}%',
                      status: cpuStatus,
                    ),
                    _SummaryTile(
                      label: 'MEMORY',
                      value: '${ramPct.toStringAsFixed(0)}%',
                      status: ramStatus,
                    ),
                    _SummaryTile(
                      label: 'STORAGE',
                      value: '${diskPct.toStringAsFixed(0)}%',
                      status: diskStatus,
                    ),
                    _SummaryTile(
                      label: 'NETWORK',
                      value: _fmtBps(netTotalBps),
                      status: _Status(
                        text: 'Active',
                        color: AppColors.accentCyan,
                      ),
                    ),
                  ];
                  // Wrap to 2×2 on narrow, 1×4 on wide
                  if (box.maxWidth > 600) {
                    return Row(
                      children: [
                        for (int i = 0; i < tiles.length; i++) ...[
                          Expanded(child: tiles[i]),
                          if (i != tiles.length - 1)
                            const SizedBox(width: AppSpacing.sm),
                        ],
                      ],
                    );
                  }
                  return Column(
                    children: [
                      Row(children: [
                        Expanded(child: tiles[0]),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(child: tiles[1]),
                      ]),
                      const SizedBox(height: AppSpacing.sm),
                      Row(children: [
                        Expanded(child: tiles[2]),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(child: tiles[3]),
                      ]),
                    ],
                  );
                }),
              ),
            ),
            const SliverToBoxAdapter(
                child: SizedBox(height: AppSpacing.lg)),

            // ── CPU detail card ──────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.pageH),
                child: _MetricCard(
                  label: 'PROCESSOR',
                  gaugeValue: mon.cpu,
                  headline: '${mon.cpu.toStringAsFixed(1)}%',
                  caption: 'Current CPU usage',
                  status: cpuStatus,
                  history: mon.cpuHistory,
                  maxValue: 100,
                  yAxisLabels: const ['100%', '50%', '0%'],
                  unitIsPercent: true,
                ),
              ),
            ),
            const SliverToBoxAdapter(
                child: SizedBox(height: AppSpacing.md)),

            // ── Memory detail card ───────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.pageH),
                child: _MetricCard(
                  label: 'MEMORY',
                  gaugeValue: ramPct,
                  headline: '${ramPct.toStringAsFixed(1)}%',
                  caption:
                      '${_fmtMb(mon.ramUsedMb)} of ${_fmtMb(mon.ramTotalMb)} used'
                      ' · ${_fmtMb(mon.ramTotalMb - mon.ramUsedMb)} free',
                  status: ramStatus,
                  history: mon.ramHistory,
                  maxValue: 100,
                  yAxisLabels: const ['100%', '50%', '0%'],
                  unitIsPercent: true,
                ),
              ),
            ),
            const SliverToBoxAdapter(
                child: SizedBox(height: AppSpacing.md)),

            // ── Storage card ─────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.pageH),
                child: _StorageCard(
                  usedGb: mon.diskUsedGb,
                  totalGb: mon.diskTotalGb,
                  pct: diskPct,
                  status: diskStatus,
                ),
              ),
            ),
            const SliverToBoxAdapter(
                child: SizedBox(height: AppSpacing.md)),

            // ── Network card ─────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.pageH),
                child: _NetworkCard(
                  rxBps: mon.rxBytesPerSec,
                  txBps: mon.txBytesPerSec,
                  rxHistory: mon.rxHistory,
                  txHistory: mon.txHistory,
                ),
              ),
            ),
            const SliverToBoxAdapter(
                child: SizedBox(height: AppSpacing.md)),

            // ── App log viewer ───────────────────────────────────
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: AppSpacing.pageH),
                child: _LogPanel(),
              ),
            ),
            const SliverToBoxAdapter(
                child: SizedBox(height: AppSpacing.huge)),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════ Header ══════════════════════════════════
class _Header extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.pageH, AppSpacing.lg, AppSpacing.pageH, AppSpacing.xl),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 28,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(2),
              gradient: const LinearGradient(
                colors: [AppColors.accentCyan, AppColors.accentGreen],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('System Monitor',
                    style: Theme.of(context).textTheme.displaySmall),
                const SizedBox(height: 2),
                Text('Live device resource usage',
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          _LivePill(),
        ],
      ),
    );
  }
}

class _LivePill extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppSpacing.rFull),
        border: Border.all(
            color: AppColors.success.withValues(alpha: 0.3), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: const BoxDecoration(
                color: AppColors.success, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          const Text('LIVE',
              style: TextStyle(
                color: AppColors.success,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              )),
        ],
      ),
    );
  }
}

// ═══════════════════════ Summary Tile ════════════════════════════════
class _SummaryTile extends StatelessWidget {
  final String label;
  final String value;
  final _Status status;

  const _SummaryTile({
    required this.label,
    required this.value,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: context.colors.card,
        borderRadius: BorderRadius.circular(AppSpacing.rMd),
        border: Border.all(color: context.colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: status.color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: context.colors.textT,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                color: context.colors.textP,
                fontSize: 22,
                fontWeight: FontWeight.w700,
                height: 1.1,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            status.text,
            style: TextStyle(
              color: status.color,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════ Metric Card ═════════════════════════════════
/// Reusable detail card used for CPU and Memory: large headline number,
/// status label, history chart with Y-axis + time labels, and
/// min/avg/max stats row.
class _MetricCard extends StatelessWidget {
  final String label;
  final double? gaugeValue;
  final String headline;
  final String caption;
  final _Status status;
  final List<double> history;
  final double maxValue;
  final List<String> yAxisLabels;
  final bool unitIsPercent;

  const _MetricCard({
    required this.label,
    this.gaugeValue,
    required this.headline,
    required this.caption,
    required this.status,
    required this.history,
    required this.maxValue,
    required this.yAxisLabels,
    required this.unitIsPercent,
  });

  @override
  Widget build(BuildContext context) {
    final stats = _summaryOf(history);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: context.colors.card,
        borderRadius: BorderRadius.circular(AppSpacing.rLg),
        border: Border.all(color: context.colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: label + status
          Row(
            children: [
              Text(label,
                  style: TextStyle(
                    color: context.colors.textT,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                  )),
              const Spacer(),
              _StatusBadge(status: status),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),

          // Row 2: optional gauge + headline + caption
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (gaugeValue != null) ...[
                GaugeWidget(
                  value: gaugeValue!,
                  size: 84,
                  label: '',
                ),
                const SizedBox(width: AppSpacing.lg),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      headline,
                      style: TextStyle(
                        color: status.color,
                        fontSize: 34,
                        fontWeight: FontWeight.w800,
                        height: 1,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(caption,
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),

          // Chart
          SizedBox(
            height: 110,
            child: LineChartWidget(
              data: history,
              maxValue: maxValue,
              color: status.color,
              yAxisLabels: yAxisLabels,
              axisColor: context.colors.textT,
            ),
          ),
          const SizedBox(height: 4),

          // X-axis time labels
          Padding(
            padding: const EdgeInsets.only(left: 32),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('60s ago',
                    style: TextStyle(
                        color: context.colors.textT, fontSize: 10)),
                Text('now',
                    style: TextStyle(
                        color: context.colors.textT, fontSize: 10)),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // Stats row: Min · Avg · Max
          Container(
            padding: const EdgeInsets.symmetric(
                vertical: AppSpacing.sm, horizontal: AppSpacing.md),
            decoration: BoxDecoration(
              color: context.colors.cardEl,
              borderRadius: BorderRadius.circular(AppSpacing.rSm),
            ),
            child: Row(
              children: [
                _Stat(label: 'MIN', value: _fmt(stats.min)),
                _VSep(),
                _Stat(label: 'AVG', value: _fmt(stats.avg)),
                _VSep(),
                _Stat(label: 'MAX', value: _fmt(stats.max)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _fmt(double v) =>
      unitIsPercent ? '${v.toStringAsFixed(0)}%' : v.toStringAsFixed(1);
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  const _Stat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(label,
              style: TextStyle(
                color: context.colors.textT,
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              )),
          const SizedBox(height: 2),
          Text(value,
              style: TextStyle(
                color: context.colors.textP,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              )),
        ],
      ),
    );
  }
}

class _VSep extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 28,
      color: context.colors.border,
    );
  }
}

// ═══════════════════════ Storage Card ════════════════════════════════
class _StorageCard extends StatelessWidget {
  final double usedGb;
  final double totalGb;
  final double pct;
  final _Status status;

  const _StorageCard({
    required this.usedGb,
    required this.totalGb,
    required this.pct,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    final freeGb = (totalGb - usedGb).clamp(0, totalGb);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: context.colors.card,
        borderRadius: BorderRadius.circular(AppSpacing.rLg),
        border: Border.all(color: context.colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('STORAGE',
                  style: TextStyle(
                    color: context.colors.textT,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                  )),
              const Spacer(),
              _StatusBadge(status: status),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${pct.toStringAsFixed(1)}%',
                style: TextStyle(
                  color: status.color,
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  height: 1,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    '${usedGb.toStringAsFixed(1)} GB of ${totalGb.toStringAsFixed(1)} GB used',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppSpacing.rSm),
            child: LinearProgressIndicator(
              value: (pct / 100).clamp(0, 1),
              minHeight: 12,
              backgroundColor: context.colors.cardEl,
              valueColor: AlwaysStoppedAnimation<Color>(status.color),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              _InlineStat(
                label: 'USED',
                value: '${usedGb.toStringAsFixed(1)} GB',
                dotColor: status.color,
              ),
              const SizedBox(width: AppSpacing.xl),
              _InlineStat(
                label: 'FREE',
                value: '${freeGb.toStringAsFixed(1)} GB',
                dotColor: context.colors.textT,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InlineStat extends StatelessWidget {
  final String label;
  final String value;
  final Color dotColor;
  const _InlineStat({
    required this.label,
    required this.value,
    required this.dotColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: dotColor,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(label,
            style: TextStyle(
              color: context.colors.textT,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            )),
        const SizedBox(width: 6),
        Text(value,
            style: TextStyle(
              color: context.colors.textP,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            )),
      ],
    );
  }
}

// ═══════════════════════ Network Card ════════════════════════════════
class _NetworkCard extends StatelessWidget {
  final double rxBps;
  final double txBps;
  final List<double> rxHistory;
  final List<double> txHistory;

  const _NetworkCard({
    required this.rxBps,
    required this.txBps,
    required this.rxHistory,
    required this.txHistory,
  });

  @override
  Widget build(BuildContext context) {
    final maxRx = rxHistory.isEmpty
        ? 1024.0
        : (rxHistory.reduce((a, b) => a > b ? a : b) * 1.3)
            .clamp(1024, double.infinity)
            .toDouble();
    final maxTx = txHistory.isEmpty
        ? 1024.0
        : (txHistory.reduce((a, b) => a > b ? a : b) * 1.3)
            .clamp(1024, double.infinity)
            .toDouble();

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: context.colors.card,
        borderRadius: BorderRadius.circular(AppSpacing.rLg),
        border: Border.all(color: context.colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('NETWORK',
              style: TextStyle(
                color: context.colors.textT,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
              )),
          const SizedBox(height: AppSpacing.lg),
          LayoutBuilder(builder: (context, box) {
            final download = _DirectionStat(
              icon: Icons.arrow_downward_rounded,
              label: 'DOWNLOAD',
              value: _fmtBps(rxBps),
              color: AppColors.accentGreen,
              history: rxHistory,
              maxValue: maxRx,
            );
            final upload = _DirectionStat(
              icon: Icons.arrow_upward_rounded,
              label: 'UPLOAD',
              value: _fmtBps(txBps),
              color: AppColors.accentCyan,
              history: txHistory,
              maxValue: maxTx,
            );
            if (box.maxWidth > 450) {
              return Row(children: [
                Expanded(child: download),
                const SizedBox(width: AppSpacing.lg),
                Expanded(child: upload),
              ]);
            }
            return Column(children: [
              download,
              const SizedBox(height: AppSpacing.lg),
              upload,
            ]);
          }),
        ],
      ),
    );
  }
}

class _DirectionStat extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final List<double> history;
  final double maxValue;

  const _DirectionStat({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    required this.history,
    required this.maxValue,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(AppSpacing.rSm),
              ),
              child: Icon(icon, color: color, size: 14),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(label,
                style: TextStyle(
                  color: context.colors.textT,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.3,
                )),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(value,
              style: TextStyle(
                color: context.colors.textP,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              )),
        ),
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          height: 54,
          child: LineChartWidget(
            data: history,
            maxValue: maxValue,
            color: color,
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════ Status helpers ══════════════════════════════
class _Status {
  final String text;
  final Color color;
  const _Status({required this.text, required this.color});
}

class _StatusBadge extends StatelessWidget {
  final _Status status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm, vertical: 3),
      decoration: BoxDecoration(
        color: status.color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppSpacing.rFull),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration:
                BoxDecoration(color: status.color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(status.text,
              style: TextStyle(
                color: status.color,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              )),
        ],
      ),
    );
  }
}

_Status _statusFor(double pct,
    {required double warn, required double crit}) {
  if (pct >= crit) {
    return const _Status(text: 'Critical', color: AppColors.danger);
  }
  if (pct >= warn) {
    return const _Status(text: 'High', color: AppColors.warning);
  }
  return const _Status(text: 'Normal', color: AppColors.accentGreen);
}

// ═══════════════════════ Data helpers ════════════════════════════════
class _HistoryStats {
  final double min;
  final double avg;
  final double max;
  const _HistoryStats(this.min, this.avg, this.max);
}

_HistoryStats _summaryOf(List<double> history) {
  if (history.isEmpty) return const _HistoryStats(0, 0, 0);
  double mn = history.first, mx = history.first, sum = 0;
  for (final v in history) {
    if (v < mn) mn = v;
    if (v > mx) mx = v;
    sum += v;
  }
  return _HistoryStats(mn, sum / history.length, mx);
}

String _fmtMb(double mb) {
  if (mb >= 1024) return '${(mb / 1024).toStringAsFixed(1)} GB';
  return '${mb.toStringAsFixed(0)} MB';
}

String _fmtBps(double bps) {
  if (bps >= 1024 * 1024) {
    return '${(bps / (1024 * 1024)).toStringAsFixed(1)} MB/s';
  }
  if (bps >= 1024) return '${(bps / 1024).toStringAsFixed(1)} KB/s';
  return '${bps.toStringAsFixed(0)} B/s';
}

// ═══════════════════════ App Log Viewer ══════════════════════════════
/// Live tail of the app's logs — captures `print`, `debugPrint`, and
/// uncaught Flutter errors via [LogService]. Auto-scrolls to the newest
/// entry when the user is already at the bottom; otherwise stays put so
/// reading older lines isn't disrupted.
class _LogPanel extends StatefulWidget {
  const _LogPanel();

  @override
  State<_LogPanel> createState() => _LogPanelState();
}

class _LogPanelState extends State<_LogPanel> {
  final ScrollController _ctl = ScrollController();
  bool _follow = true;
  LogLevel? _filter;

  @override
  void initState() {
    super.initState();
    LogService.instance.addListener(_onLogs);
    _ctl.addListener(_onUserScroll);
  }

  @override
  void dispose() {
    LogService.instance.removeListener(_onLogs);
    _ctl.removeListener(_onUserScroll);
    _ctl.dispose();
    super.dispose();
  }

  void _onLogs() {
    if (!mounted) return;
    setState(() {});
    if (_follow) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_ctl.hasClients) return;
        _ctl.jumpTo(_ctl.position.maxScrollExtent);
      });
    }
  }

  void _onUserScroll() {
    if (!_ctl.hasClients) return;
    final atBottom =
        _ctl.position.pixels >= _ctl.position.maxScrollExtent - 8;
    if (atBottom != _follow) {
      setState(() => _follow = atBottom);
    }
  }

  @override
  Widget build(BuildContext context) {
    final all = LogService.instance.entries;
    final entries = _filter == null
        ? all
        : all.where((e) => e.level == _filter).toList();

    return Container(
      decoration: BoxDecoration(
        color: context.colors.card,
        borderRadius: BorderRadius.circular(AppSpacing.rLg),
        border: Border.all(color: context.colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg, AppSpacing.md, AppSpacing.sm, AppSpacing.sm),
            child: Row(
              children: [
                Text('APP LOGS',
                    style: TextStyle(
                      color: context.colors.textT,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.5,
                    )),
                const SizedBox(width: AppSpacing.sm),
                Text('${entries.length}',
                    style: TextStyle(
                      color: context.colors.textT,
                      fontSize: 11,
                    )),
                const Spacer(),
                _FollowChip(
                  active: _follow,
                  onTap: () {
                    setState(() => _follow = true);
                    if (_ctl.hasClients) {
                      _ctl.jumpTo(_ctl.position.maxScrollExtent);
                    }
                  },
                ),
                const SizedBox(width: AppSpacing.xs),
                IconButton(
                  tooltip: 'Clear',
                  icon: Icon(Icons.delete_sweep_rounded,
                      size: 18, color: context.colors.textS),
                  onPressed: LogService.instance.clear,
                ),
              ],
            ),
          ),
          // Filter chips
          SizedBox(
            height: 32,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              children: [
                _FilterChip(
                  label: 'All',
                  selected: _filter == null,
                  onTap: () => setState(() => _filter = null),
                ),
                _FilterChip(
                  label: 'Info',
                  color: AppColors.accentCyan,
                  selected: _filter == LogLevel.info,
                  onTap: () => setState(() => _filter = LogLevel.info),
                ),
                _FilterChip(
                  label: 'Warn',
                  color: AppColors.warning,
                  selected: _filter == LogLevel.warning,
                  onTap: () => setState(() => _filter = LogLevel.warning),
                ),
                _FilterChip(
                  label: 'Error',
                  color: AppColors.danger,
                  selected: _filter == LogLevel.error,
                  onTap: () => setState(() => _filter = LogLevel.error),
                ),
              ],
            ),
          ),
          // Body
          Container(
            height: 220,
            margin: const EdgeInsets.fromLTRB(
                AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.md),
            decoration: BoxDecoration(
              color: context.colors.cardEl,
              borderRadius: BorderRadius.circular(AppSpacing.rSm),
            ),
            child: entries.isEmpty
                ? Center(
                    child: Text('No logs yet',
                        style: TextStyle(
                          color: context.colors.textT,
                          fontSize: 12,
                        )),
                  )
                : ListView.builder(
                    controller: _ctl,
                    physics: const ClampingScrollPhysics(),
                    padding: const EdgeInsets.symmetric(
                        vertical: 6, horizontal: 8),
                    itemCount: entries.length,
                    itemBuilder: (_, i) => _LogLine(entry: entries[i]),
                  ),
          ),
        ],
      ),
    );
  }
}

class _LogLine extends StatelessWidget {
  final LogEntry entry;
  const _LogLine({required this.entry});

  @override
  Widget build(BuildContext context) {
    final color = switch (entry.level) {
      LogLevel.error => AppColors.danger,
      LogLevel.warning => AppColors.warning,
      LogLevel.info => context.colors.textP,
      LogLevel.debug => context.colors.textT,
    };
    final time = entry.time;
    final ts =
        '${_pad2(time.hour)}:${_pad2(time.minute)}:${_pad2(time.second)}';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: RichText(
        text: TextSpan(
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 11,
            height: 1.4,
            color: color,
          ),
          children: [
            TextSpan(
              text: '$ts  ',
              style: TextStyle(color: context.colors.textT),
            ),
            TextSpan(text: entry.message),
          ],
        ),
      ),
    );
  }

  static String _pad2(int n) => n.toString().padLeft(2, '0');
}

class _FollowChip extends StatelessWidget {
  final bool active;
  final VoidCallback onTap;
  const _FollowChip({required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.accentGreen : context.colors.textT;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppSpacing.rFull),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              active
                  ? Icons.vertical_align_bottom_rounded
                  : Icons.pause_rounded,
              size: 13,
              color: color,
            ),
            const SizedBox(width: 4),
            Text(active ? 'Live' : 'Paused',
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                )),
          ],
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final Color? color;
  final bool selected;
  final VoidCallback onTap;
  const _FilterChip({
    required this.label,
    this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.brand;
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.xs),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md, vertical: 4),
          decoration: BoxDecoration(
            color: selected
                ? c.withValues(alpha: 0.16)
                : context.colors.cardEl,
            borderRadius: BorderRadius.circular(AppSpacing.rFull),
            border: Border.all(
              color: selected
                  ? c.withValues(alpha: 0.35)
                  : context.colors.border,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? c : context.colors.textS,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}
