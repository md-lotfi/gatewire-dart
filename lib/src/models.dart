class GateWireResponse {
  final String referenceId;
  final String status;

  GateWireResponse({required this.referenceId, required this.status});

  factory GateWireResponse.fromJson(Map<String, dynamic> json) {
    return GateWireResponse(
      referenceId: json['reference_id'] ?? '',
      status: json['status'] ?? 'unknown',
    );
  }
}

class OtpVerificationResponse {
  final String status;
  final String message;

  OtpVerificationResponse({required this.status, required this.message});

  factory OtpVerificationResponse.fromJson(Map<String, dynamic> json) {
    return OtpVerificationResponse(
      status: json['status'] ?? 'unknown',
      message: json['message'] ?? '',
    );
  }
}
