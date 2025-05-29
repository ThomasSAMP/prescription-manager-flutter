import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/services/auth_service.dart';
import '../../../../core/services/navigation_service.dart';
import '../../../../shared/providers/auth_provider.dart';
import '../../../../shared/repositories/user_repository.dart';
import '../../../../shared/widgets/app_bar.dart';
import '../../../../shared/widgets/app_button.dart';
import 'phone_validator.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _authService = getIt<AuthService>();
  final _navigationService = getIt<NavigationService>();
  final _userRepository = getIt<UserRepository>();
  final _phoneController = TextEditingController();
  bool _isLoading = false;
  final bool _isSmsEnabled = true;

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

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

  Future<void> _updatePhoneNumber() async {
    final userModelAsyncValue = ref.read(currentUserProvider);

    if (userModelAsyncValue is AsyncData && userModelAsyncValue.value != null) {
      final userModel = userModelAsyncValue.value!;

      final phoneNumber = await showDialog<String>(
        context: context,
        builder: (context) {
          _phoneController.text = userModel.phoneNumber ?? '';
          String? errorText;

          return StatefulBuilder(
            builder: (context, setState) {
              return AlertDialog(
                title: const Text('Mettre à jour le numéro de téléphone'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: _phoneController,
                      decoration: InputDecoration(
                        labelText: 'Numéro de téléphone',
                        hintText: 'Ex: +33612345678',
                        errorText: errorText,
                      ),
                      keyboardType: TextInputType.phone,
                      onChanged: (value) {
                        setState(() {
                          errorText = PhoneValidator.validatePhoneNumber(value);
                        });
                      },
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Utilisez le format international avec indicatif pays (ex: +33612345678)',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Annuler'),
                  ),
                  TextButton(
                    onPressed:
                        errorText == null
                            ? () => Navigator.of(context).pop(_phoneController.text)
                            : null,
                    child: const Text('Enregistrer'),
                  ),
                ],
              );
            },
          );
        },
      );

      if (phoneNumber != null) {
        setState(() {
          _isLoading = true;
        });

        try {
          final updatedUser = userModel.copyWith(
            phoneNumber: phoneNumber,
            updatedAt: DateTime.now(),
          );

          await _userRepository.updateUser(updatedUser);

          // Rafraîchir les données utilisateur
          ref.refresh(currentUserProvider);

          if (mounted) {
            _navigationService.showSnackBar(context, message: 'Numéro de téléphone mis à jour');
          }
        } catch (e) {
          if (mounted) {
            _navigationService.showSnackBar(context, message: 'Erreur lors de la mise à jour: $e');
          }
        } finally {
          if (mounted) {
            setState(() {
              _isLoading = false;
            });
          }
        }
      }
    }
  }

  Future<void> _toggleSmsNotifications() async {
    final userModelAsyncValue = ref.read(currentUserProvider);

    if (userModelAsyncValue is AsyncData && userModelAsyncValue.value != null) {
      final userModel = userModelAsyncValue.value!;

      setState(() {
        _isLoading = true;
      });

      try {
        final updatedUser = userModel.copyWith(
          smsNotificationsEnabled: !userModel.smsNotificationsEnabled,
          updatedAt: DateTime.now(),
        );

        await _userRepository.updateUser(updatedUser);

        // Rafraîchir les données utilisateur
        ref.refresh(currentUserProvider);

        if (mounted) {
          _navigationService.showSnackBar(
            context,
            message: 'Préférences de notification mises à jour',
          );
        }
      } catch (e) {
        if (mounted) {
          _navigationService.showSnackBar(context, message: 'Erreur lors de la mise à jour: $e');
        }
      } finally {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authUser = _authService.currentUser;
    final userModelAsyncValue = ref.watch(currentUserProvider);

    if (_isLoading) {
      return Scaffold(appBar: const AppBarWidget(title: 'Profile'), body: _buildLoadingState());
    }

    if (authUser == null) {
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

    return userModelAsyncValue.when(
      data: (userModel) {
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
                  userModel?.email.substring(0, 1).toUpperCase() ?? '?',
                  style: const TextStyle(fontSize: 40, color: Colors.white),
                ),
              ),
              const SizedBox(height: 24),
              Center(
                child: Text(
                  userModel?.email ?? 'Aucun email',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  'User ID: ${userModel?.id}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              const SizedBox(height: 24),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.phone),
                title: const Text('Numéro de téléphone'),
                subtitle: Text(userModel?.phoneNumber ?? 'Non défini'),
                trailing: const Icon(Icons.edit),
                onTap: _updatePhoneNumber,
              ),
              SwitchListTile(
                secondary: const Icon(Icons.sms),
                title: const Text('Notifications SMS'),
                subtitle: const Text('Recevoir des SMS en cas d\'échec des notifications push'),
                value: userModel?.smsNotificationsEnabled ?? true,
                onChanged: (_) => _toggleSmsNotifications(),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.logout),
                title: const Text('Se déconnecter'),
                onTap: _signOut,
              ),
            ],
          ),
        );
      },
      loading:
          () => const Scaffold(
            appBar: AppBarWidget(title: 'Profile'),
            body: Center(child: CircularProgressIndicator()),
          ),
      error:
          (error, stackTrace) => Scaffold(
            appBar: const AppBarWidget(title: 'Profile'),
            body: Center(child: Text('Erreur lors du chargement du profil: $error')),
          ),
    );
  }

  Widget _buildLoadingState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [CircularProgressIndicator(), SizedBox(height: 16)],
      ),
    );
  }
}
