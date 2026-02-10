class GateWireResponse {
  final String referenceId;
  final String status;
  final double? cost;

  GateWireResponse({
    required this.referenceId,
    required this.status,
    this.cost,
  });

  factory GateWireResponse.fromJson(Map<String, dynamic> json) {
    return GateWireResponse(
      referenceId: json['reference_id'] ?? '',
      status: json['status'] ?? 'unknown',
      cost: json['cost'] != null ? (json['cost'] as num).toDouble() : null,
    );
  }
}

class GateWireBalance {
  final double balance;
  final String currency;

  GateWireBalance({required this.balance, required this.currency});

  factory GateWireBalance.fromJson(Map<String, dynamic> json) {
    return GateWireBalance(
      balance: (json['balance'] as num).toDouble(),
      currency: json['currency'] ?? 'DZD',
    );
  }
}
