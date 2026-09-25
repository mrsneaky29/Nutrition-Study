import 'package:flutter/material.dart';

import '../domain/participant_id.dart';
import 'presentation_widgets.dart';
import 'view_models.dart';

class ParticipantLookupScreen extends StatefulWidget {
  const ParticipantLookupScreen({
    this.initialStudyId,
    this.allowOfflineStudyIdLookup = false,
    this.onSubmit,
    this.onCancel,
    super.key,
  });

  final String? initialStudyId;
  final bool allowOfflineStudyIdLookup;
  final ValueChanged<ParticipantDraft>? onSubmit;
  final VoidCallback? onCancel;

  @override
  State<ParticipantLookupScreen> createState() =>
      _ParticipantLookupScreenState();
}

class _ParticipantLookupScreenState extends State<ParticipantLookupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _studyId = TextEditingController();
  bool _lookupByStudyId = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _studyId.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    if (_lookupByStudyId) {
      widget.onSubmit?.call(
        ParticipantDraft(
          studyId: normalizeParticipantStudyId(_studyId.text)!,
          name: '',
          phone: '',
        ),
      );
      return;
    }
    widget.onSubmit?.call(
      ParticipantDraft(
        studyId: '',
        name: _name.text.trim(),
        phone: _phone.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ResponsivePage(
    appBar: AppBar(leading: BackButton(onPressed: widget.onCancel)),
    child: ListView(
      children: [
        const PageHeading(
          title: 'Participant',
          subtitle: 'Find a participant or start a new participant record.',
        ),
        if (widget.allowOfflineStudyIdLookup && !_lookupByStudyId)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => _lookupByStudyId = true),
              icon: const Icon(Icons.search),
              label: const Text('Repeat visit using Study ID'),
            ),
          ),
        if (widget.allowOfflineStudyIdLookup && _lookupByStudyId)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => _lookupByStudyId = false),
              icon: const Icon(Icons.arrow_back),
              label: const Text('Find by name and phone'),
            ),
          ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_lookupByStudyId) ...[
                    const Text(
                      'Looks up saved visits on this phone, so it works without internet. '
                      'Use the Study ID printed on the participant’s card or logbook.',
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _studyId,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(
                        labelText: 'Study ID from card/logbook',
                        hintText: 'C07-000123 or P001',
                      ),
                      validator: (value) =>
                          normalizeParticipantStudyId(value) == null
                          ? 'Enter a valid Study ID, such as C07-000123.'
                          : null,
                    ),
                  ] else ...[
                    TextFormField(
                      controller: _name,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Participant name',
                      ),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                          ? 'Enter a participant name.'
                          : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Phone number',
                      ),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                          ? 'Enter a phone number.'
                          : null,
                    ),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _submit,
                    child: Text(
                      _lookupByStudyId
                          ? 'Find saved participant'
                          : 'Find participant',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
