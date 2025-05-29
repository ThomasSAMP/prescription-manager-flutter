import 'dart:async';

import 'package:injectable/injectable.dart';

/// Types d'événements
enum EventType { ordonnancesChanged, medicamentsChanged, notificationsChanged }

/// Classe représentant un événement
class AppEvent {
  final EventType type;
  final dynamic data;

  AppEvent(this.type, [this.data]);
}

@lazySingleton
class EventBusService {
  // Contrôleur de flux pour les événements
  final _eventController = StreamController<AppEvent>.broadcast();

  // Stream exposé pour que les autres parties de l'application puissent écouter les événements
  Stream<AppEvent> get events => _eventController.stream;

  // Méthode pour publier un événement
  void publish(AppEvent event) {
    _eventController.add(event);
  }

  // Nettoyer les ressources lors de la destruction du service
  void dispose() {
    _eventController.close();
  }
}
