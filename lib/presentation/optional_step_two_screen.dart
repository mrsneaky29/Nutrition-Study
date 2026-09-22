import 'package:flutter/material.dart';

import 'app_strings.dart';
import 'presentation_widgets.dart';

class OptionalStepTwoScreen extends StatefulWidget {
  const OptionalStepTwoScreen({
    this.onContinue,
    this.onSkip,
    this.onBack,
    super.key,
  });

  final ValueChanged<String?>? onContinue;
  final VoidCallback? onSkip;
  final VoidCallback? onBack;

  @override
  State<OptionalStepTwoScreen> createState() => _OptionalStepTwoScreenState();
}

class _OptionalStepTwoScreenState extends State<OptionalStepTwoScreen> {
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ResponsivePage(
    appBar: AppBar(leading: BackButton(onPressed: widget.onBack)),
    child: ListView(
      children: [
        const PageHeading(
          title: AppStrings.optionalStepTwo,
          subtitle: 'Optional information can be added only when appropriate.',
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _note,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Optional note',
                    hintText: 'Leave blank to continue without this step.',
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () => widget.onContinue?.call(
                    _note.text.trim().isEmpty ? null : _note.text.trim(),
                  ),
                  child: const Text(AppStrings.continueLabel),
                ),
                TextButton(
                  onPressed: widget.onSkip,
                  child: const Text('Skip this optional step'),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
