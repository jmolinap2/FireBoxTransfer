import 'dart:async';

import 'package:fireboxtransfer_app/features/explorer/model/explorer_models.dart';

/// Contract used by the explorer. Paths are opaque and must be validated by
/// the concrete provider against an explicitly authorized root.
abstract class RemoteFileSystemClient {
  Future<List<ExplorerRoot>> listRoots();

  Future<ExplorerDirectoryListing> listDirectory({required ExplorerRoot root, required String path});

  Future<ExplorerFileEntry> getMetadata({required ExplorerRoot root, required String path});

  Future<ExplorerFileEntry> createDirectory({required ExplorerRoot root, required String parentPath, required String name});

  Future<ExplorerFileEntry> rename({required ExplorerRoot root, required ExplorerFileEntry entry, required String newName});

  Future<ExplorerFileEntry> copy({required ExplorerRoot root, required ExplorerFileEntry entry, required String destinationPath});

  Future<ExplorerFileEntry> move({required ExplorerRoot root, required ExplorerFileEntry entry, required String destinationPath});

  Future<void> delete({required ExplorerRoot root, required ExplorerFileEntry entry});

  Stream<List<int>> openRead({required ExplorerRoot root, required ExplorerFileEntry entry, int offset = 0});

  Future<void> writeFile({
    required ExplorerRoot root,
    required String destinationPath,
    required String fileName,
    required Stream<List<int>> content,
    int? lengthBytes,
  });
}

class RemoteFileSystemException implements Exception {
  const RemoteFileSystemException({required this.code, required this.message, this.recoverable = false});

  final String code;
  final String message;
  final bool recoverable;

  @override
  String toString() => message;
}
