import 'dart:io';

class CommandResult {
  const CommandResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  final int exitCode;
  final String stdout;
  final String stderr;

  bool get succeeded => exitCode == 0;
}

abstract class CommandRunner {
  Future<CommandResult> run(String executable, List<String> arguments);
}

class ProcessCommandRunner implements CommandRunner {
  @override
  Future<CommandResult> run(String executable, List<String> arguments) async {
    final result = await Process.run(executable, arguments, runInShell: true);
    return CommandResult(
      exitCode: result.exitCode,
      stdout: result.stdout.toString(),
      stderr: result.stderr.toString(),
    );
  }
}
