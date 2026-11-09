import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:research_os_flutter/src/api/api_endpoint_registry_io.dart';

void main() {
  test('discovers only a healthy OS-assigned loopback endpoint', () async {
    final directory = await Directory.systemTemp.createTemp('research-os-registry-');
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
      await File('${directory.path}/research-os-api.json').writeAsString(jsonEncode({
        'schema_version': 1,
        'service': 'research-os-api',
        'protocol': 'http',
        'host': '127.0.0.1',
        'port': port,
        'base_url': 'http://127.0.0.1:$port',
        'pid': pid,
      }));
      expect(
        await discoverLocalApiEndpoint(searchDirectories: [directory]),
        'http://127.0.0.1:$port',
      );
    } finally {
      await server.close(force: true);
      await directory.delete(recursive: true);
    }
  });

  test('rejects wildcard or malformed registry endpoints', () async {
    final directory = await Directory.systemTemp.createTemp('research-os-registry-');
    try {
      await File('${directory.path}/research-os-api.json').writeAsString(jsonEncode({
        'schema_version': 1,
        'service': 'research-os-api',
        'protocol': 'http',
        'host': '0.0.0.0',
        'port': 43123,
        'base_url': 'http://0.0.0.0:43123',
        'pid': pid,
      }));
      expect(await discoverLocalApiEndpoint(searchDirectories: [directory]), isNull);
    } finally {
      await directory.delete(recursive: true);
    }
  });
}
