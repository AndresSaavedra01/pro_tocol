

import 'package:pro_tocol/model/entities/GeneralConfig.dart';

class TempSessionConfig implements GeneralConfig {
  @override
  String host;
  @override
  String username;
  @override
  int port;
  @override
  String? password;
  @override
  String? keyPairId;

  TempSessionConfig({
    required this.host,
    required this.username,
    this.port = 22,
    required this.password,
    this.keyPairId
  });
}