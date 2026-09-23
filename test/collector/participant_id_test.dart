import 'package:flutter_test/flutter_test.dart';
import 'package:project2/domain/participant_id.dart';

void main() {
  test('collector Study IDs normalize consistently without a 200 cap', () {
    expect(formatCollectorParticipantStudyId(1, 201), 'C01-000201');
    expect(formatCollectorParticipantStudyId(1, 100000000), 'C01-100000000');
    expect(isValidParticipantStudyId('C01-100000000'), isTrue);
    expect(normalizeParticipantStudyId(' c001-000201 '), 'C01-000201');
    expect(extractCollectorNumberFromStudyId('C001-000201'), 1);
    final supportedPrefixes = List.generate(
      99, (index) => collectorParticipantPrefix(index + 1),
    );
    expect(supportedPrefixes.toSet().length, 99);
    expect(supportedPrefixes.first, 'C01-');
    expect(supportedPrefixes[9], 'C10-');
    expect(supportedPrefixes.last, 'C99-');
    expect(normalizeParticipantStudyId('C010-000001'), 'C10-000001');
  });

  test('rejects zero, out-of-range collector and malformed Study IDs', () {
    for (final id in [
      'C00-000001', 'C100-000001', 'C01-000000', 'C01-12345',
      'P000', 'P01', 'P000000',
    ]) {
      expect(isValidParticipantStudyId(id), isFalse, reason: id);
      expect(normalizeParticipantStudyId(id), isNull, reason: id);
    }
    expect(() => formatCollectorParticipantStudyId(100, 1), throwsArgumentError);
    expect(() => collectorParticipantPrefix(0), throwsArgumentError);
  });
}
