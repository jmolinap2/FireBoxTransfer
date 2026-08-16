import 'dart:io';

import 'package:fireboxtransfer_app/features/explorer/data/local_file_system_client.dart';
import 'package:fireboxtransfer_app/features/explorer/data/remote_file_system_client.dart';
import 'package:fireboxtransfer_app/features/explorer/model/explorer_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temporaryDirectory;
  late ExplorerRoot root;
  late LocalFileSystemClient client;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp('firebox-local-fs-');
    root = ExplorerRoot(
      id: 'test-root',
      label: 'Test',
      initialPath: temporaryDirectory.path,
      capabilities: const ExplorerCapabilities.readWrite(),
    );
    client = LocalFileSystemClient([root]);
  });

  tearDown(() => temporaryDirectory.delete(recursive: true));

  test('rejects paths outside the authorized root', () async {
    await expectLater(
      client.listDirectory(root: root, path: p.dirname(temporaryDirectory.path)),
      throwsA(isA<RemoteFileSystemException>().having((error) => error.code, 'code', 'outside_root')),
    );
  });

  test('rejects copying a directory into one of its descendants', () async {
    final source = await Directory(p.join(temporaryDirectory.path, 'source')).create();
    final child = await Directory(p.join(source.path, 'child')).create();
    final entry = await client.getMetadata(root: root, path: source.path);

    await expectLater(
      client.copy(root: root, entry: entry, destinationPath: child.path),
      throwsA(isA<RemoteFileSystemException>().having((error) => error.code, 'code', 'invalid_destination')),
    );
  });

  test('never allows deleting the authorized root itself', () async {
    final rootEntry = await client.getMetadata(root: root, path: root.initialPath);

    await expectLater(
      client.delete(root: root, entry: rootEntry),
      throwsA(isA<RemoteFileSystemException>().having((error) => error.code, 'code', 'root_mutation')),
    );
    expect(await temporaryDirectory.exists(), isTrue);
  });
}
