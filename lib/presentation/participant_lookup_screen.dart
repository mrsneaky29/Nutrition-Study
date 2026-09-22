import 'package:flutter/material.dart';

import 'presentation_widgets.dart';
import 'view_models.dart';

class ParticipantLookupScreen extends StatefulWidget {
  const ParticipantLookupScreen({
    this.initialStudyId,
    this.onSubmit,
    this.onCancel,
    super.key,
  });

  final String? initialStudyId;
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

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
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
          subtitle: 'Enter name and phone. Participant and visit numbers are assigned automatically.',
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: _name,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Participant name',
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
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
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Enter a phone number.'
                        : null,
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _submit,
                    child: const Text('Find participant'),
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
