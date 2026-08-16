import 'package:flutter/services.dart';
import 'package:localsend_isolates/util/content_uri_helper.dart';
import 'package:logging/logging.dart';

const _methodChannel = MethodChannel('com.fireboxtransfer.app/fireboxtransfer');
final _logger = Logger('AndroidSaf');

/// Opens [uri] for reading and returns an owned Linux file descriptor.
///
/// The descriptor stays open after this call and must be closed by the native
/// consumer it is passed to.
Future<int> getFileDescriptorAndroid({required String uri}) async {
  final fileDescriptor = await _methodChannel.invokeMethod<int>(
    'getFileDescriptor',
    {'uri': uri},
  );
  if (fileDescriptor == null) {
    throw StateError('Android returned no file descriptor for $uri');
  }
  return fileDescriptor;
}

Future<void> createDirectory({
  required String documentUri,
  required String directoryName,
}) async {
  _logger.info('Creating directory "$directoryName" in $documentUri');
  await _methodChannel.invokeMethod('createDirectory', {
    'documentUri': documentUri,
    'directoryName': directoryName,
  });
}

Future<void> createMissingDirectoriesAndroid({
  required String parentUri,
  required String fileName,
  required Set<String> createdDirectories,
}) async {
  final parts = fileName.split('/');
  for (int i = 0; i < parts.length - 1; i++) {
    final subDirPath = parts.sublist(0, i + 1).join('/');
    if (createdDirectories.contains(subDirPath)) {
      continue;
    }

    await createDirectory(
      documentUri: ContentUriHelper.convertTreeUriToDocumentUri(
        treeUri: parentUri,
        suffix: i == 0 ? null : parts.sublist(0, i).join('/'),
      ),
      directoryName: parts[i],
    );
    createdDirectories.add(subDirPath);
  }
}

class CreatedFileAndroid {
  /// The URI of the created document. Android may rename the file on collisions.
  final String uri;

  /// An owned writable Linux file descriptor. It stays open after this call and
  /// must be closed by the native consumer it is passed to.
  final int fileDescriptor;

  CreatedFileAndroid({required this.uri, required this.fileDescriptor});
}

/// Creates a new file inside a SAF directory (a tree or document URI)
/// and opens it for writing.
Future<CreatedFileAndroid> createFileAndroid({
  required String parentUri,
  required String fileName,
  required String mimeType,
}) async {
  final result = await _methodChannel.invokeMethod<Map>('createFile', {
    'parentUri': parentUri,
    'fileName': fileName,
    'mimeType': mimeType,
  });
  if (result == null) {
    throw StateError('Android could not create $fileName in $parentUri');
  }
  return CreatedFileAndroid(
    uri: result['uri'] as String,
    fileDescriptor: result['fd'] as int,
  );
}

/// Opens an existing document created by [createFileAndroid] for writing and
/// discards its current content.
///
/// The descriptor stays open after this call and must be closed by the native
/// consumer it is passed to.
Future<int> openFileForWritingAndroid({required String uri}) async {
  final fileDescriptor = await _methodChannel.invokeMethod<int>(
    'openFileForWriting',
    {'uri': uri},
  );
  if (fileDescriptor == null) {
    throw StateError('Android returned no file descriptor for $uri');
  }
  return fileDescriptor;
}

/// Opens the Android system tree picker and registers the selected directory
/// as an explicit remote-filesystem root. Unlike the legacy directory picker,
/// this does not recursively enumerate the selected tree.
Future<SafRootAndroid?> pickSharedRootAndroid() async {
  final result = await _methodChannel.invokeMethod<Map>('safPickSharedRoot');
  return result == null ? null : SafRootAndroid.fromMap(result);
}

Future<List<SafRootAndroid>> listSharedRootsAndroid() async {
  final result = await _methodChannel.invokeListMethod<Map>(
    'safListSharedRoots',
  );
  return result?.map(SafRootAndroid.fromMap).toList(growable: false) ?? const [];
}

/// Stops sharing [rootUri] and releases its persisted Android grant.
Future<bool> releaseSharedRootAndroid({required String rootUri}) async {
  return await _methodChannel.invokeMethod<bool>('safReleaseSharedRoot', {
        'rootUri': rootUri,
      }) ??
      false;
}

Future<List<SafDocumentAndroid>> listSafDirectoryAndroid({
  required String directoryUri,
}) async {
  final result = await _methodChannel.invokeListMethod<Map>(
    'safListDirectory',
    {'directoryUri': directoryUri},
  );
  return result?.map(SafDocumentAndroid.fromMap).toList(growable: false) ?? const [];
}

Future<SafDocumentAndroid> getSafMetadataAndroid({required String uri}) async {
  final result = await _methodChannel.invokeMethod<Map>('safGetMetadata', {
    'uri': uri,
  });
  if (result == null) throw StateError('Android returned no metadata for $uri');
  return SafDocumentAndroid.fromMap(result);
}

/// Resolves [relativePath] below [rootUri] by asking the provider for each
/// directory child. No URI or filesystem path is synthesized from user input.
Future<SafDocumentAndroid> resolveSafRelativePathAndroid({
  required String rootUri,
  required String relativePath,
}) async {
  final result = await _methodChannel.invokeMethod<Map>('safResolvePath', {
    'rootUri': rootUri,
    'relativePath': relativePath,
  });
  if (result == null) {
    throw StateError('Android could not resolve $relativePath below $rootUri');
  }
  return SafDocumentAndroid.fromMap(result);
}

Future<SafDocumentAndroid> createSafDirectoryAndroid({
  required String parentUri,
  required String name,
}) async {
  final result = await _methodChannel.invokeMethod<Map>('safCreateDirectory', {
    'parentUri': parentUri,
    'name': name,
  });
  if (result == null) {
    throw StateError('Android could not create $name in $parentUri');
  }
  return SafDocumentAndroid.fromMap(result);
}

/// Creates a file inside an explicitly shared root and returns an owned file
/// descriptor. Its native consumer is responsible for closing the descriptor.
Future<CreatedFileAndroid> createSafFileAndroid({
  required String parentUri,
  required String name,
  required String mimeType,
}) async {
  final result = await _methodChannel.invokeMethod<Map>('safCreateFile', {
    'parentUri': parentUri,
    'name': name,
    'mimeType': mimeType,
  });
  if (result == null) {
    throw StateError('Android could not create $name in $parentUri');
  }
  return CreatedFileAndroid(
    uri: result['uri'] as String,
    fileDescriptor: result['fd'] as int,
  );
}

Future<SafDocumentAndroid> renameSafDocumentAndroid({
  required String uri,
  required String newName,
}) async {
  final result = await _methodChannel.invokeMethod<Map>('safRename', {
    'uri': uri,
    'newName': newName,
  });
  if (result == null) throw StateError('Android could not rename $uri');
  return SafDocumentAndroid.fromMap(result);
}

Future<SafDocumentAndroid> moveSafDocumentAndroid({
  required String uri,
  required String sourceParentUri,
  required String targetParentUri,
}) async {
  final result = await _methodChannel.invokeMethod<Map>('safMove', {
    'uri': uri,
    'sourceParentUri': sourceParentUri,
    'targetParentUri': targetParentUri,
  });
  if (result == null) throw StateError('Android could not move $uri');
  return SafDocumentAndroid.fromMap(result);
}

Future<void> deleteSafDocumentAndroid({required String uri}) async {
  await _methodChannel.invokeMethod<void>('safDelete', {'uri': uri});
}

/// Returns an owned readable descriptor for a document in a shared root.
Future<int> openSafDocumentForReadingAndroid({required String uri}) async {
  final descriptor = await _methodChannel.invokeMethod<int>('safOpenRead', {
    'uri': uri,
  });
  if (descriptor == null) {
    throw StateError('Android returned no readable file descriptor for $uri');
  }
  return descriptor;
}

/// Returns an owned writable descriptor for a document in a shared root.
Future<int> openSafDocumentForWritingAndroid({
  required String uri,
  bool truncate = true,
}) async {
  final descriptor = await _methodChannel.invokeMethod<int>('safOpenWrite', {
    'uri': uri,
    'truncate': truncate,
  });
  if (descriptor == null) {
    throw StateError('Android returned no writable file descriptor for $uri');
  }
  return descriptor;
}

/// A persisted Android SAF tree that the user explicitly made available to
/// FireBoxTransfer's remote explorer. Contains primitives only, so it can be
/// sent between Dart isolates.
class SafRootAndroid {
  final String uri;
  final String name;
  final bool canRead;
  final bool canWrite;

  const SafRootAndroid({
    required this.uri,
    required this.name,
    required this.canRead,
    required this.canWrite,
  });

  factory SafRootAndroid.fromMap(Map<dynamic, dynamic> map) {
    return SafRootAndroid(
      uri: map['uri'] as String,
      name: map['name'] as String,
      canRead: map['canRead'] as bool,
      canWrite: map['canWrite'] as bool,
    );
  }
}

/// Metadata and provider-advertised capabilities for one SAF document.
/// The URI is an opaque capability and must never be converted to a path.
class SafDocumentAndroid {
  final String uri;
  final String name;
  final String mimeType;
  final int? size;
  final int? lastModified;
  final int flags;
  final bool isDirectory;
  final bool canRead;
  final bool canWrite;
  final bool canCreate;
  final bool canRename;
  final bool canMove;
  final bool canDelete;

  const SafDocumentAndroid({
    required this.uri,
    required this.name,
    required this.mimeType,
    required this.size,
    required this.lastModified,
    required this.flags,
    required this.isDirectory,
    required this.canRead,
    required this.canWrite,
    required this.canCreate,
    required this.canRename,
    required this.canMove,
    required this.canDelete,
  });

  factory SafDocumentAndroid.fromMap(Map<dynamic, dynamic> map) {
    return SafDocumentAndroid(
      uri: map['uri'] as String,
      name: map['name'] as String,
      mimeType: map['mimeType'] as String,
      size: map['size'] as int?,
      lastModified: map['lastModified'] as int?,
      flags: map['flags'] as int,
      isDirectory: map['isDirectory'] as bool,
      canRead: map['canRead'] as bool,
      canWrite: map['canWrite'] as bool,
      canCreate: map['canCreate'] as bool,
      canRename: map['canRename'] as bool,
      canMove: map['canMove'] as bool,
      canDelete: map['canDelete'] as bool,
    );
  }
}
