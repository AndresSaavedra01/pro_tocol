import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pro_tocol/model/entities/Profile.dart';
import 'package:pro_tocol/controller/ProfileController.dart';
import 'package:pro_tocol/injection.dart';
import 'package:pro_tocol/view/theme/AppColors.dart';

class UserProfileTab extends StatefulWidget {
  final Profile profile;

  const UserProfileTab({super.key, required this.profile});

  @override
  State<UserProfileTab> createState() => _UserProfileTabState();
}

class _UserProfileTabState extends State<UserProfileTab> {
  final _profileController = getIt<ProfileController>();
  late TextEditingController _nameController;
  bool _notificationsEnabled = true;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.profile.profileName);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.background,
      width: double.infinity,
      height: double.infinity,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            // Sección del Avatar
            Center(
              child: CircleAvatar(
                radius: 55,
                backgroundColor: AppColors.primary.withOpacity(0.2),
                child: Text(
                  _nameController.text.isNotEmpty ? _nameController.text[0].toUpperCase() : 'U',
                  style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold, color: AppColors.primary),
                ),
              ),
            ),
            const SizedBox(height: 32),

            // Campo de Nombre
            TextField(
              controller: _nameController,
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: InputDecoration(
                labelText: 'Nombre del Perfil',
                labelStyle: const TextStyle(color: AppColors.textSecondary),
                filled: true,
                fillColor: AppColors.surface,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                prefixIcon: const Icon(Icons.person, color: AppColors.textMuted),
              ),
              onChanged: (value) => setState(() {}),
            ),
            const SizedBox(height: 24),

            // Sección de Preferencias
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Preferencias', 
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: AppColors.surface, 
                borderRadius: BorderRadius.circular(12),
              ),
              child: SwitchListTile(
                title: const Text('Notificaciones', style: TextStyle(color: AppColors.textPrimary)),
                activeColor: AppColors.primary,
                value: _notificationsEnabled,
                onChanged: (value) => setState(() => _notificationsEnabled = value),
              ),
            ),
            const SizedBox(height: 40),

            // Botón de Cerrar Sesión General
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
                side: const BorderSide(color: AppColors.error),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.exit_to_app, color: AppColors.error),
              label: const Text('Cerrar Sesión', style: TextStyle(color: AppColors.error, fontSize: 16)),
              onPressed: () => _mostrarDialogoCerrarSesion(context),
            ),
          ],
        ),
      ),
    );
  }

  void _mostrarDialogoCerrarSesion(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('¿Cerrar sesión?', style: TextStyle(color: AppColors.textPrimary)),
        content: const Text(
          'Saldrás de Pro-Tocol y volverás a la pantalla de inicio.', 
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar', style: TextStyle(color: AppColors.textMuted)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext); // Cierra el diálogo de inmediato
              await _profileController.signOut(); // Limpia la sesión en el repositorio
              if (mounted) {
                context.go('/'); // Te redirige al login usando el contexto principal
              }
            },
            child: const Text('Cerrar Sesión', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
  }
}