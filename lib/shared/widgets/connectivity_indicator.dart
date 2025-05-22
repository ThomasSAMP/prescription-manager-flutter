import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/sync_status_provider.dart';
import 'sync_status_indicator.dart';

class ConnectivityIndicator extends ConsumerStatefulWidget {
  const ConnectivityIndicator({super.key});

  @override
  ConsumerState<ConnectivityIndicator> createState() => _ConnectivityIndicatorState();
}

class _ConnectivityIndicatorState extends ConsumerState<ConnectivityIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _animation;
  bool _isVisible = false;

  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _animation = CurvedAnimation(parent: _animationController, curve: Curves.easeInOut);

    // Vérifier l'état initial
    _updateVisibility(true); // Toujours visible initialement
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _updateVisibility(bool shouldBeVisible) {
    if (_isVisible != shouldBeVisible) {
      setState(() {
        _isVisible = shouldBeVisible;
      });

      if (_isVisible) {
        _animationController.forward();
      } else {
        _animationController.reverse();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final syncState = ref.watch(syncStatusProvider);

    // Déterminer si nous devons afficher l'indicateur
    final shouldShow = syncState.status != SyncStatus.synced;
    _updateVisibility(shouldShow);

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Visibility(
          visible: _animation.value > 0,
          child: Opacity(
            opacity: _animation.value,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
              color: _getBackgroundColor(syncState.status),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SyncStatusIndicator(
                    status: syncState.status,
                    errorMessage: syncState.errorMessage,
                    onRetry:
                        syncState.status == SyncStatus.error
                            ? () => ref.read(syncStatusProvider.notifier).setSyncing()
                            : null,
                  ),
                  if (syncState.pendingOperationsCount > 0) ...[
                    const SizedBox(width: 8),
                    Text(
                      '${syncState.pendingOperationsCount} modification${syncState.pendingOperationsCount > 1 ? 's' : ''} en attente',
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
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
}
