// integration_test/ussd_launcher_test.dart
//
// On-device USSD integration test.
// Run from the package root against a connected Android device:
//
//   flutter test integration_test/ussd_launcher_test.dart \
//     -d <device-id>
//
// Prerequisites (must be done once):
//   1. Declare USSDServiceKK + CALL_PHONE in your host app's AndroidManifest.xml
//      (see README → PNV Prerequisites → Accessibility Service)
//   2. Enable the app under Settings → Accessibility → Installed apps
//   3. Grant CALL_PHONE permission when prompted on first run
//
// Change [_ussdCode] and [_baseCode] / [_menuOptions] below to match your
// carrier before running.

import 'dart:developer' show log;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ussd_launcher/ussd_launcher.dart';

// ── Configuration — edit before running ─────────────────────────────────────

/// The full USSD code to dial in Approach 1 (e.g. '*113*1*1#').
const _ussdCode = '*113*1*1#';

/// Base code for Approach 2 — the menu-driven flow.
const _baseCode = '*113#';

/// Menu selections for Approach 2.
/// e.g. ['1', '1'] means: select 1 on first dialog, then 1 on second dialog.
const _menuOptions = ['1', '1'];

/// SIM slot index. 0 = SIM 1, 1 = SIM 2. -1 = default SIM.
const _simSlot = -1;

// ── Helpers ──────────────────────────────────────────────────────────────────

/// Returns [code] with '#' replaced by '%23'.
String _encodeHash(String code) => code.replaceAll('#', '%23');

// ── Tests ────────────────────────────────────────────────────────────────────

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // --------------------------------------------------------------------------
  // Approach 1-A — sendUssdRequest with the code exactly as-is
  // --------------------------------------------------------------------------
  group('Approach 1-A — raw code ($_ussdCode)', () {
    testWidgets('sendUssdRequest returns a non-null response', (tester) async {
      String? response;
      Object? error;

      try {
        response = await UssdLauncher.sendUssdRequest(
          ussdCode: _ussdCode,
          subscriptionId: _simSlot,
        );
      } on PlatformException catch (e) {
        error = e;
      } on MissingPluginException catch (e) {
        error = e;
      }

      // Print so you can read the carrier response in the test output.
      log('1-A response : $response');
      log('1-A error    : $error');

      if (error != null) {
        // Fail with a descriptive message so you know which approach to try.
        fail(
          'Approach 1-A failed.\n'
          'Error: $error\n'
          'Try Approach 1-B (# encoded) or Approach 2 (multi-session).',
        );
      }

      expect(response, isNotNull);
      expect(response, isNotEmpty);
    });
  });

  // --------------------------------------------------------------------------
  // Approach 1-B — sendUssdRequest with '#' pre-encoded as '%23'
  // --------------------------------------------------------------------------
  group('Approach 1-B — encoded code (${_encodeHash(_ussdCode)})', () {
    testWidgets('sendUssdRequest with encoded hash returns a response',
        (tester) async {
      final encodedCode = _encodeHash(_ussdCode);
      String? response;
      Object? error;

      try {
        response = await UssdLauncher.sendUssdRequest(
          ussdCode: encodedCode,
          subscriptionId: _simSlot,
        );
      } on PlatformException catch (e) {
        error = e;
      } on MissingPluginException catch (e) {
        error = e;
      }

      log('1-B encoded  : $encodedCode');
      log('1-B response : $response');
      log('1-B error    : $error');

      if (error != null) {
        fail(
          'Approach 1-B also failed.\n'
          'Error: $error\n'
          'Try Approach 2 (multi-session) — your carrier may require menu navigation.',
        );
      }

      expect(response, isNotNull);
      expect(response, isNotEmpty);
    });
  });

  // --------------------------------------------------------------------------
  // Approach 2 — multisessionUssd (menu-driven)
  // --------------------------------------------------------------------------
  group('Approach 2 — multisessionUssd ($_baseCode + $_menuOptions)', () {
    testWidgets('navigates USSD menu and completes without throwing',
        (tester) async {
      Object? error;

      try {
        await UssdLauncher.multisessionUssd(
          code: _baseCode,
          options: List<String>.from(_menuOptions),
          slotIndex: _simSlot == -1 ? 0 : _simSlot,
          initialDelayMs: 2000, // wait 2 s for first USSD dialog
          optionDelayMs: 1500,  // wait 1.5 s between menu selections
        );
        log('Approach 2 — multi-session dispatched successfully.');
        log('Check the USSD dialog on device for the carrier response.');
      } on PlatformException catch (e) {
        error = e;
      } on MissingPluginException catch (e) {
        error = e;
      }

      log('2 error: $error');

      if (error != null) {
        fail(
          'Approach 2 failed.\n'
          'Error: $error\n'
          'Possible causes:\n'
          '  - Accessibility Service not enabled for this app\n'
          '  - CALL_PHONE permission not granted\n'
          '  - Carrier does not support this USSD code\n'
          '  - Wrong menu option indices in _menuOptions',
        );
      }

      // multisessionUssd is fire-and-forget — just assert no exception.
      expect(error, isNull);
    });
  });
}
