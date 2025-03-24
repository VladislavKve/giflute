class GigaChatException implements Exception {
  final String message;
  final int? statusCode;
  final dynamic originalError;

  GigaChatException(this.message, {this.statusCode, this.originalError});

  @override
  String toString() => 'GigaChatException: $message${statusCode != null ? ' (Status: $statusCode)' : ''}';
} 