import 'package:dart_mappable/dart_mappable.dart';
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';

part 'android_channel.mapper.dart';

const _methodChannel = MethodChannel('com.fireboxtransfer.app/fireboxtransfer');
final _logger = Logger('AndroidSaf');

/// From Android 10 and above, we need to use the Storage Access Framework (SAF) to access files due to the scoped storage.
/// SAF itself is available from Android 4.4 (API level 19).
/// We implemented our own algorithm to build encode and decode content URIs.
/// Older versions might also work but the encoded content URI is not guaranteed to work with our algorithm.
const contentUriMinSdk = 27;

Future<PickDirectoryResult?> pickDirectoryAndroid() async {
  final result = await _methodChannel.invokeMethod<Map>('pickDirectory');
  if (result == null) {
    return null;
  }

  return PickDirectoryResultMapper.fromJson({
    'directoryUri': result['directoryUri'],
    'files': (result['files'] as List).map((e) => FileInfoMapper.fromJson((e as Map).cast<String, dynamic>())).toList(),
  });
}

Future<String?> pickDirectoryPathAndroid() async {
  final result = await _methodChannel.invokeMethod<String>('pickDirectoryPath');
  return result;
}

/// Lists the immediate children of an Android SAF tree selected by the user.
/// [directoryUri] remains an opaque capability; it is deliberately not a path.
Future<List<DirectoryEntry>> listDirectoryAndroid(String directoryUri) async {
  final result = await _methodChannel.invokeListMethod<Map>('listDirectory', {
    'directoryUri': directoryUri,
  });
  if (result == null) return const [];

  return result
      .map(
        (entry) => DirectoryEntry(
          name: entry['name'] as String,
          uri: entry['uri'] as String,
          size: entry['size'] as int,
          lastModified: entry['lastModified'] as int,
          isDirectory: entry['isDirectory'] as bool,
        ),
      )
      .toList(growable: false);
}

/// Opens a lightweight Android tree picker and explicitly registers that tree
/// for the remote explorer. The selected directory is not recursively scanned.
Future<AndroidSafRoot?> pickSharedRootAndroid() async {
  final result = await _methodChannel.invokeMethod<Map>('safPickSharedRoot');
  return result == null ? null : AndroidSafRoot.fromMap(result);
}

Future<List<AndroidSafRoot>> listSharedRootsAndroid() async {
  final result = await _methodChannel.invokeListMethod<Map>('safListSharedRoots');
  return result?.map(AndroidSafRoot.fromMap).toList(growable: false) ?? const [];
}

Future<bool> releaseSharedRootAndroid(String rootUri) async {
  return await _methodChannel.invokeMethod<bool>('safReleaseSharedRoot', {'rootUri': rootUri}) ?? false;
}

Future<List<AndroidSafDocument>> listSharedDirectoryAndroid(String directoryUri) async {
  final result = await _methodChannel.invokeListMethod<Map>('safListDirectory', {'directoryUri': directoryUri});
  return result?.map(AndroidSafDocument.fromMap).toList(growable: false) ?? const [];
}

Future<AndroidSafDocument> getSharedDocumentMetadataAndroid(String uri) async {
  final result = await _methodChannel.invokeMethod<Map>('safGetMetadata', {'uri': uri});
  if (result == null) throw StateError('Android returned no metadata for $uri');
  return AndroidSafDocument.fromMap(result);
}

Future<AndroidSafDocument> resolveSharedRelativePathAndroid({required String rootUri, required String relativePath}) async {
  final result = await _methodChannel.invokeMethod<Map>('safResolvePath', {'rootUri': rootUri, 'relativePath': relativePath});
  if (result == null) throw StateError('Android could not resolve $relativePath below $rootUri');
  return AndroidSafDocument.fromMap(result);
}

Future<AndroidSafDocument> createSharedDirectoryAndroid({required String parentUri, required String name}) async {
  final result = await _methodChannel.invokeMethod<Map>('safCreateDirectory', {'parentUri': parentUri, 'name': name});
  if (result == null) throw StateError('Android could not create $name in $parentUri');
  return AndroidSafDocument.fromMap(result);
}

Future<AndroidSafCreatedFile> createSharedFileAndroid({required String parentUri, required String name, required String mimeType}) async {
  final result = await _methodChannel.invokeMethod<Map>('safCreateFile', {'parentUri': parentUri, 'name': name, 'mimeType': mimeType});
  if (result == null) throw StateError('Android could not create $name in $parentUri');
  return AndroidSafCreatedFile(uri: result['uri'] as String, fileDescriptor: result['fd'] as int);
}

Future<AndroidSafDocument> renameSharedDocumentAndroid({required String uri, required String newName}) async {
  final result = await _methodChannel.invokeMethod<Map>('safRename', {'uri': uri, 'newName': newName});
  if (result == null) throw StateError('Android could not rename $uri');
  return AndroidSafDocument.fromMap(result);
}

Future<AndroidSafDocument> moveSharedDocumentAndroid({required String uri, required String sourceParentUri, required String targetParentUri}) async {
  final result = await _methodChannel.invokeMethod<Map>('safMove', {
    'uri': uri,
    'sourceParentUri': sourceParentUri,
    'targetParentUri': targetParentUri,
  });
  if (result == null) throw StateError('Android could not move $uri');
  return AndroidSafDocument.fromMap(result);
}

Future<void> deleteSharedDocumentAndroid(String uri) async {
  await _methodChannel.invokeMethod<void>('safDelete', {'uri': uri});
}

Future<int> openSharedDocumentForReadingAndroid(String uri) async {
  final descriptor = await _methodChannel.invokeMethod<int>('safOpenRead', {'uri': uri});
  if (descriptor == null) throw StateError('Android returned no readable file descriptor for $uri');
  return descriptor;
}

Future<int> openSharedDocumentForWritingAndroid(String uri, {bool truncate = true}) async {
  final descriptor = await _methodChannel.invokeMethod<int>('safOpenWrite', {'uri': uri, 'truncate': truncate});
  if (descriptor == null) throw StateError('Android returned no writable file descriptor for $uri');
  return descriptor;
}

Future<List<FileInfo>?> pickFilesAndroid() async {
  final result = await _methodChannel.invokeMethod<List>('pickFiles');
  if (result == null) {
    return null;
  }

  return result.map((e) => FileInfoMapper.fromJson((e as Map).cast<String, dynamic>())).toList();
}

/// Returns the global "Download" directory, e.g. /storage/emulated/0/Download.
Future<String?> getDownloadsDirectoryAndroid() async {
  try {
    return await _methodChannel.invokeMethod<String>('getDownloadsDirectory');
  } catch (e) {
    _logger.warning('Could not get downloads directory', e);
    return null;
  }
}

Future<bool> getSystemAnimationsStatusAndroid() async {
  return await _methodChannel.invokeMethod('isAnimationsEnabled') ?? true;
}

Future<void> openContentUri({
  required String uri,
}) async {
  _logger.info('Opening content URI: $uri');
  await _methodChannel.invokeMethod('openContentUri', {
    'uri': uri,
  });
}

Future<void> openGallery() async {
  _logger.info('Opening gallery');
  await _methodChannel.invokeMethod('openGallery');
}

@MappableClass()
class PickDirectoryResult with PickDirectoryResultMappable {
  final String directoryUri;
  final List<FileInfo> files;

  PickDirectoryResult({
    required this.directoryUri,
    required this.files,
  });
}

@MappableClass()
class FileInfo with FileInfoMappable {
  final String name;
  final int size;
  final String uri;
  final int lastModified;

  FileInfo({
    required this.name,
    required this.size,
    required this.uri,
    required this.lastModified,
  });
}

/// A single immediate child of a SAF directory.
///
/// This is intentionally separate from [FileInfo], which represents a file
/// selected for transfer and must retain its backwards-compatible mapper.
class DirectoryEntry {
  final String name;
  final String uri;
  final int size;
  final int lastModified;
  final bool isDirectory;

  const DirectoryEntry({
    required this.name,
    required this.uri,
    required this.size,
    required this.lastModified,
    required this.isDirectory,
  });
}

class AndroidSafRoot {
  final String uri;
  final String name;
  final bool canRead;
  final bool canWrite;

  const AndroidSafRoot({required this.uri, required this.name, required this.canRead, required this.canWrite});

  factory AndroidSafRoot.fromMap(Map<dynamic, dynamic> map) {
    return AndroidSafRoot(uri: map['uri'] as String, name: map['name'] as String, canRead: map['canRead'] as bool, canWrite: map['canWrite'] as bool);
  }
}

class AndroidSafCreatedFile {
  final String uri;
  final int fileDescriptor;

  const AndroidSafCreatedFile({required this.uri, required this.fileDescriptor});
}

class AndroidSafDocument {
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

  const AndroidSafDocument({
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

  factory AndroidSafDocument.fromMap(Map<dynamic, dynamic> map) {
    return AndroidSafDocument(
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
