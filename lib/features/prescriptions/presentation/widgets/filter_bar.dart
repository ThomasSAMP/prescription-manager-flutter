// lib/features/prescriptions/presentation/widgets/filter_bar.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/filter_options.dart';
import '../../providers/ordonnance_filter_provider.dart';
import '../../providers/ordonnance_provider.dart';

class FilterBar extends ConsumerWidget {
  const FilterBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedFilter = ref.watch(filterOptionProvider);
    final counts = ref.watch(ordonnanceCountsProvider);
    final isLoading = ref.watch(ordonnanceProvider).isLoading;

    return Column(
      children: [
        // Barre de filtrage
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child:
              isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : Row(
                    children:
                        FilterOption.values.map((option) {
                          final isSelected = option == selectedFilter;
                          final count = counts[option] ?? 0;

                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: FilterChip(
                              label: Text('${option.label} ($count)'),
                              selected: isSelected,
                              onSelected:
                                  isLoading
                                      ? null
                                      : (_) {
                                        ref.read(filterOptionProvider.notifier).setFilter(option);
                                      },
                              avatar: Icon(
                                option.icon,
                                color: isSelected ? Colors.white : option.color,
                                size: 16,
                              ),
                              backgroundColor: Colors.grey.shade200,
                              selectedColor: option.color,
                              labelStyle: TextStyle(
                                color: isSelected ? Colors.white : null,
                                fontWeight: isSelected ? FontWeight.bold : null,
                              ),
                            ),
                          );
                        }).toList(),
                  ),
        ),

        const Divider(),
      ],
    );
  }
}
