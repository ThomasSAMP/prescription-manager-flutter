import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/injection.dart';
import '../../core/services/event_bus_service.dart';
import '../../features/notifications/providers/medication_alert_provider.dart';
import '../../features/prescriptions/providers/medicament_provider.dart';
import '../../features/prescriptions/providers/ordonnance_provider.dart';

/// Provider qui écoute les événements et met à jour les autres providers
final eventListenerProvider = Provider<void>((ref) {
  final eventBus = getIt<EventBusService>();

  // Charger les alertes au démarrage pour avoir le badge
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(ref.read(medicationAlertsProvider.notifier).loadItems());
  });

  // Écouter les événements
  eventBus.events.listen((event) {
    switch (event.type) {
      case EventType.ordonnancesChanged:
        unawaited(ref.read(ordonnanceProvider.notifier).refreshData());
        break;
      case EventType.medicamentsChanged:
        unawaited(ref.read(allMedicamentsProvider.notifier).refreshData());
        break;
      case EventType.notificationsChanged:
        unawaited(ref.read(medicationAlertsProvider.notifier).refreshData());
        break;
    }
  });

  return;
});
