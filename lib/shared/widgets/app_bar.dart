import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/di/injection.dart';
import '../../core/services/unified_sync_service.dart';
import '../providers/sync_status_provider.dart';
import 'sync_status_indicator.dart';

class AppBarWidget extends ConsumerWidget implements PreferredSizeWidget {
  final String title;
  final List<Widget>? actions;
  final bool showBackButton;
  final VoidCallback? onBackPressed;
  final Widget? leading;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final double elevation;
  final bool centerTitle;
  final bool showSyncButton;

  const AppBarWidget({
    super.key,
    required this.title,
    this.actions,
    this.showBackButton = true,
    this.onBackPressed,
    this.leading,
    this.backgroundColor,
    this.foregroundColor,
    this.elevation = 0,
    this.centerTitle = true,
    this.showSyncButton = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Éviter de watcher syncStatusProvider si showSyncButton est false
    final syncState = showSyncButton ? ref.watch(syncStatusProvider) : null;

    // Créer la liste d'actions
    final allActions = <Widget>[];

    // Ajouter le bouton de synchronisation si demandé
    if (showSyncButton && syncState != null) {
      allActions.add(
        IconButton(
          icon: Icon(
            syncState.status == SyncStatus.syncing
                ? Icons.sync
                : syncState.status == SyncStatus.pendingSync
                ? Icons.cloud_queue
                : syncState.status == SyncStatus.error
                ? Icons.cloud_off
                : syncState.status == SyncStatus.offline
                ? Icons.wifi_off
                : Icons.cloud_done,
          ),
          onPressed:
              syncState.status == SyncStatus.syncing || syncState.status == SyncStatus.offline
                  ? null
                  : () async {
                    try {
                      // Utiliser le service de synchronisation unifié
                      await getIt<UnifiedSyncService>().syncAll();
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(
                          context,
                        ).showSnackBar(SnackBar(content: Text('Erreur: ${e.toString()}')));
                      }
                    }
                  },
          tooltip: 'Synchroniser',
        ),
      );
    }

    // Ajouter les actions personnalisées
    if (actions != null) {
      allActions.addAll(actions!);
    }

    return AppBar(
      title: Text(title),
      centerTitle: centerTitle,
      elevation: elevation,
      backgroundColor: backgroundColor,
      foregroundColor: foregroundColor,
      leading: _buildLeading(context),
      actions: allActions,
    );
  }

  Widget? _buildLeading(BuildContext context) {
    // Si un widget leading personnalisé est fourni, l'utiliser
    if (leading != null) return leading;

    // Sinon, afficher le bouton de retour si demandé et si on peut revenir en arrière
    if (showBackButton && context.canPop()) {
      return IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: onBackPressed ?? () => context.pop(),
      );
    }

    // Sinon, ne pas afficher de bouton
    return null;
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}
