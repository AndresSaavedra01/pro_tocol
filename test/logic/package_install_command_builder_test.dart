import 'package:flutter_test/flutter_test.dart';
import 'package:pro_tocol/logic/package_install_command_builder.dart';

void main() {
  group('PackageInstallCommandBuilder', () {
    test('builds apt install command', () {
      final command = PackageInstallCommandBuilder.buildInstallCommand(
        packageManager: 'apt',
        packageName: 'git',
      );

      expect(command, 'sudo apt install git');
    });

    test('builds pacman install command', () {
      final command = PackageInstallCommandBuilder.buildInstallCommand(
        packageManager: 'pacman',
        packageName: 'nginx',
      );

      expect(command, 'sudo pacman install nginx');
    });

    test('builds dnf install command', () {
      final command = PackageInstallCommandBuilder.buildInstallCommand(
        packageManager: 'dnf',
        packageName: 'curl',
      );

      expect(command, 'sudo dnf install curl');
    });

    test('rejects unsupported package managers', () {
      expect(
        () => PackageInstallCommandBuilder.buildInstallCommand(
          packageManager: 'zypper',
          packageName: 'git',
        ),
        throwsArgumentError,
      );
    });
  });
}