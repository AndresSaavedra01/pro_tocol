
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pro_tocol/injection.dart';
import 'package:pro_tocol/model/entities/DataBaseEntities.dart';
import 'package:pro_tocol/model/repositories/AiConfigRepository.dart';
import 'package:pro_tocol/model/services/ia_service.dart';
import 'package:pro_tocol/view/theme/AppColors.dart';

class AiSettingsPage extends StatefulWidget {
  const AiSettingsPage({super.key});

  @override
  State<AiSettingsPage> createState() => _AiSettingsPageState();
}

class _AiSettingsPageState extends State<AiSettingsPage> {
  static const String _providerOllama = 'ollama';
  static const String _providerGroq = 'groq';
  static const String _personalityTatiana = 'tatiana';
  static const String _personalityIberlina = 'iberlina';
  static const String _personalityYousua = 'yousua';

  final _formKey = GlobalKey<FormState>();

  final TextEditingController _hostController = TextEditingController();
  final TextEditingController _portController = TextEditingController();
  final TextEditingController _tokenController = TextEditingController();

  String _provider = _providerOllama;
  String _personality = _personalityTatiana;
  List<String> _models = [];
  String? _selectedModel;

  bool _isLoading = true;
  bool _isTesting = false;
  bool _connectionOk = false;
  bool _tokenDirty = false;

  AiConfig? _config;

  AiConfigRepository get _configRepository => getIt<AiConfigRepository>();
  IAService get _iaService => getIt<IAService>();

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  Future<void> _loadConfig() async {
    final config = await _configRepository.getConfig();
    final token = await _configRepository.getToken();

    _config = config ?? AiConfig();
    _provider = _config!.provider.isEmpty ? _providerOllama : _config!.provider;
    _personality = _config!.iaPersonality.isEmpty
      ? _personalityTatiana
      : _config!.iaPersonality;
    _hostController.text = _config!.host;
    _portController.text = _config!.port.toString();
    _selectedModel = _config!.model.isEmpty ? null : _config!.model;
    _tokenController.text = token ?? '';
    _tokenDirty = false;

    _applyProviderDefaults(force: false);

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _persistConfig() async {
    final config = _config ?? AiConfig();
    config.provider = _provider;
    config.iaPersonality = _personality;
    config.host = _hostController.text.trim();
    config.port = int.tryParse(_portController.text.trim()) ?? config.port;
    config.model = _selectedModel ?? '';

    await _configRepository.saveConfig(config);
    _config = config;

    if (_tokenDirty) {
      final token = _tokenController.text.trim();
      if (token.isEmpty) {
        await _configRepository.clearToken();
      } else {
        await _configRepository.saveToken(token);
      }
      _tokenDirty = false;
    }
  }

  Future<void> _testConnection() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isTesting = true;
      _connectionOk = false;
    });

    try {
      await _persistConfig();
      await _iaService.testConnection();

      final models = await _iaService.fetchModels();
      if (mounted) {
        setState(() {
          _models = models;
          if (_models.isNotEmpty) {
            _selectedModel = _models.contains(_selectedModel) ? _selectedModel : _models.first;
          } else {
            _selectedModel = null;
          }
          _connectionOk = true;
        });
      }

      await _persistConfig();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Conexion exitosa.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error de conexion: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isTesting = false;
        });
      }
    }
  }

  void _applyProviderDefaults({required bool force}) {
    if (_provider == _providerGroq) {
      if (force || _hostController.text.trim().isEmpty || _hostController.text.trim() == '127.0.0.1') {
        _hostController.text = 'api.groq.com';
      }
      if (force || _portController.text.trim().isEmpty || _portController.text.trim() == '11434') {
        _portController.text = '443';
      }
    } else {
      if (force || _hostController.text.trim().isEmpty || _hostController.text.trim() == 'api.groq.com') {
        _hostController.text = '127.0.0.1';
      }
      if (force || _portController.text.trim().isEmpty || _portController.text.trim() == '443') {
        _portController.text = '11434';
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: const Text('Configuracion IA', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: Container(
        decoration: AppTheme.mainBackground,
        child: SafeArea(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: SizedBox(
                    width: double.maxFinite,
                    child: Form(
                      key: _formKey,
                    child: Container(
                      padding: const EdgeInsets.all(18),
                      decoration: AppTheme.glassCard,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildSectionTitle('Proveedor'),
                          _buildProviderDropdown(),
                          const SizedBox(height: 16),
                          _buildSectionTitle('Asistente IA'),
                          _buildPersonalityDropdown(),
                          const SizedBox(height: 16),
                          _buildSectionTitle('Conexion'),
                          Row(
                            children: [
                              Expanded(
                                child: _buildTextField(
                                  label: 'Host / IP',
                                  controller: _hostController,
                                  validator: _validateHost,
                                ),
                              ),
                              const SizedBox(width: 12),
                              SizedBox(
                                width: 110,
                                child: _buildTextField(
                                  label: 'Puerto',
                                  controller: _portController,
                                  validator: _validatePort,
                                  keyboardType: TextInputType.number,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          _buildSectionTitle('Token / API Key'),
                          _buildTokenField(),
                          const SizedBox(height: 16),
                          _buildSectionTitle('Modelo'),
                          _buildModelDropdown(),
                          if (_models.isEmpty)
                            const Padding(
                              padding: EdgeInsets.only(top: 8),
                              child: Text(
                                'Probar conexion para cargar modelos.',
                                style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                              ),
                            ),
                          const SizedBox(height: 20),
                          _buildTestButtonRow(),
                        ],
                      ),
                    ),
                  ),
                ),
                ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Text(
        title,
        style: const TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _buildProviderDropdown() {
    return DropdownButtonFormField<String>(
      isExpanded: true,
      value: _provider,
      items: const [
        DropdownMenuItem(value: _providerOllama, child: Text('Ollama', maxLines: 1, overflow: TextOverflow.ellipsis)),
        DropdownMenuItem(value: _providerGroq, child: Text('Groq', maxLines: 1, overflow: TextOverflow.ellipsis)),
      ],
      onChanged: (value) {
        if (value == null) return;
        setState(() {
          _provider = value;
          _models = [];
          _selectedModel = null;
          _connectionOk = false;
        });
        _applyProviderDefaults(force: true);
      },
      decoration: _darkInputDecoration('Proveedor'),
      dropdownColor: AppColors.surface,
      style: const TextStyle(color: AppColors.textPrimary),
    );
  }

  Widget _buildPersonalityDropdown() {
    return DropdownButtonFormField<String>(
      isExpanded: true,
      value: _personality,
      items: const [
        DropdownMenuItem(
          value: _personalityTatiana,
          child: Text('Tatiana — Asistente General', maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        DropdownMenuItem(
          value: _personalityIberlina,
          child: Text('Iberlina — Seguridad & Hardening', maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        DropdownMenuItem(
          value: _personalityYousua,
          child: Text('Yousua — Automatizacion & Scripts', maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ],
      onChanged: (value) async {
        if (value == null) return;
        setState(() {
          _personality = value;
        });
        await _persistConfig();
      },
      decoration: _darkInputDecoration('Asistente IA'),
      dropdownColor: AppColors.surface,
      style: const TextStyle(color: AppColors.textPrimary),
    );
  }

  Widget _buildModelDropdown() {
    return DropdownButtonFormField<String>(
      isExpanded: true,
      value: _models.contains(_selectedModel) ? _selectedModel : null,
      items: _models
          .map((model) => DropdownMenuItem(value: model, child: Text(model, maxLines: 1, overflow: TextOverflow.ellipsis)))
          .toList(),
      onChanged: _models.isEmpty
          ? null
          : (value) async {
              setState(() {
                _selectedModel = value;
              });
              await _persistConfig();
            },
      validator: (value) {
        if (_models.isNotEmpty && value == null) {
          return 'Selecciona un modelo.';
        }
        return null;
      },
      decoration: _darkInputDecoration('Modelo disponible'),
      dropdownColor: AppColors.surface,
      style: const TextStyle(color: AppColors.textPrimary),
    );
  }

  Widget _buildTokenField() {
    return TextFormField(
      controller: _tokenController,
      obscureText: true,
      autocorrect: false,
      enableSuggestions: false,
      onChanged: (_) => _tokenDirty = true,
      validator: _validateToken,
      decoration: _darkInputDecoration('Token o API Key'),
      style: const TextStyle(color: AppColors.textPrimary),
    );
  }

  Widget _buildTextField({
    required String label,
    required TextEditingController controller,
    required String? Function(String?) validator,
    TextInputType? keyboardType,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      validator: validator,
      style: const TextStyle(color: AppColors.textPrimary),
      decoration: _darkInputDecoration(label),
    );
  }

  Widget _buildTestButtonRow() {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            onPressed: _isTesting ? null : _testConnection,
            icon: _isTesting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                  )
                : const Icon(Icons.wifi_tethering, color: Colors.white),
            label: Text(
              _isTesting ? 'Probando...' : 'Probar conexion',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Icon(
          _connectionOk ? Icons.check_circle : Icons.cancel_outlined,
          color: _connectionOk ? AppColors.success : AppColors.textMuted,
        ),
      ],
    );
  }

  InputDecoration _darkInputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: AppColors.textMuted),
      filled: true,
      fillColor: AppColors.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.primary),
      ),
    );
  }

  String? _validateHost(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Host requerido.';
    }
    return null;
  }

  String? _validatePort(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Puerto requerido.';
    }
    final port = int.tryParse(value.trim());
    if (port == null || port <= 0 || port > 65535) {
      return 'Puerto invalido.';
    }
    return null;
  }

  String? _validateToken(String? value) {
    final token = value?.trim() ?? '';
    if (token.isEmpty) return null;
    if (token.length < 16) {
      return 'Token invalido.';
    }
    return null;
  }
}
