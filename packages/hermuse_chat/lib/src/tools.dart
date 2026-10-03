import 'dart:convert';

import 'models.dart';

/// What kind of work a Hermes tool does, for its icon in the chat and the
/// Activity tab.
enum ToolKind { terminal, web, browser, file, code, other }

/// [ToolKind] of Hermes' tool [name].
ToolKind toolKindOf(String name) => switch (name) {
  'terminal' || 'process_manage' || 'read_terminal' => ToolKind.terminal,
  'execute_code' => ToolKind.code,
  'read_file' || 'write_file' || 'patch' || 'search_files' => ToolKind.file,
  // `tool_search` or `session_search` is not the web.
  _ when name.startsWith('web_') => ToolKind.web,
  _ when isBrowserTool(name) => ToolKind.browser,
  _ => ToolKind.other,
};

/// The tool name in words: `browser_navigate` → "Browser navigate".
String toolTitle(String name) {
  final words = name.replaceAll(RegExp(r'[_\-.]+'), ' ').trim();
  if (words.isEmpty) return 'Tool';
  return '${words[0].toUpperCase()}${words.substring(1)}';
}

/// Arguments that say what a call works on, most telling first.
const _detailKeys = [
  'command',
  'query',
  'url',
  'urls',
  'path',
  'pattern',
  'name',
  'title',
  'goal',
  'prompt',
  'code',
  'text',
];

/// What the call works on, from its [args]: the command, the search query,
/// the address, the file. '' when none says it.
String toolDetail(Map<String, Object?>? args) {
  if (args == null) return '';
  for (final key in _detailKeys) {
    final value = args[key];
    if (value is String && value.trim().isNotEmpty) return value.trim();
    if (value is List) {
      final items = [
        for (final v in value)
          if (v is String && v.trim().isNotEmpty) v.trim(),
      ];
      if (items.isEmpty) continue;
      return items.length == 1
          ? items.single
          : '${items.first} +${items.length - 1}';
    }
  }
  return '';
}

/// Longest command output a tool row keeps (its end: errors land there).
const toolOutputLimit = 4000;

/// Longest error line a tool row shows.
const _errorLimit = 160;

/// What a finished call returned, as its row shows it.
final class ToolOutcome {
  const ToolOutcome({this.output = '', this.error = ''});

  /// The command's printed output (terminal tools), its last
  /// [toolOutputLimit] characters.
  final String output;

  /// Why it failed, one line; '' when it succeeded.
  final String error;
}

/// Reads Hermes' tool [result]: the decoded JSON of `tool.complete`, or the
/// raw text of a stored transcript row. Only JSON objects carry an outcome.
ToolOutcome toolOutcome(Object? result) {
  var value = result;
  if (value is String) {
    final text = value.trim();
    if (!text.startsWith('{')) return const ToolOutcome();
    try {
      value = jsonDecode(text);
    } on FormatException {
      return const ToolOutcome();
    }
  }
  if (value is! Map) return const ToolOutcome();
  final out = value['output'];
  var output = out is String ? out.trimRight() : '';
  if (output.length > toolOutputLimit) {
    output = '…${output.substring(output.length - toolOutputLimit)}';
  }
  final error = value['error'];
  final exitCode = value['exit_code'];
  final String reason;
  if (error is String && error.trim().isNotEmpty) {
    reason = _errorLine(error);
  } else if (exitCode is int && exitCode != 0) {
    reason = 'Exit code $exitCode';
  } else {
    reason = '';
  }
  return ToolOutcome(output: output, error: reason);
}

/// First sentence of [error], without Hermes' `BLOCKED:` marker.
String _errorLine(String error) {
  var text = error.trim();
  if (text.startsWith('BLOCKED:')) text = text.substring(8).trim();
  final end = text.indexOf(RegExp(r'\.(\s|$)|\n'));
  if (end > 0) text = text.substring(0, end);
  return text.length > _errorLimit
      ? '${text.substring(0, _errorLimit - 1)}…'
      : text;
}

/// "<0.1s", "0.2s", "12s", "1m 5s".
String formatToolDuration(Duration duration) {
  final ms = duration.inMilliseconds;
  if (ms < 100) return '<0.1s';
  if (ms < 10000) return '${(ms / 1000).toStringAsFixed(1)}s';
  final s = duration.inSeconds;
  if (s < 60) return '${s}s';
  return '${s ~/ 60}m ${s % 60}s';
}
