import 'dart:convert';
import 'dart:io' show Platform;
import 'package:http/http.dart' as http;
import 'exceptions.dart';
import 'models.dart';
import 'phone_verification_result.dart';
import 'pnv/models/pnv_session.dart';
import 'pnv/pnv_service.dart';

class GateWireClient {
  final String apiKey;
  final String baseUrl;
  final http.Client _httpClient;

  GateWireClient({
    required this.apiKey,
    this.baseUrl = 'https://gatewire.net/api/v1',
    http.Client? client,
  }) : _httpClient = client ?? http.Client();

  /// Phone Number Verification service backed by the same HTTP client.
  ///
  /// Use [PnvService.dialAndVerify] for the full one-call flow, or call
  /// [PnvService.initiate] and [PnvService.verify] separately.
  late final PnvService pnv = PnvService(_httpClient, apiKey, baseUrl);

  /// Send an SMS or OTP
  Future<GateWireResponse> dispatch({
    required String phone,
    String? templateKey,
  }) async {
    final body = {
      'phone': phone,
      if (templateKey != null) 'template_key': templateKey,
    };

    final response = await _request('POST', '/send-otp', body);
    return GateWireResponse.fromJson(response);
  }

  /// Verify an OTP code
  Future<OtpVerificationResponse> verifyOtp({
    required String referenceId,
    required String code,
  }) async {
    final body = {'reference_id': referenceId, 'code': code};

    final response = await _request('POST', '/verify-otp', body);
    return OtpVerificationResponse.fromJson(response);
  }

  /// Platform-aware phone verification.
  ///
  /// On **Android**, performs full PNV (USSD dial + verify) via
  /// [PnvService.dialAndVerify]. Returns a [PhoneVerificationResult] with
  /// [PhoneVerificationResult.verified] set immediately.
  ///
  /// On **iOS, web, and desktop**, falls back to OTP: dispatches an SMS via
  /// [dispatch] and returns a [PhoneVerificationResult] with
  /// [PhoneVerificationResult.method] set to [VerificationMethod.otp] and
  /// [PhoneVerificationResult.verified] as `null`. The caller must prompt the
  /// user for the SMS code and call [verifyOtp] with the returned
  /// [PhoneVerificationResult.referenceId].
  ///
  /// [onSessionCreated] is forwarded to [PnvService.dialAndVerify] on Android
  /// and is never invoked on other platforms.
  ///
  /// Throws [GateWireException] on any API or USSD error.
  Future<PhoneVerificationResult> verifyPhone({
    required String phoneNumber,
    String? templateKey,
    void Function(PnvSession session)? onSessionCreated,
  }) async {
    if (Platform.isAndroid) {
      final result = await pnv.dialAndVerify(
        phoneNumber: phoneNumber,
        onSessionCreated: onSessionCreated,
      );
      return PhoneVerificationResult(
        method: VerificationMethod.pnv,
        verified: result.verified,
        message: result.message,
      );
    }

    // Non-Android fallback: dispatch OTP via SMS.
    final response = await dispatch(phone: phoneNumber, templateKey: templateKey);
    return PhoneVerificationResult(
      method: VerificationMethod.otp,
      verified: null,
      referenceId: response.referenceId,
      message: 'OTP sent via SMS. Enter the code to complete verification.',
    );
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String endpoint, [
    Map<String, dynamic>? body,
  ]) async {
    final uri = Uri.parse('$baseUrl$endpoint');
    final headers = {
      'Authorization': 'Bearer $apiKey',
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'User-Agent': 'GateWire-Flutter/1.0',
    };

    http.Response response;

    try {
      if (method == 'POST') {
        response = await _httpClient.post(
          uri,
          headers: headers,
          body: jsonEncode(body),
        );
      } else {
        response = await _httpClient.get(uri, headers: headers);
      }
    } catch (e) {
      throw GateWireException('Network error: $e');
    }

    final data = jsonDecode(response.body);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return data;
    } else {
      throw GateWireException(
        data['message'] ?? data['error'] ?? 'Unknown API Error',
        response.statusCode,
      );
    }
  }
}
