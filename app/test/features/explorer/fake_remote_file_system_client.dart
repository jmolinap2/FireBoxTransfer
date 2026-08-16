import 'package:fireboxtransfer_app/features/explorer/explorer.dart';

class FakeRemoteFileSystemClient implements RemoteFileSystemClient {
  FakeRemoteFileSystemClient({required this.roots, required Map<String, ExplorerDirectoryListing> listings}) : listings = Map.of(listings);

  final List<ExplorerRoot> roots;
  final Map<String, ExplorerDirectoryListing> listings;
  final List<String> listedPaths = [];
  final List<String> createdDirectoryNames = [];
  final List<String> deletedPaths = [];
  final List<String> writtenFileNames = [];
  Duration listDelay = Duration.zero;

  String _key(String rootId, String path) => '$rootId::$path';

  @override
  Future<List<ExplorerRoot>> listRoots() async => roots;

  @override
  Future<ExplorerDirectoryListing> listDirectory({required ExplorerRoot root, required String path}) async {
    listedPaths.add(path);
    if (listDelay != Duration.zero) {
      await Future<void>.delayed(listDelay);
    }
    final listing = listings[_key(root.id, path)];
    if (listing == null) {
      throw const RemoteFileSystemException(code: 'not_found', message: 'La carpeta ya no existe.');
    }
    return listing;
  }

  @override
  Future<ExplorerFileEntry> getMetadata({required ExplorerRoot root, required String path}) async {
    for (final listing in listings.values.where((listing) => listing.location.rootId == root.id)) {
      for (final entry in listing.entries) {
        if (entry.path == path) {
          return entry;
        }
      }
    }
    throw const RemoteFileSystemException(code: 'not_found', message: 'El elemento ya no existe.');
  }

  @override
  Future<ExplorerFileEntry> createDirectory({required ExplorerRoot root, required String parentPath, required String name}) async {
    createdDirectoryNames.add(name);
    final entry = ExplorerFileEntry(id: 'created-$name', name: name, path: '$parentPath/$name', kind: ExplorerEntryKind.directory);
    _mutableEntries(root.id, parentPath).add(entry);
    listings[_key(root.id, entry.path)] = ExplorerDirectoryListing(
      location: ExplorerDirectoryRef(rootId: root.id, path: entry.path, displayPath: name, parentPath: parentPath),
      entries: [],
      capabilities: root.capabilities,
    );
    return entry;
  }

  @override
  Future<ExplorerFileEntry> rename({required ExplorerRoot root, required ExplorerFileEntry entry, required String newName}) async {
    final renamed = ExplorerFileEntry(
      id: entry.id,
      name: newName,
      path: entry.path,
      kind: entry.kind,
      sizeBytes: entry.sizeBytes,
      modifiedAt: entry.modifiedAt,
      mimeType: entry.mimeType,
      capabilities: entry.capabilities,
    );
    for (final listing in listings.values.where((listing) => listing.location.rootId == root.id)) {
      final index = listing.entries.indexWhere((candidate) => candidate.path == entry.path);
      if (index >= 0) {
        _mutableEntries(root.id, listing.location.path)[index] = renamed;
        return renamed;
      }
    }
    throw const RemoteFileSystemException(code: 'not_found', message: 'El elemento ya no existe.');
  }

  @override
  Future<ExplorerFileEntry> copy({required ExplorerRoot root, required ExplorerFileEntry entry, required String destinationPath}) async => entry;

  @override
  Future<ExplorerFileEntry> move({required ExplorerRoot root, required ExplorerFileEntry entry, required String destinationPath}) async => entry;

  @override
  Future<void> delete({required ExplorerRoot root, required ExplorerFileEntry entry}) async {
    deletedPaths.add(entry.path);
    for (final listing in listings.values.where((listing) => listing.location.rootId == root.id)) {
      _mutableEntries(root.id, listing.location.path).removeWhere((candidate) => candidate.path == entry.path);
    }
  }

  @override
  Stream<List<int>> openRead({required ExplorerRoot root, required ExplorerFileEntry entry, int offset = 0}) =>
      Stream.value([1, 2, 3].skip(offset).toList());

  @override
  Future<void> writeFile({
    required ExplorerRoot root,
    required String destinationPath,
    required String fileName,
    required Stream<List<int>> content,
    int? lengthBytes,
  }) async {
    writtenFileNames.add(fileName);
    await content.drain<void>();
  }

  List<ExplorerFileEntry> _mutableEntries(String rootId, String path) {
    final key = _key(rootId, path);
    final existing = listings[key];
    if (existing == null) {
      throw StateError('No listing registered for $key');
    }
    return existing.entries;
  }
}

ExplorerRoot fakeRoot({
  String id = 'root',
  String label = 'Descargas autorizadas',
  String initialPath = 'opaque://root',
  ExplorerCapabilities capabilities = const ExplorerCapabilities.readWrite(),
}) => ExplorerRoot(id: id, label: label, initialPath: initialPath, capabilities: capabilities);

ExplorerDirectoryListing fakeListing({
  required ExplorerRoot root,
  required String path,
  required String displayPath,
  String? parentPath,
  List<ExplorerFileEntry>? entries,
}) => ExplorerDirectoryListing(
  location: ExplorerDirectoryRef(rootId: root.id, path: path, displayPath: displayPath, parentPath: parentPath),
  entries: entries ?? <ExplorerFileEntry>[],
  capabilities: root.capabilities,
  storage: const ExplorerStorageInfo(totalBytes: 256 * 1024 * 1024, freeBytes: 128 * 1024 * 1024),
);

ExplorerFileEntry fakeDirectory(String name, String path) => ExplorerFileEntry(id: path, name: name, path: path, kind: ExplorerEntryKind.directory);

ExplorerFileEntry fakeFile(String name, String path, {int size = 1024}) =>
    ExplorerFileEntry(id: path, name: name, path: path, kind: ExplorerEntryKind.file, sizeBytes: size, mimeType: 'text/plain');
