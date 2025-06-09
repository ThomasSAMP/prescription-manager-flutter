import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/injection.dart';
import '../../core/services/smart_sync_service.dart';
import '../providers/sync_status_provider.dart';
import 'sync_status_indicator.dart';

class SmartSyncIndicator extends ConsumerStatefulWidget {
  const SmartSyncIndicator({super.key});

  @override
  ConsumerState<SmartSyncIndicator> createState() => _SmartSyncIndicatorState();
}

class _SmartSyncIndicatorState extends ConsumerState<SmartSyncIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(duration: const Duration(seconds: 2), vsync: this);
    _pulseAnimation = Tween<double>(
      begin: 0.5,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final syncState = ref.watch(syncStatusProvider);
    final smartSyncService = getIt<SmartSyncService>();
    final syncInfo = smartSyncService.getSyncInfo();

    // Gérer l'animation de pulsation
    if (syncState.status == SyncStatus.syncing || syncInfo.isRetrying) {
      _pulseController.repeat(reverse: true);
    } else {
      _pulseController.stop();
    }

    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: _getBackgroundColor(
              syncState.status,
            ).withOpacity(syncState.status == SyncStatus.syncing ? _pulseAnimation.value : 1.0),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              if (syncState.status == SyncStatus.error)
                BoxShadow(color: Colors.red.withOpacity(0.3), blurRadius: 8, spreadRadius: 2),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildStatusIcon(syncState.status, syncInfo),
              const SizedBox(width: 8),
              _buildStatusText(syncState, syncInfo),
              if (syncState.status == SyncStatus.error) ...[
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: smartSyncService.forceSyncNow,
                  child: const Icon(Icons.refresh, size: 16, color: Colors.white),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatusIcon(SyncStatus status, SyncInfo syncInfo) {
    if (status == SyncStatus.syncing || syncInfo.isRetrying) {
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
    switch (status) {
      case SyncStatus.synced:
        icon = Icons.cloud_done;
        break;
      case SyncStatus.pendingSync:
        icon = Icons.cloud_queue;
        break;
      case SyncStatus.error:
        icon = Icons.error_outline;
        break;
      case SyncStatus.offline:
        icon = Icons.wifi_off;
        break;
      default:
        icon = Icons.cloud;
    }

    return Icon(icon, size: 16, color: Colors.white);
  }

  Widget _buildStatusText(SyncStatusState syncState, SyncInfo syncInfo) {
    String text;

    if (syncInfo.isRetrying) {
      text = 'Nouvelle tentative... (${syncInfo.retryAttempts}/${syncInfo.maxRetryAttempts})';
    } else if (syncState.status == SyncStatus.syncing) {
      text = 'Synchronisation...';
    } else if (syncState.status == SyncStatus.pendingSync) {
      text = '${syncInfo.pendingOperationsCount} en attente';
    } else if (syncState.status == SyncStatus.error) {
      text = 'Erreur de sync';
    } else if (syncState.status == SyncStatus.offline) {
      text = 'Hors ligne';
    } else {
      text = 'Synchronisé';
    }

    return Text(
      text,
      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
    );
  }

  Color _getBackgroundColor(SyncStatus status) {
    switch (status) {
      case SyncStatus.synced:
        return Colors.green;
      case SyncStatus.syncing:
        return Colors.blue;
      case SyncStatus.pendingSync:
        return Colors.orange;
      case SyncStatus.error:
        return Colors.red;
      case SyncStatus.offline:
        return Colors.grey;
    }
  }
}
