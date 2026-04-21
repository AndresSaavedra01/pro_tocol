import 'package:flutter/material.dart';

class CustomSidebar extends StatelessWidget {
  final String currentServer;
  final Function(String name, String info, bool isTemp) onNavigate;

  const CustomSidebar({
    super.key,
    required this.currentServer,
    required this.onNavigate,
  });

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: const Color(0xFF041614),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(context),
            const Divider(color: Colors.white10),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  _buildSection(
                    title: 'Servidores',
                    icon: Icons.storage_outlined,
                    items: [
                      _buildItem(
                        title: 'Servidor Principal',
                        hasStatus: true,
                        isActive: currentServer == 'Servidor Principal',
                        onTap: () => onNavigate('Servidor Principal', '192.168.1.10', false),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _buildSection(
                    title: 'Sesiones Temporales',
                    icon: Icons.access_time,
                    items: [
                      _buildItem(
                        title: 'Sesión de Prueba',
                        subtitle: 'En uso',
                        isActive: currentServer == 'Sesión de Prueba',
                        onTap: () => onNavigate('Sesión de Prueba', '10.0.0.5', true),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('Menú', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white54),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget _buildSection({required String title, required IconData icon, required List<Widget> items}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: Colors.white54, size: 18),
            const SizedBox(width: 8),
            Text(title, style: const TextStyle(color: Colors.white54, fontSize: 14, fontWeight: FontWeight.w600)),
          ],
        ),
        const SizedBox(height: 12),
        ...items,
      ],
    );
  }

  Widget _buildItem({required String title, String? subtitle, bool hasStatus = false, bool isActive = false, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFF8B63FF).withOpacity(0.1) : const Color(0xFF1E1E26),
          borderRadius: BorderRadius.circular(12),
          border: isActive ? Border.all(color: const Color(0xFF8B63FF), width: 1) : null,
        ),
        child: Row(
          children: [
            if (hasStatus) ...[
              const CircleAvatar(radius: 4, backgroundColor: Colors.greenAccent),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(color: isActive ? Colors.white : Colors.white70, fontWeight: FontWeight.bold)),
                  if (subtitle != null) Text(subtitle, style: const TextStyle(color: Colors.white38, fontSize: 12)),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios, color: Colors.white24, size: 12),
          ],
        ),
      ),
    );
  }
}