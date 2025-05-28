import 'package:flutter/material.dart';

class OrdonnanceSkeletonItem extends StatelessWidget {
  const OrdonnanceSkeletonItem({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 10),
      decoration: const BoxDecoration(
        border: Border(left: BorderSide(color: Colors.white, width: 4)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // Avatar placeholder avec forme circulaire
            Container(
              width: 48,
              height: 48,
              decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
            ),
            const SizedBox(width: 16),
            // Content placeholder
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title placeholder - plus large pour simuler un nom
                  Container(
                    width: double.infinity,
                    height: 18,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Subtitle placeholder - pour le nombre de médicaments
                  Container(
                    width: 120,
                    height: 14,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 4),
                  // Date placeholder - plus court pour la date
                  Container(
                    width: 100,
                    height: 12,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ],
              ),
            ),
            // Status icon placeholder
            Container(
              width: 24,
              height: 24,
              decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
            ),
          ],
        ),
      ),
    );
  }
}
