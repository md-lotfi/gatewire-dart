/// Response from `POST /api/v1/pnv/verify`.
///
/// Indicates whether the phone number was successfully verified by comparing
/// the USSD response against the number on the session.
class PnvResult {
  /// `true` if the carrier USSD response matched the expected phone number.
  final bool verified;

  /// Human-readable message from the backend describing the outcome.
  final String message;

  const PnvResult({
    required this.verified,
    required this.message,
  });

  /// Creates a [PnvResult] from the JSON map returned by `/pnv/verify`.
  factory PnvResult.fromJson(Map<String, dynamic> json) {
    return PnvResult(
      verified: json['verified'] as bool,
      message:  json['message']  as String,
    );
  }
}
