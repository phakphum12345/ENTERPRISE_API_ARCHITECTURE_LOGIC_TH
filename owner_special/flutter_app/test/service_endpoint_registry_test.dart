import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:research_os_owner_special/src/service_endpoint_registry.dart';

void main() {
  test('discovers healthy Owner Friend service from registry', () async {
    final directory = await Directory.systemTemp.createTemp('owner-friend-registry-');
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) {
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'status': 'ok', 'loopback_only': true}));
      request.response.close();
    });
    try {
      final port = server.port;
      await File('${directory.path}/owner-friend.json').writeAsString(jsonEncode({
        'schema_version': 1,
        'service': 'owner-friend',
        'protocol': 'http',
        'host': '127.0.0.1',
        'port': port,
        'base_url': 'http://127.0.0.1:$port',
        'pid': pid,
      }));
      expect(
        await discoverOwnerFriendEndpoint(searchDirectories: [directory]),
        'http://127.0.0.1:$port',
      );
    } finally {
      await server.close(force: true);
      await directory.delete(recursive: true);
    }
  });

  test('rejects non-loopback service records', () async {
    final directory = await Directory.systemTemp.createTemp('owner-friend-registry-');
    try {
      await File('${directory.path}/owner-friend.json').writeAsString(jsonEncode({
        'schema_version': 1,
        'service': 'owner-friend',
        'protocol': 'http',
        'host': '0.0.0.0',
        'port': 12345,
        'base_url': 'http://0.0.0.0:12345',
        'pid': pid,
      }));
      expect(await discoverOwnerFriendEndpoint(searchDirectories: [directory]), isNull);
    } finally {
      await directory.delete(recursive: true);
    }
  });
}
