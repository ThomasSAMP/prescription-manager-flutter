import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/medicament_model.dart';

class MedicamentListItem extends StatelessWidget {
  final MedicamentModel medicament;
  final VoidCallback onTap;

  const MedicamentListItem({super.key, required this.medicament, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final expirationStatus = medicament.getExpirationStatus();
    final dateFormat = DateFormat('dd/MM/yyyy');

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              _buildMedicamentIcon(expirationStatus),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      medicament.name,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    if (medicament.dosage != null && medicament.dosage!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Dosage: ${medicament.dosage}',
                        style: TextStyle(color: Theme.of(context).textTheme.bodySmall?.color),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          expirationStatus == ExpirationStatus.expired
                              ? 'Expiré le: ${dateFormat.format(medicament.expirationDate)}'
                              : 'Expire le: ${dateFormat.format(medicament.expirationDate)}',
                          style: TextStyle(
                            color:
                                expirationStatus.needsAttention
                                    ? expirationStatus.getColor()
                                    : Theme.of(context).textTheme.bodySmall?.color,
                            fontWeight:
                                expirationStatus.needsAttention
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                          ),
                        ),
                        if (expirationStatus.needsAttention) ...[
                          const SizedBox(width: 4),
                          Icon(
                            expirationStatus.getIcon(),
                            color: expirationStatus.getColor(),
                            size: 16,
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMedicamentIcon(ExpirationStatus status) {
    return CircleAvatar(
      radius: 24,
      backgroundColor:
          status.needsAttention ? status.getColor().withOpacity(0.2) : Colors.blue.withOpacity(0.2),
      child: Icon(
        Icons.medication_outlined,
        color: status.needsAttention ? status.getColor() : Colors.blue,
      ),
    );
  }
}
