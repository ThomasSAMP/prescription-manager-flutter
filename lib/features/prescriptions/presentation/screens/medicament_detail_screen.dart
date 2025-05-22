import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/services/conflict_service.dart';
import '../../../../core/services/navigation_service.dart';
import '../../../../core/services/sync_service.dart';
import '../../../../shared/providers/sync_status_provider.dart';
import '../../../../shared/widgets/app_bar.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../models/medicament_model.dart';
import '../../providers/medicament_provider.dart';
import '../../providers/ordonnance_provider.dart';
import '../../repositories/medicament_repository.dart';

class MedicamentDetailScreen extends ConsumerStatefulWidget {
  final String ordonnanceId;
  final String medicamentId;

  const MedicamentDetailScreen({super.key, required this.ordonnanceId, required this.medicamentId});

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

    if (_isLoading) {
      return Scaffold(
        appBar: AppBarWidget(
          title: 'Détails du médicament',
          showBackButton: canPop,
          leading:
              !canPop
                  ? IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed:
                        () => navigationService.navigateTo(
                          context,
                          '/ordonnances/$widget.ordonnanceId',
                        ),
                  )
                  : null,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (ordonnance == null || medicament == null) {
      return Scaffold(
        appBar: AppBarWidget(
          title: 'Détails du médicament',
          showBackButton: canPop,
          leading:
              !canPop
                  ? IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed:
                        () => navigationService.navigateTo(
                          context,
                          '/ordonnances/${widget.ordonnanceId}',
                        ),
                  )
                  : null,
        ),
        body: const Center(child: Text('Médicament non trouvé')),
      );
    }

    final expirationStatus = medicament.getExpirationStatus();
    final dateFormat = DateFormat('dd/MM/yyyy');

    return Scaffold(
      appBar: AppBarWidget(
        title: medicament.name,
        showBackButton: canPop,
        leading:
            !canPop
                ? IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed:
                      () => navigationService.navigateTo(
                        context,
                        '/ordonnances/${widget.ordonnanceId}',
                      ),
                )
                : null,
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed:
                () => navigationService.navigateTo(
                  context,
                  '/ordonnances/${widget.ordonnanceId}/medicaments/${widget.medicamentId}/edit',
                ),
            tooltip: 'Modifier le médicament',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshData,
        child: ListView(
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
                                    style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  if (medicament.dosage != null &&
                                      medicament.dosage!.isNotEmpty) ...[
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
                        if (medicament.instructions != null &&
                            medicament.instructions!.isNotEmpty) ...[
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
        ),
      ),
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
