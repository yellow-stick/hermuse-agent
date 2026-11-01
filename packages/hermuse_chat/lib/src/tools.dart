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

/// Host of a tool's `url` argument (`https://` assumed without a scheme),
/// or '' when there is none. A [toolDetail] line works too: its first word.
String urlHost(Object? url) {
  if (url is! String || url.trim().isEmpty) return '';
  final first = url.trim().split(RegExp(r'\s+')).first;
  return Uri.tryParse(first.contains('://') ? first : 'https://$first')?.host ??
      '';
}

/// What the agent is doing while it runs the tool [name] on [detail] (its
/// [toolDetail]), in a few words for the panel under the agent's name:
/// "Searching the web", "Browsing example.com", "Running a command".
String toolStepLabel(String name, {String detail = ''}) {
  switch (toolKindOf(name)) {
    case ToolKind.terminal:
      return 'Running a command';
    case ToolKind.code:
      return 'Running code';
    case ToolKind.file:
      return switch (name) {
        'read_file' => 'Reading a file',
        'search_files' => 'Searching files',
        _ => 'Editing a file',
      };
    case ToolKind.web:
      if (name == 'web_search') return 'Searching the web';
      final host = urlHost(detail);
      return host.isEmpty ? 'Reading the web' : 'Reading $host';
    case ToolKind.browser:
      final host = urlHost(detail);
      return host.isEmpty ? 'Using the browser' : 'Browsing $host';
    case ToolKind.other:
      return switch (name) {
        'memory' => 'Updating memory',
        'session_search' => 'Searching past chats',
        'cronjob' => 'Scheduling',
        'delegate_task' => 'Delegating a task',
        'vision_analyze' => 'Looking at an image',
        'image_generate' => 'Creating an image',
        'todo' => 'Planning',
        'clarify' => 'Asking you',
        'skill_view' || 'skills_list' || 'skill_manage' => 'Reading skills',
        'send_message' => 'Sending a message',
        _ => 'Working',
      };
  }
}

/// What the agent is doing in a running turn whose bubble holds [blocks]:
/// its running tool ([toolStepLabel]), an explained wait, the browser,
/// "Writing" while the answer streams, else "Thinking".
String agentStepLabel(List<Block> blocks) {
  final tool = blocks
      .whereType<ToolCallBlock>()
      .where((b) => b.running)
      .lastOrNull;
  if (tool != null) return toolStepLabel(tool.name, detail: tool.detail);
  if (blocks.whereType<WaitBlock>().lastOrNull case final wait?) {
    return wait.text;
  }
  final shown = [
    for (final b in blocks)
      if (b is! ReasoningBlock && b is! BrowserBlock) b,
  ];
  if (shown.lastOrNull is TextBlock) return 'Writing';
  final browser = blocks
      .whereType<BrowserBlock>()
      .where((b) => b.running && b.step.isNotEmpty)
      .firstOrNull;
  if (browser != null) {
    return browser.host.isEmpty
        ? 'Using the browser'
        : 'Browsing ${browser.host}';
  }
  return 'Thinking';
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
