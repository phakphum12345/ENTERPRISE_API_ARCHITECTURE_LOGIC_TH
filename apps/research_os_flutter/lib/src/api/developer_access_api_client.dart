import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_endpoint_registry_stub.dart'
    if (dart.library.io) 'api_endpoint_registry_io.dart' as endpoint_registry;

class DeveloperAccessApiException implements Exception {
  const DeveloperAccessApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class DeveloperAccessApiClient {
  DeveloperAccessApiClient({String? baseUrl, http.Client? client})
      : _baseUrl = _configuredBaseUrl(baseUrl),
        _client = client ?? http.Client();

  static String? _configuredBaseUrl(String? value) {
    final explicit = value?.trim();
    if (explicit != null && explicit.isNotEmpty) return explicit;
    const configured = String.fromEnvironment('RESEARCH_OS_DEVELOPER_API_BASE_URL');
    return configured.trim().isEmpty ? null : configured.trim();
  }

  String? _baseUrl;
  final http.Client _client;

  String get baseUrl => _baseUrl ?? '';

  Future<void> initialize() async {
    if (_baseUrl != null) return;
    final discovered = await endpoint_registry.discoverLocalServiceEndpoint(
      'research-os-developer-api',
    );
    if (discovered == null) {
      throw const DeveloperAccessApiException(
        'Developer API is unavailable: no healthy research-os-developer-api endpoint was discovered.',
      );
    }
    _baseUrl = discovered;
  }

  Uri _uri(String path) {
    final endpoint = _baseUrl;
    if (endpoint == null || endpoint.isEmpty) {
      throw const DeveloperAccessApiException(
        'Developer API endpoint has not been discovered.',
      );
    }
    return Uri.parse('$endpoint$path');
  }

  Future<Map<String, dynamic>> getSession() => _get('/v2/developer/session');

  Future<Map<String, dynamic>> getOwnerRequests({String? status}) async {
    final uri = _uri('/v2/developer/access-requests').replace(
      queryParameters: <String, String>{
        'view': 'owner',
        if (status != null && status.trim().isNotEmpty) 'status': status.trim(),
      },
    );
    return _request(() => _client.get(uri));
  }

  Future<Map<String, dynamic>> getCodeProjects() => _get('/v2/developer/code/projects');

  Future<Map<String, dynamic>> getCodeFiles({
    String project = 'research_os_flutter',
    String query = '',
  }) async {
    final uri = _uri('/v2/developer/code/files').replace(
      queryParameters: <String, String>{
        'project': project,
        if (query.trim().isNotEmpty) 'q': query.trim(),
      },
    );
    return _request(() => _client.get(uri));
  }

  Future<Map<String, dynamic>> readCodeFile(
    String path, {
    String project = 'research_os_flutter',
  }) async {
    final uri = _uri('/v2/developer/code/file/${Uri.encodeComponent(path)}').replace(
      queryParameters: <String, String>{'project': project},
    );
    return _request(() => _client.get(uri));
  }

  Future<Map<String, dynamic>> previewCodeChange({
    required String project,
    required String path,
    required String originalSha256,
    required String content,
  }) =>
      _post('/v2/developer/code/preview', <String, Object?>{
        'project': project,
        'path': path,
        'original_sha256': originalSha256,
        'content': content,
      });

  Future<Map<String, dynamic>> applyCodeChange({
    required String project,
    required String path,
    required String originalSha256,
    required String content,
  }) =>
      _post('/v2/developer/code/apply', <String, Object?>{
        'project': project,
        'path': path,
        'original_sha256': originalSha256,
        'content': content,
      });

  Future<Map<String, dynamic>> getOwnerGrants() async {
    final uri = _uri('/v2/developer/grants').replace(
      queryParameters: const <String, String>{'view': 'owner'},
    );
    return _request(() => _client.get(uri));
  }

  Future<Map<String, dynamic>> approveRequest(
    String requestId, {
    required List<String> scopes,
    int? expiresInSeconds,
  }) =>
      _post(
        '/v2/developer/access-requests/${Uri.encodeComponent(requestId)}/approve',
        <String, Object?>{
          'scopes': scopes,
          if (expiresInSeconds != null) 'expires_in_seconds': expiresInSeconds,
        },
      );

  Future<Map<String, dynamic>> rejectRequest(
    String requestId, {
    String reason = '',
  }) =>
      _post(
        '/v2/developer/access-requests/${Uri.encodeComponent(requestId)}/reject',
        <String, Object?>{'reason': reason},
      );

  Future<Map<String, dynamic>> revokeGrant(
    String grantId, {
    String reason = '',
  }) =>
      _post(
        '/v2/developer/grants/${Uri.encodeComponent(grantId)}/revoke',
        <String, Object?>{'reason': reason},
      );

  Future<Map<String, dynamic>> _get(String path) {
    return _request(() => _client.get(_uri(path)));
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, Object?> payload,
  ) {
    return _request(
      () => _client.post(
        _uri(path),
        headers: const <String, String>{'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      ),
    );
  }

  Future<Map<String, dynamic>> _request(
    Future<http.Response> Function() send,
  ) async {
    try {
      return _decode(await send());
    } on DeveloperAccessApiException {
      rethrow;
    } catch (error) {
      throw DeveloperAccessApiException(
        'เชื่อม Developer API ไม่สำเร็จ: $error',
      );
    }
  }

  Map<String, dynamic> _decode(http.Response response) {
    final Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      throw DeveloperAccessApiException(
        'Developer API returned invalid JSON (${response.statusCode}).',
        statusCode: response.statusCode,
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw DeveloperAccessApiException(
        'Developer API returned an unexpected response shape.',
        statusCode: response.statusCode,
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final rawError = decoded['error'];
      final detail = rawError is Map
          ? rawError['message'] ?? rawError['code'] ?? 'Unknown error'
          : decoded['detail'] ?? rawError ?? 'Unknown error';
      throw DeveloperAccessApiException(
        'Developer API error ${response.statusCode}: $detail',
        statusCode: response.statusCode,
      );
    }
    return decoded;
  }

  void close() => _client.close();
}
