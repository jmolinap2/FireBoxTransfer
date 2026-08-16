enum ExplorerPlatformKind { windows, android, linux, macos, ios, unknown }

enum ExplorerConnectionStatus { local, connecting, connected, offline }

enum ExplorerEntryKind { file, directory }

enum ExplorerSortField { name, size, modifiedAt }

enum ExplorerSortDirection { ascending, descending }

enum ExplorerTransferOperation { copy, move }

class ExplorerDevice {
  const ExplorerDevice({
    required this.id,
    required this.name,
    required this.platform,
    required this.connectionStatus,
  });

  final String id;
  final String name;
  final ExplorerPlatformKind platform;
  final ExplorerConnectionStatus connectionStatus;
}

class ExplorerCapabilities {
  const ExplorerCapabilities({
    this.browse = true,
    this.read = true,
    this.write = false,
    this.createDirectory = false,
    this.rename = false,
    this.move = false,
    this.delete = false,
  });

  const ExplorerCapabilities.readOnly() : this();

  const ExplorerCapabilities.readWrite()
    : this(
        write: true,
        createDirectory: true,
        rename: true,
        move: true,
        delete: true,
      );

  final bool browse;
  final bool read;
  final bool write;
  final bool createDirectory;
  final bool rename;
  final bool move;
  final bool delete;
}

class ExplorerRoot {
  const ExplorerRoot({
    required this.id,
    required this.label,
    required this.initialPath,
    this.capabilities = const ExplorerCapabilities.readOnly(),
  });

  /// Stable identifier assigned by the filesystem provider.
  final String id;

  /// Human-readable label, for example "Descargas autorizadas".
  final String label;

  /// Opaque provider path. It may be a native path, URI, document id, or token.
  final String initialPath;
  final ExplorerCapabilities capabilities;
}

class ExplorerDirectoryRef {
  const ExplorerDirectoryRef({
    required this.rootId,
    required this.path,
    required this.displayPath,
    this.parentPath,
  });

  final String rootId;

  /// Opaque provider path. The UI must never concatenate or normalize it.
  final String path;
  final String displayPath;

  /// Opaque parent path, when the provider allows navigating to it.
  final String? parentPath;
}

class ExplorerFileEntry {
  const ExplorerFileEntry({
    required this.id,
    required this.name,
    required this.path,
    required this.kind,
    this.sizeBytes,
    this.modifiedAt,
    this.mimeType,
    this.capabilities,
  });

  final String id;
  final String name;

  /// Opaque provider path. It is deliberately not interpreted by the UI.
  final String path;
  final ExplorerEntryKind kind;
  final int? sizeBytes;
  final DateTime? modifiedAt;
  final String? mimeType;
  final ExplorerCapabilities? capabilities;

  bool get isDirectory => kind == ExplorerEntryKind.directory;
}

class ExplorerStorageInfo {
  const ExplorerStorageInfo({required this.totalBytes, required this.freeBytes}) : assert(totalBytes >= 0), assert(freeBytes >= 0);

  final int totalBytes;
  final int freeBytes;

  int get usedBytes => (totalBytes - freeBytes).clamp(0, totalBytes).toInt();
  double get usedFraction => totalBytes == 0 ? 0 : usedBytes / totalBytes;
}

class ExplorerDirectoryListing {
  const ExplorerDirectoryListing({
    required this.location,
    required this.entries,
    required this.capabilities,
    this.storage,
  });

  final ExplorerDirectoryRef location;
  final List<ExplorerFileEntry> entries;
  final ExplorerCapabilities capabilities;
  final ExplorerStorageInfo? storage;
}

class ExplorerDragPayload {
  const ExplorerDragPayload({
    required this.sourcePanelId,
    required this.sourceRoot,
    required this.sourceDirectory,
    required this.entries,
  });

  final String sourcePanelId;
  final ExplorerRoot sourceRoot;
  final ExplorerDirectoryRef sourceDirectory;
  final List<ExplorerFileEntry> entries;
}

class ExplorerTransferRequest {
  const ExplorerTransferRequest({
    required this.sourcePanelId,
    required this.targetPanelId,
    required this.sourceRoot,
    required this.sourceDirectory,
    required this.entries,
    required this.targetRoot,
    required this.targetDirectory,
    this.operation = ExplorerTransferOperation.copy,
  });

  final String sourcePanelId;
  final String targetPanelId;
  final ExplorerRoot sourceRoot;
  final ExplorerDirectoryRef sourceDirectory;
  final List<ExplorerFileEntry> entries;
  final ExplorerRoot targetRoot;
  final ExplorerDirectoryRef targetDirectory;
  final ExplorerTransferOperation operation;
}
