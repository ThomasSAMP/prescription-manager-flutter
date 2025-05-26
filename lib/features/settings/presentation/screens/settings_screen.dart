import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/services/navigation_service.dart';
import '../../../../shared/providers/theme_provider.dart';
import '../../../../shared/widgets/app_bar.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  PackageInfo? _packageInfo;
  bool _isLoading = true;
  final _navigationService = getIt<NavigationService>();

  @override
  void initState() {
    super.initState();
    _loadPackageInfo();
  }

  Future<void> _loadPackageInfo() async {
    final packageInfo = await PackageInfo.fromPlatform();
    if (mounted) {
      setState(() {
        _packageInfo = packageInfo;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeProvider);

    return Scaffold(
      appBar: const AppBarWidget(title: 'Paramètres', showBackButton: false),
      body:
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                children: [
                  const SizedBox(height: 16),
                  _buildSection(
                    title: 'Apparence',
                    children: [
                      ListTile(
                        title: const Text('Thème'),
                        subtitle: Text(themeMode.name),
                        leading: Icon(themeMode.icon),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _showThemeDialog(context),
                      ),
                    ],
                  ),
                  _buildSection(
                    title: 'Notifications',
                    children: [
                      ListTile(
                        title: const Text('Paramètres de notification'),
                        subtitle: const Text(
                          'Gérer les autorisations et les préférences de notification',
                        ),
                        leading: const Icon(Icons.notifications_active),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.go('/settings/notification-settings'),
                      ),
                    ],
                  ),
                  _buildSection(
                    title: 'Notifications',
                    children: [
                      SwitchListTile(
                        title: const Text('Notifications Push'),
                        subtitle: const Text('Recevoir des notifications push'),
                        value: true,
                        onChanged: (value) {
                          // Toggle push notifications
                        },
                      ),
                    ],
                  ),
                  _buildSection(
                    title: 'Developer Tools',
                    children: [
                      ListTile(
                        title: const Text('Test Notifications'),
                        subtitle: const Text('Send and receive test notifications'),
                        leading: const Icon(Icons.notifications_active),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.go('/settings/notification-test'),
                      ),
                      ListTile(
                        title: const Text('Test Analytics'),
                        subtitle: const Text('Log and view analytics events'),
                        leading: const Icon(Icons.analytics_outlined),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.go('/settings/analytics-test'),
                      ),
                      ListTile(
                        title: const Text('Test Error Handling'),
                        subtitle: const Text('Trigger and record errors'),
                        leading: const Icon(Icons.error_outline),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.go('/settings/error-test'),
                      ),
                      ListTile(
                        title: const Text('Test App Updates'),
                        subtitle: const Text('Check for app updates'),
                        leading: const Icon(Icons.system_update_outlined),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.go('/settings/update-test'),
                      ),
                      ListTile(
                        title: const Text('Test Offline Mode'),
                        subtitle: const Text('Create and sync data offline'),
                        leading: const Icon(Icons.wifi_off_outlined),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.go('/settings/offline-test'),
                      ),
                      ListTile(
                        title: const Text('Test Cache d\'Images'),
                        subtitle: const Text('Gérer le cache d\'images'),
                        leading: const Icon(Icons.image_outlined),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.go('/settings/image-cache-test'),
                      ),
                      ListTile(
                        title: const Text('Test Haptique'),
                        subtitle: const Text('Tester les retours haptiques'),
                        leading: const Icon(Icons.vibration),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.go('/settings/haptic-test'),
                      ),
                    ],
                  ),
                  _buildSection(
                    title: 'À propos',
                    children: [
                      ListTile(
                        title: const Text('Version'),
                        subtitle: Text('${_packageInfo?.version} (${_packageInfo?.buildNumber})'),
                        leading: const Icon(Icons.info_outline),
                      ),
                    ],
                  ),
                ],
              ),
    );
  }

  Widget _buildSection({required String title, required List<Widget> children}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            title,
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        ...children,
        const SizedBox(height: 8),
      ],
    );
  }

  void _showThemeDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Choose Theme'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children:
                AppThemeMode.values.map((mode) {
                  return RadioListTile<AppThemeMode>(
                    title: Text(mode.name),
                    value: mode,
                    groupValue: ref.read(themeProvider),
                    onChanged: (value) {
                      if (value != null) {
                        ref.read(themeProvider.notifier).setThemeMode(value);
                        Navigator.pop(context);
                      }
                    },
                    secondary: Icon(mode.icon),
                  );
                }).toList(),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ],
        );
      },
    );
  }
}
