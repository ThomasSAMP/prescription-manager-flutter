import 'dart:convert';

import 'package:injectable/injectable.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/syncable_model.dart';
import '../utils/logger.dart';

@lazySingleton
class LocalStorageService {
  final SharedPreferences _prefs;
  // Cache en mémoire pour éviter les écritures/lectures redondantes
  final Map<String, List<String>> _modelListCache = {};

  LocalStorageService(this._prefs);

  /// Sauvegarde une liste de modèles dans le stockage local
  Future<bool> saveModelList<T extends SyncableModel>(String key, List<T> items) async {
    try {
      final jsonList = items.map((item) => jsonEncode(item.toJson())).toList();

      // Vérifier si les données ont changé avant de sauvegarder
      if (_modelListCache[key] != null) {
        var isDifferent = false;

        // Si le nombre d'éléments est différent, les données ont changé
        if (_modelListCache[key]!.length != jsonList.length) {
          isDifferent = true;
        } else {
          // Comparer chaque élément
          for (var i = 0; i < jsonList.length; i++) {
            if (i >= _modelListCache[key]!.length || jsonList[i] != _modelListCache[key]![i]) {
              isDifferent = true;
              break;
            }
          }
        }

        // Si les données n'ont pas changé, ne pas sauvegarder
        if (!isDifferent) {
          // AppLogger.debug('No changes detected for key: $key, skipping save');
          return true;
        }
      }

      // Mettre à jour le cache
      _modelListCache[key] = jsonList;

      // Sauvegarder dans les préférences
      final result = await _prefs.setStringList(key, jsonList);

      AppLogger.debug('Saved ${items.length} items to local storage with key: $key');
      return result;
    } catch (e) {
      AppLogger.error('Error saving items to local storage', e);
      return false;
    }
  }

  /// Charge une liste de modèles depuis le stockage local
  List<T> loadModelList<T extends SyncableModel>(
    String key,
    T Function(Map<String, dynamic> json) fromJson,
  ) {
    try {
      final jsonList = _prefs.getStringList(key) ?? [];

      // Mettre à jour le cache
      _modelListCache[key] = jsonList;

      final items =
          jsonList.map((json) => fromJson(jsonDecode(json) as Map<String, dynamic>)).toList();

      // AppLogger.debug('Loaded ${items.length} items from local storage with key: $key');
      return items;
    } catch (e) {
      AppLogger.error('Error loading items from local storage', e);
      return [];
    }
  }

  /// Sauvegarde un modèle individuel dans le stockage local
  Future<bool> saveModel<T extends SyncableModel>(String key, T item) async {
    try {
      final jsonString = jsonEncode(item.toJson());
      final result = await _prefs.setString(key, jsonString);

      AppLogger.debug('Saved item to local storage with key: $key');
      return result;
    } catch (e) {
      AppLogger.error('Error saving item to local storage', e);
      return false;
    }
  }

  /// Charge un modèle individuel depuis le stockage local
  T? loadModel<T extends SyncableModel>(
    String key,
    T Function(Map<String, dynamic> json) fromJson,
  ) {
    try {
      final jsonString = _prefs.getString(key);
      if (jsonString == null) return null;

      final item = fromJson(jsonDecode(jsonString) as Map<String, dynamic>);

      // AppLogger.debug('Loaded item from local storage with key: $key');
      return item;
    } catch (e) {
      AppLogger.error('Error loading item from local storage', e);
      return null;
    }
  }

  /// Supprime une entrée du stockage local
  Future<bool> remove(String key) async {
    try {
      final result = await _prefs.remove(key);

      // AppLogger.debug('Removed item from local storage with key: $key');
      return result;
    } catch (e) {
      AppLogger.error('Error removing item from local storage', e);
      return false;
    }
  }

  /// Vérifie si une clé existe dans le stockage local
  bool containsKey(String key) {
    return _prefs.containsKey(key);
  }

  /// Sauvegarde des opérations en attente dans le stockage local
  Future<bool> savePendingOperations<T extends SyncableModel>(
    String key,
    List<PendingOperation<T>> operations,
  ) async {
    try {
      final jsonList =
          operations
              .map((op) => jsonEncode({'type': op.type.index, 'data': op.data.toJson()}))
              .toList();

      final result = await _prefs.setStringList(key, jsonList);

      AppLogger.debug(
        'Saved ${operations.length} pending operations to local storage with key: $key',
      );
      return result;
    } catch (e) {
      AppLogger.error('Error saving pending operations to local storage', e);
      return false;
    }
  }

  /// Charge des opérations en attente depuis le stockage local
  List<Map<String, dynamic>> loadPendingOperationsData(String key) {
    try {
      final jsonList = _prefs.getStringList(key) ?? [];
      final operations = jsonList.map((json) => jsonDecode(json) as Map<String, dynamic>).toList();

      // AppLogger.debug(
      //   'Loaded ${operations.length} pending operations from local storage with key: $key',
      // );
      return operations;
    } catch (e) {
      AppLogger.error('Error loading pending operations from local storage', e);
      return [];
    }
  }
}

/// Types d'opérations en attente
enum OperationType { create, update, delete }

/// Classe représentant une opération en attente
class PendingOperation<T extends SyncableModel> {
  final OperationType type;
  final T data;
  final Future<void> Function() execute;

  PendingOperation({required this.type, required this.data, required this.execute});
}
