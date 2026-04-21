enum TemplateStepKind {
  validation,
  install,
  configure,
  startService,
}

enum TemplateStepStatus {
  pending,
  running,
  success,
  failure,
  skipped,
}

class TemplateStep {
  final String id;
  final String title;
  final String description;
  final TemplateStepKind kind;
  final String? command;
  final bool isCritical;

  const TemplateStep({
    required this.id,
    required this.title,
    required this.description,
    required this.kind,
    this.command,
    this.isCritical = true,
  });
}

class TemplateStepResult {
  final String stepId;
  final String title;
  final TemplateStepKind kind;
  final TemplateStepStatus status;
  final String? output;
  final String? error;
  final DateTime startedAt;
  final DateTime finishedAt;

  const TemplateStepResult({
    required this.stepId,
    required this.title,
    required this.kind,
    required this.status,
    required this.startedAt,
    required this.finishedAt,
    this.output,
    this.error,
  });

  Duration get duration => finishedAt.difference(startedAt);
}