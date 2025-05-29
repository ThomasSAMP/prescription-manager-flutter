import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/injection.dart';
import '../../core/services/event_bus_service.dart';
import '../../features/notifications/providers/notification_provider.dart';
import '../../features/prescriptions/providers/medicament_provider.dart';
import '../../features/prescriptions/providers/ordonnance_provider.dart';

/// Provider qui écoute les événements et met à jour les autres providers
final eventListenerProvider = Provider<void>((ref) {
  final eventBus = getIt<EventBusService>();

  // Écouter les événements
  eventBus.events.listen((event) {
    switch (event.type) {
      case EventType.ordonnancesChanged:
        // Rafraîchir les données des ordonnances sans attendre
        unawaited(ref.read(ordonnanceProvider.notifier).refreshData());
        break;
      case EventType.medicamentsChanged:
        // Rafraîchir les données des médicaments sans attendre
        unawaited(ref.read(allMedicamentsProvider.notifier).refreshData());
        break;
      case EventType.notificationsChanged:
        // Rafraîchir les données des notifications sans attendre
        unawaited(ref.read(notificationsProvider.notifier).refreshData());
        break;
    }
  });

  return;
});
