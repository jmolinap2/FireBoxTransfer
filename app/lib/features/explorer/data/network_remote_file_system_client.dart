import 'dart:async';

import 'package:fireboxtransfer_app/features/explorer/data/remote_file_system_client.dart';
import 'package:fireboxtransfer_app/features/explorer/model/explorer_models.dart';
import 'package:localsend_isolates/rust/api/cancel.dart';
import 'package:localsend_isolates/rust/api/http.dart';
import 'package:localsend_isolates/rust/api/model.dart' as rs;
import 'package:localsend_isolates/rust/api/stream.dart';

const _remoteListPageSize = 500;
const _remoteListMaxEntries = 100000;

/// HTTPS/mTLS implementation of the explorer contract.
///
/// The supplied [client] must be pinned to [expectedFingerprint]. This class
/// deliberately cannot create a discovery/unpinned client.
class NetworkRemoteFileSystemClient implements RemoteFileSystemClient {
  NetworkRemoteFileSystemClient({
    required RsHttpClient client,
    required this.ip,
    required this.port,
    required this.expectedFingerprint,
  }) : assert(expectedFingerprint.isNotEmpty),
       _client = client;

  final RsHttpClient _client;
  final String ip;
  final int port;
  final String expectedFingerprint;

  final Map<String, ExplorerStorageInfo?> _storageByRoot = {};

  @override
  Future<List<ExplorerRoot>> listRoots() => _translate(() async {
    final roots = await _client.remoteFsRoots(ip: ip, port: port);
    return roots.map(_root).toList(growable: false);
  });

  @override
  Future<ExplorerDirectoryListing> listDirectory({required ExplorerRoot root, required String path}) => _translate(() async {
    final entries = <ExplorerFileEntry>[];
    final seenCursors = <String>{};
    String? cursor;
    do {
      final page = await _client.remoteFsList(
        ip: ip,
        port: port,
        request: rs.RemoteFsListRequest(location: _location(root, path), cursor: cursor, limit: _remoteListPageSize),
      );
      entries.addAll(page.entries.map(_entry));
      if (entries.length > _remoteListMaxEntries) {
        throw const RemoteFileSystemException(
          code: 'payload_too_large',
          message: 'La carpeta contiene demasiados elementos para mostrarla con seguridad.',
        );
      }
      cursor = page.nextCursor;
      if (cursor != null && !seenCursors.add(cursor)) {
        throw const RemoteFileSystemException(code: 'invalid_response', message: 'El dispositivo devolvió una paginación inválida.');
      }
    } while (cursor != null);

    return ExplorerDirectoryListing(
      location: ExplorerDirectoryRef(rootId: root.id, path: path, displayPath: _displayPath(root, path), parentPath: _parentPath(path)),
      entries: List.unmodifiable(entries),
      capabilities: root.capabilities,
      storage: _storageByRoot[root.id],
    );
  });

  @override
  Future<ExplorerFileEntry> getMetadata({required ExplorerRoot root, required String path}) =>
      _translate(() async => _entry(await _client.remoteFsMetadata(ip: ip, port: port, target: _location(root, path))));

  @override
  Future<ExplorerFileEntry> createDirectory({required ExplorerRoot root, required String parentPath, required String name}) => _translate(
    () async {
      _validatePath(parentPath);
      _validateName(name);
      return _entry(
        await _client.remoteFsCreateDirectory(
          ip: ip,
          port: port,
          request: rs.RemoteFsCreateDirectoryRequest(parent: _location(root, parentPath), name: name),
        ),
      );
    },
  );

  @override
  Future<ExplorerFileEntry> rename({required ExplorerRoot root, required ExplorerFileEntry entry, required String newName}) => _translate(
    () async {
      _validatePath(entry.path);
      _validateName(newName);
      return _entry(
        await _client.remoteFsRename(
          ip: ip,
          port: port,
          request: rs.RemoteFsRenameRequest(source: _location(root, entry.path), newName: newName),
        ),
      );
    },
  );

  @override
  Future<ExplorerFileEntry> copy({required ExplorerRoot root, required ExplorerFileEntry entry, required String destinationPath}) async {
    _validatePath(entry.path);
    _validatePath(destinationPath);
    _validateName(entry.name);
    if (_sameOrDescendant(destinationPath, entry.path)) {
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
      throw const RemoteFileSystemException(code: 'missing_size', message: 'El dispositivo no informó el tamaño del archivo.');
    }
    final targetPath = _childPath(destinationPath, entry.name);
    await writeFile(
      root: root,
      destinationPath: destinationPath,
      fileName: entry.name,
      content: openRead(root: root, entry: entry),
      lengthBytes: size,
    );
    return getMetadata(root: root, path: targetPath);
  }

  @override
  Future<ExplorerFileEntry> move({required ExplorerRoot root, required ExplorerFileEntry entry, required String destinationPath}) => _translate(
    () async {
      _validatePath(entry.path);
      _validatePath(destinationPath);
      if (entry.isDirectory && _sameOrDescendant(destinationPath, entry.path)) {
        throw const RemoteFileSystemException(code: 'conflict', message: 'No se puede mover una carpeta dentro de sí misma.');
      }
      return _entry(
        await _client.remoteFsMove(
          ip: ip,
          port: port,
          request: rs.RemoteFsMoveRequest(
            source: _location(root, entry.path),
            destinationParent: _location(root, destinationPath),
            overwrite: false,
          ),
        ),
      );
    },
  );

  @override
  Future<void> delete({required ExplorerRoot root, required ExplorerFileEntry entry}) => _translate(
    () {
      _validatePath(entry.path);
      return _client.remoteFsDelete(
        ip: ip,
        port: port,
        request: rs.RemoteFsDeleteRequest(target: _location(root, entry.path), recursive: entry.isDirectory),
      );
    },
  );

  @override
  Stream<List<int>> openRead({required ExplorerRoot root, required ExplorerFileEntry entry, int offset = 0}) async* {
    if (offset != 0) {
      throw const RemoteFileSystemException(code: 'unsupported_offset', message: 'La lectura remota todavía no admite reanudación.');
    }
    _validatePath(entry.path);
    final cancelToken = createCancellationToken();
    try {
      final remote = await _translate(() => _client.remoteFsOpenRead(ip: ip, port: port, target: _location(root, entry.path)));
      while (true) {
        final chunk = await _translate(() => remote.nextChunk(cancelToken: cancelToken));
        if (chunk == null) break;
        yield chunk;
      }
    } finally {
      cancelToken.cancel();
    }
  }

  @override
  Future<void> writeFile({
    required ExplorerRoot root,
    required String destinationPath,
    required String fileName,
    required Stream<List<int>> content,
    int? lengthBytes,
  }) async {
    if (lengthBytes == null) {
      throw const RemoteFileSystemException(code: 'missing_size', message: 'Se necesita el tamaño para escribir por streaming.');
    }
    _validatePath(destinationPath);
    _validateName(fileName);

    final (sink, receiver) = await createStream();
    final cancelToken = createCancellationToken();
    final target = _location(root, _childPath(destinationPath, fileName));
    final writeFuture = _consumeWriteEvents(
      _client.remoteFsWrite(
        ip: ip,
        port: port,
        target: target,
        overwrite: false,
        binary: receiver,
        contentLength: BigInt.from(lengthBytes),
        cancelToken: cancelToken,
      ),
      expectedSize: lengthBytes,
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
    } catch (error) {
      cancelToken.cancel();
      sink.close();
      try {
        await writeFuture;
      } catch (_) {}
      rethrow;
    }
    await writeFuture;
  }

  Future<void> _consumeWriteEvents(Stream<RsRemoteFsWriteEvent> events, {required int expectedSize}) async {
    var completed = false;
    await for (final event in events) {
      switch (event) {
        case RsRemoteFsWriteEvent_Progress():
          break;
        case RsRemoteFsWriteEvent_Completed(:final bytesWritten):
          if (bytesWritten != BigInt.from(expectedSize)) {
            throw const RemoteFileSystemException(code: 'length_mismatch', message: 'El dispositivo escribió una cantidad de bytes inesperada.');
          }
          completed = true;
        case RsRemoteFsWriteEvent_Failed(:final error):
          throw _mapError(error);
      }
    }
    if (!completed) {
      throw const RemoteFileSystemException(code: 'transfer_failed', message: 'La escritura remota terminó sin confirmación.', recoverable: true);
    }
  }

  ExplorerRoot _root(rs.RemoteFsRoot value) {
    final storage = value.totalBytes == null || value.freeBytes == null
        ? null
        : ExplorerStorageInfo(totalBytes: _safeInt(value.totalBytes!), freeBytes: _safeInt(value.freeBytes!));
    _storageByRoot[value.id] = storage;
    return ExplorerRoot(id: value.id, label: value.displayName, initialPath: '', capabilities: _capabilities(value.capabilities));
  }

  ExplorerFileEntry _entry(rs.RemoteFsEntry value) {
    if (value.entryType == rs.RemoteFsEntryType.other) {
      throw const RemoteFileSystemException(code: 'unsupported_entry', message: 'El dispositivo devolvió un tipo de archivo no compatible.');
    }
    _validatePath(value.path);
    _validateName(value.name);
    return ExplorerFileEntry(
      id: '${value.path}:${value.name}',
      name: value.name,
      path: value.path,
      kind: value.entryType == rs.RemoteFsEntryType.directory ? ExplorerEntryKind.directory : ExplorerEntryKind.file,
      sizeBytes: value.size == null ? null : _safeInt(value.size!),
      modifiedAt: value.modified == null ? null : DateTime.tryParse(value.modified!),
      mimeType: value.mimeType,
      capabilities: _capabilities(value.capabilities),
    );
  }

  ExplorerCapabilities _capabilities(Iterable<rs.RemoteFsCapability> values) {
    final set = values.toSet();
    return ExplorerCapabilities(
      browse: set.contains(rs.RemoteFsCapability.browse),
      read: set.contains(rs.RemoteFsCapability.read),
      write: set.contains(rs.RemoteFsCapability.write),
      createDirectory: set.contains(rs.RemoteFsCapability.createDirectory),
      rename: set.contains(rs.RemoteFsCapability.rename),
      move: set.contains(rs.RemoteFsCapability.move),
      delete: set.contains(rs.RemoteFsCapability.delete),
    );
  }

  rs.RemoteFsLocation _location(ExplorerRoot root, String path) {
    _validatePath(path);
    return rs.RemoteFsLocation(rootId: root.id, path: path);
  }

  String _displayPath(ExplorerRoot root, String path) => path.isEmpty ? root.label : '${root.label}/$path';

  String? _parentPath(String path) {
    if (path.isEmpty) return null;
    final separator = path.lastIndexOf('/');
    return separator < 0 ? '' : path.substring(0, separator);
  }

  String _childPath(String parent, String name) => parent.isEmpty ? name : '$parent/$name';

  bool _sameOrDescendant(String candidate, String ancestor) => candidate == ancestor || (ancestor.isNotEmpty && candidate.startsWith('$ancestor/'));

  void _validateName(String name) {
    if (name.isEmpty || name == '.' || name == '..' || name.contains('/') || name.contains('\\') || name.contains(RegExp(r'[\u0000-\u001f]'))) {
      throw const RemoteFileSystemException(code: 'invalid_name', message: 'El nombre no es válido.');
    }
  }

  void _validatePath(String path) {
    if (path.isEmpty) return;
    if (path.startsWith('/') ||
        path.endsWith('/') ||
        path.contains('\\') ||
        path.split('/').any((part) => part.isEmpty || part == '.' || part == '..')) {
      throw const RemoteFileSystemException(code: 'invalid_path', message: 'La ruta remota no es válida.');
    }
  }

  int _safeInt(BigInt value) {
    if (value < BigInt.zero || value > BigInt.from(0x7fffffffffffffff)) {
      throw const RemoteFileSystemException(code: 'invalid_response', message: 'El dispositivo devolvió un tamaño inválido.');
    }
    return value.toInt();
  }

  Future<T> _translate<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on RsRemoteFsClientError catch (error) {
      throw _mapError(error);
    }
  }

  RemoteFileSystemException _mapError(RsRemoteFsClientError error) => switch (error) {
    RsRemoteFsClientError_Remote(:final code, :final message) => RemoteFileSystemException(
      code: _errorCode(code),
      message: message,
      recoverable: code == rs.RemoteFsErrorCode.busy || code == rs.RemoteFsErrorCode.transferFailed || code == rs.RemoteFsErrorCode.unavailable,
    ),
    RsRemoteFsClientError_InvalidRequest(:final code) => RemoteFileSystemException(
      code: _errorCode(code),
      message: 'La solicitud remota no es válida.',
    ),
    RsRemoteFsClientError_Cancelled() => const RemoteFileSystemException(
      code: 'cancelled',
      message: 'La operación fue cancelada.',
      recoverable: true,
    ),
    RsRemoteFsClientError_Setup() => const RemoteFileSystemException(code: 'connection_setup', message: 'No se pudo establecer una conexión segura.'),
    RsRemoteFsClientError_Reqwest() || RsRemoteFsClientError_Io() => const RemoteFileSystemException(
      code: 'unavailable',
      message: 'Se perdió la conexión con el dispositivo.',
      recoverable: true,
    ),
    RsRemoteFsClientError_Json() || RsRemoteFsClientError_InvalidResponse() => const RemoteFileSystemException(
      code: 'invalid_response',
      message: 'El dispositivo devolvió una respuesta inválida.',
    ),
    RsRemoteFsClientError_Other() => const RemoteFileSystemException(code: 'remote_error', message: 'No se pudo completar la operación remota.'),
  };

  String _errorCode(rs.RemoteFsErrorCode value) => value.name;
}
