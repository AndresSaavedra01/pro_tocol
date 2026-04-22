import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:pro_tocol/model/entities/DataBaseEntities.dart';
import 'package:pro_tocol/model/entities/Server.dart';
import 'package:pro_tocol/model/repositories/ServerRepository.dart';
import 'package:pro_tocol/model/repositories/ProfileRepository.dart';
import 'package:pro_tocol/model/entities/ServerMetrics.dart';
import 'package:pro_tocol/logic/apps_manager_catalog.dart';
import 'package:pro_tocol/logic/apps_manager_state.dart';
import 'package:pro_tocol/logic/command_history_manager.dart';
import 'package:pro_tocol/logic/package_install_command_builder.dart';
import 'package:pro_tocol/logic/template_model.dart';
import 'package:pro_tocol/logic/template_run_result.dart';
import 'package:pro_tocol/logic/template_step.dart';

import 'SshKeyController.dart';

class ServerController {
  final ServerRepository _serverRepository;
  final ProfileRepository _profileRepository;
  final CommandHistoryManager _commandHistoryManager;
  final SshKeyController _sshKeyController; // <- NUEVO

  // MAPA VITAL: Mantiene vivas las conexiones. La llave es el ID del ServerConfig.
  final Map<int, Server> _activeConnections = {};
  final Map<int, Map<String, AppInstallState>> _appInstallStates = {};
  final Map<int, ValueNotifier<Map<String, AppInstallState>>> _appInstallNotifiers = {};
  final Map<int, List<ManagedApp>> _appsSearchResults = {};
  final Map<int, ValueNotifier<List<ManagedApp>>> _appsSearchNotifiers = {};
  final Set<int> _activeTemplateRuns = {};
  static const String _exitCodeMarker = '__PROTOCOL_EXIT_CODE:';

  ServerController(this._serverRepository, this._profileRepository, this._commandHistoryManager, this._sshKeyController);

  /// 1. VALIDACIÓN Y CREACIÓN
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
      //await server.sshService.connectWithKey(config);

      // Si fue exitoso, lo guardamos en las conexiones activas
      _activeConnections[serverId] = server;

      // Detectar información de distro y package manager en segundo plano.
      await _detectLinuxDistro(server);

      // Detectar estado de apps instaladas en segundo plano.
      refreshInstalledAppsInBackground(serverId: serverId);

      // Estado inicial de búsqueda: catálogo base.
      _setSearchResults(serverId, AppsManagerCatalog.commonApps);
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

    _appsSearchResults.remove(serverId);
    final searchNotifier = _appsSearchNotifiers.remove(serverId);
    searchNotifier?.dispose();
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

  /// Inicia una desinstalación sin bloquear la UI.
  void uninstallAppInBackground({
    required int serverId,
    required String appId,
    required String packageName,
  }) {
    final server = getActiveServer(serverId);
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
    final server = getActiveServer(serverId);
    final packageManager = (server.packageManager ?? 'unknown').toLowerCase();

    if (!PackageInstallCommandBuilder.supportedPackageManagers.contains(packageManager)) {
      return;
    }

    await _syncInstalledApps(
      serverId: serverId,
      packageManager: packageManager,
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

  List<ManagedApp> getSearchResults(int serverId) {
    return List.unmodifiable(_appsSearchResults[serverId] ?? AppsManagerCatalog.commonApps);
  }

  ValueListenable<List<ManagedApp>> searchResultsListenable(int serverId) {
    return _appsSearchNotifiers.putIfAbsent(
      serverId,
      () => ValueNotifier<List<ManagedApp>>(List.unmodifiable(_appsSearchResults[serverId] ?? AppsManagerCatalog.commonApps)),
    );
  }

  Future<void> searchApps({
    required int serverId,
    required String query,
  }) async {
    final server = getActiveServer(serverId);
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
      final server = getActiveServer(serverId);
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
    final server = getActiveServer(serverId);

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

  void _setSearchResults(int serverId, List<ManagedApp> results) {
    _appsSearchResults[serverId] = List<ManagedApp>.from(results);
    final notifier = _appsSearchNotifiers.putIfAbsent(
      serverId,
      () => ValueNotifier<List<ManagedApp>>(const []),
    );
    notifier.value = List.unmodifiable(_appsSearchResults[serverId]!);
  }

  Future<TemplateRunResult> runTemplate({
    required int serverId,
    required TemplateModel template,
    void Function(
      TemplateRunResult progress,
      TemplateValidationRequirement? activeValidation,
      TemplateStep? activeStep,
    )? onProgress,
  }) async {
    if (_activeTemplateRuns.contains(serverId)) {
      throw StateError('Ya hay un template en ejecución para este servidor.');
    }

    _activeTemplateRuns.add(serverId);
    try {
      final server = getActiveServer(serverId);
      final startedAt = DateTime.now();
      final validationResults = <TemplateValidationResult>[];
      final results = <TemplateStepResult>[];
      String? failedStepId;
      String? failedValidationId;

      _emitTemplateProgress(
        onProgress,
        template,
        startedAt,
        validationResults,
        results,
        activeValidation: null,
        activeStep: null,
        failedStepId: failedStepId,
        failedValidationId: failedValidationId,
        success: false,
      );

      final validations = await _runTemplateValidations(server, template.validationRequirements);
      validationResults.addAll(validations);
      _emitTemplateProgress(
        onProgress,
        template,
        startedAt,
        validationResults,
        results,
        activeValidation: null,
        activeStep: null,
        failedStepId: failedStepId,
        failedValidationId: failedValidationId,
        success: false,
      );

      final blockingFailure = _firstBlockingValidationFailure(validationResults, template.validationRequirements);

      if (blockingFailure != null) {
        failedValidationId = blockingFailure.$1;
        _appendSkippedStepsAfterValidationFailure(results, template.steps, blockingFailure.$1);
        _emitTemplateProgress(
          onProgress,
          template,
          startedAt,
          validationResults,
          results,
          activeValidation: null,
          activeStep: null,
          failedStepId: failedStepId,
          failedValidationId: failedValidationId,
          success: false,
        );

        return TemplateRunResult(
          templateId: template.id,
          templateName: template.name,
          success: false,
          startedAt: startedAt,
          finishedAt: DateTime.now(),
          validationResults: validationResults,
          failedValidationId: failedValidationId,
          failedStepId: failedStepId,
          stepResults: results,
        );
      }

      for (final step in template.steps) {
        _emitTemplateProgress(
          onProgress,
          template,
          startedAt,
          validationResults,
          results,
          activeValidation: null,
          activeStep: step,
          failedStepId: failedStepId,
          failedValidationId: failedValidationId,
          success: false,
        );

        final stepResult = await _executeTemplateStep(server, step);
        results.add(stepResult);
        _emitTemplateProgress(
          onProgress,
          template,
          startedAt,
          validationResults,
          results,
          activeValidation: null,
          activeStep: null,
          failedStepId: failedStepId,
          failedValidationId: failedValidationId,
          success: false,
        );

        if (stepResult.status == TemplateStepStatus.failure && step.isCritical) {
          failedStepId = step.id;
          _appendSkippedStepsAfterFailure(results, template.steps, step.id);
          _emitTemplateProgress(
            onProgress,
            template,
            startedAt,
            validationResults,
            results,
            activeValidation: null,
            activeStep: null,
            failedStepId: failedStepId,
            failedValidationId: failedValidationId,
            success: false,
          );
          break;
        }
      }

      final finishedAt = DateTime.now();
      final success = failedStepId == null && !results.any((result) => result.status == TemplateStepStatus.failure);

      return TemplateRunResult(
        templateId: template.id,
        templateName: template.name,
        success: success,
        startedAt: startedAt,
        finishedAt: finishedAt,
        validationResults: validationResults,
        failedStepId: failedStepId,
        failedValidationId: failedValidationId,
        stepResults: results,
      );
    } finally {
      _activeTemplateRuns.remove(serverId);
    }
  }

  void _emitTemplateProgress(
    void Function(
      TemplateRunResult progress,
      TemplateValidationRequirement? activeValidation,
      TemplateStep? activeStep,
    )? onProgress,
    TemplateModel template,
    DateTime startedAt,
    List<TemplateValidationResult> validationResults,
    List<TemplateStepResult> stepResults,
    {
    required TemplateValidationRequirement? activeValidation,
    required TemplateStep? activeStep,
    required String? failedStepId,
    required String? failedValidationId,
    required bool success,
  }) {
    if (onProgress == null) return;

    onProgress(
      TemplateRunResult(
        templateId: template.id,
        templateName: template.name,
        success: success,
        startedAt: startedAt,
        finishedAt: DateTime.now(),
        validationResults: List<TemplateValidationResult>.from(validationResults),
        failedStepId: failedStepId,
        failedValidationId: failedValidationId,
        stepResults: List<TemplateStepResult>.from(stepResults),
      ),
      activeValidation,
      activeStep,
    );
  }

  Future<List<TemplateValidationResult>> _runTemplateValidations(
    Server server,
    List<TemplateValidationRequirement> validations,
  ) async {
    final results = <TemplateValidationResult>[];
    String? failedBlockingValidationId;

    for (final validation in validations) {
      final result = await _executeTemplateValidation(server, validation);
      results.add(result);

      if (result.status == TemplateValidationStatus.failure && validation.isBlocking) {
        failedBlockingValidationId = validation.id;
        break;
      }
    }

    if (failedBlockingValidationId != null) {
      final failedIndex = validations.indexWhere((validation) => validation.id == failedBlockingValidationId);
      if (failedIndex != -1) {
        final skippedAt = DateTime.now();
        for (final validation in validations.skip(failedIndex + 1)) {
          results.add(
            TemplateValidationResult(
              validationId: validation.id,
              label: validation.label,
              kind: validation.kind,
              status: TemplateValidationStatus.skipped,
              startedAt: skippedAt,
              finishedAt: skippedAt,
              error: 'Omitido por fallo crítico en una validación anterior.',
            ),
          );
        }
      }
    }

    return results;
  }

  (String, TemplateValidationRequirement)? _firstBlockingValidationFailure(
    List<TemplateValidationResult> results,
    List<TemplateValidationRequirement> validations,
  ) {
    for (final result in results) {
      if (result.status != TemplateValidationStatus.failure) {
        continue;
      }

      final validation = validations.firstWhere(
        (item) => item.id == result.validationId,
        orElse: () => TemplateValidationRequirement(
          id: result.validationId,
          label: result.label,
          description: result.error ?? '',
          kind: result.kind,
          isBlocking: false,
        ),
      );

      if (validation.isBlocking) {
        return (result.validationId, validation);
      }
    }

    return null;
  }

  Future<TemplateValidationResult> _executeTemplateValidation(
    Server server,
    TemplateValidationRequirement validation,
  ) async {
    final startedAt = DateTime.now();

    String command;
    switch (validation.kind) {
      case TemplateValidationKind.diskSpace:
        command = 'df -Pm / | awk "NR==2 {print \$4}"';
        break;
      case TemplateValidationKind.portFree:
        final port = validation.port;
        if (port == null) {
          return TemplateValidationResult(
            validationId: validation.id,
            label: validation.label,
            kind: validation.kind,
            status: validation.isBlocking ? TemplateValidationStatus.failure : TemplateValidationStatus.skipped,
            startedAt: startedAt,
            finishedAt: DateTime.now(),
            error: 'La validación de puerto no define un número de puerto.',
          );
        }
        command = "sh -lc '! ss -ltn \"( sport = :$port )\" | tail -n +2 | grep -q .'";
        break;
      case TemplateValidationKind.packageManagerReady:
        final packageManager = validation.packageManager ?? server.packageManager ?? 'unknown';
        command = 'command -v $packageManager >/dev/null 2>&1';
        break;
    }

    final result = await _executeCommandWithStatus(server, command, addToHistory: false);
    final finishedAt = DateTime.now();

    if (validation.kind == TemplateValidationKind.diskSpace) {
      final availableMb = int.tryParse(result.output.trim()) ?? 0;
      final minimumMb = validation.minimumFreeDiskSpaceMb ?? 0;

      if (result.exitCode != 0 || availableMb < minimumMb) {
        return TemplateValidationResult(
          validationId: validation.id,
          label: validation.label,
          kind: validation.kind,
          status: validation.isBlocking ? TemplateValidationStatus.failure : TemplateValidationStatus.skipped,
          startedAt: startedAt,
          finishedAt: finishedAt,
          output: result.output,
          error: 'Espacio insuficiente: $availableMb MB libres, mínimo requerido $minimumMb MB.',
        );
      }

      return TemplateValidationResult(
        validationId: validation.id,
        label: validation.label,
        kind: validation.kind,
        status: TemplateValidationStatus.success,
        startedAt: startedAt,
        finishedAt: finishedAt,
        output: result.output,
      );
    }

    if (result.exitCode != 0) {
      return TemplateValidationResult(
        validationId: validation.id,
        label: validation.label,
        kind: validation.kind,
        status: validation.isBlocking ? TemplateValidationStatus.failure : TemplateValidationStatus.skipped,
        startedAt: startedAt,
        finishedAt: finishedAt,
        output: result.output,
        error: _validationFailureMessage(validation),
      );
    }

    return TemplateValidationResult(
      validationId: validation.id,
      label: validation.label,
      kind: validation.kind,
      status: TemplateValidationStatus.success,
      startedAt: startedAt,
      finishedAt: finishedAt,
      output: result.output,
    );
  }

  Future<TemplateStepResult> _executeTemplateStep(Server server, TemplateStep step) async {
    final startedAt = DateTime.now();

    if (step.command == null || step.command!.trim().isEmpty) {
      final status = step.isCritical ? TemplateStepStatus.failure : TemplateStepStatus.skipped;
      return TemplateStepResult(
        stepId: step.id,
        title: step.title,
        kind: step.kind,
        status: status,
        startedAt: startedAt,
        finishedAt: DateTime.now(),
        error: step.isCritical ? 'El paso no tiene comando definido.' : 'Paso omitido.',
      );
    }

    final resolvedCommand = _resolveTemplateCommand(
      step.command!,
      packageManager: server.packageManager ?? 'unknown',
      serviceName: server.config.host,
    );
    final result = await _executeCommandWithStatus(server, resolvedCommand);
    final finishedAt = DateTime.now();

    if (result.exitCode != 0) {
      return TemplateStepResult(
        stepId: step.id,
        title: step.title,
        kind: step.kind,
        status: TemplateStepStatus.failure,
        startedAt: startedAt,
        finishedAt: finishedAt,
        output: result.output,
        error: result.output.isEmpty ? 'Fallo al ejecutar el paso (${result.exitCode}).' : result.output,
      );
    }

    return TemplateStepResult(
      stepId: step.id,
      title: step.title,
      kind: step.kind,
      status: TemplateStepStatus.success,
      startedAt: startedAt,
      finishedAt: finishedAt,
      output: result.output,
    );
  }

  void _appendSkippedStepsAfterFailure(
    List<TemplateStepResult> results,
    List<TemplateStep> steps,
    String failedStepId,
  ) {
    final failedIndex = steps.indexWhere((step) => step.id == failedStepId);
    if (failedIndex == -1) return;

    final skippedAt = DateTime.now();
    for (final step in steps.skip(failedIndex + 1)) {
      results.add(
        TemplateStepResult(
          stepId: step.id,
          title: step.title,
          kind: step.kind,
          status: TemplateStepStatus.skipped,
          startedAt: skippedAt,
          finishedAt: skippedAt,
          error: 'Omitido por fallo crítico en un paso anterior.',
        ),
      );
    }
  }

  void _appendSkippedStepsAfterValidationFailure(
    List<TemplateStepResult> results,
    List<TemplateStep> steps,
    String failedValidationId,
  ) {
    final skippedAt = DateTime.now();
    for (final step in steps) {
      results.add(
        TemplateStepResult(
          stepId: step.id,
          title: step.title,
          kind: step.kind,
          status: TemplateStepStatus.skipped,
          startedAt: skippedAt,
          finishedAt: skippedAt,
          error: 'Omitido por fallo crítico en una validación previa ($failedValidationId).',
        ),
      );
    }
  }

  String _validationFailureMessage(TemplateValidationRequirement validation) {
    switch (validation.kind) {
      case TemplateValidationKind.diskSpace:
        return validation.description.isNotEmpty
            ? validation.description
            : 'Validación de espacio en disco fallida.';
      case TemplateValidationKind.portFree:
        final port = validation.port;
        return port == null
            ? 'Validación de puerto fallida.'
            : 'El puerto $port no está libre.';
      case TemplateValidationKind.packageManagerReady:
        final packageManager = validation.packageManager ?? 'package manager';
        return 'El package manager $packageManager no está listo.';
    }
  }

  String _resolveTemplateCommand(
    String command, {
    required String packageManager,
    required String serviceName,
  }) {
    return command
        .replaceAll(r'${packageManager}', packageManager)
        .replaceAll(r'${serviceName}', serviceName);
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
    _validateServerInputs(config.host, config.username, config.port, config.password, config.keyPairId);
    // Isar maneja la actualización automáticamente si el ID ya existe usando put()
    await _serverRepository.saveServerConfig(config);
  }

  /// Elimina un servidor de la base de datos y cierra su conexión si estaba activa
  Future<void> deleteServer(int id) async {
    await disconnectFromServer(id); // Primero nos aseguramos de no dejar conexiones huérfanas
    await _serverRepository.deleteServer(id);
  }
}