
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:pro_tocol/model/entities/Server.dart';
import 'package:pro_tocol/model/entities/ProcessNode.dart';
import 'package:pro_tocol/model/entities/ServerMetrics.dart';

import '../../theme/AppColors.dart';

class MonitorTab extends StatefulWidget {
  final Server? activeServer;

  const MonitorTab({super.key, required this.activeServer});

  @override
  State<MonitorTab> createState() => _MonitorTabState();
}

class _MonitorTabState extends State<MonitorTab> {
  Timer? _monitorTimer;
  ServerMetrics? _metrics;
  List<ProcessNode> _processes = [];
  bool _isMonitorFetching = false;
  String _downloadSpeed = '—';
  String _uploadSpeed = '—';
  String _ipv4 = '—';

  @override
  void initState() {
    super.initState();
    _refreshMonitorData();
    _monitorTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) _refreshMonitorData();
    });
  }

  @override
  void dispose() {
    _monitorTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshMonitorData() async {
    if (widget.activeServer == null || !widget.activeServer!.sshService.isConnected) return;
    if (_isMonitorFetching) return;

    _isMonitorFetching = true;
    if (_metrics == null && mounted) setState(() {});

    try {
      final metricsFuture = widget.activeServer!.sshService.fetchMetrics();
      final processesFuture = widget.activeServer!.sshService.fetchProcesses();
      final netFuture = widget.activeServer!.sshService.fetchNetworkStats();

      final results = await Future.wait([metricsFuture, processesFuture, netFuture]);

      if (!mounted) return;

      setState(() {
        _metrics = results[0] as ServerMetrics;
        _processes = results[1] as List<ProcessNode>;
        final net = results[2] as Map<String, String>;
        _downloadSpeed = net['download'] ?? '—';
        _uploadSpeed = net['upload'] ?? '—';
        _ipv4 = net['ipv4'] ?? '—';
      });
    } catch (e) {
      debugPrint("Error monitor: $e");
    } finally {
      if (mounted) setState(() => _isMonitorFetching = false);
    }
  }

  // --- MÉTODOS DE UI DE MONITOREO ---
  @override
  Widget build(BuildContext context) {
    final m = _metrics;
    final cpuVal = m?.cpuUsage ?? 0.0;
    final usedRam = m?.usedRam ?? 0;
    final totalRam = m?.totalRam ?? 0;
    final diskStr = m?.diskUsage ?? '0%';
    final diskVal = double.tryParse(diskStr.replaceAll('%', '')) ?? 0.0;
    final ramPct = totalRam > 0 ? (usedRam / totalRam * 100) : 0.0;

    return RefreshIndicator(
      onRefresh: _refreshMonitorData,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_isMonitorFetching && _metrics == null)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: LinearProgressIndicator(minHeight: 2, color: AppColors.primary, backgroundColor: AppColors.surface),
            ),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            alignment: WrapAlignment.spaceEvenly,
            children: [
              SizedBox(width: 105, child: _buildCircleCard(label: 'CPU', percent: cpuVal, centerText: '${cpuVal.toStringAsFixed(1)}%', color: Colors.blue)),
              SizedBox(width: 105, child: _buildCircleCard(label: 'Memoria', percent: ramPct, centerText: 'Used\n${_mbToReadable(usedRam)}\n${_mbToReadable(totalRam)}\nTotal', color: Colors.purple, smallCenter: true)),
              SizedBox(width: 105, child: _buildCircleCard(label: 'Disco', percent: diskVal, centerText: 'Used\n$diskStr', color: Colors.orange, smallCenter: true)),
            ],
          ),
          const SizedBox(height: 16),
          _buildNetworkCard(),
          const SizedBox(height: 16),
          _buildProcessesCard(),
        ],
      ),
    );
  }

  Widget _buildCircleCard({required String label, required double percent, required String centerText, required Color color, bool smallCenter = false}) {
    final clamped = percent.clamp(0.0, 100.0);
    final barColor = clamped > 85 ? AppColors.error : clamped > 60 ? Colors.orange : color;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
      child: Column(
        children: [
          Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          SizedBox(
            width: 80, height: 80,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(width: 80, height: 80, child: CircularProgressIndicator(value: (clamped / 100), strokeWidth: 7, backgroundColor: AppColors.border, color: barColor)),
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(centerText, textAlign: TextAlign.center, style: TextStyle(color: AppColors.textPrimary, fontSize: smallCenter ? 9 : 13, fontWeight: FontWeight.bold, height: 1.3)),
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
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Redes', style: TextStyle(color: AppColors.textMuted, fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          const Text('Conexión activa', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          const SizedBox(height: 10),
          _netRow(color: Colors.blue, label: 'Download', value: _downloadSpeed),
          const SizedBox(height: 8),
          _netRow(color: Colors.purple, label: 'Upload', value: _uploadSpeed),
          const SizedBox(height: 8),
          _netRow(color: Colors.orange, label: 'IPv4', value: _ipv4),
        ],
      ),
    );
  }

  Widget _netRow({required Color color, required String label, required String value}) {
    return Row(
      children: [
        Container(width: 12, height: 12, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 10),
        Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
        const Spacer(),
        Text(value, style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _buildProcessesCard() {
    return Container(
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Row(
              children: [
                const Text('Aplicaciones', style: TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.bold)),
                const Spacer(),
                if (_isMonitorFetching) const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary)),
                const SizedBox(width: 8),
                Text('${_processes.length} procesos', style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: AppColors.background,
            child: const Row(
              children: [
                Expanded(flex: 3, child: ProcHeader('Name')),
                Expanded(flex: 2, child: ProcHeader('CPU', right: true)),
                Expanded(flex: 2, child: ProcHeader('Memory', right: true)),
                Expanded(flex: 2, child: ProcHeader('User', right: true)),
                Expanded(flex: 1, child: ProcHeader('PID', right: true)),
                SizedBox(width: 36),
              ],
            ),
          ),
          if (_processes.isEmpty)
            const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('Sin datos. Desliza para actualizar.', style: TextStyle(color: AppColors.textMuted))))
          else
            ListView.separated(
              shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), itemCount: _processes.length, separatorBuilder: (_, __) => const Divider(height: 1, color: AppColors.border),
              itemBuilder: (_, i) => _buildProcessRow(_processes[i]),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildProcessRow(ProcessNode proc) {
    final icon = _processIcon(proc.name);
    final cpuColor = proc.cpuPercentage > 50 ? AppColors.error : proc.cpuPercentage > 20 ? Colors.orange : AppColors.textPrimary;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Expanded(flex: 3, child: Row(
            children: [
              Icon(icon, size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(child: Text(proc.name, style: const TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis)),
            ],
          )),
          Expanded(flex: 2, child: Text('${proc.cpuPercentage.toStringAsFixed(1)}%', textAlign: TextAlign.right, style: TextStyle(color: cpuColor, fontSize: 12))),
          Expanded(flex: 2, child: Text(proc.memoryUsage, textAlign: TextAlign.right, style: const TextStyle(color: AppColors.textMuted, fontSize: 12))),
          Expanded(flex: 2, child: Text(proc.user, textAlign: TextAlign.right, style: const TextStyle(color: AppColors.textMuted, fontSize: 11), overflow: TextOverflow.ellipsis)),
          Expanded(flex: 1, child: Text(proc.pid, textAlign: TextAlign.right, style: const TextStyle(color: AppColors.textMuted, fontSize: 11))),
          SizedBox(width: 36, child: IconButton(
            icon: const Icon(Icons.close, size: 15, color: AppColors.error), tooltip: 'kill -9', padding: EdgeInsets.zero,
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
        title: const Text('¿Matar proceso?', style: TextStyle(color: AppColors.textPrimary)),
        content: Text('PID ${proc.pid} — ${proc.name}\n\nEsta acción no se puede deshacer.', style: const TextStyle(color: AppColors.textMuted)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar', style: TextStyle(color: AppColors.textMuted))),
          ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: AppColors.error), onPressed: () => Navigator.pop(ctx, true), child: const Text('Matar', style: TextStyle(color: Colors.white))),
        ],
      ),
    );

    if (confirmed == true && mounted && widget.activeServer != null) {
      final result = await widget.activeServer!.sshService.killProcess(proc.pid);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result.message), backgroundColor: result.success ? AppColors.surface : AppColors.error));
        if (result.success) _refreshMonitorData();
      }
    }
  }

  String _mbToReadable(int mb) {
    if (mb >= 1024) return '${(mb / 1024).toStringAsFixed(1)} GB';
    return '$mb MB';
  }

  IconData _processIcon(String name) {
    final n = name.toLowerCase();
    if (n.contains('nginx') || n.contains('apache') || n.contains('httpd')) return Icons.dns;
    if (n.contains('mysql') || n.contains('postgres') || n.contains('mongo')) return Icons.storage;
    if (n.contains('bash') || n.contains('zsh') || n.startsWith('sh')) return Icons.terminal;
    if (n.contains('python') || n.contains('node') || n.contains('java')) return Icons.code;
    if (n.contains('systemd') || n.contains('init')) return Icons.settings;
    if (n.contains('ssh')) return Icons.lock;
    return Icons.memory;
  }
}

class ProcHeader extends StatelessWidget {
  final String text;
  final bool right;
  const ProcHeader(this.text, {super.key, this.right = false});

  @override
  Widget build(BuildContext context) {
    return Text(text, textAlign: right ? TextAlign.right : TextAlign.left, style: const TextStyle(color: AppColors.textMuted, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.4));
  }
}