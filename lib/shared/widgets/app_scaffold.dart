import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/di/injection.dart';
import '../../core/services/haptic_service.dart';
import '../../features/notifications/providers/medication_alert_provider.dart';
import '../models/tab_item.dart';

class AppScaffold extends ConsumerStatefulWidget {
  final Widget child;
  final List<TabItem> tabs;
  final String currentPath;

  const AppScaffold({
    super.key,
    required this.child,
    required this.tabs,
    required this.currentPath,
  });

  @override
  ConsumerState<AppScaffold> createState() => _AppScaffoldState();
}

class _AppScaffoldState extends ConsumerState<AppScaffold> {
  @override
  void initState() {
    super.initState();

    // Déclencher le chargement des alertes au démarrage pour avoir le badge
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Charger les alertes en arrière-plan pour le badge
      if (mounted) {
        ref.read(medicationAlertsProvider.notifier).loadItems();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final hapticService = getIt<HapticService>();

    // Écouter le nombre d'alertes non lues
    final unreadCount = ref.watch(unreadAlertsCountProvider);

    return WillPopScope(
      onWillPop: () async {
        final canPop = Navigator.of(context).canPop();
        if (canPop) {
          return true;
        }

        if (widget.currentPath != '/ordonnances') {
          context.go('/ordonnances');
          return false;
        }

        return await _showExitDialog(context) ?? false;
      },
      child: Scaffold(
        body: widget.child,
        bottomNavigationBar: BottomNavigationBar(
          type: BottomNavigationBarType.fixed,
          currentIndex: _getCurrentIndex(),
          onTap: (index) => _onItemTapped(context, index, hapticService),
          items:
              widget.tabs.map((tab) {
                // Ajouter un badge pour l'onglet Notifications
                if (tab.label == 'Notifications' && unreadCount > 0) {
                  return BottomNavigationBarItem(
                    icon: Badge(label: Text(unreadCount.toString()), child: Icon(tab.icon)),
                    activeIcon: Badge(
                      label: Text(unreadCount.toString()),
                      child: Icon(tab.activeIcon),
                    ),
                    label: tab.label,
                  );
                } else {
                  return BottomNavigationBarItem(
                    icon: Icon(tab.icon),
                    activeIcon: Icon(tab.activeIcon),
                    label: tab.label,
                  );
                }
              }).toList(),
        ),
      ),
    );
  }

  int _getCurrentIndex() {
    final index = widget.tabs.indexWhere(
      (tab) => widget.currentPath.startsWith(tab.initialLocation),
    );
    return index < 0 ? 0 : index;
  }

  void _onItemTapped(BuildContext context, int index, HapticService hapticService) {
    final destination = widget.tabs[index].initialLocation;
    if (destination != widget.currentPath) {
      hapticService.feedback(HapticFeedbackType.tabSelection);
      context.go(destination);
    }
  }

  Future<bool?> _showExitDialog(BuildContext context) {
    getIt<HapticService>().feedback(HapticFeedbackType.medium);

    return showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Exit App'),
            content: const Text('Are you sure you want to exit the app?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () {
                  getIt<HapticService>().feedback(HapticFeedbackType.heavy);
                  Navigator.of(context).pop(true);
                },
                child: const Text('Exit'),
              ),
            ],
          ),
    );
  }
}
