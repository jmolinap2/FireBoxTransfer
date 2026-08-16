import 'package:fireboxtransfer_app/features/explorer/data/explorer_transfer_service.dart';
import 'package:fireboxtransfer_app/features/explorer/explorer.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../features/explorer/fake_remote_file_system_client.dart';

void main() {
  test('streams files between different panel clients', () async {
    final sourceRoot = fakeRoot(id: 'source', initialPath: 'source-root');
    final targetRoot = fakeRoot(id: 'target', initialPath: 'target-root');
    final file = fakeFile('song.mp3', 'source/song.mp3', size: 3);
    final source = FakeRemoteFileSystemClient(
      roots: [sourceRoot],
      listings: {
        'source::source-root': fakeListing(root: sourceRoot, path: 'source-root', displayPath: 'Source', entries: [file]),
      },
    );
    final target = FakeRemoteFileSystemClient(
      roots: [targetRoot],
      listings: {'target::target-root': fakeListing(root: targetRoot, path: 'target-root', displayPath: 'Target')},
    );
    final service = ExplorerTransferService((panelId) => panelId == 'left' ? source : target);

    await service.execute(
      ExplorerTransferRequest(
        sourcePanelId: 'left',
        targetPanelId: 'right',
        sourceRoot: sourceRoot,
        sourceDirectory: const ExplorerDirectoryRef(rootId: 'source', path: 'source-root', displayPath: 'Source'),
        entries: [file],
        targetRoot: targetRoot,
        targetDirectory: const ExplorerDirectoryRef(rootId: 'target', path: 'target-root', displayPath: 'Target'),
      ),
    );

    expect(target.writtenFileNames, ['song.mp3']);
    expect(source.deletedPaths, isEmpty);
  });

  test('deletes source only after a successful move copy', () async {
    final sourceRoot = fakeRoot(id: 'source', initialPath: 'source-root');
    final targetRoot = fakeRoot(id: 'target', initialPath: 'target-root');
    final file = fakeFile('photo.jpg', 'source/photo.jpg', size: 3);
    final source = FakeRemoteFileSystemClient(
      roots: [sourceRoot],
      listings: {
        'source::source-root': fakeListing(root: sourceRoot, path: 'source-root', displayPath: 'Source', entries: [file]),
      },
    );
    final target = FakeRemoteFileSystemClient(
      roots: [targetRoot],
      listings: {'target::target-root': fakeListing(root: targetRoot, path: 'target-root', displayPath: 'Target')},
    );
    final service = ExplorerTransferService((panelId) => panelId == 'left' ? source : target);

    await service.execute(
      ExplorerTransferRequest(
        sourcePanelId: 'left',
        targetPanelId: 'right',
        sourceRoot: sourceRoot,
        sourceDirectory: const ExplorerDirectoryRef(rootId: 'source', path: 'source-root', displayPath: 'Source'),
        entries: [file],
        targetRoot: targetRoot,
        targetDirectory: const ExplorerDirectoryRef(rootId: 'target', path: 'target-root', displayPath: 'Target'),
        operation: ExplorerTransferOperation.move,
      ),
    );

    expect(target.writtenFileNames, ['photo.jpg']);
    expect(source.deletedPaths, [file.path]);
  });
}
