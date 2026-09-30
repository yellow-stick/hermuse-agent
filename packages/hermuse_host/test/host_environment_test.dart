import 'dart:io';

import 'package:hermuse_host/hermuse_host.dart';
import 'package:test/test.dart';

void main() {
  group('hostEnvironment', () {
    test('returns the environment as is outside an AppImage', () {
      final environment = {
        'PATH': '/usr/bin:/bin',
        'LD_LIBRARY_PATH': '/opt/lib',
        'APPDIR': '/not/from/apprun',
      };
      expect(hostEnvironment(environment), environment);
    });

    test('restores the originals AppRun saved', () {
      final host = hostEnvironment({
        'HERMUSE_APPIMAGE_ENV_SAVED': '1',
        'HERMUSE_ORIG_PATH': '/home/u/.local/bin:/usr/bin',
        'PATH': '/tmp/.mount_x/usr/bin:/home/u/.local/bin:/usr/bin',
        'HERMUSE_ORIG_LD_LIBRARY_PATH': '/opt/cuda/lib64',
        'LD_LIBRARY_PATH': '/tmp/.mount_x/usr/lib:/opt/cuda/lib64',
        'HERMUSE_ORIG_XDG_DATA_DIRS': '/usr/local/share:/usr/share',
        'XDG_DATA_DIRS': '/tmp/.mount_x/usr/share:/usr/local/share:/usr/share',
        'HOME': '/home/u',
      });
      expect(host['PATH'], '/home/u/.local/bin:/usr/bin');
      expect(host['LD_LIBRARY_PATH'], '/opt/cuda/lib64');
      expect(host['XDG_DATA_DIRS'], '/usr/local/share:/usr/share');
      expect(host['HOME'], '/home/u');
    });

    test('removes what AppRun set when the session had no value', () {
      final host = hostEnvironment({
        'HERMUSE_APPIMAGE_ENV_SAVED': '1',
        'HERMUSE_ORIG_PATH': '/usr/bin',
        'PATH': '/tmp/.mount_x/usr/bin:/usr/bin',
        'LD_LIBRARY_PATH': '/tmp/.mount_x/usr/lib',
        'GTK_PATH': '/tmp/.mount_x/usr/lib/gtk-3.0',
        'GDK_BACKEND': 'x11',
        'GSETTINGS_SCHEMA_DIR': '/tmp/.mount_x/usr/share/glib-2.0/schemas',
      });
      expect(host, {'PATH': '/usr/bin'});
    });

    test('drops the AppImage bookkeeping and runtime variables', () {
      final host = hostEnvironment({
        'HERMUSE_APPIMAGE_ENV_SAVED': '1',
        'HERMUSE_ORIG_PATH': '/usr/bin',
        'HERMUSE_ORIG_UNLISTED': 'kept nowhere',
        'PATH': '/tmp/.mount_x/usr/bin:/usr/bin',
        'APPDIR': '/tmp/.mount_x',
        'APPIMAGE': '/home/u/Hermuse-Agent.AppImage',
        'APPOFFSET': '123456',
        'ARGV0': 'Hermuse-Agent.AppImage',
        'OWD': '/home/u',
        'URUNTIME': '/home/u/Hermuse-Agent.AppImage',
        'URUNTIME_DIR': '/tmp/.mount_x',
        'DBUS_SESSION_BUS_ADDRESS': 'unix:path=/run/user/1000/bus',
      });
      expect(host, {
        'PATH': '/usr/bin',
        'DBUS_SESSION_BUS_ADDRESS': 'unix:path=/run/user/1000/bus',
      });
    });
  });

  group('macOS login PATH', () {
    late Directory etc;

    setUp(() async {
      etc = await Directory.systemTemp.createTemp('host_environment_test');
      await File('${etc.path}/paths').writeAsString(
        '/usr/local/bin\n/System/Cryptexes/App/usr/bin\n/usr/bin\n/bin\n'
        '/usr/sbin\n/sbin\n',
      );
      await Directory('${etc.path}/paths.d').create();
      await File('${etc.path}/paths.d/40-tool')
          .writeAsString('/opt/tool/bin\n');
      await File('${etc.path}/paths.d/10-other')
          .writeAsString('\n/opt/other/bin\n');
    });

    tearDown(() => etc.delete(recursive: true));

    test('reads /etc/paths, then /etc/paths.d by name, like path_helper', () {
      expect(macOSSystemPaths(etc: etc.path), [
        '/usr/local/bin',
        '/System/Cryptexes/App/usr/bin',
        '/usr/bin',
        '/bin',
        '/usr/sbin',
        '/sbin',
        '/opt/other/bin',
        '/opt/tool/bin',
      ]);
    });

    test('an app opened from the Finder gets the missing directories after '
        'its own', () {
      final host = withSystemPath({
        'PATH': '/usr/bin:/bin:/usr/sbin:/sbin',
        'HOME': '/Users/u',
      }, macOSSystemPaths(etc: etc.path));
      expect(
        host['PATH'],
        '/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:'
        '/System/Cryptexes/App/usr/bin:/opt/other/bin:/opt/tool/bin',
      );
      expect(host['HOME'], '/Users/u');
      expect(withSystemPath({'PATH': host['PATH']!}, ['/usr/local/bin']), {
        'PATH': host['PATH'],
      });
    });
  });

  test('Windows children get no PowerShell 7 module path to load', () {
    // The app started from PowerShell 7 (a terminal, winget), which put its
    // own module directories first.
    final host = withoutPowerShellModulePath({
      'Path': r'C:\Windows\system32;C:\Windows',
      'PSModulePath':
          r'C:\Users\u\Documents\PowerShell\Modules;'
          r'C:\Program Files\PowerShell\Modules;'
          r'c:\program files\powershell\7\Modules;'
          r'C:\Program Files\WindowsPowerShell\Modules;'
          r'C:\Windows\system32\WindowsPowerShell\v1.0\Modules',
      'USERPROFILE': r'C:\Users\u',
    });
    expect(host, {
      'Path': r'C:\Windows\system32;C:\Windows',
      'USERPROFILE': r'C:\Users\u',
    });
    // Windows names stay case-insensitive, whatever their spelling.
    expect(host['PATH'], r'C:\Windows\system32;C:\Windows');
    expect(withoutPowerShellModulePath({'PSMODULEPATH': r'C:\m'}), isEmpty);
  });
}
