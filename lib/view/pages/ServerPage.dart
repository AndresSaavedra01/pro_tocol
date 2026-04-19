import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';
import 'package:pro_tocol/logic/apps_manager_catalog.dart';
import 'package:pro_tocol/logic/apps_manager_state.dart';

import 'package:pro_tocol/controller/ServerController.dart';
import 'package:pro_tocol/model/entities/DataBaseEntities.dart';
import 'package:pro_tocol/model/entities/FileNode.dart';
import 'package:pro_tocol/model/entities/Server.dart';
import 'package:pro_tocol/model/entities/ProcessNode.dart';
import 'package:pro_tocol/model/entities/ServerMetrics.dart';

import '../theme/AppColors.dart';

class ServerPage extends StatefulWidget {
  final ServerConfig serverConfig;
  final ServerController serverController;
  final bool isTemporarySession;

  const ServerPage({
    super.key,
    required this.serverConfig,
    required this.serverController,
    this.isTemporarySession = false,
  });

  @override
  State<ServerPage> createState() => _ServerPageState();
}

class _ServerPageState extends State<ServerPage> {
  late final Terminal terminal;
  Server? _activeServer;
  Timer? _monitorTimer;

  late final ValueListenable<Map<String, AppInstallState>> _appInstallStatesListenable;
  late final ValueListenable<List<ManagedApp>> _appsSearchResultsListenable;
  Map<String, AppInstallState> _previousAppInstallStates = const {};
  bool _appsStatusSyncRequested = false;
  bool _isAppsStatusSyncInProgress = false;
  final TextEditingController _appsSearchController = TextEditingController();
  Timer? _appsSearchDebounce;
  bool _isAppsSearchInProgress = false;
  int _searchRequestId = 0;

  // Monitor state
  ServerMetrics? _metrics;
  List<ProcessNode> _processes = [];
  bool _isMonitorFetching = false;   
  String _downloadSpeed = '—';
  String _uploadSpeed   = '—';
  String _ipv4          = '—';

  // Files
  String currentPath = "/";
  List<FileNode> currentFiles = [];
  bool _isLoadingFiles = false;

  // Terminal
  String _currentCommandBuffer = "";

  @override
  void initState() {
    super.initState();
    terminal = Terminal(maxLines: 10000);
    _appInstallStatesListenable =
        widget.serverController.installStatesListenable(widget.serverConfig.id);
    _appsSearchResultsListenable =
        widget.serverController.searchResultsListenable(widget.serverConfig.id);
    _previousAppInstallStates = Map<String, AppInstallState>.from(
      widget.serverController.getInstallStates(widget.serverConfig.id),
    );
    _appInstallStatesListenable.addListener(_handleAppInstallStateChanged);
    _connectToServerController();
  }

  @override
  void dispose() {
    _monitorTimer?.cancel();
    _appInstallStatesListenable.removeListener(_handleAppInstallStateChanged);
    _appsSearchDebounce?.cancel();
    _appsSearchController.dispose();
    super.dispose();
  }

  // CONEXION

  Future<void> _connectToServerController() async {
    try {
      _activeServer = widget.serverController.getActiveServer(widget.serverConfig.id);

      final session = await _activeServer!.sshService.createTerminal(
        width:  terminal.viewWidth  > 0 ? terminal.viewWidth  : 80,
        height: terminal.viewHeight > 0 ? terminal.viewHeight : 24,
      );

      terminal.onResize = (w, h, cw, ch) {
        if (w > 0 && h > 0) session.resizeTerminal(w, h);
      };

      _startUniversalSync(session);

      session.stdout.listen((d) {
        if (mounted) terminal.write(utf8.decode(d, allowMalformed: true));
      });
      session.stderr.listen((d) {
        if (mounted) terminal.write(utf8.decode(d, allowMalformed: true));
      });
      terminal.onOutput = (input) => _handleTerminalInput(input, session);

      terminal.write('\x1Bc');
      terminal.write('\x1B[32mConexión establecida.\x1B[0m\r\n\n');

      _refreshFiles();

      if (!widget.isTemporarySession) {
        // Primera carga inmediata
        _refreshMonitorData();
        // Timer cada 10s — el guard interno evita solapamiento
        _monitorTimer = Timer.periodic(const Duration(seconds: 10), (_) {
          if (mounted) _refreshMonitorData();
        });
      }
    } catch (e) {
      if (mounted) terminal.write('\x1B[31mError: $e\x1B[0m\r\n');
    }
  }

  // MONITOR 

  Future<void> _refreshMonitorData() async {
    if (_activeServer == null || !_activeServer!.sshService.isConnected) return;
    // Solo bloquea si YA está en curso (evita llamadas paralelas)
    if (_isMonitorFetching) return;

    _isMonitorFetching = true;
    // Mostramos indicador solo si no hay datos previos
    if (_metrics == null && mounted) setState(() {});

    try {
      // Metricas + procesos en paralelo
      final metricsFuture   = _activeServer!.sshService.fetchMetrics();
      final processesFuture = _activeServer!.sshService.fetchProcesses();
      final netFuture       = _activeServer!.sshService.fetchNetworkStats();

      final results = await Future.wait([metricsFuture, processesFuture, netFuture]);

      if (!mounted) return;

      final metrics = results[0] as ServerMetrics;
      final procs   = results[1] as List<ProcessNode>;
      final net     = results[2] as Map<String, String>;

      setState(() {
        _metrics       = metrics;
        _processes     = procs;
        _downloadSpeed = net['download'] ?? '—';
        _uploadSpeed   = net['upload']   ?? '—';
        _ipv4          = net['ipv4']     ?? '—';
      });
    } catch (e) {
      debugPrint("Error monitor: $e");
    } finally {
      _isMonitorFetching = false;
    }
  }

  // TERMINAL

  void _handleTerminalInput(String input, SSHSession session) {
    if (input == '\x1B[A') {
      final cmd = widget.serverController.commandHistoryManager.previous();
      if (cmd != null) _updateCommandBuffer(cmd);
      return;
    } else if (input == '\x1B[B') {
      final cmd = widget.serverController.commandHistoryManager.next();
      if (cmd != null) { _updateCommandBuffer(cmd); } else { _clearCommandBuffer(); }
      return;
    } else if (input == '\r' || input == '\n') {
      if (_currentCommandBuffer.isNotEmpty) {
        session.stdin.add(utf8.encode(_currentCommandBuffer + '\n'));
        _currentCommandBuffer = "";
      } else {
        session.stdin.add(utf8.encode(input));
      }
      return;
    } else if (input == '\x7F' || input == '\b') {
      if (_currentCommandBuffer.isNotEmpty) {
        _currentCommandBuffer =
            _currentCommandBuffer.substring(0, _currentCommandBuffer.length - 1);
        terminal.write('\b \b');
        return;
      }
    } else if (input.length == 1 && input.codeUnitAt(0) >= 32) {
      _currentCommandBuffer += input;
      terminal.write(input);
      return;
    }
    session.stdin.add(utf8.encode(input));
  }

  void _updateCommandBuffer(String command) {
    for (int i = 0; i < _currentCommandBuffer.length; i++) terminal.write('\b \b');
    _currentCommandBuffer = command;
    terminal.write(command);
  }

  void _clearCommandBuffer() {
    for (int i = 0; i < _currentCommandBuffer.length; i++) terminal.write('\b \b');
    _currentCommandBuffer = "";
  }

  void _startUniversalSync(SSHSession session) {
    int attempts = 0;
    Timer.periodic(const Duration(milliseconds: 300), (timer) async {
      attempts++;
      if (mounted && terminal.viewWidth > 0) {
        session.resizeTerminal(terminal.viewWidth, terminal.viewHeight);
        await _activeServer!.sshService.runSingleCommand(
            "stty cols ${terminal.viewWidth} rows ${terminal.viewHeight}");
        if (attempts >= 3) timer.cancel();
      }
      if (attempts > 10) timer.cancel();
    });
  }

  // APPS MANAGER HANDLERS

  void _handleAppInstallStateChanged() {
    if (!mounted) return;
    final current = Map<String, AppInstallState>.from(_appInstallStatesListenable.value);
    for (final entry in current.entries) {
      final prev = _previousAppInstallStates[entry.key]?.status;
      final cur  = entry.value.status;
      if (prev == cur) continue;
      final app = AppsManagerCatalog.byId(entry.key);
      final name = app?.displayName ?? entry.key;
      if (cur == AppInstallStatus.installing)   _showSnackBar('$name: instalando');
      else if (cur == AppInstallStatus.uninstalling) _showSnackBar('$name: eliminando');
      else if (cur == AppInstallStatus.installed && prev == AppInstallStatus.installing)
        _showSnackBar('$name: instalación exitosa');
      else if (cur == AppInstallStatus.idle && prev == AppInstallStatus.uninstalling)
        _showSnackBar('$name: eliminación exitosa');
      else if (cur == AppInstallStatus.failure)
        _showSnackBar(
          prev == AppInstallStatus.uninstalling ? '$name: eliminación fallida' : '$name: instalación fallida',
          isError: true,
        );
    }
    _previousAppInstallStates = current;
  }

  void _showSnackBar(String message, {bool isError = false}) {
    final m = ScaffoldMessenger.maybeOf(context);
    if (m == null) return;
    m.hideCurrentSnackBar();
    m.showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: isError ? AppColors.error : AppColors.surface,
    ));
  }

  // ARCHIVOS

  Future<void> _refreshFiles() async {
    if (_activeServer?.sshService.sftp == null) return;
    setState(() => _isLoadingFiles = true);
    try {
      final files = await _activeServer!.sshService.sftp!.listDirectory(currentPath);
      if (mounted) setState(() { currentFiles = files; _isLoadingFiles = false; });
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingFiles = false);
        _showSnackBar("Error SFTP: $e", isError: true);
      }
    }
  }

  void _goBack() {
    if (currentPath == "/" || currentPath == "") return;
    List<String> parts = currentPath.split('/');
    if (parts.last.isEmpty) parts.removeLast();
    if (parts.isNotEmpty) parts.removeLast();
    String newPath = parts.join('/');
    if (newPath.isEmpty) newPath = "/";
    setState(() => currentPath = newPath);
    _refreshFiles();
  }

  // BUILD

  @override
  Widget build(BuildContext context) {
    final connStr      = "${widget.serverConfig.username}@${widget.serverConfig.host}";
    final distroName   = _activeServer?.distroName   ?? 'Linux';
    final pkgManager   = _activeServer?.packageManager ?? 'unknown';
    final distroIcon   = _getDistroIcon(distroName);

    return DefaultTabController(
      length: widget.isTemporarySession ? 1 : 4,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.surface,
          title: Column(
            children: [
              Text(
                widget.isTemporarySession ? 'Sesión Temporal' : widget.serverConfig.host,
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              Text(connStr, style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
              if (!widget.isTemporarySession) ...[
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(distroIcon, style: const TextStyle(fontSize: 18)),
                    const SizedBox(width: 8),
                    Column(children: [
                      Text(distroName, style: const TextStyle(color: AppColors.textPrimary, fontSize: 14)),
                      Text('Package Manager: $pkgManager',
                          style: const TextStyle(color: AppColors.textMuted, fontSize: 10)),
                    ]),
                  ],
                ),
              ],
            ],
          ),
          centerTitle: true,
          bottom: widget.isTemporarySession
              ? null
              : const TabBar(
                  indicatorColor: AppColors.primary,
                  labelColor: AppColors.textPrimary,
                  tabs: [
                    Tab(text: 'Monitoreo'),
                    Tab(text: 'Terminal'),
                    Tab(text: 'Archivos'),
                    Tab(text: 'Apps Manager'),
                  ],
                ),
        ),
        body: widget.isTemporarySession
            ? _buildTerminalTab()
            : TabBarView(
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _buildMonitorTab(),
                  _buildTerminalTab(),
                  _buildArchivosTab(),
                  _buildAppsManagerTab(),
                ],
              ),
      ),
    );
  }

  
  // PESTANA MONITOREO
  

  Widget _buildMonitorTab() {
    final m        = _metrics;
    final cpuVal   = m?.cpuUsage  ?? 0.0;
    final usedRam  = m?.usedRam   ?? 0;
    final totalRam = m?.totalRam  ?? 0;
    final diskStr  = m?.diskUsage ?? '0%';
    final diskVal  = double.tryParse(diskStr.replaceAll('%', '')) ?? 0.0;
    final ramPct   = totalRam > 0 ? (usedRam / totalRam * 100) : 0.0;

    return RefreshIndicator(
      onRefresh: _refreshMonitorData,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Barra de progreso tenue mientras carga (sin bloquear la UI)
          if (_isMonitorFetching && _metrics == null)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: LinearProgressIndicator(
                minHeight: 2,
                color: AppColors.primary,
                backgroundColor: AppColors.surface,
              ),
            ),

          //  Circulos CPU / Memoria / Disco
          Row(
            children: [
              Expanded(child: _buildCircleCard(
                label:      'CPU',
                percent:    cpuVal,
                centerText: '${cpuVal.toStringAsFixed(1)}%',
                color:      Colors.blue,
              )),
              const SizedBox(width: 10),
              Expanded(child: _buildCircleCard(
                label:       'Memoria',
                percent:     ramPct,
                centerText:  'Used\n${_mbToReadable(usedRam)}\n${_mbToReadable(totalRam)}\nTotal',
                color:       Colors.purple,
                smallCenter: true,
              )),
              const SizedBox(width: 10),
              Expanded(child: _buildCircleCard(
                label:       'Disco',
                percent:     diskVal,
                centerText:  'Used\n$diskStr',
                color:       Colors.orange,
                smallCenter: true,
              )),
            ],
          ),

          const SizedBox(height: 16),

          // 
          _buildNetworkCard(),

          const SizedBox(height: 16),

          //  Procesos 
          _buildProcessesCard(),
        ],
      ),
    );
  }

  Widget _buildCircleCard({
    required String label,
    required double percent,
    required String centerText,
    required Color  color,
    bool smallCenter = false,
  }) {
    final clamped  = percent.clamp(0.0, 100.0);
    final barColor = clamped > 85 ? AppColors.error
                   : clamped > 60 ? Colors.orange
                   : color;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Text(label, style: const TextStyle(
              color: AppColors.textMuted, fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          SizedBox(
            width: 80, height: 80,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 80, height: 80,
                  child: CircularProgressIndicator(
                    value:           (clamped / 100),
                    strokeWidth:     7,
                    backgroundColor: AppColors.border,
                    color:           barColor,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    centerText,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color:      AppColors.textPrimary,
                      fontSize:   smallCenter ? 9 : 13,
                      fontWeight: FontWeight.bold,
                      height:     1.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNetworkCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Redes', style: TextStyle(
              color: AppColors.textMuted, fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          const Text('Conexión activa',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          const SizedBox(height: 10),
          _netRow(color: Colors.blue,   label: 'Download', value: _downloadSpeed),
          const SizedBox(height: 8),
          _netRow(color: Colors.purple, label: 'Upload',   value: _uploadSpeed),
          const SizedBox(height: 8),
          _netRow(color: Colors.orange, label: 'IPv4',     value: _ipv4),
        ],
      ),
    );
  }

  Widget _netRow({required Color color, required String label, required String value}) {
    return Row(
      children: [
        Container(
          width: 12, height: 12,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
        ),
        const SizedBox(width: 10),
        Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
        const Spacer(),
        Text(value, style: const TextStyle(
            color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _buildProcessesCard() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Row(
              children: [
                const Text('Aplicaciones', style: TextStyle(
                    color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.bold)),
                const Spacer(),
                if (_isMonitorFetching)
                  const SizedBox(width: 14, height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary)),
                const SizedBox(width: 8),
                Text('${_processes.length} procesos',
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: AppColors.background,
            child: const Row(
              children: [
                Expanded(flex: 3, child: _ProcHeader('Name')),
                Expanded(flex: 2, child: _ProcHeader('CPU',    right: true)),
                Expanded(flex: 2, child: _ProcHeader('Memory', right: true)),
                Expanded(flex: 2, child: _ProcHeader('User',   right: true)),
                Expanded(flex: 1, child: _ProcHeader('PID',    right: true)),
                SizedBox(width: 36),
              ],
            ),
          ),
          if (_processes.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: Text('Sin datos. Desliza para actualizar.',
                  style: TextStyle(color: AppColors.textMuted))),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _processes.length,
              separatorBuilder: (_, __) => const Divider(height: 1, color: AppColors.border),
              itemBuilder: (_, i) => _buildProcessRow(_processes[i]),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildProcessRow(ProcessNode proc) {
    final icon     = _processIcon(proc.name);
    final cpuColor = proc.cpuPercentage > 50 ? AppColors.error
                   : proc.cpuPercentage > 20 ? Colors.orange
                   : AppColors.textPrimary;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Expanded(flex: 3, child: Row(
            children: [
              Icon(icon, size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(child: Text(proc.name,
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w500),
                overflow: TextOverflow.ellipsis,
              )),
            ],
          )),
          Expanded(flex: 2, child: Text('${proc.cpuPercentage.toStringAsFixed(1)}%',
            textAlign: TextAlign.right,
            style: TextStyle(color: cpuColor, fontSize: 12),
          )),
          Expanded(flex: 2, child: Text(proc.memoryUsage,
            textAlign: TextAlign.right,
            style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
          )),
          Expanded(flex: 2, child: Text(proc.user,
            textAlign: TextAlign.right,
            style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
            overflow: TextOverflow.ellipsis,
          )),
          Expanded(flex: 1, child: Text(proc.pid,
            textAlign: TextAlign.right,
            style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
          )),
          SizedBox(width: 36, child: IconButton(
            icon: const Icon(Icons.close, size: 15, color: AppColors.error),
            tooltip: 'kill -9',
            padding: EdgeInsets.zero,
            onPressed: () => _confirmKillProcess(proc),
          )),
        ],
      ),
    );
  }

  Future<void> _confirmKillProcess(ProcessNode proc) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('¿Matar proceso?',
            style: TextStyle(color: AppColors.textPrimary)),
        content: Text('PID ${proc.pid} — ${proc.name}\n\nEsta acción no se puede deshacer.',
            style: const TextStyle(color: AppColors.textMuted)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar', style: TextStyle(color: AppColors.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Matar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final result = await _activeServer!.sshService.killProcess(proc.pid);
      if (mounted) {
        _showSnackBar(result.message, isError: !result.success);
        if (result.success) _refreshMonitorData();
      }
    }
  }

  // TERMINAL TAB

  Widget _buildTerminalTab() {
    return Container(
      color: AppColors.terminalBg,
      padding: const EdgeInsets.all(12.0),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: TerminalView(
            terminal,
            autofocus: true,
            backgroundOpacity: 1,
            theme: TerminalTheme(
              cursor:     AppColors.textPrimary,
              selection:  Colors.blueAccent.withOpacity(0.4),
              foreground: AppColors.textPrimary,
              background: AppColors.background,
              black:      Colors.black,
              red:        AppColors.error,
              green:      AppColors.success,
              yellow:     Colors.yellowAccent,
              blue:       Colors.blueAccent,
              magenta:    Colors.purpleAccent,
              cyan:       Colors.cyanAccent,
              white:      AppColors.textPrimary,
              brightBlack:   Colors.grey,
              brightRed:     Colors.red,
              brightGreen:   Colors.green,
              brightYellow:  Colors.yellow,
              brightBlue:    Colors.blue,
              brightMagenta: Colors.purple,
              brightCyan:    Colors.cyan,
              brightWhite:   Colors.white,
              searchHitBackground:        Colors.yellowAccent.withOpacity(0.3),
              searchHitBackgroundCurrent: Colors.orangeAccent.withOpacity(0.5),
              searchHitForeground:        Colors.black,
            ),
            textStyle: const TerminalStyle(fontSize: 12),
          ),
        ),
      ),
    );
  }

  // ARCHIVOS TAB

  Widget _buildArchivosTab() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          color: AppColors.surface,
          child: Row(
            children: [
              if (currentPath != "/")
                Container(
                  margin: const EdgeInsets.only(right: 12),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.arrow_upward, color: AppColors.primary, size: 20),
                    onPressed: _goBack,
                    tooltip: "Subir un nivel",
                    padding: const EdgeInsets.all(8),
                    constraints: const BoxConstraints(),
                  ),
                ),
              const Icon(Icons.folder_open, color: AppColors.textMuted, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text(currentPath,
                style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 13),
                overflow: TextOverflow.ellipsis)),
              if (_isLoadingFiles)
                const SizedBox(width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary)),
            ],
          ),
        ),
        const Divider(height: 1, color: AppColors.border),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _refreshFiles,
            child: ListView.builder(
              itemCount: currentFiles.length,
              itemBuilder: (_, i) => _buildFileNodeItem(currentFiles[i]),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFileNodeItem(FileNode node) {
    final isDir = node.isDirectory;
    IconData icon = Icons.insert_drive_file;
    Color   color = AppColors.textMuted;

    if (isDir) { icon = Icons.folder; color = AppColors.fileDir; }
    else if (node.type == FileType.txt || node.type == FileType.markdown)
      { icon = Icons.description; color = AppColors.fileTxt; }
    else if (node.type == FileType.image)
      { icon = Icons.image; color = AppColors.fileImg; }
    else if (node.type == FileType.config)
      { icon = Icons.settings; color = AppColors.fileCfg; }

    return ListTile(
      leading: Icon(icon, color: color),
      title:    Text(node.name,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 14)),
      subtitle: Text("${node.permissions} • ${_formatSize(node.sizeInBytes)}",
          style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
      trailing: isDir
          ? const Icon(Icons.chevron_right, color: AppColors.textMuted, size: 20)
          : null,
      onTap: () {
        if (node.isDirectory) {
          if (node.name == ".") return;
          setState(() => currentPath = node.path);
          _refreshFiles();
        }
      },
    );
  }

  // APPS MANAGER TAB

  Widget _buildAppsManagerTab() {
    if (!_appsStatusSyncRequested) {
      _appsStatusSyncRequested = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _syncAppsStatus();
      });
    }

    return ValueListenableBuilder<Map<String, AppInstallState>>(
      valueListenable: widget.serverController.installStatesListenable(widget.serverConfig.id),
      builder: (context, states, _) {
        return ValueListenableBuilder<List<ManagedApp>>(
          valueListenable: _appsSearchResultsListenable,
          builder: (context, searchResults, __) {
            return Column(
              children: [
                if (_isAppsStatusSyncInProgress)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    color: AppColors.surface,
                    child: const Row(children: [
                      SizedBox(width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary)),
                      SizedBox(width: 10),
                      Text('Comprobando apps instaladas...',
                          style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                    ]),
                  ),
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  color: AppColors.surface,
                  child: TextField(
                    controller: _appsSearchController,
                    onChanged: _handleAppsSearchChanged,
                    style: const TextStyle(color: AppColors.textPrimary),
                    decoration: InputDecoration(
                      hintText: 'Buscar paquetes (git, htop, nginx...)',
                      hintStyle: const TextStyle(color: AppColors.textMuted),
                      prefixIcon: const Icon(Icons.search, color: AppColors.textMuted),
                      suffixIcon: _isAppsSearchInProgress
                          ? const Padding(padding: EdgeInsets.all(12),
                              child: SizedBox(width: 16, height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2)))
                          : (_appsSearchController.text.trim().isNotEmpty
                              ? IconButton(onPressed: _clearAppsSearch,
                                  icon: const Icon(Icons.close, color: AppColors.textMuted))
                              : null),
                      filled: true,
                      fillColor: AppColors.background,
                      border:        OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.border)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.border)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.primary)),
                    ),
                  ),
                ),
                Expanded(
                  child: searchResults.isEmpty
                      ? const Center(child: Text('Sin resultados para tu búsqueda.',
                          style: TextStyle(color: AppColors.textMuted)))
                      : ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: searchResults.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (_, i) {
                            final app   = searchResults[i];
                            final state = states[app.id] ?? const AppInstallState.idle();
                            return _buildManagedAppCard(app: app, state: state);
                          },
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _handleAppsSearchChanged(String value) {
    _appsSearchDebounce?.cancel();
    _appsSearchDebounce = Timer(const Duration(milliseconds: 350), () => _runAppsSearch(value));
    setState(() {});
  }

  Future<void> _runAppsSearch(String query) async {
    final id = ++_searchRequestId;
    if (mounted) setState(() => _isAppsSearchInProgress = true);
    try {
      await widget.serverController.searchApps(serverId: widget.serverConfig.id, query: query);
    } finally {
      if (!mounted || id != _searchRequestId) return;
      setState(() => _isAppsSearchInProgress = false);
    }
  }

  void _clearAppsSearch() {
    _appsSearchController.clear();
    _appsSearchDebounce?.cancel();
    _runAppsSearch('');
    if (mounted) setState(() {});
  }

  Future<void> _syncAppsStatus() async {
    if (_isAppsStatusSyncInProgress) return;
    if (mounted) setState(() => _isAppsStatusSyncInProgress = true);
    try {
      await widget.serverController.refreshInstalledApps(serverId: widget.serverConfig.id);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isAppsStatusSyncInProgress = false);
    }
  }

  Widget _buildManagedAppCard({required ManagedApp app, required AppInstallState state}) {
    final pkgMgr      = (_activeServer?.packageManager ?? 'unknown').toLowerCase();
    final canRunAction = !state.isBusy && pkgMgr != 'unknown';
    final isInstalled  = state.isInstalled;

    final btnLabel = state.status == AppInstallStatus.installing   ? 'Instalando...'
                   : state.status == AppInstallStatus.uninstalling ? 'Eliminando...'
                   : isInstalled ? 'Eliminar' : 'Instalar';
    final btnColor = isInstalled ? AppColors.error : AppColors.primary;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.glassCard.copyWith(color: AppColors.surface),
      child: Row(
        children: [
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(app.displayName, style: const TextStyle(
                  color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(app.description,
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
              const SizedBox(height: 8),
              _buildInstallStateBadge(state),
              if (state.message != null && state.message!.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(state.message!,
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
              ],
              if (pkgMgr == 'unknown') ...[
                const SizedBox(height: 8),
                const Text('Package manager no detectado.',
                    style: TextStyle(color: AppColors.error, fontSize: 11)),
              ],
            ],
          )),
          const SizedBox(width: 10),
          ElevatedButton(
            onPressed: canRunAction ? () {
              if (isInstalled) {
                widget.serverController.uninstallAppInBackground(
                  serverId: widget.serverConfig.id, appId: app.id, packageName: app.packageName);
              } else {
                widget.serverController.installAppInBackground(
                  serverId: widget.serverConfig.id, appId: app.id, packageName: app.packageName);
              }
            } : null,
            style: ElevatedButton.styleFrom(
              backgroundColor:         btnColor,
              disabledBackgroundColor: AppColors.border,
              foregroundColor:         AppColors.textPrimary,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            child: Text(btnLabel),
          ),
        ],
      ),
    );
  }

  Widget _buildInstallStateBadge(AppInstallState state) {
    String label; Color color;
    switch (state.status) {
      case AppInstallStatus.installing:   label = 'Instalando'; color = Colors.amber;        break;
      case AppInstallStatus.uninstalling: label = 'Eliminando'; color = Colors.orange;       break;
      case AppInstallStatus.installed:    label = 'Instalada';  color = AppColors.success;   break;
      case AppInstallStatus.failure:      label = 'Fallo';      color = AppColors.error;     break;
      case AppInstallStatus.success:      label = 'Exito';      color = AppColors.success;   break;
      case AppInstallStatus.idle:         label = 'Listo';      color = AppColors.textMuted; break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.18),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Text(label,
          style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }

  // HELPERS

  IconData _processIcon(String name) {
    final n = name.toLowerCase();
    if (n.contains('nginx') || n.contains('apache') || n.contains('httpd')) return Icons.dns;
    if (n.contains('mysql') || n.contains('postgres') || n.contains('mongo')) return Icons.storage;
    if (n.contains('bash')  || n.contains('zsh')  || n.startsWith('sh'))     return Icons.terminal;
    if (n.contains('python')|| n.contains('node') || n.contains('java'))     return Icons.code;
    if (n.contains('systemd')|| n.contains('init'))                          return Icons.settings;
    if (n.contains('ssh'))                                                    return Icons.lock;
    return Icons.memory;
  }

  String _mbToReadable(int mb) {
    if (mb >= 1024) return '${(mb / 1024).toStringAsFixed(1)} GB';
    return '$mb MB';
  }

  String _getDistroIcon(String d) {
    final n = d.toLowerCase();
    if (n.contains('ubuntu'))  return '🐧';
    if (n.contains('debian'))  return '🦆';
    if (n.contains('arch'))    return '🌀';
    if (n.contains('manjaro')) return '🌲';
    if (n.contains('fedora'))  return '🛡️';
    if (n.contains('rhel') || n.contains('red hat')) return '🔥';
    return '🐧';
  }

  String _formatSize(int bytes) {
    if (bytes <= 0) return "0 B";
    const s = ["B", "KB", "MB", "GB"];
    var i = (log(bytes) / log(1024)).floor();
    return '${(bytes / pow(1024, i)).toStringAsFixed(1)} ${s[i]}';
  }
}

// WIDGET HELPER

class _ProcHeader extends StatelessWidget {
  final String text;
  final bool right;
  const _ProcHeader(this.text, {this.right = false});

  @override
  Widget build(BuildContext context) {
    return Text(text,
      textAlign: right ? TextAlign.right : TextAlign.left,
      style: const TextStyle(
        color: AppColors.textMuted, fontSize: 11,
        fontWeight: FontWeight.w700, letterSpacing: 0.4,
      ),
    );
  }
}