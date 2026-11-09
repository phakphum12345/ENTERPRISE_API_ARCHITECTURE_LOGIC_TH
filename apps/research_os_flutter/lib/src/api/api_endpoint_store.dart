import 'package:shared_preferences/shared_preferences.dart';

import 'api_endpoint_registry_stub.dart'
    if (dart.library.io) 'api_endpoint_registry_io.dart' as endpoint_registry;

class ApiEndpointStore {
  ApiEndpointStore._();

  static const _storageKey = 'research_os_api_base_url_v1';
  static const renderDefault = 'https://research-os-api-phakphoum.onrender.com';

  static const loginWindows = 'windows';
  static const loginGitHub = 'github';
  static const loginGoogle = 'google';
  static const loginNone = 'none';
  static const loginCustom = 'custom';

  static const userLevelOwner = 'owner';
  static const userLevelDeveloper = 'developer';
  static const userLevelGeneral = 'general';

  static const buildDefault = String.fromEnvironment(
    'RESEARCH_OS_API_BASE_URL',
    defaultValue: renderDefault,
  );

  static Future<String> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_storageKey)?.trim();

    // A deliberate HTTPS selection remains authoritative. Otherwise prefer a
    // healthy local service discovered by stable service ID, never a fixed port.
    if (saved != null && saved.isNotEmpty) {
      final savedUri = Uri.tryParse(normalize(saved));
      if (savedUri?.scheme == 'https') return normalize(saved);
    }

    final localEndpoint = await endpoint_registry.discoverLocalApiEndpoint();
    if (localEndpoint != null) return normalize(localEndpoint);

    // Do not retain a stale loopback URL after a service restart or port change.
    if (saved != null && saved.isNotEmpty) {
      final savedUri = Uri.tryParse(normalize(saved));
      if (savedUri != null &&
          !{'127.0.0.1', 'localhost', '::1'}.contains(savedUri.host)) {
        return normalize(saved);
      }
    }

    return normalize(buildDefault);
  }

  static Future<void> save(String value) async {
    final normalized = normalize(value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, normalized);
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
  }

  static String normalize(String value) {
    var normalized = value.trim();
    while (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    final uri = Uri.tryParse(normalized);
    if (uri == null ||
        !uri.hasScheme ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      throw const FormatException(
        'API Base URL must start with http:// or https://.',
      );
    }
    return normalized;
  }
}
