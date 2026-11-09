import 'dart:convert';
import 'dart:io';

Future<String?> discoverLocalApiEndpoint({
  List<Object>? searchDirectories,
}) => discoverLocalServiceEndpoint(
      'research-os-api',
      searchDirectories: searchDirectories,
    );

Future<String?> discoverLocalServiceEndpoint(
  String serviceId, {
  List<Object>? searchDirectories,
}) async {
  if (!RegExp(r'^[a-z][a-z0-9-]{0,63}
  for (final directory in directories) {
    final file = File('${directory.path}${Platform.pathSeparator}$serviceId.json');
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) continue;
      if (decoded['schema_version'] != 1 ||
          decoded['service'] != serviceId ||
          decoded['protocol'] != 'http') {
        continue;
      }
      final host = decoded['host'];
      final port = decoded['port'];
      final baseUrl = decoded['base_url'];
      if (host != '127.0.0.1' && host != '::1' && host != 'localhost') {
        continue;
      }
      if (port is! int || port < 1 || port > 65535 || baseUrl is! String) {
        continue;
      }
      final authorityHost = host == '::1' ? '[$host]' : host as String;
      final expected = 'http://$authorityHost:$port';
      if (baseUrl != expected) continue;
      if (await _isHealthy(baseUrl)) return baseUrl;
    } on Object {
      // Missing, malformed, stale or unavailable registry records are not READY.
      continue;
    }
  }
  return null;
}

List<Directory> _defaultRegistryDirectories() {
  final result = <Directory>[];
  final explicit = Platform.environment['RESEARCH_OS_SERVICE_REGISTRY_DIR']?.trim();
  if (explicit != null && explicit.isNotEmpty) {
    result.add(Directory(explicit));
  }
  final dataDir = Platform.environment['RESEARCH_OS_DATA_DIR']?.trim();
  if (dataDir != null && dataDir.isNotEmpty) {
    result.add(Directory('$dataDir${Platform.pathSeparator}run${Platform.pathSeparator}services'));
  }
  if (Platform.isWindows) {
    final userProfile = Platform.environment['USERPROFILE']?.trim();
    if (userProfile != null && userProfile.isNotEmpty) {
      result.add(Directory('$userProfile${Platform.pathSeparator}ResearchOSData${Platform.pathSeparator}run${Platform.pathSeparator}services'));
    }
    final programData = Platform.environment['PROGRAMDATA']?.trim();
    if (programData != null && programData.isNotEmpty) {
      result.add(Directory('$programData${Platform.pathSeparator}ResearchOS${Platform.pathSeparator}run${Platform.pathSeparator}services'));
    }
  } else {
    final stateHome = Platform.environment['XDG_STATE_HOME']?.trim();
    if (stateHome != null && stateHome.isNotEmpty) {
      result.add(Directory('$stateHome${Platform.pathSeparator}research-os${Platform.pathSeparator}run${Platform.pathSeparator}services'));
    }
    result.add(Directory('${Platform.environment['HOME'] ?? Directory.current.path}${Platform.pathSeparator}ResearchOSData${Platform.pathSeparator}run${Platform.pathSeparator}services'));
  }
  final unique = <String>{};
  return result.where((item) => unique.add(item.path)).toList(growable: false);
}

Future<bool> _isHealthy(String baseUrl) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
  try {
    final request = await client.getUrl(Uri.parse('$baseUrl/health')).timeout(const Duration(seconds: 3));
    final response = await request.close().timeout(const Duration(seconds: 3));
    if (response.statusCode != HttpStatus.ok) return false;
    final body = await utf8.decoder.bind(response).join().timeout(const Duration(seconds: 3));
    final payload = jsonDecode(body);
    return payload is Map<String, dynamic> && payload['status'] == 'ok';
  } on Object {
    return false;
  } finally {
    client.close(force: true);
  }
}
).hasMatch(serviceId)) return null;
  final directories = searchDirectories?.cast<Directory>() ?? _defaultRegistryDirectories();
  for (final directory in directories) {
    final file = File('${directory.path}${Platform.pathSeparator}research-os-api.json');
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) continue;
      if (decoded['schema_version'] != 1 ||
          decoded['service'] != 'research-os-api' ||
          decoded['protocol'] != 'http') {
        continue;
      }
      final host = decoded['host'];
      final port = decoded['port'];
      final baseUrl = decoded['base_url'];
      if (host != '127.0.0.1' && host != '::1' && host != 'localhost') {
        continue;
      }
      if (port is! int || port < 1 || port > 65535 || baseUrl is! String) {
        continue;
      }
      final authorityHost = host == '::1' ? '[$host]' : host as String;
      final expected = 'http://$authorityHost:$port';
      if (baseUrl != expected) continue;
      if (await _isHealthy(baseUrl)) return baseUrl;
    } on Object {
      // Missing, malformed, stale or unavailable registry records are not READY.
      continue;
    }
  }
  return null;
}

List<Directory> _defaultRegistryDirectories() {
  final result = <Directory>[];
  final explicit = Platform.environment['RESEARCH_OS_SERVICE_REGISTRY_DIR']?.trim();
  if (explicit != null && explicit.isNotEmpty) {
    result.add(Directory(explicit));
  }
  final dataDir = Platform.environment['RESEARCH_OS_DATA_DIR']?.trim();
  if (dataDir != null && dataDir.isNotEmpty) {
    result.add(Directory('$dataDir${Platform.pathSeparator}run${Platform.pathSeparator}services'));
  }
  if (Platform.isWindows) {
    final userProfile = Platform.environment['USERPROFILE']?.trim();
    if (userProfile != null && userProfile.isNotEmpty) {
      result.add(Directory('$userProfile${Platform.pathSeparator}ResearchOSData${Platform.pathSeparator}run${Platform.pathSeparator}services'));
    }
    final programData = Platform.environment['PROGRAMDATA']?.trim();
    if (programData != null && programData.isNotEmpty) {
      result.add(Directory('$programData${Platform.pathSeparator}ResearchOS${Platform.pathSeparator}run${Platform.pathSeparator}services'));
    }
  } else {
    final stateHome = Platform.environment['XDG_STATE_HOME']?.trim();
    if (stateHome != null && stateHome.isNotEmpty) {
      result.add(Directory('$stateHome${Platform.pathSeparator}research-os${Platform.pathSeparator}run${Platform.pathSeparator}services'));
    }
    result.add(Directory('${Platform.environment['HOME'] ?? Directory.current.path}${Platform.pathSeparator}ResearchOSData${Platform.pathSeparator}run${Platform.pathSeparator}services'));
  }
  final unique = <String>{};
  return result.where((item) => unique.add(item.path)).toList(growable: false);
}

Future<bool> _isHealthy(String baseUrl) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
  try {
    final request = await client.getUrl(Uri.parse('$baseUrl/health')).timeout(const Duration(seconds: 3));
    final response = await request.close().timeout(const Duration(seconds: 3));
    if (response.statusCode != HttpStatus.ok) return false;
    final body = await utf8.decoder.bind(response).join().timeout(const Duration(seconds: 3));
    final payload = jsonDecode(body);
    return payload is Map<String, dynamic> && payload['status'] == 'ok';
  } on Object {
    return false;
  } finally {
    client.close(force: true);
  }
}
