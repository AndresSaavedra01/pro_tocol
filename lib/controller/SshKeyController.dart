
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pro_tocol/logic/rsa_generator.dart' as local_rsa;
import 'package:pro_tocol/model/entities/DataBaseEntities.dart';
import 'package:pro_tocol/model/services/SSHService.dart';

class SshKeyController {
  static const String _pemPrivateBegin = '-----BEGIN PRIVATE KEY-----';
  static const String _pemPrivateEnd = '-----END PRIVATE KEY-----';
  static const String _pemRsaPrivateBegin = '-----BEGIN RSA PRIVATE KEY-----';
  static const String _pemRsaPrivateEnd = '-----END RSA PRIVATE KEY-----';
  static const String _storageRecordType = 'protocol_rsa_key_v1';

  final FlutterSecureStorage _secureStorage;

  SshKeyController({FlutterSecureStorage? secureStorage})
      : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  /// Genera llaves, las instala en el servidor y devuelve el ID para guardar en BD
  Future<String> generateAndInstallKey(ServerConfig config) async {
    if (config.password == null || config.password!.isEmpty) {
      throw Exception("Se requiere la contraseña para instalar la llave.");
    }

    // 1. Generar llaves
    final rsaKeyPair = local_rsa.RSAGenerator().generateKeyPair(bitLength: 2048);
    final privateKeyPem = _encodeRsaPrivateKeyToPem(rsaKeyPair.privateKey);
    final publicKeyOpenSsh = _encodeToOpenSshPublicKey(rsaKeyPair.publicKey);

    // 2. Conectar temporalmente para instalar (usamos un servicio temporal para no ensuciar el Controller)
    final tempSshService = SSHService();
    try {
      await tempSshService.connect(config); // Aquí asume que usará el password

      final escapedPublicKey = publicKeyOpenSsh.replaceAll("'", "'\"'\"'");
      final command = "mkdir -p ~/.ssh && chmod 700 ~/.ssh && "
          "printf '%s\\n' '$escapedPublicKey' >> ~/.ssh/authorized_keys && "
          "chmod 600 ~/.ssh/authorized_keys";

      final result = await tempSshService.runSingleCommand(command);
      if (result.toLowerCase().contains("error") || result.toLowerCase().contains("denied")) {
        throw Exception("Error instalando llave en servidor: $result");
      }
    } finally {
      tempSshService.disconnect();
    }

    // 3. Guardar en Secure Storage
    final keyId = 'ssh_key_${DateTime.now().millisecondsSinceEpoch}';
    await _secureStorage.write(
      key: keyId,
      value: _encodeStoredKeyRecord(
        privateKeyPem: privateKeyPem,
        publicKeyOpenSsh: publicKeyOpenSsh,
      ),
    );

    return keyId;
  }

  /// Recupera la llave privada del almacenamiento seguro
  Future<String?> getPrivateKey(String keyId) async {
    final rawValue = await _secureStorage.read(key: keyId);
    if (rawValue == null) return null;

    final record = _tryDecodeStoredKeyRecord(rawValue);
    return record?.privateKeyPem ?? rawValue;
  }

  /// Obtiene la llave pública en formato OpenSSH a partir del ID de la privada
  Future<String?> getPublicKey(String keyId) async {
    final rawValue = await _secureStorage.read(key: keyId);
    if (rawValue == null) return null;

    final record = _tryDecodeStoredKeyRecord(rawValue);
    if (record != null) {
      return record.publicKeyOpenSsh;
    }

    try {
      return _tryDeriveOpenSshPublicKey(rawValue);
    } catch (e) {
      print("Error reconstruyendo pública: $e");
      return null;
    }
  }
  /// Elimina la llave (útil cuando se borra un servidor)
  Future<void> deleteKey(String keyId) async {
    await _secureStorage.delete(key: keyId);
  }

  /// Guarda una llave privada proporcionada manualmente por el usuario
  Future<String> saveManualKey(String privateKeyPem) async {
    if (privateKeyPem.isEmpty) throw Exception("La llave no puede estar vacía");

    final normalizedPem = privateKeyPem.trim();
    final derivedPublicKey = _tryDeriveOpenSshPublicKey(normalizedPem);

    // Generamos un ID único para esta llave manual
    final keyId = 'manual_key_${DateTime.now().millisecondsSinceEpoch}';
    await _secureStorage.write(
      key: keyId,
      value: derivedPublicKey == null
          ? normalizedPem
          : _encodeStoredKeyRecord(
              privateKeyPem: normalizedPem,
              publicKeyOpenSsh: derivedPublicKey,
            ),
    );
    return keyId;
  }

  // --- Helper Privado de Formateo (El que construimos antes) ---
  String _encodeToOpenSshPublicKey(local_rsa.RSAPublicKey publicKey) {
    final builder = BytesBuilder();
    void writeLength(int length) => builder.add([(length >> 24) & 0xFF, (length >> 16) & 0xFF, (length >> 8) & 0xFF, length & 0xFF]);
    void writeBytes(List<int> bytes) { writeLength(bytes.length); builder.add(bytes); }
    void writeBigInt(BigInt value) {
      var hexString = value.toRadixString(16);
      if (hexString.length % 2 != 0) hexString = '0$hexString';
      var bytes = List<int>.generate(hexString.length ~/ 2, (i) => int.parse(hexString.substring(i * 2, i * 2 + 2), radix: 16));
      if (bytes.isNotEmpty && (bytes[0] & 0x80) != 0) bytes = [0x00, ...bytes];
      writeBytes(bytes);
    }

    writeBytes(utf8.encode('ssh-rsa'));
    writeBigInt(publicKey.e);
    writeBigInt(publicKey.n);

    final base64Key = base64.encode(builder.toBytes());
    return 'ssh-rsa $base64Key protocol_app';
  }

  String _encodeRsaPrivateKeyToPem(local_rsa.RSAPrivateKey privateKey) {
    final p = privateKey.p;
    final q = privateKey.q;
    final e = privateKey.e;

    if (p == null || q == null || e == null) {
      throw Exception('La llave privada no contiene componentes CRT (p, q, e).');
    }

    final d = privateKey.d;
    final dP = d % (p - BigInt.one);
    final dQ = d % (q - BigInt.one);
    final qInv = _modInverse(q, p);

    final der = _derSequence([
      _derInteger(BigInt.zero),
      _derInteger(privateKey.n),
      _derInteger(e),
      _derInteger(d),
      _derInteger(p),
      _derInteger(q),
      _derInteger(dP),
      _derInteger(dQ),
      _derInteger(qInv),
    ]);

    final base64Body = base64.encode(der);
    final wrapped = _wrapAt64(base64Body);
    return '$_pemRsaPrivateBegin\n$wrapped\n$_pemRsaPrivateEnd';
  }

  String _encodeStoredKeyRecord({
    required String privateKeyPem,
    required String publicKeyOpenSsh,
  }) {
    return jsonEncode({
      'type': _storageRecordType,
      'privateKeyPem': privateKeyPem,
      'publicKeyOpenSsh': publicKeyOpenSsh,
    });
  }

  _StoredSshKeyRecord? _tryDecodeStoredKeyRecord(String rawValue) {
    try {
      final decoded = jsonDecode(rawValue);
      if (decoded is! Map<String, dynamic>) return null;
      if (decoded['type'] != _storageRecordType) return null;

      final privateKeyPem = decoded['privateKeyPem'];
      final publicKeyOpenSsh = decoded['publicKeyOpenSsh'];
      if (privateKeyPem is! String || publicKeyOpenSsh is! String) return null;

      return _StoredSshKeyRecord(
        privateKeyPem: privateKeyPem,
        publicKeyOpenSsh: publicKeyOpenSsh,
      );
    } catch (_) {
      return null;
    }
  }

  String? _tryDeriveOpenSshPublicKey(String privateKeyPem) {
    final publicKey = _tryExtractPublicKeyFromPem(privateKeyPem);
    if (publicKey == null) return null;
    return _encodeToOpenSshPublicKey(publicKey);
  }

  local_rsa.RSAPublicKey? _tryExtractPublicKeyFromPem(String privateKeyPem) {
    final trimmed = privateKeyPem.trim();

    if (trimmed.startsWith(_pemRsaPrivateBegin)) {
      final der = _pemToDer(trimmed, _pemRsaPrivateBegin, _pemRsaPrivateEnd);
      if (der == null) return null;
      return _parsePkcs1PrivateForPublic(der);
    }

    if (trimmed.startsWith(_pemPrivateBegin)) {
      final der = _pemToDer(trimmed, _pemPrivateBegin, _pemPrivateEnd);
      if (der == null) return null;
      return _parsePkcs8PrivateForPublic(der);
    }

    return null;
  }

  Uint8List? _pemToDer(String pem, String beginMarker, String endMarker) {
    final lines = const LineSplitter()
        .convert(pem)
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();

    if (lines.length < 3 || lines.first != beginMarker || lines.last != endMarker) {
      return null;
    }

    final base64Body = lines.sublist(1, lines.length - 1).join();
    try {
      return Uint8List.fromList(base64.decode(base64Body));
    } catch (_) {
      return null;
    }
  }

  local_rsa.RSAPublicKey? _parsePkcs8PrivateForPublic(Uint8List der) {
    try {
      final top = _DerReader(der).readElement();
      if (top.tag != 0x30) return null;

      final topReader = _DerReader(top.value);
      topReader.readElement(); // version
      topReader.readElement(); // algorithmIdentifier
      final privateKeyOctet = topReader.readElement();
      if (privateKeyOctet.tag != 0x04) return null;

      return _parsePkcs1PrivateForPublic(privateKeyOctet.value);
    } catch (_) {
      return null;
    }
  }

  local_rsa.RSAPublicKey? _parsePkcs1PrivateForPublic(Uint8List der) {
    try {
      final seq = _DerReader(der).readElement();
      if (seq.tag != 0x30) return null;

      final reader = _DerReader(seq.value);
      reader.readElement(); // version
      final modulusElement = reader.readElement();
      final exponentElement = reader.readElement();

      if (modulusElement.tag != 0x02 || exponentElement.tag != 0x02) {
        return null;
      }

      final modulus = _decodeDerInteger(modulusElement.value);
      final exponent = _decodeDerInteger(exponentElement.value);
      return local_rsa.RSAPublicKey(e: exponent, n: modulus);
    } catch (_) {
      return null;
    }
  }

  Uint8List _derSequence(List<Uint8List> parts) {
    final content = BytesBuilder();
    for (final part in parts) {
      content.add(part);
    }
    return _derElement(0x30, content.toBytes());
  }

  Uint8List _derInteger(BigInt value) {
    if (value < BigInt.zero) {
      throw ArgumentError('Solo se soportan enteros DER positivos.');
    }

    final bytes = _unsignedBigIntBytes(value);
    final normalized = bytes.isEmpty
        ? <int>[0x00]
        : ((bytes.first & 0x80) != 0 ? <int>[0x00, ...bytes] : bytes);

    return _derElement(0x02, Uint8List.fromList(normalized));
  }

  Uint8List _derElement(int tag, Uint8List value) {
    final builder = BytesBuilder();
    builder.addByte(tag);
    builder.add(_encodeDerLength(value.length));
    builder.add(value);
    return builder.toBytes();
  }

  Uint8List _encodeDerLength(int length) {
    if (length < 0x80) {
      return Uint8List.fromList([length]);
    }

    final octets = <int>[];
    int remaining = length;
    while (remaining > 0) {
      octets.insert(0, remaining & 0xFF);
      remaining >>= 8;
    }

    return Uint8List.fromList([0x80 | octets.length, ...octets]);
  }

  BigInt _decodeDerInteger(Uint8List bytes) {
    if (bytes.isEmpty) return BigInt.zero;

    int index = 0;
    while (index < bytes.length - 1 && bytes[index] == 0x00) {
      index++;
    }

    BigInt value = BigInt.zero;
    for (int i = index; i < bytes.length; i++) {
      value = (value << 8) | BigInt.from(bytes[i]);
    }

    return value;
  }

  List<int> _unsignedBigIntBytes(BigInt value) {
    if (value == BigInt.zero) {
      return const [0x00];
    }

    var hex = value.toRadixString(16);
    if (hex.length.isOdd) {
      hex = '0$hex';
    }

    final bytes = <int>[];
    for (int i = 0; i < hex.length; i += 2) {
      bytes.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return bytes;
  }

  BigInt _modInverse(BigInt a, BigInt m) {
    final result = _extendedGcd(a, m);
    if (result.gcd != BigInt.one) {
      throw Exception('No existe inverso modular para los valores dados.');
    }

    BigInt x = result.x % m;
    if (x < BigInt.zero) {
      x += m;
    }
    return x;
  }

  _ExtendedGcdResult _extendedGcd(BigInt a, BigInt b) {
    BigInt oldR = a;
    BigInt r = b;
    BigInt oldS = BigInt.one;
    BigInt s = BigInt.zero;
    BigInt oldT = BigInt.zero;
    BigInt t = BigInt.one;

    while (r != BigInt.zero) {
      final q = oldR ~/ r;

      final tempR = oldR - q * r;
      oldR = r;
      r = tempR;

      final tempS = oldS - q * s;
      oldS = s;
      s = tempS;

      final tempT = oldT - q * t;
      oldT = t;
      t = tempT;
    }

    return _ExtendedGcdResult(gcd: oldR, x: oldS, y: oldT);
  }

  String _wrapAt64(String value) {
    final buffer = StringBuffer();
    for (int i = 0; i < value.length; i += 64) {
      final end = (i + 64 < value.length) ? i + 64 : value.length;
      buffer.writeln(value.substring(i, end));
    }
    return buffer.toString().trimRight();
  }
}

class _StoredSshKeyRecord {
  final String privateKeyPem;
  final String publicKeyOpenSsh;

  const _StoredSshKeyRecord({
    required this.privateKeyPem,
    required this.publicKeyOpenSsh,
  });
}

class _DerElement {
  final int tag;
  final Uint8List value;

  const _DerElement({
    required this.tag,
    required this.value,
  });
}

class _DerReader {
  final Uint8List _bytes;
  int _offset = 0;

  _DerReader(this._bytes);

  _DerElement readElement() {
    if (_offset >= _bytes.length) {
      throw const FormatException('Fin inesperado en DER.');
    }

    final tag = _bytes[_offset++];
    final length = _readLength();
    if (_offset + length > _bytes.length) {
      throw const FormatException('Longitud DER inválida.');
    }

    final value = Uint8List.sublistView(_bytes, _offset, _offset + length);
    _offset += length;
    return _DerElement(tag: tag, value: value);
  }

  int _readLength() {
    if (_offset >= _bytes.length) {
      throw const FormatException('Longitud DER incompleta.');
    }

    final first = _bytes[_offset++];
    if ((first & 0x80) == 0) {
      return first;
    }

    final count = first & 0x7F;
    if (count == 0 || count > 4 || _offset + count > _bytes.length) {
      throw const FormatException('Longitud DER no soportada.');
    }

    int value = 0;
    for (int i = 0; i < count; i++) {
      value = (value << 8) | _bytes[_offset++];
    }
    return value;
  }
}

class _ExtendedGcdResult {
  final BigInt gcd;
  final BigInt x;
  final BigInt y;

  const _ExtendedGcdResult({
    required this.gcd,
    required this.x,
    required this.y,
  });
}