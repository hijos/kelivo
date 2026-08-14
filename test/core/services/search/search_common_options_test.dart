import 'package:Kelivo/core/services/search/search_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SearchCommonOptions timeout', () {
    test('defaults to 60 seconds', () {
      const options = SearchCommonOptions();

      expect(options.timeout, 60000);
      expect(options.timeout, SearchCommonOptions.defaultTimeoutMs);
    });

    test('restores existing persisted timeout values', () {
      final options = SearchCommonOptions.fromJson({
        'resultSize': 7,
        'timeout': 5000,
      });

      expect(options.resultSize, 7);
      expect(options.timeout, 5000);
    });

    test('uses the new default for missing or invalid values', () {
      expect(
        SearchCommonOptions.fromJson(const {}).timeout,
        SearchCommonOptions.defaultTimeoutMs,
      );
      expect(
        SearchCommonOptions.fromJson({'timeout': 'invalid'}).timeout,
        SearchCommonOptions.defaultTimeoutMs,
      );
    });

    test('clamps restored values to the supported range', () {
      expect(
        SearchCommonOptions.fromJson({'timeout': 0}).timeout,
        SearchCommonOptions.minTimeoutMs,
      );
      expect(
        SearchCommonOptions.fromJson({'timeout': 999999}).timeout,
        SearchCommonOptions.maxTimeoutMs,
      );
      expect(
        SearchCommonOptions.fromJson({'timeout': '120000'}).timeout,
        SearchCommonOptions.maxTimeoutMs,
      );
    });
  });
}
