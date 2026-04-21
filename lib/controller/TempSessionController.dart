
import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:pro_tocol/logic/apps_manager_catalog.dart';
import 'package:pro_tocol/logic/apps_manager_state.dart';
import 'package:pro_tocol/model/entities/TempSession.dart';
import 'package:pro_tocol/model/entities/TempSessionConfig.dart';
import 'package:pro_tocol/model/repositories/TempSessionRepository.dart';
import 'package:pro_tocol/logic/command_history_manager.dart';
import 'package:pro_tocol/logic/package_install_command_builder.dart';
import 'package:pro_tocol/logic/template_model.dart';
import 'package:pro_tocol/logic/template_run_result.dart';
import 'package:pro_tocol/logic/template_step.dart';

class TempSessionController {
  final TempSessionRepository _repository;
  final CommandHistoryManager _commandHistoryManager;

  // Mapa para gestionar las sesiones activas en ejecución (Key: un ID único generado en RAM)
  final Map<String, TempSession> _activeSessions = {};
  final Map<String, Map<String, AppInstallState>> _appInstallStates = {};
  final Map<String, ValueNotifier<Map<String, AppInstallState>>> _appInstallNotifiers = {};
  static const String _exitCodeMarker = '__PROTOCOL_EXIT_CODE:';

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

      refreshInstalledAppsInBackground(host: host);

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

  /// Inicia una desinstalación sin bloquear la UI.
  void uninstallAppInBackground({
    required String host,
    required String appId,
    required String packageName,
  }) {
    final session = _getValidSession(host);
    final packageManager = (session.packageManager ?? 'unknown').toLowerCase();

    _setInstallState(
      host,
      appId,
      AppInstallState.uninstalling('Eliminando $packageName...'),
    );

    unawaited(
      _runAppUninstall(
        host: host,
        appId: appId,
        packageName: packageName,
        packageManager: packageManager,
      ),
    );
  }

  /// Sincroniza en segundo plano si cada app del catálogo está instalada.
  void refreshInstalledAppsInBackground({required String host}) {
    final session = _getValidSession(host);
    final packageManager = (session.packageManager ?? 'unknown').toLowerCase();

    if (!PackageInstallCommandBuilder.supportedPackageManagers.contains(packageManager)) {
      return;
    }

    unawaited(
      _syncInstalledApps(
        host: host,
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
      final session = _getValidSession(host);
      final command = PackageInstallCommandBuilder.buildInstallCommand(
        packageManager: packageManager,
        packageName: packageName,
      );
      final commandWithSudoHandling = _withSudoPasswordIfAvailable(
        command,
        session.config.password,
      );

      var result = await _executeCommandWithStatus(session, commandWithSudoHandling);

      // En Arch Linux, pacman usa '-S' para instalar paquetes.
      if (result.exitCode != 0 && packageManager == 'pacman') {
        final fallbackCommand = 'sudo pacman -S --noconfirm $packageName';
        final fallbackCommandWithSudoHandling = _withSudoPasswordIfAvailable(
          fallbackCommand,
          session.config.password,
        );
        result = await _executeCommandWithStatus(session, fallbackCommandWithSudoHandling);
      }

      if (result.exitCode != 0 || _looksLikeInstallFailure(result.output)) {
        final errorMessage = _buildPackageCommandFailureMessage(
          output: result.output,
          packageName: packageName,
          exitCode: result.exitCode,
          hasPassword: (session.config.password ?? '').trim().isNotEmpty,
          action: 'instalar',
        );
        _setInstallState(host, appId, AppInstallState.failure(errorMessage));
        return;
      }

      _setInstallState(host, appId, AppInstallState.installed('Instalada: $packageName'));
    } catch (e) {
      _setInstallState(host, appId, AppInstallState.failure(e.toString()));
    }
  }

  Future<void> _runAppUninstall({
    required String host,
    required String appId,
    required String packageName,
    required String packageManager,
  }) async {
    try {
      final session = _getValidSession(host);
      final command = PackageInstallCommandBuilder.buildUninstallCommand(
        packageManager: packageManager,
        packageName: packageName,
      );
      final commandWithSudoHandling = _withSudoPasswordIfAvailable(
        command,
        session.config.password,
      );

      final result = await _executeCommandWithStatus(session, commandWithSudoHandling);

      if (result.exitCode != 0 || _looksLikeInstallFailure(result.output)) {
        final errorMessage = _buildPackageCommandFailureMessage(
          output: result.output,
          packageName: packageName,
          exitCode: result.exitCode,
          hasPassword: (session.config.password ?? '').trim().isNotEmpty,
          action: 'eliminar',
        );
        _setInstallState(host, appId, AppInstallState.failure(errorMessage));
        return;
      }

      _setInstallState(host, appId, const AppInstallState.idle());
    } catch (e) {
      _setInstallState(host, appId, AppInstallState.failure(e.toString()));
    }
  }

  Future<void> _syncInstalledApps({
    required String host,
    required String packageManager,
  }) async {
    final session = _getValidSession(host);

    for (final app in AppsManagerCatalog.commonApps) {
      final currentState = getInstallState(host, app.id);
      if (currentState.isBusy) {
        continue;
      }

      final isInstalled = await _isAppInstalled(
        session: session,
        packageManager: packageManager,
        packageName: app.packageName,
      );

      if (isInstalled) {
        _setInstallState(host, app.id, AppInstallState.installed('Instalada: ${app.packageName}'));
      } else {
        _setInstallState(host, app.id, const AppInstallState.idle());
      }
    }
  }

  Future<bool> _isAppInstalled({
    required TempSession session,
    required String packageManager,
    required String packageName,
  }) async {
    final command = PackageInstallCommandBuilder.buildCheckInstalledCommand(
      packageManager: packageManager,
      packageName: packageName,
    );
    final result = await _executeCommandWithStatus(
      session,
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
    TempSession session,
    String command, {
    bool addToHistory = true,
  }) async {
    final wrappedCommand = '({ $command; }) 2>&1; echo "$_exitCodeMarker\$?"';
    final raw = await session.sshService.runSingleCommand(wrappedCommand);
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

  Future<TemplateRunResult> runTemplate({
    required String host,
    required TemplateModel template,
  }) async {
    final session = _getValidSession(host);
    final startedAt = DateTime.now();
    final validationResults = <TemplateValidationResult>[];
    final results = <TemplateStepResult>[];
    String? failedStepId;
    String? failedValidationId;

    final validations = await _runTemplateValidations(session, template.validationRequirements);
    validationResults.addAll(validations);

    final blockingFailure = _firstBlockingValidationFailure(validationResults, template.validationRequirements);

    if (blockingFailure != null) {
      failedValidationId = blockingFailure.$1;
      _appendSkippedStepsAfterValidationFailure(results, template.steps, blockingFailure.$1);

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
      final stepResult = await _executeTemplateStep(session, step);
      results.add(stepResult);

      if (stepResult.status == TemplateStepStatus.failure && step.isCritical) {
        failedStepId = step.id;
        _appendSkippedStepsAfterFailure(results, template.steps, step.id);
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
  }

  Future<List<TemplateValidationResult>> _runTemplateValidations(
    TempSession session,
    List<TemplateValidationRequirement> validations,
  ) async {
    final results = <TemplateValidationResult>[];
    String? failedBlockingValidationId;

    for (final validation in validations) {
      final result = await _executeTemplateValidation(session, validation);
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

  Future<TemplateValidationResult> _executeTemplateValidation(
    TempSession session,
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
        final packageManager = validation.packageManager ?? session.packageManager ?? 'unknown';
        command = 'command -v $packageManager >/dev/null 2>&1';
        break;
    }

    final result = await _executeCommandWithStatus(
      session,
      command,
      addToHistory: false,
    );
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

  Future<TemplateStepResult> _executeTemplateStep(TempSession session, TemplateStep step) async {
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

    final result = await _executeCommandWithStatus(session, step.command!);
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