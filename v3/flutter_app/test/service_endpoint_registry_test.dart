import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:research_os_v3_flutter/src/api/service_endpoint_registry.dart';

void main() {
  test('discovers healthy V3 endpoint from its service registry', () async {
    final directory = await Directory.systemTemp.createTemp('v3-registry-');
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) {
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'status': 'ok'}));
      request.response.close();
    });
    try {
      final port = server.port;
      await File('${directory.path}/research-os-v3.json').writeAsString(jsonEncode({
        'schema_version': 1,
        'service': 'research-os-v3',
        'protocol': 'http',
        'host': '127.0.0.1',
        'port': port,
        'base_url': 'http://127.0.0.1:$port',
        'pid': pid,
      }));
      expect(
        await discoverV3Endpoint(searchDirectories: [directory]),
        'http://127.0.0.1:$port',
      );
    } finally {
      await server.close(force: true);
      await directory.delete(recursive: true);
    }
  });
}
