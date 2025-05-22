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
  late Animation<double> _animation;
  bool _isVisible = false;
  SyncNotification? _currentNotification;

  @override
  void initState() {
    super.initState();

    // Initialiser le contrôleur d'animation
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _animation = CurvedAnimation(parent: _animationController, curve: Curves.easeInOut);

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

  IconData _getIcon(SyncStatus status) {
    switch (status) {
      case SyncStatus.synced:
        return Icons.cloud_done;
      case SyncStatus.syncing:
        return Icons.sync;
      case SyncStatus.pendingSync:
        return Icons.cloud_queue;
      case SyncStatus.error:
        return Icons.cloud_off;
      case SyncStatus.offline:
        return Icons.wifi_off;
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
              animation: _animation,
              builder: (context, child) {
                return Transform.translate(
                  offset: Offset(0, -48 * (1 - _animation.value)),
                  child: Opacity(opacity: _animation.value, child: child),
                );
              },
              child: Material(
                color: _getBackgroundColor(_currentNotification!.status),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (_currentNotification!.status == SyncStatus.syncing)
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        else
                          Icon(
                            _getIcon(_currentNotification!.status),
                            color: Colors.white,
                            size: 16,
                          ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            _currentNotification!.message,
                            style: const TextStyle(color: Colors.white),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
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
