/// Platform-specific storage capability explicitly granted by the user.
///
/// [locator] never crosses the network boundary. Remote peers address data by
/// [id] and a validated relative path only.
class RemoteFsGrant {
  final String id;
  final String displayName;
  final RemoteFsGrantKind kind;
  final String locator;
  final bool readOnly;

  const RemoteFsGrant({
    required this.id,
    required this.displayName,
    required this.kind,
    required this.locator,
    required this.readOnly,
  });
}

enum RemoteFsGrantKind {
  localPath,
  androidSaf,
}

/// Snapshot of remote-filesystem authorization. All fields contain only
/// isolate-sendable values and can be replaced while the server keeps running.
class RemoteFsAccessConfig {
  final Set<String> trustedFingerprints;
  final List<RemoteFsGrant> grants;

  const RemoteFsAccessConfig({
    required this.trustedFingerprints,
    required this.grants,
  });

  static const empty = RemoteFsAccessConfig(
    trustedFingerprints: {},
    grants: [],
  );
}
