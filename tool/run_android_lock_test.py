#!/usr/bin/env python3
"""Native credential test on an explicitly disposable emulator only.

The random emulator PIN exists only in this process and Android's lock settings.
Subprocess command/output containing it is never printed or written to a file.
"""
import argparse
import os
from pathlib import Path
import secrets
import subprocess
import sys
import time
import xml.etree.ElementTree as ET

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--device', required=True)
parser.add_argument('--ephemeral-emulator', action='store_true', required=True)
parser.add_argument('--log', default='/private/tmp/compliance-t5-android-device.log')
args = parser.parse_args()
if not args.device.startswith('emulator-'):
    sys.exit('Only an explicitly disposable emulator is supported.')
adb = Path(os.environ.get('ANDROID_HOME', Path.home() / 'Library/Android/sdk')) / 'platform-tools/adb'

def command(*items):
    return subprocess.run([str(adb), '-s', args.device, *items], capture_output=True, text=True, timeout=30)

if command('shell', 'getprop', 'ro.kernel.qemu').stdout.strip() != '1':
    sys.exit('The selected target is not an emulator.')
pin = str(secrets.randbelow(900000) + 100000)
configured = False
process = None
try:
    result = command('shell', 'locksettings', 'set-pin', pin)
    verified = command('shell', 'locksettings', 'verify', '--old', pin)
    if result.returncode or 'verified successfully' not in verified.stdout.lower():
        raise RuntimeError('Emulator credential configuration was not verified.')
    configured = True
    print('Temporary emulator credential configured; its value is never logged.', flush=True)
    log_path = Path(args.log)
    with log_path.open('w') as output:
        process = subprocess.Popen([
            './tool/flutter', 'drive', '--driver=test_driver/lock_driver.dart',
            '--target=integration_test/lock_smoke_test.dart', '-d', args.device,
            '--dart-define=VERIFY_NATIVE_DEVICE_CREDENTIAL=true',
        ], stdout=output, stderr=subprocess.STDOUT)
        handled = set()
        deadline = time.monotonic() + 600
        while process.poll() is None:
            if time.monotonic() > deadline:
                raise RuntimeError('Native credential test timed out.')
            text = log_path.read_text(errors='replace')
            for marker in ('T5_READY_FOR_NATIVE_ENROLL_AUTH', 'T5_READY_FOR_NATIVE_UNLOCK_AUTH'):
                if marker not in text or marker in handled:
                    continue
                prompt_deadline = time.monotonic() + 45
                while time.monotonic() < prompt_deadline:
                    focused = command('shell', 'dumpsys', 'window').stdout
                    focused = '\n'.join(line for line in focused.splitlines() if 'mCurrentFocus=' in line)
                    credential_prompt = any(name in focused.lower() for name in ('confirmlock', 'confirmdevicecredential'))
                    if 'BiometricPrompt' in focused:
                        # API 36 may render the credential entry directly inside
                        # SystemUI's BiometricPrompt rather than a separate Activity.
                        command('shell', 'uiautomator', 'dump', '/data/local/tmp/t5-window.xml')
                        xml = command('shell', 'cat', '/data/local/tmp/t5-window.xml').stdout
                        command('shell', 'rm', '/data/local/tmp/t5-window.xml')
                        try:
                            credential_prompt = any(
                                node.get('resource-id') == 'com.android.systemui:id/lockPassword'
                                and node.get('password') == 'true'
                                for node in ET.fromstring(xml).iter('node')
                            )
                        except ET.ParseError:
                            credential_prompt = False
                    if credential_prompt:
                        break
                    if process.poll() is not None:
                        raise RuntimeError('Native test stopped before the credential prompt.')
                    time.sleep(.25)
                else:
                    raise RuntimeError('Expected OS-owned credential prompt was not verified.')
                command('shell', 'input', 'text', pin)
                command('shell', 'input', 'keyevent', 'KEYCODE_ENTER')
                handled.add(marker)
                print('Submitted temporary credential to the verified OS prompt.', flush=True)
            time.sleep(.25)
        if process.returncode or len(handled) != 2:
            raise RuntimeError('Native device-credential verification failed.')
    print('Android native device-credential verification passed.', flush=True)
except Exception:
    # Do not include exception repr or command arguments: they may contain PIN.
    print('Android emulator credential test did not complete; inspect the value-free test log.', file=sys.stderr)
    if process is not None and process.poll() is None:
        process.terminate()
        process.wait(timeout=20)
    sys.exit(1)
finally:
    if configured:
        cleared = command('shell', 'locksettings', 'clear', '--old', pin)
        if cleared.returncode:
            print('Temporary credential cleanup requires stopping this disposable emulator.', file=sys.stderr)
    pin = None
