class OperationLog {
  const OperationLog({
    required this.timestamp,
    required this.action,
    required this.message,
    required this.success,
    this.command,
    this.exitCode,
  });

  final DateTime timestamp;
  final String action;
  final String message;
  final bool success;
  final String? command;
  final int? exitCode;

  String get displayTime {
    final h = timestamp.hour.toString().padLeft(2, '0');
    final m = timestamp.minute.toString().padLeft(2, '0');
    final s = timestamp.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }
}
