import 'template_step.dart';

class TemplateRunResult {
  final String templateId;
  final String templateName;
  final bool success;
  final DateTime startedAt;
  final DateTime finishedAt;
  final String? failedStepId;
  final List<TemplateStepResult> stepResults;

  const TemplateRunResult({
    required this.templateId,
    required this.templateName,
    required this.success,
    required this.startedAt,
    required this.finishedAt,
    required this.stepResults,
    this.failedStepId,
  });

  Duration get duration => finishedAt.difference(startedAt);

  bool get hasFailures => stepResults.any((result) => result.status == TemplateStepStatus.failure);

  List<String> get logLines => stepResults.map((result) {
        final statusLabel = result.status.name.toUpperCase();
        final details = result.error ?? result.output ?? 'Sin salida';
        return '[${result.kind.name}] ${result.title} => $statusLabel: $details';
      }).toList(growable: false);
}