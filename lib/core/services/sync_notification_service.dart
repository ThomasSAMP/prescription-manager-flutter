import 'dart:async';

import 'package:injectable/injectable.dart';

import '../../shared/widgets/sync_status_indicator.dart';
import '../utils/logger.dart';

@lazySingleton
class SyncNotificationService {
  // Contrôleur pour les notifications
  final StreamController<SyncNotification> _notificationController =
      StreamController<SyncNotification>.broadcast();

  // Stream exposé pour que les autres parties de l'application puissent écouter les notifications
  Stream<SyncNotification> get notifications => _notificationController.stream;

  // Notification actuelle
  SyncNotification? _currentNotification;
  SyncNotification? get currentNotification => _currentNotification;

  // Minuteur pour masquer automatiquement les notifications
  Timer? _autoHideTimer;

  // Afficher une notification de synchronisation
  void showSyncing() {
    _cancelAutoHideTimer();
    _currentNotification = SyncNotification(
      status: SyncStatus.syncing,
      message: 'Synchronisation en cours...',
      timestamp: DateTime.now(),
    );
    _notificationController.add(_currentNotification!);
    AppLogger.debug('SyncNotificationService: Showing syncing notification');
  }

  // Afficher une notification de synchronisation réussie
  void showSynced() {
    _cancelAutoHideTimer();
    _currentNotification = SyncNotification(
      status: SyncStatus.synced,
      message: 'Synchronisation réussie',
      timestamp: DateTime.now(),
    );
    _notificationController.add(_currentNotification!);
    AppLogger.debug('SyncNotificationService: Showing synced notification');

    // Masquer automatiquement après 3 secondes
    _autoHideTimer = Timer(const Duration(seconds: 3), hide);
  }

  // Afficher une notification d'erreur
  void showError(String errorMessage) {
    _cancelAutoHideTimer();
    _currentNotification = SyncNotification(
      status: SyncStatus.error,
      message: 'Erreur: $errorMessage',
      timestamp: DateTime.now(),
    );
    _notificationController.add(_currentNotification!);
    AppLogger.debug('SyncNotificationService: Showing error notification');
  }

  // Afficher une notification de mode hors ligne
  void showOffline() {
    _cancelAutoHideTimer();
    _currentNotification = SyncNotification(
      status: SyncStatus.offline,
      message: 'Mode hors ligne',
      timestamp: DateTime.now(),
    );
    _notificationController.add(_currentNotification!);
    AppLogger.debug('SyncNotificationService: Showing offline notification');

    // Pas de timer pour masquer automatiquement cette notification
    // Elle doit rester visible tant que l'appareil est hors ligne
  }

  // Afficher une notification de synchronisation en attente
  void showPendingSync(int count) {
    _cancelAutoHideTimer();
    _currentNotification = SyncNotification(
      status: SyncStatus.pendingSync,
      message: '$count modification${count > 1 ? 's' : ''} en attente',
      timestamp: DateTime.now(),
    );
    _notificationController.add(_currentNotification!);
    AppLogger.debug('SyncNotificationService: Showing pending sync notification');
  }

  // Masquer la notification actuelle
  void hide() {
    _cancelAutoHideTimer();
    if (_currentNotification != null) {
      _currentNotification = null;
      _notificationController.add(SyncNotification.hidden());
      AppLogger.debug('SyncNotificationService: Hiding notification');
    }
  }

  // Annuler le minuteur d'auto-masquage
  void _cancelAutoHideTimer() {
    _autoHideTimer?.cancel();
    _autoHideTimer = null;
  }

  // Nettoyer les ressources lors de la destruction du service
  void dispose() {
    _cancelAutoHideTimer();
    _notificationController.close();
  }
}

class SyncNotification {
  final SyncStatus status;
  final String message;
  final DateTime timestamp;
  final bool isVisible;

  SyncNotification({
    required this.status,
    required this.message,
    required this.timestamp,
    this.isVisible = true,
  });

  factory SyncNotification.hidden() {
    return SyncNotification(
      status: SyncStatus.synced,
      message: '',
      timestamp: DateTime.now(),
      isVisible: false,
    );
  }
}
