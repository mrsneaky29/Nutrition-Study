import 'package:flutter_test/flutter_test.dart';
import 'package:project2/domain/participant_id.dart';

void main() {
  test('collector Study IDs normalize without a collector-number cap', () {
    expect(formatCollectorParticipantStudyId(1, 201), 'C01-000201');
    expect(formatCollectorParticipantStudyId(1, 100000000), 'C01-100000000');
    expect(isValidParticipantStudyId('C01-100000000'), isTrue);
    expect(normalizeParticipantStudyId(' c001-000201 '), 'C01-000201');
    expect(extractCollectorNumberFromStudyId('C001-000201'), 1);
    final supportedPrefixes = List.generate(
      101, (index) => collectorParticipantPrefix(index + 1),
    );
    expect(supportedPrefixes.toSet().length, 101);
    expect(supportedPrefixes.first, 'C01-');
    expect(supportedPrefixes[9], 'C10-');
    expect(supportedPrefixes[98], 'C99-');
    expect(supportedPrefixes[99], 'C100-');
    expect(supportedPrefixes.last, 'C101-');
    expect(normalizeParticipantStudyId('C010-000001'), 'C10-000001');
    expect(normalizeParticipantStudyId('c00100-000001'), 'C100-000001');
    expect(formatCollectorParticipantStudyId(100, 1), 'C100-000001');
    expect(collectorParticipantPrefix(100), 'C100-');
  });

  test('rejects zero and malformed Study IDs', () {
    for (final id in [
      'C00-000001', 'C01-000000', 'C01-12345',
      'P000', 'P01', 'P000000',
    ]) {
      expect(isValidParticipantStudyId(id), isFalse, reason: id);
      expect(normalizeParticipantStudyId(id), isNull, reason: id);
    }
    expect(() => formatCollectorParticipantStudyId(0, 1), throwsArgumentError);
    expect(() => collectorParticipantPrefix(0), throwsArgumentError);
  });
}
