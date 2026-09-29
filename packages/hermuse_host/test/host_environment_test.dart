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
}
