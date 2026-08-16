import 'package:fireboxtransfer_app/features/explorer/explorer.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../features/explorer/fake_remote_file_system_client.dart';

void main() {
  group('ExplorerController', () {
    test('loads an authorized root and sorts folders before files', () async {
      final root = fakeRoot();
      final client = FakeRemoteFileSystemClient(
        roots: [root],
        listings: {
          '${root.id}::${root.initialPath}': fakeListing(
            root: root,
            path: root.initialPath,
            displayPath: 'Descargas',
            entries: [fakeFile('zeta.txt', 'opaque://zeta'), fakeDirectory('Album', 'opaque://album'), fakeFile('alpha.txt', 'opaque://alpha')],
          ),
        },
      );
      final controller = ExplorerController(client: client);
      addTearDown(controller.dispose);

      await controller.initialize();

      expect(controller.state.status, ExplorerLoadStatus.ready);
      expect(controller.state.activeRoot, root);
      expect(controller.state.visibleEntries.map((entry) => entry.name), ['Album', 'alpha.txt', 'zeta.txt']);
    });

    test('navigates into an opaque directory and back without joining paths', () async {
      final root = fakeRoot();
      final album = fakeDirectory('Album', 'content://tree/root/document/album%3A1');
      final client = FakeRemoteFileSystemClient(
        roots: [root],
        listings: {
          '${root.id}::${root.initialPath}': fakeListing(root: root, path: root.initialPath, displayPath: 'Descargas', entries: [album]),
          '${root.id}::${album.path}': fakeListing(root: root, path: album.path, displayPath: 'Descargas / Album', parentPath: root.initialPath),
        },
      );
      final controller = ExplorerController(client: client);
      addTearDown(controller.dispose);
      await controller.initialize();

      expect(await controller.openDirectory(album), isTrue);
      expect(controller.state.listing!.location.path, album.path);
      expect(await controller.goUp(), isTrue);
      expect(controller.state.listing!.location.path, root.initialPath);
      expect(client.listedPaths, [root.initialPath, album.path, root.initialPath]);
    });

    test('filters the current folder and supports multi-selection', () async {
      final root = fakeRoot();
      final image = fakeFile('vacaciones.jpg', 'opaque://vacaciones');
      final report = fakeFile('reporte.pdf', 'opaque://reporte');
      final client = FakeRemoteFileSystemClient(
        roots: [root],
        listings: {
          '${root.id}::${root.initialPath}': fakeListing(root: root, path: root.initialPath, displayPath: 'Descargas', entries: [image, report]),
        },
      );
      final controller = ExplorerController(client: client);
      addTearDown(controller.dispose);
      await controller.initialize();

      controller.setSearchQuery('REPOR');
      expect(controller.state.visibleEntries, [report]);

      controller.selectEntry(image);
      controller.selectEntry(report, toggle: true);
      expect(controller.state.selectedEntries.toSet(), {image, report});
    });

    test('blocks mutations on a read-only root', () async {
      final root = fakeRoot(capabilities: const ExplorerCapabilities.readOnly());
      final client = FakeRemoteFileSystemClient(
        roots: [root],
        listings: {'${root.id}::${root.initialPath}': fakeListing(root: root, path: root.initialPath, displayPath: 'Descargas')},
      );
      final controller = ExplorerController(client: client);
      addTearDown(controller.dispose);
      await controller.initialize();

      expect(await controller.createDirectory('Privado'), isFalse);
      expect(client.createdDirectoryNames, isEmpty);
      expect(controller.state.operationError, isNotNull);
    });

    test('creates a folder when the authorized root allows writes', () async {
      final root = fakeRoot();
      final client = FakeRemoteFileSystemClient(
        roots: [root],
        listings: {'${root.id}::${root.initialPath}': fakeListing(root: root, path: root.initialPath, displayPath: 'Descargas')},
      );
      final controller = ExplorerController(client: client);
      addTearDown(controller.dispose);
      await controller.initialize();

      expect(await controller.createDirectory('Proyectos'), isTrue);
      expect(client.createdDirectoryNames, ['Proyectos']);
      expect(controller.state.visibleEntries.single.name, 'Proyectos');
    });
  });
}
