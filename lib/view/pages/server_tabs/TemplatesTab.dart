import 'package:flutter/material.dart';
import 'package:pro_tocol/controller/ServerController.dart';
import 'package:pro_tocol/logic/template_model.dart';
import 'package:pro_tocol/logic/template_run_result.dart';
import 'package:pro_tocol/logic/template_step.dart';
import 'package:pro_tocol/model/entities/Server.dart';

import '../../../model/entities/DataBaseEntities.dart';
import '../../theme/AppColors.dart';

class TemplatesTab extends StatefulWidget {
  final ServerConfig serverConfig;
  final ServerController serverController;
  final Server? activeServer;

  const TemplatesTab({
    super.key,
    required this.serverConfig,
    required this.serverController,
    required this.activeServer,
  });

  @override
  State<TemplatesTab> createState() => _TemplatesTabState();
}

class _TemplatesTabState extends State<TemplatesTab> {
  late final List<TemplateModel> _templates;
  TemplateModel? _selectedTemplate;
  bool _isRunning = false;
  bool _isPreparing = false;
  String? _activeValidationId;
  String? _activeStepId;
  TemplateRunResult? _lastResult;
  List<TemplateValidationResult> _validationResults = const [];
  List<TemplateStepResult> _stepResults = const [];

  @override
  void initState() {
    super.initState();
    _templates = _buildTemplates();
    _selectedTemplate = _templates.first;
  }

  List<TemplateModel> _buildTemplates() {
    return [
      TemplateModel(
        id: 'postgres',
        name: 'Postgres',
        description: 'Instala y deja listo PostgreSQL con servicio activo.',
        serviceName: 'postgresql',
        requiredPackages: const ['postgresql'],
        validationRequirements: const [
          TemplateValidationRequirement(
            id: 'disk-postgres',
            label: 'Espacio mínimo',
            description: 'Se requieren al menos 2048 MB libres para Postgres.',
            kind: TemplateValidationKind.diskSpace,
            minimumFreeDiskSpaceMb: 2048,
          ),
          TemplateValidationRequirement(
            id: 'port-postgres',
            label: 'Puerto 5432 libre',
            description: 'El puerto 5432 debe estar libre antes de arrancar Postgres.',
            kind: TemplateValidationKind.portFree,
            port: 5432,
          ),
          TemplateValidationRequirement(
            id: 'pkgmgr-postgres',
            label: 'Package manager listo',
            description: 'Debe existir el package manager detectado en el servidor.',
            kind: TemplateValidationKind.packageManagerReady,
          ),
        ],
        steps: const [
          TemplateStep(
            id: 'postgres-install',
            title: 'Instalar PostgreSQL',
            description: 'Instala el paquete principal del servicio.',
            kind: TemplateStepKind.install,
            command: r'''sudo ${packageManager} install -y postgresql''',
          ),
          TemplateStep(
            id: 'postgres-config',
            title: 'Configurar servicio',
            description: 'Genera una configuración base de ejemplo.',
            kind: TemplateStepKind.configure,
            command: r'''sh -lc "sudo mkdir -p /etc/protocol && printf '# Managed by Pro-Tocol
listen_addresses = '*'
' | sudo tee /etc/protocol/postgresql.conf >/dev/null"''',
          ),
          TemplateStep(
            id: 'postgres-start',
            title: 'Iniciar servicio',
            description: 'Activa y arranca PostgreSQL.',
            kind: TemplateStepKind.startService,
            command: 'sudo systemctl enable --now postgresql',
          ),
        ],
      ),
      TemplateModel(
        id: 'apache',
        name: 'Apache',
        description: 'Despliega Apache con configuración básica y servicio activo.',
        serviceName: 'apache',
        requiredPackages: const ['apache2', 'httpd'],
        validationRequirements: const [
          TemplateValidationRequirement(
            id: 'disk-apache',
            label: 'Espacio mínimo',
            description: 'Se requieren al menos 1024 MB libres para Apache.',
            kind: TemplateValidationKind.diskSpace,
            minimumFreeDiskSpaceMb: 1024,
          ),
          TemplateValidationRequirement(
            id: 'port-apache',
            label: 'Puerto 80 libre',
            description: 'El puerto 80 debe estar libre antes de arrancar Apache.',
            kind: TemplateValidationKind.portFree,
            port: 80,
          ),
          TemplateValidationRequirement(
            id: 'pkgmgr-apache',
            label: 'Package manager listo',
            description: 'Debe existir el package manager detectado en el servidor.',
            kind: TemplateValidationKind.packageManagerReady,
          ),
        ],
        steps: const [
          TemplateStep(
            id: 'apache-install',
            title: 'Instalar Apache',
            description: 'Instala apache2 en Debian/Ubuntu o httpd en otras distros.',
            kind: TemplateStepKind.install,
            command: r'''sh -lc "if [ "${packageManager}" = "apt" ]; then sudo apt install -y apache2; else sudo ${packageManager} install -y httpd; fi"''',
          ),
          TemplateStep(
            id: 'apache-config',
            title: 'Configurar Apache',
            description: 'Crea un archivo de configuración base.',
            kind: TemplateStepKind.configure,
            command: r'''sh -lc "if [ "${packageManager}" = "apt" ]; then printf 'ServerName localhost
' | sudo tee /etc/apache2/conf-available/protocol.conf >/dev/null && sudo a2enconf protocol; else printf 'ServerName localhost
' | sudo tee /etc/httpd/conf.d/protocol.conf >/dev/null; fi"''',
          ),
          TemplateStep(
            id: 'apache-start',
            title: 'Iniciar Apache',
            description: 'Activa y arranca el servicio web.',
            kind: TemplateStepKind.startService,
            command: r'''sh -lc "if [ "${packageManager}" = "apt" ]; then sudo systemctl enable --now apache2; else sudo systemctl enable --now httpd; fi"''',
          ),
        ],
      ),
      TemplateModel(
        id: 'docker-compose',
        name: 'Docker Compose',
        description: 'Instala Docker y despliega una definición compose de ejemplo.',
        serviceName: 'docker',
        requiredPackages: const ['docker', 'docker-compose'],
        validationRequirements: const [
          TemplateValidationRequirement(
            id: 'disk-docker',
            label: 'Espacio mínimo',
            description: 'Se requieren al menos 4096 MB libres para Docker Compose.',
            kind: TemplateValidationKind.diskSpace,
            minimumFreeDiskSpaceMb: 4096,
          ),
          TemplateValidationRequirement(
            id: 'pkgmgr-docker',
            label: 'Package manager listo',
            description: 'Debe existir el package manager detectado en el servidor.',
            kind: TemplateValidationKind.packageManagerReady,
          ),
        ],
        steps: const [
          TemplateStep(
            id: 'docker-install',
            title: 'Instalar Docker',
            description: 'Instala Docker y el soporte compose.',
            kind: TemplateStepKind.install,
            command: r'''sh -lc "if [ "${packageManager}" = "apt" ]; then sudo apt install -y docker.io docker-compose-plugin; elif [ "${packageManager}" = "pacman" ]; then sudo pacman -S --noconfirm docker docker-compose; else sudo dnf install -y docker docker-compose-plugin; fi"''',
          ),
          TemplateStep(
            id: 'docker-config',
            title: 'Configurar compose',
            description: 'Crea un docker-compose.yml de ejemplo.',
            kind: TemplateStepKind.configure,
            command: r'''sh -lc "sudo mkdir -p /opt/protocol && cat <<'EOF' | sudo tee /opt/protocol/docker-compose.yml >/dev/null
version: '3.8'
services:
  web:
    image: nginx:alpine
    ports:
      - '8080:80'
EOF"''',
          ),
          TemplateStep(
            id: 'docker-start',
            title: 'Iniciar compose',
            description: 'Levanta el stack en segundo plano.',
            kind: TemplateStepKind.startService,
            command: r'''sh -lc "cd /opt/protocol && sudo docker compose up -d"''',
          ),
        ],
      ),
    ];
  }

  Future<void> _runSelectedTemplate() async {
    final template = _selectedTemplate;
    final activeServer = widget.activeServer;
    if (template == null || activeServer == null || _isRunning) return;

    setState(() {
      _isRunning = true;
      _isPreparing = true;
      _validationResults = const [];
      _stepResults = const [];
      _lastResult = null;
      _activeValidationId = null;
      _activeStepId = null;
    });

    try {
      final result = await widget.serverController.runTemplate(
        serverId: widget.serverConfig.id,
        template: template,
        onProgress: (progress, activeValidation, activeStep) {
          if (!mounted) return;
          setState(() {
            _validationResults = progress.validationResults;
            _stepResults = progress.stepResults;
            _activeValidationId = activeValidation?.id;
            _activeStepId = activeStep?.id;
            _isPreparing = progress.validationResults.isEmpty && progress.stepResults.isEmpty;
          });
        },
      );

      if (!mounted) return;
      setState(() {
        _lastResult = result;
        _validationResults = result.validationResults;
        _stepResults = result.stepResults;
        _activeValidationId = null;
        _activeStepId = null;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error ejecutando template: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isRunning = false;
          _isPreparing = false;
        });
      }
    }
  }

  TemplateValidationStatus _validationStatus(String id) {
    if (_activeValidationId == id) return TemplateValidationStatus.running;
    final result = _validationResults.where((item) => item.validationId == id).cast<TemplateValidationResult?>().firstWhere((item) => item != null, orElse: () => null);
    return result?.status ?? TemplateValidationStatus.pending;
  }

  TemplateStepStatus _stepStatus(String id) {
    if (_activeStepId == id) return TemplateStepStatus.running;
    final result = _stepResults.where((item) => item.stepId == id).cast<TemplateStepResult?>().firstWhere((item) => item != null, orElse: () => null);
    return result?.status ?? TemplateStepStatus.pending;
  }

  @override
  Widget build(BuildContext context) {
    final activeServer = widget.activeServer;

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          color: AppColors.surface,
          child: Row(
            children: [
              const Icon(Icons.auto_awesome, color: AppColors.primary, size: 20),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Templates de despliegue',
                  style: TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ),
              if (_isRunning || _isPreparing)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (activeServer == null)
                _buildHintCard('Conecta un servidor para ejecutar templates.')
              else ...[
                _buildTemplatePicker(activeServer),
                const SizedBox(height: 14),
                _buildSummaryCard(),
                const SizedBox(height: 14),
                _buildChecklistCard(title: 'Checklist de validación', subtitle: 'Se ejecuta antes de la secuencia principal.', children: _buildValidationItems()),
                const SizedBox(height: 14),
                _buildChecklistCard(title: 'Secuencia del template', subtitle: 'La ejecución se detiene al primer fallo crítico.', children: _buildStepItems()),
                const SizedBox(height: 14),
                _buildLogCard(),
                const SizedBox(height: 14),
                ElevatedButton.icon(
                  onPressed: _isRunning ? null : _runSelectedTemplate,
                  icon: const Icon(Icons.play_arrow),
                  label: Text(_isRunning ? 'Ejecutando...' : 'Desplegar template'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.textPrimary,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTemplatePicker(Server activeServer) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Templates disponibles', style: TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          ..._templates.map((template) {
            final selected = _selectedTemplate?.id == template.id;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: _isRunning ? null : () => setState(() => _selectedTemplate = template),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: selected ? AppColors.primary.withOpacity(0.12) : AppColors.background,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: selected ? AppColors.primary : AppColors.border),
                  ),
                  child: Row(
                    children: [
                      Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off, color: selected ? AppColors.primary : AppColors.textMuted),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(template.name, style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 4),
                            Text(template.description, style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                            const SizedBox(height: 6),
                            Text('Servicio: ${template.serviceName}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
          Text('Servidor activo: ${activeServer.config.host}', style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildSummaryCard() {
    final template = _selectedTemplate;
    final totalValidations = template?.validationRequirements.length ?? 0;
    final totalSteps = template?.steps.length ?? 0;
    final doneValidations = _validationResults.where((result) => result.status != TemplateValidationStatus.pending).length;
    final doneSteps = _stepResults.where((result) => result.status != TemplateStepStatus.pending).length;
    final totalItems = totalValidations + totalSteps;
    final doneItems = doneValidations + doneSteps;
    final progress = totalItems == 0 ? 0.0 : doneItems / totalItems;
    final result = _lastResult;
    final summaryLines = result?.summaryLines ?? const <String>[];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Progreso de ejecución', style: TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          LinearProgressIndicator(value: progress, minHeight: 6, color: AppColors.primary, backgroundColor: AppColors.border),
          const SizedBox(height: 8),
          Text('${(progress * 100).toStringAsFixed(0)}% completado', style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
          const SizedBox(height: 6),
          Text('Validaciones: $doneValidations/$totalValidations • Pasos: $doneSteps/$totalSteps', style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
          if (result != null) ...[
            const SizedBox(height: 8),
            Text(
              'Validaciones OK: ${result.successfulValidationCount} • Fallidas: ${result.failedValidationCount}',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
            ),
            Text(
              'Pasos OK: ${result.successfulStepCount} • Fallidos: ${result.failedStepCount} • Omitidos: ${result.skippedStepCount}',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
            ),
            ...summaryLines.map(
              (line) => Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(line, style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildChecklistCard({required String title, required String subtitle, required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(subtitle, style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  List<Widget> _buildValidationItems() {
    final template = _selectedTemplate;
    if (template == null) return const [];

    return template.validationRequirements.map((validation) {
      final status = _validationStatus(validation.id);
      final result = _validationResults.where((item) => item.validationId == validation.id).cast<TemplateValidationResult?>().firstWhere((item) => item != null, orElse: () => null);
      final message = result?.error ?? result?.output ?? validation.description;
      return _buildStatusRow(
        title: validation.label,
        subtitle: message,
        statusLabel: _validationStatusLabel(status),
        color: _statusColor(status: status),
      );
    }).toList(growable: false);
  }

  List<Widget> _buildStepItems() {
    final template = _selectedTemplate;
    if (template == null) return const [];

    return template.steps.map((step) {
      final status = _stepStatus(step.id);
      final result = _stepResults.where((item) => item.stepId == step.id).cast<TemplateStepResult?>().firstWhere((item) => item != null, orElse: () => null);
      final message = result?.error ?? result?.output ?? step.description;
      return _buildStatusRow(
        title: step.title,
        subtitle: message,
        statusLabel: _stepStatusLabel(status),
        color: _statusColor(stepStatus: status),
      );
    }).toList(growable: false);
  }

  Widget _buildStatusRow({
    required String title,
    required String subtitle,
    required String statusLabel,
    required Color color,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(subtitle, style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(statusLabel, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _buildLogCard() {
    final result = _lastResult;
    final lines = result?.logLines ?? const <String>[];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Reporte final', style: TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          if (result == null)
            const Text('Aún no hay ejecución de template.', style: TextStyle(color: AppColors.textMuted, fontSize: 11))
          else ...[
            Text(result.success ? 'Ejecución completada con éxito.' : 'La ejecución terminó con errores.', style: TextStyle(color: result.success ? AppColors.success : AppColors.error, fontSize: 11, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text(
              'Validaciones OK: ${result.successfulValidationCount} • Fallidas: ${result.failedValidationCount}',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
            ),
            Text(
              'Pasos OK: ${result.successfulStepCount} • Fallidos: ${result.failedStepCount} • Omitidos: ${result.skippedStepCount}',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
            ),
            const SizedBox(height: 8),
            Container(
              constraints: const BoxConstraints(maxHeight: 180),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.border)),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: lines.length,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (_, index) => Text(lines[index], style: const TextStyle(color: AppColors.textMuted, fontSize: 11, height: 1.3)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHintCard(String text) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(text, style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
    );
  }

  String _validationStatusLabel(TemplateValidationStatus status) {
    switch (status) {
      case TemplateValidationStatus.running:
        return 'COMPROBANDO';
      case TemplateValidationStatus.success:
        return 'OK';
      case TemplateValidationStatus.failure:
        return 'FALLO';
      case TemplateValidationStatus.skipped:
        return 'OMITIDO';
      case TemplateValidationStatus.pending:
        return 'PENDIENTE';
    }
  }

  String _stepStatusLabel(TemplateStepStatus status) {
    switch (status) {
      case TemplateStepStatus.running:
        return 'EJECUTANDO';
      case TemplateStepStatus.success:
        return 'OK';
      case TemplateStepStatus.failure:
        return 'FALLO';
      case TemplateStepStatus.skipped:
        return 'OMITIDO';
      case TemplateStepStatus.pending:
        return 'PENDIENTE';
    }
  }

  Color _statusColor({TemplateValidationStatus? status, TemplateStepStatus? stepStatus}) {
    final effective = status?.name ?? stepStatus?.name ?? 'pending';
    switch (effective) {
      case 'running':
        return Colors.amber;
      case 'success':
        return AppColors.success;
      case 'failure':
        return AppColors.error;
      case 'skipped':
        return AppColors.textMuted;
      default:
        return AppColors.textMuted;
    }
  }
}