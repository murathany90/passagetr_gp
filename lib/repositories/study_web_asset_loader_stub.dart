Future<String> loadVersionedStudyWebAsset({
  required String root,
  required String relativePath,
  required String buildSha,
}) =>
    throw UnsupportedError('Versioned Study assets are only loaded on web.');
