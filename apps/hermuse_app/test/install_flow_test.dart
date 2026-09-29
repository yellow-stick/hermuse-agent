import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_client/hermes_client.dart';
import 'package:hermuse_app/host/install_flow.dart';
import 'package:hermuse_app/platform/local_host.dart';
import 'package:hermuse_host/hermuse_host.dart';
import 'package:yellow_stick_ui/yellow_stick_ui.dart';
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';

void main() {
  testWidgets('should open the Command Line Tools installer on macOS, then '
      'go on once they are installed', (tester) async {
    const tools = '/Library/Developer/CommandLineTools';
    var installed = false;
    var requests = 0;
    final planRead = Completer<void>();
    final installer = HermesInstaller(
      hermesHome: '/h',
      installDir: '/h/hermes-agent',
      isWindows: false,
      isMacOS: true,
      source: const InstallerSource(
        isWindows: false,
        localScript: '/fake/install.sh',
      ),
      environment: const {'PATH': '/usr/bin'},
      // The /usr/bin/git stub is there with or without the tools.
      which: (name) async => '/usr/bin/$name',
      fileExists: (path) async =>
          path == '/fake/install.sh' ||
          (installed && path == '$tools/usr/bin/git'),
      runScript: (executable, args, {environment, onLine}) {
        if (executable == '/usr/bin/xcode-select') {
          if (args.contains('--install')) {
            requests++;
            return Future.value(ProcessResult(0, 0, '', ''));
          }
          return Future.value(
            installed
                ? ProcessResult(0, 0, '$tools\n', '')
                : ProcessResult(0, 2, '', 'no active developer directory'),
          );
        }
        // `--manifest`: the flow went past the prerequisites.
        if (!planRead.isCompleted) planRead.complete();
        return Completer<ProcessResult>().future;
      },
    );
    final host = LocalHermesHost.test(
      detector: HermesDetector(
        isWindows: false,
        environment: const {'HERMES_HOME': '/h'},
        homeDirectory: '/nowhere',
        fileExists: (_) async => false,
        runVersion: (_, _) async => ProcessResult(0, 1, '', ''),
        which: (_) async => null,
      ),
      secrets: MemorySecretStore(),
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MediaQuery(
          data: MediaQueryData.fromView(tester.view),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: YsTheme(
              palette: YsPalette.dark,
              child: Overlay.wrap(
                child: InstallFlowScreen(
                  host: host,
                  detected: null,
                  installer: installer,
                  onDone: (_) {},
                  onCancel: () {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(
      find.text('Missing tools: ${HermesInstaller.commandLineTools}.'),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(YsButton, 'Install'));
    await tester.pump();

    expect(requests, 1);
    expect(
      find.text(
        'Finish the installation in the dialog that opened, then check again.',
      ),
      findsOneWidget,
    );
    expect(find.widgetWithText(YsButton, 'Install'), findsNothing);

    // Still missing: the flow stays on the prerequisites.
    await tester.tap(find.widgetWithText(YsButton, 'Check again'));
    await tester.pump();
    await tester.pump();
    expect(planRead.isCompleted, isFalse);

    installed = true;
    await tester.tap(find.widgetWithText(YsButton, 'Check again'));
    await tester.pump();
    await tester.pump();
    expect(planRead.isCompleted, isTrue);
    expect(find.text('Reading install plan…'), findsOneWidget);
  });
}
