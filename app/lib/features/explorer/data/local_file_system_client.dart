import 'dart:async';
import 'dart:io';

import 'package:fireboxtransfer_app/features/explorer/data/remote_file_system_client.dart';
import 'package:fireboxtransfer_app/features/explorer/model/explorer_models.dart';
import 'package:path/path.dart' as p;

/// Native filesystem implementation used by the local desktop panel and by
/// explicitly shared desktop roots.
class LocalFileSystemClient implements RemoteFileSystemClient {
  final List<ExplorerRoot> _roots;

  LocalFileSystemClient(Iterable<ExplorerRoot> roots) : _roots = List.unmodifiable(roots);

  @override
  Future<List<ExplorerRoot>> listRoots() async => _roots;

  @override
  Future<ExplorerFileEntry> getMetadata({required ExplorerRoot root, required String path}) async {
    final resolved = await _existingPath(root, path);
    final type = await FileSystemEntity.type(resolved, followLinks: false);
    if (type != FileSystemEntityType.file && type != FileSystemEntityType.directory) {
      throw const RemoteFileSystemException(code: 'not_found', message: 'The requested file or directory was not found');
    }
    return _entry(resolved, type);
  }

  @override
  Future<ExplorerDirectoryListing> listDirectory({required ExplorerRoot root, required String path}) async {
    final directoryPath = await _existingPath(root, path);
    final directory = Directory(directoryPath);
    if (!await directory.exists()) {
      throw const RemoteFileSystemException(code: 'not_found', message: 'Directory not found');
    }

    final entries = <ExplorerFileEntry>[];
    await for (final entity in directory.list(followLinks: false)) {
      final type = await FileSystemEntity.type(entity.path, followLinks: false);
      if (type == FileSystemEntityType.link || type == FileSystemEntityType.notFound) continue;
      entries.add(await _entry(entity.path, type));
    }

    final location = ExplorerDirectoryRef(
      rootId: root.id,
      path: directoryPath,
      displayPath: directoryPath,
      parentPath: _samePath(directoryPath, root.initialPath) ? null : p.dirname(directoryPath),
    );

    return ExplorerDirectoryListing(
      location: location,
      entries: entries,
      capabilities: root.capabilities,
      storage: await _storageInfo(directoryPath),
    );
  }

  @override
  Future<ExplorerFileEntry> createDirectory({required ExplorerRoot root, required String parentPath, required String name}) async {
    _validateName(name);
    _require(root.capabilities.createDirectory, 'Creating folders is not allowed');
    final parent = await _existingPath(root, parentPath);
    final created = Directory(_resolveLexically(root, p.join(parent, name)));
    await created.create();
    return _entry(created.path, FileSystemEntityType.directory);
  }

  @override
  Future<ExplorerFileEntry> rename({required ExplorerRoot root, required ExplorerFileEntry entry, required String newName}) async {
    _validateName(newName);
    _require(root.capabilities.rename, 'Renaming is not allowed');
    final source = await _existingPath(root, entry.path);
    _rejectRootMutation(root, source);
    final destination = _resolveLexically(root, p.join(p.dirname(source), newName));
    await _rejectSymbolicLink(destination);
    final renamed = await FileSystemEntity.type(source, followLinks: false) == FileSystemEntityType.directory
        ? await Directory(source).rename(destination)
        : await File(source).rename(destination);
    return _entry(renamed.path, await FileSystemEntity.type(renamed.path, followLinks: false));
  }

  @override
  Future<ExplorerFileEntry> copy({required ExplorerRoot root, required ExplorerFileEntry entry, required String destinationPath}) async {
    _require(root.capabilities.write, 'Copying is not allowed');
    final source = await _existingPath(root, entry.path);
    _rejectRootMutation(root, source);
    final destinationDirectory = await _existingPath(root, destinationPath);
    final destination = _resolveLexically(root, p.join(destinationDirectory, entry.name));
    final sourceType = await FileSystemEntity.type(source, followLinks: false);
    if (sourceType == FileSystemEntityType.directory && (_samePath(source, destination) || _isWithin(source, destination))) {
      throw const RemoteFileSystemException(
        code: 'invalid_destination',
        message: 'A folder cannot be copied into itself.',
      );
    }
    await _rejectSymbolicLink(destination);
    await _copyEntity(source, destination);
    return _entry(destination, await FileSystemEntity.type(destination, followLinks: false));
  }

  @override
  Future<ExplorerFileEntry> move({required ExplorerRoot root, required ExplorerFileEntry entry, required String destinationPath}) async {
    _require(root.capabilities.move, 'Moving is not allowed');
    final source = await _existingPath(root, entry.path);
    _rejectRootMutation(root, source);
    final destinationDirectory = await _existingPath(root, destinationPath);
    final destination = _resolveLexically(root, p.join(destinationDirectory, entry.name));
    final sourceType = await FileSystemEntity.type(source, followLinks: false);
    if (sourceType == FileSystemEntityType.directory && (_samePath(source, destination) || _isWithin(source, destination))) {
      throw const RemoteFileSystemException(
        code: 'invalid_destination',
        message: 'A folder cannot be moved into itself.',
      );
    }
    await _rejectSymbolicLink(destination);
    final moved = sourceType == FileSystemEntityType.directory ? await Directory(source).rename(destination) : await File(source).rename(destination);
    return _entry(moved.path, await FileSystemEntity.type(moved.path, followLinks: false));
  }

  @override
  Future<void> delete({required ExplorerRoot root, required ExplorerFileEntry entry}) async {
    _require(root.capabilities.delete, 'Deleting is not allowed');
    final source = await _existingPath(root, entry.path);
    _rejectRootMutation(root, source);
    final type = await FileSystemEntity.type(source, followLinks: false);
    if (type == FileSystemEntityType.directory) {
      await Directory(source).delete(recursive: true);
    } else {
      await File(source).delete();
    }
  }

  @override
  Stream<List<int>> openRead({required ExplorerRoot root, required ExplorerFileEntry entry, int offset = 0}) async* {
    _require(root.capabilities.read, 'Reading is not allowed');
    final source = await _existingPath(root, entry.path);
    if (entry.isDirectory) {
      throw const RemoteFileSystemException(code: 'is_directory', message: 'Cannot read a directory as a file');
    }
    yield* File(source).openRead(offset);
  }

  @override
  Future<void> writeFile({
    required ExplorerRoot root,
    required String destinationPath,
    required String fileName,
    required Stream<List<int>> content,
    int? lengthBytes,
  }) async {
    _validateName(fileName);
    _require(root.capabilities.write, 'Writing is not allowed');
    final directory = await _existingPath(root, destinationPath);
    final target = File(_resolveLexically(root, p.join(directory, fileName)));
    await _rejectSymbolicLink(target.path);
    final sink = target.openWrite();
    try {
      await sink.addStream(content);
    } finally {
      await sink.close();
    }

    if (lengthBytes != null && await target.length() != lengthBytes) {
      throw const RemoteFileSystemException(code: 'length_mismatch', message: 'The written file has an unexpected size', recoverable: true);
    }
  }

  /// Imports files and folders selected outside FireBoxTransfer into an
  /// authorized local directory. Every source is streamed/copied by dart:io;
  /// symbolic links are rejected so an external drop cannot escape its tree.
  Future<void> importExternalPaths({required ExplorerRoot root, required String destinationPath, required Iterable<String> sourcePaths}) async {
    _require(root.capabilities.write, 'Writing is not allowed');
    final destinationDirectory = await _existingPath(root, destinationPath);
    for (final sourcePath in sourcePaths) {
      final type = await FileSystemEntity.type(sourcePath, followLinks: false);
      if (type == FileSystemEntityType.link || type == FileSystemEntityType.notFound) {
        throw const RemoteFileSystemException(code: 'unsupported_entry', message: 'Symbolic links and missing files cannot be imported.');
      }
      final name = p.basename(sourcePath);
      _validateName(name);
      final destination = _resolveLexically(root, p.join(destinationDirectory, name));
      if (type == FileSystemEntityType.directory && (_samePath(sourcePath, destination) || _isWithin(sourcePath, destination))) {
        throw const RemoteFileSystemException(code: 'invalid_destination', message: 'A folder cannot be copied into itself.');
      }
      await _copyEntity(sourcePath, destination);
    }
  }

  Future<ExplorerFileEntry> _entry(String path, FileSystemEntityType type) async {
    final stat = await FileStat.stat(path);
    return ExplorerFileEntry(
      id: path,
      name: p.basename(path),
      path: path,
      kind: type == FileSystemEntityType.directory ? ExplorerEntryKind.directory : ExplorerEntryKind.file,
      sizeBytes: type == FileSystemEntityType.directory ? null : stat.size,
      modifiedAt: stat.modified,
    );
  }

  Future<ExplorerStorageInfo?> _storageInfo(String path) async {
    // dart:io does not expose portable volume capacity. The provider leaves it
    // absent instead of presenting fabricated values; Windows integration can
    // add native volume data later without changing the explorer contract.
    return null;
  }

  String _resolveLexically(ExplorerRoot root, String candidate) {
    final rootPath = p.normalize(p.absolute(root.initialPath));
    final normalized = p.normalize(p.absolute(candidate));
    if (!_samePath(rootPath, normalized) && !p.isWithin(rootPath, normalized)) {
      throw const RemoteFileSystemException(code: 'outside_root', message: 'The requested path is outside the authorized root');
    }
    return normalized;
  }

  Future<String> _existingPath(ExplorerRoot root, String candidate) async {
    final lexical = _resolveLexically(root, candidate);
    try {
      final resolvedRoot = await Directory(root.initialPath).resolveSymbolicLinks();
      final type = await FileSystemEntity.type(lexical, followLinks: false);
      if (type == FileSystemEntityType.link) {
        throw const RemoteFileSystemException(code: 'symbolic_link', message: 'Symbolic links are not exposed');
      }
      final resolved = type == FileSystemEntityType.directory
          ? await Directory(lexical).resolveSymbolicLinks()
          : await File(lexical).resolveSymbolicLinks();
      if (!_samePath(resolvedRoot, resolved) && !p.isWithin(resolvedRoot, resolved)) {
        throw const RemoteFileSystemException(code: 'outside_root', message: 'The requested path resolves outside the authorized root');
      }
      return lexical;
    } on FileSystemException {
      throw const RemoteFileSystemException(code: 'not_found', message: 'The requested file or directory was not found');
    }
  }

  Future<void> _copyEntity(String source, String destination) async {
    await _rejectSymbolicLink(destination);
    final type = await FileSystemEntity.type(source, followLinks: false);
    if (type == FileSystemEntityType.file) {
      await File(source).copy(destination);
      return;
    }
    if (type != FileSystemEntityType.directory) {
      throw const RemoteFileSystemException(code: 'unsupported_entry', message: 'This filesystem entry cannot be copied');
    }
    await Directory(destination).create();
    await for (final child in Directory(source).list(followLinks: false)) {
      if (await FileSystemEntity.type(child.path, followLinks: false) == FileSystemEntityType.link) continue;
      await _copyEntity(child.path, p.join(destination, p.basename(child.path)));
    }
  }

  bool _samePath(String first, String second) => Platform.isWindows ? p.equals(first.toLowerCase(), second.toLowerCase()) : p.equals(first, second);

  bool _isWithin(String parent, String child) =>
      Platform.isWindows ? p.isWithin(parent.toLowerCase(), child.toLowerCase()) : p.isWithin(parent, child);

  Future<void> _rejectSymbolicLink(String path) async {
    if (await FileSystemEntity.type(path, followLinks: false) == FileSystemEntityType.link) {
      throw const RemoteFileSystemException(
        code: 'symbolic_link',
        message: 'Symbolic links are not exposed.',
      );
    }
  }

  void _rejectRootMutation(ExplorerRoot root, String path) {
    if (_samePath(p.normalize(p.absolute(root.initialPath)), p.normalize(p.absolute(path)))) {
      throw const RemoteFileSystemException(
        code: 'root_mutation',
        message: 'The authorized root cannot be modified.',
      );
    }
  }

  void _require(bool allowed, String message) {
    if (!allowed) throw RemoteFileSystemException(code: 'permission_denied', message: message);
  }

  void _validateName(String name) {
    if (name.isEmpty || name == '.' || name == '..' || p.basename(name) != name || name.contains('/') || name.contains('\\')) {
      throw const RemoteFileSystemException(code: 'invalid_name', message: 'Invalid file name');
    }
  }
}
