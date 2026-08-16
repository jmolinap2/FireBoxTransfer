import 'package:fireboxtransfer_app/features/explorer/explorer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../features/explorer/fake_remote_file_system_client.dart';

void main() {
  testWidgets('dual explorer identifies both devices and emits a transfer request', (tester) async {
    final leftRoot = fakeRoot(id: 'pc-root', label: 'Este PC', initialPath: 'C-token');
    final rightRoot = fakeRoot(id: 'phone-root', label: 'Teléfono', initialPath: 'saf-token');
    final report = fakeFile('reporte.pdf', 'pc-token/reporte', size: 4096);
    final leftClient = FakeRemoteFileSystemClient(
      roots: [leftRoot],
      listings: {
        '${leftRoot.id}::${leftRoot.initialPath}': fakeListing(
          root: leftRoot,
          path: leftRoot.initialPath,
          displayPath: 'Descargas',
          entries: [report],
        ),
      },
    );
    final rightClient = FakeRemoteFileSystemClient(
      roots: [rightRoot],
      listings: {'${rightRoot.id}::${rightRoot.initialPath}': fakeListing(root: rightRoot, path: rightRoot.initialPath, displayPath: 'Download')},
    );
    final leftController = ExplorerController(client: leftClient);
    final rightController = ExplorerController(client: rightClient);
    addTearDown(leftController.dispose);
    addTearDown(rightController.dispose);
    ExplorerTransferRequest? request;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1200,
            height: 720,
            child: DualExplorer(
              leftController: leftController,
              leftDevice: const ExplorerDevice(
                id: 'pc',
                name: 'PC-YISUS',
                platform: ExplorerPlatformKind.windows,
                connectionStatus: ExplorerConnectionStatus.local,
              ),
              rightController: rightController,
              rightDevice: const ExplorerDevice(
                id: 'phone',
                name: 'POCO X6 Pro',
                platform: ExplorerPlatformKind.android,
                connectionStatus: ExplorerConnectionStatus.connected,
              ),
              onTransfer: (value) async => request = value,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('PC-YISUS'), findsOneWidget);
    expect(find.text('POCO X6 Pro'), findsOneWidget);
    expect(find.text('reporte.pdf'), findsOneWidget);

    leftController.selectEntry(report);
    await tester.pumpAndSettle();
    expect(leftController.state.selectedEntries, [report]);
    final copyRight = tester.widget<IconButton>(find.byKey(const ValueKey('explorer-copy-right')));
    expect(copyRight.onPressed, isNotNull);
    copyRight.onPressed!();
    await tester.pumpAndSettle();

    expect(request, isNotNull);
    expect(request!.entries, [report]);
    expect(request!.sourcePanelId, 'left');
    expect(request!.targetPanelId, 'right');
    expect(request!.targetDirectory.path, rightRoot.initialPath);
  });

  testWidgets('mobile explorer switches between phone and PC in one panel', (tester) async {
    final phoneRoot = fakeRoot(id: 'phone', initialPath: 'phone-token');
    final pcRoot = fakeRoot(id: 'pc', initialPath: 'pc-token');
    final phoneController = ExplorerController(
      client: FakeRemoteFileSystemClient(
        roots: [phoneRoot],
        listings: {
          '${phoneRoot.id}::${phoneRoot.initialPath}': fakeListing(
            root: phoneRoot,
            path: phoneRoot.initialPath,
            displayPath: 'Este teléfono',
            entries: [fakeDirectory('DCIM', 'phone-token/dcim')],
          ),
        },
      ),
    );
    final pcController = ExplorerController(
      client: FakeRemoteFileSystemClient(
        roots: [pcRoot],
        listings: {
          '${pcRoot.id}::${pcRoot.initialPath}': fakeListing(
            root: pcRoot,
            path: pcRoot.initialPath,
            displayPath: 'PC',
            entries: [fakeDirectory('Documentos', 'pc-token/documents')],
          ),
        },
      ),
    );
    addTearDown(phoneController.dispose);
    addTearDown(pcController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MobileExplorer(
            sources: [
              MobileExplorerSource(
                id: 'phone',
                label: 'Este teléfono',
                device: const ExplorerDevice(
                  id: 'phone-device',
                  name: 'POCO X6 Pro',
                  platform: ExplorerPlatformKind.android,
                  connectionStatus: ExplorerConnectionStatus.local,
                ),
                controller: phoneController,
              ),
              MobileExplorerSource(
                id: 'pc',
                label: 'PC-YISUS',
                device: const ExplorerDevice(
                  id: 'pc-device',
                  name: 'PC-YISUS',
                  platform: ExplorerPlatformKind.windows,
                  connectionStatus: ExplorerConnectionStatus.connected,
                ),
                controller: pcController,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('DCIM'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('mobile-explorer-source-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('PC-YISUS').last);
    await tester.pumpAndSettle();

    expect(find.text('Documentos'), findsOneWidget);
    expect(find.text('DCIM'), findsNothing);
  });
}
