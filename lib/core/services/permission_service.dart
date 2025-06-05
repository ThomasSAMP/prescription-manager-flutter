import 'package:injectable/injectable.dart';
import 'package:permission_handler/permission_handler.dart';

import '../utils/logger.dart';

@lazySingleton
class PermissionService {
  Future<bool> requestNotificationPermission() async {
    try {
      final status = await Permission.notification.request();
      return status.isGranted;
    } catch (e, stackTrace) {
      AppLogger.error('Error requesting notification permission', e, stackTrace);
      return false;
    }
  }
}
