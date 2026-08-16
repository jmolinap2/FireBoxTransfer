import 'dart:async';

import 'package:fireboxtransfer_app/features/explorer/data/remote_file_system_client.dart';
import 'package:fireboxtransfer_app/features/explorer/model/explorer_models.dart';
import 'package:fireboxtransfer_app/model/persistence/shared_file_root.dart';
import 'package:fireboxtransfer_app/util/native/channel/android_channel.dart' as android;
import 'package:localsend_isolates/rust/api/stream.dart' as rs_stream;
import 'package:uri_content/uri_content.dart';

/// Main-isolate SAF provider for the mobile explorer.
///
/// SAF URIs remain opaque. The native channel validates every URI against a
/// persisted user-selected tree before performing an operation.
class AndroidSafFileSystemClient implements RemoteFileSystemClient {
  final List<SharedFileRoot> _grants;
  final UriContent _uriContent;

  AndroidSafFileSystemClient(Iterable<SharedFileRoot> grants, {UriContent? uriContent})
    : _grants = List.unmodifiable(grants.where((root) => root.type == SharedFileRootType.androidSaf)),
      _uriContent = uriContent ?? UriContent();

  @override
  Future<List<ExplorerRoot>> listRoots() async {
    final active = {for (final root in await android.listSharedRootsAndroid()) root.uri: root};
    return [
      for (final grant in _grants)
        if (active[grant.locator] case final safRoot?)
          ExplorerRoot(
            id: grant.id,
            label: grant.name,
            initialPath: grant.locator,
            capabilities: _rootCapabilities(grant, safRoot),
          ),
    ];
  }

  @override
  Future<ExplorerDirectoryListing> listDirectory({required ExplorerRoot root, required String path}) async {
    final directory = await _resolve(root, path);
    if (!directory.isDirectory) {
      throw const RemoteFileSystemException(code: 'not_directory', message: 'La ubicación solicitada no es una carpeta.');
    }
    final documents = await android.listSharedDirectoryAndroid(directory.uri);
    return ExplorerDirectoryListing(
      location: ExplorerDirectoryRef(
        rootId: root.id,
        path: _relativePath(root, path),
        displayPath: _displayPath(root, path),
        parentPath: _parentPath(root, path),
      ),
      entries: documents.map((document) => _entry(root, _relativePath(root, path), document)).toList(growable: false),
      capabilities: root.capabilities,
    );
  }

  @override
  Future<ExplorerFileEntry> getMetadata({required ExplorerRoot root, required String path}) async {
    final document = await _resolve(root, path);
    return _entry(root, _parentPath(root, path) ?? '', document);
  }

  @override
  Future<ExplorerFileEntry> createDirectory({required ExplorerRoot root, required String parentPath, required String name}) async {
    _validateName(name);
    _require(root.capabilities.createDirectory);
    final parent = await _resolve(root, parentPath);
    final created = await android.createSharedDirectoryAndroid(parentUri: parent.uri, name: name);
    return _entry(root, parentPath, created);
  }

  @override
  Future<ExplorerFileEntry> rename({required ExplorerRoot root, required ExplorerFileEntry entry, required String newName}) async {
    _validateName(newName);
    _require(root.capabilities.rename);
    final source = await _resolve(root, entry.path);
    final renamed = await android.renameSharedDocumentAndroid(uri: source.uri, newName: newName);
    return _entry(root, _parentPath(root, entry.path) ?? '', renamed);
  }

  @override
  Future<ExplorerFileEntry> copy({required ExplorerRoot root, required ExplorerFileEntry entry, required String destinationPath}) async {
    _require(root.capabilities.write);
    final sourcePath = _relativePath(root, entry.path);
    final targetPath = _relativePath(root, destinationPath);
    if (entry.isDirectory && (targetPath == sourcePath || (sourcePath.isNotEmpty && targetPath.startsWith('$sourcePath/')))) {
      throw const RemoteFileSystemException(code: 'conflict', message: 'No se puede copiar una carpeta dentro de sí misma.');
    }
    if (entry.isDirectory) {
      final created = await createDirectory(root: root, parentPath: destinationPath, name: entry.name);
      final listing = await listDirectory(root: root, path: entry.path);
      for (final child in listing.entries) {
        await copy(root: root, entry: child, destinationPath: created.path);
      }
      return created;
    }
    final size = entry.sizeBytes;
    if (size == null) {
      throw const RemoteFileSystemException(code: 'missing_size', message: 'Android no informó el tamaño del archivo.');
    }
    await writeFile(
      root: root,
      destinationPath: destinationPath,
      fileName: entry.name,
      content: openRead(root: root, entry: entry),
      lengthBytes: size,
    );
    return getMetadata(root: root, path: destinationPath.isEmpty ? entry.name : '$destinationPath/${entry.name}');
  }

  @override
  Future<ExplorerFileEntry> move({required ExplorerRoot root, required ExplorerFileEntry entry, required String destinationPath}) async {
    _require(root.capabilities.move);
    final source = await _resolve(root, entry.path);
    final sourceParentPath = _parentPath(root, entry.path);
    if (sourceParentPath == null) {
      throw const RemoteFileSystemException(code: 'root_mutation', message: 'No se puede mover una raíz compartida.');
    }
    final sourceParent = await _resolve(root, sourceParentPath);
    final destination = await _resolve(root, destinationPath);
    final moved = await android.moveSharedDocumentAndroid(uri: source.uri, sourceParentUri: sourceParent.uri, targetParentUri: destination.uri);
    return _entry(root, destinationPath, moved);
  }

  @override
  Future<void> delete({required ExplorerRoot root, required ExplorerFileEntry entry}) async {
    _require(root.capabilities.delete);
    final source = await _resolve(root, entry.path);
    await android.deleteSharedDocumentAndroid(source.uri);
  }

  @override
  Stream<List<int>> openRead({required ExplorerRoot root, required ExplorerFileEntry entry, int offset = 0}) async* {
    _require(root.capabilities.read);
    if (offset != 0) {
      throw const RemoteFileSystemException(code: 'unsupported_offset', message: 'SAF todavía no permite reanudar desde un desplazamiento.');
    }
    final source = await _resolve(root, entry.path);
    yield* _uriContent.getContentStream(Uri.parse(source.uri), bufferSize: 512 * 1024);
  }

  @override
  Future<void> writeFile({
    required ExplorerRoot root,
    required String destinationPath,
    required String fileName,
    required Stream<List<int>> content,
    int? lengthBytes,
  }) async {
    _require(root.capabilities.write);
    _validateName(fileName);
    if (lengthBytes == null) {
      throw const RemoteFileSystemException(code: 'missing_size', message: 'Se necesita el tamaño para escribir por streaming.');
    }
    final parent = await _resolve(root, destinationPath);
    final created = await android.createSharedFileAndroid(parentUri: parent.uri, name: fileName, mimeType: 'application/octet-stream');
    final (sink, receiver) = await rs_stream.createStream();
    final writeFuture = rs_stream.writeStreamToTarget(
      binary: receiver,
      fileDescriptor: created.fileDescriptor,
      expectedSize: BigInt.from(lengthBytes),
    );
    try {
      await for (final chunk in content) {
        try {
          await sink.add(data: chunk);
        } catch (_) {
          await writeFuture;
          rethrow;
        }
      }
      sink.close();
      final written = await writeFuture;
      if (written != BigInt.from(lengthBytes)) {
        throw const RemoteFileSystemException(code: 'length_mismatch', message: 'Android escribió una cantidad de bytes inesperada.');
      }
    } catch (error) {
      sink.close();
      try {
        await writeFuture;
      } catch (_) {}
      // Rust now owns and closes the descriptor. Remove the partial document
      // when SAF still exposes it.
      try {
        await android.deleteSharedDocumentAndroid(created.uri);
      } catch (_) {}
      rethrow;
    }
  }

  Future<android.AndroidSafDocument> _resolve(ExplorerRoot root, String path) {
    final relative = _relativePath(root, path);
    if (relative.isEmpty) {
      return android.getSharedDocumentMetadataAndroid(root.initialPath);
    }
    return android.resolveSharedRelativePathAndroid(rootUri: root.initialPath, relativePath: relative);
  }

  String _relativePath(ExplorerRoot root, String path) {
    if (path == root.initialPath || path.isEmpty) return '';
    if (path.startsWith('content://')) {
      throw const RemoteFileSystemException(code: 'invalid_path', message: 'La ruta no pertenece a esta raíz compartida.');
    }
    _validateRelativePath(path);
    return path;
  }

  ExplorerFileEntry _entry(ExplorerRoot root, String parentPath, android.AndroidSafDocument document) {
    final path = parentPath.isEmpty ? document.name : '$parentPath/${document.name}';
    return ExplorerFileEntry(
      id: document.uri,
      name: document.name,
      path: path,
      kind: document.isDirectory ? ExplorerEntryKind.directory : ExplorerEntryKind.file,
      sizeBytes: document.isDirectory ? null : document.size,
      modifiedAt: document.lastModified == null ? null : DateTime.fromMillisecondsSinceEpoch(document.lastModified!),
      mimeType: document.mimeType,
      capabilities: ExplorerCapabilities(
        browse: document.isDirectory && document.canRead,
        read: document.canRead,
        write: document.canWrite,
        createDirectory: document.isDirectory && document.canCreate,
        rename: document.canRename,
        move: document.canMove,
        delete: document.canDelete,
      ),
    );
  }

  ExplorerCapabilities _rootCapabilities(SharedFileRoot grant, android.AndroidSafRoot root) {
    final write = !grant.readOnly && root.canWrite;
    return ExplorerCapabilities(
      browse: root.canRead,
      read: root.canRead,
      write: write,
      createDirectory: write,
      rename: write,
      move: write,
      delete: write,
    );
  }

  String? _parentPath(ExplorerRoot root, String path) {
    final relative = _relativePath(root, path);
    if (relative.isEmpty) return null;
    final separator = relative.lastIndexOf('/');
    return separator < 0 ? '' : relative.substring(0, separator);
  }

  String _displayPath(ExplorerRoot root, String path) {
    final relative = _relativePath(root, path);
    return relative.isEmpty ? root.label : '${root.label}/$relative';
  }

  void _require(bool allowed) {
    if (!allowed) throw const RemoteFileSystemException(code: 'permission_denied', message: 'La operación no está permitida en esta ubicación.');
  }

  void _validateName(String name) {
    if (name.isEmpty || name == '.' || name == '..' || name.contains('/') || name.contains('\\') || name.contains('\u0000')) {
      throw const RemoteFileSystemException(code: 'invalid_name', message: 'El nombre no es válido.');
    }
  }

  void _validateRelativePath(String path) {
    if (path.startsWith('/') ||
        path.endsWith('/') ||
        path.contains('\\') ||
        path.split('/').any((part) => part.isEmpty || part == '.' || part == '..')) {
      throw const RemoteFileSystemException(code: 'invalid_path', message: 'La ruta no es válida.');
    }
  }
}
