import 'package:injectable/injectable.dart';

import '../models/syncable_model.dart';
import '../utils/logger.dart';

@lazySingleton
class UnifiedCacheService {
  final Map<String, List<SyncableModel>> _cache = {};
  final Map<String, DateTime> _cacheTimestamps = {};
  final Map<String, bool> _cacheInitialized = {};

  // Durée de validité du cache (5 minutes par défaut)
  static const Duration _cacheValidityDuration = Duration(minutes: 5);

  /// Vérifie si le cache est valide pour une clé donnée
  bool isCacheValid(String key) {
    if (!_cacheInitialized.containsKey(key) || !_cacheInitialized[key]!) {
      return false;
    }

    final timestamp = _cacheTimestamps[key];
    if (timestamp == null) return false;

    return DateTime.now().difference(timestamp) < _cacheValidityDuration;
  }

  /// Récupère les données du cache
  List<T> getFromCache<T extends SyncableModel>(String key) {
    if (!isCacheValid(key)) return [];

    final cached = _cache[key];
    if (cached == null) return [];

    return cached.cast<T>();
  }

  /// Met à jour le cache
  void updateCache<T extends SyncableModel>(String key, List<T> items) {
    _cache[key] = items;
    _cacheTimestamps[key] = DateTime.now();
    _cacheInitialized[key] = true;

    AppLogger.debug('Cache updated for $key: ${items.length} items');
  }

  /// Invalide le cache pour une clé
  void invalidateCache(String key) {
    _cache.remove(key);
    _cacheTimestamps.remove(key);
    _cacheInitialized[key] = false;

    AppLogger.debug('Cache invalidated for $key');
  }

  /// Invalide tout le cache
  void invalidateAllCache() {
    _cache.clear();
    _cacheTimestamps.clear();
    _cacheInitialized.clear();

    AppLogger.debug('All cache invalidated');
  }

  /// Obtient la taille du cache
  int getCacheSize(String key) {
    return _cache[key]?.length ?? 0;
  }

  /// Obtient l'âge du cache en minutes
  int getCacheAgeInMinutes(String key) {
    final timestamp = _cacheTimestamps[key];
    if (timestamp == null) return -1;

    return DateTime.now().difference(timestamp).inMinutes;
  }
}
