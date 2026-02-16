import 'dart:convert';
import 'package:http/http.dart' as http;
import 'exceptions.dart';
import 'models.dart';

class GateWireClient {
  final String apiKey;
  final String baseUrl;
  final http.Client _httpClient;

  GateWireClient({
    required this.apiKey,
    this.baseUrl = 'https://gatewire.raystate.com/api/v1',
    http.Client? client,
  }) : _httpClient = client ?? http.Client();

  /// Send an SMS or OTP
  Future<GateWireResponse> dispatch({
    required String phone,
    String? templateKey,
  }) async {
    final body = {
      'phone': phone,
      if (templateKey != null) 'template_key': templateKey,
    };

    final response = await _request('POST', '/dispatch', body);
    return GateWireResponse.fromJson(response);
  }

  /// Verify an OTP code
  Future<OtpVerificationResponse> verifyOtp({
    required String referenceId,
    required String code,
  }) async {
    final body = {
      'reference_id': referenceId,
      'code': code,
    };

    final response = await _request('POST', '/verify-otp', body);
    return OtpVerificationResponse.fromJson(response);
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
