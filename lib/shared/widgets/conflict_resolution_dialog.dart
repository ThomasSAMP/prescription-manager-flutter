import 'package:flutter/material.dart';

import '../../core/models/syncable_model.dart';

enum ConflictChoice { useLocal, useRemote, merge }

class ConflictResolutionDialog<T extends SyncableModel> extends StatelessWidget {
  final T localVersion;
  final T remoteVersion;
  final String title;
  final String message;
  final Widget Function(T) buildLocalDetails;
  final Widget Function(T) buildRemoteDetails;
  final Widget Function(T, T)? buildMergePreview;

  const ConflictResolutionDialog({
    super.key,
    required this.localVersion,
    required this.remoteVersion,
    required this.title,
    required this.message,
    required this.buildLocalDetails,
    required this.buildRemoteDetails,
    this.buildMergePreview,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            const Text('Votre version:', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            buildLocalDetails(localVersion),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            const Text('Version du serveur:', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            buildRemoteDetails(remoteVersion),
            if (buildMergePreview != null) ...[
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),
              const Text('Version fusionnée:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              buildMergePreview!(localVersion, remoteVersion),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(ConflictChoice.useLocal),
          child: const Text('Utiliser ma version'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(ConflictChoice.useRemote),
          child: const Text('Utiliser version serveur'),
        ),
        if (buildMergePreview != null)
          TextButton(
            onPressed: () => Navigator.of(context).pop(ConflictChoice.merge),
            child: const Text('Fusionner'),
          ),
      ],
    );
  }
}
