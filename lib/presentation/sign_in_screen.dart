import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_strings.dart';
import 'presentation_widgets.dart';

class SignInScreen extends StatefulWidget {
  const SignInScreen({this.onSignIn, super.key});

  final ValueChanged<CollectorAccessInput>? onSignIn;

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class CollectorAccessInput {
  const CollectorAccessInput({required this.collectorCode});

  final String collectorCode;
}

class _SignInScreenState extends State<SignInScreen> {
  final _formKey = GlobalKey<FormState>();
  final _collectorCode = TextEditingController();

  @override
  void dispose() {
    _collectorCode.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      final number = int.parse(_collectorCode.text.trim());
      widget.onSignIn?.call(
        CollectorAccessInput(
          collectorCode: 'C${number.toString().padLeft(3, '0')}',
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => ResponsivePage(
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.health_and_safety_outlined,
                    size: 48,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    AppStrings.appName,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Enter the collector number created by the administrator. '
                    'The first phone to use it becomes the assigned phone.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 28),
                  TextFormField(
                    controller: _collectorCode,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: 'Collector number',
                      hintText: '1',
                    ),
                    validator: (value) =>
                        !RegExp(r'^[1-9]\d*$').hasMatch(value?.trim() ?? '')
                        ? 'Enter a number such as 1.'
                        : null,
                    onFieldSubmitted: (_) => _submit(),
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _submit,
                    child: const Text('Continue'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
