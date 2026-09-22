import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'participant_details.dart';

class AssessmentScreen extends StatefulWidget {
  const AssessmentScreen({super.key});

  @override
  State<AssessmentScreen> createState() => _AssessmentScreenState();
}

class _AssessmentScreenState extends State<AssessmentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _participantIdController = TextEditingController();
  final _ageController = TextEditingController();

  ParticipantDetails? _reviewedDetails;

  @override
  void dispose() {
    _participantIdController.dispose();
    _ageController.dispose();
    super.dispose();
  }

  void _checkDetails() {
    final normalizedId = _participantIdController.text.trim().toUpperCase();
    _participantIdController.value = TextEditingValue(
      text: normalizedId,
      selection: TextSelection.collapsed(offset: normalizedId.length),
    );

    if (!(_formKey.currentState?.validate() ?? false)) {
      setState(() => _reviewedDetails = null);
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _reviewedDetails = ParticipantDetails(
        participantId: normalizedId,
        age: int.parse(_ageController.text.trim()),
      );
    });
  }

  void _clearReview() {
    if (_reviewedDetails != null) {
      setState(() => _reviewedDetails = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: SelectionArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _Header(),
                    const SizedBox(height: 24),
                    Card(
                      elevation: 0,
                      color: colors.surface,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                        side: const BorderSide(color: Color(0xFFDCE7E1)),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                'Participant details',
                                style: Theme.of(context).textTheme.titleLarge
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Use the assigned study ID. Do not enter a name or phone number.',
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(color: colors.onSurfaceVariant),
                              ),
                              const SizedBox(height: 24),
                              TextFormField(
                                controller: _participantIdController,
                                textCapitalization:
                                    TextCapitalization.characters,
                                textInputAction: TextInputAction.next,
                                autovalidateMode:
                                    AutovalidateMode.onUserInteraction,
                                decoration: const InputDecoration(
                                  labelText: 'Participant ID',
                                  hintText: 'P001',
                                  helperText:
                                      'Assigned IDs range from P001 to P200',
                                  prefixIcon: Icon(Icons.badge_outlined),
                                ),
                                validator: ParticipantDetails.validateId,
                                onChanged: (_) => _clearReview(),
                              ),
                              const SizedBox(height: 20),
                              TextFormField(
                                controller: _ageController,
                                keyboardType: TextInputType.number,
                                textInputAction: TextInputAction.done,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                ],
                                autovalidateMode:
                                    AutovalidateMode.onUserInteraction,
                                decoration: const InputDecoration(
                                  labelText: 'Age',
                                  hintText: '30–40',
                                  helperText: 'Enter age in completed years',
                                  prefixIcon: Icon(Icons.cake_outlined),
                                ),
                                validator: ParticipantDetails.validateAge,
                                onChanged: (_) => _clearReview(),
                                onFieldSubmitted: (_) => _checkDetails(),
                              ),
                              const SizedBox(height: 24),
                              FilledButton.icon(
                                onPressed: _checkDetails,
                                icon: const Icon(Icons.fact_check_outlined),
                                label: const Text('Check details'),
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 16,
                                  ),
                                  textStyle: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (_reviewedDetails case final details?) ...[
                      const SizedBox(height: 18),
                      _ReviewCard(details: details),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: colors.primaryContainer,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(Icons.eco_outlined, color: colors.onPrimaryContainer),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Nutrition & lifestyle',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: colors.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Participant assessment',
                style: Theme.of(context).textTheme.bodyLarge
                    ?.copyWith(color: colors.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({required this.details});

  final ParticipantDetails details;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFFE7F4EE),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFB8D9CB)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.check_circle_outline, color: colors.primary),
                const SizedBox(width: 10),
                Text(
                  'Ready to review',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colors.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _ReviewRow(label: 'Participant ID', value: details.participantId),
            const SizedBox(height: 10),
            _ReviewRow(label: 'Age', value: '${details.age} years'),
            const SizedBox(height: 16),
            const Text(
              'These details have not been saved yet.',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReviewRow extends StatelessWidget {
  const _ReviewRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(width: 16),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
      ],
    );
  }
}
