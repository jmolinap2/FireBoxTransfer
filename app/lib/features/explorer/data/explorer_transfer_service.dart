import 'dart:io';

import 'package:fireboxtransfer_app/features/explorer/data/remote_file_system_client.dart';
import 'package:fireboxtransfer_app/features/explorer/model/explorer_models.dart';
import 'package:path/path.dart' as p;

typedef ExplorerClientResolver = RemoteFileSystemClient Function(String panelId);

/// Executes direct panel-to-panel copies for the dual explorer.
///
/// Files are streamed end to end. Directories are traversed progressively, so
/// neither a large file nor a complete directory tree is buffered in memory.
class ExplorerTransferService {
  final ExplorerClientResolver _resolveClient;

  ExplorerTransferService(this._resolveClient);

  Future<void> execute(ExplorerTransferRequest request) async {
    final source = _resolveClient(request.sourcePanelId);
    final target = _resolveClient(request.targetPanelId);

    if (identical(source, target) && request.sourceRoot.id == request.targetRoot.id) {
      for (final entry in request.entries) {
        if (request.operation == ExplorerTransferOperation.move) {
          await source.move(root: request.sourceRoot, entry: entry, destinationPath: request.targetDirectory.path);
        } else {
          await source.copy(root: request.sourceRoot, entry: entry, destinationPath: request.targetDirectory.path);
        }
      }
      return;
    }

    for (final entry in request.entries) {
      await _copyEntry(
        sourceClient: source,
        sourceRoot: request.sourceRoot,
        sourceEntry: entry,
        targetClient: target,
        targetRoot: request.targetRoot,
        targetDirectoryPath: request.targetDirectory.path,
      );
    }

    if (request.operation == ExplorerTransferOperation.move) {
      // Remove sources only after every copy completed successfully. A partial
      // failure therefore never destroys a source file.
      for (final entry in request.entries) {
        await source.delete(root: request.sourceRoot, entry: entry);
      }
    }
  }

  Future<void> importExternalPaths({
    required String targetPanelId,
    required ExplorerRoot targetRoot,
    required String targetDirectoryPath,
    required List<String> paths,
  }) {
    final target = _resolveClient(targetPanelId);
    return _importExternal(target: target, root: targetRoot, directoryPath: targetDirectoryPath, paths: paths);
  }

  Future<void> _importExternal({
    required RemoteFileSystemClient target,
    required ExplorerRoot root,
    required String directoryPath,
    required List<String> paths,
  }) async {
    for (final sourcePath in paths) {
      final type = await FileSystemEntity.type(sourcePath, followLinks: false);
      if (type == FileSystemEntityType.link || type == FileSystemEntityType.notFound) {
        throw const RemoteFileSystemException(
          code: 'unsupported_entry',
          message: 'No se pueden importar enlaces simbólicos ni elementos inexistentes.',
        );
      }
      final name = p.basename(sourcePath);
      if (type == FileSystemEntityType.file) {
        final file = File(sourcePath);
        await target.writeFile(
          root: root,
          destinationPath: directoryPath,
          fileName: name,
          content: file.openRead(),
          lengthBytes: await file.length(),
        );
      } else if (type == FileSystemEntityType.directory) {
        final created = await target.createDirectory(root: root, parentPath: directoryPath, name: name);
        await for (final child in Directory(sourcePath).list(followLinks: false)) {
          await _importExternal(target: target, root: root, directoryPath: created.path, paths: [child.path]);
        }
      } else {
        throw const RemoteFileSystemException(code: 'unsupported_entry', message: 'El tipo de archivo no es compatible.');
      }
    }
  }

  Future<void> _copyEntry({
    required RemoteFileSystemClient sourceClient,
    required ExplorerRoot sourceRoot,
    required ExplorerFileEntry sourceEntry,
    required RemoteFileSystemClient targetClient,
    required ExplorerRoot targetRoot,
    required String targetDirectoryPath,
  }) async {
    if (!sourceEntry.isDirectory) {
      await targetClient.writeFile(
        root: targetRoot,
        destinationPath: targetDirectoryPath,
        fileName: sourceEntry.name,
        content: sourceClient.openRead(root: sourceRoot, entry: sourceEntry),
        lengthBytes: sourceEntry.sizeBytes,
      );
      return;
    }

    final created = await targetClient.createDirectory(
      root: targetRoot,
      parentPath: targetDirectoryPath,
      name: sourceEntry.name,
    );
    final sourceListing = await sourceClient.listDirectory(root: sourceRoot, path: sourceEntry.path);
    for (final child in sourceListing.entries) {
      await _copyEntry(
        sourceClient: sourceClient,
        sourceRoot: sourceRoot,
        sourceEntry: child,
        targetClient: targetClient,
        targetRoot: targetRoot,
        targetDirectoryPath: created.path,
      );
    }
  }
}
