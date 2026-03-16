import 'dart:io' show Platform;

/// Pricing and availability information for a single GateWire service.
class ServiceInfo {
  /// Whether this service is enabled for the current API key.
  final bool enabled;

  /// Cost per API request in the smallest currency unit (e.g. fils, centimes).
  final int pricePerRequestCents;

  /// ISO 4217 currency code for [pricePerRequestCents] (e.g. `"DZD"`).
  final String currency;

  /// Platform scope: `"all"` for cross-platform services (OTP),
  /// `"android"` for USSD-based services (PNV).
  final String platform;

  const ServiceInfo({
    required this.enabled,
    required this.pricePerRequestCents,
    required this.currency,
    required this.platform,
  });

  /// Parses a [ServiceInfo] from a single service entry in the
  /// `GET /api/v1/client/services` response.
  factory ServiceInfo.fromJson(Map<String, dynamic> json) {
    return ServiceInfo(
      enabled: json['enabled'] as bool,
      pricePerRequestCents: json['price_per_request_cents'] as int,
      currency: json['currency'] as String,
      platform: json['platform'] as String,
    );
  }
}

/// Catalog of services available to the current API key, returned by
/// [ServicesService.fetchCatalog].
///
/// Use [isPnvAvailableOnThisDevice] as the single source of truth when
/// deciding whether to offer PNV in your UI.
///
/// ## Recommended usage
/// ```dart
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
class ServiceCatalog {
  /// OTP (SMS) service availability and pricing.
  final ServiceInfo otp;

  /// PNV (USSD phone number verification) service availability and pricing.
  final ServiceInfo pnv;

  // Injected platform check — defaults to dart:io Platform.isAndroid.
  // Exposed for testing: pass `isAndroid: () => true/false` in tests to avoid
  // dart:io dependency.
  final bool Function() _isAndroid;

  ServiceCatalog({
    required this.otp,
    required this.pnv,
    bool Function()? isAndroid,
  }) : _isAndroid = isAndroid ?? _defaultIsAndroid;

  static bool _defaultIsAndroid() => Platform.isAndroid;

  /// `true` when PNV is enabled for this API key **and** the current device
  /// is Android (USSD is a carrier-level feature unavailable on iOS/web/desktop).
  bool get isPnvAvailableOnThisDevice => pnv.enabled && _isAndroid();

  /// Parses a [ServiceCatalog] from the `GET /api/v1/client/services` response.
  ///
  /// Pass [isAndroid] to override platform detection — useful in unit tests:
  /// ```dart
  /// ServiceCatalog.fromJson(json, isAndroid: () => true);
  /// ```
  factory ServiceCatalog.fromJson(
    Map<String, dynamic> json, {
    bool Function()? isAndroid,
  }) {
    final services = json['services'] as Map<String, dynamic>;
    return ServiceCatalog(
      otp: ServiceInfo.fromJson(services['otp'] as Map<String, dynamic>),
      pnv: ServiceInfo.fromJson(services['pnv'] as Map<String, dynamic>),
      isAndroid: isAndroid,
    );
  }
}
