import 'dart:async';

import 'package:fireboxtransfer_app/model/persistence/shared_file_root.dart';
import 'package:fireboxtransfer_app/provider/persistence_provider.dart';
import 'package:fireboxtransfer_app/provider/remote_fs_access_provider.dart';
import 'package:fireboxtransfer_app/util/remote_fs_grants.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// Directories this device exposes to trusted peers.
final sharedFileRootsProvider = ReduxProvider<SharedFileRootsService, List<SharedFileRoot>>((ref) {
  return SharedFileRootsService(
    ref.read(persistenceProvider),
    onChanged: (roots) => ref
        .redux(remoteFsAccessProvider)
        .dispatchAsync(
          SetRemoteFsGrantsAction(roots.map(toRemoteFsGrant)),
        ),
  );
});

class SharedFileRootsService extends ReduxNotifier<List<SharedFileRoot>> {
  final PersistenceService _persistence;
  final FutureOr<void> Function(List<SharedFileRoot>)? _onChanged;

  SharedFileRootsService(this._persistence, {FutureOr<void> Function(List<SharedFileRoot>)? onChanged}) : _onChanged = onChanged;

  @override
  List<SharedFileRoot> init() => _persistence.getSharedFileRoots();

  Future<List<SharedFileRoot>> _persist(List<SharedFileRoot> roots) async {
    final immutable = List<SharedFileRoot>.unmodifiable(roots);
    await _persistence.setSharedFileRoots(immutable);
    await _onChanged?.call(immutable);
    return immutable;
  }
}

class AddSharedFileRootAction extends AsyncReduxAction<SharedFileRootsService, List<SharedFileRoot>> {
  final SharedFileRoot root;

  AddSharedFileRootAction(this.root);

  @override
  Future<List<SharedFileRoot>> reduce() async {
    final existing = state.indexWhere((entry) => entry.locator == root.locator);
    if (existing == -1) {
      return notifier._persist([...state, root]);
    }

    final updated = [...state]..[existing] = root;
    return notifier._persist(updated);
  }
}

class UpdateSharedFileRootAction extends AsyncReduxAction<SharedFileRootsService, List<SharedFileRoot>> {
  final SharedFileRoot root;

  UpdateSharedFileRootAction(this.root);

  @override
  Future<List<SharedFileRoot>> reduce() async {
    final index = state.indexWhere((entry) => entry.id == root.id);
    if (index == -1) return state;
    final updated = [...state]..[index] = root;
    return notifier._persist(updated);
  }
}

class RemoveSharedFileRootAction extends AsyncReduxAction<SharedFileRootsService, List<SharedFileRoot>> {
  final String id;

  RemoveSharedFileRootAction(this.id);

  @override
  Future<List<SharedFileRoot>> reduce() async {
    return notifier._persist(state.where((entry) => entry.id != id).toList());
  }
}
