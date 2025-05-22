import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:injectable/injectable.dart';

import '../../shared/repositories/user_repository.dart';
import '../di/injection.dart';
import '../errors/auth_exception.dart';
import '../utils/logger.dart';
import 'error_service.dart';

@lazySingleton
class AuthService {
  final FirebaseAuth _firebaseAuth;
  final UserRepository _userRepository;
  late final ErrorService _errorService;

  // Durée de validité de la session (8 heures par défaut)
  static const sessionDuration = Duration(hours: 8);

  // Timestamp de la dernière authentification réussie
  DateTime? _lastAuthTime;

  // Timer pour vérifier périodiquement l'authentification
  Timer? _authCheckTimer;

  AuthService(this._firebaseAuth, this._userRepository) {
    // Initialiser _errorService via getIt
    _errorService = getIt<ErrorService>();

    // Écouter les changements d'état d'authentification
    _firebaseAuth.authStateChanges().listen(_handleAuthStateChange);
  }

  void _handleAuthStateChange(User? user) {
    if (user != null) {
      // Utilisateur connecté
      _lastAuthTime = DateTime.now();
      _startAuthCheckTimer();
    } else {
      // Utilisateur déconnecté
      _lastAuthTime = null;
      _stopAuthCheckTimer();
    }
  }

  void _startAuthCheckTimer() {
    _stopAuthCheckTimer(); // Arrêter le timer existant s'il y en a un

    // Vérifier l'authentification toutes les 15 minutes
    _authCheckTimer = Timer.periodic(const Duration(minutes: 15), (timer) {
      _checkSessionValidity();
    });
  }

  void _stopAuthCheckTimer() {
    _authCheckTimer?.cancel();
    _authCheckTimer = null;
  }

  Future<void> _checkSessionValidity() async {
    // Vérifier si la session a expiré
    if (_lastAuthTime != null && DateTime.now().difference(_lastAuthTime!) > sessionDuration) {
      AppLogger.info('Session expired, signing out user');
      await signOut();
    }

    // Vérifier si le token est toujours valide
    try {
      await _firebaseAuth.currentUser?.getIdToken(true);
    } catch (e) {
      AppLogger.error('Error refreshing token', e);
      await signOut();
    }
  }

  Stream<User?> get authStateChanges => _firebaseAuth.authStateChanges();

  User? get currentUser => _firebaseAuth.currentUser;

  bool get isAuthenticated => currentUser != null;

  bool get isSessionValid {
    if (_lastAuthTime == null || currentUser == null) return false;
    return DateTime.now().difference(_lastAuthTime!) <= sessionDuration;
  }

  Future<User?> signInWithEmailAndPassword(String email, String password) async {
    try {
      final userCredential = await _firebaseAuth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      // Définir les informations de l'utilisateur pour Crashlytics
      final user = userCredential.user;
      if (user != null) {
        await _errorService.setUserInfo(user.uid, email: user.email, name: user.displayName);
        _lastAuthTime = DateTime.now();
      }

      return user;
    } on FirebaseAuthException catch (e, stackTrace) {
      AppLogger.error('Sign in error', e, stackTrace);
      await _errorService.recordError(
        e,
        stackTrace,
        reason: 'Sign in error: ${e.code}',
        information: ['email: $email'],
      );
      throw AuthException.fromFirebaseAuthException(e);
    } catch (e, stackTrace) {
      AppLogger.error('Sign in error', e, stackTrace);
      await _errorService.recordError(
        e,
        stackTrace,
        reason: 'Sign in error: unexpected',
        information: ['email: $email'],
      );
      throw AuthException(message: 'An unexpected error occurred');
    }
  }

  Future<void> signOut() async {
    try {
      // Réinitialiser les informations de l'utilisateur pour Crashlytics
      await _errorService.setUserInfo('anonymous');

      _lastAuthTime = null;
      _stopAuthCheckTimer();

      await _firebaseAuth.signOut();
    } catch (e, stackTrace) {
      AppLogger.error('Sign out error', e, stackTrace);
      await _errorService.recordError(e, stackTrace, reason: 'Sign out error');
      throw AuthException(message: 'Failed to sign out');
    }
  }

  // Méthode pour rafraîchir manuellement la session
  Future<void> refreshSession() async {
    try {
      final user = _firebaseAuth.currentUser;
      if (user != null) {
        await user.getIdToken(true);
        _lastAuthTime = DateTime.now();
      }
    } catch (e, stackTrace) {
      AppLogger.error('Error refreshing session', e, stackTrace);
      await _errorService.recordError(e, stackTrace, reason: 'Session refresh error');
      throw AuthException(message: 'Failed to refresh session');
    }
  }
}
