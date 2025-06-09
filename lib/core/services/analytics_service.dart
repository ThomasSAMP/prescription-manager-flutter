import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';

import '../utils/logger.dart';

@lazySingleton
class AnalyticsService {
  final FirebaseAnalytics _analytics = FirebaseAnalytics.instance;
  FirebaseAnalyticsObserver? _observer;

  // Getter pour l'observer (utilisé dans la configuration du routeur)
  FirebaseAnalyticsObserver get observer {
    _observer ??= FirebaseAnalyticsObserver(analytics: _analytics);
    return _observer!;
  }

  // Initialiser le service d'analytics
  Future<void> initialize() async {
    try {
      // Activer la collecte d'analytics (désactivée en mode debug par défaut)
      await _analytics.setAnalyticsCollectionEnabled(!kDebugMode);
      AppLogger.info('AnalyticsService initialized successfully');
    } catch (e, stackTrace) {
      AppLogger.error('Failed to initialize AnalyticsService', e, stackTrace);
    }
  }

  Future<void> _logEventSafely(String eventName, Map<String, Object>? parameters) async {
    if (kDebugMode) {
      AppLogger.debug('Analytics: $eventName with params: $parameters');
      return; // Ne pas envoyer en mode debug
    }

    try {
      await _analytics.logEvent(name: eventName, parameters: parameters);
    } catch (e, stackTrace) {
      AppLogger.error('Failed to log analytics event: $eventName', e, stackTrace);
      // Ne pas faire échouer l'app si Analytics ne fonctionne pas
    }
  }

  // Enregistrer un événement de connexion
  Future<void> logLogin({required String method}) async {
    await _logEventSafely('login', {'login_method': method});
  }

  // Enregistrer un événement d'inscription
  Future<void> logSignUp({required String method}) async {
    await _logEventSafely('sign_up', {'sign_up_method': method});
  }

  // Enregistrer un événement de recherche
  Future<void> logSearch({required String searchTerm}) async {
    await _logEventSafely('search', {'search_term': searchTerm});
  }

  Future<void> logCustomEvent({required String name, Map<String, Object>? parameters}) async {
    await _logEventSafely(name, parameters);
  }

  // Définir les propriétés utilisateur
  Future<void> setUserProperties({
    String? userId,
    String? userRole,
    String? subscriptionType,
  }) async {
    try {
      if (userId != null) {
        await _analytics.setUserId(id: userId);
      }

      if (userRole != null) {
        await _analytics.setUserProperty(name: 'user_role', value: userRole);
      }

      if (subscriptionType != null) {
        await _analytics.setUserProperty(name: 'subscription_type', value: subscriptionType);
      }

      AppLogger.debug('Analytics: Set user properties');
    } catch (e, stackTrace) {
      AppLogger.error('Failed to set user properties', e, stackTrace);
    }
  }
}
