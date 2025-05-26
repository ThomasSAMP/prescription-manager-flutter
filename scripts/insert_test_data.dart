import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:prescription_manager/core/config/firebase_options.dart';

const String sharedKeyBase64 = '4TsOqlhDt2Rnjn2V+R5m1D5hqn0+2IaJcneRXl5DQxg=';
const String sharedIVBase64 = '0/AIedqHmLs/F1YQHb9qGg==';

// Fonction de chiffrement
String encryptData(String plainText) {
  final keyBytes = base64.decode(sharedKeyBase64);
  final key = encrypt.Key(Uint8List.fromList(keyBytes));
  final encrypter = encrypt.Encrypter(encrypt.AES(key));

  final ivBytes = base64.decode(sharedIVBase64);
  final iv = encrypt.IV(Uint8List.fromList(ivBytes));

  final encrypted = encrypter.encrypt(plainText, iv: iv);
  return encrypted.base64;
}

void main() async {
  // Initialiser Flutter
  WidgetsFlutterBinding.ensureInitialized();

  // Initialiser Firebase
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  final firestore = FirebaseFirestore.instance;
  final random = Random();

  // Liste de noms de patients
  final patientNames = [
    'Jean Dupont',
    'Marie Martin',
    'Pierre Durand',
    'Sophie Lefebvre',
    'Thomas Bernard',
    'Camille Petit',
    'Nicolas Moreau',
    'Emma Lambert',
    'Lucas Robert',
    'Chloé Richard',
    'Hugo Dubois',
    'Léa Bertrand',
    'Louis Morel',
    'Manon Simon',
    'Jules Laurent',
    'Jade Leroy',
    'Raphaël Michel',
    'Louise Lefevre',
    'Gabriel Roux',
    'Alice Fournier',
    'Arthur Vincent',
    'Lina David',
    'Paul Thomas',
    'Zoé Bonnet',
    'Ethan Mercier',
    'Inès Guerin',
    'Adam Blanc',
    'Clara Garnier',
  ];

  // Liste de noms de médicaments
  final medicamentNames = [
    'Doliprane',
    'Efferalgan',
    'Advil',
    'Spasfon',
    'Smecta',
    'Gaviscon',
    'Voltarene',
    'Imodium',
    'Aspégic',
    'Nurofen',
    'Rhinofluimucil',
    'Strepsils',
    'Humex',
    'Actifed',
    'Fervex',
    'Oscillococcinum',
    'Biseptine',
    'Hextril',
    'Drill',
    'Vicks',
    'Toplexil',
    'Daflon',
    'Maalox',
    'Motilium',
    'Forlax',
    'Microlax',
    'Eludril',
    'Biafine',
    'Bepanthen',
    'Arnican',
    'Dacryoserum',
    'Physiomer',
    'Mucomyst',
    'Euphytose',
    'Lysopaine',
    'Maxilase',
    'Dulcolax',
    'Cytéal',
    'Hexomédine',
    'Dakin',
  ];

  // Liste de dosages
  final dosages = [
    '500mg',
    '1000mg',
    '250mg',
    '100mg',
    '50mg',
    '20mg',
    '10mg',
    '5mg',
    '2mg',
    '1mg',
    '500mg 2 fois par jour',
    '1000mg matin et soir',
    '250mg 3 fois par jour',
    '1 comprimé par jour',
    '2 comprimés matin et soir',
    '1 sachet matin et soir',
    '1 cuillère à café 3 fois par jour',
    '10 gouttes matin et soir',
    '1 application locale 2 fois par jour',
    '1 pulvérisation 3 fois par jour',
  ];

  // Liste d'instructions
  final instructions = [
    'Prendre avant les repas',
    'Prendre après les repas',
    'Prendre au coucher',
    'Ne pas prendre avec des produits laitiers',
    'Éviter l\'exposition au soleil',
    'Prendre à jeun',
    'Prendre avec un grand verre d\'eau',
    'Ne pas écraser ou croquer le comprimé',
    'Peut provoquer une somnolence',
    'Ne pas conduire après la prise',
    'Conserver au réfrigérateur',
    'Agiter avant emploi',
    'Ne pas utiliser en cas de grossesse',
    'Arrêter le traitement en cas d\'effets indésirables',
    'Contacter un médecin en cas de symptômes persistants',
  ];

  print('Début de l\'insertion des données factices...');

  // Créer 50 ordonnances
  for (var i = 0; i < 50; i++) {
    // Générer une date de création aléatoire dans les 6 derniers mois
    final createdAt = DateTime.now().subtract(Duration(days: random.nextInt(180)));

    // Sélectionner un nom de patient aléatoire
    final patientName = patientNames[random.nextInt(patientNames.length)];

    // Chiffrer le nom du patient
    final encryptedPatientName = encryptData(patientName);

    // Créer l'ordonnance
    final ordonnanceRef = firestore.collection('ordonnances').doc();
    final ordonnanceId = ordonnanceRef.id; // Obtenir l'ID généré

    await ordonnanceRef.set({
      'id': ordonnanceId, // Ajouter l'ID dans le document
      'patientName': encryptedPatientName,
      'createdBy': '8nzrtYEHdTS4QhiDYw13YEwUfmn2',
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(createdAt),
      'isSynced': true,
      'version': 1,
    });

    print('Ordonnance créée pour $patientName (ID: $ordonnanceId)');

    // Déterminer le nombre de médicaments pour cette ordonnance (entre 3 et 5)
    final medicamentCount = random.nextInt(3) + 3; // 3 à 5

    // Créer les médicaments pour cette ordonnance
    for (var j = 0; j < medicamentCount; j++) {
      // Sélectionner un nom de médicament aléatoire
      final medicamentName = medicamentNames[random.nextInt(medicamentNames.length)];

      // Sélectionner un dosage aléatoire
      final dosage = dosages[random.nextInt(dosages.length)];

      // Sélectionner des instructions aléatoires (ou null dans certains cas)
      final instruction =
          random.nextBool() ? instructions[random.nextInt(instructions.length)] : null;

      // Générer une date d'expiration
      DateTime expirationDate;

      // Distribuer les dates d'expiration pour couvrir tous les cas
      // 10% déjà expirés, 30% critiques (<14 jours), 30% en alerte (14-30 jours), 30% OK (>30 jours)
      final expirationCase = random.nextInt(10);
      if (expirationCase < 1) {
        // Déjà expiré
        expirationDate = DateTime.now().subtract(Duration(days: random.nextInt(30) + 1));
      } else if (expirationCase < 4) {
        // Critique (<14 jours)
        expirationDate = DateTime.now().add(Duration(days: random.nextInt(14)));
      } else if (expirationCase < 7) {
        // Alerte (14-30 jours)
        expirationDate = DateTime.now().add(Duration(days: 14 + random.nextInt(16)));
      } else {
        // OK (>30 jours)
        expirationDate = DateTime.now().add(Duration(days: 30 + random.nextInt(335)));
      }

      // Chiffrer les données sensibles
      final encryptedName = encryptData(medicamentName);
      final encryptedDosage = dosage != null ? encryptData(dosage) : null;
      final encryptedInstructions = instruction != null ? encryptData(instruction) : null;

      // Créer le médicament
      final medicamentRef = firestore.collection('medicaments').doc();
      final medicamentId = medicamentRef.id; // Obtenir l'ID généré

      await medicamentRef.set({
        'id': medicamentId, // Ajouter l'ID dans le document
        'ordonnanceId': ordonnanceId, // Utiliser l'ID de l'ordonnance
        'name': encryptedName,
        'dosage': encryptedDosage,
        'instructions': encryptedInstructions,
        'expirationDate': Timestamp.fromDate(expirationDate),
        'createdAt': Timestamp.fromDate(createdAt),
        'updatedAt': Timestamp.fromDate(createdAt),
        'isSynced': true,
        'version': 1,
      });

      print(
        '  Médicament ajouté: $medicamentName, expire le ${expirationDate.day}/${expirationDate.month}/${expirationDate.year}',
      );
    }
  }

  print('Insertion des données factices terminée!');
  print('50 ordonnances créées avec un total de ${50 * 4} médicaments en moyenne.');
}
