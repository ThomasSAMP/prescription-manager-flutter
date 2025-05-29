import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/services/navigation_service.dart';
import '../../../../shared/widgets/app_bar.dart';
import '../../../../shared/widgets/app_button.dart';

class NotificationMonitoringScreen extends ConsumerStatefulWidget {
  const NotificationMonitoringScreen({super.key});

  @override
  ConsumerState<NotificationMonitoringScreen> createState() => _NotificationMonitoringScreenState();
}

class _NotificationMonitoringScreenState extends ConsumerState<NotificationMonitoringScreen> {
  final _navigationService = getIt<NavigationService>();
  bool _isLoading = false;
  Map<String, dynamic>? _stats;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final callable = FirebaseFunctions.instanceFor(
        region: 'europe-west1',
      ).httpsCallable('getNotificationStats');

      final result = await callable.call({'days': 7});

      setState(() {
        _stats = result.data;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Erreur lors du chargement des statistiques: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final canPop = context.canPop();

    return Scaffold(
      appBar: AppBarWidget(
        title: 'Monitoring Notifications',
        showBackButton: canPop,
        leading:
            !canPop
                ? IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => _navigationService.navigateTo(context, '/settings'),
                )
                : null,
      ),
      body:
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _errorMessage != null
              ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(_errorMessage!),
                    const SizedBox(height: 16),
                    AppButton(text: 'Réessayer', onPressed: _loadStats, fullWidth: false),
                  ],
                ),
              )
              : _buildStatsView(),
    );
  }

  Widget _buildStatsView() {
    if (_stats == null) return const Center(child: Text('Aucune donnée disponible'));

    final health = _stats!['currentHealth'] as Map<String, dynamic>?;
    final stats = _stats!['stats'] as List<dynamic>? ?? [];

    return RefreshIndicator(
      onRefresh: _loadStats,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // État de santé actuel
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'État du système',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  if (health != null) ...[
                    Row(
                      children: [
                        Icon(
                          _getHealthIcon(health['status']),
                          color: _getHealthColor(health['status']),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _getHealthText(health['status']),
                          style: TextStyle(
                            color: _getHealthColor(health['status']),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Notification d\'aujourd\'hui: ${health['todayNotificationSent'] ? 'Envoyée' : 'Non envoyée'}',
                    ),
                    Text('Logs récents: ${health['recentLogsCount']}'),
                  ],
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Statistiques des 7 derniers jours
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Statistiques (7 derniers jours)',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  if (stats.isNotEmpty)
                    ...stats.take(7).whereType<Map<String, dynamic>>().map(_buildStatItem)
                  else
                    const Text('Aucune statistique disponible'),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Boutons d'action
          AppButton(text: 'Actualiser', onPressed: _loadStats, icon: Icons.refresh),
        ],
      ),
    );
  }

  Widget _buildStatItem(Map<String, dynamic> stat) {
    final date = stat['date'] as String;
    final newCritical = stat['newCritical'] as int? ?? 0;
    final newWarning = stat['newWarning'] as int? ?? 0;
    final newExpired = stat['newExpired'] as int? ?? 0;
    final notificationSent = stat['notificationSent'] as bool? ?? false;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(DateFormat('dd/MM').format(DateTime.parse(date))),
          Row(
            children: [
              if (newExpired > 0) Text('🚨$newExpired '),
              if (newCritical > 0) Text('⚠️$newCritical '),
              if (newWarning > 0) Text('🟡$newWarning '),
              Icon(
                notificationSent ? Icons.check_circle : Icons.error,
                color: notificationSent ? Colors.green : Colors.red,
                size: 16,
              ),
            ],
          ),
        ],
      ),
    );
  }

  IconData _getHealthIcon(String status) {
    switch (status) {
      case 'healthy':
        return Icons.check_circle;
      case 'warning':
        return Icons.warning;
      case 'error':
        return Icons.error;
      default:
        return Icons.help;
    }
  }

  Color _getHealthColor(String status) {
    switch (status) {
      case 'healthy':
        return Colors.green;
      case 'warning':
        return Colors.orange;
      case 'error':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _getHealthText(String status) {
    switch (status) {
      case 'healthy':
        return 'Système opérationnel';
      case 'warning':
        return 'Attention requise';
      case 'error':
        return 'Problème détecté';
      default:
        return 'État inconnu';
    }
  }
}
