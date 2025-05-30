import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../shared/widgets/app_bar.dart';
import '../../../../shared/widgets/app_button.dart';

class NotFoundScreen extends StatelessWidget {
  final String? path;

  const NotFoundScreen({super.key, this.path});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AppBarWidget(title: 'Page introuvable', showBackButton: false),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 80, color: Colors.red),
              const SizedBox(height: 24),
              Text('Page introuvable', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 16),
              Text(
                path != null
                    ? 'La page\n"$path"\nn\'a pas pu être trouvée.'
                    : 'La page demandée n\'a pas pu être trouvée.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 32),
              AppButton(
                text: 'Retour à l\'accueil',
                onPressed: () => context.go('/ordonnances'),
                icon: Icons.home,
                fullWidth: false,
                padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 15),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
