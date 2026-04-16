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

    test('builds apt check installed command', () {
      final command = PackageInstallCommandBuilder.buildCheckInstalledCommand(
        packageManager: 'apt',
        packageName: 'git',
      );

      expect(command, 'dpkg -s git >/dev/null 2>&1');
    });

    test('builds pacman check installed command', () {
      final command = PackageInstallCommandBuilder.buildCheckInstalledCommand(
        packageManager: 'pacman',
        packageName: 'htop',
      );

      expect(command, 'pacman -Qs htop >/dev/null 2>&1');
    });

    test('builds dnf check installed command', () {
      final command = PackageInstallCommandBuilder.buildCheckInstalledCommand(
        packageManager: 'dnf',
        packageName: 'curl',
      );

      expect(command, 'rpm -q curl >/dev/null 2>&1');
    });

    test('builds apt uninstall command', () {
      final command = PackageInstallCommandBuilder.buildUninstallCommand(
        packageManager: 'apt',
        packageName: 'git',
      );

      expect(command, 'sudo apt remove -y git');
    });

    test('builds pacman uninstall command', () {
      final command = PackageInstallCommandBuilder.buildUninstallCommand(
        packageManager: 'pacman',
        packageName: 'htop',
      );

      expect(command, 'sudo pacman -Rns --noconfirm htop');
    });

    test('builds dnf uninstall command', () {
      final command = PackageInstallCommandBuilder.buildUninstallCommand(
        packageManager: 'dnf',
        packageName: 'nginx',
      );

      expect(command, 'sudo dnf remove -y nginx');
    });

    test('builds apt search command', () {
      final command = PackageInstallCommandBuilder.buildSearchCommand(
        packageManager: 'apt',
        query: 'git',
      );

      expect(command, 'apt search git');
    });

    test('builds pacman search command', () {
      final command = PackageInstallCommandBuilder.buildSearchCommand(
        packageManager: 'pacman',
        query: 'docker',
      );

      expect(command, 'pacman -Ss docker');
    });

    test('builds dnf search command', () {
      final command = PackageInstallCommandBuilder.buildSearchCommand(
        packageManager: 'dnf',
        query: 'nginx',
      );

      expect(command, 'dnf search nginx');
    });

    test('rejects empty search query', () {
      expect(
        () => PackageInstallCommandBuilder.buildSearchCommand(
          packageManager: 'apt',
          query: '   ',
        ),
        throwsArgumentError,
      );
    });
  });
}