import 'dart:math';
import 'dart:typed_data';

class RSAPublicKey {
  final BigInt e;
  final BigInt n;

  const RSAPublicKey({
    required this.e,
    required this.n,
  });
}

class RSAPrivateKey {
  final BigInt d;
  final BigInt n;
  final BigInt? e;
  final BigInt? p;
  final BigInt? q;

  const RSAPrivateKey({
    required this.d,
    required this.n,
    this.e,
    this.p,
    this.q,
  });
}

class RSAKeyPair {
  final RSAPublicKey publicKey;
  final RSAPrivateKey privateKey;

  const RSAKeyPair({
    required this.publicKey,
    required this.privateKey,
  });
}

class RSAGenerator {
  static final BigInt _zero = BigInt.zero;
  static final BigInt _one = BigInt.one;
  static final BigInt _two = BigInt.from(2);
  static final BigInt _publicExponent = BigInt.from(65537);

  final Random _secureRandom;
  final int millerRabinRounds;

  RSAGenerator({
    Random? random,
    this.millerRabinRounds = 40,
  }) : _secureRandom = random ?? Random.secure();

  RSAKeyPair generateKeyPair({int bitLength = 2048}) {
    if (bitLength < 32) {
      throw ArgumentError('bitLength debe ser al menos 32.');
    }

    if (millerRabinRounds < 1) {
      throw ArgumentError('millerRabinRounds debe ser mayor que cero.');
    }

    final pBits = bitLength ~/ 2;
    final qBits = bitLength - pBits;

    while (true) {
      final p = _generateProbablePrime(pBits);
      BigInt q = _generateProbablePrime(qBits);

      while (q == p) {
        q = _generateProbablePrime(qBits);
      }

      final n = p * q;
      if (n.bitLength != bitLength) {
        continue;
      }

      final phi = (p - _one) * (q - _one);

      if (_gcd(_publicExponent, phi) != _one) {
        continue;
      }

      final d = _modInverse(_publicExponent, phi);

      return RSAKeyPair(
        publicKey: RSAPublicKey(e: _publicExponent, n: n),
        privateKey: RSAPrivateKey(
          d: d,
          n: n,
          e: _publicExponent,
          p: p,
          q: q,
        ),
      );
    }
  }

  BigInt _generateProbablePrime(int bitLength) {
    while (true) {
      final candidate = _randomOddBigInt(bitLength);
      if (_isProbablePrime(candidate, rounds: millerRabinRounds)) {
        return candidate;
      }
    }
  }

  bool _isProbablePrime(BigInt n, {required int rounds}) {
    if (n < _two) return false;
    if (n == _two || n == BigInt.from(3)) return true;
    if (n.isEven) return false;

    final nMinusOne = n - _one;
    BigInt d = nMinusOne;
    int s = 0;

    // Miller-Rabin: n-1 = 2^s * d, con d impar.
    while (d.isEven) {
      d = d >> 1;
      s++;
    }

    for (int i = 0; i < rounds; i++) {
      final a = _randomInRange(_two, n - _two);
      BigInt x = a.modPow(d, n);

      if (x == _one || x == nMinusOne) {
        continue;
      }

      bool witnessFound = true;
      for (int r = 1; r < s; r++) {
        x = (x * x) % n;
        if (x == nMinusOne) {
          witnessFound = false;
          break;
        }
      }

      if (witnessFound) {
        return false;
      }
    }

    return true;
  }

  BigInt _modInverse(BigInt a, BigInt m) {
    // Euclides Extendido: encuentra x,y tal que a*x + m*y = gcd(a,m).
    final result = _extendedGcd(a, m);
    if (result.gcd != _one) {
      throw StateError('No existe inverso modular para los valores dados.');
    }

    BigInt x = result.x % m;
    if (x < _zero) {
      x += m;
    }
    return x;
  }

  _ExtendedGcdResult _extendedGcd(BigInt a, BigInt b) {
    BigInt oldR = a;
    BigInt r = b;
    BigInt oldS = _one;
    BigInt s = _zero;
    BigInt oldT = _zero;
    BigInt t = _one;

    while (r != _zero) {
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

  BigInt _gcd(BigInt a, BigInt b) {
    BigInt x = a.abs();
    BigInt y = b.abs();
    while (y != _zero) {
      final temp = x % y;
      x = y;
      y = temp;
    }
    return x;
  }

  BigInt _randomOddBigInt(int bitLength) {
    final byteLength = (bitLength + 7) >> 3;
    final bytes = Uint8List(byteLength);

    for (int i = 0; i < byteLength; i++) {
      bytes[i] = _secureRandom.nextInt(256);
    }

    final extraBits = (byteLength * 8) - bitLength;
    if (extraBits > 0) {
      final mask = 0xFF >> extraBits;
      bytes[0] &= mask;
    }

    final highestBitIndex = 7 - extraBits;
    bytes[0] |= (1 << highestBitIndex);
    bytes[bytes.length - 1] |= 1;

    return _bytesToBigInt(bytes);
  }

  BigInt _randomInRange(BigInt minInclusive, BigInt maxInclusive) {
    if (minInclusive > maxInclusive) {
      throw ArgumentError('Rango inválido para generación aleatoria.');
    }

    final range = (maxInclusive - minInclusive) + _one;
    return minInclusive + _randomBelow(range);
  }

  BigInt _randomBelow(BigInt upperExclusive) {
    if (upperExclusive <= _zero) {
      throw ArgumentError('upperExclusive debe ser mayor que cero.');
    }

    final bitLength = upperExclusive.bitLength;
    while (true) {
      final candidate = _randomBigIntWithBitLength(bitLength);
      if (candidate < upperExclusive) {
        return candidate;
      }
    }
  }

  BigInt _randomBigIntWithBitLength(int bitLength) {
    final byteLength = (bitLength + 7) >> 3;
    final bytes = Uint8List(byteLength);

    for (int i = 0; i < byteLength; i++) {
      bytes[i] = _secureRandom.nextInt(256);
    }

    final extraBits = (byteLength * 8) - bitLength;
    if (extraBits > 0) {
      final mask = 0xFF >> extraBits;
      bytes[0] &= mask;
    }

    return _bytesToBigInt(bytes);
  }

  BigInt _bytesToBigInt(Uint8List bytes) {
    BigInt result = _zero;
    for (final byte in bytes) {
      result = (result << 8) | BigInt.from(byte);
    }
    return result;
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
