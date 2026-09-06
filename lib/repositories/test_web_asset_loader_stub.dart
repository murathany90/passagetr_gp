Future<String> loadVersionedTestWebAsset({
  required String root,
  required String relativePath,
  required String buildSha,
}) =>
    throw UnsupportedError('Versioned Testler assets are only loaded on web.');
