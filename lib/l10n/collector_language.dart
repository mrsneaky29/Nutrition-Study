import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'app_localizations.dart';
import 'collector_copy.dart';

abstract interface class CollectorLanguageStore {
  Future<String?> read();
  Future<void> write(String language);
}

class SecureCollectorLanguageStore implements CollectorLanguageStore {
  const SecureCollectorLanguageStore();
  static const storageKey = 'vivayu_collector_language_v1';
  static const _storage = FlutterSecureStorage();
  @override
  Future<String?> read() => _storage.read(key: storageKey);
  @override
  Future<void> write(String language) =>
      _storage.write(key: storageKey, value: language);
}

class CollectorLanguageController extends ChangeNotifier {
  CollectorLanguageController({CollectorLanguageStore? store})
    : _store = store ?? const SecureCollectorLanguageStore();
  final CollectorLanguageStore _store;
  Locale _locale = const Locale('en');
  Locale get locale => _locale;
  bool _selected = false;
  bool _disposed = false;
  Future<void> _writes = Future<void>.value();

  Future<void> load() async {
    String? language;
    try {
      language = await _store.read();
    } catch (_) {
      // Language preferences must never block access to saved study records.
    }
    if (_selected || _disposed) return;
    _locale = Locale(language == 'te' ? 'te' : 'en');
    notifyListeners();
  }

  Future<void> select(String language) async {
    if (_disposed) return;
    if (language != 'en' && language != 'te') return;
    _selected = true;
    _locale = Locale(language);
    notifyListeners();
    // Serialize writes so rapid toggles always persist the final selection.
    _writes = _writes.then((_) async {
      try {
        await _store.write(language);
      } catch (_) {
        // The in-memory selection still works if device storage is unavailable.
      }
    });
    await _writes;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class CollectorLanguageScope
    extends InheritedNotifier<CollectorLanguageController> {
  const CollectorLanguageScope({
    required CollectorLanguageController controller,
    required super.child,
    super.key,
  }) : super(notifier: controller);
  static CollectorLanguageController? of(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<CollectorLanguageScope>()
      ?.notifier;
}

/// Only pass application-owned copy here; names, notes and IDs remain raw Text.
String collectorText(BuildContext context, String text) {
  final localization = Localizations.of<AppLocalizations>(
    context,
    AppLocalizations,
  );
  return localization == null
      ? text
      : translateCollectorCopy(localization, text);
}

class CollectorText extends StatelessWidget {
  const CollectorText(
    this.data, {
    this.style,
    this.textAlign,
    this.overflow,
    this.maxLines,
    this.softWrap,
    super.key,
  });
  final String data;
  final TextStyle? style;
  final TextAlign? textAlign;
  final TextOverflow? overflow;
  final int? maxLines;
  final bool? softWrap;
  @override
  Widget build(BuildContext context) => Text(
    collectorText(context, data),
    style: style,
    textAlign: textAlign,
    overflow: overflow,
    maxLines: maxLines,
    softWrap: softWrap,
  );
}

/// Lives above the Navigator so every collector route retains the same toggle.
class CollectorLanguageBar extends StatelessWidget {
  const CollectorLanguageBar({super.key});
  @override
  Widget build(BuildContext context) {
    final controller = CollectorLanguageScope.of(context);
    if (controller == null) return const SizedBox.shrink();
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Flexible(
                child: SegmentedButton<String>(
                  key: const Key('collector-language-toggle'),
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: 'en', label: Text('English')),
                    ButtonSegment(
                      value: 'te',
                      label: Text(
                        'తెలుగు',
                        style: TextStyle(fontFamily: 'NotoSansTelugu'),
                      ),
                    ),
                  ],
                  selected: {controller.locale.languageCode},
                  onSelectionChanged: (selection) =>
                      controller.select(selection.single),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
