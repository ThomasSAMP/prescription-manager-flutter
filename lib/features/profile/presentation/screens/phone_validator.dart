class PhoneValidator {
  static bool isValidPhoneNumber(String phoneNumber) {
    // Format international requis : +33123456789
    final phoneRegex = RegExp(r'^\+[1-9]\d{1,14}$');
    return phoneRegex.hasMatch(phoneNumber);
  }

  static String? validatePhoneNumber(String? value) {
    if (value == null || value.isEmpty) {
      return null; // Autoriser un numéro vide
    }

    if (!isValidPhoneNumber(value)) {
      return 'Format invalide. Utilisez le format international (ex: +33612345678)';
    }

    return null;
  }
}
