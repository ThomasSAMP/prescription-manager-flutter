import 'package:flutter/material.dart';

class ShimmerPlaceholder extends StatelessWidget {
  final double width;
  final double height;
  final double borderRadius;
  final BoxShape shape;

  const ShimmerPlaceholder({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius = 4.0,
    this.shape = BoxShape.rectangle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: shape == BoxShape.rectangle ? BorderRadius.circular(borderRadius) : null,
        shape: shape,
      ),
    );
  }
}
