import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/unified_sync_service.dart';
import '../providers/sync_status_provider.dart';

enum SyncStatus { synced, syncing, pendingSync, error, offline }

class SyncStatusIndicator extends ConsumerWidget {
  final SyncStatus status;
  final String? errorMessage;
  final VoidCallback? onRetry;

  const SyncStatusIndicator({super.key, required this.status, this.errorMessage, this.onRetry});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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

// Widget pour afficher les informations de sync
class UnifiedSyncIndicator extends ConsumerWidget {
  const UnifiedSyncIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final syncInfoAsync = ref.watch(unifiedSyncInfoProvider);

    return syncInfoAsync.when(
      data: (syncInfo) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: _getBackgroundColor(syncInfo.status),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildStatusIcon(syncInfo),
              const SizedBox(width: 8),
              Text(
                _getStatusMessage(syncInfo),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  Widget _buildStatusIcon(SyncInfo syncInfo) {
    if (syncInfo.status == UnifiedSyncStatus.syncing || syncInfo.isRetrying) {
      return const SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
        ),
      );
    }

    IconData icon;
    switch (syncInfo.status) {
      case UnifiedSyncStatus.synced:
        icon = Icons.cloud_done;
        break;
      case UnifiedSyncStatus.pendingOperations:
        icon = Icons.cloud_queue;
        break;
      case UnifiedSyncStatus.error:
        icon = Icons.error_outline;
        break;
      case UnifiedSyncStatus.offline:
        icon = Icons.wifi_off;
        break;
      default:
        icon = Icons.cloud;
    }

    return Icon(icon, size: 16, color: Colors.white);
  }

  String _getStatusMessage(SyncInfo syncInfo) {
    if (syncInfo.isRetrying) {
      return 'Nouvelle tentative... (${syncInfo.retryAttempts}/${syncInfo.maxRetryAttempts})';
    }

    switch (syncInfo.status) {
      case UnifiedSyncStatus.syncing:
        return 'Synchronisation...';
      case UnifiedSyncStatus.synced:
        return 'Synchronisé';
      case UnifiedSyncStatus.pendingOperations:
        return '${syncInfo.pendingOperationsCount} en attente';
      case UnifiedSyncStatus.error:
        return 'Erreur de sync';
      case UnifiedSyncStatus.offline:
        return 'Hors ligne';
      default:
        return '';
    }
  }

  Color _getBackgroundColor(UnifiedSyncStatus status) {
    switch (status) {
      case UnifiedSyncStatus.synced:
        return Colors.green;
      case UnifiedSyncStatus.syncing:
        return Colors.blue;
      case UnifiedSyncStatus.pendingOperations:
        return Colors.orange;
      case UnifiedSyncStatus.error:
        return Colors.red;
      case UnifiedSyncStatus.offline:
        return Colors.grey;
      default:
        return Colors.blue;
    }
  }
}
