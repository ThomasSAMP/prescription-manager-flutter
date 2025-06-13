import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/services/conflict_service.dart';
import '../../../../core/services/navigation_service.dart';
import '../../../../core/utils/logger.dart';
import '../../../../core/utils/refresh_helper.dart';
import '../../../../shared/widgets/app_bar.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/shimmer_loading.dart';
import '../../../../shared/widgets/shimmer_placeholder.dart';
import '../../models/medicament_model.dart';
import '../../models/ordonnance_model.dart';
import '../../providers/medicament_provider.dart';
import '../../providers/ordonnance_provider.dart';
import '../../repositories/medicament_repository.dart';
import '../widgets/medicament_list_item.dart';
import '../widgets/medicament_skeleton_item.dart';

class OrdonnanceDetailScreen extends ConsumerStatefulWidget {
  final String ordonnanceId;
  final bool fromNotifications;

  const OrdonnanceDetailScreen({
    super.key,
    required this.ordonnanceId,
    this.fromNotifications = false,
  });

  @override
  ConsumerState<OrdonnanceDetailScreen> createState() => _OrdonnanceDetailScreenState();
}

class _OrdonnanceDetailScreenState extends ConsumerState<OrdonnanceDetailScreen> {
  final _navigationService = getIt<NavigationService>();
  bool _isDeleting = false;
  bool _isLocalLoading = true; // État de chargement local

  @override
  void initState() {
    super.initState();
    // Déclencher le chargement après le premier rendu
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _triggerLoading();
    });
  }

  // Méthode pour déclencher le chargement sans bloquer l'UI
  void _triggerLoading() {
    // Déclencher le chargement des ordonnances sans await
    unawaited(ref.read(ordonnanceProvider.notifier).loadItems());

    // Charger les médicaments en arrière-plan
    unawaited(
      _loadMedicaments().then((_) {
        if (mounted) {
          setState(() {
            _isLocalLoading = false;
          });
        }
      }),
    );
  }

  // Méthode pour charger les médicaments
  Future<void> _loadMedicaments() async {
    try {
      final repository = getIt<MedicamentRepository>();
      final medicaments = await repository.getMedicamentsByOrdonnance(widget.ordonnanceId);

      if (mounted) {
        // Mettre à jour le provider avec ces médicaments spécifiques
        ref
            .read(allMedicamentsProvider.notifier)
            .updateItemsForOrdonnance(widget.ordonnanceId, medicaments);
      }
    } catch (e) {
      AppLogger.error('Error loading medicaments for ordonnance', e);
      // Ne pas modifier _isLocalLoading ici pour continuer à afficher le skeleton
    }
  }

  // Méthode pour le pull-to-refresh
  Future<void> _refreshData() async {
    setState(() {
      _isLocalLoading = true;
    });

    await RefreshHelper.refreshData(
      context: context,
      ref: ref,
      onlineRefresh: () async {
        // Ici nous voulons attendre
        await ref.read(ordonnanceProvider.notifier).forceReload();
        await _loadMedicaments();
      },
      offlineRefresh: () async {
        // Ici aussi nous voulons attendre
        await ref.read(ordonnanceProvider.notifier).loadItems();
        await _loadMedicaments();
      },
    );

    if (mounted) {
      setState(() {
        _isLocalLoading = false;
      });
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

      // Ici nous voulons attendre le rechargement avant de naviguer
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

    // Éviter les watchers multiples en mode loading
    if (_isLocalLoading || _isDeleting) {
      return Scaffold(
        appBar: AppBarWidget(
          title: 'Chargement...',
          showBackButton: canPop,
          leading:
              !canPop
                  ? IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed:
                        () => _navigationService.navigateTo(
                          context,
                          widget.fromNotifications ? '/notifications' : '/ordonnances',
                        ),
                  )
                  : null,
        ),
        body: _buildLoadingState(),
      );
    }

    // Watcher les providers seulement quand nécessaire
    final ordonnanceAsync = ref.watch(ordonnanceByIdProvider(widget.ordonnanceId));
    final medicaments = ref.watch(medicamentsByOrdonnanceProvider(widget.ordonnanceId));

    return Scaffold(
      appBar: AppBarWidget(
        title: ordonnanceAsync != null ? ordonnanceAsync.patientName : 'Chargement...',
        showBackButton: canPop,
        leading:
            !canPop
                ? IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed:
                      () => _navigationService.navigateTo(
                        context,
                        widget.fromNotifications ? '/notifications' : '/ordonnances',
                      ),
                )
                : null,
        onBackPressed:
            widget.fromNotifications && canPop
                ? () => _navigationService.navigateTo(context, '/notifications')
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
      body: RefreshIndicator(
        onRefresh: _refreshData,
        child:
            _isDeleting
                ? _buildLoadingState()
                : ordonnanceAsync == null
                ? const Center(child: Text('Ordonnance non trouvée'))
                : _buildOrdonnanceDetails(ordonnanceAsync, medicaments),
      ),
      floatingActionButton:
          ordonnanceAsync != null && !_isDeleting
              ? FloatingActionButton(
                onPressed: () => _addMedicament(ordonnanceAsync),
                tooltip: 'Ajouter un médicament',
                child: const Icon(Icons.add),
              )
              : null,
    );
  }

  Widget _buildLoadingState() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Skeleton pour les infos du patient
        ShimmerLoading(
          isLoading: true,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 10),
            decoration: const BoxDecoration(
              border: Border(left: BorderSide(color: Colors.white, width: 4)),
            ),
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Row(
                children: [
                  // Avatar placeholder
                  CircleAvatar(radius: 24, backgroundColor: Colors.white),
                  SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ShimmerPlaceholder(width: 150, height: 18),
                        SizedBox(height: 8),
                        ShimmerPlaceholder(width: 100, height: 12),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        // Titre des médicaments
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Médicaments', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            TextButton.icon(
              onPressed: null,
              icon: const Icon(Icons.add),
              label: const Text('Ajouter'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // Skeletons pour les médicaments
        ...List.generate(
          3,
          (index) => const Padding(
            padding: EdgeInsets.only(bottom: 8.0),
            child: ShimmerLoading(isLoading: true, child: MedicamentSkeletonItem()),
          ),
        ),
      ],
    );
  }

  Widget _buildOrdonnanceDetails(OrdonnanceModel ordonnance, List<MedicamentModel> medicaments) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildPatientInfo(ordonnance),
            const SizedBox(height: 24),
            _buildMedicamentsList(medicaments, ordonnance),
          ],
        ),
      ],
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
