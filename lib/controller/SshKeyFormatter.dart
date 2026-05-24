import 'dart:convert';
import 'dart:typed_data';
import '../logic/rsa_generator.dart';

class SshKeyFormatter {
  /// Convierte una RSAPublicKey al formato estándar de servidor: "ssh-rsa AAAAB3..."
  static String toOpenSshFormat(RSAPublicKey key, {String comment = 'pro-tocol-key'}) {
    final List<int> buffer = [];
    buffer.addAll(_encodeString('ssh-rsa'));
    buffer.addAll(_encodeMpint(key.e));
    buffer.addAll(_encodeMpint(key.n));
    return 'ssh-rsa ${base64.encode(buffer)} $comment';
  }

  /// Convierte una RSAPrivateKey al formato estándar PKCS#1 PEM requerido por dartssh2
  static String toPkcs1PrivateKeyPem(RSAPrivateKey key, {BigInt? publicExponent}) {
    final List<int> inner = [];
    final e = publicExponent ?? key.e ?? BigInt.from(65537);
    final p = key.p ?? BigInt.zero;
    final q = key.q ?? BigInt.zero;

    // Calcular exponentes de agilización (requeridos por la estructura PKCS#1)
    final dmp1 = (p > BigInt.one) ? key.d % (p - BigInt.one) : BigInt.zero;
    final dmq1 = (q > BigInt.one) ? key.d % (q - BigInt.one) : BigInt.zero;
    final iqmp = (q > BigInt.zero && p > BigInt.zero) ? q.modInverse(p) : BigInt.zero;

    // Construir la secuencia ASN.1 de enteros
    inner.addAll(_encodeDerInteger(BigInt.zero)); // Version 0
    inner.addAll(_encodeDerInteger(key.n));       // Módulo (n)
    inner.addAll(_encodeDerInteger(e));           // Exponente Público (e)
    inner.addAll(_encodeDerInteger(key.d));       // Exponente Privado (d)
    inner.addAll(_encodeDerInteger(p));           // Primo 1 (p)
    inner.addAll(_encodeDerInteger(q));           // Primo 2 (q)
    inner.addAll(_encodeDerInteger(dmp1));        // Exponente 1 (d mod p-1)
    inner.addAll(_encodeDerInteger(dmq1));        // Exponente 2 (d mod q-1)
    inner.addAll(_encodeDerInteger(iqmp));        // Coeficiente (q^-1 mod p)

    final List<int> seq = [0x30, ..._encodeDerLength(inner.length), ...inner];
    final base64Str = base64.encode(seq);

    // Dividir en líneas de 64 caracteres por estándar PEM
    final chunks = [];
    for (int i = 0; i < base64Str.length; i += 64) {
      int end = i + 64;
      if (end > base64Str.length) end = base64Str.length;
      chunks.add(base64Str.substring(i, end));
    }

    return [
      '-----BEGIN RSA PRIVATE KEY-----',
      ...chunks,
      '-----END RSA PRIVATE KEY-----'
    ].join('\n');
  }

  static List<int> _encodeString(String text) {
    final bytes = utf8.encode(text);
    final lengthHeader = ByteData(4)..setUint32(0, bytes.length, Endian.big);
    return [...lengthHeader.buffer.asUint8List(), ...bytes];
  }

  static List<int> _encodeMpint(BigInt number) {
    var hex = number.toRadixString(16);
    if (hex.length % 2 != 0) hex = '0$hex';
    final List<int> bytes = [];
    for (int i = 0; i < hex.length; i += 2) {
      bytes.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    if (bytes.isNotEmpty && (bytes[0] & 0x80) != 0) {
      bytes.insert(0, 0x00);
    }
    final lengthHeader = ByteData(4)..setUint32(0, bytes.length, Endian.big);
    return [...lengthHeader.buffer.asUint8List(), ...bytes];
  }

  static List<int> _encodeDerInteger(BigInt number) {
    var hex = number.toRadixString(16);
    if (hex.length % 2 != 0) hex = '0$hex';
    List<int> bytes = [];
    for (int i = 0; i < hex.length; i += 2) {
      bytes.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    if (bytes.isNotEmpty && (bytes[0] & 0x80) != 0) {
      bytes.insert(0, 0x00);
    }
    if (bytes.isEmpty) bytes = [0];
    return [0x02, ..._encodeDerLength(bytes.length), ...bytes];
  }

  static List<int> _encodeDerLength(int length) {
    if (length < 128) return [length];
    List<int> lenBytes = [];
    int temp = length;
    while (temp > 0) {
      lenBytes.insert(0, temp & 0xFF);
      temp >>= 8;
    }
    return [0x80 | lenBytes.length, ...lenBytes];
  }
}