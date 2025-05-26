import 'package:flutter/material.dart';

import '../../models/medicament_model.dart';
import '../../models/ordonnance_model.dart';

class OrdonnanceListItem extends StatelessWidget {
  final OrdonnanceModel ordonnance;
  final int medicamentCount;
  final ExpirationStatus? expirationStatus;
  final VoidCallback onTap;
  final bool isSynced;

  const OrdonnanceListItem({
    super.key,
    required this.ordonnance,
    required this.medicamentCount,
    this.expirationStatus,
    required this.onTap,
    required this.isSynced,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      // Ajouter une bordure colorée selon la criticité
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
          border:
              expirationStatus != null && expirationStatus!.needsAttention
                  ? Border(left: BorderSide(color: expirationStatus!.getColor(), width: 4))
                  : null,
        ),
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                _buildPatientAvatar(),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              ordonnance.patientName,
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                          ),
                          if (!isSynced)
                            const Icon(Icons.cloud_queue, size: 16, color: Colors.orange),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Médicaments: $medicamentCount',
                        style: TextStyle(color: Theme.of(context).textTheme.bodySmall?.color),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Créée le ${_formatDate(ordonnance.createdAt)}',
                        style: TextStyle(
                          color: Theme.of(context).textTheme.bodySmall?.color,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                if (expirationStatus != null && expirationStatus!.needsAttention)
                  _buildExpirationIndicator(expirationStatus!),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPatientAvatar() {
    // Créer un avatar avec les initiales du patient
    final initials = ordonnance.patientName
        .split(' ')
        .map((name) => name.isNotEmpty ? name[0].toUpperCase() : '')
        .join('');

    return CircleAvatar(
      radius: 24,
      backgroundColor: Colors.blue,
      child: Text(
        initials,
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
      ),
    );
  }

  Widget _buildExpirationIndicator(ExpirationStatus status) {
    return Tooltip(
      message: _getExpirationMessage(status),
      child: Icon(status.getIcon(), color: status.getColor(), size: 24),
    );
  }

  String _getExpirationMessage(ExpirationStatus status) {
    switch (status) {
      case ExpirationStatus.warning:
        return 'Un médicament expire bientôt (< 30 jours)';
      case ExpirationStatus.critical:
        return 'Un médicament expire très bientôt (< 14 jours)';
      case ExpirationStatus.expired:
        return 'Un médicament est expiré !';
      default:
        return '';
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }
}
