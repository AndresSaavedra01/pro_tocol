import 'package:flutter/material.dart';
import 'package:pro_tocol/presentation/controllers/NavigationController.dart';
import 'home_screen.dart';
// Importamos las entidades y el controlador
import 'package:pro_tocol/entity/DataBaseEntities.dart';
import 'package:pro_tocol/presentation/controllers/ProfileController.dart';

class ProfileScreen extends StatefulWidget {
  // 1. Pedimos el controlador por constructor
  final ProfileController controller;

  const ProfileScreen({super.key, required this.controller, required NavigationController navigationController});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  // Ya no necesitamos la lista _perfiles, usamos la del controlador
  final TextEditingController _nameController = TextEditingController();

  // 2. Función para agregar perfil usando el controlador y la BD
  Future<void> _addProfile() async {
    if (_nameController.text.isNotEmpty && widget.controller.allProfiles.length < 4) {
      // Llamamos al método que guarda en Isar
      await widget.controller.createProfile(_nameController.text);

      _nameController.clear();
      if (mounted) {
        Navigator.pop(context); // Cerramos el diálogo
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    double cardWidth = (MediaQuery.of(context).size.width / 2) - 40;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF1B2430),
              Color(0xFF000000),
            ],
          ),
        ),
        child: SafeArea(
          child: SizedBox(
            width: double.infinity,
            // 3. El ListenableBuilder escucha al controlador y redibuja cuando hay cambios
            child: ListenableBuilder(
                listenable: widget.controller,
                builder: (context, child) {
                  // Obtenemos los perfiles reales de la base de datos
                  final perfilesExistentes = widget.controller.allProfiles;

                  return Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        '¿ Quien esta ?',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Selecciona o crea tu perfil',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 40),

                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Wrap(
                          spacing: 20,
                          runSpacing: 20,
                          alignment: WrapAlignment.center,
                          children: [
                            // 4. Mapeamos los perfiles reales (objetos Profile)
                            ...perfilesExistentes.map((perfil) => _buildProfileCard(perfil, cardWidth)),

                            // Botón Nuevo perfil (Solo si hay menos de 4 en la BD)
                            if (perfilesExistentes.length < 4)
                              GestureDetector(
                                onTap: () => _showCreateProfileDialog(context),
                                child: Container(
                                  width: cardWidth,
                                  height: 140,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF282A36).withOpacity(0.5),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: Colors.white10),
                                  ),
                                  child: const Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.add, color: Colors.white54, size: 48),
                                      SizedBox(height: 8),
                                      Text(
                                        'Nuevo perfil',
                                        style: TextStyle(color: Colors.white, fontSize: 14),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  );
                }
            ),
          ),
        ),
      ),
    );
  }

  // 5. Ajustamos para que reciba el objeto Profile completo
  Widget _buildProfileCard(Profile perfil, double width) {
    return GestureDetector(
      onTap: () {
        // Marcamos este perfil como activo en el controlador antes de ir al Home
        widget.controller.setActiveProfile(perfil);

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => HomeScreen(profileName: perfil.profileName),
          ),
        );
      },
      child: Container(
        width: width,
        height: 140,
        decoration: BoxDecoration(
          color: const Color(0xFF8B63FF).withOpacity(0.15),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: const Color(0xFF8B63FF).withOpacity(0.5),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircleAvatar(
              radius: 30,
              backgroundColor: Color(0xFF8B63FF),
              child: Icon(Icons.person, color: Colors.white, size: 35),
            ),
            const SizedBox(height: 12),
            Text(
              perfil.profileName,
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  void _showCreateProfileDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: const Color(0xFFFEF7F7),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Crear Nuevo Perfil',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black87),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _nameController,
                style: const TextStyle(color: Colors.black),
                decoration: InputDecoration(
                  hintText: 'Nombre del Perfil',
                  filled: true,
                  fillColor: Colors.grey[200],
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 25),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF8B63FF),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: _addProfile,
                      child: const Text('Crear'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}