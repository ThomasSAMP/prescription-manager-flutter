import 'package:flutter/material.dart';

class MedicamentSkeletonItem extends StatelessWidget {
  const MedicamentSkeletonItem({super.key});

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
            // Icon placeholder avec cercle
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.grey.withOpacity(0.2)),
              ),
              child: const Center(
                child: Icon(Icons.medication_outlined, color: Colors.white, size: 24),
              ),
            ),
            const SizedBox(width: 16),
            // Content placeholder
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title placeholder - pour le nom du médicament
                  Container(
                    width: double.infinity,
                    height: 16,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Subtitle placeholder - pour le dosage
                  Container(
                    width: 150,
                    height: 14,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 4),
                  // Date placeholder - pour la date d'expiration
                  Row(
                    children: [
                      Container(
                        width: 16,
                        height: 16,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Container(
                        width: 120,
                        height: 14,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Chevron placeholder
            Container(
              width: 24,
              height: 24,
              decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
              child: const Center(child: Icon(Icons.chevron_right, color: Colors.white, size: 20)),
            ),
          ],
        ),
      ),
    );
  }
}
