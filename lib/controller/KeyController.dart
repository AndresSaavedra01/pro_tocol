import 'package:isar/isar.dart';
import 'package:pro_tocol/model/entities/DataBaseEntities.dart';
import 'package:pro_tocol/model/services/SSHService.dart';

import '../logic/rsa_generator.dart';
import 'SshKeyFormatter.dart';

class KeyController {
  final Isar isar;
  final SSHService sshService;

  KeyController({required this.isar, required this.sshService});

  /// Genera un nuevo par de llaves y lo guarda en Isar
  Future<PairKeys> generateKeyPair(String name) async {
    final generator = RSAGenerator();
    final keyPair = generator.generateKeyPair(bitLength: 2048);

    final publicKeyStr = SshKeyFormatter.toOpenSshFormat(keyPair.publicKey, comment: 'ProTocol-$name');
    final privateKeyStr = SshKeyFormatter.toPkcs1PrivateKeyPem(keyPair.privateKey);

    final newKey = PairKeys()
      ..name = name
      ..publicKeyOpenSsh = publicKeyStr
      ..privateKeyPem = privateKeyStr
      ..createdAt = DateTime.now();

    await isar.writeTxn(() async {
      // FIX: Usar collection<PairKeys>() es inmune a errores de nombrado de Isar
      await isar.collection<PairKeys>().put(newKey);
    });

    return newKey;
  }

  /// Asocia la llave al servidor configurado y sube la pública mediante contraseña temporal
  Future<bool> associateKeyToServer(PairKeys pairKey, ServerConfig server, String currentPassword) async {
    // Almacenamos temporalmente la contraseña para la conexión inicial
    server.password = currentPassword;

    final conectado = await sshService.connect(server);
    if (!conectado) return false;

    try {
      final bashCommand = '''
mkdir -p ~/.ssh && chmod 700 ~/.ssh
echo '${pairKey.publicKeyOpenSsh}' >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
'''.trim();

      final response = await sshService.runSingleCommand(bashCommand);

      if (response.toLowerCase().contains('error') || response.toLowerCase().contains('denied')) {
        throw Exception('El servidor rechazó la instalación: $response');
      }

      // Si todo sale bien, guardamos la relación de Isar localmente
      await isar.writeTxn(() async {
        server.password = null; // Remover contraseña por seguridad
        server.keyPair.value = pairKey;
        // FIX: Usar collection<ServerConfig>()
        await isar.collection<ServerConfig>().put(server);
        await server.keyPair.save();
      });

      return true;
    } finally {
      if (sshService.isConnected) {
        sshService.disconnect();
      }
    }
  }

  /// Elimina por completo las llaves del servidor y de la base de datos local
  Future<void> deleteKeyPairFromServer(ServerConfig server, PairKeys pairKey) async {
    await isar.writeTxn(() async {
      // Desvincular del servidor
      server.keyPair.value = null;
      await isar.collection<ServerConfig>().put(server);
      await server.keyPair.save();

      // Eliminar el registro físico de la colección de llaves
      await isar.collection<PairKeys>().delete(pairKey.id);
    });
  }

  /// Importa una llave privada externa (texto o archivo) y la convierte en entidad Isar
  Future<PairKeys> importKeyPair(String name, String privateKeyPem) async {
    final newKey = PairKeys()
      ..name = name
      ..publicKeyOpenSsh = '' // No es estrictamente necesaria para conectarnos como clientes
      ..privateKeyPem = privateKeyPem.trim()
      ..createdAt = DateTime.now();

    await isar.writeTxn(() async {
      await isar.collection<PairKeys>().put(newKey);
    });

    return newKey;
  }
}