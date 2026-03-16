import 'dart:convert';

import 'package:http/http.dart' as http;

import '../exceptions.dart';
import 'models/service_catalog.dart';

/// Fetches and caches the catalog of services enabled for this API key.
///
/// Obtain an instance through [GateWireClient.services] rather than
/// constructing this class directly.
///
/// ## Typical usage
/// ```dart
/// // On app launch or before showing verification UI:
/// final catalog = await gw.services.fetchCatalog();
///
/// if (catalog.otp.enabled) {
///   // show OTP option
/// }
///
/// if (catalog.isPnvAvailableOnThisDevice) {
///   // show PNV option — only on Android AND backend-enabled
/// }
/// ```
class ServicesService {
  final http.Client _httpClient;
  final String _apiKey;
  final String _baseUrl;

  ServiceCatalog? _cachedCatalog;
  DateTime? _cacheTime;

  // ignore: public_member_api_docs — internal constructor, exposed via GateWireClient.services
  ServicesService(this._httpClient, this._apiKey, this._baseUrl);

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Returns the [ServiceCatalog] for the current API key.
  ///
  /// Results are cached in memory for [cacheDuration] (default 5 minutes).
  /// Subsequent calls within the TTL return the cached catalog immediately
  /// without a network request. Call [invalidateCache] to force a refresh.
  ///
  /// Throws [GateWireException] on API or network errors.
  Future<ServiceCatalog> fetchCatalog({
    Duration cacheDuration = const Duration(minutes: 5),
  }) async {
    if (_cachedCatalog != null &&
        _cacheTime != null &&
        DateTime.now().difference(_cacheTime!) < cacheDuration) {
      return _cachedCatalog!;
    }

    final data = await _request('/client/services');
    _cachedCatalog = ServiceCatalog.fromJson(data);
    _cacheTime = DateTime.now();
    return _cachedCatalog!;
  }

  /// Clears the in-memory cache.
  ///
  /// The next call to [fetchCatalog] will hit the network regardless of the
  /// cache TTL. Call this after the user changes a service toggle in your
  /// settings UI so the SDK reflects the new state immediately.
  void invalidateCache() {
    _cachedCatalog = null;
    _cacheTime = null;
  }

  // ---------------------------------------------------------------------------
  // Internal HTTP helper — mirrors GateWireClient._request (GET only).
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>> _request(String endpoint) async {
    final uri = Uri.parse('$_baseUrl$endpoint');
    final headers = {
      'Authorization': 'Bearer $_apiKey',
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'User-Agent': 'GateWire-Flutter/1.0',
    };

    http.Response response;
    try {
      response = await _httpClient.get(uri, headers: headers);
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
