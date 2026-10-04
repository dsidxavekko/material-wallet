import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'pbkdf2_fallback.dart';

/// Derives a key with PBKDF2, preferring the browser's Web Crypto API.
///
/// `crypto.subtle` runs in native code, so it is non-blocking and orders of
/// magnitude faster than pure Dart on JavaScript — the 600k-iteration vault
/// key drops from tens of seconds to a few milliseconds.
///
/// When the page is not a secure context (`crypto.subtle` is `undefined`, e.g.
/// when the app is opened over plain HTTP on a LAN IP) this falls back to a
/// cooperative pure-Dart derivation that keeps the tab responsive.
Future<Uint8List> pbkdf2({
  required Pbkdf2Hash hash,
  required Uint8List password,
  required Uint8List salt,
  required int iterations,
  required int keyLength,
}) async {
  final _SubtleCrypto? subtle = _subtleCrypto();
  if (subtle == null) {
    return pbkdf2Chunked(hash, password, salt, iterations, keyLength);
  }

  final JSObject key = await subtle
      .importKey(
        'raw'.toJS,
        password.toJS,
        _parameters(<String, Object?>{'name': 'PBKDF2'}),
        false.toJS,
        <JSString>['deriveBits'.toJS].toJS,
      )
      .toDart;

  final JSArrayBuffer bits = await subtle
      .deriveBits(
        _parameters(<String, Object?>{
          'name': 'PBKDF2',
          'salt': salt,
          'iterations': iterations,
          'hash': hash == Pbkdf2Hash.sha512 ? 'SHA-512' : 'SHA-256',
        }),
        key,
        (keyLength * 8).toJS,
      )
      .toDart;

  return bits.toDart.asUint8List();
}

/// `crypto.subtle`, or `null` when the global or the property is missing.
_SubtleCrypto? _subtleCrypto() {
  final JSObject? crypto = _crypto;
  if (crypto == null) {
    return null;
  }
  final JSAny? subtle = crypto.getProperty<JSAny?>('subtle'.toJS);
  return subtle.isUndefinedOrNull ? null : _SubtleCrypto(subtle! as JSObject);
}

@JS('crypto')
external JSObject? get _crypto;

JSObject _parameters(Map<String, Object?> values) =>
    values.jsify()! as JSObject;

/// Minimal `SubtleCrypto` binding covering the two calls the wallet needs.
extension type _SubtleCrypto(JSObject _) implements JSObject {
  external JSPromise<JSObject> importKey(
    JSString format,
    JSAny keyData,
    JSObject algorithm,
    JSBoolean extractable,
    JSArray<JSString> keyUsages,
  );

  external JSPromise<JSArrayBuffer> deriveBits(
    JSObject algorithm,
    JSObject baseKey,
    JSNumber length,
  );
}
