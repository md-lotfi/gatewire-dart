/// Indicates which verification method was used by [GateWireClient.verifyPhone].
enum VerificationMethod {
  /// Phone was verified via USSD carrier dial (Android only).
  pnv,

  /// An OTP SMS was dispatched as a fallback (non-Android platforms).
  ///
  /// Call [GateWireClient.verifyOtp] with [PhoneVerificationResult.referenceId]
  /// after the user enters the code.
  otp,
}

/// Result returned by [GateWireClient.verifyPhone].
///
/// When [method] is [VerificationMethod.pnv], [verified] is immediately
/// available and [referenceId] is `null`.
///
/// When [method] is [VerificationMethod.otp], [verified] is `null` (pending
/// the user entering the SMS code) and [referenceId] holds the session ID
/// to pass to [GateWireClient.verifyOtp].
class PhoneVerificationResult {
  /// Which path was taken: PNV (USSD) or OTP (SMS fallback).
  final VerificationMethod method;

  /// `true` / `false` for PNV; `null` when OTP is pending user input.
  final bool? verified;

  /// OTP session ID for use with [GateWireClient.verifyOtp]. `null` for PNV.
  final String? referenceId;

  /// Human-readable status message.
  final String message;

  const PhoneVerificationResult({
    required this.method,
    required this.message,
    this.verified,
    this.referenceId,
  });
}
