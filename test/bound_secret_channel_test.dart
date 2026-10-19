import 'package:crypto_wallet/data/wallet/secure_pin_store.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The Dart half of the fingerprint-bound store, against a scripted native side.
/// (The Kotlin half — `BoundSecret.kt` — needs a device; see the README.)
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const MethodChannel channel = MethodChannel('material_wallet/bound_secret');
  const SecurePinStore store = SecurePinStore();

  late List<MethodCall> calls;

  void native(Future<Object?> Function(MethodCall call) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) {
      calls.add(call);
      return handler(call);
    });
  }

  setUp(() {
    calls = <MethodCall>[];
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('is supported only when the device reports a usable fingerprint',
      () async {
    native((_) async => 'ok');
    expect(await store.isSupported, isTrue);

    native((_) async => 'none_enrolled');
    expect(await store.isSupported, isFalse);

    native((_) async => throw MissingPluginException());
    expect(await store.isSupported, isFalse);
  });

  test('a stored password sets the flag; reading needs the native prompt',
      () async {
    native((MethodCall call) async => null);
    expect(await store.hasPin, isFalse);

    expect(await store.write('hunter22'), isTrue);
    expect(await store.hasPin, isTrue);
    expect(calls.single.method, 'write');
    expect((calls.single.arguments as Map)['secret'], 'hunter22');

    native((MethodCall call) async => call.method == 'read' ? 'hunter22' : null);
    expect(await store.read(), 'hunter22');
  });

  test('a cancelled write stores nothing and leaves no flag', () async {
    native((MethodCall call) async {
      if (call.method == 'write') {
        throw PlatformException(code: 'cancelled', message: 'user cancelled');
      }
      return null;
    });
    expect(await store.write('hunter22'), isFalse);
    expect(await store.hasPin, isFalse);
    // The half-created key is removed again.
    expect(calls.map((MethodCall c) => c.method), contains('clear'));
  });

  test('a cancelled read is null and keeps the stored password', () async {
    native((MethodCall call) async => null);
    await store.write('hunter22');

    native((MethodCall call) async {
      throw PlatformException(code: 'cancelled', message: 'user cancelled');
    });
    expect(await store.read(), isNull);
    expect(await store.hasPin, isTrue);
  });

  test('an invalidated key clears everything and says so', () async {
    native((MethodCall call) async => null);
    await store.write('hunter22');

    native((MethodCall call) async {
      if (call.method == 'read') {
        throw PlatformException(code: 'invalidated', message: 'changed');
      }
      return null;
    });
    await expectLater(store.read(), throwsA(isA<BoundSecretInvalidated>()));
    expect(await store.hasPin, isFalse);
  });

  test('clear forgets the secret natively and drops the flag', () async {
    native((MethodCall call) async => null);
    await store.write('hunter22');
    await store.clear();

    expect(calls.map((MethodCall c) => c.method), contains('clear'));
    expect(await store.hasPin, isFalse);
  });
}
