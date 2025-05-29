import 'package:firebase_auth/firebase_auth.dart';

class AuthException implements Exception {
  final String code;
  final String message;

  AuthException({this.code = 'unknown', required this.message});

  factory AuthException.fromFirebaseAuthException(FirebaseAuthException e) {
    String message;

    switch (e.code) {
      case 'invalid-email':
        message = 'L\'adresse email n\'est pas valide.';
        break;
      case 'user-disabled':
        message = 'Cet utilisateur a été désactivé.';
        break;
      case 'user-not-found':
        message = 'Aucun utilisateur trouvé avec cet email.';
        break;
      case 'wrong-password':
        message = 'Mot de passe incorrect.';
        break;
      case 'email-already-in-use':
        message = 'Cet e-mail est déjà utilisé par un autre compte.';
        break;
      case 'weak-password':
        message = 'Le mot de passe est trop faible.';
        break;
      case 'operation-not-allowed':
        message = 'Cette opération n\'est pas autorisée.';
        break;
      case 'too-many-requests':
        message = 'Trop de requêtes. Veuillez réessayer plus tard..';
        break;
      case 'invalid-credential':
        message = 'L\'email ou le mot de passe est incorrect';
        break;
      default:
        message = e.message ?? 'Une erreur inconnue s\'est produite.';
    }

    return AuthException(code: e.code, message: message);
  }

  @override
  String toString() => '$message (code: $code)';
}
