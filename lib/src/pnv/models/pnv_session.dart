/// Response from `POST /api/v1/pnv/initiate`.
///
/// Contains the USSD code to dial and session metadata returned by the
/// GateWire backend when a Phone Number Verification session is created.
class PnvSession {
  /// Unique identifier for this PNV session. Pass to [PnvService.verify].
  final String referenceId;

  /// Human-readable name of the mobile operator (e.g. "Djezzy").
  final String operatorName;

  /// ISO 3166-1 alpha-2 country code (e.g. "DZ").
  final String countryCode;

  /// The USSD code to dial on the device (e.g. "*555#").
  final String ussdCode;

  /// UTC timestamp after which this session can no longer be verified.
  final DateTime expiresAt;

  const PnvSession({
    required this.referenceId,
    required this.operatorName,
    required this.countryCode,
    required this.ussdCode,
    required this.expiresAt,
  });

  /// Creates a [PnvSession] from the JSON map returned by `/pnv/initiate`.
  factory PnvSession.fromJson(Map<String, dynamic> json) {
    return PnvSession(
      referenceId:  json['reference_id']  as String,
      operatorName: json['operator_name'] as String,
      countryCode:  json['country_code']  as String,
      ussdCode:     json['ussd_code']     as String,
      expiresAt:    DateTime.parse(json['expires_at'] as String),
    );
  }
}
