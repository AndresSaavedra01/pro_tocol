import 'dart:async';
import 'dart:convert';
import 'package:dartssh2/dartssh2.dart';
import 'package:pro_tocol/model/entities/GeneralConfig.dart';
import 'package:pro_tocol/model/entities/ProcessNode.dart';

import 'SFTPService.dart';
import '../entities/ServerMetrics.dart';

class SSHService {
  SSHClient? _client;
  SFTPService? _sftpService;

  GeneralConfig? config;

  bool get isConnected => _client != null;

  SFTPService? get sftp => _sftpService;

// ------------------------------------------------------------------
  // 1. CONEXIÓN MEDIANTE CONTRASEÑA
  // ------------------------------------------------------------------
  Future<bool> connectWithPassword(GeneralConfig details) async {
    try {
      config = details;

      final socket = await SSHSocket.connect(
        details.host,
        details.port,
        timeout: const Duration(seconds: 10),
      );

      _client = SSHClient(
        socket,
        username: details.username,
        // Solo usamos la contraseña
        onPasswordRequest: () => details.password,
      );

      _sftpService = SFTPService(_client!);
      return true;
    } catch (e) {
      _cleanup();
      rethrow;
    }
  }

  // ------------------------------------------------------------------
  // 2. CONEXIÓN MEDIANTE LLAVE PRIVADA (RSA / Ed25519)
  // ------------------------------------------------------------------
  /// Recibe los detalles del servidor y el contenido PEM de la llave privada
  Future<bool> connectWithKey(GeneralConfig details, String privateKeyPem) async {
    try {
      config = details;

      final socket = await SSHSocket.connect(
        details.host,
        details.port,
        timeout: const Duration(seconds: 10),
      );

      // Parseamos el texto (PEM) de la llave privada
      final identities = SSHKeyPair.fromPem(privateKeyPem);

      _client = SSHClient(
        socket,
        username: details.username,
        identities: identities, // Usamos la identidad parseada
        // Opcional: Fallback a contraseña si la llave falla o requiere 2FA
        onPasswordRequest: () => details.password,
      );

      _sftpService = SFTPService(_client!);
      return true;
    } catch (e) {
      _cleanup();
      rethrow;
    }
  }

  Future<String> runSingleCommand(String command) async {
    if (_client == null) return 'Error: Desconectado';
    final result = await _client!.run(command);
    return utf8.decode(result).trim();
  }

  // CPU via /proc/stat
  Future<ServerMetrics> fetchMetrics() async {
    if (_client == null) throw Exception('No conectado');

    final stat1 = await runSingleCommand(
      r"head -1 /proc/stat | awk '{print $2+$3+$4+$5+$6+$7+$8, $5}'",
    );
    await Future.delayed(const Duration(milliseconds: 600));
    final stat2 = await runSingleCommand(
      r"head -1 /proc/stat | awk '{print $2+$3+$4+$5+$6+$7+$8, $5}'",
    );

    double cpuUsage = 0.0;
    try {
      final p1 = stat1.trim().split(' ');
      final p2 = stat2.trim().split(' ');
      if (p1.length >= 2 && p2.length >= 2) {
        final total1 = double.parse(p1[0]);
        final idle1  = double.parse(p1[1]);
        final total2 = double.parse(p2[0]);
        final idle2  = double.parse(p2[1]);
        final totalDiff = total2 - total1;
        final idleDiff  = idle2  - idle1;
        if (totalDiff > 0) {
          cpuUsage = ((totalDiff - idleDiff) / totalDiff) * 100;
        }
      }
    } catch (_) {
      cpuUsage = 0.0;
    }

    final ramDisk = await runSingleCommand(
      r"free -m | awk 'NR==2{print $3,$2}'; df / --output=pcent | tail -1",
    );

    final lines    = ramDisk.split('\n');
    final ramParts = (lines.isNotEmpty ? lines[0].trim() : '0 0').split(' ');
    final diskStr  = lines.length > 1 ? lines[1].trim() : '0%';

    return ServerMetrics(
      cpuUsage: cpuUsage,
      usedRam:  int.tryParse(ramParts.isNotEmpty        ? ramParts[0] : '0') ?? 0,
      totalRam: int.tryParse(ramParts.length > 1        ? ramParts[1] : '0') ?? 0,
      diskUsage: diskStr,
      timestamp: DateTime.now(),
    );
  }

  // Red: velocidad real con dos muestras de /proc/net/dev
  Future<Map<String, String>> fetchNetworkStats() async {
    if (_client == null) return {'download': '—', 'upload': '—', 'ipv4': '—'};

    try {
      final iface = await runSingleCommand(
        r"ip route 2>/dev/null | grep default | awk '{print $5}' | head -1",
      );

      if (iface.isEmpty || iface.startsWith('Error')) {
        return {'download': '—', 'upload': '—', 'ipv4': '—'};
      }

      final sample1 = await runSingleCommand(
        "grep '${iface}:' /proc/net/dev | awk '{print \$2,\$10}'",
      );
      await Future.delayed(const Duration(seconds: 1));
      final sample2 = await runSingleCommand(
        "grep '${iface}:' /proc/net/dev | awk '{print \$2,\$10}'",
      );

      final ipv4 = await runSingleCommand(
        "ip addr show $iface 2>/dev/null | grep 'inet ' | awk '{print \$2}' | cut -d/ -f1",
      );

      final p1 = sample1.trim().split(' ');
      final p2 = sample2.trim().split(' ');

      if (p1.length < 2 || p2.length < 2) {
        return {'download': '—', 'upload': '—', 'ipv4': ipv4.isEmpty ? '—' : ipv4};
      }

      final rxDiff = (int.tryParse(p2[0]) ?? 0) - (int.tryParse(p1[0]) ?? 0);
      final txDiff = (int.tryParse(p2[1]) ?? 0) - (int.tryParse(p1[1]) ?? 0);

      return {
        'download': _formatSpeed(rxDiff < 0 ? 0 : rxDiff),
        'upload':   _formatSpeed(txDiff < 0 ? 0 : txDiff),
        'ipv4':     ipv4.isEmpty ? '—' : ipv4,
      };
    } catch (_) {
      return {'download': '—', 'upload': '—', 'ipv4': '—'};
    }
  }

  String _formatSpeed(int bytesPerSec) {
    if (bytesPerSec < 1024)          return '$bytesPerSec B/s';
    if (bytesPerSec < 1024 * 1024)   return '${(bytesPerSec / 1024).toStringAsFixed(1)} KiB/s';
    return '${(bytesPerSec / (1024 * 1024)).toStringAsFixed(1)} MiB/s';
  }

  // Top 30 procesos por CPU
  Future<List<ProcessNode>> fetchProcesses() async {
    if (_client == null) throw Exception('No conectado');

    final raw = await runSingleCommand(
      "ps aux --sort=-%cpu | awk 'NR>1 && NR<=31 {printf \"%s|%s|%s|%s|%s|\",\$1,\$2,\$3,\$4,\$6; for(i=11;i<=NF;i++) printf \$i\" \"; print \"\"}'",
    );

    return raw
        .split('\n')
        .where((l) => l.trim().isNotEmpty)
        .map((l) => ProcessNode.fromRawLine(l))
        .toList();
  }

  // Kill con fallback a sudo -n sin contraseña
  Future<({bool success, String message})> killProcess(String pid) async {
    if (_client == null) return (success: false, message: 'No conectado');

    final r1 = await runSingleCommand('kill -9 $pid 2>&1; echo "__EXIT:\$?"');
    if (r1.contains('__EXIT:0')) {
      return (success: true, message: 'Proceso $pid terminado.');
    }

    final r2 = await runSingleCommand('sudo -n kill -9 $pid 2>&1; echo "__EXIT:\$?"');
    if (r2.contains('__EXIT:0')) {
      return (success: true, message: 'Proceso $pid terminado (sudo).');
    }

    final err = r1.replaceAll(RegExp(r'__EXIT:\d+'), '').trim();
    return (
      success: false,
      message: err.isNotEmpty ? err : 'Sin permisos para PID $pid',
    );
  }

  Future<SSHSession> createTerminal({int width = 80, int height = 24}) async {
    if (_client == null) throw Exception('Cliente no inicializado');
    return await _client!.shell(
      pty: SSHPtyConfig(
        type: 'xterm-256color',
        width: width,
        height: height,
      ),
    );
  }

  void disconnect() {
    _cleanup();
  }

  void _cleanup() {
    _client?.close();
    _client = null;
    _sftpService = null;
    config = null;
  }


}