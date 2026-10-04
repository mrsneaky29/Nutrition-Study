# Vivayu +9 — Telugu collector verification

Verified on 2026-10-04. Release label: **Vivayu +9**. Visible Android name:
**Vivayu**. Android metadata: `1.0.2+10`; build number 10 advances the official
+8.1 package's build number 9. It is not a release called +10.

## Scope and compatibility

- English/తెలుగు toggle lives above the collector Navigator, including sign-in,
  scanner, saved visits, questionnaire, review and receipts. Switching is display
  only and retains the existing route, controllers and entered answers.
- English is the default and fallback for missing/unreadable preferences.
  The separate `vivayu_collector_language_v1` secure-storage key survives logout.
  Late reads cannot overwrite a selection; writes are serialized for rapid taps.
- Flutter localization bundles supply Telugu copy and standard localized widgets.
  Noto Sans Telugu is bundled under its SIL Open Font License for offline use.
- Names, notes, identifiers and units remain unchanged. The phone keyboard
  language is not switched by the app; existing English keyboards remain usable.
  Numeric measurement input types remain unchanged.
- Canonical questionnaire values, calculations, schema 3, drafts, local records,
  idempotency keys and sync payloads are unchanged. No server migration is needed.
- Admin remains English. Admin answers are still rendered from canonical codes;
  Telugu entered names/notes remain Telugu, not automatically translated.

## Checks and evidence

- `node tool/check_collector_translations.js`: both bundles have matching keys
  and placeholders; every translation includes Telugu script. A Dart test also
  checks every exact/interpolated bundle message through the display adapter.
- `flutter analyze --no-pub`: no issues found.
- Full default test suite: **305 passed, 14 configuration-dependent skips**.
- Generic-release configuration: **25 passed, 2 public-mode skips**.
- Public production configuration: **10 passed** across QR sign-in,
  preconfigured origin and session restoration tests, with
  `LOCAL_GENERIC_RELEASE=true`, `LOCAL_PUBLIC_RELEASE=true` and
  `LOCAL_API_BASE_URL=https://api.nutrition.achantalabs.com`.
- Telugu-specific suite: **16 passed**, including preference fallback/restart,
  sign-out persistence, preference races, mid-form language changes, immediate
  validation translation, raw names/notes, canonical missing reasons and schema,
  calculated waist-to-hip ratio, offline pending records and resumed sync.
- 360x800 portrait checks at text scales 1.4 and 1.5: measurement dropdowns,
  review, toggle and cancelled/denied/invalid/unavailable-camera QR messages.
  No RenderFlex exceptions after the responsive toggle fix. Review content is
  scrollable and long labels/options wrap. Numeric keyboard types are asserted.
- Rendered screenshots inspected with the bundled Telugu font and real Latin
  and icon preview fonts: measurements, review and narrow permission-denied
  sign-in guidance. Previews are tooling artifacts in `build/telugu-preview`.
- Signed production APK and AAB built successfully. APK verified with
  `tool/verify_android_release.ps1`: package ID `org.nutritionstudy.project2`,
  version `1.0.2`, version code `10`, expected release certificate and no explicit
  cleartext allowance. The production API origin and bundled Telugu font were
  confirmed inside the APK.
- Existing private Drive signing backup was downloaded as binary and compared
  by SHA256 against the current keystore and password properties: both match.
  Signing files remain ignored and are excluded from the release/source kit.

The generic-only tests intentionally expect a blank compiled server and manual
test sign-in; running those tests with public-production defines produces
configuration-mismatch failures. They were rerun with their intended flags and
passed. Public production tests above passed separately with the release flags.

## Package

Share `dist/vivayu-9/Vivayu.apk` with collectors. Do not share the AAB as an APK.
The AAB and source archive are included in the private Drive release kit.

- APK SHA256: `25308b7319bca68157af9e113267bf4facae706a142d987717602dfdc89305fa`
- AAB SHA256: `96b9ea9c29d59ab232939cb31e87700d1a245acc9d2c096a451fb02f50a96749`
- Certificate SHA256: `36b7e26028c228305181b060a64e9e3d5e72747236214b7ec553d007a58cefb9`

Install over the official +8.1 Vivayu APK without uninstalling or clearing data.
Same package/certificate and a higher build number enable in-place updates; an
actual phone update preserving encrypted data was **not** tested in this run.
No phone was connected and no collector data or server records were touched.

## Remaining human checks

Automated checks are not native-speaker or physical-device approval. Before
wide field rollout, review the bilingual wording checklist with a Telugu-speaking
study coordinator and check the update on one phone: saved visits/answers,
language after restart/logout, offline collection, real camera permission
handling/scanning and sync. Do not clear app data to perform these checks.

The build emitted existing Firebase-plugin Kotlin Gradle migration warnings.
They did not fail this release; plan dependency migration before upgrading to
a future Flutter toolchain that makes those warnings fatal.
