import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

/// Wraps fl_chart LineChart with automotive dark styling
class MetricLineChart extends StatelessWidget {
  final List<double> data;
  final String label;
  final Color color;
  final String unit;
  final double? maxY;

  const MetricLineChart({
    super.key,
    required this.data,
    required this.label,
    this.color = const Color(0xFF00D4FF),
    this.unit = '',
    this.maxY,
  });

  @override
  Widget build(BuildContext context) {
    final spots = <FlSpot>[];
    for (int i = 0; i < data.length; i++) {
      spots.add(FlSpot(i.toDouble(), data[i].clamp(0.0, double.infinity)));
    }

    final actualMax = data.isEmpty
        ? 100.0
        : (maxY ?? data.reduce((a, b) => a > b ? a : b).clamp(1.0, double.infinity) * 1.2);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 4),
          child: Text(
            label,
            style: const TextStyle(
              color: Color(0xFF888899),
              fontSize: 11,
              letterSpacing: 0.8,
            ),
          ),
        ),
        SizedBox(
          height: 80,
          child: LineChart(
            LineChartData(
              backgroundColor: Colors.transparent,
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                getDrawingHorizontalLine: (value) => FlLine(
                  color: const Color(0xFF1E1E2E),
                  strokeWidth: 1,
                ),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 36,
                    interval: actualMax / 2,
                    getTitlesWidget: (v, _) => Text(
                      v == 0 ? '' : '${v.toStringAsFixed(0)}$unit',
                      style: const TextStyle(
                        color: Color(0xFF444455),
                        fontSize: 9,
                      ),
                    ),
                  ),
                ),
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                bottomTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
              ),
              minX: 0,
              maxX: (data.length - 1).toDouble(),
              minY: 0,
              maxY: actualMax,
              lineBarsData: [
                LineChartBarData(
                  spots: spots,
                  isCurved: true,
                  curveSmoothness: 0.3,
                  color: color,
                  barWidth: 2,
                  dotData: const FlDotData(show: false),
                  belowBarData: BarAreaData(
                    show: true,
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        color.withOpacity(0.25),
                        color.withOpacity(0.0),
                      ],
                    ),
                  ),
                ),
              ],
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  getTooltipColor: (_) => const Color(0xFF1A1A2E),
                  getTooltipItems: (spots) => spots.map((s) => LineTooltipItem(
                    '${s.y.toStringAsFixed(1)}$unit',
                    TextStyle(color: color, fontSize: 10),
                  )).toList(),
                ),
              ),
            ),
            duration: const Duration(milliseconds: 200),
          ),
        ),
      ],
    );
  }
}
