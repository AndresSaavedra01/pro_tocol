import 'dart:math';
import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';
import 'package:fl_chart/fl_chart.dart';
import '../widgets/custom_sidebar.dart';
import '../entity/FileNode.dart'; 

class ServerScreen extends StatefulWidget {
  final String serverName;
  final String connectionInfo;
  final bool isTemporarySession;

  const ServerScreen({
    super.key,
    required this.serverName,
    required this.connectionInfo,
    required this.isTemporarySession,
  });

  @override
  State<ServerScreen> createState() => _ServerScreenState();
}

class _ServerScreenState extends State<ServerScreen> {
  late final Terminal terminal;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  // --- VARIABLES PARA EL CONTROLADOR ---
  // Gráficos
  List<FlSpot> cpuPoints = [const FlSpot(0, 0)];
  List<FlSpot> ramPoints = [const FlSpot(0, 0)];
  
  // Explorador de Archivos
  String currentPath = "/";
  List<FileNode> currentFiles = [];

  @override
  void initState() {
    super.initState();
    terminal = Terminal();
    _initTerminal();
    
    // Datos de prueba para que veas el explorador funcionando apenas abras la pantalla
    // (Tu controlador luego actualizará esto)
    currentFiles = [
      FileNode(name: "home", path: "/home", type: FileType.directory, sizeInBytes: 0, permissions: "drwxr-xr-x", lastModified: DateTime.now()),
      FileNode(name: "var", path: "/var", type: FileType.directory, sizeInBytes: 0, permissions: "drwxr-xr-x", lastModified: DateTime.now()),
      FileNode(name: "script.sh", path: "/script.sh", type: FileType.unknown, sizeInBytes: 856, permissions: "-rwxr-xr-x", lastModified: DateTime.now()),
    ];
  }

  void _initTerminal() {
    terminal.write('Conectando a ${widget.connectionInfo}...\r\n');
    terminal.write('\x1B[32mConexión establecida.\x1B[0m\r\n');
    terminal.write('\x1B[32m${widget.connectionInfo}:~\$\x1B[0m ');
  }

  // --- MÉTODOS PÚBLICOS PARA EL FUTURO CONTROLADOR ---

  // Para actualizar los gráficos
  void updateCharts(double x, double cpu, double ram) {
    setState(() {
      cpuPoints.add(FlSpot(x, cpu));
      ramPoints.add(FlSpot(x, ram));
      if (cpuPoints.length > 15) {
        cpuPoints.removeAt(0);
        ramPoints.removeAt(0);
      }
    });
  }

  // Para actualizar la vista de archivos
  void updateFileSystem(String path, List<FileNode> files) {
    setState(() {
      currentPath = path;
      currentFiles = files;
    });
  }


  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: const Color(0xFF0F1319),
        appBar: AppBar(
          backgroundColor: const Color(0xFF1B2430),
          elevation: 0,
          title: Column(
            children: [
              Text(widget.serverName, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              Text(widget.connectionInfo, style: const TextStyle(color: Colors.white54, fontSize: 12)),
            ],
          ),
          centerTitle: true,
          bottom: widget.isTemporarySession
              ? null
              : const TabBar(
                  indicatorColor: Color(0xFF8B63FF),
                  labelColor: Colors.white,
                  tabs: [Tab(text: 'Estado'), Tab(text: 'Terminal'), Tab(text: 'Archivos')],
                ),
        ),
        body: widget.isTemporarySession
            ? _buildTerminalTab()
            : TabBarView(
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _buildEstadoTab(),
                  _buildTerminalTab(),
                  _buildArchivosTab(),
                ],
              ),
      ),
    );
  }

  //  LOGICA DE NAVEGACION ENTRE SERVIDORES 
  void _handleNavigation(String name, String info, bool isTemp) {
    Navigator.pop(context);
    if (widget.serverName == name) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => ServerScreen(
          serverName: name,
          connectionInfo: info,
          isTemporarySession: isTemp,
        ),
      ),
    );
  }

  // PESTAÑA 1: ESTADO
  Widget _buildEstadoTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: _buildStatCard("CPU", "${cpuPoints.last.y.toInt()}%", Colors.blue, Icons.memory, cpuPoints.last.y / 100)),
              const SizedBox(width: 12),
              Expanded(child: _buildStatCard("RAM", "${ramPoints.last.y.toInt()}%", Colors.purple, Icons.storage, ramPoints.last.y / 100)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _buildSimpleCard("Uptime", "0h 0m", Colors.green, Icons.speed)),
              const SizedBox(width: 12),
              Expanded(child: _buildSimpleCard("Estado", "Online", Colors.teal, Icons.dns, showDot: true)),
            ],
          ),
          const SizedBox(height: 20),
          _buildGraphContainer("Uso de CPU", Colors.blue, cpuPoints),
          const SizedBox(height: 20),
          _buildGraphContainer("Uso de RAM", Colors.purple, ramPoints),
        ],
      ),
    );
  }

  Widget _buildStatCard(String title, String val, Color col, IconData ic, double progress) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: const Color(0xFF1B2430), borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [Icon(ic, color: col, size: 16), const SizedBox(width: 8), Text(title, style: const TextStyle(color: Colors.white54, fontSize: 12))]),
          const SizedBox(height: 12),
          Text(val, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          LinearProgressIndicator(value: progress.clamp(0.0, 1.0), backgroundColor: Colors.white10, color: col, minHeight: 4),
        ],
      ),
    );
  }

  Widget _buildSimpleCard(String title, String val, Color col, IconData ic, {bool showDot = false}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: const Color(0xFF1B2430), borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [Icon(ic, color: col, size: 16), const SizedBox(width: 8), Text(title, style: const TextStyle(color: Colors.white54, fontSize: 12))]),
          const SizedBox(height: 12),
          Row(children: [
            if (showDot) const Padding(padding: EdgeInsets.only(right: 8), child: CircleAvatar(radius: 4, backgroundColor: Colors.greenAccent)),
            Text(val, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
          ]),
        ],
      ),
    );
  }

  Widget _buildGraphContainer(String title, Color col, List<FlSpot> points) {
    return Container(
      height: 250,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: const Color(0xFF1B2430), borderRadius: BorderRadius.circular(20)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          Expanded(
            child: LineChart(
              LineChartData(
                gridData: FlGridData(show: true, drawVerticalLine: false, getDrawingHorizontalLine: (v) => FlLine(color: Colors.white10, strokeWidth: 1)),
                titlesData: const FlTitlesData(show: false),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: points,
                    isCurved: true,
                    color: col,
                    barWidth: 3,
                    dotData: const FlDotData(show: true),
                    belowBarData: BarAreaData(show: true, color: col.withOpacity(0.1)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // PESTAÑA 2: TERMINAL
  Widget _buildTerminalTab() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Container(
        decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white10)),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: const BoxDecoration(color: Color(0xFF1B2430), borderRadius: BorderRadius.only(topLeft: Radius.circular(12), topRight: Radius.circular(12))),
              child: Row(children: [const Icon(Icons.code, color: Colors.greenAccent, size: 14), const SizedBox(width: 8), Text(widget.connectionInfo, style: const TextStyle(color: Colors.white54, fontSize: 12))]),
            ),
            Expanded(child: Padding(padding: const EdgeInsets.all(8.0), child: ClipRRect(borderRadius: BorderRadius.circular(8), child: TerminalView(terminal)))),
          ],
        ),
      ),
    );
  }

  // PESTAÑA 3: ARCHIVOS
  Widget _buildArchivosTab() {
    return Column(
      children: [
        // Barra de ruta 
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          color: const Color(0xFF0F1319),
          child: Row(
            children: [
              const Icon(Icons.home_outlined, color: Colors.white70, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  currentPath,
                  style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: Colors.white10),
        
        // Lista de carpetas y archivos
        Expanded(
          child: currentFiles.isEmpty
              ? const Center(child: Text("Carpeta vacía o esperando datos...", style: TextStyle(color: Colors.white54)))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: currentFiles.length,
                  itemBuilder: (context, index) {
                    return _buildFileNodeItem(currentFiles[index]);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildFileNodeItem(FileNode node) {
    final isDir = node.isDirectory;
    IconData nodeIcon = Icons.insert_drive_file;
    Color iconColor = Colors.white54;
    
    if (isDir) {
      nodeIcon = Icons.folder_outlined;
      iconColor = Colors.blueAccent;
    } else if (node.type == FileType.txt || node.type == FileType.markdown) {
      nodeIcon = Icons.description;
    } else if (node.type == FileType.image) {
      nodeIcon = Icons.image;
      iconColor = Colors.purpleAccent;
    } else if (node.type == FileType.config) {
      nodeIcon = Icons.settings;
      iconColor = Colors.orangeAccent;
    }

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 0),
      leading: Icon(nodeIcon, color: iconColor),
      title: Text(node.name, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
      trailing: isDir 
          ? const Icon(Icons.chevron_right, color: Colors.white24, size: 20)
          : Text(_formatBytes(node.sizeInBytes), style: const TextStyle(color: Colors.white38, fontSize: 12)),
      onTap: () {
        if (isDir) {
          // El controlador deberá detectar esto y actualizar la ruta
          print("Navegando a: ${node.path}");
        } else {
          print("Abriendo archivo: ${node.name}");
        }
      },
    );
  }

  // Utilidad para formatear los bytes
  String _formatBytes(int bytes) {
    if (bytes <= 0) return "0 B";
    const suffixes = ["B", "KB", "MB", "GB"];
    var i = (log(bytes) / log(1024)).floor();
    return '${(bytes / pow(1024, i)).toStringAsFixed(i > 0 ? 1 : 0)} ${suffixes[i]}';
  }
}