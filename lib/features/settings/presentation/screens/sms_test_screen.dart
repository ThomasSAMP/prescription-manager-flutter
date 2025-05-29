import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/services/navigation_service.dart';
import '../../../../shared/widgets/app_bar.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/app_text_field.dart';

class SMSTestScreen extends ConsumerStatefulWidget {
  const SMSTestScreen({super.key});

  @override
  ConsumerState<SMSTestScreen> createState() => _SMSTestScreenState();
}

class _SMSTestScreenState extends ConsumerState<SMSTestScreen> {
  final _navigationService = getIt<NavigationService>();
  final _phoneController = TextEditingController(text: '+33');
  final _formKey = GlobalKey<FormState>();

  bool _isLoading = false;
  String? _statusMessage;
  Map<String, dynamic>? _lastResult;

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _testSMS() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _statusMessage = null;
      _lastResult = null;
    });

    try {
      final callable = FirebaseFunctions.instanceFor(
        region: 'europe-west1',
      ).httpsCallable('testSMSService');

      final result = await callable.call({'phoneNumber': _phoneController.text.trim()});

      setState(() {
        _lastResult = result.data;
        if (result.data['success'] == true) {
          _statusMessage = 'SMS envoyé avec succès !';
        } else {
          _statusMessage = 'Échec de l\'envoi SMS: ${result.data['error'] ?? 'Erreur inconnue'}';
        }
      });
    } catch (e) {
      setState(() {
        _statusMessage = 'Erreur lors du test SMS: $e';
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
        title: 'Test SMS',
        showBackButton: canPop,
        leading:
            !canPop
                ? IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => _navigationService.navigateTo(context, '/settings'),
                )
                : null,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Test du service SMS',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Testez l\'envoi de SMS via Twilio. Assurez-vous d\'utiliser un numéro de téléphone au format international.',
              ),
              const SizedBox(height: 24),

              AppTextField(
                controller: _phoneController,
                label: 'Numéro de téléphone',
                hint: '+33123456789',
                keyboardType: TextInputType.phone,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Veuillez saisir un numéro de téléphone';
                  }
                  if (!RegExp(r'^\+[1-9]\d{1,14}$').hasMatch(value)) {
                    return 'Format invalide. Utilisez le format international (+33123456789)';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),

              AppButton(
                text: 'Envoyer SMS de test',
                onPressed: _isLoading ? null : _testSMS,
                isLoading: _isLoading,
                icon: Icons.sms,
              ),

              if (_statusMessage != null) ...[
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color:
                        _statusMessage!.contains('succès')
                            ? Theme.of(context).colorScheme.primaryContainer
                            : Theme.of(context).colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _statusMessage!,
                    style: TextStyle(
                      color:
                          _statusMessage!.contains('succès')
                              ? Theme.of(context).colorScheme.onPrimaryContainer
                              : Theme.of(context).colorScheme.onErrorContainer,
                    ),
                  ),
                ),
              ],

              if (_lastResult != null) ...[
                const SizedBox(height: 24),
                const Text(
                  'Détails du résultat',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildResultRow('Succès', _lastResult!['success'].toString()),
                      if (_lastResult!['messageId'] != null)
                        _buildResultRow('ID du message', _lastResult!['messageId']),
                      if (_lastResult!['status'] != null)
                        _buildResultRow('Statut', _lastResult!['status']),
                      if (_lastResult!['error'] != null)
                        _buildResultRow('Erreur', _lastResult!['error']),

                      const SizedBox(height: 8),
                      const Text('État du service:', style: TextStyle(fontWeight: FontWeight.bold)),
                      if (_lastResult!['serviceStatus'] != null) ...[
                        _buildResultRow(
                          'Service activé',
                          _lastResult!['serviceStatus']['enabled'].toString(),
                        ),
                        _buildResultRow('Fournisseur', _lastResult!['serviceStatus']['provider']),
                        _buildResultRow(
                          'Numéro expéditeur',
                          _lastResult!['serviceStatus']['fromNumber'],
                        ),
                      ],
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 16),

              const Text(
                'Instructions',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                '• Utilisez le format international (+33 pour la France)\n'
                '• Le SMS de test confirme que Twilio fonctionne\n'
                '• En cas d\'échec, vérifiez votre configuration Twilio\n'
                '• Les SMS de fallback ne sont envoyés qu\'après 3 échecs de notifications push\n'
                '• Chaque SMS coûte environ 0,02€ avec Twilio',
              ),

              const SizedBox(height: 24),

              Card(
                color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.info_outline, color: Theme.of(context).colorScheme.primary),
                          const SizedBox(width: 8),
                          const Text(
                            'Informations Twilio',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Twilio offre 15\$ de crédit gratuit (≈750 SMS). '
                        'Consultez votre console Twilio pour suivre votre consommation.',
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResultRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text('$label:', style: const TextStyle(fontWeight: FontWeight.w500)),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
