import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/services/auth_service.dart';
import '../../../../core/services/haptic_service.dart';
import '../../../../core/services/navigation_service.dart';
import '../../../../core/utils/data_validator.dart';
import '../../../../shared/widgets/app_bar.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/app_text_field.dart';
import '../../../../shared/widgets/shimmer_loading.dart';
import '../../../../shared/widgets/shimmer_placeholder.dart';
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
  bool _hasValidationErrors = false;

  @override
  void initState() {
    super.initState();
    _patientNameController.addListener(_validateForm);
  }

  void _validateForm() {
    final nameError = DataValidator.validatePatientName(_patientNameController.text);
    setState(() {
      _hasValidationErrors = nameError != null;
    });
  }

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

      final sanitizedName = DataValidator.sanitizeString(_patientNameController.text.trim());

      final ordonnance = await repository.createOrdonnance(sanitizedName, userId);

      // Déclencher le rechargement sans attendre (pour ne pas bloquer la navigation)
      unawaited(getIt<HapticService>().feedback(HapticFeedbackType.success));
      unawaited(ref.read(ordonnanceProvider.notifier).loadItems());

      if (mounted) {
        _navigationService.navigateTo(context, '/ordonnances/${ordonnance.id}');
      }
    } catch (e) {
      unawaited(getIt<HapticService>().feedback(HapticFeedbackType.error));
      if (mounted) {
        setState(() {
          _errorMessage = 'Erreur lors de la création de l\'ordonnance: $e';
        });
      }
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
      body:
          _isLoading
              ? _buildLoadingState()
              : SingleChildScrollView(
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
                        validator: DataValidator.validatePatientName,
                        suffix:
                            _patientNameController.text.isNotEmpty
                                ? Icon(
                                  _hasValidationErrors ? Icons.error : Icons.check_circle,
                                  color: _hasValidationErrors ? Colors.red : Colors.green,
                                )
                                : null,
                      ),
                      const SizedBox(height: 24),
                      AppButton(
                        text: 'Créer l\'ordonnance',
                        onPressed: _hasValidationErrors || _isLoading ? null : _createOrdonnance,
                        isLoading: _isLoading,
                        type: _hasValidationErrors ? AppButtonType.outline : AppButtonType.primary,
                      ),
                    ],
                  ),
                ),
              ),
    );
  }

  Widget _buildLoadingState() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: const [
        // Skeleton pour le titre
        ShimmerLoading(isLoading: true, child: ShimmerPlaceholder(width: 200, height: 18)),
        SizedBox(height: 16),
        // Skeleton pour le champ de texte
        ShimmerLoading(
          isLoading: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ShimmerPlaceholder(width: 100, height: 14),
              SizedBox(height: 8),
              ShimmerPlaceholder(width: double.infinity, height: 48),
            ],
          ),
        ),
        SizedBox(height: 24),
        // Skeleton pour le bouton
        ShimmerLoading(
          isLoading: true,
          child: ShimmerPlaceholder(width: double.infinity, height: 48),
        ),
      ],
    );
  }
}
