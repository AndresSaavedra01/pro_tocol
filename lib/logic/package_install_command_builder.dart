class PackageInstallCommandBuilder {
  static const Set<String> supportedPackageManagers = {'apt', 'pacman', 'dnf'};

  static String buildInstallCommand({
    required String packageManager,
    required String packageName,
  }) {
    final normalized = _validateInputs(packageManager, packageName);
    final normalizedManager = normalized.$1;
    final normalizedPackage = normalized.$2;

    return 'sudo $normalizedManager install $normalizedPackage';
  }

  static String buildCheckInstalledCommand({
    required String packageManager,
    required String packageName,
  }) {
    final normalized = _validateInputs(packageManager, packageName);
    final normalizedManager = normalized.$1;
    final normalizedPackage = normalized.$2;

    switch (normalizedManager) {
      case 'apt':
        return 'dpkg -s $normalizedPackage >/dev/null 2>&1';
      case 'pacman':
        return 'pacman -Qs $normalizedPackage >/dev/null 2>&1';
      case 'dnf':
        return 'rpm -q $normalizedPackage >/dev/null 2>&1';
      default:
        return 'command -v $normalizedPackage >/dev/null 2>&1';
    }
  }

  static String buildUninstallCommand({
    required String packageManager,
    required String packageName,
  }) {
    final normalized = _validateInputs(packageManager, packageName);
    final normalizedManager = normalized.$1;
    final normalizedPackage = normalized.$2;

    switch (normalizedManager) {
      case 'apt':
        return 'sudo apt remove -y $normalizedPackage';
      case 'pacman':
        return 'sudo pacman -Rns --noconfirm $normalizedPackage';
      case 'dnf':
        return 'sudo dnf remove -y $normalizedPackage';
      default:
        throw ArgumentError('Package manager no soportado: $packageManager');
    }
  }

  static (String, String) _validateInputs(String packageManager, String packageName) {
    final normalizedManager = packageManager.trim().toLowerCase();
    final normalizedPackage = packageName.trim();

    if (normalizedManager.isEmpty) {
      throw ArgumentError('El package manager no puede estar vacío.');
    }

    if (!supportedPackageManagers.contains(normalizedManager)) {
      throw ArgumentError('Package manager no soportado: $packageManager');
    }

    if (normalizedPackage.isEmpty) {
      throw ArgumentError('El nombre del paquete no puede estar vacío.');
    }

    return (normalizedManager, normalizedPackage);
  }
}