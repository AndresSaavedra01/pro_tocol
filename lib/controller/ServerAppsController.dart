
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:pro_tocol/model/entities/Server.dart';
import 'package:pro_tocol/logic/apps_manager_catalog.dart';
import 'package:pro_tocol/logic/apps_manager_state.dart';
import 'package:pro_tocol/logic/command_history_manager.dart';
import 'package:pro_tocol/logic/package_install_command_builder.dart';

import 'ServerConnectionController.dart'; // Importa el controlador de conexión

class ServerAppsController {
  final ServerConnectionController _connectionController;
  final CommandHistoryManager _commandHistoryManager;

  final Map<int, Map<String, AppInstallState>> _appInstallStates = {};
  final Map<int, ValueNotifier<Map<String, AppInstallState>>> _appInstallNotifiers = {};
  final Map<int, List<ManagedApp>> _appsSearchResults = {};
  final Map<int, ValueNotifier<List<ManagedApp>>> _appsSearchNotifiers = {};

  static const String _exitCodeMarker = '__PROTOCOL_EXIT_CODE:';

  ServerAppsController(this._connectionController, this._commandHistoryManager);

  /// ==========================================
  /// 1. MÉTODOS PÚBLICOS DE GESTIÓN DE APPS
  /// ==========================================

  /// Inicia una instalación sin bloquear la UI.
  void installAppInBackground({
    required int serverId,
    required String appId,
    required String packageName,
  }) {
    final server = _connectionController.getActiveServer(serverId);
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

  /// Inicia una desinstalación sin bloquear la UI.
  void uninstallAppInBackground({
    required int serverId,
    required String appId,
    required String packageName,
  }) {
    final server = _connectionController.getActiveServer(serverId);
    final packageManager = (server.packageManager ?? 'unknown').toLowerCase();

    _setInstallState(
      serverId,
      appId,
      AppInstallState.uninstalling('Eliminando $packageName...'),
    );

    unawaited(
      _runAppUninstall(
        serverId: serverId,
        appId: appId,
        packageName: packageName,
        packageManager: packageManager,
      ),
    );
  }

  /// Sincroniza en segundo plano si cada app del catálogo está instalada.
  void refreshInstalledAppsInBackground({required int serverId}) {
    unawaited(refreshInstalledApps(serverId: serverId));
  }

  /// Sincroniza de forma explícita si cada app del catálogo está instalada.
  Future<void> refreshInstalledApps({required int serverId}) async {
    final server = _connectionController.getActiveServer(serverId);
    final packageManager = (server.packageManager ?? 'unknown').toLowerCase();

    if (!PackageInstallCommandBuilder.supportedPackageManagers.contains(packageManager)) {
      return;
    }

    await _syncInstalledApps(
      serverId: serverId,
      packageManager: packageManager,
    );
  }

  Future<void> searchApps({
    required int serverId,
    required String query,
  }) async {
    final server = _connectionController.getActiveServer(serverId);
    final normalizedQuery = query.trim().toLowerCase();
    final packageManager = (server.packageManager ?? 'unknown').toLowerCase();

    final localMatches = _searchInCatalog(normalizedQuery);
    if (normalizedQuery.isEmpty) {
      _setSearchResults(serverId, localMatches);
      return;
    }

    if (!PackageInstallCommandBuilder.supportedPackageManagers.contains(packageManager)) {
      _setSearchResults(serverId, localMatches);
      return;
    }

    try {
      final searchCommand = PackageInstallCommandBuilder.buildSearchCommand(
        packageManager: packageManager,
        query: normalizedQuery,
      );

      final result = await _executeCommandWithStatus(
        server,
        searchCommand,
        addToHistory: false,
      );

      if (result.exitCode != 0 || result.output.trim().isEmpty) {
        _setSearchResults(serverId, localMatches);
        return;
      }

      final remoteMatches = _parseRemoteSearchResults(
        packageManager: packageManager,
        rawOutput: result.output,
      );

      final merged = _mergeSearchResults(localMatches, remoteMatches);
      _setSearchResults(serverId, merged);
    } catch (_) {
      _setSearchResults(serverId, localMatches);
    }
  }

  /// Inicializa la búsqueda por defecto (llamar después de conectar)
  void initSearchCatalog(int serverId) {
    _setSearchResults(serverId, AppsManagerCatalog.commonApps);
  }

  /// Limpia los recursos al desconectar
  void disposeServerResources(int serverId) {
    _appInstallStates.remove(serverId);
    final notifier = _appInstallNotifiers.remove(serverId);
    notifier?.dispose();

    _appsSearchResults.remove(serverId);
    final searchNotifier = _appsSearchNotifiers.remove(serverId);
    searchNotifier?.dispose();
  }

  /// ==========================================
  /// 2. LISTENERS Y ESTADOS PARA LA UI
  /// ==========================================

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

  List<ManagedApp> getSearchResults(int serverId) {
    return List.unmodifiable(_appsSearchResults[serverId] ?? AppsManagerCatalog.commonApps);
  }

  ValueListenable<List<ManagedApp>> searchResultsListenable(int serverId) {
    return _appsSearchNotifiers.putIfAbsent(
      serverId,
          () => ValueNotifier<List<ManagedApp>>(List.unmodifiable(_appsSearchResults[serverId] ?? AppsManagerCatalog.commonApps)),
    );
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

  void _setSearchResults(int serverId, List<ManagedApp> results) {
    _appsSearchResults[serverId] = List<ManagedApp>.from(results);
    final notifier = _appsSearchNotifiers.putIfAbsent(
      serverId,
          () => ValueNotifier<List<ManagedApp>>(const []),
    );
    notifier.value = List.unmodifiable(_appsSearchResults[serverId]!);
  }

  /// ==========================================
  /// 3. LÓGICA INTERNA DE COMANDOS Y PARSEO
  /// ==========================================

  Future<void> _runAppInstall({
    required int serverId,
    required String appId,
    required String packageName,
    required String packageManager,
  }) async {
    try {
      final server = _connectionController.getActiveServer(serverId);
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
        final errorMessage = _buildPackageCommandFailureMessage(
          output: result.output,
          packageName: packageName,
          exitCode: result.exitCode,
          hasPassword: (server.config.password ?? '').trim().isNotEmpty,
          action: 'instalar',
        );
        _setInstallState(serverId, appId, AppInstallState.failure(errorMessage));
        return;
      }

      _setInstallState(serverId, appId, AppInstallState.installed('Instalada: $packageName'));
    } catch (e) {
      _setInstallState(serverId, appId, AppInstallState.failure(e.toString()));
    }
  }

  Future<void> _runAppUninstall({
    required int serverId,
    required String appId,
    required String packageName,
    required String packageManager,
  }) async {
    try {
      final server = _connectionController.getActiveServer(serverId);
      final command = PackageInstallCommandBuilder.buildUninstallCommand(
        packageManager: packageManager,
        packageName: packageName,
      );
      final commandWithSudoHandling = _withSudoPasswordIfAvailable(
        command,
        server.config.password,
      );

      final result = await _executeCommandWithStatus(server, commandWithSudoHandling);

      if (result.exitCode != 0 || _looksLikeInstallFailure(result.output)) {
        final errorMessage = _buildPackageCommandFailureMessage(
          output: result.output,
          packageName: packageName,
          exitCode: result.exitCode,
          hasPassword: (server.config.password ?? '').trim().isNotEmpty,
          action: 'eliminar',
        );
        _setInstallState(serverId, appId, AppInstallState.failure(errorMessage));
        return;
      }

      _setInstallState(serverId, appId, const AppInstallState.idle());
    } catch (e) {
      _setInstallState(serverId, appId, AppInstallState.failure(e.toString()));
    }
  }

  Future<void> _syncInstalledApps({
    required int serverId,
    required String packageManager,
  }) async {
    final server = _connectionController.getActiveServer(serverId);

    for (final app in AppsManagerCatalog.commonApps) {
      final currentState = getInstallState(serverId, app.id);
      if (currentState.isBusy) {
        continue;
      }

      final isInstalled = await _isAppInstalled(
        server: server,
        packageManager: packageManager,
        packageName: app.packageName,
      );

      if (isInstalled) {
        _setInstallState(serverId, app.id, AppInstallState.installed('Instalada: ${app.packageName}'));
      } else {
        _setInstallState(serverId, app.id, const AppInstallState.idle());
      }
    }
  }

  Future<bool> _isAppInstalled({
    required Server server,
    required String packageManager,
    required String packageName,
  }) async {
    final command = PackageInstallCommandBuilder.buildCheckInstalledCommand(
      packageManager: packageManager,
      packageName: packageName,
    );
    final result = await _executeCommandWithStatus(
      server,
      command,
      addToHistory: false,
    );
    return result.exitCode == 0;
  }

  Future<({String output, int exitCode})> _executeCommandWithStatus(
      Server server,
      String command, {
        bool addToHistory = true,
      }) async {
    final wrappedCommand = '({ $command; }) 2>&1; echo "$_exitCodeMarker\$?"';
    final raw = await server.sshService.runSingleCommand(wrappedCommand);
    if (addToHistory) {
      _commandHistoryManager.add(command);
    }

    final markerIndex = raw.lastIndexOf(_exitCodeMarker);
    if (markerIndex == -1) {
      return (output: raw.trim(), exitCode: 1);
    }

    final output = raw.substring(0, markerIndex).trim();
    final exitCodeRaw = raw.substring(markerIndex + _exitCodeMarker.length).trim();
    final exitCode = int.tryParse(exitCodeRaw) ?? 1;

    return (output: output, exitCode: exitCode);
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

  String _buildPackageCommandFailureMessage({
    required String output,
    required String packageName,
    required int exitCode,
    required bool hasPassword,
    required String action,
  }) {
    final normalized = output.toLowerCase();

    if (normalized.contains('a terminal is required to read the password') ||
        normalized.contains('a password is required')) {
      if (!hasPassword) {
        return 'Sudo requiere contraseña para $action $packageName y esta conexión no tiene password. Recomendado: reconectar con password o configurar NOPASSWD para ese usuario.';
      }
      return 'Sudo rechazó la operación para $action $packageName. Verifica permisos sudo del usuario y la política requiretty/NOPASSWD en el servidor.';
    }

    return output.isEmpty
        ? 'Fallo al $action $packageName (exit $exitCode)'
        : output;
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

  List<ManagedApp> _searchInCatalog(String normalizedQuery) {
    if (normalizedQuery.isEmpty) {
      return List<ManagedApp>.from(AppsManagerCatalog.commonApps);
    }

    return AppsManagerCatalog.commonApps.where((app) {
      final id = app.id.toLowerCase();
      final name = app.displayName.toLowerCase();
      final packageName = app.packageName.toLowerCase();
      final description = app.description.toLowerCase();

      return id.contains(normalizedQuery) ||
          name.contains(normalizedQuery) ||
          packageName.contains(normalizedQuery) ||
          description.contains(normalizedQuery);
    }).toList();
  }

  List<ManagedApp> _parseRemoteSearchResults({
    required String packageManager,
    required String rawOutput,
  }) {
    switch (packageManager) {
      case 'apt':
        return _parseAptSearchResults(rawOutput);
      case 'pacman':
        return _parsePacmanSearchResults(rawOutput);
      case 'dnf':
        return _parseDnfSearchResults(rawOutput);
      default:
        return const [];
    }
  }

  List<ManagedApp> _parseAptSearchResults(String output) {
    final results = <ManagedApp>[];
    final lines = output.split('\n');

    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('Sorting') || line.startsWith('Full Text Search')) {
        continue;
      }
      if (!line.contains('/')) {
        continue;
      }

      final packageName = line.split('/').first.trim();
      if (packageName.isEmpty) {
        continue;
      }

      results.add(_toManagedApp(packageName: packageName));
      if (results.length >= 30) break;
    }

    return results;
  }

  List<ManagedApp> _parsePacmanSearchResults(String output) {
    final results = <ManagedApp>[];
    final lines = output.split('\n');

    for (final rawLine in lines) {
      if (!rawLine.contains('/')) {
        continue;
      }

      final line = rawLine.trim();
      if (line.isEmpty) {
        continue;
      }

      final firstToken = line.split(RegExp(r'\s+')).first;
      final slashIndex = firstToken.indexOf('/');
      if (slashIndex == -1 || slashIndex == firstToken.length - 1) {
        continue;
      }

      final packageName = firstToken.substring(slashIndex + 1).trim();
      if (packageName.isEmpty) {
        continue;
      }

      results.add(_toManagedApp(packageName: packageName));
      if (results.length >= 30) break;
    }

    return results;
  }

  List<ManagedApp> _parseDnfSearchResults(String output) {
    final results = <ManagedApp>[];
    final lines = output.split('\n');

    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('=')) {
        continue;
      }

      final separatorIndex = line.indexOf(':');
      if (separatorIndex == -1) {
        continue;
      }

      final leftPart = line.substring(0, separatorIndex).trim();
      if (leftPart.isEmpty) {
        continue;
      }

      final firstToken = leftPart.split(RegExp(r'\s+')).first;
      final packageName = firstToken.replaceFirst(RegExp(r'\.(x86_64|i686|noarch|aarch64)$'), '').trim();
      if (packageName.isEmpty) {
        continue;
      }

      results.add(_toManagedApp(packageName: packageName));
      if (results.length >= 30) break;
    }

    return results;
  }

  ManagedApp _toManagedApp({
    required String packageName,
    String? fallbackDescription,
  }) {
    final normalized = packageName.toLowerCase();
    for (final app in AppsManagerCatalog.commonApps) {
      if (app.packageName.toLowerCase() == normalized || app.id.toLowerCase() == normalized) {
        return app;
      }
    }

    return ManagedApp(
      id: packageName,
      displayName: packageName,
      packageName: packageName,
      description: fallbackDescription ?? 'Resultado remoto',
    );
  }

  List<ManagedApp> _mergeSearchResults(List<ManagedApp> local, List<ManagedApp> remote) {
    final byPackage = <String, ManagedApp>{};

    for (final app in local) {
      byPackage[app.packageName.toLowerCase()] = app;
    }
    for (final app in remote) {
      byPackage.putIfAbsent(app.packageName.toLowerCase(), () => app);
    }

    return byPackage.values.toList(growable: false);
  }
}