import 'dart:io';

abstract final class XFileHelper {
  static Future<void> ensureDirectory(String path) async {
    await Directory(path).create(recursive: true);
  }
}
