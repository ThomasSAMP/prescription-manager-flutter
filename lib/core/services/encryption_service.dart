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
      // Vérifier si une clé existe déjà localement
      final keyString = await _secureStorage.read(key: _keyName);
      final ivString = await _secureStorage.read(key: _ivName);

      if (keyString == null || ivString == null) {
        const sharedKeyBase64 = '4TsOqlhDt2Rnjn2V+R5m1D5hqn0+2IaJcneRXl5DQxg=';
        const sharedIVBase64 = '0/AIedqHmLs/F1YQHb9qGg==';

        // Stocker localement
        await _secureStorage.write(key: _keyName, value: sharedKeyBase64);
        await _secureStorage.write(key: _ivName, value: sharedIVBase64);

        // Initialiser l'encrypteur
        final keyBytes = base64.decode(sharedKeyBase64);
        final key = encryptt.Key(Uint8List.fromList(keyBytes));
        _encrypter = encryptt.Encrypter(encryptt.AES(key));

        final ivBytes = base64.decode(sharedIVBase64);
        _iv = encryptt.IV(Uint8List.fromList(ivBytes));
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
