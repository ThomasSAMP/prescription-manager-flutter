import 'dart:convert';
import 'dart:typed_data';

import 'package:encrypt/encrypt.dart' as encryptt;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:injectable/injectable.dart';

import '../utils/logger.dart';

@lazySingleton
class EncryptionService {
  static const String _keyName = 'encryption_key';
  static const String _ivName = 'encryption_iv';

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  encryptt.Encrypter? _encrypter;
  encryptt.IV? _iv;

  // Cache pour éviter de déchiffrer plusieurs fois les mêmes données
  final Map<String, String> _decryptionCache = {};
  final int _maxCacheSize = 1000; // Limiter la taille du cache

  // Initialiser le service de chiffrement
  Future<void> initialize() async {
    try {
      // Vérifier si une clé existe déjà
      final keyString = await _secureStorage.read(key: _keyName);
      final ivString = await _secureStorage.read(key: _ivName);

      if (keyString == null || ivString == null) {
        // Générer une nouvelle clé et un nouveau vecteur d'initialisation
        await _generateNewKeyAndIV();
      } else {
        // Utiliser la clé et le vecteur d'initialisation existants
        final keyBytes = base64.decode(keyString);
        final key = encryptt.Key(Uint8List.fromList(keyBytes));
        _encrypter = encryptt.Encrypter(encryptt.AES(key));

        final ivBytes = base64.decode(ivString);
        _iv = encryptt.IV(Uint8List.fromList(ivBytes));
      }

      AppLogger.info('EncryptionService initialized successfully');
    } catch (e, stackTrace) {
      AppLogger.error('Failed to initialize EncryptionService', e, stackTrace);
      rethrow;
    }
  }

  // Générer une nouvelle clé et un nouveau vecteur d'initialisation
  Future<void> _generateNewKeyAndIV() async {
    try {
      // Générer une clé aléatoire
      final key = encryptt.Key.fromSecureRandom(32); // AES-256
      _encrypter = encryptt.Encrypter(encryptt.AES(key));

      // Générer un vecteur d'initialisation aléatoire
      _iv = encryptt.IV.fromSecureRandom(16);

      // Stocker la clé et le vecteur d'initialisation
      await _secureStorage.write(key: _keyName, value: base64.encode(key.bytes));
      await _secureStorage.write(key: _ivName, value: base64.encode(_iv!.bytes));

      AppLogger.debug('New encryption key and IV generated');
    } catch (e, stackTrace) {
      AppLogger.error('Failed to generate new encryption key and IV', e, stackTrace);
      rethrow;
    }
  }

  // Chiffrer une chaîne de caractères
  String encrypt(String plainText) {
    if (_encrypter == null || _iv == null) {
      throw Exception('EncryptionService not initialized');
    }

    try {
      final encrypted = _encrypter!.encrypt(plainText, iv: _iv!);
      return encrypted.base64;
    } catch (e, stackTrace) {
      AppLogger.error('Failed to encrypt data', e, stackTrace);
      rethrow;
    }
  }

  // Déchiffrer une chaîne de caractères
  String decrypt(String encryptedText) {
    if (_encrypter == null || _iv == null) {
      throw Exception('EncryptionService not initialized');
    }

    try {
      // Vérifier si déjà dans le cache
      if (_decryptionCache.containsKey(encryptedText)) {
        return _decryptionCache[encryptedText]!;
      }

      final encrypted = encryptt.Encrypted.fromBase64(encryptedText);
      final decrypted = _encrypter!.decrypt(encrypted, iv: _iv!);

      // Ajouter au cache si pas trop grand
      if (_decryptionCache.length < _maxCacheSize) {
        _decryptionCache[encryptedText] = decrypted;
      } else if (_decryptionCache.length == _maxCacheSize) {
        // Vider la moitié du cache quand il devient trop grand
        final keysToRemove = _decryptionCache.keys.take(_maxCacheSize ~/ 2).toList();
        for (final key in keysToRemove) {
          _decryptionCache.remove(key);
        }
        _decryptionCache[encryptedText] = decrypted;
      }

      return decrypted;
    } catch (e, stackTrace) {
      AppLogger.error('Failed to decrypt data', e, stackTrace);
      rethrow;
    }
  }

  void clearCache() {
    _decryptionCache.clear();
  }
}
