import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:go_router/go_router.dart';
import 'package:injectable/injectable.dart';

import '../../features/prescriptions/models/medicament_model.dart';
import '../../routes/app_router.dart';
import '../di/injection.dart';
import '../utils/logger.dart';
import 'auth_service.dart';
import 'navigation_service.dart';

// Énumération des types de notifications
enum NotificationType { medicationExpiration, syncStatus, general }

// Classe pour les données de notification
class NotificationData {
  final NotificationType type;
  final String title;
  final String body;
  final Map<String, dynamic>? data;
  final String? route;
  final Color? color;

  NotificationData({
    required this.type,
    required this.title,
    required this.body,
    this.data,
    this.route,
    this.color,
  });
}

@lazySingleton
class UnifiedNotificationService {
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();

  String? _token;
  String? _pendingNavigationRoute;

  String? get token => _token;
  bool get hasPendingNavigation => _pendingNavigationRoute != null;
  String? get pendingNavigationRoute => _pendingNavigationRoute;

  // Canal de notification unifié
  static const AndroidNotificationChannel _unifiedChannel = AndroidNotificationChannel(
    'unified_notifications',
    'Prescription Manager',
    description: 'All notifications for Prescription Manager',
    importance: Importance.high,
    enableVibration: true,
    playSound: true,
    enableLights: true,
    ledColor: Color.fromARGB(255, 255, 255, 255),
    showBadge: true,
  );

  Future<void> initialize() async {
    try {
      await _requestPermission();
      await _initializeLocalNotifications();
      _configureForegroundHandler();
      _configureBackgroundOpenedAppHandler();
      _configureTerminatedAppHandler();
      await _getToken();
      await subscribeToAllUsers();

      AppLogger.info('UnifiedNotificationService initialized successfully');
    } catch (e, stackTrace) {
      AppLogger.error('Failed to initialize UnifiedNotificationService', e, stackTrace);
    }
  }

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

  Future<void> _initializeLocalNotifications() async {
    const androidInitSettings = AndroidInitializationSettings('@drawable/ic_notification');
    const iosInitSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const initSettings = InitializationSettings(android: androidInitSettings, iOS: iosInitSettings);

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    await _localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_unifiedChannel);
  }

  void _configureForegroundHandler() {
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
  }

  void _configureBackgroundOpenedAppHandler() {
    FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageOpenedApp);
  }

  void _configureTerminatedAppHandler() {
    _checkInitialMessage();
  }

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

  Future<void> _getToken() async {
    _token = await _messaging.getToken();
    AppLogger.debug('FCM Token: $_token');

    _messaging.onTokenRefresh.listen((newToken) {
      _token = newToken;
      AppLogger.debug('FCM Token refreshed: $_token');
    });
  }

  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    AppLogger.debug('Foreground message received: ${message.notification?.title}');

    final notification = message.notification;
    if (notification != null && notification.title != null && notification.body != null) {
      await showLocalNotification(
        NotificationData(
          type: NotificationType.general,
          title: notification.title!,
          body: notification.body!,
          data: message.data,
        ),
      );
    }
  }

  void _handleMessageOpenedApp(RemoteMessage message) {
    AppLogger.debug('App opened from notification: ${message.notification?.title}');
    _pendingNavigationRoute = _extractNavigationRoute(message.data);
    _handleNotificationNavigation(message.data);
  }

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

  void _handleNotificationNavigation(Map<String, dynamic> data) {
    final route = _extractNavigationRoute(data) ?? '/notifications';
    AppLogger.debug('Navigation from notification to: $route');

    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 1000), () {
        try {
          final authService = getIt<AuthService>();
          if (authService.currentUser == null) {
            AppLogger.debug('User not authenticated, storing route');
            _pendingNavigationRoute = route;
            return;
          }

          final context = rootNavigatorKey.currentContext;
          if (context == null) {
            AppLogger.error('Root navigator context not available');
            _pendingNavigationRoute = route;
            return;
          }

          AppLogger.debug('Using root navigator context for navigation');
          context.go(route, extra: {'fromNotification': true, 'forceRefresh': true});
          AppLogger.debug('Context navigation completed to: $route');
        } catch (e) {
          AppLogger.error('Navigation failed', e);
          _pendingNavigationRoute = route;
        }
      });
    });
  }

  // Méthode unifiée pour afficher des notifications locales
  Future<void> showLocalNotification(NotificationData notificationData) async {
    try {
      final androidDetails = AndroidNotificationDetails(
        _unifiedChannel.id,
        _unifiedChannel.name,
        channelDescription: _unifiedChannel.description,
        importance: _unifiedChannel.importance,
        priority: Priority.high,
        icon: '@drawable/ic_notification',
        enableVibration: true,
        playSound: true,
        enableLights: true,
        ledColor: notificationData.color ?? _unifiedChannel.ledColor,
        showWhen: true,
        category: _getAndroidCategory(notificationData.type),
        visibility: NotificationVisibility.public,
      );

      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        badgeNumber: 1,
      );

      final details = NotificationDetails(android: androidDetails, iOS: iosDetails);

      await _localNotifications.show(
        DateTime.now().millisecondsSinceEpoch ~/ 1000,
        notificationData.title,
        notificationData.body,
        details,
        payload: notificationData.data != null ? jsonEncode(notificationData.data) : null,
      );

      AppLogger.debug('Local notification shown: ${notificationData.title}');
    } catch (e, stackTrace) {
      AppLogger.error('Error showing local notification', e, stackTrace);
    }
  }

  AndroidNotificationCategory _getAndroidCategory(NotificationType type) {
    switch (type) {
      case NotificationType.medicationExpiration:
        return AndroidNotificationCategory.reminder;
      case NotificationType.syncStatus:
        return AndroidNotificationCategory.status;
      case NotificationType.general:
        return AndroidNotificationCategory.message;
    }
  }

  // Méthodes spécifiques pour les notifications de médicaments
  Future<void> showMedicationExpirationNotification(MedicamentModel medication) async {
    final status = medication.getExpirationStatus();
    String title;
    String body;
    Color color;

    switch (status) {
      case ExpirationStatus.expired:
        title = 'Médicament expiré !';
        body = 'Le médicament ${medication.name} est expiré. Veuillez renouveler l\'ordonnance.';
        color = Colors.red.shade900;
        break;
      case ExpirationStatus.critical:
        title = 'Médicament bientôt expiré !';
        body = 'Le médicament ${medication.name} expire dans moins de 14 jours.';
        color = Colors.red;
        break;
      case ExpirationStatus.warning:
        title = 'Attention à l\'expiration';
        body = 'Le médicament ${medication.name} expire dans moins de 30 jours.';
        color = Colors.orange;
        break;
      default:
        return;
    }

    await showLocalNotification(
      NotificationData(
        type: NotificationType.medicationExpiration,
        title: title,
        body: body,
        color: color,
        data: {'screen': 'medication_detail', 'id': medication.id},
      ),
    );
  }

  // Méthodes pour les notifications de synchronisation
  Future<void> showSyncNotification(String message, {bool isError = false}) async {
    await showLocalNotification(
      NotificationData(
        type: NotificationType.syncStatus,
        title: 'Synchronisation',
        body: message,
        color: isError ? Colors.red : Colors.blue,
      ),
    );
  }

  Future<void> subscribeToAllUsers() async {
    try {
      await _messaging.subscribeToTopic('all_users');
      AppLogger.debug('Subscribed to topic: all_users');
    } catch (e) {
      AppLogger.error('Error subscribing to topic: all_users', e);
    }
  }

  Future<void> subscribeToTopic(String topic) async {
    await _messaging.subscribeToTopic(topic);
    AppLogger.debug('Subscribed to topic: $topic');
  }

  Future<void> unsubscribeFromTopic(String topic) async {
    await _messaging.unsubscribeFromTopic(topic);
    AppLogger.debug('Unsubscribed from topic: $topic');
  }

  void handlePostLoginNavigation() {
    if (_pendingNavigationRoute != null) {
      try {
        final navigationService = getIt<NavigationService>();
        final route = _pendingNavigationRoute!;
        _pendingNavigationRoute = null;

        AppLogger.debug('Navigating to pending route after login: $route');
        navigationService.navigateToRoute(route);
      } catch (e) {
        AppLogger.error('Error navigating to pending route after login', e);
        _pendingNavigationRoute = null;
      }
    }
  }

  void clearPendingNavigation() {
    _pendingNavigationRoute = null;
  }
}
