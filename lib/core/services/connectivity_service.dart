import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:injectable/injectable.dart';

import '../di/injection.dart';
import '../utils/logger.dart';
import 'sync_notification_service.dart';
import 'sync_service.dart';

enum ConnectionStatus { online, offline }

@lazySingleton
class ConnectivityService {
  // Instance de Connectivity pour surveiller les changements de connectivité
  final Connectivity _connectivity = Connectivity();

  // Contrôleur de flux pour diffuser les changements d'état de connexion
  final _connectionStatusController = StreamController<ConnectionStatus>.broadcast();

  // Stream exposé pour que les autres parties de l'application puissent écouter les changements
  Stream<ConnectionStatus> get connectionStatus => _connectionStatusController.stream;

  // État actuel de la connexion
  ConnectionStatus _currentStatus = ConnectionStatus.online;
  ConnectionStatus get currentStatus => _currentStatus;

  // Abonnement aux changements de connectivité
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  ConnectivityService() {
    // Initialiser l'état de la connexion
    _initConnectivity();
    // Écouter les changements de connectivité
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen(_updateConnectionStatus);
  }

  // Initialiser l'état de la connexion au démarrage
  Future<void> _initConnectivity() async {
    try {
      final results = await _connectivity.checkConnectivity();
      _updateConnectionStatus(results);
    } catch (e) {
      AppLogger.error('Error checking connectivity', e);
      _updateConnectionStatus([ConnectivityResult.none]);
    }
  }

  // Mettre à jour l'état de la connexion et notifier les écouteurs
  void _updateConnectionStatus(List<ConnectivityResult> results) {
    // Si au moins un résultat n'est pas "none", alors nous sommes en ligne
    final isOffline =
        results.isEmpty || results.every((result) => result == ConnectivityResult.none);

    final newStatus = isOffline ? ConnectionStatus.offline : ConnectionStatus.online;

    if (_currentStatus != newStatus) {
      _currentStatus = newStatus;
      _connectionStatusController.add(_currentStatus);

      // Notifier également le service de notification de synchronisation
      if (newStatus == ConnectionStatus.offline) {
        getIt<SyncNotificationService>().showOffline();
      } else {
        // Si nous passons en mode en ligne, vérifier s'il y a des opérations en attente
        final syncService = getIt<SyncService>();
        if (syncService.hasPendingOperations()) {
          getIt<SyncNotificationService>().showPendingSync(syncService.getPendingOperationsCount());
        } else {
          // Sinon, cacher la notification
          getIt<SyncNotificationService>().hide();
        }
      }

      AppLogger.info('Connection status changed to: ${_currentStatus.name}');
    }
  }

  // Vérifier manuellement l'état de la connexion
  Future<ConnectionStatus> checkConnectivity() async {
    try {
      final results = await _connectivity.checkConnectivity();
      _updateConnectionStatus(results);
      return _currentStatus;
    } catch (e) {
      AppLogger.error('Error checking connectivity', e);
      return ConnectionStatus.offline;
    }
  }

  // Nettoyer les ressources lors de la destruction du service
  void dispose() {
    _connectivitySubscription?.cancel();
    _connectionStatusController.close();
  }
}
