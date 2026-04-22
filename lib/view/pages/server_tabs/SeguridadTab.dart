import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart'; // Para descargar archivos
import 'package:pro_tocol/controller/ServerController.dart';
import 'package:pro_tocol/model/entities/DataBaseEntities.dart';
import '../../theme/AppColors.dart';

class SeguridadTab extends StatefulWidget {
  final ServerConfig serverConfig;
  final ServerController serverController;

  const SeguridadTab({
    super.key,
    required this.serverConfig,
    required this.serverController,
  });

  @override
  State<SeguridadTab> createState() => _SeguridadTabState();
}

class _SeguridadTabState extends State<SeguridadTab> {
  bool _isLoading = false;
  late ServerConfig _currentConfig; // Usamos una variable local para permitir refrescos

  @override
  void initState() {
    super.initState();
    _currentConfig = widget.serverConfig;
  }

  bool get _hasKeys =>
      _currentConfig.keyPairId != null &&
          _currentConfig.keyPairId!.isNotEmpty;

  // --- LÓGICA DE EXPORTACIÓN Y DESCARGA ---

  Future<void> _exportarLlave(bool esPublica, {bool descargar = false}) async {
    setState(() => _isLoading = true);
    try {
      final keyId = _currentConfig.keyPairId!;
      final String? keyContent;

      if (esPublica) {
        keyContent = await widget.serverController.sshKeyController.getPublicKey(keyId);
      } else {
        keyContent = await widget.serverController.sshKeyController.getPrivateKey(keyId);
      }

      if (keyContent == null) return;

      if (descargar) {
        // Opción: Descargar como archivo
        final String fileName = esPublica ? "id_rsa_server.pub" : "id_rsa_server.pem";

        String? outputFile = await FilePicker.platform.saveFile(
          dialogTitle: 'Guardar llave ${esPublica ? "Pública" : "Privada"}',
          fileName: fileName,
          bytes: Uint8List.fromList(keyContent.codeUnits),
        );

        if (outputFile != null && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('✅ Archivo guardado: $fileName'), backgroundColor: Colors.green),
          );
        }
      } else {
        // Opción: Copiar al portapapeles
        await Clipboard.setData(ClipboardData(text: keyContent));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(esPublica
                  ? '📋 Llave PÚBLICA copiada al portapapeles.'
                  : '🔐 Llave PRIVADA copiada. ¡Mantenla segura!'),
              backgroundColor: esPublica ? AppColors.primary : Colors.orange,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- LÓGICA DE GENERACIÓN ---

  Future<void> _generarLlaves() async {
    setState(() => _isLoading = true);
    try {
      // 1. Generar e instalar llaves
      await widget.serverController.upgradeServerToKeyAuth(_currentConfig.id);

      // 2. Refrescar la configuración local desde la DB para detectar que ya tiene keyPairId
      final updated = await widget.serverController.getServerConfig(_currentConfig.id);

      if (mounted && updated != null) {
        setState(() {
          _currentConfig = updated;
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Llaves generadas e instaladas con éxito.'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Error al generar llaves: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Seguridad del Servidor',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          if (_isLoading)
            const Center(child: Padding(
              padding: EdgeInsets.all(20.0),
              child: CircularProgressIndicator(color: AppColors.primary),
            ))
          else if (_hasKeys)
            _buildSecureState()
          else
            _buildUnsecureState(),
        ],
      ),
    );
  }

  Widget _buildSecureState() {
    return Column(
      children: [
        const Icon(Icons.verified_user, color: Colors.green, size: 64),
        const SizedBox(height: 16),
        const Text('Servidor Protegido', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green)),
        const SizedBox(height: 24),

        // Tarjeta para Llave Pública
        _buildKeyActionCard(
          title: "Llave Pública",
          subtitle: "Úsala para autorizar este móvil en otros servidores.",
          icon: Icons.public,
          onCopy: () => _exportarLlave(true, descargar: false),
          onDownload: () => _exportarLlave(true, descargar: true),
        ),

        const SizedBox(height: 16),

        // Tarjeta para Llave Privada
        _buildKeyActionCard(
          title: "Llave Privada",
          subtitle: "Identidad secreta del servidor. No la compartas.",
          icon: Icons.vpn_key,
          isCritical: true,
          onCopy: () => _exportarLlave(false, descargar: false),
          onDownload: () => _exportarLlave(false, descargar: true),
        ),
      ],
    );
  }

  Widget _buildKeyActionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onCopy,
    required VoidCallback onDownload,
    bool isCritical = false
  }) {
    final color = isCritical ? Colors.orange : AppColors.primary;

    return Card(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: color.withOpacity(0.3))),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              children: [
                Icon(icon, color: color),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                      Text(subtitle, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 24, color: Colors.white10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onCopy,
                    icon: const Icon(Icons.copy, size: 18),
                    label: const Text("Copiar"),
                    style: OutlinedButton.styleFrom(foregroundColor: color, side: BorderSide(color: color)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: onDownload,
                    icon: const Icon(Icons.download, size: 18),
                    label: const Text("Descargar"),
                    style: ElevatedButton.styleFrom(backgroundColor: color, foregroundColor: Colors.white),
                  ),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }

  Widget _buildUnsecureState() {
    return Card(
      color: AppColors.surface,
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 80),
            const SizedBox(height: 16),
            const Text('Acceso por Contraseña', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.orange)),
            const SizedBox(height: 12),
            const Text(
              'Este servidor no tiene llaves SSH configuradas. El acceso por contraseña es menos seguro.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textMuted),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _generarLlaves,
                icon: const Icon(Icons.security),
                label: const Text('Generar e Instalar Llaves Ahora'),
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}