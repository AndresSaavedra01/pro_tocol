
import 'dart:async';
import 'package:pro_tocol/model/entities/Server.dart';
import 'package:pro_tocol/logic/command_history_manager.dart';
import 'package:pro_tocol/logic/template_model.dart';
import 'package:pro_tocol/logic/template_run_result.dart';
import 'package:pro_tocol/logic/template_step.dart';

import 'ServerConnectionController.dart'; // Dependencia para obtener el servidor activo

class ServerTemplateController {
  final ServerConnectionController _connectionController;
  final CommandHistoryManager _commandHistoryManager;

  // Evita ejecuciones simultáneas de plantillas en el mismo servidor
  final Set<int> _activeTemplateRuns = {};

  static const String _exitCodeMarker = '__PROTOCOL_EXIT_CODE:';

  ServerTemplateController(this._connectionController, this._commandHistoryManager);

  /// ==========================================
  /// 1. MÉTODO PRINCIPAL DE EJECUCIÓN
  /// ==========================================

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
      final server = _connectionController.getActiveServer(serverId);
      final startedAt = DateTime.now();
      final validationResults = <TemplateValidationResult>[];
      final results = <TemplateStepResult>[];
      String? failedStepId;
      String? failedValidationId;

      // Estado inicial
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

      // Fase 1: Validaciones
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

      // Fase 2: Ejecución de pasos
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

  /// ==========================================
  /// 2. LÓGICA DE VALIDACIÓN Y PASOS
  /// ==========================================

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

  /// ==========================================
  /// 3. UTILIDADES PRIVADAS
  /// ==========================================

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

  (String, TemplateValidationRequirement)? _firstBlockingValidationFailure(
      List<TemplateValidationResult> results,
      List<TemplateValidationRequirement> validations,
      ) {
    for (final result in results) {
      if (result.status != TemplateValidationStatus.failure) continue;

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
}