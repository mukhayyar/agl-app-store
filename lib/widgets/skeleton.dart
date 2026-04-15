import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// A rectangular shimmering placeholder. Use it as a direct building
/// block for skeleton screens (wrap with ClipRRect for rounded corners).
class SkeletonBox extends StatefulWidget {
  final double? width;
  final double? height;
  final BorderRadiusGeometry borderRadius;

  const SkeletonBox({
    super.key,
    this.width,
    this.height,
    this.borderRadius = const BorderRadius.all(Radius.circular(8)),
  });

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = context.colors.cardEl;
    final highlight = context.colors.border;
    return ClipRRect(
      borderRadius: widget.borderRadius,
      child: AnimatedBuilder(
        animation: _ctl,
        builder: (_, __) {
          return SizedBox(
            width: widget.width,
            height: widget.height,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment(-1 + _ctl.value * 2, 0),
                  end: Alignment(1 + _ctl.value * 2, 0),
                  colors: [base, highlight, base],
                  stops: const [0.25, 0.5, 0.75],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Skeleton row mirroring the shape of `_AppTile` — icon + name +
/// summary + action area. Use inside a ListView while a source is
/// loading.
class SkeletonAppTile extends StatelessWidget {
  const SkeletonAppTile({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.colors.card,
        borderRadius: BorderRadius.circular(AppSpacing.rLg),
        border: Border.all(color: context.colors.border),
      ),
      child: Row(
        children: [
          // Accent strip placeholder
          const SizedBox(width: 4, height: 72),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                children: [
                  const SkeletonBox(
                    width: 52,
                    height: 52,
                    borderRadius:
                        BorderRadius.all(Radius.circular(AppSpacing.rMd)),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SkeletonBox(
                          width: MediaQuery.of(context).size.width * 0.35,
                          height: 14,
                        ),
                        const SizedBox(height: 8),
                        SkeletonBox(
                          width: MediaQuery.of(context).size.width * 0.5,
                          height: 11,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  const SkeletonBox(
                    width: 72,
                    height: 32,
                    borderRadius:
                        BorderRadius.all(Radius.circular(AppSpacing.rFull)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Skeleton card mirroring the shape of the featured-cards row. Width
/// should match the real card width on the same screen for a seamless
/// swap-in on load completion.
class SkeletonFeaturedCard extends StatelessWidget {
  final double width;
  final double height;
  const SkeletonFeaturedCard({
    super.key,
    this.width = 300,
    this.height = 220,
  });

  @override
  Widget build(BuildContext context) {
    return SkeletonBox(
      width: width,
      height: height,
      borderRadius: const BorderRadius.all(Radius.circular(AppSpacing.rXl)),
    );
  }
}
