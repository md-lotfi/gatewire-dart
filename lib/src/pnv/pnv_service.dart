import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:ussd_launcher/ussd_launcher.dart';

import '../exceptions.dart';
import 'models/pnv_result.dart';
import 'models/pnv_session.dart';

/// Service for Phone Number Verification (PNV) via carrier USSD.
///
/// Obtain an instance through [GateWireClient.pnv] rather than constructing
/// this class directly.
///
/// ## Typical flow
/// ```dart
/// // One-call helper (Android only):
/// final result = await gatewire.pnv.dialAndVerify(phoneNumber: '+213770123456');
///
/// // Or step by step:
/// final session = await gatewire.pnv.initiate(phoneNumber: '+213770123456');
/// // … dial session.ussdCode yourself …
/// final result = await gatewire.pnv.verify(
///   referenceId: session.referenceId,
///   ussdResponse: rawUssdString,
/// );
/// ```
class PnvService {
  final http.Client _httpClient;
  final String _apiKey;
  final String _baseUrl;

  // ignore: public_member_api_docs — internal constructor, exposed via GateWireClient.pnv
  const PnvService(this._httpClient, this._apiKey, this._baseUrl);

  // -------------------------------------------------------------------------
  // Public API
  // -------------------------------------------------------------------------

  /// Step 1 — tells the backend to begin a PNV session for [phoneNumber].
  ///
  /// Returns a [PnvSession] containing the USSD code to dial and session
  /// metadata. Pass [PnvSession.referenceId] and the carrier's raw response
  /// string to [verify] once the USSD dialog completes.
  ///
  /// Throws [GateWireException] on API errors:
  /// - 402 Insufficient balance
  /// - 404 No USSD configuration for the detected operator
  /// - 422 Validation error (e.g. invalid phone number format)
  /// - 429 Rate limited
  Future<PnvSession> initiate({required String phoneNumber}) async {
    try {
      final data =
          await _request('/pnv/initiate', {'phone_number': phoneNumber});
      return PnvSession.fromJson(data);
    } on GateWireException catch (e) {
      if (e.statusCode == 403) {
        throw GateWireException(
          'Phone Number Verification is not enabled for your account. '
          'Enable it from your dashboard.',
          403,
          'service_disabled',
        );
      }
      rethrow;
    }
  }

  /// Step 2 — submits the raw USSD [ussdResponse] string captured from the
  /// carrier dialog for the session identified by [referenceId].
  ///
  /// Returns a [PnvResult] where [PnvResult.verified] is `true` when the
  /// backend regex-parsed phone number matches the one on the session.
  ///
  /// Throws [GateWireException] on API errors:
  /// - 400 Session expired, already used, or phone number mismatch
  /// - 404 Session not found
  /// - 429 Rate limited
  Future<PnvResult> verify({
    required String referenceId,
    required String ussdResponse,
  }) async {
    final data = await _request('/pnv/verify', {
      'reference_id': referenceId,
      'ussd_response': ussdResponse,
    });
    return PnvResult.fromJson(data);
  }

  /// Full flow helper — initiates a PNV session, dials the USSD code on the
  /// device, waits for the carrier response, then verifies — all in one call.
  ///
  /// [onSessionCreated] is invoked after the session is created and before the
  /// USSD dialog is shown, giving the caller an opportunity to display a
  /// "Dialing…" indicator that includes [PnvSession.ussdCode].
  ///
  /// **Android only.** USSD is a carrier-level feature unavailable on iOS,
  /// web, or desktop. Calling this method on a non-Android platform throws
  /// [GateWireException] immediately, before any network call is made.
  ///
  /// Throws [GateWireException] if:
  /// - the platform is not Android
  /// - the USSD dialer is blocked or unavailable ([PlatformException])
  /// - USSD is not supported on the device ([UnsupportedError])
  /// - any underlying API call fails
  Future<PnvResult> dialAndVerify({
    required String phoneNumber,
    void Function(PnvSession session)? onSessionCreated,
    int simSlotIndex = 0,
  }) async {
    if (!Platform.isAndroid) {
      throw GateWireException('USSD dialing is only supported on Android.');
    }

    final session = await initiate(phoneNumber: phoneNumber);
    onSessionCreated?.call(session);

    // ── Approach 1: sendUssdRequest ──────────────────────────────────────
    // Fast, no UI. Blocked by many carriers — silently falls through on error.
    try {
      final response = await UssdLauncher.sendUssdRequest(
        ussdCode: session.ussdCode,
        subscriptionId: -1,
      );
      if (response != null && response.isNotEmpty) {
        return verify(referenceId: session.referenceId, ussdResponse: response);
      }
    } on PlatformException {
      // Carrier blocked sendUssdRequest — try Approach 2.
    } on UnsupportedError {
      // API level too low — try Approach 2.
    }

    // ── Approach 2: multisessionUssd ─────────────────────────────────────
    // Opens phone dialer, Accessibility Service reads dialogs and pushes
    // responses via setUssdMessageListener.
    //
    // Early-exit optimisation: some operators (e.g. Ooredoo) include the full
    // phone number in the very first USSD response, before the menu navigation
    // completes. When any carrier message matches the phone-number pattern we
    // complete [sessionDone] immediately and cancel the native session, skipping
    // any remaining menu options.
    final parsed = _parseUssdCode(session.ussdCode);
    String lastResponse = '';
    final sessionDone = Completer<void>();
    bool earlyExit = false;

    UssdLauncher.setUssdMessageListener((msg) {
      if (_isSentinel(msg)) {
        if (msg == 'SESSION_COMPLETED' && !sessionDone.isCompleted) {
          sessionDone.complete();
        } else if (!sessionDone.isCompleted) {
          sessionDone.completeError(msg);
        }
      } else {
        lastResponse = msg;
        // Early exit: phone number visible now — no need to send further options.
        if (!sessionDone.isCompleted &&
            _containsPhoneNumber(msg, session.phonePattern)) {
          earlyExit = true;
          sessionDone.complete();
        }
      }
    });

    try {
      final dialFuture = UssdLauncher.multisessionUssd(
        code: parsed.base,
        options: parsed.options,
        slotIndex: simSlotIndex,
        initialDelayMs: 2000,
        optionDelayMs: 1500,
      );

      // Race: all options sent normally OR phone number detected early.
      await Future.any([dialFuture, sessionDone.future]);

      if (earlyExit) {
        // Stop the native session so no further menu options are auto-filled.
        await UssdLauncher.cancelSession();
      } else if (!sessionDone.isCompleted) {
        // Normal path: wait for SESSION_COMPLETED sentinel.
        await sessionDone.future.timeout(const Duration(seconds: 8),
            onTimeout: () {});
      }
    } on PlatformException catch (e) {
      throw GateWireException('USSD dialing failed: ${e.message}');
    } finally {
      UssdLauncher.removeUssdMessageListener();
    }

    if (lastResponse.isEmpty) {
      throw GateWireException('No USSD response received from carrier.');
    }

    return verify(referenceId: session.referenceId, ussdResponse: lastResponse);
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// Parses a full USSD code like `*113*1*1#` into a base code and menu
  /// options suitable for [UssdLauncher.multisessionUssd].
  ///
  /// Examples:
  /// - `*113*1*1#` → base: `*113#`, options: `['1', '1']`
  /// - `*555#`     → base: `*555#`, options: `[]`
  static const _sentinels = {
    'SESSION_COMPLETED',
    'ACCESSIBILITY_NOT_ENABLED',
    'ACCESSIBILITY_OR_OVERLAY_NOT_ENABLED',
    'BAD_MAPPING_STRUCTURE',
    'EMPTY_USSD_CODE',
  };

  /// Fallback phone-number regex used when the server does not provide one.
  /// Matches 9–15 digit strings optionally prefixed with `+`.
  static const _defaultPhonePattern = r'\+?[0-9]{9,15}';

  bool _isSentinel(String msg) =>
      _sentinels.contains(msg) ||
      msg.startsWith('SESSION_END_ERROR:') ||
      msg.startsWith('SEND_OPTION_ERROR:') ||
      msg.startsWith('DIAL_ERROR:');

  bool _containsPhoneNumber(String msg, String? pattern) =>
      RegExp(pattern ?? _defaultPhonePattern).hasMatch(msg);

  ({String base, List<String> options}) _parseUssdCode(String code) {
    final inner = code.replaceFirst('*', '').replaceAll('#', '');
    final parts = inner.split('*');
    return (
      base: '*${parts.first}#',
      options: parts.length > 1 ? parts.sublist(1) : <String>[],
    );
  }

  // -------------------------------------------------------------------------
  // Internal HTTP helper — mirrors GateWireClient._request exactly.
  // -------------------------------------------------------------------------

  Future<Map<String, dynamic>> _request(
    String endpoint, [
    Map<String, dynamic>? body,
  ]) async {
    final uri = Uri.parse('$_baseUrl$endpoint');
    final headers = {
      'Authorization': 'Bearer $_apiKey',
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'User-Agent': 'GateWire-Flutter/1.0',
    };

    http.Response response;
    try {
      response = await _httpClient.post(
        uri,
        headers: headers,
        body: jsonEncode(body),
      );
    } catch (e) {
      throw GateWireException('Network error: $e');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return data;
    }
    throw GateWireException(
      data['message'] as String? ??
          data['error'] as String? ??
          'Unknown API Error',
      response.statusCode,
    );
  }
}
