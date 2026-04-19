class ProcessNode {
  final String pid;
  final String name;
  final double cpuPercentage;
  final double memoryPercentage;
  final String memoryUsage;
  final String user;
  final String status;

  ProcessNode({
    required this.pid,
    required this.name,
    required this.cpuPercentage,
    required this.memoryPercentage,
    required this.memoryUsage,
    required this.user,
    required this.status,
  });

  /// Parsea una línea del comando:
  /// ps aux --sort=-%cpu | awk 'NR>1 {printf "%s|%s|%s|%s|%s|%s\n",$1,$2,$3,$4,$6,$11}'
  /// Formato: USER|PID|%CPU|%MEM|RSS_KB|COMMAND
  factory ProcessNode.fromRawLine(String line) {
    final parts = line.split('|');
    if (parts.length < 6) {
      return ProcessNode(
        pid: '?',
        name: line,
        cpuPercentage: 0,
        memoryPercentage: 0,
        memoryUsage: '?',
        user: '?',
        status: '?',
      );
    }

    final rssKb = int.tryParse(parts[4].trim()) ?? 0;
    final memMb = (rssKb / 1024).toStringAsFixed(1);

    // Acortar el nombre del proceso (quitar path completo)
    final rawName = parts[5].trim();
    final shortName = rawName.contains('/')
        ? rawName.split('/').last
        : rawName;

    return ProcessNode(
      user: parts[0].trim(),
      pid: parts[1].trim(),
      cpuPercentage: double.tryParse(parts[2].trim()) ?? 0.0,
      memoryPercentage: double.tryParse(parts[3].trim()) ?? 0.0,
      memoryUsage: '$memMb MB',
      name: shortName,
      status: 'running',
    );
  }
}