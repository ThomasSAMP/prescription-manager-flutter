import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:prescription_manager/features/settings/presentation/screens/notification_monitoring_screen.dart';

import '../core/di/injection.dart';
import '../core/services/analytics_service.dart';
import '../core/utils/logger.dart';
import '../features/auth/presentation/screens/login_screen.dart';
import '../features/error/presentation/screens/not_found_screen.dart';
import '../features/notifications/presentation/screens/notifications_screen.dart';
import '../features/prescriptions/presentation/screens/create_ordonnance_screen.dart';
import '../features/prescriptions/presentation/screens/medicament_detail_screen.dart';
import '../features/prescriptions/presentation/screens/medicament_form_screen.dart';
import '../features/prescriptions/presentation/screens/ordonnance_detail_screen.dart';
import '../features/prescriptions/presentation/screens/ordonnance_list_screen.dart';
import '../features/profile/presentation/screens/profile_screen.dart';
import '../features/settings/presentation/screens/analytics_test_screen.dart';
import '../features/settings/presentation/screens/error_test_screen.dart';
import '../features/settings/presentation/screens/haptic_test_screen.dart';
import '../features/settings/presentation/screens/image_cache_test_screen.dart';
import '../features/settings/presentation/screens/notification_settings_screen.dart';
import '../features/settings/presentation/screens/notification_test_screen.dart';
import '../features/settings/presentation/screens/settings_screen.dart';
import '../features/settings/presentation/screens/sms_test_screen.dart';
import '../features/settings/presentation/screens/update_test_screen.dart';
import '../shared/models/tab_item.dart';
import '../shared/providers/auth_provider.dart';
import '../shared/widgets/app_scaffold.dart';
import 'navigation_observer.dart';
import 'page_transitions.dart' as custom_page_transition;

export 'package:flutter/material.dart' show GlobalKey, NavigatorState;

final rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'rootNavigator');
final _shellNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'shellNavigator');

final tabsProvider = Provider<List<TabItem>>((ref) {
  return [
    TabItem(
      initialLocation: '/ordonnances',
      icon: Icons.description_outlined,
      activeIcon: Icons.description,
      label: 'Ordonnances',
    ),
    TabItem(
      initialLocation: '/profile',
      icon: Icons.person_outline,
      activeIcon: Icons.person,
      label: 'Profile',
    ),
    TabItem(
      initialLocation: '/notifications',
      icon: Icons.notifications_outlined,
      activeIcon: Icons.notifications,
      label: 'Notifications',
    ),
    TabItem(
      initialLocation: '/settings',
      icon: Icons.settings_outlined,
      activeIcon: Icons.settings,
      label: 'Paramètres',
    ),
  ];
});

final routerProvider = Provider<GoRouter>((ref) {
  final tabs = ref.watch(tabsProvider);
  final isAuthenticated = ref.watch(isAuthenticatedProvider);
  final observer = getIt<AppNavigationObserver>();
  final analyticsObserver = getIt<AnalyticsService>().observer;

  final router = GoRouter(
    initialLocation: '/ordonnances',
    navigatorKey: rootNavigatorKey,
    debugLogDiagnostics: true,
    observers: [observer, analyticsObserver],
    redirect: (context, state) {
      try {
        // Si l'utilisateur n'est pas authentifié, rediriger vers login
        if (!isAuthenticated) {
          // Ne pas rediriger si déjà sur la page de login
          if (state.matchedLocation == '/login') {
            return null;
          }
          return '/login';
        }

        // Si l'utilisateur est authentifié et tente d'accéder à login
        if (isAuthenticated && state.matchedLocation == '/login') {
          return '/ordonnances';
        }

        return null;
      } catch (e) {
        // En cas d'erreur, permettre la navigation normale
        AppLogger.error('Error in router redirect', e);
        return null;
      }
    },
    errorBuilder: (context, state) => NotFoundScreen(path: state.uri.toString()),
    routes: [
      // Auth routes
      GoRoute(
        path: '/login',
        name: 'login',
        pageBuilder:
            (context, state) => custom_page_transition.FadeTransitionPage(
              child: const LoginScreen(),
              name: 'LoginScreen',
            ),
      ),

      // Main app shell with bottom navigation
      ShellRoute(
        navigatorKey: _shellNavigatorKey,
        builder: (context, state, child) {
          return AppScaffold(tabs: tabs, currentPath: state.matchedLocation, child: child);
        },
        routes: [
          GoRoute(
            path: '/ordonnances',
            name: 'ordonnances',
            pageBuilder:
                (context, state) => custom_page_transition.NoTransitionPage(
                  child: const OrdonnanceListScreen(),
                  name: 'OrdonnanceListScreen',
                ),
          ),
          GoRoute(
            path: '/ordonnance/:ordonnanceId',
            name: 'ordonnance-detail-direct',
            pageBuilder: (context, state) {
              final ordonnanceId = state.pathParameters['ordonnanceId']!;
              final fromNotifications =
                  state.extra is Map<String, dynamic> &&
                  (state.extra as Map<String, dynamic>)['fromNotifications'] == true;

              return custom_page_transition.NoTransitionPage(
                child: OrdonnanceDetailScreen(
                  ordonnanceId: ordonnanceId,
                  fromNotifications: fromNotifications,
                ),
                name: 'OrdonnanceDetailScreen',
              );
            },
          ),
          GoRoute(
            path: '/medicament/:ordonnanceId/:medicamentId',
            name: 'medicament-detail-direct',
            pageBuilder: (context, state) {
              final ordonnanceId = state.pathParameters['ordonnanceId']!;
              final medicamentId = state.pathParameters['medicamentId']!;
              final fromNotifications =
                  state.extra is Map<String, dynamic> &&
                  (state.extra as Map<String, dynamic>)['fromNotifications'] == true;

              return custom_page_transition.NoTransitionPage(
                child: MedicamentDetailScreen(
                  ordonnanceId: ordonnanceId,
                  medicamentId: medicamentId,
                  fromNotifications: fromNotifications,
                ),
                name: 'MedicamentDetailScreen',
              );
            },
          ),
          // Routes imbriquées pour la navigation normale depuis la liste
          GoRoute(
            path: '/ordonnances/new',
            name: 'create-ordonnance',
            pageBuilder:
                (context, state) => custom_page_transition.NoTransitionPage(
                  child: const CreateOrdonnanceScreen(),
                  name: 'CreateOrdonnanceScreen',
                ),
          ),
          GoRoute(
            path: '/ordonnances/:ordonnanceId',
            name: 'ordonnance-detail',
            pageBuilder: (context, state) {
              final ordonnanceId = state.pathParameters['ordonnanceId']!;
              final fromNotifications =
                  state.extra is Map<String, dynamic> &&
                  (state.extra as Map<String, dynamic>)['fromNotifications'] == true;

              return custom_page_transition.NoTransitionPage(
                child: OrdonnanceDetailScreen(
                  ordonnanceId: ordonnanceId,
                  fromNotifications: fromNotifications,
                ),
                name: 'OrdonnanceDetailScreen',
              );
            },
            routes: [
              GoRoute(
                path: 'medicaments/new',
                name: 'create-medicament',
                pageBuilder: (context, state) {
                  final ordonnanceId = state.pathParameters['ordonnanceId']!;
                  return custom_page_transition.NoTransitionPage(
                    child: MedicamentFormScreen(ordonnanceId: ordonnanceId),
                    name: 'CreateMedicamentScreen',
                  );
                },
              ),
              GoRoute(
                path: 'medicaments/:medicamentId',
                name: 'medicament-detail',
                pageBuilder: (context, state) {
                  final ordonnanceId = state.pathParameters['ordonnanceId']!;
                  final medicamentId = state.pathParameters['medicamentId']!;
                  final fromNotifications =
                      state.extra is Map<String, dynamic> &&
                      (state.extra as Map<String, dynamic>)['fromNotifications'] == true;

                  return custom_page_transition.NoTransitionPage(
                    child: MedicamentDetailScreen(
                      ordonnanceId: ordonnanceId,
                      medicamentId: medicamentId,
                      fromNotifications: fromNotifications,
                    ),
                    name: 'MedicamentDetailScreen',
                  );
                },
                routes: [
                  GoRoute(
                    path: 'edit',
                    name: 'edit-medicament',
                    pageBuilder: (context, state) {
                      final ordonnanceId = state.pathParameters['ordonnanceId']!;
                      final medicamentId = state.pathParameters['medicamentId']!;
                      return custom_page_transition.NoTransitionPage(
                        child: MedicamentFormScreen(
                          ordonnanceId: ordonnanceId,
                          medicamentId: medicamentId,
                        ),
                        name: 'EditMedicamentScreen',
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
          GoRoute(
            path: '/profile',
            name: 'profile',
            pageBuilder:
                (context, state) => custom_page_transition.NoTransitionPage(
                  child: const ProfileScreen(),
                  name: 'ProfileScreen',
                ),
          ),
          GoRoute(
            path: '/notifications',
            name: 'notifications',
            pageBuilder: (context, state) {
              final extra = state.extra as Map<String, dynamic>?;

              final fromNotification = extra?['fromNotification'] ?? false;
              final forceRefresh = extra?['forceRefresh'] ?? false;

              return custom_page_transition.NoTransitionPage(
                child: NotificationsScreen(
                  fromNotification: fromNotification,
                  forceRefresh: forceRefresh,
                ),
                name: 'NotificationsScreen',
              );
            },
          ),
          GoRoute(
            path: '/settings',
            name: 'settings',
            pageBuilder:
                (context, state) => custom_page_transition.NoTransitionPage(
                  child: const SettingsScreen(),
                  name: 'SettingsScreen',
                ),
            routes: [
              // Routes imbriquées pour les écrans de test
              GoRoute(
                path: 'notification-settings',
                name: 'notification-settings',
                pageBuilder:
                    (context, state) => custom_page_transition.NoTransitionPage(
                      child: const NotificationSettingsScreen(),
                      name: 'NotificationSettingsScreen',
                    ),
              ),
              GoRoute(
                path: 'notification-test',
                name: 'notification-test',
                pageBuilder:
                    (context, state) => custom_page_transition.NoTransitionPage(
                      child: const NotificationTestScreen(),
                      name: 'NotificationTestScreen',
                    ),
              ),
              GoRoute(
                path: 'analytics-test',
                name: 'analytics-test',
                pageBuilder:
                    (context, state) => custom_page_transition.NoTransitionPage(
                      child: const AnalyticsTestScreen(),
                      name: 'AnalyticsTestScreen',
                    ),
              ),
              GoRoute(
                path: 'error-test',
                name: 'error-test',
                pageBuilder:
                    (context, state) => custom_page_transition.NoTransitionPage(
                      child: const ErrorTestScreen(),
                      name: 'ErrorTestScreen',
                    ),
              ),
              GoRoute(
                path: 'update-test',
                name: 'update-test',
                pageBuilder:
                    (context, state) => custom_page_transition.NoTransitionPage(
                      child: const UpdateTestScreen(),
                      name: 'UpdateTestScreen',
                    ),
              ),
              GoRoute(
                path: 'image-cache-test',
                name: 'image-cache-test',
                pageBuilder:
                    (context, state) => custom_page_transition.NoTransitionPage(
                      child: const ImageCacheTestScreen(),
                      name: 'ImageCacheTestScreen',
                    ),
              ),
              GoRoute(
                path: 'haptic-test',
                name: 'haptic-test',
                pageBuilder:
                    (context, state) => custom_page_transition.NoTransitionPage(
                      child: const HapticTestScreen(),
                      name: 'HapticTestScreen',
                    ),
              ),
              GoRoute(
                path: 'notification-monitoring',
                name: 'notification-monitoring',
                pageBuilder:
                    (context, state) => custom_page_transition.NoTransitionPage(
                      child: const NotificationMonitoringScreen(),
                      name: 'NotificationMonitoring',
                    ),
              ),
              GoRoute(
                path: 'sms-test',
                name: 'sms-test',
                pageBuilder:
                    (context, state) => custom_page_transition.NoTransitionPage(
                      child: const SMSTestScreen(),
                      name: 'SMSTestScreen',
                    ),
              ),
            ],
          ),
        ],
      ),
    ],
  );

  // Enregistrer le router dans GetIt
  if (!getIt.isRegistered<GoRouter>()) {
    getIt.registerSingleton<GoRouter>(router);
  }

  return router;
});
