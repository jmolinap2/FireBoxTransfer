import 'dart:async';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:fireboxtransfer_app/features/explorer/data/android_saf_file_system_client.dart';
import 'package:fireboxtransfer_app/features/explorer/data/explorer_transfer_service.dart';
import 'package:fireboxtransfer_app/features/explorer/explorer.dart';
import 'package:fireboxtransfer_app/model/persistence/favorite_device.dart';
import 'package:fireboxtransfer_app/model/persistence/shared_file_root.dart';
import 'package:fireboxtransfer_app/provider/favorites_provider.dart';
import 'package:fireboxtransfer_app/provider/http_provider.dart';
import 'package:fireboxtransfer_app/provider/network/nearby_devices_provider.dart';
import 'package:fireboxtransfer_app/provider/shared_file_roots_provider.dart';
import 'package:fireboxtransfer_app/util/native/directories.dart';
import 'package:fireboxtransfer_app/widget/responsive_builder.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:localsend_isolates/model/device.dart' as network;
import 'package:refena_flutter/refena_flutter.dart';

/// Phase 3 entry point. Desktop renders two persistent panels; mobile renders
/// one panel at a time and keeps the same filesystem contracts underneath.
class ExplorerTab extends StatefulWidget {
  const ExplorerTab({super.key});

  @override
  State<ExplorerTab> createState() => _ExplorerTabState();
}

class _ExplorerTabState extends State<ExplorerTab> {
  _ExplorerContext? _context;
  String? _signature;
  String? _selectedRemoteFingerprint;
  ExplorerTransferOperation _operation = ExplorerTransferOperation.copy;
  bool _externalDragActive = false;

  @override
  void dispose() {
    _context?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final roots = context.watch(sharedFileRootsProvider);
    final favorites = context.watch(favoritesProvider);
    final nearby = context.watch(nearbyDevicesProvider.select((state) => state.allDevices));
    final httpClients = context.watch(httpProvider);
    final signature = [
      for (final root in roots) '${root.id}:${root.locator}:${root.readOnly}',
      for (final favorite in favorites) '${favorite.fingerprint}:${favorite.ip}:${favorite.port}',
      for (final device in nearby.values) '${device.fingerprint}:${device.ip}:${device.port}',
    ].join('|');

    if (_signature != signature) {
      _signature = signature;
      _context?.dispose();
      _context = null;
      WidgetsBinding.instance.addPostFrameCallback((_) => _createContext(roots, favorites, nearby, httpClients));
    }

    final explorer = _context;
    if (explorer == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return ResponsiveBuilder(
      builder: (size) {
        return Column(
          children: [
            _Toolbar(
              remoteDevices: explorer.remoteChoices,
              selectedFingerprint: explorer.remoteDevice?.id,
              operation: _operation,
              onRemoteChanged: (fingerprint) {
                setState(() {
                  _selectedRemoteFingerprint = fingerprint;
                  _signature = null;
                });
              },
              onOperationChanged: (operation) => setState(() => _operation = operation),
            ),
            Expanded(
              child: size.isMobile
                  ? MobileExplorer(sources: explorer.mobileSources)
                  : explorer.remoteController == null
                  ? _NoRemoteDevice(localController: explorer.localController, localDevice: explorer.localDevice)
                  : _ExternalDropArea(
                      active: _externalDragActive,
                      destinationLabel: explorer.remoteController!.state.listing?.location.displayPath ?? explorer.remoteDevice!.name,
                      canAccept: explorer.remoteController!.state.listing != null && explorer.remoteController!.state.capabilities.write,
                      onEntered: (accepted) => setState(() => _externalDragActive = accepted),
                      onExited: () => setState(() => _externalDragActive = false),
                      onDropped: (paths) => _importExternal(explorer, paths),
                      child: DualExplorer(
                        leftController: explorer.localController,
                        leftDevice: explorer.localDevice,
                        rightController: explorer.remoteController!,
                        rightDevice: explorer.remoteDevice!,
                        onTransfer: explorer.transferService.execute,
                        operation: _operation,
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _createContext(
    List<SharedFileRoot> configuredRoots,
    List<FavoriteDevice> favorites,
    Map<String, network.Device> nearby,
    HttpClientCollection httpClients,
  ) async {
    final localClient = await _localClient(configuredRoots);
    final localController = ExplorerController(client: localClient);
    final localDevice = ExplorerDevice(
      id: 'local',
      name: defaultTargetPlatform == TargetPlatform.android ? 'Este teléfono' : 'Este PC',
      platform: _localPlatform(),
      connectionStatus: ExplorerConnectionStatus.local,
    );

    RemoteFileSystemClient? remoteClient;
    final onlineTrusted = <network.Device>[];
    for (final favorite in favorites) {
      final candidate = nearby[favorite.fingerprint];
      if (candidate?.ip != null && candidate!.https) {
        onlineTrusted.add(candidate);
      }
    }
    network.Device? remoteNetworkDevice;
    for (final candidate in onlineTrusted) {
      if (candidate.fingerprint == _selectedRemoteFingerprint) {
        remoteNetworkDevice = candidate;
        break;
      }
    }
    remoteNetworkDevice ??= onlineTrusted.firstOrNull;
    _selectedRemoteFingerprint = remoteNetworkDevice?.fingerprint;

    ExplorerController? remoteController;
    ExplorerDevice? remoteDevice;
    if (remoteNetworkDevice != null) {
      final remoteIp = remoteNetworkDevice.ip;
      if (remoteIp == null) {
        remoteNetworkDevice = null;
      } else {
        remoteClient = NetworkRemoteFileSystemClient(
          client: httpClients.pinnedTo(remoteNetworkDevice.fingerprint),
          ip: remoteIp,
          port: remoteNetworkDevice.port,
          expectedFingerprint: remoteNetworkDevice.fingerprint,
        );
        final client = remoteClient;
        remoteController = ExplorerController(client: client);
        remoteDevice = ExplorerDevice(
          id: remoteNetworkDevice.fingerprint,
          name: remoteNetworkDevice.alias,
          platform: remoteNetworkDevice.deviceType == network.DeviceType.mobile ? ExplorerPlatformKind.android : ExplorerPlatformKind.windows,
          connectionStatus: ExplorerConnectionStatus.connected,
        );
      }
    }

    final clients = <String, RemoteFileSystemClient>{'left': localClient, 'mobile-local': localClient, 'mobile-local-device': localClient};
    if (remoteClient case final client?) {
      clients['right'] = client;
      clients['mobile-remote'] = client;
      clients['mobile-${remoteNetworkDevice!.fingerprint}'] = client;
    }
    final next = _ExplorerContext(
      localController: localController,
      localDevice: localDevice,
      remoteController: remoteController,
      remoteDevice: remoteDevice,
      remoteChoices: List.unmodifiable(onlineTrusted),
      transferService: ExplorerTransferService((panelId) => clients[panelId]!),
    );
    if (!mounted) {
      next.dispose();
      return;
    }
    setState(() => _context = next);
  }

  Future<void> _importExternal(_ExplorerContext explorer, List<String> paths) async {
    setState(() => _externalDragActive = false);
    final controller = explorer.remoteController;
    final root = controller?.state.activeRoot;
    final directory = controller?.state.listing?.location;
    if (controller == null || root == null || directory == null || !controller.state.capabilities.write) return;
    try {
      await explorer.transferService.importExternalPaths(
        targetPanelId: 'right',
        targetRoot: root,
        targetDirectoryPath: directory.path,
        paths: paths,
      );
      await controller.reload();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  Future<RemoteFileSystemClient> _localClient(List<SharedFileRoot> configuredRoots) async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSafFileSystemClient(configuredRoots);
    }
    final roots = configuredRoots.where((root) => root.type == SharedFileRootType.localPath).toList();
    if (roots.isEmpty) {
      final downloads = await getDefaultDestinationDirectory();
      roots.add(SharedFileRoot(id: 'local-downloads', name: 'Descargas', type: SharedFileRootType.localPath, locator: downloads, readOnly: false));
    }
    return LocalFileSystemClient(
      roots.map(
        (root) => ExplorerRoot(
          id: root.id,
          label: root.name,
          initialPath: root.locator,
          capabilities: root.readOnly ? const ExplorerCapabilities.readOnly() : const ExplorerCapabilities.readWrite(),
        ),
      ),
    );
  }

  ExplorerPlatformKind _localPlatform() => switch (defaultTargetPlatform) {
    TargetPlatform.android => ExplorerPlatformKind.android,
    TargetPlatform.windows => ExplorerPlatformKind.windows,
    TargetPlatform.linux => ExplorerPlatformKind.linux,
    TargetPlatform.macOS => ExplorerPlatformKind.macos,
    TargetPlatform.iOS => ExplorerPlatformKind.ios,
    TargetPlatform.fuchsia => ExplorerPlatformKind.unknown,
  };
}

class _ExplorerContext {
  final ExplorerController localController;
  final ExplorerDevice localDevice;
  final ExplorerController? remoteController;
  final ExplorerDevice? remoteDevice;
  final List<network.Device> remoteChoices;
  final ExplorerTransferService transferService;

  const _ExplorerContext({
    required this.localController,
    required this.localDevice,
    required this.remoteController,
    required this.remoteDevice,
    required this.remoteChoices,
    required this.transferService,
  });

  List<MobileExplorerSource> get mobileSources => [
    MobileExplorerSource(id: 'local', label: localDevice.name, device: localDevice, controller: localController),
    if (remoteController != null) MobileExplorerSource(id: 'remote', label: remoteDevice!.name, device: remoteDevice!, controller: remoteController!),
  ];

  void dispose() {
    localController.dispose();
    remoteController?.dispose();
  }
}

class _Toolbar extends StatelessWidget {
  final List<network.Device> remoteDevices;
  final String? selectedFingerprint;
  final ExplorerTransferOperation operation;
  final ValueChanged<String?> onRemoteChanged;
  final ValueChanged<ExplorerTransferOperation> onOperationChanged;

  const _Toolbar({
    required this.remoteDevices,
    required this.selectedFingerprint,
    required this.operation,
    required this.onRemoteChanged,
    required this.onOperationChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Row(
        children: [
          Text('Explorar', style: Theme.of(context).textTheme.titleLarge),
          const Spacer(),
          if (remoteDevices.isEmpty)
            const Padding(padding: EdgeInsets.only(right: 12), child: Text('Selecciona y confía un dispositivo para explorar el otro lado')),
          if (remoteDevices.length > 1)
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 220),
              child: DropdownButtonFormField<String>(
                initialValue: selectedFingerprint,
                decoration: const InputDecoration(labelText: 'Dispositivo remoto', prefixIcon: Icon(Icons.devices)),
                items: remoteDevices
                    .map(
                      (device) => DropdownMenuItem(
                        value: device.fingerprint,
                        child: Text(device.alias, overflow: TextOverflow.ellipsis),
                      ),
                    )
                    .toList(),
                onChanged: onRemoteChanged,
              ),
            ),
          if (remoteDevices.isNotEmpty) ...[
            const SizedBox(width: 10),
            SegmentedButton<ExplorerTransferOperation>(
              segments: const [
                ButtonSegment(value: ExplorerTransferOperation.copy, icon: Icon(Icons.copy_outlined), label: Text('Copiar')),
                ButtonSegment(value: ExplorerTransferOperation.move, icon: Icon(Icons.drive_file_move_outline), label: Text('Mover')),
              ],
              selected: {operation},
              onSelectionChanged: (selected) => onOperationChanged(selected.single),
            ),
            const SizedBox(width: 10),
          ],
          OutlinedButton.icon(
            onPressed: () => SharedRootsDialog.open(context),
            icon: const Icon(Icons.folder_shared),
            label: const Text('Carpetas compartidas'),
          ),
        ],
      ),
    );
  }
}

class _NoRemoteDevice extends StatelessWidget {
  final ExplorerController localController;
  final ExplorerDevice localDevice;

  const _NoRemoteDevice({required this.localController, required this.localDevice});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: ExplorerPanel(panelId: 'left', controller: localController, device: localDevice),
        ),
        const VerticalDivider(width: 1),
        const Expanded(
          child: Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Text('No hay un dispositivo confiable compatible conectado.', textAlign: TextAlign.center),
            ),
          ),
        ),
      ],
    );
  }
}

class _ExternalDropArea extends StatelessWidget {
  const _ExternalDropArea({
    required this.active,
    required this.destinationLabel,
    required this.canAccept,
    required this.onEntered,
    required this.onExited,
    required this.onDropped,
    required this.child,
  });

  final bool active;
  final String destinationLabel;
  final bool canAccept;
  final ValueChanged<bool> onEntered;
  final VoidCallback onExited;
  final Future<void> Function(List<String>) onDropped;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DropTarget(
      onDragEntered: (_) => onEntered(canAccept),
      onDragExited: (_) => onExited(),
      onDragDone: (event) {
        if (canAccept) {
          unawaited(onDropped(event.files.map((file) => file.path).toList(growable: false)));
        }
      },
      child: Stack(
        children: [
          child,
          if (active)
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.94),
                    border: Border.all(color: Theme.of(context).colorScheme.primary, width: 3),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.file_download_outlined, size: 64),
                        const SizedBox(height: 12),
                        Text('Suelta para copiar', style: Theme.of(context).textTheme.titleLarge),
                        const SizedBox(height: 6),
                        Text(destinationLabel, style: Theme.of(context).textTheme.bodyLarge),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

extension<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
