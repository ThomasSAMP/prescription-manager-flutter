import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/unified_sync_service.dart';
import '../providers/sync_status_provider.dart';

class SyncNotificationOverlay extends ConsumerStatefulWidget {
  final Widget child;

  const SyncNotificationOverlay({super.key, required this.child});

  @override
  ConsumerState<SyncNotificationOverlay> createState() => _SyncNotificationOverlayState();
}

class _SyncNotificationOverlayState extends ConsumerState<SyncNotificationOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _slideAnimation;
  late Animation<double> _opacityAnimation;

  bool _isVisible = false;
  SyncInfo? _currentSyncInfo;

  @override
  void initState() {
    super.initState();

    // Initialiser les contrôleurs d'animation
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _slideAnimation = Tween<double>(
      begin: -1.0,
      end: 0.0,
    ).animate(CurvedAnimation(parent: _animationController, curve: Curves.easeInOut));

    _opacityAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _animationController, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _handleSyncInfo(SyncInfo syncInfo) {
    if (!mounted) return;

    setState(() {
      _currentSyncInfo = syncInfo;
      _isVisible = _shouldShowNotification(syncInfo);
    });

    if (_isVisible) {
      _animationController.forward();
    } else {
      _animationController.reverse();
    }
  }

  bool _shouldShowNotification(SyncInfo syncInfo) {
    switch (syncInfo.status) {
      case UnifiedSyncStatus.syncing:
      case UnifiedSyncStatus.error:
      case UnifiedSyncStatus.offline:
      case UnifiedSyncStatus.pendingOperations:
        return true;
      case UnifiedSyncStatus.synced:
        return false; // Masquer après un délai
      default:
        return false;
    }
  }

  Color _getBackgroundColor(UnifiedSyncStatus status) {
    switch (status) {
      case UnifiedSyncStatus.synced:
        return Colors.green.shade700;
      case UnifiedSyncStatus.syncing:
        return Colors.blue.shade700;
      case UnifiedSyncStatus.pendingOperations:
        return Colors.orange.shade700;
      case UnifiedSyncStatus.error:
        return Colors.red.shade700;
      case UnifiedSyncStatus.offline:
        return Colors.grey.shade700;
      default:
        return Colors.blue.shade700;
    }
  }

  Widget _buildNotificationIcon(UnifiedSyncStatus status) {
    switch (status) {
      case UnifiedSyncStatus.syncing:
        return const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
          ),
        );
      case UnifiedSyncStatus.synced:
        return const Icon(Icons.cloud_done, color: Colors.white, size: 16);
      case UnifiedSyncStatus.pendingOperations:
        return const Icon(Icons.cloud_queue, color: Colors.white, size: 16);
      case UnifiedSyncStatus.error:
        return const Icon(Icons.cloud_off, color: Colors.white, size: 16);
      case UnifiedSyncStatus.offline:
        return const Icon(Icons.wifi_off, color: Colors.white, size: 16);
      default:
        return const Icon(Icons.cloud, color: Colors.white, size: 16);
    }
  }

  String _getNotificationMessage(SyncInfo syncInfo) {
    switch (syncInfo.status) {
      case UnifiedSyncStatus.syncing:
        return 'Synchronisation en cours...';
      case UnifiedSyncStatus.synced:
        return 'Synchronisation réussie';
      case UnifiedSyncStatus.pendingOperations:
        return '${syncInfo.pendingOperationsCount} modification${syncInfo.pendingOperationsCount > 1 ? 's' : ''} en attente';
      case UnifiedSyncStatus.error:
        return syncInfo.errorMessage ?? 'Erreur de synchronisation';
      case UnifiedSyncStatus.offline:
        return 'Mode hors ligne';
      case UnifiedSyncStatus.retrying:
        return 'Nouvelle tentative... (${syncInfo.retryAttempts}/${syncInfo.maxRetryAttempts})';
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    // Écouter les changements de sync info
    ref.listen<AsyncValue<SyncInfo>>(unifiedSyncInfoProvider, (previous, next) {
      next.whenData(_handleSyncInfo);
    });

    return Stack(
      children: [
        widget.child,
        if (_currentSyncInfo != null && _isVisible)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: AnimatedBuilder(
              animation: _animationController,
              builder: (context, child) {
                return Transform.translate(
                  offset: Offset(0, 48 * _slideAnimation.value),
                  child: Opacity(opacity: _opacityAnimation.value, child: child),
                );
              },
              child: Material(
                color: _getBackgroundColor(_currentSyncInfo!.status),
                elevation: 4,
                child: SafeArea(
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildNotificationIcon(_currentSyncInfo!.status),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            _getNotificationMessage(_currentSyncInfo!),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 2,
                          ),
                        ),
                        // Bouton de fermeture pour les erreurs
                        if (_currentSyncInfo!.status == UnifiedSyncStatus.error) ...[
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () {
                              setState(() {
                                _isVisible = false;
                              });
                              _animationController.reverse();
                            },
                            child: const Icon(Icons.close, color: Colors.white, size: 16),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
