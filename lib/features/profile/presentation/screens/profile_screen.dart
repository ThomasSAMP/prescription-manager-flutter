import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/services/auth_service.dart';
import '../../../../core/services/navigation_service.dart';
import '../../../../shared/widgets/app_bar.dart';
import '../../../../shared/widgets/app_button.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _authService = getIt<AuthService>();
  final _navigationService = getIt<NavigationService>();
  bool _isLoading = false;

  Future<void> _signOut() async {
    setState(() {
      _isLoading = true;
    });

    try {
      await _authService.signOut();
      if (mounted) {
        _navigationService.navigateTo(context, '/login');
      }
    } catch (e) {
      if (mounted) {
        _navigationService.showSnackBar(context, message: 'Erreur de déconnexion: $e');
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
    final user = _authService.currentUser;

    if (_isLoading) {
      return Scaffold(appBar: const AppBarWidget(title: 'Profile'), body: _buildLoadingState());
    }

    if (user == null) {
      return Scaffold(
        appBar: const AppBarWidget(title: 'Profile'),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('Vous devez être connecté pour voir votre profile'),
              const SizedBox(height: 16),
              AppButton(
                text: 'Se connecter',
                onPressed: () => _navigationService.navigateTo(context, '/login'),
                icon: Icons.login,
                fullWidth: false,
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBarWidget(
        title: 'Profile',
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _signOut,
            tooltip: 'Se déconnecter',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SizedBox(height: 16),
          CircleAvatar(
            radius: 50,
            backgroundColor: Theme.of(context).colorScheme.primary,
            child: Text(
              user.email?.substring(0, 1).toUpperCase() ?? '?',
              style: const TextStyle(fontSize: 40, color: Colors.white),
            ),
          ),
          const SizedBox(height: 24),
          Center(
            child: Text(user.email ?? 'Aucun email', style: Theme.of(context).textTheme.titleLarge),
          ),
          const SizedBox(height: 8),
          Center(child: Text('User ID: ${user.uid}', style: Theme.of(context).textTheme.bodySmall)),
          const SizedBox(height: 8),
          Center(
            child: Text(
              'Numéro de tel: ${user.phoneNumber != null ? (user.phoneNumber!.isNotEmpty ? user.phoneNumber : 'Aucun tel') : 'Aucun tel'}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          const SizedBox(height: 32),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Se déconnecter'),
            onTap: _signOut,
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Déconnexion en cours...'),
        ],
      ),
    );
  }
}
