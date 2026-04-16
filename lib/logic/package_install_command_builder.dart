class PackageInstallCommandBuilder {
  static const Set<String> supportedPackageManagers = {'apt', 'pacman', 'dnf'};

  static String buildInstallCommand({
    required String packageManager,
    required String packageName,
  }) {
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

    return 'sudo $normalizedManager install $normalizedPackage';
  }
}