import 'dart:convert';
import 'dart:typed_data';

import 'package:profile_backup_documents/profile_backup_documents.dart';

import 'domain.dart';

/// Keeps document access separate from schema validation and persistence.
class ProfileBackupFiles {
  final ProfileBackupDocuments documents;
  const ProfileBackupFiles({this.documents = const ProfileBackupDocuments()});

  Future<bool> save(String source) async {
    decodeProfileBackup(source);
    return documents.save(Uint8List.fromList(utf8.encode(source)));
  }

  Future<String?> open() async {
    final bytes = await documents.open(maxBytes: maxProfileBackupLength * 3);
    if (bytes == null) return null;
    if (bytes.length > maxProfileBackupLength * 3) {
      throw const FormatException('Backup exceeds the byte limit.');
    }
    // Strict UTF-8: never silently replace Arabic or malformed byte sequences.
    final source = utf8.decode(bytes, allowMalformed: false);
    if (source.length > maxProfileBackupLength) {
      throw const FormatException('Backup exceeds the character limit.');
    }
    return source;
  }
}
