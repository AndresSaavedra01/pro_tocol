class ManagedApp {
  final String id;
  final String displayName;
  final String packageName;
  final String description;

  const ManagedApp({
    required this.id,
    required this.displayName,
    required this.packageName,
    required this.description,
  });
}

class AppsManagerCatalog {
  static const List<ManagedApp> commonApps = [
    ManagedApp(
      id: 'git',
      displayName: 'Git',
      packageName: 'git',
      description: 'Control de versiones distribuido.',
    ),
    ManagedApp(
      id: 'docker',
      displayName: 'Docker',
      packageName: 'docker',
      description: 'Contenedores y despliegue reproducible.',
    ),
    ManagedApp(
      id: 'nginx',
      displayName: 'Nginx',
      packageName: 'nginx',
      description: 'Servidor web y proxy inverso.',
    ),
    ManagedApp(
      id: 'curl',
      displayName: 'cURL',
      packageName: 'curl',
      description: 'Cliente HTTP de línea de comandos.',
    ),
    ManagedApp(
      id: 'htop',
      displayName: 'htop',
      packageName: 'htop',
      description: 'Monitor interactivo de procesos.',
    ),
    ManagedApp(
      id: 'wget',
      displayName: 'wget',
      packageName: 'wget',
      description: 'Descargas desde la terminal.',
    ),
  ];

  static ManagedApp? byId(String id) {
    for (final app in commonApps) {
      if (app.id == id) {
        return app;
      }
    }
    return null;
  }
}