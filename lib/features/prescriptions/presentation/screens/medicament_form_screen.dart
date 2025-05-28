import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/services/navigation_service.dart';
import '../../../../core/utils/logger.dart';
import '../../../../shared/widgets/app_bar.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/app_text_field.dart';
import '../../../../shared/widgets/shimmer_loading.dart';
import '../../../../shared/widgets/shimmer_placeholder.dart';
import '../../models/medicament_model.dart';
import '../../providers/medicament_provider.dart';
import '../../providers/ordonnance_provider.dart';

class MedicamentFormScreen extends ConsumerStatefulWidget {
  final String ordonnanceId;
  final String? medicamentId; // Null pour création, non-null pour modification

  const MedicamentFormScreen({super.key, required this.ordonnanceId, this.medicamentId});

  @override
  ConsumerState<MedicamentFormScreen> createState() => _MedicamentFormScreenState();
}

class _MedicamentFormScreenState extends ConsumerState<MedicamentFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _dosageController = TextEditingController();
  final _instructionsController = TextEditingController();
  final _expirationDateController = TextEditingController();
  final _navigationService = getIt<NavigationService>();

  DateTime _expirationDate = DateTime.now().add(const Duration(days: 30));
  bool _isLoading = false;
  bool _isInitialLoading = true; // État de chargement initial
  String? _errorMessage;
  bool _isEditing = false;
  MedicamentModel? _existingMedicament;

  @override
  void initState() {
    super.initState();
    _isEditing = widget.medicamentId != null;

    // Initialiser la date d'expiration pour un nouveau médicament
    _expirationDateController.text = DateFormat('dd/MM/yyyy').format(_expirationDate);

    // Déclencher le chargement après le premier rendu
    if (_isEditing) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _triggerLoading();
      });
    } else {
      // Si création, pas besoin de charger des données
      setState(() {
        _isInitialLoading = false;
      });
    }
  }

  // Méthode pour déclencher le chargement sans bloquer l'UI
  void _triggerLoading() {
    // Charger le médicament en arrière-plan
    _loadMedicament().then((_) {
      if (mounted) {
        setState(() {
          _isInitialLoading = false;
        });
      }
    });
  }

  // Méthode pour charger le médicament
  Future<void> _loadMedicament() async {
    try {
      // Charger les médicaments si ce n'est pas déjà fait
      await ref.read(allMedicamentsProvider.notifier).loadItems();

      // Récupérer le médicament existant
      final medicament = ref.read(medicamentByIdProvider(widget.medicamentId!));

      if (medicament != null && mounted) {
        _existingMedicament = medicament;

        // Remplir les champs avec les données existantes
        _nameController.text = medicament.name;
        if (medicament.dosage != null) {
          _dosageController.text = medicament.dosage!;
        }
        if (medicament.instructions != null) {
          _instructionsController.text = medicament.instructions!;
        }
        _expirationDate = medicament.expirationDate;
        _expirationDateController.text = DateFormat('dd/MM/yyyy').format(_expirationDate);
      }
    } catch (e) {
      AppLogger.error('Error loading medicament', e);
      if (mounted) {
        setState(() {
          _errorMessage = 'Erreur lors du chargement du médicament: $e';
        });
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _dosageController.dispose();
    _instructionsController.dispose();
    _expirationDateController.dispose();
    super.dispose();
  }

  Future<void> _selectDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _expirationDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)), // 5 ans
    );

    if (picked != null && picked != _expirationDate) {
      setState(() {
        _expirationDate = picked;
        _expirationDateController.text = DateFormat('dd/MM/yyyy').format(_expirationDate);
      });
    }
  }

  Future<void> _saveMedicament() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final repository = ref.read(medicamentRepositoryProvider);

      if (_isEditing && _existingMedicament != null) {
        // Mettre à jour un médicament existant
        await repository.updateMedicament(
          medicament: _existingMedicament!,
          newName: _nameController.text.trim(),
          newExpirationDate: _expirationDate,
          newDosage:
              _dosageController.text.trim().isNotEmpty ? _dosageController.text.trim() : null,
          newInstructions:
              _instructionsController.text.trim().isNotEmpty
                  ? _instructionsController.text.trim()
                  : null,
        );
      } else {
        // Créer un nouveau médicament
        await repository.createMedicament(
          ordonnanceId: widget.ordonnanceId,
          name: _nameController.text.trim(),
          expirationDate: _expirationDate,
          dosage: _dosageController.text.trim().isNotEmpty ? _dosageController.text.trim() : null,
          instructions:
              _instructionsController.text.trim().isNotEmpty
                  ? _instructionsController.text.trim()
                  : null,
        );
      }

      // Déclencher le rechargement sans attendre (pour ne pas bloquer la navigation)
      unawaited(ref.read(allMedicamentsProvider.notifier).loadItems());

      if (mounted) {
        _navigationService.navigateTo(context, '/ordonnances/${widget.ordonnanceId}');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Erreur lors de l\'enregistrement du médicament: $e';
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

  Future<void> _deleteMedicament() async {
    if (!_isEditing || _existingMedicament == null) return;

    final confirmed = await _navigationService.showConfirmationDialog(
      context,
      title: 'Supprimer le médicament',
      message: 'Êtes-vous sûr de vouloir supprimer ce médicament ?',
      confirmText: 'Supprimer',
      cancelText: 'Annuler',
    );

    if (confirmed != true) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final repository = ref.read(medicamentRepositoryProvider);
      await repository.deleteMedicament(_existingMedicament!.id);

      // Déclencher le rechargement sans attendre (pour ne pas bloquer la navigation)
      unawaited(ref.read(allMedicamentsProvider.notifier).loadItems());

      if (mounted) {
        _navigationService.navigateTo(context, '/ordonnances/${widget.ordonnanceId}');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Erreur lors de la suppression du médicament: $e';
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

    // Seulement récupérer l'ordonnance si pas en chargement initial
    final ordonnance =
        _isInitialLoading ? null : ref.watch(ordonnanceByIdProvider(widget.ordonnanceId));

    return Scaffold(
      appBar: AppBarWidget(
        title: _isEditing ? 'Modifier le médicament' : 'Nouveau médicament',
        showBackButton: canPop,
        leading:
            !canPop
                ? IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed:
                      () => _navigationService.navigateTo(
                        context,
                        '/ordonnances/${widget.ordonnanceId}',
                      ),
                )
                : null,
        actions:
            _isEditing && !_isInitialLoading
                ? [
                  IconButton(
                    icon: const Icon(Icons.delete),
                    onPressed: _isLoading ? null : _deleteMedicament,
                    tooltip: 'Supprimer le médicament',
                  ),
                ]
                : null,
      ),
      body:
          _isInitialLoading
              ? _buildLoadingState()
              : ordonnance == null
              ? const Center(child: Text('Ordonnance non trouvée'))
              : SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Ordonnance de ${ordonnance.patientName}',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'Informations du médicament',
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
                        controller: _nameController,
                        label: 'Nom du médicament',
                        hint: 'Entrez le nom du médicament',
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Le nom du médicament est requis';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      AppTextField(
                        controller: _dosageController,
                        label: 'Dosage (optionnel)',
                        hint: 'Ex: 500mg, 2 comprimés par jour',
                      ),
                      const SizedBox(height: 16),
                      AppTextField(
                        controller: _instructionsController,
                        label: 'Instructions (optionnel)',
                        hint: 'Ex: Prendre après les repas',
                        maxLines: 3,
                      ),
                      const SizedBox(height: 16),
                      AppTextField(
                        controller: _expirationDateController,
                        label: 'Date d\'expiration',
                        hint: 'Sélectionnez une date',
                        readOnly: true,
                        onTap: () => _selectDate(context),
                        suffix: const Icon(Icons.calendar_today),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'La date d\'expiration est requise';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 24),
                      AppButton(
                        text:
                            _isEditing ? 'Enregistrer les modifications' : 'Ajouter le médicament',
                        onPressed: _isLoading ? null : _saveMedicament,
                        isLoading: _isLoading,
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
      children: [
        // Skeleton pour le titre de l'ordonnance
        const ShimmerLoading(
          isLoading: true,
          child: ShimmerPlaceholder(width: double.infinity, height: 18),
        ),
        const SizedBox(height: 24),
        // Skeleton pour le titre du formulaire
        const ShimmerLoading(isLoading: true, child: ShimmerPlaceholder(width: 200, height: 18)),
        const SizedBox(height: 16),
        // Skeleton pour les champs du formulaire
        ...List.generate(
          4,
          (index) => const Padding(
            padding: EdgeInsets.only(bottom: 16.0),
            child: ShimmerLoading(
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
          ),
        ),
        const SizedBox(height: 24),
        // Skeleton pour le bouton
        const ShimmerLoading(
          isLoading: true,
          child: ShimmerPlaceholder(width: double.infinity, height: 48),
        ),
      ],
    );
  }
}
