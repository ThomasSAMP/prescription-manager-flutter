// lib/features/prescriptions/presentation/screens/medicament_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/services/navigation_service.dart';
import '../../../../shared/widgets/app_bar.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../models/medicament_model.dart';
import '../../providers/medicament_provider.dart';
import '../../providers/ordonnance_provider.dart';

class MedicamentDetailScreen extends ConsumerWidget {
  final String ordonnanceId;
  final String medicamentId;

  const MedicamentDetailScreen({super.key, required this.ordonnanceId, required this.medicamentId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final navigationService = getIt<NavigationService>();
    final ordonnance = ref.watch(ordonnanceByIdProvider(ordonnanceId));
    final medicament = ref.watch(medicamentByIdProvider(medicamentId));
    final canPop = context.canPop();

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
                        () => navigationService.navigateTo(context, '/ordonnances/$ordonnanceId'),
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
                      () => navigationService.navigateTo(context, '/ordonnances/$ordonnanceId'),
                )
                : null,
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed:
                () => navigationService.navigateTo(
                  context,
                  '/ordonnances/$ordonnanceId/medicaments/$medicamentId/edit',
                ),
            tooltip: 'Modifier le médicament',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
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
                          '/ordonnances/$ordonnanceId/medicaments/$medicamentId/edit',
                        ),
                    icon: Icons.edit,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: AppButton(
                    text: 'Retour à l\'ordonnance',
                    onPressed:
                        () => navigationService.navigateTo(context, '/ordonnances/$ordonnanceId'),
                    type: AppButtonType.outline,
                  ),
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
