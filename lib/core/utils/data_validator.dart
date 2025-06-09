class DataValidator {
  // Validation des noms de patients
  static String? validatePatientName(String? name) {
    if (name == null || name.trim().isEmpty) {
      return 'Le nom du patient est requis';
    }

    if (name.trim().length < 2) {
      return 'Le nom doit contenir au moins 2 caractères';
    }

    if (name.trim().length > 100) {
      return 'Le nom ne peut pas dépasser 100 caractères';
    }

    // Vérifier les caractères autorisés (lettres, espaces, tirets, apostrophes)
    final validNameRegex = RegExp(r"^[a-zA-ZÀ-ÿ\s\-'\.]+$");
    if (!validNameRegex.hasMatch(name.trim())) {
      return 'Le nom contient des caractères non autorisés';
    }

    return null;
  }

  // Validation des noms de médicaments
  static String? validateMedicamentName(String? name) {
    if (name == null || name.trim().isEmpty) {
      return 'Le nom du médicament est requis';
    }

    if (name.trim().length < 2) {
      return 'Le nom doit contenir au moins 2 caractères';
    }

    if (name.trim().length > 200) {
      return 'Le nom ne peut pas dépasser 200 caractères';
    }

    return null;
  }

  // Validation des dosages
  static String? validateDosage(String? dosage) {
    if (dosage == null || dosage.trim().isEmpty) {
      return null; // Optionnel
    }

    if (dosage.trim().length > 100) {
      return 'Le dosage ne peut pas dépasser 100 caractères';
    }

    return null;
  }

  // Validation des instructions
  static String? validateInstructions(String? instructions) {
    if (instructions == null || instructions.trim().isEmpty) {
      return null; // Optionnel
    }

    if (instructions.trim().length > 500) {
      return 'Les instructions ne peuvent pas dépasser 500 caractères';
    }

    return null;
  }

  // Validation des dates d'expiration
  static String? validateExpirationDate(DateTime? date) {
    if (date == null) {
      return 'La date d\'expiration est requise';
    }

    final now = DateTime.now();
    final minDate = now.subtract(const Duration(days: 365)); // 1 an dans le passé max
    final maxDate = now.add(const Duration(days: 365 * 10)); // 10 ans dans le futur max

    if (date.isBefore(minDate)) {
      return 'La date ne peut pas être antérieure à 1 an';
    }

    if (date.isAfter(maxDate)) {
      return 'La date ne peut pas être supérieure à 10 ans';
    }

    return null;
  }

  // Validation des emails
  static String? validateEmail(String? email) {
    if (email == null || email.trim().isEmpty) {
      return 'L\'email est requis';
    }

    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    if (!emailRegex.hasMatch(email.trim())) {
      return 'Format d\'email invalide';
    }

    return null;
  }

  // Validation des mots de passe
  static String? validatePassword(String? password) {
    if (password == null || password.isEmpty) {
      return 'Le mot de passe est requis';
    }

    if (password.length < 8) {
      return 'Le mot de passe doit contenir au moins 8 caractères';
    }

    if (password.length > 128) {
      return 'Le mot de passe ne peut pas dépasser 128 caractères';
    }

    // Vérifier la complexité
    final hasUppercase = password.contains(RegExp(r'[A-Z]'));
    final hasLowercase = password.contains(RegExp(r'[a-z]'));
    final hasDigits = password.contains(RegExp(r'[0-9]'));

    if (!hasUppercase || !hasLowercase || !hasDigits) {
      return 'Le mot de passe doit contenir au moins une majuscule, une minuscule et un chiffre';
    }

    return null;
  }

  // Sanitisation des données
  static String sanitizeString(String input) {
    return input.trim().replaceAll(RegExp(r'\s+'), ' '); // Remplacer multiples espaces par un seul
  }
}
