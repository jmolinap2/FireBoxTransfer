import 'dart:async';

import 'package:fireboxtransfer_app/provider/persistence_provider.dart';
import 'package:fireboxtransfer_app/util/remote_fs_grants.dart';
import 'package:localsend_isolates/isolate.dart';
import 'package:localsend_isolates/model/remote_fs_grant.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// Live authorization snapshot consumed by the Rust remote-filesystem server.
final remoteFsAccessProvider = ReduxProvider<RemoteFsAccessService, RemoteFsAccessConfig>((ref) {
  final persistence = ref.read(persistenceProvider);
  return RemoteFsAccessService(
    RemoteFsAccessConfig(
      trustedFingerprints: Set.unmodifiable(persistence.getFavorites().map((device) => device.fingerprint)),
      grants: List.unmodifiable(persistence.getSharedFileRoots().map(toRemoteFsGrant)),
    ),
    onChanged: (access) {
      ref.redux(parentIsolateProvider).dispatch(IsolateHttpServerUpdateRemoteFsAccessAction(access: access));
    },
  );
});

class RemoteFsAccessService extends ReduxNotifier<RemoteFsAccessConfig> {
  final RemoteFsAccessConfig _initial;
  final FutureOr<void> Function(RemoteFsAccessConfig) _onChanged;

  RemoteFsAccessService(this._initial, {required FutureOr<void> Function(RemoteFsAccessConfig) onChanged}) : _onChanged = onChanged;

  @override
  RemoteFsAccessConfig init() => _initial;

  Future<RemoteFsAccessConfig> publish(RemoteFsAccessConfig next) async {
    await _onChanged(next);
    return next;
  }
}

class SetRemoteFsTrustedFingerprintsAction extends AsyncReduxAction<RemoteFsAccessService, RemoteFsAccessConfig> {
  final Iterable<String> fingerprints;

  SetRemoteFsTrustedFingerprintsAction(this.fingerprints);

  @override
  Future<RemoteFsAccessConfig> reduce() {
    return notifier.publish(
      RemoteFsAccessConfig(
        trustedFingerprints: Set.unmodifiable(fingerprints),
        grants: state.grants,
      ),
    );
  }
}

class SetRemoteFsGrantsAction extends AsyncReduxAction<RemoteFsAccessService, RemoteFsAccessConfig> {
  final Iterable<RemoteFsGrant> grants;

  SetRemoteFsGrantsAction(this.grants);

  @override
  Future<RemoteFsAccessConfig> reduce() {
    return notifier.publish(
      RemoteFsAccessConfig(
        trustedFingerprints: state.trustedFingerprints,
        grants: List.unmodifiable(grants),
      ),
    );
  }
}
