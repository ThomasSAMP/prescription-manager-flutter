import 'dart:async';

import '../../shared/providers/sync_status_provider.dart';
import '../di/injection.dart';
import '../models/syncable_model.dart';
import '../services/connectivity_service.dart';
import '../services/local_storage_service.dart';
import '../services/sync_service.dart';
import '../utils/conflict_resolver.dart';
import '../utils/logger.dart';

/// Classe de base pour les repositories avec prise en charge du mode hors ligne
abstract class OfflineRepositoryBase<T extends SyncableModel> {
  final ConnectivityService connectivityService;
  final LocalStorageService localStorageService;

  // Clé pour le stockage local des données
  final String storageKey;

  // Clé pour le stockage local des opérations en attente
  final String pendingOperationsKey;

  // File d'attente des opérations en attente
  final List<PendingOperation<T>> pendingOperations = [];

  final ConflictResolver _conflictResolver = ConflictResolver(
    strategy: ConflictResolutionStrategy.newerWins,
  );

  // Abonnement aux changements de connectivité
  StreamSubscription<ConnectionStatus>? _connectivitySubscription;

  // Fonction pour créer un modèle à partir d'un JSON
  final T Function(Map<String, dynamic> json) fromJson;

  OfflineRepositoryBase({
    required this.connectivityService,
    required this.localStorageService,
    required this.storageKey,
    required this.pendingOperationsKey,
    required this.fromJson,
  }) {
    // Écouter les changements de connectivité
    _connectivitySubscription = connectivityService.connectionStatus.listen(
      _handleConnectivityChange,
    );

    // Charger les opérations en attente
    _loadPendingOperations();
  }

  // Mettre à jour le nombre d'opérations en attente
  void _updatePendingOperationsCount() {
    final syncService = getIt<SyncService>();
    syncService.updatePendingOperationsCount();
  }

  // Méthode appelée lorsque la connectivité change
  void _handleConnectivityChange(ConnectionStatus status) {
    if (status == ConnectionStatus.online) {
      AppLogger.info('Connection restored. Processing pending operations...');
      processPendingOperations();
    }
  }

  // Traiter les opérations en attente lorsque la connexion est rétablie
  Future<void> processPendingOperations() async {
    if (pendingOperations.isEmpty) return;

    AppLogger.info('Processing ${pendingOperations.length} pending operations');

    final syncStatusNotifier = getIt<SyncStatusNotifier>();
    syncStatusNotifier.setSyncing();

    // Créer une copie pour éviter les modifications concurrentes
    final operations = List<PendingOperation<T>>.from(pendingOperations);
    final failedOperations = <PendingOperation<T>>[];
    var errorMessage = '';

    for (final operation in operations) {
      try {
        await operation.execute();
        pendingOperations.remove(operation);
        AppLogger.debug('Successfully processed pending operation: ${operation.type}');
      } catch (e) {
        AppLogger.error('Failed to process pending operation: ${operation.type}', e);
        failedOperations.add(operation);
        errorMessage = 'Échec de la synchronisation: ${e.toString()}';
        // ✅ NOUVEAU : Gestion des erreurs par type
        if (e.toString().contains('permission-denied') || e.toString().contains('not-found')) {
          // Erreurs définitives : supprimer l'opération
          pendingOperations.remove(operation);
          AppLogger.warning('Removing failed operation due to permanent error: ${operation.type}');
        } else {
          // Garder l'opération dans la file d'attente pour réessayer plus tard
          break; // Arrêter le traitement en cas d'erreur
        }
      }
    }

    // Sauvegarder l'état mis à jour
    await savePendingOperations();

    // Mettre à jour l'état de synchronisation
    if (failedOperations.isNotEmpty) {
      syncStatusNotifier.setError('${failedOperations.length} opération(s) en échec $errorMessage');
    } else if (pendingOperations.isEmpty) {
      syncStatusNotifier.setSynced();
    } else {
      syncStatusNotifier.setPendingOperationsCount(pendingOperations.length);
    }
  }

  // Ajouter une opération à la file d'attente
  Future<void> addPendingOperation(PendingOperation<T> operation) async {
    try {
      // Ajouter à la liste en mémoire
      pendingOperations.add(operation);

      // Sauvegarder immédiatement sur disque
      await savePendingOperations();

      // Mettre à jour le compteur
      _updatePendingOperationsCount();

      // Si en ligne, traiter immédiatement
      if (connectivityService.currentStatus == ConnectionStatus.online) {
        // Ne pas attendre pour ne pas bloquer l'UI
        unawaited(processPendingOperations());
      }

      AppLogger.debug('Pending operation added safely: ${operation.type}');
    } catch (e) {
      AppLogger.error('Failed to add pending operation', e);
      // Retirer de la liste si la sauvegarde a échoué
      pendingOperations.remove(operation);
      rethrow;
    }
  }

  // Charger les opérations en attente depuis le stockage local
  Future<void> _loadPendingOperations() async {
    try {
      final operationsData = localStorageService.loadPendingOperationsData(pendingOperationsKey);

      for (final data in operationsData) {
        final type = OperationType.values[data['type'] as int];
        final modelData = data['data'] as Map<String, dynamic>;
        final model = fromJson(modelData);

        switch (type) {
          case OperationType.create:
          case OperationType.update:
            await addPendingOperation(
              PendingOperation<T>(type: type, data: model, execute: () => saveToRemote(model)),
            );
            break;
          case OperationType.delete:
            await addPendingOperation(
              PendingOperation<T>(
                type: type,
                data: model,
                execute: () => deleteFromRemote(model.id),
              ),
            );
            break;
        }
      }

      AppLogger.debug('Loaded ${operationsData.length} pending operations');
    } catch (e) {
      AppLogger.error('Error loading pending operations', e);
    }
  }

  // Sauvegarder les opérations en attente dans le stockage local
  Future<void> savePendingOperations() async {
    await localStorageService.savePendingOperations<T>(pendingOperationsKey, pendingOperations);
  }

  // Sauvegarder localement
  Future<void> saveLocally(T item) async {
    final items = loadAllLocally();
    final index = items.indexWhere((i) => i.id == item.id);

    if (index >= 0) {
      items[index] = item;
    } else {
      items.add(item);
    }

    await localStorageService.saveModelList<T>(storageKey, items);
  }

  // Supprimer localement
  Future<void> deleteLocally(String id) async {
    final items = loadAllLocally();
    final updatedItems = items.where((item) => item.id != id).toList();
    await localStorageService.saveModelList<T>(storageKey, updatedItems);
  }

  // Charger toutes les données locales
  List<T> loadAllLocally() {
    return localStorageService.loadModelList<T>(storageKey, fromJson);
  }

  /// Sauvegarde un élément sur le serveur distant
  Future<void> saveToRemote(T item);

  /// Supprime un élément du serveur distant
  Future<void> deleteFromRemote(String id);

  /// Charge tous les éléments depuis le serveur distant
  Future<List<T>> loadAllFromRemote();

  /// Synchronise les données avec le serveur
  Future<void> syncWithServer() async {
    try {
      final syncStatusNotifier = getIt<SyncStatusNotifier>();
      syncStatusNotifier.setSyncing();

      // Traiter les opérations en attente
      await processPendingOperations();

      // Si toutes les opérations ont été traitées avec succès
      if (pendingOperations.isEmpty) {
        // Récupérer les données depuis le serveur
        final remoteItems = <T>[];
        try {
          remoteItems.addAll(await loadAllFromRemote());
        } catch (e) {
          AppLogger.error('Error loading data from remote', e);
          // Continuer avec une liste vide si la récupération échoue
        }

        // Récupérer les données locales
        final localItems = loadAllLocally();

        // Créer une liste pour les éléments à sauvegarder localement
        final itemsToSave = <T>[];

        // Traiter tous les éléments distants
        for (final remoteItem in remoteItems) {
          try {
            // Chercher l'élément correspondant localement
            final localItem = localItems.firstWhere(
              (item) => item.id == remoteItem.id,
              orElse: () => null as T,
            );

            // L'élément existe localement, vérifier s'il y a un conflit
            if (_conflictResolver.hasConflict(localItem, remoteItem)) {
              // Résoudre le conflit
              final resolvedItem = _conflictResolver.resolve(localItem, remoteItem);
              itemsToSave.add(resolvedItem.copyWith(isSynced: true) as T);
            } else {
              // Pas de conflit, utiliser la version avec le isSynced à true
              itemsToSave.add(remoteItem.copyWith(isSynced: true) as T);
            }
          } catch (e) {
            AppLogger.error('Error processing remote item: ${remoteItem.id}', e);
            // Continuer avec l'élément suivant
          }
        }

        // Ajouter les éléments qui existent uniquement localement
        for (final localItem in localItems) {
          try {
            if (!remoteItems.any((item) => item.id == localItem.id)) {
              // Cet élément n'existe que localement
              if (!localItem.isSynced) {
                // Il n'est pas synchronisé, le sauvegarder sur le serveur
                await saveToRemote(localItem);
                itemsToSave.add(localItem.copyWith(isSynced: true) as T);
              } else {
                // Il est déjà synchronisé, l'ajouter simplement à la liste
                itemsToSave.add(localItem);
              }
            }
          } catch (e) {
            AppLogger.error('Error processing local item: ${localItem.id}', e);
            // Continuer avec l'élément suivant
          }
        }

        // Sauvegarder tous les éléments localement
        await localStorageService.saveModelList<T>(storageKey, itemsToSave);

        syncStatusNotifier.setSynced();
        AppLogger.info('Data synchronized with server');
      }
    } catch (e) {
      AppLogger.error('Error synchronizing data with server', e);
      final syncStatusNotifier = getIt<SyncStatusNotifier>();
      syncStatusNotifier.setError('Erreur de synchronisation: ${e.toString()}');
      rethrow;
    }
  }

  // Nettoyer les ressources lors de la destruction du repository
  void dispose() {
    _connectivitySubscription?.cancel();
  }
}
