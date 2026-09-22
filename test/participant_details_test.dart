import 'package:flutter_test/flutter_test.dart';
import 'package:project2/participant_details.dart';

void main() {
  test('participant IDs accept study boundaries and normalized input', () {
    for (final id in ['P001', 'P200', ' p050 ']) {
      expect(ParticipantDetails.validateId(id), isNull);
    }
    for (final id in [null, '', 'P000', 'P201', 'P01', 'Alice']) {
      expect(ParticipantDetails.validateId(id), isNotNull);
    }
  });
  test('age accepts only whole years within study range', () {
    for (final age in ['30', '35', '40']) {
      expect(ParticipantDetails.validateAge(age), isNull);
    }
    for (final age in [null, '', '29', '41', '35.5', 'abc']) {
      expect(ParticipantDetails.validateAge(age), isNotNull);
    }
  });
}
