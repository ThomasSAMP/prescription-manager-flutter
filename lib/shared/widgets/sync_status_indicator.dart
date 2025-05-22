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
    String message;

    switch (status) {
      case SyncStatus.synced:
        icon = Icons.cloud_done;
        message = 'Synchronisé';
        break;
      case SyncStatus.syncing:
        icon = Icons.sync;
        message = 'Synchronisation...';
        break;
      case SyncStatus.pendingSync:
        icon = Icons.cloud_queue;
        message = 'En attente de synchronisation';
        break;
      case SyncStatus.error:
        icon = Icons.cloud_off;
        message = 'Erreur de synchronisation';
        break;
      case SyncStatus.offline:
        icon = Icons.wifi_off;
        message = 'Hors ligne';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(4)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (status == SyncStatus.syncing)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white70),
              ),
            )
          else
            Icon(icon, size: 16, color: Colors.white70),
          const SizedBox(width: 8),
          Text(message, style: const TextStyle(fontSize: 12, color: Colors.white70)),
          if (status == SyncStatus.error && onRetry != null) ...[
            const SizedBox(width: 8),
            InkWell(
              onTap: onRetry,
              child: const Icon(Icons.refresh, size: 16, color: Colors.white70),
            ),
          ],
        ],
      ),
    );
  }
}
