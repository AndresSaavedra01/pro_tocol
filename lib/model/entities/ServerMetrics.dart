class ServerMetrics {
  final double cpuUsage;
  final int usedRam;
  final int totalRam;
  final String diskUsage;
  final DateTime timestamp;

  // Red
  final String downloadSpeed;
  final String uploadSpeed;
  final String ipv4;

  ServerMetrics({
    required this.cpuUsage,
    required this.usedRam,
    required this.totalRam,
    required this.diskUsage,
    required this.timestamp,
    this.downloadSpeed = '—',
    this.uploadSpeed = '—',
    this.ipv4 = '—',
  });

  factory ServerMetrics.fromRawOutput(String raw) {
    final lines = raw.split('\n');
    return ServerMetrics(
      cpuUsage: double.tryParse(lines[0]) ?? 0.0,
      usedRam: int.tryParse(lines.length > 1 ? lines[1].split(' ')[0] : '0') ?? 0,
      totalRam: int.tryParse(lines.length > 1 ? lines[1].split(' ')[1] : '0') ?? 0,
      diskUsage: lines.length > 2 ? lines[2].trim() : '0%',
      timestamp: DateTime.now(),
    );
  }

  ServerMetrics copyWithNetwork({
    required String downloadSpeed,
    required String uploadSpeed,
    required String ipv4,
  }) {
    return ServerMetrics(
      cpuUsage: cpuUsage,
      usedRam: usedRam,
      totalRam: totalRam,
      diskUsage: diskUsage,
      timestamp: timestamp,
      downloadSpeed: downloadSpeed,
      uploadSpeed: uploadSpeed,
      ipv4: ipv4,
    );
  }
}