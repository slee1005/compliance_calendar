import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../core/ocr/document_input.dart';
import '../../core/ocr/input_controller.dart';
import '../../core/security/app_lock_controller.dart';
import '../../shared/widgets/section_card.dart';

/// T6 development input only. No OCR result or production record is created.
class ScanScreen extends StatefulWidget {
  /// Creates the guarded input trial without starting hardware automatically.
  const ScanScreen({super.key, this.input, this.lock, this.cameraPreview});

  /// Explicit input service, absent in UI-only previews.
  final InputController? input;

  /// Session used to gate consent, reads and foreground delivery.
  final AppLockController? lock;

  /// Injected camera surface, without a feature-level platform dependency.
  final WidgetBuilder? cameraPreview;
  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> with WidgetsBindingObserver {
  bool _enabled = false;
  bool _picking = false;
  bool _wasVisible = true;
  String? _message;
  StreamSubscription<DocumentFile>? _drops;
  bool _desktopEnabled = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.lock?.addListener(_sessionChanged);
    _drops = widget.input?.desktop?.drops.listen(
      (file) => unawaited(_receive(file)),
    );
    _wasVisible = widget.lock?.visible ?? true;
  }

  bool get _unlocked =>
      widget.lock?.phase == LockPhase.unlocked && widget.lock!.policy.enabled;
  void _sessionChanged() {
    final visible = widget.lock?.visible ?? false;
    if ((_wasVisible && !visible) || !_unlocked) {
      unawaited(widget.input?.suspend() ?? Future.value());
    }
    _wasVisible = visible;
    _syncDesktop();
    if (mounted) setState(() {});
  }

  void _syncDesktop() {
    // An unread file capability may arrive while Finder/picker owns focus.
    // Reading still requires foreground authorization on both sides.
    final desired = _enabled && _unlocked;
    if (_desktopEnabled == desired) return;
    _desktopEnabled = desired;
    unawaited(_configureDesktop(desired));
  }

  Future<void> _configureDesktop(bool enabled) async {
    try {
      await widget.input?.desktop?.setEnabled(enabled);
    } catch (_) {
      if (mounted) setState(() => _message = '파일 입력을 사용할 수 없습니다.');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      unawaited(widget.input?.suspend() ?? Future.value());
    }
  }

  Future<bool> _foreground({int? generation}) async {
    for (var i = 0; i < 40; i++) {
      if (!mounted || !_enabled || !_unlocked) return false;
      if (widget.lock!.authorized) {
        try {
          widget.lock!.requireAuthorization(generation: generation);
          return true;
        } catch (_) {
          return false;
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    return false;
  }

  Future<void> _receive(DocumentFile file, {int? generation}) async {
    var transferred = false;
    try {
      if (!await _foreground(generation: generation)) {
        if (mounted) setState(() => _message = '앱 잠금을 해제한 뒤 다시 입력해 주세요.');
        return;
      }
      transferred = true;
      await widget.input!.readFile(file);
    } catch (_) {
      if (mounted) setState(() => _message = '파일 입력을 완료하지 못했습니다.');
    } finally {
      if (!transferred) {
        try {
          await file.release();
        } catch (_) {
          /* no source details */
        }
      }
    }
  }

  Future<void> _pick() async {
    if (_picking || !_enabled || widget.lock?.authorized != true) return;
    final generation = widget.lock!.requireAuthorization();
    setState(() => _picking = true);
    try {
      final file = await widget.input!.desktop!.pick();
      if (file != null) await _receive(file, generation: generation);
    } catch (_) {
      if (mounted) setState(() => _message = '파일 선택을 사용할 수 없습니다.');
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.lock?.removeListener(_sessionChanged);
    unawaited(_drops?.cancel() ?? Future.value());
    unawaited(widget.input?.suspend() ?? Future.value());
    unawaited(_configureDesktop(false));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final input = widget.input;
    if (input == null) {
      return const SectionCard(
        title: '서류 입력',
        child: Text('이 미리보기에는 카메라·파일 입력이 연결되지 않았습니다.'),
      );
    }
    return ListenableBuilder(
      listenable: input,
      builder: (context, _) => SectionCard(
        title: '서류를 저장하지 않고 입력',
        subtitle: '원본은 보관하지 않습니다. 파일을 고르면 원본 파일은 그대로 유지합니다.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const DevelopmentNotice(
              message: '입력 시험 단계입니다. 가상·비식별 테스트 문서만 사용하세요. 글자 인식과 정보 저장은 아직 준비 중입니다.',
            ),
            const SizedBox(height: 16),
            if (!_unlocked) const Text('먼저 설정에서 앱 잠금을 설정하고 해제해 주세요.'),
            CheckboxListTile(
              key: const Key('input-test-consent'),
              contentPadding: EdgeInsets.zero,
              value: _enabled,
              onChanged: !_unlocked
                  ? null
                  : (value) {
                      setState(() {
                        _enabled = value ?? false;
                        _message = null;
                      });
                      _syncDesktop();
                      if (!_enabled) unawaited(input.suspend());
                    },
              title: const Text('가상·비식별 문서로 입력 시험 켜기'),
            ),
            if (_enabled && _unlocked) ...[
              if (input.camera != null) ...[
                if ((input.live || input.phase == InputPhase.reading) &&
                    widget.cameraPreview != null)
                  SizedBox(height: 240, child: widget.cameraPreview!(context)),
                const SizedBox(height: 12),
                FilledButton.icon(
                  key: const Key('input-camera-start'),
                  onPressed: input.busy || input.live
                      ? null
                      : input.startCamera,
                  icon: const Icon(Icons.camera_alt_outlined),
                  label: const Text('카메라 시작'),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  key: const Key('input-capture'),
                  onPressed: input.live ? input.capture : null,
                  child: const Text('현재 프레임 입력·즉시 폐기'),
                ),
              ],
              if (input.desktop != null) ...[
                Container(
                  key: const Key('input-drop-area'),
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xFF16776B)),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    '이 창으로 로컬 이미지 또는 PDF 한 개를 끌어 놓으세요.\nPNG · JPEG · HEIC · PDF, 최대 20MB\n링크·폴더·클라우드 파일은 받지 않습니다.',
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  key: const Key('input-pick'),
                  onPressed: input.busy || _picking ? null : _pick,
                  icon: const Icon(Icons.file_open_outlined),
                  label: const Text('파일 선택'),
                ),
              ],
              const SizedBox(height: 12),
              OutlinedButton(
                key: const Key('input-discard'),
                onPressed: () => input.suspend(),
                child: const Text('중단·메모리 폐기'),
              ),
            ],
            if (input.busy || _picking)
              const Padding(
                padding: EdgeInsets.all(16),
                child: LinearProgressIndicator(),
              ),
            if (input.receipt != null)
              const Padding(
                padding: EdgeInsets.only(top: 16),
                child: Text(
                  '입력을 확인하고 메모리 버퍼를 폐기했습니다. 글자 인식은 아직 준비 중입니다.',
                  key: Key('input-receipt'),
                ),
              ),
            if (input.failure != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(_failure(input.failure!)),
              ),
            if (_message != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_message!),
              ),
          ],
        ),
      ),
    );
  }

  String _failure(InputFailure reason) => switch (reason) {
    InputFailure.permissionDenied => '카메라 권한이 없습니다. 기기 설정에서 허용한 뒤 다시 시작해 주세요.',
    InputFailure.tooLarge => '입력이 20MB 제한을 넘었습니다.',
    InputFailure.unsupported ||
    InputFailure.invalidData => '지원하는 이미지 또는 PDF 입력을 확인해 주세요.',
    InputFailure.expired => '입력 시간이 지나 메모리를 폐기했습니다. 다시 입력해 주세요.',
    InputFailure.locked => '앱 잠금을 해제한 뒤 다시 입력해 주세요.',
    InputFailure.cancelled => '입력을 취소하고 메모리를 폐기했습니다.',
    InputFailure.busy => '현재 입력을 마친 뒤 다시 시도해 주세요.',
    InputFailure.unavailable => '이 환경에서는 카메라 또는 입력 장치를 사용할 수 없습니다.',
    InputFailure.io => '입력을 완료하지 못했습니다. 원본 파일은 변경하지 않았습니다.',
  };
}
