import 'dart:async';

import 'package:fireboxtransfer_app/model/persistence/favorite_device.dart';
import 'package:fireboxtransfer_app/provider/persistence_provider.dart';
import 'package:fireboxtransfer_app/provider/remote_fs_access_provider.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// This provider stores the list of favorite devices.
/// It automatically saves the list to the device's storage.
final favoritesProvider = ReduxProvider<FavoritesService, List<FavoriteDevice>>((ref) {
  return FavoritesService(
    ref.read(persistenceProvider),
    onChanged: (favorites) => ref
        .redux(remoteFsAccessProvider)
        .dispatchAsync(
          SetRemoteFsTrustedFingerprintsAction(
            favorites.map((device) => device.fingerprint),
          ),
        ),
  );
});

class FavoritesService extends ReduxNotifier<List<FavoriteDevice>> {
  final PersistenceService _persistence;
  final FutureOr<void> Function(List<FavoriteDevice>)? _onChanged;

  FavoritesService(this._persistence, {FutureOr<void> Function(List<FavoriteDevice>)? onChanged}) : _onChanged = onChanged;

  Future<void> notifyChanged(List<FavoriteDevice> favorites) async {
    await _onChanged?.call(favorites);
  }

  @override
  List<FavoriteDevice> init() => _persistence.getFavorites();
}

/// Adds a favorite device.
class AddFavoriteAction extends AsyncReduxAction<FavoritesService, List<FavoriteDevice>> {
  final FavoriteDevice device;

  AddFavoriteAction(this.device);

  @override
  Future<List<FavoriteDevice>> reduce() async {
    final updated = List<FavoriteDevice>.unmodifiable([
      ...state,
      device,
    ]);
    await notifier._persistence.setFavorites(updated);
    await notifier.notifyChanged(updated);
    return updated;
  }
}

/// Updates a favorite device.
class UpdateFavoriteAction extends AsyncReduxAction<FavoritesService, List<FavoriteDevice>> {
  final FavoriteDevice device;

  UpdateFavoriteAction(this.device);

  @override
  Future<List<FavoriteDevice>> reduce() async {
    final index = state.indexWhere((e) => e.id == device.id);
    if (index == -1) {
      // Unknown device
      await Future.microtask(() {});
      return state;
    }
    final updated = List<FavoriteDevice>.unmodifiable(
      <FavoriteDevice>[
        ...state,
      ]..replaceRange(index, index + 1, [device]),
    );
    await notifier._persistence.setFavorites(updated);
    await notifier.notifyChanged(updated);
    return updated;
  }
}

/// Removes a favorite device.
class RemoveFavoriteAction extends AsyncReduxAction<FavoritesService, List<FavoriteDevice>> {
  final String deviceFingerprint;

  RemoveFavoriteAction({
    required this.deviceFingerprint,
  });

  @override
  Future<List<FavoriteDevice>> reduce() async {
    final index = state.indexWhere((e) => e.fingerprint == deviceFingerprint);
    if (index == -1) {
      // Unknown device
      return state;
    }
    final updated = List<FavoriteDevice>.unmodifiable(
      <FavoriteDevice>[
        ...state,
      ]..removeAt(index),
    );
    await notifier._persistence.setFavorites(updated);
    await notifier.notifyChanged(updated);
    return updated;
  }
}
