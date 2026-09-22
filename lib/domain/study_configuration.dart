/// Rules used to generate and validate study participant identifiers.
class ParticipantIdPolicy {
  const ParticipantIdPolicy({
    required this.prefix,
    required this.firstNumber,
    required this.lastNumber,
    this.padding = 3,
  }) : assert(prefix != ''),
       assert(firstNumber > 0),
       assert(lastNumber >= firstNumber),
       assert(padding > 0);

  final String prefix;
  final int firstNumber;
  final int lastNumber;
  final int padding;

  String format(int number) {
    if (!contains(number)) {
      throw ArgumentError.value(number, 'number', 'Outside the study range.');
    }
    return '$prefix${number.toString().padLeft(padding, '0')}';
  }

  bool contains(int number) => number >= firstNumber && number <= lastNumber;

  /// Returns a canonical upper-case ID, or null when [value] is invalid.
  String? normalize(String? value) {
    final candidate = (value ?? '').trim().toUpperCase();
    final expectedPrefix = prefix.toUpperCase();
    if (!candidate.startsWith(expectedPrefix)) return null;

    final digits = candidate.substring(expectedPrefix.length);
    if (digits.length != padding || !RegExp(r'^\d+$').hasMatch(digits)) {
      return null;
    }
    final number = int.tryParse(digits);
    if (number == null || !contains(number)) return null;
    return '$expectedPrefix${number.toString().padLeft(padding, '0')}';
  }

  Map<String, Object> toMap() => {
    'prefix': prefix,
    'firstNumber': firstNumber,
    'lastNumber': lastNumber,
    'padding': padding,
  };
}
