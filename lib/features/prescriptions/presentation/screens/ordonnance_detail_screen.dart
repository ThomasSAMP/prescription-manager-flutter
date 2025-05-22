import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/services/conflict_service.dart';
import '../../../../core/services/navigation_service.dart';
import '../../../../core/services/sync_service.dart';
import '../../../../shared/providers/sync_status_provider.dart';
import '../../../../shared/widgets/app_bar.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../models/medicament_model.dart';
import '../../models/ordonnance_model.dart';
import '../../providers/medicament_provider.dart';
import '../../providers/ordonnance_provider.dart';
import '../../repositories/medicament_repository.dart';
import '../widgets/medicament_list_item.dart';

class OrdonnanceDetailScreen extends ConsumerStatefulWidget {
  final String ordonnanceId;

  const OrdonnanceDetailScreen({super.key, required this.ordonnanceId});

  @override
  ConsumerState<OrdonnanceDetailScreen> createState() => _OrdonnanceDetailScreenState();
}

class _OrdonnanceDetailScreenState extends ConsumerState<OrdonnanceDetailScreen> {
  final _navigationService = getIt<NavigationService>();
  bool _isDeleting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });
  }

  Future<void> _loadData() async {
    try {
      // Charger d'abord l'ordonnance
      await ref.read(ordonnanceProvider.notifier).loadItems();

      // Ensuite, charger uniquement les médicaments pour cette ordonnance
      if (mounted) {
        final repository = getIt<MedicamentRepository>();
        final medicaments = await repository.getMedicamentsByOrdonnance(widget.ordonnanceId);

        // Mettre à jour le provider avec ces médicaments spécifiques
        ref
            .read(allMedicamentsProvider.notifier)
            .updateItemsForOrdonnance(widget.ordonnanceId, medicaments);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erreur lors du chargement des données: $e')));
      }
    }
  }

  // Méthode pour le pull-to-refresh
  Future<void> _refreshData() async {
    try {
      // Mettre à jour l'état de synchronisation
      ref.read(syncStatusProvider.notifier).setSyncing();

      // Synchroniser les données avec le serveur
      await getIt<SyncService>().syncAll();

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Données synchronisées avec succès')));
      }
    } catch (e) {
      // Marquer l'erreur
      ref.read(syncStatusProvider.notifier).setError('Erreur: ${e.toString()}');

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erreur lors de la synchronisation: $e')));
      }
    }
  }

  void _addMedicament(OrdonnanceModel ordonnance) {
    _navigationService.navigateTo(context, '/ordonnances/${ordonnance.id}/medicaments/new');
  }

  Future<void> _deleteOrdonnance(OrdonnanceModel ordonnance) async {
    final confirmed = await _navigationService.showConfirmationDialog(
      context,
      title: 'Supprimer l\'ordonnance',
      message: 'Êtes-vous sûr de vouloir supprimer cette ordonnance et tous ses médicaments ?',
      confirmText: 'Supprimer',
      cancelText: 'Annuler',
    );

    if (confirmed != true) return;

    setState(() {
      _isDeleting = true;
    });

    try {
      final repository = ref.read(ordonnanceRepositoryProvider);
      await repository.deleteOrdonnance(ordonnance.id);

      // Recharger les ordonnances
      await ref.read(ordonnanceProvider.notifier).loadItems();

      if (mounted) {
        _navigationService.navigateTo(context, '/ordonnances');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erreur lors de la suppression: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isDeleting = false;
        });
      }
    }
  }

  /// Gère un conflit détecté lors de la synchronisation
  Future<void> _handleConflict(OrdonnanceModel local, OrdonnanceModel remote) async {
    final conflictService = getIt<ConflictService>();

    final resolvedOrdonnance = await conflictService.resolveManually(context, local, remote);

    if (resolvedOrdonnance != null) {
      // Rafraîchir les données
      await _refreshData();
    }
  }

  @override
  Widget build(BuildContext context) {
    final canPop = context.canPop();
    final ordonnanceAsync = ref.watch(ordonnanceByIdProvider(widget.ordonnanceId));
    final medicaments = ref.watch(medicamentsByOrdonnanceProvider(widget.ordonnanceId));
    final isLoading =
        ref.watch(ordonnanceProvider).isLoading || ref.watch(allMedicamentsProvider).isLoading;

    if (ordonnanceAsync == null && !isLoading) {
      return Scaffold(
        appBar: AppBarWidget(
          title: 'Détails de l\'ordonnance',
          showBackButton: canPop,
          leading:
              !canPop
                  ? IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => _navigationService.navigateTo(context, '/ordonnances'),
                  )
                  : null,
        ),
        body: const Center(child: Text('Ordonnance non trouvée')),
      );
    }

    return Scaffold(
      appBar: AppBarWidget(
        title: ordonnanceAsync != null ? ordonnanceAsync.patientName : 'Chargement...',
        showBackButton: canPop,
        leading:
            !canPop
                ? IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => _navigationService.navigateTo(context, '/ordonnances'),
                )
                : null,
        actions:
            ordonnanceAsync != null
                ? [
                  IconButton(
                    icon: const Icon(Icons.delete),
                    onPressed: _isDeleting ? null : () => _deleteOrdonnance(ordonnanceAsync),
                    tooltip: 'Supprimer l\'ordonnance',
                  ),
                ]
                : null,
      ),
      body:
          isLoading || _isDeleting
              ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text(_isDeleting ? 'Suppression en cours...' : 'Chargement...'),
                  ],
                ),
              )
              : RefreshIndicator(
                onRefresh: _refreshData,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildPatientInfo(ordonnanceAsync!),
                        const SizedBox(height: 24),
                        _buildMedicamentsList(medicaments, ordonnanceAsync),
                      ],
                    ),
                  ],
                ),
              ),
      floatingActionButton:
          ordonnanceAsync != null && !isLoading && !_isDeleting
              ? FloatingActionButton(
                onPressed: () => _addMedicament(ordonnanceAsync),
                tooltip: 'Ajouter un médicament',
                child: const Icon(Icons.add),
              )
              : null,
    );
  }

  Widget _buildPatientInfo(OrdonnanceModel ordonnance) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: Colors.blue,
                  child: Text(
                    ordonnance.patientName.isNotEmpty
                        ? ordonnance.patientName[0].toUpperCase()
                        : '?',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ordonnance.patientName,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Créée le ${_formatDate(ordonnance.createdAt)}',
                        style: TextStyle(
                          color: Theme.of(context).textTheme.bodySmall?.color,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMedicamentsList(List<MedicamentModel> medicaments, OrdonnanceModel ordonnance) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Médicaments', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            TextButton.icon(
              onPressed: () => _addMedicament(ordonnance),
              icon: const Icon(Icons.add),
              label: const Text('Ajouter'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        medicaments.isEmpty
            ? _buildEmptyMedicamentsList()
            : ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: medicaments.length,
              separatorBuilder: (context, index) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final medicament = medicaments[index];
                return MedicamentListItem(
                  medicament: medicament,
                  onTap:
                      () =>
                          context.go('/ordonnances/${ordonnance.id}/medicaments/${medicament.id}'),
                );
              },
            ),
      ],
    );
  }

  Widget _buildEmptyMedicamentsList() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.medication_outlined, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text(
              'Aucun médicament',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text('Ajoutez des médicaments à cette ordonnance', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            AppButton(
              text: 'Ajouter un médicament',
              onPressed:
                  () => _addMedicament(ref.read(ordonnanceByIdProvider(widget.ordonnanceId))!),
              icon: Icons.add,
              fullWidth: false,
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }
}
