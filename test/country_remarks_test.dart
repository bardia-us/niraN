import 'package:flutter_test/flutter_test.dart';
import 'package:niran/core/formatters.dart';

void main() {
  for (final sample in <String, String>{
    '🇫🇷 Paris': 'FR',
    'Paris 🇫🇷': 'FR',
    'Route 🇫🇷 Premium': 'FR',
    'سرور 🇮🇷 ویژه': 'IR',
    'JP🇯🇵Tokyo': 'JP',
  }.entries) {
    test('flag position is independent: ${sample.key}', () {
      expect(countryCodeFromRemark(sample.key), sample.value);
    });
  }
  test(
    'all flags retain their order, deduplicate, and clean only the label',
    () {
      expect(countryCodesFromRemark('🇩🇪 route 🇫🇷 🇩🇪 end 🇳🇱'), [
        'DE',
        'FR',
        'NL',
      ]);
      expect(
        remarkWithoutCountryFlag('🇩🇪 route 🇫🇷 🇩🇪 end 🇳🇱'),
        'route end',
      );
      expect(countryCodesFromRemark('ordinary server'), isEmpty);
      expect(countryCodeFromRemark('partial 🇫'), isNull);
    },
  );
}
