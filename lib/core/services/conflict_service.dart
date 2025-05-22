import 'package:flutter/material.dart';
import 'package:injectable/injectable.dart';

import '../../features/prescriptions/models/medicament_model.dart';
import '../../features/prescriptions/models/ordonnance_model.dart';
import '../../features/prescriptions/repositories/medicament_repository.dart';
import '../../features/prescriptions/repositories/ordonnance_repository.dart';
import '../../shared/widgets/conflict_resolution_dialog.dart';
import '../models/syncable_model.dart';
import '../utils/conflict_resolver.dart';
import '../utils/logger.dart';
import '../utils/model_merger.dart';

@lazySingleton
class ConflictService {
  final ConflictResolver _resolver;
  final OrdonnanceRepository _ordonnanceRepository;
  final MedicamentRepository _medicamentRepository;

  ConflictService(this._ordonnanceRepository, this._medicamentRepository)
    : _resolver = ConflictResolver(strategy: ConflictResolutionStrategy.newerWins);

  /// Détecte s'il y a un conflit entre deux versions d'un modèle
  bool hasConflict<T extends SyncableModel>(T local, T remote) {
    return _resolver.hasConflict(local, remote);
  }

  /// Résout automatiquement un conflit entre deux versions d'un modèle
  T resolveAutomatically<T extends SyncableModel>(T local, T remote) {
    return _resolver.resolve(local, remote);
  }

  /// Affiche un dialogue pour résoudre manuellement un conflit
  Future<T?> resolveManually<T extends SyncableModel>(
    BuildContext context,
    T local,
    T remote,
  ) async {
    if (local is OrdonnanceModel && remote is OrdonnanceModel) {
      return _resolveOrdonnanceConflict(context, local, remote) as T?;
    } else if (local is MedicamentModel && remote is MedicamentModel) {
      return _resolveMedicamentConflict(context, local, remote) as T?;
    } else {
      // Pour les autres types, résoudre automatiquement
      AppLogger.warning(
        'Manual conflict resolution not implemented for this model type, resolving automatically',
      );
      return resolveAutomatically(local, remote);
    }
  }

  /// Résout manuellement un conflit entre deux versions d'une ordonnance
  Future<OrdonnanceModel?> _resolveOrdonnanceConflict(
    BuildContext context,
    OrdonnanceModel local,
    OrdonnanceModel remote,
  ) async {
    final choice = await showDialog<ConflictChoice>(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => ConflictResolutionDialog<OrdonnanceModel>(
            localVersion: local,
            remoteVersion: remote,
            title: 'Conflit détecté',
            message:
                'Cette ordonnance a été modifiée à la fois localement et sur le serveur. Comment souhaitez-vous résoudre ce conflit?',
            buildLocalDetails:
                (ordonnance) => _buildOrdonnanceDetails(context, ordonnance, 'locale'),
            buildRemoteDetails:
                (ordonnance) => _buildOrdonnanceDetails(context, ordonnance, 'serveur'),
          ),
    );

    if (choice == null) {
      // L'utilisateur a annulé
      return null;
    }

    // Résoudre le conflit selon le choix de l'utilisateur
    return _ordonnanceRepository.resolveConflictManually(local, remote, choice);
  }

  /// Résout manuellement un conflit entre deux versions d'un médicament
  Future<MedicamentModel?> _resolveMedicamentConflict(
    BuildContext context,
    MedicamentModel local,
    MedicamentModel remote,
  ) async {
    final choice = await showDialog<ConflictChoice>(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => ConflictResolutionDialog<MedicamentModel>(
            localVersion: local,
            remoteVersion: remote,
            title: 'Conflit détecté',
            message:
                'Ce médicament a été modifié à la fois localement et sur le serveur. Comment souhaitez-vous résoudre ce conflit?',
            buildLocalDetails:
                (medicament) => _buildMedicamentDetails(context, medicament, 'locale'),
            buildRemoteDetails:
                (medicament) => _buildMedicamentDetails(context, medicament, 'serveur'),
            buildMergePreview:
                (local, remote) => _buildMedicamentMergePreview(context, local, remote),
          ),
    );

    if (choice == null) {
      // L'utilisateur a annulé
      return null;
    }

    // Résoudre le conflit selon le choix de l'utilisateur
    return _medicamentRepository.resolveConflictManually(local, remote, choice);
  }

  /// Construit un widget pour afficher les détails d'une ordonnance
  Widget _buildOrdonnanceDetails(BuildContext context, OrdonnanceModel ordonnance, String source) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Nom du patient: ${ordonnance.patientName}'),
            Text('Dernière mise à jour: ${_formatDate(ordonnance.updatedAt)}'),
            Text('Version: ${ordonnance.version}'),
            Text('Source: $source'),
          ],
        ),
      ),
    );
  }

  /// Construit un widget pour afficher les détails d'un médicament
  Widget _buildMedicamentDetails(BuildContext context, MedicamentModel medicament, String source) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Nom: ${medicament.name}'),
            Text('Dosage: ${medicament.dosage ?? "Non spécifié"}'),
            Text('Date d\'expiration: ${_formatDate(medicament.expirationDate)}'),
            Text('Instructions: ${medicament.instructions ?? "Non spécifiées"}'),
            Text('Dernière mise à jour: ${_formatDate(medicament.updatedAt)}'),
            Text('Version: ${medicament.version}'),
            Text('Source: $source'),
          ],
        ),
      ),
    );
  }

  /// Construit un widget pour afficher l'aperçu de la fusion de deux médicaments
  Widget _buildMedicamentMergePreview(
    BuildContext context,
    MedicamentModel local,
    MedicamentModel remote,
  ) {
    // Créer une version fusionnée
    final merged = ModelMerger.merge(local, remote);

    return Card(
      color: Colors.green.withOpacity(0.1),
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Nom: ${merged.name}'),
            Text('Dosage: ${merged.dosage ?? "Non spécifié"}'),
            Text('Date d\'expiration: ${_formatDate(merged.expirationDate)}'),
            Text('Instructions: ${merged.instructions ?? "Non spécifiées"}'),
            Text('Dernière mise à jour: ${_formatDate(merged.updatedAt)}'),
            Text('Version: ${merged.version}'),
            const Text('Source: Fusion'),
          ],
        ),
      ),
    );
  }

  /// Formate une date pour l'affichage
  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}
