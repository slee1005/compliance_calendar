# Project instructions

<!-- postman-cli:installation:start -->
Postman CLI is installed on this device, and can be used for API Engineering work.
<!-- postman-cli:installation:end -->

- Read `docs/implementation-status.md` before choosing the next task. The canonical product specification is `docs/small-biz-compliance-planner.md` v1.2; preserve the supplied Markdown and PDF.
- Keep the Flutter application shared in `lib/`. Put native configuration and bridges in `android/`, `ios/`, `macos/`, and `windows/`; do not fork the application into four duplicated codebases.
- Use Flutter 3.50.1 / Dart 3.14.0 and retain `pubspec.lock`. Prefer `./tool/flutter` on this machine. The local `.tools/` SDK is ignored and must never be committed.
- Follow the milestone order and completion criteria in chapter 7. On 2026-11-21 the user explicitly authorized deferring Windows verification and continuing from T2. T1 remains open for Windows build, execution, and screenshot evidence; the other three platforms have verified evidence. This deferral does not waive Windows verification before release or permit claiming an unverified build passed.
- The current app is a preview shell. `DemoCredential` is fictional, memory-only UI data, not the production License schema. Examples must be opt-in, removable, and visibly labeled.
- Do not accept or persist real staff data before the required encryption, SQLCipher, and OS key storage are implemented and verified. Do not substitute plaintext files or ordinary SQLite.
- Never persist document images, PDFs, thumbnails, OCR text, tokens, or keys in source, logs, fixtures, analytics, or a new backend. Document inputs must be ephemeral and OCR must stay on-device. Development UI screenshots and the supplied planning PDF are not customer document storage.
- Keep cryptography, Calendar, storage, OCR, notifications, and billing separated. Follow the dependency rules in `docs/architecture.md`. Use interfaces rather than `Platform.isX` in feature code.
- Google Calendar private properties are not encryption. Consult the concrete API corrections in the status document before implementing synchronization.
- Run `bash tool/verify.sh` for Dart changes. Check both 375×667 and 1440×900 layouts, including 200% text size. Add or update meaningful tests for changed behavior; use `integration_test/app_smoke_test.dart` for native runner checks.
- Leave unavailable services visibly unavailable. Do not simulate successful synchronization, security activation, exports, notifications, or purchases.
- Do not publish, provision OAuth accounts, spend money, or create release signing credentials as part of a local build.
