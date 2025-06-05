import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/injection.dart';
import '../../core/services/sync_notification_service.dart';
import 'sync_status_indicator.dart';

class SyncNotificationOverlay extends ConsumerStatefulWidget {
  final Widget child;

  const SyncNotificationOverlay({super.key, required this.child});

  @override
  ConsumerState<SyncNotificationOverlay> createState() => _SyncNotificationOverlayState();
}

class _SyncNotificationOverlayState extends ConsumerState<SyncNotificationOverlay>
    with SingleTickerProviderStateMixin {
  final SyncNotificationService _notificationService = getIt<SyncNotificationService>();
  late AnimationController _animationController;
  late Animation<double> _slideAnimation;
  late Animation<double> _opacityAnimation;

  bool _isVisible = false;
  SyncNotification? _currentNotification;

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

    // Écouter les notifications
    _notificationService.notifications.listen(_handleNotification);
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _handleNotification(SyncNotification notification) {
    if (!mounted) return;

    setState(() {
      _currentNotification = notification;
      _isVisible = notification.isVisible;
    });

    if (_isVisible) {
      _animationController.forward();
    } else {
      _animationController.reverse();
    }
  }

  Color _getBackgroundColor(SyncStatus status) {
    switch (status) {
      case SyncStatus.synced:
        return Colors.green.shade700;
      case SyncStatus.syncing:
        return Colors.blue.shade700;
      case SyncStatus.pendingSync:
        return Colors.orange.shade700;
      case SyncStatus.error:
        return Colors.red.shade700;
      case SyncStatus.offline:
        return Colors.grey.shade700;
    }
  }

  Widget _buildNotificationIcon(SyncStatus status) {
    switch (status) {
      case SyncStatus.syncing:
        return const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
          ),
        );
      case SyncStatus.synced:
        return const Icon(Icons.cloud_done, color: Colors.white, size: 16);
      case SyncStatus.pendingSync:
        return const Icon(Icons.cloud_queue, color: Colors.white, size: 16);
      case SyncStatus.error:
        return const Icon(Icons.cloud_off, color: Colors.white, size: 16);
      case SyncStatus.offline:
        return const Icon(Icons.wifi_off, color: Colors.white, size: 16);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_currentNotification != null && _isVisible)
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
                color: _getBackgroundColor(_currentNotification!.status),
                elevation: 4,
                child: SafeArea(
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildNotificationIcon(_currentNotification!.status),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            _currentNotification!.message,
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
                        if (_currentNotification!.status == SyncStatus.error) ...[
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: _notificationService.hide,
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
