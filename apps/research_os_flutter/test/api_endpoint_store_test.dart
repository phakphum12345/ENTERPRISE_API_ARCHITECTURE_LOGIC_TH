import 'package:flutter_test/flutter_test.dart';
import 'package:research_os_flutter/src/api/api_endpoint_store.dart';

void main() {
  test('build default follows the compile-time API contract', () {
    const expected = String.fromEnvironment(
      'RESEARCH_OS_API_BASE_URL',
      defaultValue: ApiEndpointStore.renderDefault,
    );
    expect(ApiEndpointStore.buildDefault, expected);
  });

  test('dynamic loopback endpoint is accepted without a fixed port', () {
    expect(
      ApiEndpointStore.normalize('http://127.0.0.1:43127'),
      'http://127.0.0.1:43127',
    );
  });

}
