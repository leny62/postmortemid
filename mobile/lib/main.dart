import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'biometrics/model_manifest.dart';
import 'capture/capture_controller.dart';
import 'data/database.dart';
import 'data/local_repository.dart';
import 'ui/home_screen.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final docs = await getApplicationDocumentsDirectory();
  final imagesDir = await Directory(p.join(docs.path, 'images')).create(recursive: true);
  // Android: app-specific external storage, reachable with adb pull or a file manager.
  // iOS: the documents folder, shown in the Files app.
  final external = Platform.isAndroid ? await getExternalStorageDirectory() ?? docs : docs;
  final db = await openStudyDatabase(p.join(await getDatabasesPath(), 'postmortemid.db'));
  final package = await PackageInfo.fromPlatform();

  final services = AppServices(
    repository: LocalRepository(db),
    manifest: await ModelManifest.load(),
    imagesDir: imagesDir,
    exportsDir: Directory(p.join(external.path, 'exports')),
    deviceModel: await _deviceModel(),
    appVersion: '${package.version}+${package.buildNumber}',
  );
  runApp(PostMortemIdApp(services: services));
}

Future<String> _deviceModel() async {
  final device = DeviceInfoPlugin();
  if (Platform.isIOS) return 'Apple ${(await device.iosInfo).modelName}';
  if (!Platform.isAndroid) return Platform.operatingSystem;
  final info = await device.androidInfo;
  return '${info.manufacturer} ${info.model}';
}

class PostMortemIdApp extends StatelessWidget {
  const PostMortemIdApp({super.key, required this.services});

  final AppServices services;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'PostMortemID',
    theme: buildTheme(),
    home: HomeScreen(services: services),
  );
}
