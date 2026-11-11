import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ir_mobile/services/api_service.dart';

http.Response profile(int points) =>
    http.Response(jsonEncode({'points': points}), 200);

void main() {
  test('Concurrent identical reads share a request and completed reads refresh',
      () async {
    var requests = 0;
    final pending = Completer<http.Response>();
    final started = Completer<void>();
    final api = ApiService(client: MockClient((request) {
      requests++;
      if (requests == 1) {
        started.complete();
        return pending.future;
      }
      return Future.value(profile(requests));
    }));
    final first = api.getDriverMe();
    await started.future;
    final second = api.getDriverMe();
    pending.complete(profile(10));
    final values = await Future.wait([first, second]);
    expect(requests, 1);
    expect(values.map((value) => value['points']), [10, 10]);
    expect(identical(values[0], values[1]), isFalse);
    expect((await api.getDriverMe())['points'], 2);
    expect(requests, 2);
  });

  test('Reads with different authentication never share data', () async {
    final pending = <String, Completer<http.Response>>{};
    final api = ApiService(client: MockClient((request) {
      final key = request.headers['authorization']!;
      return (pending[key] = Completer<http.Response>()).future;
    }));
    api.token = 'first-session';
    final first = api.getDriverMe();
    await Future<void>.delayed(Duration.zero);
    api.token = 'second-session';
    final second = api.getDriverMe();
    await Future<void>.delayed(Duration.zero);
    expect(pending.length, 2);
    pending['Token first-session']!.complete(profile(1));
    pending['Token second-session']!.complete(profile(2));
    expect((await first)['points'], 1);
    expect((await second)['points'], 2);
  });

  test('A failed read is removed and the next attempt can succeed', () async {
    var requests = 0;
    final api = ApiService(client: MockClient((request) async {
      if (++requests == 1) throw http.ClientException('offline');
      return profile(20);
    }));
    await expectLater(api.getDriverMe(), throwsA(isA<ApiException>()));
    expect((await api.getDriverMe())['points'], 20);
    expect(requests, 2);
  });

  test('Refresh after a write does not join a read from before that write',
      () async {
    var reads = 0;
    final pending = Completer<http.Response>();
    final started = Completer<void>();
    final api = ApiService(client: MockClient((request) {
      if (request.method == 'PATCH') {
        return Future.value(http.Response('{}', 200));
      }
      if (++reads == 1) {
        started.complete();
        return pending.future;
      }
      return Future.value(profile(2));
    }));
    final oldRead = api.getDriverMe();
    await started.future;
    await api.updateDriverStatus('available');
    expect((await api.getDriverMe())['points'], 2);
    pending.complete(profile(1));
    expect((await oldRead)['points'], 1);
    expect(reads, 2);
  });

  test('Photo upload uses the provided client and invalidates preceding reads',
      () async {
    var reads = 0;
    final pending = Completer<http.Response>();
    final started = Completer<void>();
    final api = ApiService(client: MockClient((request) {
      if (request.method == 'POST') {
        return Future.value(
            http.Response('{"photo_url":"https://ir.test/photo.png"}', 200));
      }
      if (++reads == 1) {
        started.complete();
        return pending.future;
      }
      return Future.value(profile(2));
    }));
    final beforeUpload = api.getDriverMe();
    await started.future;
    expect(
        await api.uploadProfilePhoto(
            bytes: Uint8List.fromList([1, 2, 3]), filename: 'test.png'),
        'https://ir.test/photo.png');
    expect((await api.getDriverMe())['points'], 2);
    pending.complete(profile(1));
    await beforeUpload;
    expect(reads, 2);
  });
}
