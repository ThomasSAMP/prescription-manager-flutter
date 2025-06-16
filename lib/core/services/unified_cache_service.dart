import 'dart:async';
import 'dart:convert';

import 'package:injectable/injectable.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/syncable_model.dart';
import '../utils/logger.dart';

// Niveaux de cache hiérarchiques
enum CacheLevel {
  memory, // Cache mémoire (le plus rapide)
  disk, // Cache disque (persistant)
  both, // Les deux niveaux
}

// Stratégies d'invalidation
enum InvalidationStrategy {
  manual, // Invalidation manuelle uniquement
  timeBasedOnly, // Basée sur le temps seulement
  versionBased, // Basée sur la version des données
  smart, // Combinaison intelligente (recommandé)
}

// Métadonnées du cache
class CacheMetadata {
  final DateTime createdAt;
  final DateTime lastAccessed;
  final DateTime? expiresAt;
  final int version;
  final int accessCount;
  final String dataHash;

  CacheMetadata({
    required this.createdAt,
    required this.lastAccessed,
    this.expiresAt,
    required this.version,
    this.accessCount = 1,
    required this.dataHash,
  });

  factory CacheMetadata.fromJson(Map<String, dynamic> json) {
    return CacheMetadata(
      createdAt: DateTime.parse(json['createdAt']),
      lastAccessed: DateTime.parse(json['lastAccessed']),
      expiresAt: json['expiresAt'] != null ? DateTime.parse(json['expiresAt']) : null,
      version: json['version'] ?? 1,
      accessCount: json['accessCount'] ?? 1,
      dataHash: json['dataHash'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'createdAt': createdAt.toIso8601String(),
      'lastAccessed': lastAccessed.toIso8601String(),
      'expiresAt': expiresAt?.toIso8601String(),
      'version': version,
      'accessCount': accessCount,
      'dataHash': dataHash,
    };
  }

  CacheMetadata copyWith({
    DateTime? lastAccessed,
    DateTime? expiresAt,
    int? version,
    int? accessCount,
    String? dataHash,
  }) {
    return CacheMetadata(
      createdAt: createdAt,
      lastAccessed: lastAccessed ?? this.lastAccessed,
      expiresAt: expiresAt ?? this.expiresAt,
      version: version ?? this.version,
      accessCount: accessCount ?? this.accessCount,
      dataHash: dataHash ?? this.dataHash,
    );
  }

  bool get isExpired {
    if (expiresAt == null) return false;
    return DateTime.now().isAfter(expiresAt!);
  }

  bool get isStale {
    // Considérer comme périmé après 1 heure sans accès
    return DateTime.now().difference(lastAccessed) > const Duration(hours: 1);
  }
}

// Entrée de cache unifiée
class CacheEntry<T> {
  final T data;
  final CacheMetadata metadata;

  CacheEntry({required this.data, required this.metadata});

  factory CacheEntry.fromJson(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic>) fromJsonFunc,
  ) {
    return CacheEntry<T>(
      data: fromJsonFunc(json['data']),
      metadata: CacheMetadata.fromJson(json['metadata']),
    );
  }

  Map<String, dynamic> toJson(Map<String, dynamic> Function(T) toJsonFunc) {
    return {'data': toJsonFunc(data), 'metadata': metadata.toJson()};
  }

  CacheEntry<T> updateAccess() {
    return CacheEntry<T>(
      data: data,
      metadata: metadata.copyWith(
        lastAccessed: DateTime.now(),
        accessCount: metadata.accessCount + 1,
      ),
    );
  }
}

@lazySingleton
class UnifiedCacheService {
  final SharedPreferences _prefs;

  // Cache mémoire avec gestion LRU
  final Map<String, CacheEntry<dynamic>> _memoryCache = {};
  final List<String> _accessOrder = []; // Pour LRU

  // Configuration
  static const int _maxMemoryCacheSize = 100;
  static const Duration _defaultTTL = Duration(minutes: 30);
  static const String _cachePrefix = 'unified_cache_';
  static const String _metadataPrefix = 'cache_meta_';

  UnifiedCacheService(this._prefs);

  // Calculer le hash des données pour détecter les changements
  String _calculateHash(dynamic data) {
    try {
      final jsonString = jsonEncode(data);
      return jsonString.hashCode.toString();
    } catch (e) {
      return DateTime.now().millisecondsSinceEpoch.toString();
    }
  }

  // Gestion LRU du cache mémoire
  void _updateLRU(String key) {
    _accessOrder.remove(key);
    _accessOrder.add(key);

    // Nettoyer si trop d'entrées
    while (_accessOrder.length > _maxMemoryCacheSize) {
      final oldestKey = _accessOrder.removeAt(0);
      _memoryCache.remove(oldestKey);
    }
  }

  // Sauvegarder une entrée (niveau unifié)
  Future<void> put<T extends SyncableModel>(
    String key,
    T data, {
    Duration? ttl,
    CacheLevel level = CacheLevel.both,
    InvalidationStrategy strategy = InvalidationStrategy.smart,
  }) async {
    try {
      final now = DateTime.now();
      final dataHash = _calculateHash(data.toJson());
      final expiresAt = ttl != null ? now.add(ttl) : now.add(_defaultTTL);

      final metadata = CacheMetadata(
        createdAt: now,
        lastAccessed: now,
        expiresAt: expiresAt,
        version: data.version,
        dataHash: dataHash,
      );

      final entry = CacheEntry<T>(data: data, metadata: metadata);

      // Cache mémoire
      if (level == CacheLevel.memory || level == CacheLevel.both) {
        _memoryCache[key] = entry;
        _updateLRU(key);
      }

      // Cache disque
      if (level == CacheLevel.disk || level == CacheLevel.both) {
        await _saveToDisk(key, entry);
      }

      AppLogger.debug('Cache PUT: $key (${level.name}) - Hash: $dataHash');
    } catch (e) {
      AppLogger.error('Error putting cache entry: $key', e);
    }
  }

  // Récupérer une entrée (avec fallback automatique)
  Future<T?> get<T extends SyncableModel>(
    String key,
    T Function(Map<String, dynamic>) fromJson, {
    bool updateAccess = true,
  }) async {
    try {
      CacheEntry<T>? entry;

      // 1. Essayer le cache mémoire d'abord
      if (_memoryCache.containsKey(key)) {
        final memoryEntry = _memoryCache[key] as CacheEntry<T>?;
        if (memoryEntry != null && !memoryEntry.metadata.isExpired) {
          entry = memoryEntry;
          if (updateAccess) {
            _updateLRU(key);
          }
          AppLogger.debug('Cache HIT (memory): $key');
        } else if (memoryEntry != null) {
          // Entrée expirée en mémoire
          _memoryCache.remove(key);
          _accessOrder.remove(key);
          AppLogger.debug('Cache EXPIRED (memory): $key');
        }
      }

      // 2. Fallback sur le cache disque
      if (entry == null) {
        entry = await _loadFromDisk<T>(key, fromJson);
        if (entry != null && !entry.metadata.isExpired) {
          // Remettre en cache mémoire
          _memoryCache[key] = entry;
          _updateLRU(key);
          AppLogger.debug('Cache HIT (disk → memory): $key');
        } else if (entry != null) {
          // Entrée expirée sur disque
          await _removeFromDisk(key);
          AppLogger.debug('Cache EXPIRED (disk): $key');
          entry = null;
        }
      }

      // 3. Mettre à jour l'accès si trouvé
      if (entry != null && updateAccess) {
        final updatedEntry = entry.updateAccess();
        _memoryCache[key] = updatedEntry;
        // Sauvegarder les métadonnées mises à jour sur disque
        unawaited(_updateMetadataOnDisk(key, updatedEntry.metadata));
      }

      return entry?.data;
    } catch (e) {
      AppLogger.error('Error getting cache entry: $key', e);
      return null;
    }
  }

  // Vérifier si une entrée existe et est valide
  Future<bool> contains(String key) async {
    // Vérifier mémoire
    if (_memoryCache.containsKey(key)) {
      final entry = _memoryCache[key];
      if (entry != null && !entry.metadata.isExpired) {
        return true;
      }
    }

    // Vérifier disque
    final diskEntry = await _loadFromDisk(key, (json) => json);
    return diskEntry != null && !diskEntry.metadata.isExpired;
  }

  // Invalider une entrée spécifique
  Future<void> invalidate(String key) async {
    try {
      // Supprimer de la mémoire
      _memoryCache.remove(key);
      _accessOrder.remove(key);

      // Supprimer du disque
      await _removeFromDisk(key);

      AppLogger.debug('Cache INVALIDATED: $key');
    } catch (e) {
      AppLogger.error('Error invalidating cache entry: $key', e);
    }
  }

  // Invalider par pattern (ex: "ordonnances_*")
  Future<void> invalidatePattern(String pattern) async {
    try {
      final regex = RegExp(pattern.replaceAll('*', '.*'));

      // Invalider en mémoire
      final keysToRemove = _memoryCache.keys.where(regex.hasMatch).toList();
      for (final key in keysToRemove) {
        _memoryCache.remove(key);
        _accessOrder.remove(key);
      }

      // Invalider sur disque
      final diskKeys = _prefs
          .getKeys()
          .where((key) => key.startsWith(_cachePrefix))
          .map((key) => key.substring(_cachePrefix.length))
          .where(regex.hasMatch);

      for (final key in diskKeys) {
        await _removeFromDisk(key);
      }

      AppLogger.debug('Cache INVALIDATED (pattern): $pattern (${keysToRemove.length} entries)');
    } catch (e) {
      AppLogger.error('Error invalidating cache pattern: $pattern', e);
    }
  }

  // Invalider tout le cache
  Future<void> invalidateAll() async {
    try {
      // Vider la mémoire
      _memoryCache.clear();
      _accessOrder.clear();

      // Vider le disque
      final cacheKeys =
          _prefs
              .getKeys()
              .where((key) => key.startsWith(_cachePrefix) || key.startsWith(_metadataPrefix))
              .toList();

      for (final key in cacheKeys) {
        await _prefs.remove(key);
      }

      AppLogger.debug('Cache INVALIDATED (all): ${cacheKeys.length} entries');
    } catch (e) {
      AppLogger.error('Error invalidating all cache', e);
    }
  }

  // Nettoyer les entrées expirées
  Future<void> cleanup() async {
    try {
      var cleanedCount = 0;

      // Nettoyer la mémoire
      final expiredMemoryKeys =
          _memoryCache.entries
              .where((entry) => entry.value.metadata.isExpired)
              .map((entry) => entry.key)
              .toList();

      for (final key in expiredMemoryKeys) {
        _memoryCache.remove(key);
        _accessOrder.remove(key);
        cleanedCount++;
      }

      // Nettoyer le disque
      final diskKeys = _prefs
          .getKeys()
          .where((key) => key.startsWith(_cachePrefix))
          .map((key) => key.substring(_cachePrefix.length));

      for (final key in diskKeys) {
        final entry = await _loadFromDisk(key, (json) => json);
        if (entry != null && entry.metadata.isExpired) {
          await _removeFromDisk(key);
          cleanedCount++;
        }
      }

      AppLogger.debug('Cache CLEANUP: $cleanedCount expired entries removed');
    } catch (e) {
      AppLogger.error('Error during cache cleanup', e);
    }
  }

  // Obtenir les statistiques du cache
  Future<Map<String, dynamic>> getStats() async {
    try {
      final memorySize = _memoryCache.length;
      final diskKeys = _prefs.getKeys().where((key) => key.startsWith(_cachePrefix)).length;

      var totalHits = 0;
      var expiredCount = 0;

      for (final entry in _memoryCache.values) {
        totalHits += entry.metadata.accessCount;
        if (entry.metadata.isExpired) expiredCount++;
      }

      return {
        'memoryEntries': memorySize,
        'diskEntries': diskKeys,
        'totalEntries': memorySize + diskKeys,
        'totalAccess': totalHits,
        'expiredEntries': expiredCount,
        'maxMemorySize': _maxMemoryCacheSize,
        'memoryUsage': '${(memorySize / _maxMemoryCacheSize * 100).toStringAsFixed(1)}%',
      };
    } catch (e) {
      AppLogger.error('Error getting cache stats', e);
      return {};
    }
  }

  // Méthodes privées pour la gestion du disque
  Future<void> _saveToDisk<T>(String key, CacheEntry<T> entry) async {
    try {
      final cacheKey = '$_cachePrefix$key';
      final metaKey = '$_metadataPrefix$key';

      if (entry.data is SyncableModel) {
        final data = (entry.data as SyncableModel).toJson();
        await _prefs.setString(cacheKey, jsonEncode(data));
        await _prefs.setString(metaKey, jsonEncode(entry.metadata.toJson()));
      }
    } catch (e) {
      AppLogger.error('Error saving to disk: $key', e);
    }
  }

  Future<CacheEntry<T>?> _loadFromDisk<T>(
    String key,
    T Function(Map<String, dynamic>) fromJson,
  ) async {
    try {
      final cacheKey = '$_cachePrefix$key';
      final metaKey = '$_metadataPrefix$key';

      final dataString = _prefs.getString(cacheKey);
      final metaString = _prefs.getString(metaKey);

      if (dataString != null && metaString != null) {
        final data = fromJson(jsonDecode(dataString));
        final metadata = CacheMetadata.fromJson(jsonDecode(metaString));
        return CacheEntry<T>(data: data, metadata: metadata);
      }
    } catch (e) {
      AppLogger.error('Error loading from disk: $key', e);
    }
    return null;
  }

  Future<void> _removeFromDisk(String key) async {
    try {
      final cacheKey = '$_cachePrefix$key';
      final metaKey = '$_metadataPrefix$key';

      await _prefs.remove(cacheKey);
      await _prefs.remove(metaKey);
    } catch (e) {
      AppLogger.error('Error removing from disk: $key', e);
    }
  }

  Future<void> _updateMetadataOnDisk(String key, CacheMetadata metadata) async {
    try {
      final metaKey = '$_metadataPrefix$key';
      await _prefs.setString(metaKey, jsonEncode(metadata.toJson()));
    } catch (e) {
      AppLogger.error('Error updating metadata on disk: $key', e);
    }
  }
}
