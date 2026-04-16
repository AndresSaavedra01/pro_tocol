
import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:pro_tocol/logic/apps_manager_state.dart';
import 'package:pro_tocol/model/entities/TempSession.dart';
import 'package:pro_tocol/model/entities/TempSessionConfig.dart';
import 'package:pro_tocol/model/repositories/TempSessionRepository.dart';
import 'package:pro_tocol/logic/command_history_manager.dart';
import 'package:pro_tocol/logic/package_install_command_builder.dart';

class TempSessionController {
  final TempSessionRepository _repository;
  final CommandHistoryManager _commandHistoryManager;

  // Mapa para gestionar las sesiones activas en ejecución (Key: un ID único generado en RAM)
  final Map<String, TempSession> _activeSessions = {};
  final Map<String, Map<String, AppInstallState>> _appInstallStates = {};
  final Map<String, ValueNotifier<Map<String, AppInstallState>>> _appInstallNotifiers = {};

  TempSessionController(this._repository, this._commandHistoryManager);

  Future<TempSession> createAndConnect({
    required String host,
    required String username,
    required int port,
    String? password,
    String? privateKey,
  }) async {
    // Validamos los campos igual que en el servidor persistente
    _validateInputs(host, username, port, password, privateKey);

    // Creamos la configuración volátil
    final config = TempSessionConfig(password: password,
        host: host,
        username: username,
        port: port,
        privateKey: privateKey
    );


    // El repositorio ensambla el modelo (Config + SSHService)
    final session = _repository.buildTempSession(config);

    try {
      // Intentamos la conexión SSH
      await session.sshService.connect(config);

      // Si tiene éxito, la guardamos en nuestro mapa de sesiones activas
      // Usamos el host como llave temporal o un hash de la config
      _activeSessions[host] = session;

      await _detectLinuxDistro(session);

      return session;
    } catch (e) {
      throw Exception('Fallo al conectar sesión temporal con $host: $e');
    }
  }

  Future<void> _detectLinuxDistro(TempSession session) async {
    try {
      if (!session.sshService.isConnected) {
        _setDefaultDistroValues(session, 'Not connected');
        return;
      }

      final rawOsRelease = await session.sshService.runSingleCommand('cat /etc/os-release');
      
      if (rawOsRelease.trim().isEmpty) {
        _setDefaultDistroValues(session, 'Empty os-release');
        return;
      }

      final values = _parseOsRelease(rawOsRelease);
      
      if (values.isEmpty) {
        _setDefaultDistroValues(session, 'Failed to parse os-release');
        return;
      }

      final id = values['ID']?.toLowerCase();
      final name = values['NAME']?.replaceAll('"', '').trim();
      final idLike = values['ID_LIKE']?.toLowerCase();

      if (id == null || id.isEmpty) {
        _setDefaultDistroValues(session, 'Missing ID field');
        return;
      }

      session.distroName = name ?? id;
      session.packageManager = _resolvePackageManager(id, idLike);
      debugPrint('[TempSessionController] Distro detected: ${session.distroName} (PM: ${session.packageManager})');
    } catch (e) {
      debugPrint('[TempSessionController] Distro detection failed: $e');
      _setDefaultDistroValues(session, e.toString());
    }
  }

  void _setDefaultDistroValues(TempSession session, String reason) {
    session.distroName = 'Linux';
    session.packageManager = 'unknown';
    debugPrint('[TempSessionController] Using defaults ($reason)');
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

  /// 2. GESTIÓN DE ESTADO
  Future<void> disconnectAndRemove(String host) async {
    if (_activeSessions.containsKey(host)) {
      final session = _activeSessions[host]!;
      await _repository.removeTempSession(session);
      _activeSessions.remove(host);
    }

    _appInstallStates.remove(host);
    final notifier = _appInstallNotifiers.remove(host);
    notifier?.dispose();
  }


  Future<String> runCommand(String host, String command) async {
    final session = _getValidSession(host);
    final result = await session.sshService.runSingleCommand(command);
    _commandHistoryManager.add(command);
    return result;
  }

  /// Inicia una instalación sin bloquear la UI.
  void installAppInBackground({
    required String host,
    required String appId,
    required String packageName,
  }) {
    final session = _getValidSession(host);
    final packageManager = (session.packageManager ?? 'unknown').toLowerCase();

    _setInstallState(
      host,
      appId,
      AppInstallState.installing('Instalando $packageName...'),
    );

    unawaited(
      _runAppInstall(
        host: host,
        appId: appId,
        packageName: packageName,
        packageManager: packageManager,
      ),
    );
  }

  AppInstallState getInstallState(String host, String appId) {
    return _appInstallStates[host]?[appId] ?? const AppInstallState.idle();
  }

  Map<String, AppInstallState> getInstallStates(String host) {
    return Map.unmodifiable(_appInstallStates[host] ?? {});
  }

  ValueListenable<Map<String, AppInstallState>> installStatesListenable(String host) {
    return _appInstallNotifiers.putIfAbsent(
      host,
      () => ValueNotifier<Map<String, AppInstallState>>(Map.unmodifiable(_appInstallStates[host] ?? {})),
    );
  }

  Future<void> _runAppInstall({
    required String host,
    required String appId,
    required String packageName,
    required String packageManager,
  }) async {
    try {
      final command = PackageInstallCommandBuilder.buildInstallCommand(
        packageManager: packageManager,
        packageName: packageName,
      );

      final output = await runCommand(host, command);

      if (_looksLikeInstallFailure(output)) {
        _setInstallState(host, appId, AppInstallState.failure(output.isEmpty ? 'Fallo desconocido' : output));
        return;
      }

      _setInstallState(host, appId, AppInstallState.success('Instalacion completada: $packageName'));
    } catch (e) {
      _setInstallState(host, appId, AppInstallState.failure(e.toString()));
    }
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

  void _setInstallState(String host, String appId, AppInstallState state) {
    final next = Map<String, AppInstallState>.from(_appInstallStates[host] ?? {});
    next[appId] = state;
    _appInstallStates[host] = next;

    final notifier = _appInstallNotifiers.putIfAbsent(
      host,
      () => ValueNotifier<Map<String, AppInstallState>>(const {}),
    );
    notifier.value = Map.unmodifiable(next);
  }

  /// Utilidad interna para asegurar que la sesión existe y está conectada
  TempSession _getValidSession(String host) {
    final session = _activeSessions[host];
    if (session == null || !session.sshService.isConnected) {
      throw Exception('La sesión temporal en $host no está activa.');
    }
    return session;
  }

  /// Lógica de validación pura (DRY: Reutiliza la misma lógica de ServerController)
  void _validateInputs(String host, String username, int port, String? password, String? privateKey) {
    if (host.trim().isEmpty) throw ArgumentError('El host es obligatorio.');
    if (username.trim().isEmpty) throw ArgumentError('El usuario es obligatorio.');
    if (port <= 0 || port > 65535) throw ArgumentError('Puerto inválido.');

    if ((password == null || password.isEmpty) && (privateKey == null || privateKey.isEmpty)) {
      throw ArgumentError('Se requiere contraseña o llave privada.');
    }
  }

  /// Retorna la lista de sesiones para mostrar en el Sidebar
  List<TempSession> getActiveSessions() {
    return _activeSessions.values.toList();
  }


  TempSession getValidSession(String host) {
    final session = _activeSessions[host];
    if (session == null || !session.sshService.isConnected) {
      throw Exception('La sesión temporal en $host no está activa.');
    }
    return session;
  }

  /// Acceso al gestor de historial de comandos
  CommandHistoryManager get commandHistoryManager => _commandHistoryManager;
}