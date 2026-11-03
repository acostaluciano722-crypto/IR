import 'dart:io';

Future<void> releaseCapturedImage(String path) async {
  try {
    final image = File(path);
    if (await image.exists()) await image.delete();
  } on FileSystemException {
    // The camera's cache file may already have been removed by the platform.
  }
}
