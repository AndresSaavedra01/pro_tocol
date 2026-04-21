import 'template_step.dart';

enum TemplateValidationKind {
  diskSpace,
  portFree,
  packageManagerReady,
}

class TemplateModel {
  final String id;
  final String name;
  final String description;
  final String serviceName;
  final List<String> requiredPackages;
  final List<TemplateValidationRequirement> validationRequirements;
  final List<TemplateStep> steps;

  const TemplateModel({
    required this.id,
    required this.name,
    required this.description,
    required this.serviceName,
    required this.requiredPackages,
    this.validationRequirements = const [],
    required this.steps,
  });

  bool get hasValidationSteps =>
      validationRequirements.isNotEmpty ||
      steps.any((step) => step.kind == TemplateStepKind.validation);

  bool get hasCriticalSteps => steps.any((step) => step.isCritical);
}

class TemplateValidationRequirement {
  final String id;
  final String label;
  final String description;
  final TemplateValidationKind kind;
  final bool isBlocking;
  final int? minimumFreeDiskSpaceMb;
  final int? port;
  final String? packageManager;

  const TemplateValidationRequirement({
    required this.id,
    required this.label,
    required this.description,
    required this.kind,
    this.isBlocking = true,
    this.minimumFreeDiskSpaceMb,
    this.port,
    this.packageManager,
  });
}

class TemplateDefinition {
  final TemplateModel template;
  final List<TemplateValidationRequirement> validations;

  const TemplateDefinition({
    required this.template,
    required this.validations,
  });
}