import 'package:flutter/services.dart';

/// Uses Android's Storage Access Framework, without storage permissions or
/// app-private copies. Null means the user cancelled, not a storage failure.
class ProfileBackupDocuments {
  static const channel = MethodChannel('com.ikram/profile_backup_documents');

  const ProfileBackupDocuments();

  Future<bool> save(Uint8List bytes) async =>
      await channel.invokeMethod<bool>('save', {
        'bytes': bytes,
      }) ??
      false;

  Future<Uint8List?> open({required int maxBytes}) =>
      channel.invokeMethod<Uint8List>('open', {'maxBytes': maxBytes});
}
