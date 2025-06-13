import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/injection.dart';
import '../../core/services/event_bus_service.dart';
import '../../features/notifications/providers/medication_alert_provider.dart';
import '../../features/prescriptions/providers/medicament_provider.dart';
import '../../features/prescriptions/providers/ordonnance_provider.dart';

// Provider optimisé qui évite les rechargements multiples
final eventListenerProvider = Provider<void>((ref) {
  final eventBus = getIt<EventBusService>();

  // Flag pour éviter les chargements multiples
  var isInitialized = false;

  // Charger les alertes au démarrage une seule fois
  if (!isInitialized) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(ref.read(medicationAlertsProvider.notifier).loadItems());
      isInitialized = true;
    });
  }

  // Écouter les événements avec debouncing
  Timer? debounceTimer;

  eventBus.events.listen((event) {
    debounceTimer?.cancel();

    debounceTimer = Timer(const Duration(milliseconds: 300), () {
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
  });

  return;
});
