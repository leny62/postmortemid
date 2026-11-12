import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postmortemid/capture/capture_controller.dart';
import 'package:postmortemid/data/field_upload.dart';
import 'package:postmortemid/data/models.dart';
import 'package:postmortemid/data/upload_client.dart';

import 'support.dart';

/// Stand-in for the study server: records requests and answers with [status].
class FakeServer {
  late HttpServer _server;
  final photos = <String, Map<String, Object?>>{};
  final animals = <String, Map<String, dynamic>>{};
  final auth = <String?>[];
  int Function(String path) status = (_) => 200;

  String get url => 'http://127.0.0.1:${_server.port}';

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen((req) async {
      final body = await req.fold<List<int>>([], (a, b) => a..addAll(b));
      auth.add(req.headers.value('authorization'));
      final code = status(req.uri.path);
      if (code == 200 && req.uri.path.startsWith('/v1/photos/')) {
        expect(req.headers.value('x-sha256'), sha256.convert(body).toString());
        photos[req.uri.path.substring('/v1/photos/'.length)] =
            jsonDecode(req.headers.value('x-meta')!) as Map<String, Object?>;
      } else if (code == 200) {
        animals[req.uri.pathSegments.last] = jsonDecode(utf8.decode(body)) as Map<String, dynamic>;
      }
      req.response.statusCode = code;
      await req.response.close();
    });
  }

  Future<void> stop() => _server.close(force: true);
}

void main() {
  late Directory tmp;
  late AppServices services;
  late FakeServer server;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('pmid_upload');
    services = await testServices(tmp, {
      'cow': [1.0, 0.0],
    });
    server = FakeServer();
    await server.start();
  });

  tearDown(() async {
    await server.stop();
    await tmp.delete(recursive: true);
  });

  Future<Animal> collect(String code, int photos, {String? earTag}) async {
    final a = await services.repository.addAnimal(
      Animal(
        studyCode: code,
        externalId: earTag,
        linkageStatus: LinkageStatus.confirmed,
        createdAt: DateTime(2026, 11, 13),
      ),
    );
    final c = CaptureController(services);
    await c.startCollection(a, TimePoint.t0, Modality.muzzle);
    for (var i = 0; i < photos; i++) {
      final f = File('${tmp.path}/cow_$code$i.jpg')..writeAsBytesSync([i, 1, 2]);
      await c.addImage(f.path, move: true);
    }
    return a;
  }

  Future<UploadResult> upload([String token = 'tok']) async {
    final client = UploadClient(server.url, token);
    try {
      return await uploadPending(services.repository, client, 'Tecno Spark é');
    } finally {
      client.close();
    }
  }

  test('pending photos and animal logs go up once, with key, checksum and log', () async {
    final a = await collect('PM-A01', 2, earTag: 'RW-TAG-9');
    await services.repository.updateFieldLog(
      a.id!,
      FieldLog(slaughterTime: DateTime(2026, 11, 13, 9, 40), headWashed: false),
    );

    final first = await upload();
    expect((first.uploaded, first.remaining, first.error), (2, 0, null));
    expect(server.photos.keys, everyElement(startsWith('PM-A01/L/muzzle/')));
    expect(server.photos.values.first['device_model'], 'Test Phone');
    expect(server.auth, everyElement('Bearer tok'));
    expect(server.animals['PM-A01'], {
      'linkage_status': 'confirmed',
      'slaughter_time': '2026-11-13T09:40:00.000',
      'head_washed': 'no',
      'nose_condition': null,
      'notes': null,
      'device_model': 'Tecno Spark é',
    });
    expect(jsonEncode(server.animals), isNot(contains('RW-TAG-9')));

    server.photos.clear();
    final again = await upload();
    expect(again.uploaded, 0);
    expect(server.photos, isEmpty);
  });

  test('a failure stops the upload and leaves the rest queued for later', () async {
    await collect('PM-A02', 3);
    var calls = 0;
    server.status = (path) => path.startsWith('/v1/photos/') && ++calls == 2 ? 500 : 200;

    final first = await upload();
    expect((first.uploaded, first.remaining), (1, 2));
    expect(first.error, contains('500'));

    final retry = await upload();
    expect((retry.uploaded, retry.remaining, retry.error), (2, 0, null));
    expect(server.photos, hasLength(3));
  });

  test('a rejected key uploads nothing and says why', () async {
    await collect('PM-A03', 1);
    server.status = (_) => 401;
    final result = await upload('wrong');
    expect((result.uploaded, result.remaining), (0, 1));
    expect(result.error, contains('upload key'));
  });

  test('no server gives a plain connection message', () async {
    await collect('PM-A04', 1);
    final url = server.url;
    await server.stop();
    final client = UploadClient(url, 'tok');
    final result = await uploadPending(services.repository, client, 'Test Phone');
    client.close();
    expect(result.error, contains('No connection'));
  });
}
