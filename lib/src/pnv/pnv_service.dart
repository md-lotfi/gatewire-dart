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
  }) async {
    if (!Platform.isAndroid) {
      throw GateWireException('USSD dialing is only supported on Android.');
    }

    final session = await initiate(phoneNumber: phoneNumber);
    onSessionCreated?.call(session);

    String ussdResponse;
    try {
      ussdResponse = await UssdLauncher.sendUssdRequest(
            ussdCode: session.ussdCode,
            subscriptionId: -1, // -1 selects the default SIM
          ) ??
          '';
    } on PlatformException catch (e) {
      throw GateWireException('USSD dialing failed: ${e.message}');
    } on UnsupportedError catch (e) {
      throw GateWireException('USSD not supported on this device: $e');
    }

    return verify(
      referenceId: session.referenceId,
      ussdResponse: ussdResponse,
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
