import 'template_step.dart';

class TemplateModel {
  final String id;
  final String name;
  final String description;
  final String serviceName;
  final List<String> requiredPackages;
  final List<TemplateStep> steps;

  const TemplateModel({
    required this.id,
    required this.name,
    required this.description,
    required this.serviceName,
    required this.requiredPackages,
    required this.steps,
  });

  bool get hasValidationSteps =>
      steps.any((step) => step.kind == TemplateStepKind.validation);

  bool get hasCriticalSteps => steps.any((step) => step.isCritical);
}

class TemplateValidationRequirement {
  final String id;
  final String label;
  final String description;
  final bool isBlocking;

  const TemplateValidationRequirement({
    required this.id,
    required this.label,
    required this.description,
    this.isBlocking = true,
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