import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:pro_tocol/model/entities/DataBaseEntities.dart';
import 'package:pro_tocol/model/entities/Server.dart';
import 'package:pro_tocol/model/repositories/ServerRepository.dart';
import 'package:pro_tocol/model/repositories/ProfileRepository.dart';
import 'package:pro_tocol/model/entities/ServerMetrics.dart';
import 'package:pro_tocol/logic/apps_manager_state.dart';
import 'package:pro_tocol/logic/command_history_manager.dart';
import 'package:pro_tocol/logic/package_install_command_builder.dart';

class ServerController {
  final ServerRepository _serverRepository;
  final ProfileRepository _profileRepository;
  final CommandHistoryManager _commandHistoryManager;

  // MAPA VITAL: Mantiene vivas las conexiones. La llave es el ID del ServerConfig.
  final Map<int, Server> _activeConnections = {};
  final Map<int, Map<String, AppInstallState>> _appInstallStates = {};
  final Map<int, ValueNotifier<Map<String, AppInstallState>>> _appInstallNotifiers = {};
  static const String _exitCodeMarker = '__PROTOCOL_EXIT_CODE:';

  ServerController(this._serverRepository, this._profileRepository, this._commandHistoryManager);

  /// 1. VALIDACIÓN Y CREACIÓN
  Future<ServerConfig> createAndLinkServer({
    required int profileId,
    required String host,
    required String username,
    required int port,
    String? password,
    String? privateKey,
  }) async {
    _validateServerInputs(host, username, port, password, privateKey);

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
      ..privateKey = privateKey;

    // Guarda el servidor y lo vincula al perfil usando tu DAO
    await _profileRepository.addServerToProfile(profileId, newConfig);

    return newConfig;
  }

  /// 2. GESTIÓN DE CONEXIONES (SERVICIOS)
  Future<void> connectToServer(ServerConfig config) async {
    final serverId = config.id;

    // Si ya está conectado o en memoria, no hacemos nada
    if (_activeConnections.containsKey(serverId) &&
        _activeConnections[serverId]!.sshService.isConnected) {
      return;
    }

    // Le pedimos al repositorio que ensamble el dominio (Config + SSHService)
    final server = _serverRepository.buildServerFromConfig(config);

    try {
      // Usamos el servicio interno para conectar.
      // Al implementar GeneralConfig, config pasa directo sin problemas.
      await server.sshService.connect(config);

      // Si fue exitoso, lo guardamos en las conexiones activas
      _activeConnections[serverId] = server;

      // Detectar información de distro y package manager en segundo plano.
      await _detectLinuxDistro(server);
    } catch (e) {
      throw Exception('Fallo al conectar con ${config.host}: $e');
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
      debugPrint('[ServerController] Distro detected: ${server.distroName} (PM: ${server.packageManager})');
    } catch (e) {
      debugPrint('[ServerController] Distro detection failed: $e');
      _setDefaultDistroValues(server, e.toString());
    }
  }

  void _setDefaultDistroValues(Server server, String reason) {
    server.distroName = 'Linux';
    server.packageManager = 'unknown';
    debugPrint('[ServerController] Using defaults ($reason)');
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

  Future<void> disconnectFromServer(int serverId) async {
    if (_activeConnections.containsKey(serverId)) {
      _activeConnections[serverId]!.sshService.disconnect();
      _activeConnections.remove(serverId);
    }

    _appInstallStates.remove(serverId);
    final notifier = _appInstallNotifiers.remove(serverId);
    notifier?.dispose();
  }

  /// 3. EJECUCIÓN DE SERVICIOS
  Future<ServerMetrics> getServerMetrics(int serverId) async {
    final server = getActiveServer(serverId);
    return await server.sshService.fetchMetrics();
  }

  Future<String> executeCommand(int serverId, String command) async {
    final server = getActiveServer(serverId);
    final result = await server.sshService.runSingleCommand(command);
    _commandHistoryManager.add(command);
    return result;
  }

  /// Inicia una instalación sin bloquear la UI.
  void installAppInBackground({
    required int serverId,
    required String appId,
    required String packageName,
  }) {
    final server = getActiveServer(serverId);
    final packageManager = (server.packageManager ?? 'unknown').toLowerCase();

    _setInstallState(
      serverId,
      appId,
      AppInstallState.installing('Instalando $packageName...'),
    );

    unawaited(
      _runAppInstall(
        serverId: serverId,
        appId: appId,
        packageName: packageName,
        packageManager: packageManager,
      ),
    );
  }

  AppInstallState getInstallState(int serverId, String appId) {
    return _appInstallStates[serverId]?[appId] ?? const AppInstallState.idle();
  }

  Map<String, AppInstallState> getInstallStates(int serverId) {
    return Map.unmodifiable(_appInstallStates[serverId] ?? {});
  }

  ValueListenable<Map<String, AppInstallState>> installStatesListenable(int serverId) {
    return _appInstallNotifiers.putIfAbsent(
      serverId,
      () => ValueNotifier<Map<String, AppInstallState>>(Map.unmodifiable(_appInstallStates[serverId] ?? {})),
    );
  }

  Future<void> _runAppInstall({
    required int serverId,
    required String appId,
    required String packageName,
    required String packageManager,
  }) async {
    try {
      final server = getActiveServer(serverId);
      final command = PackageInstallCommandBuilder.buildInstallCommand(
        packageManager: packageManager,
        packageName: packageName,
      );
      final commandWithSudoHandling = _withSudoPasswordIfAvailable(
        command,
        server.config.password,
      );

      var result = await _executeCommandWithStatus(server, commandWithSudoHandling);

      // En Arch Linux, pacman usa '-S' para instalar paquetes.
      if (result.exitCode != 0 && packageManager == 'pacman') {
        final fallbackCommand = 'sudo pacman -S --noconfirm $packageName';
        final fallbackCommandWithSudoHandling = _withSudoPasswordIfAvailable(
          fallbackCommand,
          server.config.password,
        );
        result = await _executeCommandWithStatus(server, fallbackCommandWithSudoHandling);
      }

      if (result.exitCode != 0 || _looksLikeInstallFailure(result.output)) {
        final errorMessage = _buildInstallFailureMessage(
          output: result.output,
          packageName: packageName,
          exitCode: result.exitCode,
          hasPassword: (server.config.password ?? '').trim().isNotEmpty,
        );
        _setInstallState(serverId, appId, AppInstallState.failure(errorMessage));
        return;
      }

      _setInstallState(serverId, appId, AppInstallState.success('Instalacion completada: $packageName'));
    } catch (e) {
      _setInstallState(serverId, appId, AppInstallState.failure(e.toString()));
    }
  }

  String _withSudoPasswordIfAvailable(String command, String? password) {
    final trimmedPassword = (password ?? '').trim();
    if (trimmedPassword.isEmpty || !command.startsWith('sudo ')) {
      return command;
    }

    final escapedPassword = _shellSingleQuoteEscape(trimmedPassword);
    final sudoReadyCommand = command.replaceFirst('sudo ', "sudo -S -p '' ");
    return "printf '%s\\n' '$escapedPassword' | $sudoReadyCommand";
  }

  String _shellSingleQuoteEscape(String value) {
    return value.replaceAll("'", "'\"'\"'");
  }

  String _buildInstallFailureMessage({
    required String output,
    required String packageName,
    required int exitCode,
    required bool hasPassword,
  }) {
    final normalized = output.toLowerCase();

    if (normalized.contains('a terminal is required to read the password') ||
        normalized.contains('a password is required')) {
      if (!hasPassword) {
        return 'Sudo requiere contraseña para instalar $packageName y esta conexión no tiene password. Recomendado: reconectar con password o configurar NOPASSWD para ese usuario.';
      }
      return 'Sudo rechazó la instalación de $packageName. Verifica permisos sudo del usuario y la política requiretty/NOPASSWD en el servidor.';
    }

    return output.isEmpty
          ? 'Fallo al instalar $packageName (exit $exitCode)'
            : output;
  }

  Future<({String output, int exitCode})> _executeCommandWithStatus(Server server, String command) async {
    final wrappedCommand = '({ $command; }) 2>&1; echo "$_exitCodeMarker\$?"';
    final raw = await server.sshService.runSingleCommand(wrappedCommand);
    _commandHistoryManager.add(command);

    final markerIndex = raw.lastIndexOf(_exitCodeMarker);
    if (markerIndex == -1) {
      return (output: raw.trim(), exitCode: 1);
    }

    final output = raw.substring(0, markerIndex).trim();
    final exitCodeRaw = raw.substring(markerIndex + _exitCodeMarker.length).trim();
    final exitCode = int.tryParse(exitCodeRaw) ?? 1;

    return (output: output, exitCode: exitCode);
  }

  bool _looksLikeInstallFailure(String output) {
    final normalized = output.toLowerCase();
    return normalized.contains('error') ||
        normalized.contains('failed') ||
        normalized.contains('unable to locate package') ||
        normalized.contains('no se pudo') ||
        normalized.contains('permission denied') ||
        normalized.contains('not found');
  }

  void _setInstallState(int serverId, String appId, AppInstallState state) {
    final next = Map<String, AppInstallState>.from(_appInstallStates[serverId] ?? {});
    next[appId] = state;
    _appInstallStates[serverId] = next;

    final notifier = _appInstallNotifiers.putIfAbsent(
      serverId,
      () => ValueNotifier<Map<String, AppInstallState>>(const {}),
    );
    notifier.value = Map.unmodifiable(next);
  }

  /// Utilidad interna para asegurar que operamos sobre un servidor activo
  Server getActiveServer(int serverId) {
    final server = _activeConnections[serverId];
    if (server == null || !server.sshService.isConnected) {
      throw Exception('El servidor no está conectado. Conecta primero antes de ejecutar comandos.');
    }
    return server;
  }

  /// Acceso al gestor de historial de comandos
  CommandHistoryManager get commandHistoryManager => _commandHistoryManager;

  /// Lógica de validación pura
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

  /// Actualiza una configuración de servidor existente
  Future<void> updateServer(ServerConfig config) async {
    _validateServerInputs(config.host, config.username, config.port, config.password, config.privateKey);
    // Isar maneja la actualización automáticamente si el ID ya existe usando put()
    await _serverRepository.saveServerConfig(config);
  }

  /// Elimina un servidor de la base de datos y cierra su conexión si estaba activa
  Future<void> deleteServer(int id) async {
    await disconnectFromServer(id); // Primero nos aseguramos de no dejar conexiones huérfanas
    await _serverRepository.deleteServer(id);
  }
}