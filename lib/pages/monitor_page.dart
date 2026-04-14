import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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
        ? (mon.ramUsedMb / mon.ramTotalMb * 100) : 0.0;
    final diskPct = mon.diskTotalGb > 0
        ? (mon.diskUsedGb / mon.diskTotalGb * 100) : 0.0;

    return Scaffold(
      backgroundColor: context.colors.bg,
      body: SafeArea(
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            // Header
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.pageH, AppSpacing.lg, AppSpacing.pageH, AppSpacing.xxl),
                child: Row(
                  children: [
                    Container(
                      width: 4, height: 24,
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
                          Text('Real-time resource usage',
                              style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.success.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(AppSpacing.rFull),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6, height: 6,
                            decoration: const BoxDecoration(
                                color: AppColors.success,
                                shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 4),
                          Text('LIVE', style: TextStyle(
                            color: AppColors.success,
                            fontSize: 14, fontWeight: FontWeight.w700,
                            letterSpacing: 1,
                          )),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // CPU + RAM gauges — side by side on wide, stacked on narrow
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pageH),
                child: LayoutBuilder(builder: (context, box) {
                  final cpuCard = _GaugeCard(
                    title: 'CPU',
                    value: mon.cpu,
                    history: mon.cpuHistory,
                    color: _cpuColor(mon.cpu),
                    detail: '${mon.cpu.toStringAsFixed(1)}%',
                  );
                  final ramCard = _GaugeCard(
                    title: 'RAM',
                    value: ramPct,
                    history: mon.ramHistory,
                    color: _ramColor(ramPct),
                    detail: '${mon.ramUsedMb.toStringAsFixed(0)} / ${mon.ramTotalMb.toStringAsFixed(0)} MB',
                  );
                  if (box.maxWidth > 500) {
                    return Row(children: [
                      Expanded(child: cpuCard),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(child: ramCard),
                    ]);
                  }
                  return Column(children: [
                    cpuCard,
                    const SizedBox(height: AppSpacing.md),
                    ramCard,
                  ]);
                }),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.md)),

            // Disk
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pageH),
                child: _DiskCard(
                  usedGb: mon.diskUsedGb,
                  totalGb: mon.diskTotalGb,
                  pct: diskPct,
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.md)),

            // Network
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pageH),
                child: _NetworkCard(
                  rxBps: mon.rxBytesPerSec,
                  txBps: mon.txBytesPerSec,
                  rxHistory: mon.rxHistory,
                  txHistory: mon.txHistory,
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.md)),

            // CPU History (full width chart)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pageH),
                child: _HistoryCard(
                  title: 'CPU History',
                  subtitle: '60s window',
                  data: mon.cpuHistory,
                  maxValue: 100,
                  color: _cpuColor(mon.cpu),
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.md)),

            // RAM History
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pageH),
                child: _HistoryCard(
                  title: 'Memory History',
                  subtitle: '60s window',
                  data: mon.ramHistory,
                  maxValue: 100,
                  color: _ramColor(ramPct),
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.huge)),
          ],
        ),
      ),
    );
  }

  static Color _cpuColor(double v) {
    if (v < 50) return AppColors.accentCyan;
    if (v < 80) return AppColors.warning;
    return AppColors.danger;
  }

  static Color _ramColor(double v) {
    if (v < 60) return const Color(0xFF8B5CF6);
    if (v < 85) return AppColors.warning;
    return AppColors.danger;
  }
}

// ─────────────────────────── Gauge Card ─────────────────────────────
class _GaugeCard extends StatelessWidget {
  final String title;
  final double value;
  final List<double> history;
  final Color color;
  final String detail;

  const _GaugeCard({
    required this.title,
    required this.value,
    required this.history,
    required this.color,
    required this.detail,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: context.colors.card,
        borderRadius: BorderRadius.circular(AppSpacing.rLg),
        border: Border.all(color: context.colors.border),
      ),
      child: Column(
        children: [
          Text(title, style: TextStyle(
            color: context.colors.textT, fontSize: 16,
            fontWeight: FontWeight.w700, letterSpacing: 1.5,
          )),
          const SizedBox(height: AppSpacing.md),
          GaugeWidget(value: value, size: 100, label: title),
          const SizedBox(height: AppSpacing.sm),
          Text(detail, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            height: 40,
            child: LineChartWidget(
              data: history, maxValue: 100, color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────── Disk Card ──────────────────────────────
class _DiskCard extends StatelessWidget {
  final double usedGb;
  final double totalGb;
  final double pct;
  const _DiskCard({required this.usedGb, required this.totalGb, required this.pct});

  @override
  Widget build(BuildContext context) {
    final color = pct < 70 ? AppColors.accentCyan
        : pct < 90 ? AppColors.warning : AppColors.danger;
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
              Text('DISK', style: TextStyle(
                color: context.colors.textT, fontSize: 16,
                fontWeight: FontWeight.w700, letterSpacing: 1.5,
              )),
              const Spacer(),
              Text('${pct.toStringAsFixed(0)}%',
                  style: TextStyle(
                    color: color, fontSize: 20, fontWeight: FontWeight.w700,
                  )),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (pct / 100).clamp(0, 1),
              minHeight: 10,
              backgroundColor: context.colors.cardEl,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '${usedGb.toStringAsFixed(1)} GB used of ${totalGb.toStringAsFixed(1)} GB',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────── Network Card ───────────────────────────
class _NetworkCard extends StatelessWidget {
  final double rxBps;
  final double txBps;
  final List<double> rxHistory;
  final List<double> txHistory;
  const _NetworkCard({
    required this.rxBps, required this.txBps,
    required this.rxHistory, required this.txHistory,
  });

  @override
  Widget build(BuildContext context) {
    final maxRx = rxHistory.isEmpty ? 1024.0
        : (rxHistory.reduce((a, b) => a > b ? a : b) * 1.3).clamp(1024, double.infinity);
    final maxTx = txHistory.isEmpty ? 1024.0
        : (txHistory.reduce((a, b) => a > b ? a : b) * 1.3).clamp(1024, double.infinity);

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
              Text('NETWORK', style: TextStyle(
                color: context.colors.textT, fontSize: 16,
                fontWeight: FontWeight.w700, letterSpacing: 1.5,
              )),
              const Spacer(),
              _Badge('RX', _fmt(rxBps), AppColors.accentGreen),
              const SizedBox(width: AppSpacing.sm),
              _Badge('TX', _fmt(txBps), AppColors.accentCyan),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          LayoutBuilder(builder: (context, box) {
            final dl = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Download', style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 4),
                SizedBox(
                  height: 50,
                  child: LineChartWidget(
                    data: rxHistory, maxValue: maxRx.toDouble(),
                    color: AppColors.accentGreen,
                  ),
                ),
              ],
            );
            final ul = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Upload', style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 4),
                SizedBox(
                  height: 50,
                  child: LineChartWidget(
                    data: txHistory, maxValue: maxTx.toDouble(),
                    color: AppColors.accentCyan,
                  ),
                ),
              ],
            );
            if (box.maxWidth > 400) {
              return Row(children: [
                Expanded(child: dl),
                const SizedBox(width: AppSpacing.lg),
                Expanded(child: ul),
              ]);
            }
            return Column(children: [
              dl,
              const SizedBox(height: AppSpacing.md),
              ul,
            ]);
          }),
        ],
      ),
    );
  }

  String _fmt(double bps) {
    if (bps >= 1024 * 1024) return '${(bps / (1024 * 1024)).toStringAsFixed(1)} MB/s';
    if (bps >= 1024) return '${(bps / 1024).toStringAsFixed(1)} KB/s';
    return '${bps.toStringAsFixed(0)} B/s';
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _Badge(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppSpacing.rSm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: TextStyle(
              color: color, fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(width: 4),
          Text(value, style: TextStyle(
              color: context.colors.textP, fontSize: 16)),
        ],
      ),
    );
  }
}

// ─────────────────────────── History Card ────────────────────────────
class _HistoryCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<double> data;
  final double maxValue;
  final Color color;
  const _HistoryCard({
    required this.title, required this.subtitle,
    required this.data, required this.maxValue, required this.color,
  });

  @override
  Widget build(BuildContext context) {
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
              Text(title, style: Theme.of(context).textTheme.titleSmall),
              const Spacer(),
              Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            height: 80,
            child: LineChartWidget(data: data, maxValue: maxValue, color: color),
          ),
        ],
      ),
    );
  }
}
