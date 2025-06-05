import 'package:flutter/material.dart';
import 'package:prescription_manager/theme/theme_extensions.dart';
import 'package:shimmer/shimmer.dart';

class ShimmerLoading extends StatelessWidget {
  final Widget child;
  final bool isLoading;
  final Color? baseColor;
  final Color? highlightColor;
  final Duration period;
  final ShimmerDirection direction;

  const ShimmerLoading({
    super.key,
    required this.child,
    required this.isLoading,
    this.baseColor,
    this.highlightColor,
    this.period = const Duration(milliseconds: 1500),
    this.direction = ShimmerDirection.ltr,
  });

  @override
  Widget build(BuildContext context) {
    if (!isLoading) {
      return child;
    }

    final theme = Theme.of(context);
    final baseColorValue = baseColor ?? theme.shimmerBaseColor;
    final highlightColorValue = highlightColor ?? theme.shimmerHighlightColor;

    return Shimmer.fromColors(
      baseColor: baseColorValue,
      highlightColor: highlightColorValue,
      period: period,
      direction: direction,
      child: child,
    );
  }
}
