import 'dart:js_interop';

import 'package:web/web.dart' as web;

Future<String> loadVersionedTestWebAsset({
  required String root,
  required String relativePath,
  required String buildSha,
}) async {
  final uri = Uri.base
      .resolve('assets/$root/$relativePath')
      .replace(queryParameters: <String, String>{'v': buildSha});
  final response = await web.window.fetch(uri.toString().toJS).toDart;
  if (!response.ok) {
    throw StateError('Testler asset HTTP ${response.status}: $uri');
  }
  return (await response.text().toDart).toDart;
}
