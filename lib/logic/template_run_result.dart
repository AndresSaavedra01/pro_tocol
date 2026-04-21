import 'template_model.dart';
import 'template_step.dart';

enum TemplateValidationStatus {
  pending,
  running,
  success,
  failure,
  skipped,
}

class TemplateValidationResult {
  final String validationId;
  final String label;
  final TemplateValidationKind kind;
  final TemplateValidationStatus status;
  final String? output;
  final String? error;
  final DateTime startedAt;
  final DateTime finishedAt;

  const TemplateValidationResult({
    required this.validationId,
    required this.label,
    required this.kind,
    required this.status,
    required this.startedAt,
    required this.finishedAt,
    this.output,
    this.error,
  });

  Duration get duration => finishedAt.difference(startedAt);
}

class TemplateRunResult {
  final String templateId;
  final String templateName;
  final bool success;
  final DateTime startedAt;
  final DateTime finishedAt;
  final List<TemplateValidationResult> validationResults;
  final String? failedStepId;
  final String? failedValidationId;
  final List<TemplateStepResult> stepResults;

  const TemplateRunResult({
    required this.templateId,
    required this.templateName,
    required this.success,
    required this.startedAt,
    required this.finishedAt,
    required this.validationResults,
    required this.stepResults,
    this.failedStepId,
    this.failedValidationId,
  });

  Duration get duration => finishedAt.difference(startedAt);

  bool get validationHasFailures =>
      validationResults.any((result) => result.status == TemplateValidationStatus.failure);

  bool get hasFailures => stepResults.any((result) => result.status == TemplateStepStatus.failure);

  List<String> get logLines => [
        ...validationResults.map((result) {
          final statusLabel = result.status.name.toUpperCase();
          final details = result.error ?? result.output ?? 'Sin salida';
          return '[VALIDATION:${result.kind.name}] ${result.label} => $statusLabel: $details';
        }),
        ...stepResults.map((result) {
        final statusLabel = result.status.name.toUpperCase();
        final details = result.error ?? result.output ?? 'Sin salida';
        return '[${result.kind.name}] ${result.title} => $statusLabel: $details';
      }),
      ].toList(growable: false);
}