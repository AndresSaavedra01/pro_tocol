import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // NECESARIO PARA EL PORTAPAPELES
import 'package:path_provider/path_provider.dart';
import 'package:pro_tocol/injection.dart';
import 'package:pro_tocol/model/entities/DataBaseEntities.dart';
import 'package:pro_tocol/controller/KeyController.dart';
import 'package:pro_tocol/view/theme/AppColors.dart';

class SeguridadTab extends StatefulWidget {
  final ServerConfig serverConfig;

  const SeguridadTab({super.key, required this.serverConfig});

  @override
  State<SeguridadTab> createState() => _SeguridadTabState();
}

class _SeguridadTabState extends State<SeguridadTab> with AutomaticKeepAliveClientMixin {
  final KeyController _keyController = getIt<KeyController>();
  final TextEditingController _passwordController = TextEditingController();

  PairKeys? _currentKeyPair;
  bool _isLoading = false;
  bool _isKeyAssociated = false;

  // ESTO PREVIENE QUE EL TAB SE REINICIE AL CAMBIAR DE PESTAÑA
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _checkExistingKeys();
  }

  /// Carga inicial del estado de llaves del servidor desde Isar
  Future<void> _checkExistingKeys() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final isar = _keyController.isar;

      // Buscamos la instancia fresca del servidor administrado por Isar
      final managedServer = await isar.collection<ServerConfig>().get(widget.serverConfig.id);

      if (managedServer != null) {
        await managedServer.keyPair.load();
        if (mounted) {
          setState(() {
            _currentKeyPair = managedServer.keyPair.value;
            // Si tiene llave asignada en la base de datos, está asociada
            _isKeyAssociated = _currentKeyPair != null;
          });
        }
      }
    } catch (e) {
      debugPrint('Error al cargar llaves desde Isar: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// Genera un par de llaves localmente
  Future<void> _generarLlaves() async {
    setState(() => _isLoading = true);
    try {
      final name = 'Key-${widget.serverConfig.host}';
      final newKey = await _keyController.generateKeyPair(name);

      setState(() {
        _currentKeyPair = newKey;
        _isKeyAssociated = false; // Aún falta asociarla al servidor físico
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Par de llaves RSA generado exitosamente.')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al generar llaves: $e')),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  /// Muestra el modal para ingresar clave SSH e instalar la llave pública
  Future<void> _mostrarDialogoAsociacion() async {
    _passwordController.clear();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.background,
        title: const Text('Asociar Llave al Servidor', style: TextStyle(color: AppColors.textPrimary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Se instalará la llave pública en el servidor remoto. Ingresa la contraseña actual de SSH para autorizar esta operación:',
              style: TextStyle(color: AppColors.textMuted),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _passwordController,
              obscureText: true,
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: const InputDecoration(
                labelText: 'Contraseña SSH Actual',
                labelStyle: TextStyle(color: AppColors.textMuted),
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppColors.textMuted)),
                focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppColors.primary)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar', style: TextStyle(color: AppColors.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: () async {
              final password = _passwordController.text.trim();
              if (password.isEmpty) return;

              Navigator.pop(context);
              setState(() => _isLoading = true);

              try {
                if (_currentKeyPair == null) return;

                final exito = await _keyController.associateKeyToServer(
                  _currentKeyPair!,
                  widget.serverConfig,
                  password,
                );

                if (exito) {
                  await _checkExistingKeys(); // Refrescar estado completo desde Isar
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Llave pública asociada e instalada correctamente.')),
                  );
                }
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Error al asociar llave: $e')),
                );
              } finally {
                setState(() => _isLoading = false);
              }
            },
            child: const Text('Confirmar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  /// Elimina las llaves de la base de datos local y rompe el vínculo
  Future<void> _eliminarLlaves() async {
    if (_currentKeyPair == null) return;

    setState(() => _isLoading = true);
    try {
      await _keyController.deleteKeyPairFromServer(widget.serverConfig, _currentKeyPair!);
      setState(() {
        _currentKeyPair = null;
        _isKeyAssociated = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Llaves eliminadas correctamente.')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al eliminar llaves: $e')),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  /// Copia el texto pasado al portapapeles y muestra un mensaje
  void _copiarAlPortapapeles(String texto, String mensajeExito) {
    Clipboard.setData(ClipboardData(text: texto));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(mensajeExito)),
    );
  }

  @override
  Widget build(BuildContext context) {
    // REQUERIDO POR AutomaticKeepAliveClientMixin
    super.build(context);

    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation(AppColors.primary)),
      );
    }

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Seguridad del Servidor',
              style: TextStyle(color: AppColors.textPrimary, fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Administra la autenticación mediante claves SSH para evitar el uso de contraseñas en texto plano.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 14),
            ),
            const SizedBox(height: 24),

            if (_currentKeyPair == null) ...[
              // ESTADO 1: Sin llaves generadas
              Card(
                color: AppColors.surface,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    children: [
                      const Icon(Icons.vpn_key_outlined, size: 48, color: AppColors.textMuted),
                      const SizedBox(height: 16),
                      const Text(
                        'Autenticación por Llaves Desactivada',
                        style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Este servidor actualmente no tiene llaves SSH configuradas localmente en la aplicación.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: _generarLlaves,
                        icon: const Icon(Icons.add, color: Colors.white),
                        label: const Text('Generar Par de Llaves', style: TextStyle(color: Colors.white)),
                      ),
                    ],
                  ),
                ),
              ),
            ] else ...[
              // ESTADO 2: Llaves existentes o recién generadas
              Card(
                color: AppColors.surface,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            _isKeyAssociated ? Icons.verified_user : Icons.gpp_maybe,
                            color: _isKeyAssociated ? AppColors.success : Colors.amber,
                            size: 28,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _currentKeyPair!.name,
                                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.bold),
                                ),
                                Text(
                                  _isKeyAssociated ? 'Asociada y activa en el servidor' : 'Generada localmente (Sin asociar al servidor remoto)',
                                  style: TextStyle(
                                    color: _isKeyAssociated ? AppColors.success : Colors.amber,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const Divider(color: Colors.white10, height: 24),

                      // LLAVE PÚBLICA CON BOTÓN COPIAR
                      const Text('Llave Pública (OpenSSH):', style: TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.only(left: 10, top: 2, bottom: 2, right: 2),
                        decoration: BoxDecoration(
                          color: Colors.black26,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                _currentKeyPair!.publicKeyOpenSsh.isNotEmpty
                                    ? _currentKeyPair!.publicKeyOpenSsh
                                    : 'Llave importada / Contenido privado',
                                style: const TextStyle(color: AppColors.textMuted, fontSize: 11, fontFamily: 'monospace'),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.copy, color: AppColors.primary, size: 20),
                              tooltip: 'Copiar llave pública',
                              onPressed: () => _copiarAlPortapapeles(_currentKeyPair!.publicKeyOpenSsh, 'Llave pública copiada'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // LLAVE PRIVADA CON BOTÓN COPIAR (Oculta por defecto en UI)
                      const Text('Llave Privada (RSA):', style: TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.only(left: 10, top: 2, bottom: 2, right: 2),
                        decoration: BoxDecoration(
                          color: Colors.black26,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          children: [
                            const Expanded(
                              child: Text(
                                '••••••••••••••••••••••••••••••••••••••••••••••',
                                style: TextStyle(color: AppColors.textMuted, fontSize: 11, fontFamily: 'monospace', letterSpacing: 2),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.copy, color: AppColors.primary, size: 20),
                              tooltip: 'Copiar llave privada',
                              onPressed: () => _copiarAlPortapapeles(_currentKeyPair!.privateKeyPem, 'Llave privada copiada al portapapeles. ¡Mantenla segura!'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Panel Operacional
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (!_isKeyAssociated) ...[
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo[800]),
                      onPressed: _mostrarDialogoAsociacion,
                      icon: const Icon(Icons.cloud_upload, color: Colors.white),
                      label: const Text('Asociar al Servidor', style: TextStyle(color: Colors.white)),
                    ),
                    const SizedBox(width: 12),
                  ],
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red[900]),
                    onPressed: _eliminarLlaves,
                    icon: const Icon(Icons.delete_forever, color: Colors.white),
                    label: const Text('Eliminar Llaves', style: TextStyle(color: Colors.white)),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }
}