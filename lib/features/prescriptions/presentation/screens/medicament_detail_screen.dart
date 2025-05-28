import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/services/conflict_service.dart';
import '../../../../core/services/navigation_service.dart';
import '../../../../core/utils/refresh_helper.dart';
import '../../../../shared/widgets/app_bar.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/shimmer_loading.dart';
import '../../models/medicament_model.dart';
import '../../models/ordonnance_model.dart';
import '../../providers/medicament_provider.dart';
import '../../providers/ordonnance_provider.dart';
import '../../repositories/medicament_repository.dart';

class MedicamentDetailScreen extends ConsumerStatefulWidget {
  final String ordonnanceId;
  final String medicamentId;
  final bool fromNotifications;

  const MedicamentDetailScreen({
    super.key,
    required this.ordonnanceId,
    required this.medicamentId,
    this.fromNotifications = false,
  });

  @override
  ConsumerState<MedicamentDetailScreen> createState() => _MedicamentDetailScreenState();
}

class _MedicamentDetailScreenState extends ConsumerState<MedicamentDetailScreen> {
  final navigationService = getIt<NavigationService>();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });
  }

  Future<void> _loadData() async {
    try {
      setState(() {
        _isLoading = true;
      });

      // Charger l'ordonnance
      await ref.read(ordonnanceProvider.notifier).loadItems();

      // Charger le médicament spécifique
      final repository = getIt<MedicamentRepository>();
      final medicament = await repository.getMedicamentById(widget.medicamentId);

      if (medicament != null) {
        // Mettre à jour le provider
        ref.read(allMedicamentsProvider.notifier).updateSingleMedicament(medicament);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erreur lors du chargement des données: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // Méthode pour le pull-to-refresh
  Future<void> _refreshData() async {
    await RefreshHelper.refreshData(
      context: context,
      ref: ref,
      onlineRefresh: () async {
        await ref.read(ordonnanceProvider.notifier).loadItems();

        // Recharger le médicament spécifique
        if (mounted) {
          final repository = getIt<MedicamentRepository>();
          final medicament = await repository.getMedicamentById(widget.medicamentId);

          if (medicament != null) {
            // Mettre à jour le provider avec ce médicament spécifique
            ref.read(allMedicamentsProvider.notifier).updateSingleMedicament(medicament);
          }
        }
      },
      offlineRefresh: () async {
        await ref.read(ordonnanceProvider.notifier).loadItems();

        // Recharger le médicament spécifique
        if (mounted) {
          final repository = getIt<MedicamentRepository>();
          final medicament = await repository.getMedicamentById(widget.medicamentId);

          if (medicament != null) {
            // Mettre à jour le provider avec ce médicament spécifique
            ref.read(allMedicamentsProvider.notifier).updateSingleMedicament(medicament);
          }
        }
      },
    );
  }

  /// Gère un conflit détecté lors de la synchronisation
  Future<void> _handleConflict(MedicamentModel local, MedicamentModel remote) async {
    final conflictService = getIt<ConflictService>();

    final resolvedMedicament = await conflictService.resolveManually(context, local, remote);

    if (resolvedMedicament != null) {
      // Rafraîchir les données
      await _refreshData();
    }
  }

  @override
  Widget build(BuildContext context) {
    final navigationService = getIt<NavigationService>();
    final ordonnance = ref.watch(ordonnanceByIdProvider(widget.ordonnanceId));
    final medicament = ref.watch(medicamentByIdProvider(widget.medicamentId));
    final canPop = context.canPop();

    return Scaffold(
      appBar: AppBarWidget(
        title: medicament != null ? medicament.name : 'Détails du médicament',
        showBackButton: canPop,
        leading:
            !canPop
                ? IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed:
                      () => navigationService.navigateTo(
                        context,
                        widget.fromNotifications
                            ? '/notifications'
                            : '/ordonnances/${widget.ordonnanceId}',
                      ),
                )
                : null,
        onBackPressed:
            widget.fromNotifications && canPop
                ? () => navigationService.navigateTo(context, '/notifications')
                : null,
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed:
                medicament == null
                    ? null
                    : () => navigationService.navigateTo(
                      context,
                      '/ordonnances/${widget.ordonnanceId}/medicaments/${widget.medicamentId}/edit',
                    ),
            tooltip: 'Modifier le médicament',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshData,
        child:
            _isLoading
                ? _buildLoadingState()
                : (ordonnance == null || medicament == null)
                ? const Center(child: Text('Médicament non trouvé'))
                : _buildMedicamentDetails(context, ordonnance, medicament),
      ),
    );
  }

  Widget _buildLoadingState() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Skeleton pour le titre de l'ordonnance
        ShimmerLoading(
          isLoading: true,
          child: Container(
            width: double.infinity,
            height: 18,
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4)),
          ),
        ),
        const SizedBox(height: 24),
        // Skeleton pour la carte du médicament
        ShimmerLoading(
          isLoading: true,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 10),
            decoration: const BoxDecoration(
              border: Border(left: BorderSide(color: Colors.white, width: 4)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: double.infinity,
                              height: 20,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              width: 150,
                              height: 16,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 16),
                  Container(
                    width: 150,
                    height: 16,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Container(
                        width: 24,
                        height: 24,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        width: 120,
                        height: 16,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: 180,
                    height: 16,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        // Skeleton pour les boutons
        Row(
          children: [
            Expanded(
              child: ShimmerLoading(
                isLoading: true,
                child: Container(
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: ShimmerLoading(
                isLoading: true,
                child: Container(
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMedicamentDetails(
    BuildContext context,
    OrdonnanceModel ordonnance,
    MedicamentModel medicament,
  ) {
    final expirationStatus = medicament.getExpirationStatus();
    final dateFormat = DateFormat('dd/MM/yyyy');

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Ordonnance de ${ordonnance.patientName}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            Card(
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
                          backgroundColor:
                              expirationStatus.needsAttention
                                  ? expirationStatus.getColor().withOpacity(0.2)
                                  : Colors.blue.withOpacity(0.2),
                          child: Icon(
                            Icons.medication_outlined,
                            color:
                                expirationStatus.needsAttention
                                    ? expirationStatus.getColor()
                                    : Colors.blue,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                medicament.name,
                                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                              ),
                              if (medicament.dosage != null && medicament.dosage!.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  'Dosage: ${medicament.dosage}',
                                  style: const TextStyle(fontSize: 16),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 16),
                    _buildExpirationInfo(context, medicament, expirationStatus, dateFormat),
                    if (medicament.instructions != null && medicament.instructions!.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      const Divider(),
                      const SizedBox(height: 16),
                      const Text(
                        'Instructions',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(medicament.instructions!, style: const TextStyle(fontSize: 16)),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: AppButton(
                    text: 'Modifier',
                    onPressed:
                        () => navigationService.navigateTo(
                          context,
                          '/ordonnances/${widget.ordonnanceId}/medicaments/${widget.medicamentId}/edit',
                        ),
                    icon: Icons.edit,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: AppButton(
                    text: 'Retour à l\'ordonnance',
                    onPressed:
                        () => navigationService.navigateTo(
                          context,
                          '/ordonnances/${widget.ordonnanceId}',
                        ),
                    type: AppButtonType.outline,
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildExpirationInfo(
    BuildContext context,
    MedicamentModel medicament,
    ExpirationStatus status,
    DateFormat dateFormat,
  ) {
    // Code existant inchangé
    final daysUntilExpiration = medicament.expirationDate.difference(DateTime.now()).inDays;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Date d\'expiration',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Icon(status.getIcon(), color: status.getColor(), size: 24),
            const SizedBox(width: 8),
            Text(
              dateFormat.format(medicament.expirationDate),
              style: TextStyle(
                fontSize: 16,
                color: status.needsAttention ? status.getColor() : null,
                fontWeight: status.needsAttention ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          _getExpirationMessage(daysUntilExpiration, status),
          style: TextStyle(color: status.needsAttention ? status.getColor() : null),
        ),
      ],
    );
  }

  String _getExpirationMessage(int daysUntilExpiration, ExpirationStatus status) {
    if (daysUntilExpiration < 0) {
      return 'Expiré depuis ${-daysUntilExpiration} jour${-daysUntilExpiration > 1 ? 's' : ''}';
    } else if (daysUntilExpiration == 0) {
      return 'Expire aujourd\'hui !';
    } else {
      return 'Expire dans $daysUntilExpiration jour${daysUntilExpiration > 1 ? 's' : ''}';
    }
  }
}
