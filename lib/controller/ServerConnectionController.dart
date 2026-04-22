import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:pro_tocol/model/entities/DataBaseEntities.dart';
import 'package:pro_tocol/model/entities/Server.dart';
import 'package:pro_tocol/model/repositories/ServerRepository.dart';
import 'package:pro_tocol/model/repositories/ProfileRepository.dart';
import 'SshKeyController.dart';

class ServerConnectionController {
  final ServerRepository _serverRepository;
  final ProfileRepository _profileRepository;
  final SshKeyController sshKeyController;

  // MAPA VITAL: Mantiene vivas las conexiones. La llave es el ID del ServerConfig.
  final Map<int, Server> _activeConnections = {};

  ServerConnectionController(
      this._serverRepository,
      this._profileRepository,
      this.sshKeyController,
      );

  /// ==========================================
  /// 1. CRUD Y CONFIGURACIÓN (BASE DE DATOS)
  /// ==========================================

  Future<ServerConfig> createAndLinkServer({
    required int profileId,
    required String host,
    required String username,
    required int port,
    String? password,
    String? keyPairId,
  }) async {
    _validateServerInputs(host, username, port, password, keyPairId);

    // Verificamos que el perfil exista antes de crear el servidor
    final profile = await _profileRepository.getProfileById(profileId);
    if (profile == null) {
      throw Exception('El perfil con ID $profileId no existe.');
    }

    final newConfig = ServerConfig()
      ..host = host.trim()
      ..username = username.trim()
      ..port = port
      ..password = password
      ..keyPairId = keyPairId;

    // Guarda el servidor y lo vincula al perfil
    await _profileRepository.addServerToProfile(profileId, newConfig);

    return newConfig;
  }

  /// Obtiene la configuración actualizada de un servidor desde la base de datos.
  Future<ServerConfig?> getServerConfig(int id) async {
    try {
      return await _serverRepository.getServerConfigById(id);
    } catch (e) {
      debugPrint('Error al obtener la configuración del servidor $id: $e');
      return null;
    }
  }

  /// Actualiza una configuración de servidor existente
  Future<void> updateServer(ServerConfig config) async {
    _validateServerInputs(config.host, config.username, config.port, config.password, config.keyPairId);
    await _serverRepository.saveServerConfig(config);
  }

  /// Elimina un servidor de la base de datos y cierra su conexión si estaba activa
  Future<void> deleteServer(int id) async {
    await disconnectFromServer(id);
    await _serverRepository.deleteServer(id);
  }

  /// Genera llaves SSH, las instala en el servidor remoto y actualiza la BD.
  Future<void> upgradeServerToKeyAuth(int serverId) async {
    final config = await _serverRepository.getServerConfigById(serverId);
    if (config == null) throw Exception("No se encontró la configuración del servidor.");

    try {
      final newKeyId = await sshKeyController.generateAndInstallKey(config);
      config.keyPairId = newKeyId;

      await updateServer(config);
      await disconnectFromServer(serverId);
    } catch (e) {
      throw Exception("Error al subir de nivel la seguridad: $e");
    }
  }

  /// ==========================================
  /// 2. GESTIÓN DEL CICLO DE VIDA (CONEXIONES)
  /// ==========================================

  Future<void> connectToServer(ServerConfig config) async {
    final serverId = config.id;

    // Si ya está conectado, no hacemos nada
    if (_activeConnections.containsKey(serverId) &&
        _activeConnections[serverId]!.sshService.isConnected) {
      return;
    }

    final server = _serverRepository.buildServerFromConfig(config);

    try {
      String? privateKeyContent;

      if (config.keyPairId != null && config.keyPairId!.isNotEmpty) {
        privateKeyContent = await sshKeyController.getPrivateKey(config.keyPairId!);
      }

      await server.sshService.connect(config, privateKeyPem: privateKeyContent);
      _activeConnections[serverId] = server;

      // Detectar información de distro y package manager en segundo plano
      await _detectLinuxDistro(server);

      // NOTA: La lógica de `refreshInstalledAppsInBackground` y `_setSearchResults`
      // fue movida a ServerAppsController. Deberás llamarlas desde la Fachada o UI
      // justo después de que este método termine exitosamente.

    } catch (e) {
      throw Exception('Fallo al conectar con ${config.host}: $e');
    }
  }

  Future<void> disconnectFromServer(int serverId) async {
    if (_activeConnections.containsKey(serverId)) {
      _activeConnections[serverId]!.sshService.disconnect();
      _activeConnections.remove(serverId);
    }
    // NOTA: Deberás llamar a `ServerAppsController.disposeServerResources(serverId)`
    // desde tu orquestador para limpiar la memoria de los notifiers.
  }

  /// Proveedor de acceso seguro al servidor conectado para los demás controladores
  Server getActiveServer(int serverId) {
    final server = _activeConnections[serverId];
    if (server == null || !server.sshService.isConnected) {
      throw Exception('El servidor no está conectado. Conecta primero antes de ejecutar comandos.');
    }
    return server;
  }

  /// ==========================================
  /// 3. UTILIDADES PRIVADAS (DISTRO & VALIDACIÓN)
  /// ==========================================

  void _validateServerInputs(String host, String username, int port, String? password, String? privateKey) {
    if (host.trim().isEmpty) throw ArgumentError('El host es obligatorio.');
    if (username.trim().isEmpty) throw ArgumentError('El usuario es obligatorio.');
    if (port <= 0 || port > 65535) throw ArgumentError('El puerto debe ser entre 1 y 65535.');

    final hasPassword = password != null && password.isNotEmpty;
    final hasKey = privateKey != null && privateKey.isNotEmpty;

    if (!hasPassword && !hasKey) {
      throw ArgumentError('Debes proporcionar una contraseña o una llave privada RSA/ED25519.');
    }
  }

  Future<void> _detectLinuxDistro(Server server) async {
    try {
      if (!server.sshService.isConnected) {
        _setDefaultDistroValues(server, 'Not connected');
        return;
      }

      final rawOsRelease = await server.sshService.runSingleCommand('cat /etc/os-release');

      if (rawOsRelease.trim().isEmpty) {
        _setDefaultDistroValues(server, 'Empty os-release');
        return;
      }

      final values = _parseOsRelease(rawOsRelease);

      if (values.isEmpty) {
        _setDefaultDistroValues(server, 'Failed to parse os-release');
        return;
      }

      final id = values['ID']?.toLowerCase();
      final name = values['NAME']?.replaceAll('"', '').trim();
      final idLike = values['ID_LIKE']?.toLowerCase();

      if (id == null || id.isEmpty) {
        _setDefaultDistroValues(server, 'Missing ID field');
        return;
      }

      server.distroName = name ?? id;
      server.packageManager = _resolvePackageManager(id, idLike);
      debugPrint('[ServerConnectionController] Distro detected: ${server.distroName} (PM: ${server.packageManager})');
    } catch (e) {
      debugPrint('[ServerConnectionController] Distro detection failed: $e');
      _setDefaultDistroValues(server, e.toString());
    }
  }

  void _setDefaultDistroValues(Server server, String reason) {
    server.distroName = 'Linux';
    server.packageManager = 'unknown';
    debugPrint('[ServerConnectionController] Using defaults ($reason)');
  }

  Map<String, String> _parseOsRelease(String raw) {
    final lines = raw.split('\n');
    final Map<String, String> values = {};

    for (final line in lines) {
      if (line.trim().isEmpty || !line.contains('=')) continue;
      final index = line.indexOf('=');
      final key = line.substring(0, index).trim();
      final value = line.substring(index + 1).trim().replaceAll('"', '');
      values[key] = value;
    }

    return values;
  }

  String _resolvePackageManager(String? id, String? idLike) {
    final normalizedIdLike = idLike ?? '';

    if (id == 'ubuntu' || id == 'debian' || normalizedIdLike.contains('debian')) {
      return 'apt';
    }
    if (id == 'arch' || id == 'manjaro' || normalizedIdLike.contains('arch')) {
      return 'pacman';
    }
    if (id == 'fedora' || id == 'rhel' || normalizedIdLike.contains('fedora') || normalizedIdLike.contains('rhel')) {
      return 'dnf';
    }
    return 'unknown';
  }
}