import 'dart:io';

import 'package:flutter/material.dart';

import 'src/friend_app.dart';
import 'src/owner_api.dart';
import 'src/startup_probe.dart';
import 'src/service_endpoint_registry.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final ownerId = Platform.environment['RESEARCH_OS_OWNER_ID'] ?? 'owner';
  final profileId =
      Platform.environment['RESEARCH_OS_OWNER_PROFILE'] ?? 'default';
  final sessionId =
      Platform.environment['RESEARCH_OS_OWNER_SESSION'] ?? 'desktop';
  final configuredFriendUrl =
      Platform.environment['RESEARCH_OS_FRIEND_URL']?.trim();
  final baseUrl = configuredFriendUrl != null && configuredFriendUrl.isNotEmpty
      ? configuredFriendUrl
      : await discoverOwnerFriendEndpoint() ?? '';

  final api = HttpOwnerFriendApi(
    baseUrl: baseUrl,
    ownerId: ownerId,
    profileId: profileId,
    sessionId: sessionId,
  );
  registerOwnerFriendApi(api);

  Map<String, dynamic>? startup;
  String? startupError;

  try {
    startup = await OwnerStartupProbe(api).run();
  } catch (error) {
    startupError = error.toString();
  }

  runApp(
    OwnerFriendApp(
      api: api,
      startup: startup,
      startupError: startupError,
    ),
  );
}
