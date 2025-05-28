import 'package:flutter/material.dart';

class FilterBarSkeleton extends StatelessWidget {
  const FilterBarSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Barre de filtrage skeleton
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: List.generate(
              4, // Nombre de filtres
              (index) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Container(
                  width: 100,
                  height: 32,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
          ),
        ),
        const Divider(),
      ],
    );
  }
}
