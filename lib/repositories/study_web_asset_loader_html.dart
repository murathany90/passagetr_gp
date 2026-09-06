import 'dart:js_interop';

import 'package:web/web.dart' as web;

Future<String> loadVersionedStudyWebAsset({
  required String root,
  required String relativePath,
  required String buildSha,
}) {
  final assetUri = Uri.base
      .resolve('assets/$root/$relativePath')
      .replace(queryParameters: <String, String>{'v': buildSha});
  return _loadText(assetUri);
}

Future<String> _loadText(Uri assetUri) async {
  final response = await web.window.fetch(assetUri.toString().toJS).toDart;
  if (!response.ok) {
    throw StateError('Study asset HTTP ${response.status}: $assetUri');
  }
  return (await response.text().toDart).toDart;
}
