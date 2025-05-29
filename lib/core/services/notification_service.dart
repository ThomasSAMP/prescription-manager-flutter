import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:injectable/injectable.dart';

import '../di/injection.dart';
import '../utils/logger.dart';
import 'navigation_service.dart';

// Canal de notification pour Android
const AndroidNotificationChannel medicationChannel = AndroidNotificationChannel(
  'medication_alerts', // id
  'Medication Alerts', // title
  description: 'Notifications for medication expiration alerts', // description
  importance: Importance.high,
  enableVibration: true,
  playSound: true,
);

@lazySingleton
class NotificationService {
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();

  // Pour stocker le token FCM
  String? _token;
  String? get token => _token;

  // Pour gérer la navigation différée
  String? _pendingNavigationRoute;

  // Initialiser le service de notification
  Future<void> initialize() async {
    try {
      // Demander la permission pour les notifications
      await _requestPermission();

      // Initialiser les notifications locales
      await _initializeLocalNotifications();

      // Configurer les gestionnaires de messages
      _configureForegroundHandler();
      _configureBackgroundOpenedAppHandler();
      _configureTerminatedAppHandler();

      // Obtenir le token FCM
      await _getToken();

      // S'abonner au topic pour tous les utilisateurs
      await subscribeToAllUsers();

      AppLogger.info('NotificationService initialized successfully');
    } catch (e, stackTrace) {
      AppLogger.error('Failed to initialize NotificationService', e, stackTrace);
    }
  }

  // Demander la permission pour les notifications
  Future<void> _requestPermission() async {
    final settings = await _messaging.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );

    AppLogger.debug('Notification permission status: ${settings.authorizationStatus}');
  }

  // Initialiser les notifications locales
  Future<void> _initializeLocalNotifications() async {
    // Initialiser les paramètres pour Android
    const androidInitSettings = AndroidInitializationSettings('@mipmap/ic_launcher');

    // Initialiser les paramètres pour iOS
    const iosInitSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    // Initialiser les paramètres globaux
    const initSettings = InitializationSettings(android: androidInitSettings, iOS: iosInitSettings);

    // Initialiser le plugin avec les paramètres
    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    // Créer le canal de notification pour Android
    await _localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(medicationChannel);
  }

  // Configurer le gestionnaire de messages en premier plan
  void _configureForegroundHandler() {
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
  }

  // Configurer le gestionnaire de messages en arrière-plan lorsque l'application est ouverte
  void _configureBackgroundOpenedAppHandler() {
    FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageOpenedApp);
  }

  // Configurer le gestionnaire pour les messages reçus quand l'app était fermée
  void _configureTerminatedAppHandler() {
    // Vérifier s'il y a un message initial (app ouverte via notification)
    _checkInitialMessage();
  }

  // Vérifier le message initial
  Future<void> _checkInitialMessage() async {
    try {
      final initialMessage = await _messaging.getInitialMessage();
      if (initialMessage != null) {
        AppLogger.debug('App opened from terminated state via notification');
        _handleMessageOpenedApp(initialMessage);
      }
    } catch (e) {
      AppLogger.error('Error checking initial message', e);
    }
  }

  // Obtenir le token FCM
  Future<void> _getToken() async {
    _token = await _messaging.getToken();
    AppLogger.debug('FCM Token: $_token');

    // Écouter les changements de token
    _messaging.onTokenRefresh.listen((newToken) {
      _token = newToken;
      AppLogger.debug('FCM Token refreshed: $_token');
    });
  }

  // Gérer les messages reçus en premier plan
  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    AppLogger.debug('Foreground message received: ${message.notification?.title}');

    // Extraire les données de notification
    final notification = message.notification;

    // Si la notification contient un titre et un corps, afficher une notification locale
    if (notification != null && notification.title != null && notification.body != null) {
      await _showLocalNotification(
        title: notification.title!,
        body: notification.body!,
        data: message.data,
      );
    }
  }

  // Gérer les messages lorsque l'application est ouverte à partir d'une notification
  void _handleMessageOpenedApp(RemoteMessage message) {
    AppLogger.debug('App opened from notification: ${message.notification?.title}');

    // Stocker la route de navigation pour plus tard si l'utilisateur n'est pas connecté
    _pendingNavigationRoute = _extractNavigationRoute(message.data);

    // Naviguer immédiatement si possible
    _handleNotificationNavigation(message.data);
  }

  // Extraire la route de navigation des données
  String? _extractNavigationRoute(Map<String, dynamic> data) {
    if (data.containsKey('screen')) {
      final screen = data['screen'] as String;
      switch (screen) {
        case 'notifications':
          return '/notifications';
        case 'profile':
          return '/profile';
        case 'settings':
          return '/settings';
        default:
          return '/ordonnances';
      }
    }
    return null;
  }

  // Gérer la navigation lorsqu'une notification est tapée
  void _onNotificationTapped(NotificationResponse response) {
    AppLogger.debug('Notification tapped: ${response.payload}');

    if (response.payload != null) {
      try {
        final data = jsonDecode(response.payload!) as Map<String, dynamic>;
        _handleNotificationNavigation(data);
      } catch (e) {
        AppLogger.error('Error parsing notification payload', e);
      }
    }
  }

  // Naviguer vers un écran spécifique en fonction des données de notification
  void _handleNotificationNavigation(Map<String, dynamic> data) {
    try {
      final navigationService = getIt<NavigationService>();
      final route = _extractNavigationRoute(data) ?? '/notifications';

      // Essayer de naviguer immédiatement
      navigationService.navigateToRoute(route);
    } catch (e) {
      // Si la navigation échoue (probablement parce que l'utilisateur n'est pas connecté),
      // stocker la route pour plus tard
      AppLogger.debug('Navigation failed, storing route for later: $e');
      _pendingNavigationRoute = _extractNavigationRoute(data);
    }
  }

  // Méthode appelée après une connexion réussie pour naviguer vers la route en attente
  void handlePostLoginNavigation() {
    if (_pendingNavigationRoute != null) {
      try {
        final navigationService = getIt<NavigationService>();
        final route = _pendingNavigationRoute!;
        _pendingNavigationRoute = null; // Réinitialiser

        AppLogger.debug('Navigating to pending route after login: $route');
        navigationService.navigateToRoute(route);
      } catch (e) {
        AppLogger.error('Error navigating to pending route after login', e);
        _pendingNavigationRoute = null;
      }
    }
  }

  // Afficher une notification locale
  Future<void> _showLocalNotification({
    required String title,
    required String body,
    Map<String, dynamic>? data,
  }) async {
    try {
      const androidDetails = AndroidNotificationDetails(
        'medication_alerts',
        'Medication Alerts',
        channelDescription: 'Notifications for medication expiration alerts',
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
        enableVibration: true,
        playSound: true,
      );

      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      const details = NotificationDetails(android: androidDetails, iOS: iosDetails);

      await _localNotifications.show(
        DateTime.now().millisecondsSinceEpoch ~/ 1000,
        title,
        body,
        details,
        payload: data != null ? jsonEncode(data) : null,
      );

      AppLogger.debug('Local notification shown: $title');
    } catch (e, stackTrace) {
      AppLogger.error('Error showing local notification', e, stackTrace);
    }
  }

  // Méthode publique pour afficher une notification locale (pour les tests)
  Future<void> showLocalNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    try {
      const androidDetails = AndroidNotificationDetails(
        'medication_alerts',
        'Medication Alerts',
        channelDescription: 'Notifications for medication expiration alerts',
        importance: Importance.high,
        priority: Priority.high,
      );

      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      const details = NotificationDetails(android: androidDetails, iOS: iosDetails);

      await _localNotifications.show(id, title, body, details, payload: payload);
      AppLogger.debug('Local notification sent: $title');
    } catch (e, stackTrace) {
      AppLogger.error('Error sending local notification', e, stackTrace);
      rethrow;
    }
  }

  // Abonner tous les appareils au topic 'all_users'
  Future<void> subscribeToAllUsers() async {
    try {
      await _messaging.subscribeToTopic('all_users');
      AppLogger.debug('Subscribed to topic: all_users');
    } catch (e) {
      AppLogger.error('Error subscribing to topic: all_users', e);
    }
  }

  // Souscrire à un topic pour recevoir des notifications ciblées
  Future<void> subscribeToTopic(String topic) async {
    await _messaging.subscribeToTopic(topic);
    AppLogger.debug('Subscribed to topic: $topic');
  }

  // Se désabonner d'un topic
  Future<void> unsubscribeFromTopic(String topic) async {
    await _messaging.unsubscribeFromTopic(topic);
    AppLogger.debug('Unsubscribed from topic: $topic');
  }

  // Getter pour vérifier s'il y a une navigation en attente
  bool get hasPendingNavigation => _pendingNavigationRoute != null;

  // Getter pour obtenir la route en attente
  String? get pendingNavigationRoute => _pendingNavigationRoute;

  // Méthode pour effacer la navigation en attente
  void clearPendingNavigation() {
    _pendingNavigationRoute = null;
  }
}
