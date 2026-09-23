import 'package:flutter_test/flutter_test.dart';
import 'package:project2/domain/participant_id.dart';

void main() {
  test(
    'long random-sequence Study IDs preserve canonical collector and sequence',
    () {
      const ids = [
        'C07-1000000000000001',
        'C07-8999999999999999',
        'C12-1000000000000001',
      ];
      expect(ids.toSet().length, ids.length);
      for (final id in ids) {
        expect(normalizeParticipantStudyId(id), id);
        expect(isValidParticipantStudyId(id), isTrue);
      }
      expect(extractCollectorNumberFromStudyId(ids.first), 7);
      expect(extractCollectorNumberFromStudyId(ids.last), 12);
      expect(formatCollectorParticipantStudyId(7, 1000000000000001), ids.first);
    },
  );
}
