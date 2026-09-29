import 'dart:io';

import 'package:hermuse_host/hermuse_host.dart' show hostEnvironment;
import 'package:url_launcher/url_launcher.dart';

/// Opens [url] in the user's browser; a URL without a scheme is ignored.
///
/// On Linux it runs `xdg-open` in the [hostEnvironment]: a launch from the
/// app process itself would hand the AppImage's bundled libraries and GTK
/// settings to the host browser. Other platforms go through url_launcher.
/// Opening is best effort: a failure leaves the link where it is.
Future<void> openExternalUrl(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null || !uri.hasScheme) return;
  try {
    if (Platform.isLinux) {
      await Process.start(
        'xdg-open',
        [url],
        mode: ProcessStartMode.detached,
        includeParentEnvironment: false,
        environment: hostEnvironment(),
      );
    } else {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  } on Object {
    // Best effort, see above.
  }
}
