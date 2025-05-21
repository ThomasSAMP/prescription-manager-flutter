import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/services/auth_service.dart';
import '../../../../core/services/navigation_service.dart';
import '../../../../shared/widgets/app_bar.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/app_text_field.dart';
import '../../providers/ordonnance_provider.dart';

class CreateOrdonnanceScreen extends ConsumerStatefulWidget {
  const CreateOrdonnanceScreen({super.key});

  @override
  ConsumerState<CreateOrdonnanceScreen> createState() => _CreateOrdonnanceScreenState();
}

class _CreateOrdonnanceScreenState extends ConsumerState<CreateOrdonnanceScreen> {
  final _formKey = GlobalKey<FormState>();
  final _patientNameController = TextEditingController();
  final _navigationService = getIt<NavigationService>();
  final _authService = getIt<AuthService>();

  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _patientNameController.dispose();
    super.dispose();
  }

  Future<void> _createOrdonnance() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final repository = ref.read(ordonnanceRepositoryProvider);
      final userId = _authService.currentUser?.uid;

      if (userId == null) {
        throw Exception('Utilisateur non connecté');
      }

      final ordonnance = await repository.createOrdonnance(
        _patientNameController.text.trim(),
        userId,
      );

      // Recharger les ordonnances
      await ref.read(ordonnanceProvider.notifier).loadItems();

      if (mounted) {
        _navigationService.navigateTo(context, '/ordonnances/${ordonnance.id}');
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Erreur lors de la création de l\'ordonnance: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final canPop = context.canPop();

    return Scaffold(
      appBar: AppBarWidget(
        title: 'Nouvelle Ordonnance',
        showBackButton: canPop,
        leading:
            !canPop
                ? IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => _navigationService.navigateTo(context, '/ordonnances'),
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
                'Informations du patient',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              if (_errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _errorMessage!,
                    style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              AppTextField(
                controller: _patientNameController,
                label: 'Nom du patient',
                hint: 'Entrez le nom complet du patient',
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Le nom du patient est requis';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),
              AppButton(
                text: 'Créer l\'ordonnance',
                onPressed: _isLoading ? null : _createOrdonnance,
                isLoading: _isLoading,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
