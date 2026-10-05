import 'package:flutter/material.dart';

import '../../api/research_os_api_client.dart';
import '../../ui/enterprise_components.dart';

class ApiManagementPage extends StatefulWidget {
  const ApiManagementPage({required this.apiClient, super.key});

  final ResearchOSApiClient apiClient;

  @override
  State<ApiManagementPage> createState() => _ApiManagementPageState();
}

class _ApiManagementPageState extends State<ApiManagementPage> {
  bool _loading = true;
  bool _creating = false;
  String? _error;
  String _principalId = '';
  List<Map<String, dynamic>> _applications = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _keys = <Map<String, dynamic>>[];
  Map<String, dynamic>? _newSecret;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final auth = await widget.apiClient.getAuthStatus();
      final applications = await widget.apiClient.getPlatformResource('applications');
      final keys = <Map<String, dynamic>>[];
      for (final application in _items(applications)) {
        final applicationId = '\${application['application_id'] ?? ''}'.trim();
        if (applicationId.isEmpty) continue;
        final value = await widget.apiClient.getPlatformKeys(applicationId);
        for (final key in _items(value)) {
          keys.add(<String, dynamic>{...key, 'application_name': application['name']});
        }
      }
      if (!mounted) return;
      setState(() {
        final account = auth['account'];
        _principalId = account is Map ? '\${account['user_id'] ?? ''}'.trim() : '';
        _applications = _items(applications);
        _keys = keys;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '\$error';
      });
    }
  }

  List<Map<String, dynamic>> _items(Map<String, dynamic> value) {
    final raw = value['items'];
    if (raw is! List) return <Map<String, dynamic>>[];
    return raw.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList();
  }

  Future<void> _createCredential() async {
    if (_creating) return;
    setState(() {
      _creating = true;
      _error = null;
      _newSecret = null;
    });
    try {
      final stamp = DateTime.now().toUtc().millisecondsSinceEpoch;
      final orgId = 'org_\$stamp';
      final projectId = 'proj_\$stamp';
      final appId = 'app_\$stamp';
      const scopeId = 'scope:api.execute';
      final planId = 'plan_\$stamp';
      final entitlementId = 'ent_\$stamp';

      await widget.apiClient.createPlatformResource('organizations', <String, Object?>{
        'organization_id': orgId,
        'name': 'Research OS Developer',
      });
      await widget.apiClient.createPlatformResource('projects', <String, Object?>{
        'project_id': projectId,
        'organization_id': orgId,
        'name': 'Developer Application',
      });
      await widget.apiClient.createPlatformResource('applications', <String, Object?>{
        'application_id': appId,
        'project_id': projectId,
        'name': 'Research OS SDK Client',
      });
      await widget.apiClient.createPlatformResource('scopes', <String, Object?>{
        'scope_id': scopeId,
        'name': scopeId,
        'description': 'Governed API execution capability.',
      });
      await widget.apiClient.createPlatformResource('plans', <String, Object?>{
        'plan_id': planId,
        'project_id': projectId,
        'name': 'Developer',
      });
      await widget.apiClient.createPlatformResource('entitlements', <String, Object?>{
        'entitlement_id': entitlementId,
        'plan_id': planId,
        'scope_ids': <String>[scopeId],
      });
      final key = await widget.apiClient.createPlatformKey(
        appId,
        <String, Object?>{
          'principal_id': _principalId,
          'entitlement_id': entitlementId,
          'scopes': <String>[scopeId],
        },
      );
      if (!mounted) return;
      setState(() {
        _newSecret = key;
        _creating = false;
      });
      await _refresh();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _creating = false;
        _error = '\$error';
      });
    }
  }

  Future<void> _revoke(String keyId) async {
    try {
      await widget.apiClient.revokePlatformKey(keyId);
      await _refresh();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '\$error');
    }
  }

  Future<void> _rotate(String keyId) async {
    try {
      final rotated = await widget.apiClient.rotatePlatformKey(keyId, const <String, Object?>{});
      if (!mounted) return;
      setState(() => _newSecret = rotated);
      await _refresh();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '\$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 32),
      children: <Widget>[
        EnterprisePageHeader(
          icon: Icons.vpn_key_outlined,
          title: 'API Management',
          subtitle: 'สร้าง Application และ API Credential ผ่าน canonical /platform/v1 management plane โดยไม่สร้าง execution kernel ซ้ำ',
          actions: <Widget>[
            IconButton(onPressed: _loading ? null : _refresh, icon: const Icon(Icons.refresh)),
          ],
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: <Widget>[
            EnterpriseStatusTile(
              icon: Icons.person_outline,
              title: 'Principal',
              value: _principalId.isEmpty ? 'Unavailable' : _principalId,
              caption: 'จาก verified session',
            ),
            EnterpriseStatusTile(
              icon: Icons.apps_outlined,
              title: 'Applications',
              value: '\${_applications.length}',
              caption: 'management registry',
            ),
            EnterpriseStatusTile(
              icon: Icons.key_outlined,
              title: 'Credentials',
              value: '\${_keys.length}',
              caption: 'metadata + lifecycle',
            ),
          ],
        ),
        const SizedBox(height: 24),
        if (_error != null)
          Card(
            child: ListTile(
              leading: const Icon(Icons.error_outline),
              title: const Text('API Management error'),
              subtitle: SelectableText(_error!),
            ),
          ),
        if (_newSecret != null) ...<Widget>[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text('Secret shown once', style: TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  const Text('คัดลอกค่า secret นี้ไปเก็บใน secret manager ของคุณทันที ระบบจะไม่แสดง raw secret จาก storage อีกครั้ง'),
                  const SizedBox(height: 12),
                  SelectableText('\${_newSecret!['raw_secret'] ?? '(secret unavailable)'}'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
        EnterpriseSection(
          title: 'Developer credential',
          subtitle: 'Bootstrap Organization → Project → Application → Scope → Plan → Entitlement → API Key',
          child: FilledButton.icon(
            onPressed: _creating || _principalId.isEmpty ? null : _createCredential,
            icon: _creating ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.add_moderator_outlined),
            label: Text(_creating ? 'กำลังสร้าง…' : 'สร้าง API Credential'),
          ),
        ),
        const SizedBox(height: 20),
        EnterpriseSection(
          title: 'Applications',
          subtitle: 'Applications เป็น consumer identity ของ credential',
          child: _loading
              ? const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
              : _applications.isEmpty
                  ? const Card(child: ListTile(title: Text('ยังไม่มี Application')))
                  : Column(
                      children: _applications.map((app) => Card(
                        child: ListTile(
                          leading: const Icon(Icons.apps_outlined),
                          title: Text('\${app['name'] ?? app['application_id']}'),
                          subtitle: Text('\${app['application_id']} • project \${app['project_id']}'),
                        ),
                      )).toList(),
                    ),
        ),
        const SizedBox(height: 20),
        EnterpriseSection(
          title: 'API Keys',
          subtitle: 'Raw secret ไม่อยู่ใน list; lifecycle ผ่าน revoke / rotate',
          child: _keys.isEmpty
              ? const Card(child: ListTile(title: Text('ยังไม่มี API Key')))
              : Column(
                  children: _keys.map((key) {
                    final revoked = key['revoked_at'] != null;
                    final keyId = '\${key['key_id']}';
                    return Card(
                      child: ListTile(
                        leading: Icon(revoked ? Icons.block_outlined : Icons.key_outlined),
                        title: Text(keyId),
                        subtitle: Text('\${key['application_name'] ?? ''} • \${key['fingerprint'] ?? ''}'),
                        trailing: Wrap(
                          spacing: 4,
                          children: <Widget>[
                            IconButton(
                              tooltip: 'Rotate',
                              onPressed: revoked ? null : () => _rotate(keyId),
                              icon: const Icon(Icons.autorenew),
                            ),
                            IconButton(
                              tooltip: 'Revoke',
                              onPressed: revoked ? null : () => _revoke(keyId),
                              icon: const Icon(Icons.block_outlined),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
        ),
        const SizedBox(height: 20),
        const Card(
          child: ListTile(
            leading: Icon(Icons.security_outlined),
            title: Text('Authority boundary'),
            subtitle: Text('Management state และ API credential metadata ไม่ได้ grant execution โดยตัวเอง; runtime authorization ยังคงเป็นหน้าที่ของ ResourceControlPlane'),
          ),
        ),
      ],
    );
  }
}
