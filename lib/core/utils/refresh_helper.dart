import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/providers/sync_status_provider.dart';
import '../di/injection.dart';
import '../services/connectivity_service.dart';
import '../services/unified_sync_service.dart';

class RefreshHelper {
  /// Exécute une opération de rafraîchissement en tenant compte de l'état de la connectivité
  static Future<void> refreshData({
    required BuildContext context,
    required WidgetRef ref,
    required Future<void> Function() onlineRefresh,
    required Future<void> Function() offlineRefresh,
  }) async {
    try {
      // Vérifier d'abord si nous sommes en ligne
      final connectivityService = getIt<ConnectivityService>();
      if (connectivityService.currentStatus == ConnectionStatus.offline) {
        // Si nous sommes hors ligne, exécuter la logique hors ligne
        await offlineRefresh();

        // Afficher une notification de mode hors ligne
        ref.read(syncStatusProvider.notifier).setOffline();

        // Afficher un message à l'utilisateur
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Mode hors ligne : données locales chargées')),
          );
        }

        return; // Sortir de la méthode sans essayer de synchroniser
      }

      // Si nous sommes en ligne, exécuter la logique en ligne
      await onlineRefresh();

      // Synchroniser les données avec le serveur
      await getIt<UnifiedSyncService>().syncAll();
    } catch (e) {
      // Gérer l'erreur
      if (!e.toString().contains('hors ligne')) {
        // Ne pas afficher d'erreur pour le mode hors ligne
        ref.read(syncStatusProvider.notifier).setError('Erreur: ${e.toString()}');

        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Erreur lors de la synchronisation: $e')));
        }
      }
    }
  }
}
