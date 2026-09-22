class ParticipantDetails {
  const ParticipantDetails({required this.participantId, required this.age});

  final String participantId;
  final int age;

  static String? validateId(String? value) {
    final id = (value ?? '').trim().toUpperCase();
    if (!RegExp(r'^P\d{3}$').hasMatch(id)) {
      return 'Enter an ID from P001 to P200.';
    }
    final number = int.parse(id.substring(1));
    if (number < 1 || number > 200) {
      return 'Enter an ID from P001 to P200.';
    }
    return null;
  }

  static String? validateAge(String? value) {
    final age = int.tryParse((value ?? '').trim());
    if (age == null || age < 30 || age > 40) {
      return 'Enter an age between 30 and 40 years.';
    }
    return null;
  }
}
