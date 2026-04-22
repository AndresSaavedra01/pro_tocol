import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart'; // IMPORTANTE

class ConnectionFormDialog extends StatefulWidget {
  final String title;
  final String subtitle;
  final String buttonText;

  final String? initialHost;
  final String? initialUser;
  final String? initialPass;
  final int? initialPort;
  final String? initialKeyId;

  // Actualizamos la firma para que también pueda devolver la llave pública si se ingresa
  final void Function(
      String host,
      String username,
      String? password,
      int port,
      String? privateKey,
      String? publicKey, // NUEVO PARÁMETRO
      ) onSubmit;

  const ConnectionFormDialog({
    super.key,
    required this.title,
    required this.subtitle,
    required this.buttonText,
    required this.onSubmit,
    this.initialHost,
    this.initialUser,
    this.initialPass,
    this.initialPort,
    this.initialKeyId,
  });

  @override
  State<ConnectionFormDialog> createState() => _ConnectionFormDialogState();
}

class _ConnectionFormDialogState extends State<ConnectionFormDialog> {
  final _formKey = GlobalKey<FormState>();

  bool usePassword = true;
  bool isPasswordVisible = false;

  late TextEditingController _ipController;
  late TextEditingController _userController;
  late TextEditingController _passController;
  late TextEditingController _portController;
  late TextEditingController _privKeyController;
  late TextEditingController _pubKeyController; // Controlador para llave pública

  @override
  void initState() {
    super.initState();
    _ipController = TextEditingController(text: widget.initialHost ?? '');
    _userController = TextEditingController(text: widget.initialUser ?? '');
    _passController = TextEditingController(text: widget.initialPass ?? '');
    _portController = TextEditingController(text: (widget.initialPort ?? 22).toString());
    _privKeyController = TextEditingController();
    _pubKeyController = TextEditingController();

    if (widget.initialKeyId != null) {
      usePassword = false;
    }
  }

  // MÉTODO PARA CARGAR ARCHIVOS
  Future<void> _pickKeyFile(TextEditingController controller) async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.any, // Algunas llaves no tienen extensión .txt
      );

      if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);
        final content = await file.readAsString();
        setState(() {
          controller.text = content.trim();
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error al leer el archivo: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF161A26),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: _buildTitle(),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildField("Host / IP", _ipController, hint: "192.168.1.1"),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(flex: 3, child: _buildField("Usuario", _userController, hint: "root")),
                  const SizedBox(width: 12),
                  Expanded(flex: 2, child: _buildField("Puerto", _portController, hint: "22", isNumber: true)),
                ],
              ),
              const SizedBox(height: 20),
              _buildAuthSelector(),
              const SizedBox(height: 16),
              if (usePassword)
                _buildField("Contraseña", _passController, hint: "••••••••", isPassword: true)
              else
                widget.initialKeyId != null
                    ? _buildAlreadyHasKeyInfo()
                    : _buildKeySection(),
            ],
          ),
        ),
      ),
      actions: _buildActions(),
    );
  }

  // SECCIÓN DE LLAVES CON BOTONES DE CARGA
  Widget _buildKeySection() {
    return Column(
      children: [
        _buildKeyFieldWithPicker(
            "Llave Privada (ID_RSA / PEM)",
            _privKeyController,
            "-----BEGIN RSA PRIVATE KEY-----"
        ),
        const SizedBox(height: 16),
        _buildKeyFieldWithPicker(
            "Llave Pública (ID_RSA.PUB)",
            _pubKeyController,
            "ssh-rsa AAAA..."
        ),
      ],
    );
  }

  Widget _buildKeyFieldWithPicker(String label, TextEditingController controller, String hint) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500)),
            TextButton.icon(
              onPressed: () => _pickKeyFile(controller),
              icon: const Icon(Icons.file_open, size: 14, color: Color(0xFF7B52FF)),
              label: const Text("Cargar archivo", style: TextStyle(fontSize: 11, color: Color(0xFF7B52FF))),
              style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 0)),
            ),
          ],
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          maxLines: 3,
          style: const TextStyle(color: Colors.white, fontSize: 12, fontFamily: 'monospace'),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Colors.white24, fontSize: 11),
            filled: true,
            fillColor: const Color(0xFF1E2230),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
          ),
        ),
      ],
    );
  }

  // ... (Los demás métodos como _buildField, _authOption, etc. se mantienen igual) ...

  void _handleInternalSubmit() {
    if (_formKey.currentState!.validate()) {
      widget.onSubmit(
        _ipController.text.trim(),
        _userController.text.trim(),
        usePassword ? _passController.text : null,
        int.parse(_portController.text.trim()),
        !usePassword ? _privKeyController.text.trim() : null,
        !usePassword ? _pubKeyController.text.trim() : null, // Enviamos la pública también
      );
    }
  }

  // --- MÉTODOS DE APOYO UI ---
  Widget _buildTitle() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.title, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(widget.subtitle, style: const TextStyle(color: Colors.white60, fontSize: 13)),
      ],
    );
  }

  Widget _buildAuthSelector() {
    return Row(
      children: [
        _authOption("Contraseña", usePassword, () => setState(() => usePassword = true)),
        const SizedBox(width: 8),
        _authOption("Llave SSH", !usePassword, () => setState(() => usePassword = false)),
      ],
    );
  }

  Widget _authOption(String label, bool selected, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF7B52FF).withOpacity(0.2) : Colors.transparent,
            border: Border.all(color: selected ? const Color(0xFF7B52FF) : Colors.white10),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(label, textAlign: TextAlign.center, style: TextStyle(color: selected ? Colors.white : Colors.white38, fontSize: 12)),
        ),
      ),
    );
  }

  Widget _buildAlreadyHasKeyInfo() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.green.withOpacity(0.1), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.green.withOpacity(0.3))),
      child: const Row(
        children: [
          Icon(Icons.check_circle, color: Colors.green, size: 20),
          SizedBox(width: 8),
          Expanded(child: Text("Usando llave guardada en este dispositivo", style: TextStyle(color: Colors.green, fontSize: 12))),
        ],
      ),
    );
  }

  List<Widget> _buildActions() {
    return [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancelar", style: TextStyle(color: Colors.white54))),
      ElevatedButton(
        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF7B52FF), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
        onPressed: _handleInternalSubmit,
        child: Text(widget.buttonText, style: const TextStyle(color: Colors.white)),
      ),
    ];
  }

  Widget _buildField(String label, TextEditingController controller, {String? hint, bool isPassword = false, bool isNumber = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500)),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          obscureText: isPassword && !isPasswordVisible,
          keyboardType: isNumber ? TextInputType.number : TextInputType.text,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Colors.white24, fontSize: 13),
            filled: true,
            fillColor: const Color(0xFF1E2230),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
            suffixIcon: isPassword ? IconButton(
              icon: Icon(isPasswordVisible ? Icons.visibility : Icons.visibility_off, color: Colors.white38, size: 18),
              onPressed: () => setState(() => isPasswordVisible = !isPasswordVisible),
            ) : null,
          ),
          validator: (v) => v == null || v.isEmpty ? "Campo obligatorio" : null,
        ),
      ],
    );
  }
}