class GateWireException implements Exception {
  final String message;
  final int? statusCode;

  GateWireException(this.message, [this.statusCode]);

  @override
  String toString() => 'GateWireException: $message (Code: $statusCode)';
}
