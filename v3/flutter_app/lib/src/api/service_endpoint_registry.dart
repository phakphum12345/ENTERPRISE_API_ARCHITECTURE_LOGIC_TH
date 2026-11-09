import 'dart:convert';
import 'dart:io';

Future<String?> discoverV3Endpoint({
  List<Directory>? searchDirectories,
}) async {
  final directories = searchDirectories ?? _registryDirectories();
  for (final directory in directories) {
    final file = File('${directory.path}${Platform.pathSeparator}research-os-v3.json');
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic> ||
          decoded['schema_version'] != 1 ||
          decoded['service'] != 'research-os-v3' ||
          decoded['protocol'] != 'http') {
        continue;
      }
      final host = decoded['host'];
      final port = decoded['port'];
      final baseUrl = decoded['base_url'];
      if (host != '127.0.0.1' && host != 'localhost' && host != '::1') continue;
      if (port is! int || port < 1 || port > 65535 || baseUrl is! String) continue;
      final authorityHost = host == '::1' ? '[$host]' : host as String;
      if (baseUrl != 'http://$authorityHost:$port') continue;
      if (await _healthy(baseUrl)) return baseUrl;
    } on Object {
      continue;
    }
  }
  return null;
}

List<Directory> _registryDirectories() {
  final result = <Directory>[];
  final explicit = Platform.environment['RESEARCH_OS_SERVICE_REGISTRY_DIR']?.trim();
  if (explicit != null && explicit.isNotEmpty) result.add(Directory(explicit));
  final configured = Platform.environment['RESEARCH_OS_V3_DATA_DIR']?.trim();
  if (configured != null && configured.isNotEmpty) {
    result.add(Directory('$configured${Platform.pathSeparator}run${Platform.pathSeparator}services'));
  } else if (Platform.isWindows) {
    final programData = Platform.environment['PROGRAMDATA']?.trim();
    if (programData != null && programData.isNotEmpty) {
      result.add(Directory('$programData${Platform.pathSeparator}ResearchOSV3${Platform.pathSeparator}run${Platform.pathSeparator}services'));
    }
  } else {
    final dataHome = Platform.environment['XDG_DATA_HOME']?.trim();
    if (dataHome != null && dataHome.isNotEmpty) {
      result.add(Directory('$dataHome${Platform.pathSeparator}research-os-v3${Platform.pathSeparator}run${Platform.pathSeparator}services'));
    } else {
      final home = Platform.environment['HOME'] ?? Directory.current.path;
      result.add(Directory('$home${Platform.pathSeparator}.local${Platform.pathSeparator}share${Platform.pathSeparator}research-os-v3${Platform.pathSeparator}run${Platform.pathSeparator}services'));
    }
  }
  final seen = <String>{};
  return result.where((directory) => seen.add(directory.path)).toList(growable: false);
}

Future<bool> _healthy(String baseUrl) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
  try {
    final request = await client.getUrl(Uri.parse('$baseUrl/health')).timeout(const Duration(seconds: 3));
    final response = await request.close().timeout(const Duration(seconds: 3));
    if (response.statusCode != HttpStatus.ok) return false;
    final body = await utf8.decoder.bind(response).join().timeout(const Duration(seconds: 3));
    final decoded = jsonDecode(body);
    return decoded is Map<String, dynamic> && decoded['status'] == 'ok';
  } on Object {
    return false;
  } finally {
    client.close(force: true);
  }
}
