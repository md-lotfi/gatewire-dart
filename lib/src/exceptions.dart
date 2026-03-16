/// Exception thrown by all GateWire SDK methods on API or network errors.
///
/// [statusCode] is the HTTP response code when available, or `null` for
/// network-level errors (e.g. no connectivity).
///
/// [code] is a machine-readable error identifier. Currently defined values:
/// - `'service_disabled'` — the requested service (OTP or PNV) is not enabled
///   for this API key. Direct the user to enable it from the GateWire dashboard.
class GateWireException implements Exception {
  final String message;
  final int? statusCode;

  /// Machine-readable error code. `null` for generic API / network errors.
  final String? code;

  GateWireException(this.message, [this.statusCode, this.code]);

  @override
  String toString() => 'GateWireException: $message (Code: $statusCode)';
}
