import 'package:fireboxtransfer_app/model/persistence/shared_file_root.dart';
import 'package:localsend_isolates/model/remote_fs_grant.dart';

RemoteFsGrant toRemoteFsGrant(SharedFileRoot root) {
  return RemoteFsGrant(
    id: root.id,
    displayName: root.name,
    kind: switch (root.type) {
      SharedFileRootType.localPath => RemoteFsGrantKind.localPath,
      SharedFileRootType.androidSaf => RemoteFsGrantKind.androidSaf,
    },
    locator: root.locator,
    readOnly: root.readOnly,
  );
}
