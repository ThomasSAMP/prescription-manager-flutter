import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum SyncStatus { synced, syncing, pendingSync, error, offline }

class SyncStatusIndicator extends ConsumerWidget {
  final SyncStatus status;
  final String? errorMessage;
  final VoidCallback? onRetry;

  const SyncStatusIndicator({super.key, required this.status, this.errorMessage, this.onRetry});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    // Déterminer l'apparence en fonction du statut
    IconData icon;
    Color color;
    String message;

    switch (status) {
      case SyncStatus.synced:
        icon = Icons.cloud_done;
        color = Colors.green;
        message = 'Synchronisé';
        break;
      case SyncStatus.syncing:
        icon = Icons.sync;
        color = Colors.blue;
        message = 'Synchronisation...';
        break;
      case SyncStatus.pendingSync:
        icon = Icons.cloud_queue;
        color = Colors.orange;
        message = 'En attente de synchronisation';
        break;
      case SyncStatus.error:
        icon = Icons.cloud_off;
        color = Colors.red;
        message = 'Erreur de synchronisation';
        break;
      case SyncStatus.offline:
        icon = Icons.wifi_off;
        color = Colors.grey;
        message = 'Hors ligne';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (status == SyncStatus.syncing)
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            )
          else
            Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Text(message, style: TextStyle(fontSize: 12, color: color)),
          if (status == SyncStatus.error && onRetry != null) ...[
            const SizedBox(width: 8),
            InkWell(onTap: onRetry, child: Icon(Icons.refresh, size: 16, color: color)),
          ],
        ],
      ),
    );
  }
}
