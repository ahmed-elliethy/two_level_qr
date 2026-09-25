import '../domain/ecc_codewords.dart';
import '../domain/ports.dart';
import 'galois_field.dart';

/// Exception thrown when Reed-Solomon decoding fails due to too many errors.
class ReedSolomonException implements Exception {
  ReedSolomonException(this.message);
  final String message;
  @override
  String toString() => 'ReedSolomonException: $message';
}

/// Reed-Solomon encoder and decoder for QR Code symbols.
class ReedSolomonCodec implements ReedSolomonCodecPort {
  ReedSolomonCodec([GaloisField256? field]) : _gf = field ?? GaloisField256.instance;

  final GaloisField256 _gf;

  @override
  EccCodewords generateEcc({
    required List<int> data,
    required int eccCodewordsCount,
  }) {
    if (eccCodewordsCount <= 0) {
      return EccCodewords(const []);
    }
    final generator = _gf.generatorPolynomial(eccCodewordsCount);
    // info coefficients shifted by eccCodewordsCount
    final info = List<int>.filled(data.length + eccCodewordsCount, 0);
    info.setRange(0, data.length, data);

    for (var i = 0; i < data.length; i++) {
      final lead = info[i];
      if (lead != 0) {
        for (var j = 0; j < generator.length; j++) {
          info[i + j] ^= _gf.multiply(generator[j], lead);
        }
      }
    }

    final ecc = info.sublist(data.length);
    return EccCodewords(ecc);
  }

  @override
  ({List<int> data, int errorsCorrected}) correctBlock({
    required List<int> received,
    required int dataCodewordsCount,
    required int eccCodewordsCount,
  }) {
    final n = received.length;
    if (n != dataCodewordsCount + eccCodewordsCount) {
      throw ArgumentError(
        'Received length $n does not match data ($dataCodewordsCount) + ECC ($eccCodewordsCount)',
      );
    }

    // 1. Calculate syndromes S_0 ... S_{2t-1} where S_i = r(alpha^i)
    // r(x) = received[0]*x^(n-1) + ... + received[n-1]
    final syndromes = List<int>.filled(eccCodewordsCount, 0);
    var hasError = false;
    for (var i = 0; i < eccCodewordsCount; i++) {
      final s = _gf.evaluatePoly(received, _gf.exp(i));
      syndromes[i] = s;
      if (s != 0) hasError = true;
    }

    if (!hasError) {
      return (
        data: received.sublist(0, dataCodewordsCount),
        errorsCorrected: 0,
      );
    }

    // 2. Berlekamp-Massey Algorithm to find Error Locator Polynomial Lambda(x)
    var lambda = <int>[1]; // Lambda(x) = 1
    var b = <int>[1];      // B(x) = 1
    var l = 0;             // Number of errors detected so far
    var m = 1;             // Iteration offset

    for (var k = 0; k < eccCodewordsCount; k++) {
      // Compute discrepancy delta_k = sum_{j=0}^l (lambda_j * S_{k-j})
      var delta = syndromes[k];
      for (var j = 1; j <= l && j < lambda.length; j++) {
        delta ^= _gf.multiply(lambda[j], syndromes[k - j]);
      }

      if (delta == 0) {
        m++;
      } else {
        final t = List<int>.from(lambda);
        // lambda = lambda - delta * x^m * B(x)
        final scaledB = _gf.scalePoly(b, delta);
        final shiftedScaledB = <int>[...List<int>.filled(m, 0), ...scaledB];

        // Pad lambda or shiftedScaledB to equal length for XOR
        final maxLen = shiftedScaledB.length > lambda.length ? shiftedScaledB.length : lambda.length;
        final newLambda = List<int>.filled(maxLen, 0, growable: true);
        for (var i = 0; i < lambda.length; i++) {
          newLambda[i] ^= lambda[i];
        }
        for (var i = 0; i < shiftedScaledB.length; i++) {
          newLambda[i] ^= shiftedScaledB[i];
        }
        // Trim trailing zeros from right if any (highest degree is at right in this representation)
        while (newLambda.length > 1 && newLambda.last == 0) {
          newLambda.removeLast();
        }
        lambda = newLambda;

        if (2 * l <= k) {
          l = k + 1 - l;
          b = _gf.scalePoly(t, _gf.inverse(delta));
          m = 1;
        } else {
          m++;
        }
      }
    }

    final numErrors = l;
    if (numErrors > eccCodewordsCount ~/ 2) {
      throw ReedSolomonException('Too many errors to correct (detected $numErrors, max ${eccCodewordsCount ~/ 2})');
    }

    // 3. Chien Search to find error positions
    // Error locations: find X_k = alpha^(n-1-pos) such that Lambda(X_k^-1) = 0
    final errorPositions = <int>[];
    final errorLocators = <int>[];

    for (var pos = 0; pos < n; pos++) {
      final power = n - 1 - pos;
      final xInv = _gf.exp((255 - power) % 255);
      // Evaluate Lambda(xInv) where lambda = [lambda_0, lambda_1, ... lambda_l]
      var val = 0;
      var xPow = 1;
      for (var j = 0; j < lambda.length; j++) {
        val ^= _gf.multiply(lambda[j], xPow);
        xPow = _gf.multiply(xPow, xInv);
      }
      if (val == 0) {
        errorPositions.add(pos);
        errorLocators.add(_gf.exp(power)); // X_k
      }
    }

    if (errorPositions.length != numErrors) {
      throw ReedSolomonException('Chien search found ${errorPositions.length} roots, expected $numErrors');
    }

    // 4. Forney Algorithm to calculate error values
    // Omega(x) = (S(x) * Lambda(x)) mod x^(eccCodewordsCount)
    final sPoly = syndromes; // [S_0, S_1, ...]
    final omega = List<int>.filled(eccCodewordsCount, 0);
    for (var i = 0; i < eccCodewordsCount; i++) {
      for (var j = 0; j < lambda.length; j++) {
        if (i + j < eccCodewordsCount) {
          omega[i + j] ^= _gf.multiply(sPoly[i], lambda[j]);
        }
      }
    }

    // Correct received codewords
    final corrected = List<int>.from(received);
    for (var k = 0; k < numErrors; k++) {
      final pos = errorPositions[k];
      final xk = errorLocators[k];
      final xkInv = _gf.inverse(xk);

      // Evaluate Omega(xkInv)
      var omegaVal = 0;
      var xPow = 1;
      for (var j = 0; j < omega.length; j++) {
        omegaVal ^= _gf.multiply(omega[j], xPow);
        xPow = _gf.multiply(xPow, xkInv);
      }

      // Evaluate formal derivative Lambda'(xkInv) = sum_{j odd} lambda_j * (xkInv)^(j-1)
      var lambdaPrimeVal = 0;
      xPow = 1;
      for (var j = 1; j < lambda.length; j += 2) {
        final term = _gf.multiply(lambda[j], xPow);
        lambdaPrimeVal ^= term;
        xPow = _gf.multiply(xPow, _gf.multiply(xkInv, xkInv)); // step by 2
      }

      if (lambdaPrimeVal == 0) {
        throw ReedSolomonException('Formal derivative Lambda prime evaluated to 0');
      }

      final errorValue = _gf.multiply(xk, _gf.divide(omegaVal, lambdaPrimeVal));
      corrected[pos] ^= errorValue;
    }

    // 5. Verify syndrome of corrected data is all zero
    for (var i = 0; i < eccCodewordsCount; i++) {
      if (_gf.evaluatePoly(corrected, _gf.exp(i)) != 0) {
        throw ReedSolomonException('Error correction verification failed (syndrome non-zero)');
      }
    }

    return (
      data: corrected.sublist(0, dataCodewordsCount),
      errorsCorrected: numErrors,
    );
  }
}
