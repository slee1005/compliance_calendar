import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../core/security/app_lock_controller.dart';
import '../../core/security/lock_credentials.dart';
import '../../core/security/privacy_guard.dart';

/// User-facing messages contain no exception details, secrets, or paths.
String lockFailureText(LockFailure? failure) => switch (failure) {
  LockFailure.weakPassword => '앱 비밀번호는 12~128자로 입력해 주세요.',
  LockFailure.denied => '인증되지 않았습니다. 다시 확인해 주세요.',
  LockFailure.cancelled => '인증이 취소되었습니다.',
  LockFailure.unavailable => '이 기기의 인증을 사용할 수 없습니다.',
  LockFailure.rateLimited => '인증을 여러 번 시도했습니다. 잠시 후 다시 시도해 주세요.',
  LockFailure.configurationChanged => '잠금 설정이 변경되었습니다. 다시 확인해 주세요.',
  LockFailure.authorizationRequired => '설정한 기기 인증 또는 앱 비밀번호가 필요합니다.',
  LockFailure.corruptConfiguration ||
  LockFailure.storageUnavailable => '잠금 설정을 확인할 수 없습니다. 보호를 유지하고 있습니다.',
  null => '',
};

/// Root gate sits outside Navigator so dialogs and keyboard focus cannot bypass it.
final class AppLockBoundary extends StatefulWidget {
  /// Ownership of controller remains with the caller.
  const AppLockBoundary({
    super.key,
    required this.controller,
    required this.child,
  });

  /// Session authority.
  final AppLockController controller;

  /// Application navigator, inaccessible while hidden or locked.
  final Widget child;
  @override
  State<AppLockBoundary> createState() => _AppLockBoundaryState();
}

class _AppLockBoundaryState extends State<AppLockBoundary>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(widget.controller.initialize());
    final state = WidgetsBinding.instance.lifecycleState;
    if (state != null) didChangeAppLifecycleState(state);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      FocusManager.instance.primaryFocus?.unfocus();
    }
    widget.controller.visibility(switch (state) {
      AppLifecycleState.resumed => PrivacySignal.foreground,
      AppLifecycleState.inactive => PrivacySignal.inactive,
      _ => PrivacySignal.background,
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final lock = widget.controller;
      if (lock.visible) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(lock.revealFrame());
        });
      }
      final hasSession =
          lock.phase == LockPhase.unlocked || lock.phase == LockPhase.preview;
      return Stack(
        fit: StackFit.expand,
        children: [
          if (hasSession)
            ExcludeSemantics(
              excluding: !lock.canShowContent,
              child: IgnorePointer(
                ignoring: !lock.canShowContent,
                child: TickerMode(
                  enabled: lock.canShowContent,
                  child: Offstage(
                    offstage: !lock.canShowContent,
                    child: widget.child,
                  ),
                ),
              ),
            ),
          if (!lock.canShowContent)
            Positioned.fill(
              child: !lock.visible
                  ? const _PrivacyScreen()
                  : Navigator(
                      key: const ValueKey('security-navigator'),
                      onGenerateRoute: (_) => PageRouteBuilder<void>(
                        transitionDuration: Duration.zero,
                        reverseTransitionDuration: Duration.zero,
                        pageBuilder: (context, _, _) => ListenableBuilder(
                          listenable: lock,
                          builder: (context, _) => LockScreen(controller: lock),
                        ),
                      ),
                    ),
            ),
        ],
      );
    },
  );
}

class _PrivacyScreen extends StatelessWidget {
  const _PrivacyScreen();
  @override
  Widget build(BuildContext context) => Material(
    color: Color(0xFFF5F8F6),
    child: Center(
      child: Semantics(
        label: '화면 보호 중',
        child: Icon(Icons.shield_outlined, size: 48, color: Color(0xFF16776B)),
      ),
    ),
  );
}

/// Locked/loading/failure screen with actual native or password authentication.
final class LockScreen extends StatefulWidget {
  /// Uses only an injected session interface, never platform APIs.
  const LockScreen({super.key, required this.controller});

  /// Session authority.
  final AppLockController controller;
  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  final _password = TextEditingController();
  Future<void> _unlock() async {
    final value = _password.text;
    FocusScope.of(context).unfocus();
    _password.clear();
    await widget.controller.unlockPassword(value);
  }

  @override
  void dispose() {
    _password.clear();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lock = widget.controller;
    final loading = lock.phase == LockPhase.loading;
    final blocked = lock.phase == LockPhase.blocked;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(
                    Icons.lock_outline,
                    size: 52,
                    color: Color(0xFF16776B),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    loading
                        ? '보호 설정 확인 중'
                        : blocked
                        ? '보호를 유지하고 있습니다'
                        : '앱이 잠겨 있습니다',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 12),
                  const Text('자격·컴플라이언스', textAlign: TextAlign.center),
                  const SizedBox(height: 24),
                  if (loading || lock.busy)
                    const Center(child: CircularProgressIndicator()),
                  if (!loading && lock.failure != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Text(
                        lockFailureText(lock.failure),
                        key: const Key('lock-error'),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  if (blocked)
                    FilledButton(
                      onPressed: lock.busy ? null : lock.retry,
                      child: const Text('다시 확인'),
                    ),
                  if (!loading && !blocked && lock.policy.device) ...[
                    FilledButton.icon(
                      key: const Key('unlock-device'),
                      onPressed: lock.busy ? null : lock.unlockDevice,
                      icon: const Icon(Icons.fingerprint),
                      label: const Text('기기 인증으로 열기'),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      '생체인증이 어려우면 기기 암호를 사용할 수 있습니다.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                  ],
                  if (!loading && !blocked && lock.policy.password) ...[
                    TextField(
                      key: const Key('unlock-password'),
                      controller: _password,
                      enabled: !lock.busy,
                      obscureText: true,
                      enableSuggestions: false,
                      autocorrect: false,
                      enableIMEPersonalizedLearning: false,
                      autofillHints: const [],
                      decoration: const InputDecoration(labelText: '앱 비밀번호'),
                      onSubmitted: lock.busy ? null : (_) => _unlock(),
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton(
                      key: const Key('unlock-password-submit'),
                      onPressed: lock.busy ? null : _unlock,
                      child: const Text('앱 비밀번호로 열기'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Settings control with explicit enrollment and reauthentication for disabling.
final class LockSettings extends StatelessWidget {
  /// Null means this preview has no security service and offers no fake controls.
  const LockSettings({super.key, required this.controller});

  /// Injected lock service; optional only for UI-only preview/test composition.
  final AppLockController? controller;
  @override
  Widget build(BuildContext context) {
    final lock = controller;
    if (lock == null) return const Text('앱 잠금 · 이 미리보기에는 연결되지 않았습니다.');
    return ListenableBuilder(
      listenable: lock,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            lock.policy.enabled ? '앱 잠금 · 사용 중' : '앱 잠금 · 꺼짐',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          const Text('다른 화면으로 이동하면 내용이 가려지고, 5분이 지나면 다시 인증합니다.'),
          const SizedBox(height: 12),
          if (lock.failure != null) Text(lockFailureText(lock.failure)),
          if (!lock.policy.enabled) ...[
            if (lock.capabilities.deviceCredential)
              OutlinedButton(
                key: const Key('enable-device-lock'),
                onPressed: lock.busy ? null : lock.enableDevice,
                child: const Text('기기 인증으로 잠금 설정'),
              )
            else
              const Text('이 기기의 인증을 사용할 수 없습니다. 앱 비밀번호를 설정할 수 있습니다.'),
            const SizedBox(height: 10),
            FilledButton(
              key: const Key('setup-password-lock'),
              onPressed: lock.busy
                  ? null
                  : () => showDialog<void>(
                      context: context,
                      builder: (_) =>
                          _PasswordDialog(lock: lock, enrolling: true),
                    ),
              child: const Text('앱 비밀번호 설정'),
            ),
          ] else ...[
            FilledButton(
              key: const Key('lock-now'),
              onPressed: lock.busy ? null : lock.lock,
              child: const Text('지금 잠그기'),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              key: const Key('disable-lock'),
              onPressed: lock.busy
                  ? null
                  : () => showDialog<void>(
                      context: context,
                      builder: (_) =>
                          _PasswordDialog(lock: lock, enrolling: false),
                    ),
              child: const Text('잠금 끄기 · 다시 인증'),
            ),
          ],
          if (lock.protection?.captureProtection == false) ...[
            const SizedBox(height: 12),
            const Text('이 기기에서는 스크린샷 촬영을 막지 못합니다.'),
          ],
        ],
      ),
    );
  }
}

class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog({required this.lock, required this.enrolling});
  final AppLockController lock;
  final bool enrolling;
  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog>
    with WidgetsBindingObserver {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _allowDevice = false;
  bool _busy = false;
  String? _message;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.lock.addListener(_visibilityChanged);
  }

  void _visibilityChanged() {
    if (!widget.lock.visible) {
      _password.clear();
      _confirm.clear();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _password.clear();
      _confirm.clear();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.lock.removeListener(_visibilityChanged);
    _password.clear();
    _confirm.clear();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit({bool device = false}) async {
    if (_busy) return;
    if (widget.enrolling && _password.text != _confirm.text) {
      setState(() => _message = '두 비밀번호가 일치하지 않습니다.');
      return;
    }
    final password = _password.text;
    _password.clear();
    _confirm.clear();
    setState(() => _busy = true);
    final ok = widget.enrolling
        ? await widget.lock.enablePassword(password, allowDevice: _allowDevice)
        : device
        ? await widget.lock.disableDevice()
        : await widget.lock.disablePassword(password);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
    } else {
      setState(() {
        _busy = false;
        _message = lockFailureText(widget.lock.failure);
      });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.enrolling ? '앱 비밀번호 설정' : '잠금 끄기'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.enrolling
                ? '12~128자로 설정해 주세요. 앱 비밀번호는 기기 암호와 별개입니다.'
                : '현재 인증으로 확인한 뒤 잠금을 끕니다.',
          ),
          if (widget.enrolling || widget.lock.policy.password) ...[
            const SizedBox(height: 16),
            TextField(
              key: const Key('security-password'),
              controller: _password,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              enableIMEPersonalizedLearning: false,
              decoration: const InputDecoration(labelText: '앱 비밀번호'),
            ),
          ],
          if (widget.enrolling) ...[
            const SizedBox(height: 12),
            TextField(
              key: const Key('security-password-confirm'),
              controller: _confirm,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              enableIMEPersonalizedLearning: false,
              decoration: const InputDecoration(labelText: '앱 비밀번호 확인'),
            ),
            if (widget.lock.capabilities.deviceCredential)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('기기 인증도 허용'),
                value: _allowDevice,
                onChanged: _busy
                    ? null
                    : (value) => setState(() => _allowDevice = value ?? false),
              ),
          ],
          if (!widget.enrolling && widget.lock.policy.device) ...[
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: _busy ? null : () => _submit(device: true),
              child: const Text('기기 인증으로 확인'),
            ),
          ],
          if (_message != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_message!),
            ),
          if (_busy)
            const Padding(
              padding: EdgeInsets.only(top: 16),
              child: LinearProgressIndicator(),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.of(context).pop(),
        child: const Text('취소'),
      ),
      if (widget.enrolling || widget.lock.policy.password)
        FilledButton(
          key: const Key('security-password-submit'),
          onPressed: _busy ? null : () => _submit(),
          child: Text(widget.enrolling ? '설정' : '앱 비밀번호로 확인'),
        ),
    ],
  );
}
