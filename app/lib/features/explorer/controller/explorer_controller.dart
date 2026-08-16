import 'package:fireboxtransfer_app/features/explorer/controller/explorer_state.dart';
import 'package:fireboxtransfer_app/features/explorer/data/remote_file_system_client.dart';
import 'package:fireboxtransfer_app/features/explorer/model/explorer_models.dart';
import 'package:flutter/foundation.dart';

class ExplorerController extends ChangeNotifier {
  ExplorerController({required this.client, String? preferredRootId}) : _preferredRootId = preferredRootId;

  final RemoteFileSystemClient client;
  final String? _preferredRootId;
  final List<ExplorerDirectoryRef> _backStack = [];

  ExplorerState _state = const ExplorerState();
  ExplorerState get state => _state;

  bool _disposed = false;
  int _requestGeneration = 0;
  Future<void>? _initialization;

  bool get canGoUp => _backStack.isNotEmpty || _state.listing?.location.parentPath != null;
  bool get isInitialized => _state.roots.isNotEmpty && _state.listing != null;

  Future<void> initialize() {
    if (isInitialized) {
      return Future.value();
    }
    return _initialization ??= _initialize().whenComplete(() => _initialization = null);
  }

  Future<void> _initialize() async {
    _emit(_state.copyWith(status: ExplorerLoadStatus.loading, clearLoadError: true, clearOperationError: true));

    try {
      final roots = (await client.listRoots()).where((root) => root.capabilities.browse).toList();
      if (_disposed) {
        return;
      }
      if (roots.isEmpty) {
        throw const RemoteFileSystemException(code: 'no_authorized_roots', message: 'No hay ubicaciones autorizadas para explorar.');
      }

      final activeRoot = roots.where((root) => root.id == _preferredRootId).firstOrNull ?? roots.first;
      _emit(_state.copyWith(roots: List.unmodifiable(roots), activeRoot: activeRoot, clearListing: true));
      await _loadDirectory(root: activeRoot, path: activeRoot.initialPath);
    } catch (error) {
      if (!_disposed) {
        _emit(_state.copyWith(status: ExplorerLoadStatus.error, loadError: _errorMessage(error)));
      }
    }
  }

  Future<bool> selectRoot(String rootId) async {
    ExplorerRoot? target;
    for (final root in _state.roots) {
      if (root.id == rootId) {
        target = root;
        break;
      }
    }
    if (target == null || target.id == _state.activeRoot?.id) {
      return target != null;
    }

    _backStack.clear();
    _emit(
      _state.copyWith(
        activeRoot: target,
        clearListing: true,
        selectedPaths: const {},
        searchQuery: '',
        clearLoadError: true,
        clearOperationError: true,
      ),
    );
    return _loadDirectory(root: target, path: target.initialPath);
  }

  Future<bool> openDirectory(ExplorerFileEntry entry) async {
    final root = _state.activeRoot;
    final previousLocation = _state.listing?.location;
    if (!entry.isDirectory || root == null || previousLocation == null) {
      return false;
    }

    final opened = await _loadDirectory(root: root, path: entry.path);
    if (opened && !_disposed) {
      _backStack.add(previousLocation);
      notifyListeners();
    }
    return opened;
  }

  Future<bool> navigateTo(ExplorerDirectoryRef directory, {bool rememberCurrent = true}) async {
    final root = _state.roots.where((item) => item.id == directory.rootId).firstOrNull;
    final previousLocation = _state.listing?.location;
    if (root == null) {
      return false;
    }

    final rootChanged = root.id != _state.activeRoot?.id;
    final opened = await _loadDirectory(root: root, path: directory.path);
    if (opened && rememberCurrent && previousLocation != null && !_disposed) {
      if (rootChanged) {
        _backStack.clear();
      } else {
        _backStack.add(previousLocation);
      }
      notifyListeners();
    }
    return opened;
  }

  Future<bool> goUp() async {
    final root = _state.activeRoot;
    final listing = _state.listing;
    if (root == null || listing == null) {
      return false;
    }

    if (_backStack.isNotEmpty) {
      final target = _backStack.last;
      final opened = await _loadDirectory(root: root, path: target.path);
      if (opened && !_disposed) {
        _backStack.removeLast();
        notifyListeners();
      }
      return opened;
    }

    final parentPath = listing.location.parentPath;
    if (parentPath == null) {
      return false;
    }
    return _loadDirectory(root: root, path: parentPath);
  }

  Future<bool> reload() async {
    final root = _state.activeRoot;
    final path = _state.listing?.location.path ?? root?.initialPath;
    if (root == null || path == null) {
      return false;
    }
    return _loadDirectory(root: root, path: path, preserveSelection: true);
  }

  Future<bool> _loadDirectory({required ExplorerRoot root, required String path, bool preserveSelection = false}) async {
    if (!root.capabilities.browse) {
      _emit(_state.copyWith(status: ExplorerLoadStatus.error, loadError: 'Esta ubicación no permite explorar archivos.'));
      return false;
    }
    final generation = ++_requestGeneration;
    _emit(_state.copyWith(status: ExplorerLoadStatus.loading, clearLoadError: true, clearOperationError: true));

    try {
      final listing = await client.listDirectory(root: root, path: path);
      if (_disposed || generation != _requestGeneration) {
        return false;
      }
      if (listing.location.rootId != root.id) {
        throw const RemoteFileSystemException(code: 'invalid_root', message: 'La ubicación devuelta no pertenece a la raíz autorizada.');
      }

      final retainedSelection = preserveSelection
          ? _state.selectedPaths.where((selectedPath) => listing.entries.any((entry) => entry.path == selectedPath)).toSet()
          : <String>{};
      _emit(
        _state.copyWith(
          status: ExplorerLoadStatus.ready,
          activeRoot: root,
          listing: listing,
          selectedPaths: Set.unmodifiable(retainedSelection),
          clearLoadError: true,
        ),
      );
      return true;
    } catch (error) {
      if (!_disposed && generation == _requestGeneration) {
        _emit(
          _state.copyWith(
            status: _state.listing == null ? ExplorerLoadStatus.error : ExplorerLoadStatus.ready,
            loadError: _errorMessage(error),
          ),
        );
      }
      return false;
    }
  }

  void setSearchQuery(String query) {
    if (query == _state.searchQuery) {
      return;
    }
    _emit(_state.copyWith(searchQuery: query));
  }

  void setSort(ExplorerSortField field, {ExplorerSortDirection? direction}) {
    final nextDirection = direction ?? (_state.sortField == field ? _opposite(_state.sortDirection) : ExplorerSortDirection.ascending);
    _emit(_state.copyWith(sortField: field, sortDirection: nextDirection));
  }

  void selectEntry(ExplorerFileEntry entry, {bool toggle = false}) {
    final selected = Set<String>.of(_state.selectedPaths);
    if (toggle) {
      selected.contains(entry.path) ? selected.remove(entry.path) : selected.add(entry.path);
    } else {
      selected
        ..clear()
        ..add(entry.path);
    }
    _emit(_state.copyWith(selectedPaths: Set.unmodifiable(selected), clearOperationError: true));
  }

  void clearSelection() {
    if (_state.selectedPaths.isNotEmpty) {
      _emit(_state.copyWith(selectedPaths: const {}));
    }
  }

  List<ExplorerFileEntry> dragEntriesFor(ExplorerFileEntry entry) {
    final selected = _state.selectedEntries;
    return _state.selectedPaths.contains(entry.path) && selected.isNotEmpty ? selected : [entry];
  }

  Future<bool> createDirectory(String name) {
    final normalized = _validatedName(name);
    if (normalized == null) {
      return Future.value(false);
    }
    return _runMutation(
      allowed: _state.capabilities.createDirectory,
      action: (root, listing) => client.createDirectory(root: root, parentPath: listing.location.path, name: normalized),
    );
  }

  Future<bool> renameEntry(ExplorerFileEntry entry, String newName) {
    final normalized = _validatedName(newName);
    if (normalized == null) {
      return Future.value(false);
    }
    return _runMutation(
      allowed: entry.capabilities?.rename ?? _state.capabilities.rename,
      action: (root, _) => client.rename(root: root, entry: entry, newName: normalized),
    );
  }

  Future<bool> deleteEntries(Iterable<ExplorerFileEntry> entries) {
    final entriesToDelete = List<ExplorerFileEntry>.of(entries);
    return _runMutation(
      allowed: entriesToDelete.isNotEmpty && entriesToDelete.every((entry) => entry.capabilities?.delete ?? _state.capabilities.delete),
      action: (root, _) async {
        for (final entry in entriesToDelete) {
          await client.delete(root: root, entry: entry);
        }
        return null;
      },
    );
  }

  Future<bool> copyEntry(ExplorerFileEntry entry, ExplorerDirectoryRef destination) {
    return _runMutation(
      allowed: (entry.capabilities?.read ?? _state.capabilities.read) && _state.capabilities.write,
      action: (root, _) => client.copy(root: root, entry: entry, destinationPath: destination.path),
    );
  }

  Future<bool> moveEntry(ExplorerFileEntry entry, ExplorerDirectoryRef destination) {
    return _runMutation(
      allowed: entry.capabilities?.move ?? _state.capabilities.move,
      action: (root, _) => client.move(root: root, entry: entry, destinationPath: destination.path),
    );
  }

  Future<bool> _runMutation({required bool allowed, required Future<Object?> Function(ExplorerRoot, ExplorerDirectoryListing) action}) async {
    final root = _state.activeRoot;
    final listing = _state.listing;
    if (!allowed || root == null || listing == null || _state.isMutating) {
      _emit(_state.copyWith(operationError: 'La operación no está permitida en esta ubicación.'));
      return false;
    }

    _emit(_state.copyWith(isMutating: true, clearOperationError: true));
    try {
      await action(root, listing);
      if (_disposed) {
        return false;
      }
      _emit(_state.copyWith(isMutating: false, selectedPaths: const {}));
      return reload();
    } catch (error) {
      if (!_disposed) {
        _emit(_state.copyWith(isMutating: false, operationError: _errorMessage(error)));
      }
      return false;
    }
  }

  void clearOperationError() => _emit(_state.copyWith(clearOperationError: true));

  String? _validatedName(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty || normalized == '.' || normalized == '..' || normalized.contains(RegExp(r'[\u0000-\u001f]'))) {
      _emit(_state.copyWith(operationError: 'El nombre no es válido.'));
      return null;
    }
    return normalized;
  }

  String _errorMessage(Object error) {
    if (error is RemoteFileSystemException) {
      return error.message;
    }
    if (error is ArgumentError) {
      return error.message?.toString() ?? 'La solicitud no es válida.';
    }
    return 'No se pudo completar la operación. Inténtalo de nuevo.';
  }

  ExplorerSortDirection _opposite(ExplorerSortDirection direction) =>
      direction == ExplorerSortDirection.ascending ? ExplorerSortDirection.descending : ExplorerSortDirection.ascending;

  void _emit(ExplorerState nextState) {
    if (_disposed) {
      return;
    }
    _state = nextState;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _requestGeneration++;
    super.dispose();
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
