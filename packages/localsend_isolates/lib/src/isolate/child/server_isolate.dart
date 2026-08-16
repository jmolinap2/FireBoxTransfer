import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:localsend_isolates/constants.dart';
import 'package:localsend_isolates/model/dto/multicast_dto.dart';
import 'package:localsend_isolates/model/file_type.dart';
import 'package:localsend_isolates/model/remote_fs_grant.dart';
import 'package:localsend_isolates/rust/api/model.dart' hide ProtocolType;
import 'package:localsend_isolates/rust/api/server.dart';
import 'package:localsend_isolates/src/isolate/child/main.dart';
import 'package:localsend_isolates/src/isolate/child/sync_provider.dart';
import 'package:localsend_isolates/src/isolate/dto/send_to_isolate_data.dart';
import 'package:localsend_isolates/src/task/server/file_saver.dart';
import 'package:localsend_isolates/src/task/server/http_server.dart';
import 'package:localsend_isolates/util/android_channel.dart' as android_channel;
import 'package:localsend_isolates/util/future_queue.dart';
import 'package:localsend_isolates/util/rust.dart';
import 'package:logging/logging.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;
import 'package:refena_flutter/refena_flutter.dart';
import 'package:typed_isolates/typed_isolates.dart';

final _logger = Logger('HttpServerIsolate');

sealed class BaseHttpServerTask {}

/// Starts the HTTP server.
/// The device information is derived from the sync state.
///
/// The server emits [HttpServerEvent]s on the stream of this task
/// until the server is stopped via [HttpServerStopTask].
class HttpServerStartTask implements BaseHttpServerTask {
  /// Optional PIN that senders must provide to start an upload session.
  final String? pin;

  /// Whether the SHA-256 checksums that senders provide for their files are
  /// verified after receiving.
  final bool verifyChecksums;

  /// Serves the web pages: the download page (web send) and/or the upload page.
  /// `null` disables the web pages.
  final WebParams? web;

  /// Enables the internal `show` endpoint, guarded by this token, that lets another
  /// application instance request this one to show itself. `null` disables it.
  final String? showToken;

  /// Snapshot updated by [HttpServerUpdateRemoteFsAccessTask]. Remote requests
  /// are checked against it immediately before each filesystem operation.
  final RemoteFsAccessConfig remoteFsAccess;

  HttpServerStartTask({
    required this.pin,
    required this.verifyChecksums,
    required this.web,
    required this.showToken,
    required this.remoteFsAccess,
  });
}

/// Replaces the trusted-peer and shared-root snapshot without restarting the
/// HTTP listener or interrupting unrelated transfers.
class HttpServerUpdateRemoteFsAccessTask implements BaseHttpServerTask {
  final RemoteFsAccessConfig access;

  HttpServerUpdateRemoteFsAccessTask({required this.access});
}

/// Stops the HTTP server.
/// The stream of this task completes once the server has released the port.
class HttpServerStopTask implements BaseHttpServerTask {}

/// Everything the server isolate needs to receive the accepted files on its
/// own, without further involvement of the main isolate.
class HttpServerReceiveConfig {
  /// The session ID of the [HttpServerPrepareUploadEvent] being answered.
  final String sessionId;

  /// The accepted file IDs mapped to the desired file name
  /// (may contain a relative directory prefix).
  final Map<String, String> fileNameMap;

  final String destinationDirectory;

  /// Used as intermediate storage when [saveToGallery] is enabled.
  final String cacheDirectory;

  /// Save received images/videos to the OS gallery instead of
  /// [destinationDirectory].
  final bool saveToGallery;

  /// The Android SDK version, `null` on other platforms. Enables SAF handling
  /// for destinations that cannot be written directly.
  final int? androidSdkInt;

  HttpServerReceiveConfig({
    required this.sessionId,
    required this.fileNameMap,
    required this.destinationDirectory,
    required this.cacheDirectory,
    required this.saveToGallery,
    required this.androidSdkInt,
  });
}

/// Answers a pending [HttpServerPrepareUploadEvent].
///
/// When accepted, the server isolate receives all files on its own:
/// it resolves the save target for every upload, lets the Rust server write
/// the file and applies post-processing (timestamps, gallery). The main
/// isolate only observes [HttpServerFileUploadEvent],
/// [HttpServerFileUploadProgressEvent] and [HttpServerFileUploadResultEvent]
/// on the server event stream and may cancel the session via
/// [HttpServerCancelSessionTask].
class HttpServerPrepareUploadDecisionTask implements BaseHttpServerTask {
  /// The receive configuration including the accepted file IDs.
  /// `null` declines the request.
  final HttpServerReceiveConfig? config;

  HttpServerPrepareUploadDecisionTask({
    required this.config,
  });
}

/// Cancels the active upload session, e.g. because the user aborted the
/// transfer on the receiving side. Uploads that are already in progress still
/// run to completion, but new upload requests are rejected and a new session
/// can be created. No [HttpServerSessionEndEvent] is emitted.
class HttpServerCancelSessionTask implements BaseHttpServerTask {
  final String sessionId;

  HttpServerCancelSessionTask({
    required this.sessionId,
  });
}

/// Answers a pending [HttpServerWebPrepareDownloadEvent].
class HttpServerPrepareDownloadDecisionTask implements BaseHttpServerTask {
  final String sessionId;

  /// `true` accepts the download request, `false` declines it.
  final bool accept;

  HttpServerPrepareDownloadDecisionTask({
    required this.sessionId,
    required this.accept,
  });
}

/// Answers a pending [HttpServerWebFileDownloadEvent] with the source the file
/// content should be read from: either a file [path] or a readable [fileDescriptor] (Android).
///
/// The file is read and streamed by the Rust server itself.
class HttpServerFileDownloadTargetTask implements BaseHttpServerTask {
  final String sessionId;
  final String fileId;
  final String? path;
  final int? fileDescriptor;

  HttpServerFileDownloadTargetTask({
    required this.sessionId,
    required this.fileId,
    required this.path,
    required this.fileDescriptor,
  });
}

/// Fails a pending [HttpServerWebFileDownloadEvent], e.g. because no source
/// for the file content could be resolved. The download request fails with an
/// error response. Does nothing if the download was already answered with a
/// [HttpServerFileDownloadTargetTask].
class HttpServerFailFileDownloadTask implements BaseHttpServerTask {
  final String sessionId;
  final String fileId;

  HttpServerFailFileDownloadTask({
    required this.sessionId,
    required this.fileId,
  });
}

/// A message sent from the server isolate to the main isolate.
sealed class HttpServerEvent {}

/// The server has been started and is listening.
/// Always the first event emitted by a [HttpServerStartTask].
class HttpServerStartedEvent extends HttpServerEvent {}

/// A device registered itself on this server.
///
/// On TLS, this event is only emitted when [RegisterDtoV2.fingerprint] matches
/// the fingerprint of the client certificate verified during the mTLS
/// handshake, so the fingerprint cannot be spoofed.
class HttpServerRegisterEvent extends HttpServerEvent {
  final String ip;
  final RegisterDtoV2 info;

  HttpServerRegisterEvent({
    required this.ip,
    required this.info,
  });
}

/// A sender requests to upload files.
/// Must be answered with a [HttpServerPrepareUploadDecisionTask].
class HttpServerPrepareUploadEvent extends HttpServerEvent {
  /// The session ID the upload session will have when the request is accepted.
  final String sessionId;
  final String ip;
  final RegisterDtoV2 info;

  /// The SHA-256 fingerprint (uppercase hex) of the sender's client
  /// certificate verified during the mTLS handshake. Unlike
  /// [RegisterDtoV2.fingerprint], this value cannot be spoofed.
  /// `null` when the server runs without TLS.
  final String? certFingerprint;

  final Map<String, FileDto> files;

  HttpServerPrepareUploadEvent({
    required this.sessionId,
    required this.ip,
    required this.info,
    required this.certFingerprint,
    required this.files,
  });
}

/// An accepted file started being uploaded.
/// The server isolate receives and saves the file on its own; the main
/// isolate only needs to update its view of the session.
class HttpServerFileUploadEvent extends HttpServerEvent {
  final String sessionId;
  final String fileId;
  final FileDto file;

  HttpServerFileUploadEvent({
    required this.sessionId,
    required this.fileId,
    required this.file,
  });
}

/// The receive progress of a file as a fraction (0.0 to 1.0).
class HttpServerFileUploadProgressEvent extends HttpServerEvent {
  final String sessionId;
  final String fileId;
  final double progress;

  HttpServerFileUploadProgressEvent({
    required this.sessionId,
    required this.fileId,
    required this.progress,
  });
}

/// A file of the upload session has been received completely (or failed).
class HttpServerFileUploadResultEvent extends HttpServerEvent {
  final String sessionId;
  final String fileId;

  /// The path or content URI the file has been saved to.
  /// `null` when the file was saved to the gallery or on error.
  final String? path;

  /// Whether the file ended up in the OS gallery.
  final bool savedToGallery;

  /// `null` if the file has been saved successfully.
  final String? error;

  HttpServerFileUploadResultEvent({
    required this.sessionId,
    required this.fileId,
    required this.path,
    required this.savedToGallery,
    required this.error,
  });
}

/// An upload session ended.
class HttpServerSessionEndEvent extends HttpServerEvent {
  final String sessionId;
  final SessionEndReasonV2 reason;

  HttpServerSessionEndEvent({
    required this.sessionId,
    required this.reason,
  });
}

/// A prepare-upload request was aborted before a session was created,
/// e.g. the sender disconnected while the application was still deciding.
/// The [HttpServerPrepareUploadEvent] with the same [sessionId]
/// no longer needs to be answered.
class HttpServerPrepareUploadAbortedEvent extends HttpServerEvent {
  final String sessionId;

  HttpServerPrepareUploadAbortedEvent({required this.sessionId});
}

/// The remote device cancels a transfer this application is currently
/// *sending* to it. [sessionId] is the session ID issued by the remote device
/// during prepare-upload. The application must verify that [ip] matches the
/// target of the send session before cancelling it.
class HttpServerCancelReceivedEvent extends HttpServerEvent {
  final String ip;
  final String sessionId;

  HttpServerCancelReceivedEvent({
    required this.ip,
    required this.sessionId,
  });
}

/// A web client requests to download the shared files.
/// Must be answered with a [HttpServerPrepareDownloadDecisionTask].
class HttpServerWebPrepareDownloadEvent extends HttpServerEvent {
  final String ip;
  final String sessionId;
  final String? userAgent;

  HttpServerWebPrepareDownloadEvent({
    required this.ip,
    required this.sessionId,
    required this.userAgent,
  });
}

/// A web client downloads an offered file.
/// Must be answered with a [HttpServerFileDownloadTargetTask].
class HttpServerWebFileDownloadEvent extends HttpServerEvent {
  final String sessionId;
  final String fileId;
  final FileDto file;

  HttpServerWebFileDownloadEvent({
    required this.sessionId,
    required this.fileId,
    required this.file,
  });
}

/// Another application instance requested the running application to show itself.
class HttpServerShowEvent extends HttpServerEvent {
  /// Command-line arguments forwarded by the other application instance.
  final List<String> args;

  HttpServerShowEvent({
    required this.args,
  });
}

class _ReceiveSession {
  final HttpServerReceiveConfig config;

  /// Directories already created inside the destination, shared across all
  /// files of the session.
  final Set<String> createdDirectories = {};

  /// One queue per file ID, so that uploads of the same file do not overlap.
  ///
  /// A sender may upload the same file again after it was rejected because of
  /// a checksum mismatch. Both attempts write to the same [targets] entry.
  final Map<String, FutureQueue> uploads = {};

  /// The destination of each file of this session, by file ID.
  ///
  /// Remembered so that another attempt at the same file overwrites it instead
  /// of being saved next to it under a numbered name.
  final Map<String, FileSaveTarget> targets = {};

  _ReceiveSession(this.config);
}

/// Holds the active receive session, set when a prepare-upload request is accepted.
final _receiveSessionProvider = Provider((ref) => _ReceiveSessionHolder());

final _remoteFsAccessProvider = Provider((ref) => _RemoteFsAccessHolder());

class _RemoteFsAccessHolder {
  RemoteFsAccessConfig _value = RemoteFsAccessConfig.empty;

  RemoteFsAccessConfig get value => _value;

  set value(RemoteFsAccessConfig value) {
    _value = RemoteFsAccessConfig(
      trustedFingerprints: Set.unmodifiable(value.trustedFingerprints.map(_normalizeFingerprint)),
      grants: List.unmodifiable(value.grants),
    );
  }
}

class _ReceiveSessionHolder {
  _ReceiveSession? session;
}

Future<void> setupHttpServerIsolate(
  Stream<SendToIsolateData<IsolateTask<BaseHttpServerTask>>> receiveFromMain,
  void Function(IsolateTaskStreamResult<HttpServerEvent>) sendToMain,
  InitialData initialData,
) async {
  await setupChildIsolateHelper(
    debugLabel: 'HttpServerIsolate',
    receiveFromMain: receiveFromMain,
    sendToMain: sendToMain,
    initialData: initialData,
    init: (ref) async {
      // Initialize the platform method channel so SAF (file creation) and the
      // gallery plugin work inside this isolate.
      BackgroundIsolateBinaryMessenger.ensureInitialized(
        ref.read(syncProvider).rootIsolateToken as RootIsolateToken,
      );
    },
    handler: (ref, task) async {
      switch (task.data) {
        case HttpServerStartTask startTask:
          ref.read(_remoteFsAccessProvider).value = startTask.remoteFsAccess;
          final syncState = ref.read(syncProvider);
          final Stream<RsServerEvent> events;
          try {
            events = await ref
                .read(httpServerProvider)
                .start(
                  port: syncState.port,
                  tls: syncState.protocol == ProtocolType.https
                      ? TlsConfig(
                          cert: syncState.securityContext.certificate,
                          privateKey: syncState.securityContext.privateKey,
                        )
                      : null,
                  alias: syncState.alias,
                  version: protocolVersion,
                  deviceModel: syncState.deviceInfo.deviceModel,
                  deviceType: syncState.deviceInfo.deviceType.toRust(),
                  fingerprint: syncState.securityContext.certificateHash,
                  pin: startTask.pin,
                  verifyChecksums: startTask.verifyChecksums,
                  web: startTask.web,
                  showToken: startTask.showToken,
                  enableRemoteFs: syncState.protocol == ProtocolType.https,
                );
          } catch (e) {
            // Starting failed (e.g. the port is already in use).
            // The error must be sendable across the isolate boundary.
            sendToMain(
              IsolateTaskStreamResult.error(
                id: task.id,
                error: e.humanErrorMessage,
              ),
            );
            return;
          }

          sendToMain(
            IsolateTaskStreamResult.event(
              id: task.id,
              data: HttpServerStartedEvent(),
            ),
          );

          void emit(HttpServerEvent data) {
            sendToMain(
              IsolateTaskStreamResult.event(
                id: task.id,
                data: data,
              ),
            );
          }

          try {
            await for (final event in events) {
              final holder = ref.read(_receiveSessionProvider);
              switch (event) {
                case RsServerEvent_Register(:final ip, :final info):
                  emit(HttpServerRegisterEvent(ip: ip, info: info));
                case RsServerEvent_PrepareUpload(:final sessionId, :final ip, :final info, :final certFingerprint, :final files):
                  // The Rust server is the authority on the single-session
                  // invariant: a new request means the old session is over.
                  holder.session = null;
                  emit(
                    HttpServerPrepareUploadEvent(
                      sessionId: sessionId,
                      ip: ip,
                      info: info,
                      certFingerprint: certFingerprint,
                      files: files,
                    ),
                  );
                case RsServerEvent_FileUpload(:final sessionId, :final fileId, :final file):
                  final session = holder.session;
                  if (session == null || session.config.sessionId != sessionId || !session.config.fileNameMap.containsKey(fileId)) {
                    _logger.warning('Rejecting upload of file $fileId: no matching active session');
                    // Reject the upload (and any further ones) by cancelling the session.
                    unawaited(ref.read(httpServerProvider).cancelSession(sessionId: sessionId));
                    break;
                  }

                  // Files may be uploaded concurrently, so the event loop must
                  // not block. Attempts of the same file are queued instead,
                  // see [_ReceiveSession.uploads].
                  final queue = session.uploads.putIfAbsent(
                    fileId,
                    () => FutureQueue(onError: (e, st) => _logger.severe('Unexpected error while receiving file $fileId', e, st)),
                  );
                  queue.add(() async {
                    emit(
                      HttpServerFileUploadEvent(
                        sessionId: sessionId,
                        fileId: fileId,
                        file: file,
                      ),
                    );

                    await _handleFileUpload(
                      ref: ref,
                      session: session,
                      sessionId: sessionId,
                      fileId: fileId,
                      file: file,
                      emit: emit,
                    );
                  });
                case RsServerEvent_SessionEnd(:final sessionId, :final reason):
                  if (holder.session?.config.sessionId == sessionId) {
                    holder.session = null;
                  }
                  emit(
                    HttpServerSessionEndEvent(
                      sessionId: sessionId,
                      reason: reason,
                    ),
                  );
                case RsServerEvent_PrepareUploadAborted(:final sessionId):
                  emit(
                    HttpServerPrepareUploadAbortedEvent(
                      sessionId: sessionId,
                    ),
                  );
                case RsServerEvent_CancelReceived(:final ip, :final sessionId):
                  emit(
                    HttpServerCancelReceivedEvent(
                      ip: ip,
                      sessionId: sessionId,
                    ),
                  );
                case RsServerEvent_WebPrepareDownload(:final ip, :final sessionId, :final userAgent):
                  emit(
                    HttpServerWebPrepareDownloadEvent(
                      ip: ip,
                      sessionId: sessionId,
                      userAgent: userAgent,
                    ),
                  );
                case RsServerEvent_WebFileDownload(:final sessionId, :final fileId, :final file):
                  emit(
                    HttpServerWebFileDownloadEvent(
                      sessionId: sessionId,
                      fileId: fileId,
                      file: file,
                    ),
                  );
                case RsServerEvent_Show(:final args):
                  emit(HttpServerShowEvent(args: args));
                case RsServerEvent_RemoteFsRoots():
                  unawaited(_handleRemoteFsEvent(ref, event));
                case RsServerEvent_RemoteFsList():
                  unawaited(_handleRemoteFsEvent(ref, event));
                case RsServerEvent_RemoteFsMetadata():
                  unawaited(_handleRemoteFsEvent(ref, event));
                case RsServerEvent_RemoteFsCreateDirectory():
                  unawaited(_handleRemoteFsEvent(ref, event));
                case RsServerEvent_RemoteFsRename():
                  unawaited(_handleRemoteFsEvent(ref, event));
                case RsServerEvent_RemoteFsMove():
                  unawaited(_handleRemoteFsEvent(ref, event));
                case RsServerEvent_RemoteFsDelete():
                  unawaited(_handleRemoteFsEvent(ref, event));
                case RsServerEvent_RemoteFsRead():
                  unawaited(_handleRemoteFsEvent(ref, event));
                case RsServerEvent_RemoteFsWrite():
                  unawaited(_handleRemoteFsEvent(ref, event));
              }
            }
          } finally {
            ref.read(_receiveSessionProvider).session = null;
            sendToMain(
              IsolateTaskStreamResult.done(
                id: task.id,
              ),
            );
          }
          return;
        case HttpServerStopTask _:
          ref.read(_receiveSessionProvider).session = null;
          await ref.read(httpServerProvider).stop();
          sendToMain(
            IsolateTaskStreamResult.done(
              id: task.id,
            ),
          );
          return;
        case HttpServerUpdateRemoteFsAccessTask updateTask:
          ref.read(_remoteFsAccessProvider).value = updateTask.access;
          return;
        case HttpServerPrepareUploadDecisionTask decisionTask:
          final config = decisionTask.config;
          // An empty fileNameMap accepts nothing: the Rust server responds
          // with 204 and creates no session.
          ref.read(_receiveSessionProvider).session = config == null || config.fileNameMap.isEmpty ? null : _ReceiveSession(config);
          await ref.read(httpServerProvider).respondPrepareUpload(acceptedFileIds: config?.fileNameMap.keys.toList());
          return;
        case HttpServerCancelSessionTask cancelTask:
          final holder = ref.read(_receiveSessionProvider);
          if (holder.session?.config.sessionId == cancelTask.sessionId) {
            holder.session = null;
          }
          await ref.read(httpServerProvider).cancelSession(sessionId: cancelTask.sessionId);
          return;
        case HttpServerPrepareDownloadDecisionTask decisionTask:
          await ref
              .read(httpServerProvider)
              .respondPrepareDownload(
                sessionId: decisionTask.sessionId,
                accept: decisionTask.accept,
              );
          return;
        case HttpServerFileDownloadTargetTask targetTask:
          await ref
              .read(httpServerProvider)
              .respondFileDownload(
                sessionId: targetTask.sessionId,
                fileId: targetTask.fileId,
                path: targetTask.path,
                fileDescriptor: targetTask.fileDescriptor,
              );
          return;
        case HttpServerFailFileDownloadTask failTask:
          await ref
              .read(httpServerProvider)
              .failFileDownload(
                sessionId: failTask.sessionId,
                fileId: failTask.fileId,
              );
          return;
      }
    },
  );
}

/// Handles authenticated remote-filesystem requests without blocking the
/// server event loop. Every request reads the current trust/grant snapshot;
/// updates therefore take effect without restarting the listener.
Future<void> _handleRemoteFsEvent(Ref ref, RsServerEvent event) async {
  final requestId = switch (event) {
    RsServerEvent_RemoteFsRoots(:final requestId) => requestId,
    RsServerEvent_RemoteFsList(:final requestId) => requestId,
    RsServerEvent_RemoteFsMetadata(:final requestId) => requestId,
    RsServerEvent_RemoteFsCreateDirectory(:final requestId) => requestId,
    RsServerEvent_RemoteFsRename(:final requestId) => requestId,
    RsServerEvent_RemoteFsMove(:final requestId) => requestId,
    RsServerEvent_RemoteFsDelete(:final requestId) => requestId,
    RsServerEvent_RemoteFsRead(:final requestId) => requestId,
    RsServerEvent_RemoteFsWrite(:final requestId) => requestId,
    _ => throw StateError('Unexpected non-filesystem server event'),
  };

  try {
    switch (event) {
      case RsServerEvent_RemoteFsRoots(:final peer):
        await _respondRemoteFsRoots(ref, requestId, peer);
      case RsServerEvent_RemoteFsList(:final peer, :final request):
        await _respondRemoteFsList(ref, requestId, peer, request);
      case RsServerEvent_RemoteFsMetadata(:final peer, :final target):
        await _respondRemoteFsMetadata(ref, requestId, peer, target);
      case RsServerEvent_RemoteFsCreateDirectory(:final peer, :final request):
        await _respondRemoteFsCreateDirectory(ref, requestId, peer, request);
      case RsServerEvent_RemoteFsRename(:final peer, :final request):
        await _respondRemoteFsRename(ref, requestId, peer, request);
      case RsServerEvent_RemoteFsMove(:final peer, :final request):
        await _respondRemoteFsMove(ref, requestId, peer, request);
      case RsServerEvent_RemoteFsDelete(:final peer, :final request):
        await _respondRemoteFsDelete(ref, requestId, peer, request);
      case RsServerEvent_RemoteFsRead(:final peer, :final target):
        await _respondRemoteFsRead(ref, requestId, peer, target);
      case RsServerEvent_RemoteFsWrite(:final peer, :final request):
        await _respondRemoteFsWrite(ref, requestId, peer, request);
      default:
        return;
    }
  } catch (error, stackTrace) {
    final code = _remoteFsErrorCode(error);
    _logger.warning('Remote filesystem request $requestId failed with ${code.name} (${error.runtimeType})', null, stackTrace);
    try {
      await ref.read(httpServerProvider).respondRemoteFsError(requestId: requestId, error: code);
    } catch (_) {
      // The HTTP request may have timed out or its responder may already have
      // been committed to a streaming read/write target.
    }
  }
}

Future<void> _respondRemoteFsRoots(Ref ref, String requestId, RsRemoteFsPeer peer) async {
  _requireTrustedPeer(ref, peer);
  final access = ref.read(_remoteFsAccessProvider).value;
  final roots = <RemoteFsRoot>[];
  for (final grant in access.grants) {
    if (!_validPublicRoot(grant) || access.grants.where((candidate) => candidate.id == grant.id).length != 1) continue;
    final root = await _availableRemoteFsRoot(grant);
    if (root != null) roots.add(root);
  }
  _requireTrustedPeer(ref, peer);
  await ref.read(httpServerProvider).respondRemoteFsRoots(requestId: requestId, roots: roots);
}

Future<void> _respondRemoteFsList(Ref ref, String requestId, RsRemoteFsPeer peer, RemoteFsListRequest request) async {
  final grant = _authorizeGrant(ref, peer, request.location.rootId, RemoteFsCapability.browse);
  _validateRelativePath(request.location.path);
  final entries = switch (grant.kind) {
    RemoteFsGrantKind.localPath => await _listLocalDirectory(grant, request.location.path),
    RemoteFsGrantKind.androidSaf => await _listSafDirectory(grant, request.location.path),
  };
  entries.sort(_compareRemoteFsEntries);

  final offset = _decodeListCursor(request.cursor);
  if (offset > entries.length) throw const _RemoteFsFailure(RemoteFsErrorCode.invalidRequest);
  final end = (offset + request.limit).clamp(0, entries.length);
  final response = RemoteFsListResponse(
    entries: entries.sublist(offset, end),
    nextCursor: end < entries.length ? 'v1:$end' : null,
  );
  _ensureGrantCurrent(ref, peer, grant, RemoteFsCapability.browse);
  await ref.read(httpServerProvider).respondRemoteFsList(requestId: requestId, response: response);
}

Future<void> _respondRemoteFsMetadata(Ref ref, String requestId, RsRemoteFsPeer peer, RemoteFsLocation target) async {
  final grant = _authorizeGrant(ref, peer, target.rootId, RemoteFsCapability.browse);
  _requireEntryPath(target.path);
  final entry = switch (grant.kind) {
    RemoteFsGrantKind.localPath => await _localEntryForPath(grant, target.path),
    RemoteFsGrantKind.androidSaf => await _safEntryForPath(grant, target.path),
  };
  _ensureGrantCurrent(ref, peer, grant, RemoteFsCapability.browse);
  await ref.read(httpServerProvider).respondRemoteFsEntry(requestId: requestId, entry: entry);
}

Future<void> _respondRemoteFsCreateDirectory(Ref ref, String requestId, RsRemoteFsPeer peer, RemoteFsCreateDirectoryRequest request) async {
  final grant = _authorizeGrant(ref, peer, request.parent.rootId, RemoteFsCapability.createDirectory);
  _validateRelativePath(request.parent.path);
  _validateFileName(request.name);
  final childPath = _childRemotePath(request.parent.path, request.name);
  final entry = switch (grant.kind) {
    RemoteFsGrantKind.localPath => await _createLocalDirectory(ref, peer, grant, request.parent.path, request.name, childPath),
    RemoteFsGrantKind.androidSaf => await _createSafDirectory(ref, peer, grant, request.parent.path, request.name, childPath),
  };
  await ref.read(httpServerProvider).respondRemoteFsEntry(requestId: requestId, entry: entry);
}

Future<void> _respondRemoteFsRename(Ref ref, String requestId, RsRemoteFsPeer peer, RemoteFsRenameRequest request) async {
  final grant = _authorizeGrant(ref, peer, request.source.rootId, RemoteFsCapability.rename);
  _requireEntryPath(request.source.path);
  _validateFileName(request.newName);
  final parentPath = _parentRemotePath(request.source.path);
  final renamedPath = _childRemotePath(parentPath, request.newName);
  final entry = switch (grant.kind) {
    RemoteFsGrantKind.localPath => await _renameLocalEntry(ref, peer, grant, request.source.path, request.newName, renamedPath),
    RemoteFsGrantKind.androidSaf => await _renameSafEntry(ref, peer, grant, request.source.path, request.newName, renamedPath),
  };
  await ref.read(httpServerProvider).respondRemoteFsEntry(requestId: requestId, entry: entry);
}

Future<void> _respondRemoteFsMove(Ref ref, String requestId, RsRemoteFsPeer peer, RemoteFsMoveRequest request) async {
  final sourceGrant = _authorizeGrant(ref, peer, request.source.rootId, RemoteFsCapability.move);
  final destinationGrant = _authorizeGrant(ref, peer, request.destinationParent.rootId, RemoteFsCapability.write);
  _requireEntryPath(request.source.path);
  _validateRelativePath(request.destinationParent.path);
  final newName = request.newName ?? _basenameRemotePath(request.source.path);
  _validateFileName(newName);
  if (newName != _basenameRemotePath(request.source.path)) {
    final renameGrant = _authorizeGrant(ref, peer, request.source.rootId, RemoteFsCapability.rename);
    if (renameGrant.kind != sourceGrant.kind || renameGrant.locator != sourceGrant.locator) {
      throw const _RemoteFsFailure(RemoteFsErrorCode.permissionDenied);
    }
  }
  final destinationPath = _childRemotePath(request.destinationParent.path, newName);
  if (sourceGrant.kind != destinationGrant.kind) throw const _RemoteFsFailure(RemoteFsErrorCode.unsupported);

  final entry = switch (sourceGrant.kind) {
    RemoteFsGrantKind.localPath => await _moveLocalEntry(
      ref,
      peer,
      sourceGrant,
      destinationGrant,
      request.source.path,
      request.destinationParent.path,
      newName,
      destinationPath,
      request.overwrite,
    ),
    RemoteFsGrantKind.androidSaf => await _moveSafEntry(
      ref,
      peer,
      sourceGrant,
      destinationGrant,
      request.source.path,
      request.destinationParent.path,
      newName,
      destinationPath,
      request.overwrite,
    ),
  };
  await ref.read(httpServerProvider).respondRemoteFsEntry(requestId: requestId, entry: entry);
}

Future<void> _respondRemoteFsDelete(Ref ref, String requestId, RsRemoteFsPeer peer, RemoteFsDeleteRequest request) async {
  final grant = _authorizeGrant(ref, peer, request.target.rootId, RemoteFsCapability.delete);
  _requireEntryPath(request.target.path);
  switch (grant.kind) {
    case RemoteFsGrantKind.localPath:
      await _deleteLocalEntry(ref, peer, grant, request.target.path, request.recursive);
    case RemoteFsGrantKind.androidSaf:
      await _deleteSafEntry(ref, peer, grant, request.target.path, request.recursive);
  }
  await ref.read(httpServerProvider).respondRemoteFsDelete(requestId: requestId);
}

Future<void> _respondRemoteFsRead(Ref ref, String requestId, RsRemoteFsPeer peer, RemoteFsLocation target) async {
  final grant = _authorizeGrant(ref, peer, target.rootId, RemoteFsCapability.read);
  _requireEntryPath(target.path);
  switch (grant.kind) {
    case RemoteFsGrantKind.localPath:
      final resolved = await _resolveExistingLocal(grant, target.path);
      if (resolved.type == FileSystemEntityType.directory) throw const _RemoteFsFailure(RemoteFsErrorCode.isDirectory);
      if (resolved.type != FileSystemEntityType.file) throw const _RemoteFsFailure(RemoteFsErrorCode.notFound);
      final entry = await _localEntry(resolved.path, target.path, resolved.type, grant);
      _ensureGrantCurrent(ref, peer, grant, RemoteFsCapability.read);
      await ref.read(httpServerProvider).respondRemoteFsRead(requestId: requestId, entry: entry, path: resolved.path);
    case RemoteFsGrantKind.androidSaf:
      final document = await _resolveSafDocument(grant, target.path);
      if (document.isDirectory) throw const _RemoteFsFailure(RemoteFsErrorCode.isDirectory);
      _ensureGrantCurrent(ref, peer, grant, RemoteFsCapability.read);
      final descriptor = await android_channel.openSafDocumentForReadingAndroid(uri: document.uri);
      final entry = _safEntry(document, target.path, grant);
      await ref.read(httpServerProvider).respondRemoteFsRead(requestId: requestId, entry: entry, fileDescriptor: descriptor);
  }
}

Future<void> _respondRemoteFsWrite(Ref ref, String requestId, RsRemoteFsPeer peer, RemoteFsWriteRequest request) async {
  final grant = _authorizeGrant(ref, peer, request.target.rootId, RemoteFsCapability.write);
  _requireEntryPath(request.target.path);
  switch (grant.kind) {
    case RemoteFsGrantKind.localPath:
      final target = await _prepareLocalWriteTarget(grant, request.target.path, request.overwrite);
      _ensureGrantCurrent(ref, peer, grant, RemoteFsCapability.write);
      await for (final event in ref.read(httpServerProvider).respondRemoteFsWrite(requestId: requestId, path: target)) {
        if (event case RsRemoteFsWriteTargetEvent_Failed()) {
          _logger.warning('Remote filesystem write $requestId did not complete');
        }
      }
    case RemoteFsGrantKind.androidSaf:
      final descriptor = await _prepareSafWriteTarget(ref, peer, grant, request.target.path, request.overwrite);
      await for (final event in ref.read(httpServerProvider).respondRemoteFsWrite(requestId: requestId, fileDescriptor: descriptor)) {
        if (event case RsRemoteFsWriteTargetEvent_Failed()) {
          _logger.warning('Remote filesystem write $requestId did not complete');
        }
      }
  }
}

void _requireTrustedPeer(Ref ref, RsRemoteFsPeer peer) {
  final fingerprint = _normalizeFingerprint(peer.certificateFingerprint);
  if (fingerprint.isEmpty) throw const _RemoteFsFailure(RemoteFsErrorCode.unauthenticated);
  if (!ref.read(_remoteFsAccessProvider).value.trustedFingerprints.contains(fingerprint)) {
    throw const _RemoteFsFailure(RemoteFsErrorCode.untrustedDevice);
  }
}

RemoteFsGrant _authorizeGrant(Ref ref, RsRemoteFsPeer peer, String rootId, RemoteFsCapability capability) {
  _requireTrustedPeer(ref, peer);
  final matching = ref.read(_remoteFsAccessProvider).value.grants.where((grant) => grant.id == rootId).toList(growable: false);
  if (matching.length != 1 || !_validPublicRoot(matching.single)) {
    throw const _RemoteFsFailure(RemoteFsErrorCode.rootNotFound);
  }
  final grant = matching.single;
  if (grant.readOnly && _isWriteCapability(capability)) {
    throw const _RemoteFsFailure(RemoteFsErrorCode.readOnly);
  }
  return grant;
}

void _ensureGrantCurrent(Ref ref, RsRemoteFsPeer peer, RemoteFsGrant expected, RemoteFsCapability capability) {
  final current = _authorizeGrant(ref, peer, expected.id, capability);
  if (current.kind != expected.kind || current.locator != expected.locator || current.readOnly != expected.readOnly) {
    throw const _RemoteFsFailure(RemoteFsErrorCode.permissionDenied);
  }
}

String _normalizeFingerprint(String value) => value.trim().toUpperCase();

bool _isWriteCapability(RemoteFsCapability capability) => switch (capability) {
  RemoteFsCapability.write ||
  RemoteFsCapability.createDirectory ||
  RemoteFsCapability.rename ||
  RemoteFsCapability.move ||
  RemoteFsCapability.delete => true,
  RemoteFsCapability.browse || RemoteFsCapability.read => false,
};

bool _validPublicRoot(RemoteFsGrant grant) {
  return RegExp(r'^[A-Za-z0-9._~-]{1,128}$').hasMatch(grant.id) &&
      grant.displayName.isNotEmpty &&
      utf8.encode(grant.displayName).length <= 256 &&
      !_hasControlCharacter(grant.displayName) &&
      grant.locator.isNotEmpty;
}

List<RemoteFsCapability> _rootCapabilities(RemoteFsGrant grant, {bool writable = true}) {
  if (grant.readOnly || !writable) return const [RemoteFsCapability.browse, RemoteFsCapability.read];
  return const [
    RemoteFsCapability.browse,
    RemoteFsCapability.read,
    RemoteFsCapability.write,
    RemoteFsCapability.createDirectory,
    RemoteFsCapability.rename,
    RemoteFsCapability.move,
    RemoteFsCapability.delete,
  ];
}

Future<RemoteFsRoot?> _availableRemoteFsRoot(RemoteFsGrant grant) async {
  try {
    switch (grant.kind) {
      case RemoteFsGrantKind.localPath:
        await _resolveLocalRoot(grant);
        return RemoteFsRoot(id: grant.id, displayName: grant.displayName, capabilities: _rootCapabilities(grant));
      case RemoteFsGrantKind.androidSaf:
        final roots = await android_channel.listSharedRootsAndroid();
        final root = roots.where((root) => root.uri == grant.locator).firstOrNull;
        if (root == null || !root.canRead) return null;
        final metadata = await android_channel.getSafMetadataAndroid(uri: grant.locator);
        return RemoteFsRoot(
          id: grant.id,
          displayName: grant.displayName,
          capabilities: _safRootCapabilities(grant, root, metadata),
        );
    }
  } catch (_) {
    return null;
  }
}

List<RemoteFsCapability> _safRootCapabilities(
  RemoteFsGrant grant,
  android_channel.SafRootAndroid root,
  android_channel.SafDocumentAndroid metadata,
) {
  final result = <RemoteFsCapability>[RemoteFsCapability.browse];
  if (root.canRead) result.add(RemoteFsCapability.read);
  if (grant.readOnly || !root.canWrite) return result;
  result.add(RemoteFsCapability.write);
  if (metadata.canCreate) result.add(RemoteFsCapability.createDirectory);
  if (metadata.canRename) result.add(RemoteFsCapability.rename);
  if (metadata.canMove) result.add(RemoteFsCapability.move);
  if (metadata.canDelete) result.add(RemoteFsCapability.delete);
  return result;
}

List<RemoteFsCapability> _localEntryCapabilities(RemoteFsGrant grant, FileSystemEntityType type) {
  final result = <RemoteFsCapability>[];
  if (type == FileSystemEntityType.directory) {
    result.add(RemoteFsCapability.browse);
  } else if (type == FileSystemEntityType.file) {
    result.add(RemoteFsCapability.read);
  }
  if (!grant.readOnly) {
    if (type == FileSystemEntityType.directory) result.add(RemoteFsCapability.createDirectory);
    if (type == FileSystemEntityType.file) result.add(RemoteFsCapability.write);
    result.addAll(const [RemoteFsCapability.rename, RemoteFsCapability.move, RemoteFsCapability.delete]);
  }
  return result;
}

List<RemoteFsCapability> _safEntryCapabilities(android_channel.SafDocumentAndroid document, RemoteFsGrant grant) {
  final result = <RemoteFsCapability>[];
  if (document.isDirectory) {
    result.add(RemoteFsCapability.browse);
  } else if (document.canRead) {
    result.add(RemoteFsCapability.read);
  }
  if (!grant.readOnly) {
    if (document.canWrite) result.add(RemoteFsCapability.write);
    if (document.canCreate) result.add(RemoteFsCapability.createDirectory);
    if (document.canRename) result.add(RemoteFsCapability.rename);
    if (document.canMove) result.add(RemoteFsCapability.move);
    if (document.canDelete) result.add(RemoteFsCapability.delete);
  }
  return result;
}

Future<String> _resolveLocalRoot(RemoteFsGrant grant) async {
  final root = Directory(p.normalize(p.absolute(grant.locator)));
  final type = await FileSystemEntity.type(root.path, followLinks: false);
  if (type == FileSystemEntityType.link) throw const _RemoteFsFailure(RemoteFsErrorCode.permissionDenied);
  if (type != FileSystemEntityType.directory) throw const _RemoteFsFailure(RemoteFsErrorCode.rootNotFound);
  try {
    return p.normalize(await root.resolveSymbolicLinks());
  } on FileSystemException {
    throw const _RemoteFsFailure(RemoteFsErrorCode.rootNotFound);
  }
}

String _lexicalLocalPath(RemoteFsGrant grant, String relativePath) {
  _validateRelativePath(relativePath);
  final root = p.normalize(p.absolute(grant.locator));
  final candidate = relativePath.isEmpty ? root : p.normalize(p.joinAll([root, ...relativePath.split('/')]));
  if (!_sameLocalPath(root, candidate) && !_isWithinLocalPath(root, candidate)) {
    throw const _RemoteFsFailure(RemoteFsErrorCode.invalidPath);
  }
  return candidate;
}

Future<_ResolvedLocalPath> _resolveExistingLocal(RemoteFsGrant grant, String relativePath) async {
  final root = await _resolveLocalRoot(grant);
  final candidate = _lexicalLocalPath(grant, relativePath);
  final type = await FileSystemEntity.type(candidate, followLinks: false);
  if (type == FileSystemEntityType.link) throw const _RemoteFsFailure(RemoteFsErrorCode.permissionDenied);
  if (type == FileSystemEntityType.notFound) throw const _RemoteFsFailure(RemoteFsErrorCode.notFound);
  if (type != FileSystemEntityType.file && type != FileSystemEntityType.directory) {
    throw const _RemoteFsFailure(RemoteFsErrorCode.unsupported);
  }
  try {
    final resolved = type == FileSystemEntityType.directory
        ? p.normalize(await Directory(candidate).resolveSymbolicLinks())
        : p.normalize(await File(candidate).resolveSymbolicLinks());
    if (!_sameLocalPath(root, resolved) && !_isWithinLocalPath(root, resolved)) {
      throw const _RemoteFsFailure(RemoteFsErrorCode.permissionDenied);
    }
    return _ResolvedLocalPath(path: candidate, type: type);
  } on _RemoteFsFailure {
    rethrow;
  } on FileSystemException {
    throw const _RemoteFsFailure(RemoteFsErrorCode.notFound);
  }
}

Future<String> _resolveNewLocalChild(RemoteFsGrant grant, String parentPath, String name) async {
  _validateFileName(name);
  final parent = await _resolveExistingLocal(grant, parentPath);
  if (parent.type != FileSystemEntityType.directory) throw const _RemoteFsFailure(RemoteFsErrorCode.notDirectory);
  final candidate = p.normalize(p.join(parent.path, name));
  final root = await _resolveLocalRoot(grant);
  if (!_sameLocalPath(root, candidate) && !_isWithinLocalPath(root, candidate)) {
    throw const _RemoteFsFailure(RemoteFsErrorCode.invalidPath);
  }
  final type = await FileSystemEntity.type(candidate, followLinks: false);
  if (type == FileSystemEntityType.link) throw const _RemoteFsFailure(RemoteFsErrorCode.permissionDenied);
  return candidate;
}

Future<List<RemoteFsEntry>> _listLocalDirectory(RemoteFsGrant grant, String relativePath) async {
  final resolved = await _resolveExistingLocal(grant, relativePath);
  if (resolved.type != FileSystemEntityType.directory) throw const _RemoteFsFailure(RemoteFsErrorCode.notDirectory);
  final entries = <RemoteFsEntry>[];
  try {
    await for (final entity in Directory(resolved.path).list(followLinks: false)) {
      final type = await FileSystemEntity.type(entity.path, followLinks: false);
      if (type != FileSystemEntityType.file && type != FileSystemEntityType.directory) continue;
      final name = p.basename(entity.path);
      if (!_validFileName(name)) continue;
      final childPath = _childRemotePath(relativePath, name);
      if (!_validRelativePath(childPath)) continue;
      try {
        final confined = await _resolveExistingLocal(grant, childPath);
        entries.add(await _localEntry(confined.path, childPath, confined.type, grant));
      } on _RemoteFsFailure catch (error) {
        if (error.code != RemoteFsErrorCode.permissionDenied && error.code != RemoteFsErrorCode.notFound) rethrow;
        // Links, junctions escaping the root, and entries that disappear while
        // listing are not remotely visible; they do not poison the directory.
      }
    }
    return entries;
  } on _RemoteFsFailure {
    rethrow;
  } on FileSystemException catch (error) {
    throw _mapFileSystemException(error);
  }
}

Future<RemoteFsEntry> _localEntryForPath(RemoteFsGrant grant, String relativePath) async {
  final resolved = await _resolveExistingLocal(grant, relativePath);
  return _localEntry(resolved.path, relativePath, resolved.type, grant);
}

Future<RemoteFsEntry> _localEntry(String localPath, String relativePath, FileSystemEntityType type, RemoteFsGrant grant) async {
  final stat = await FileStat.stat(localPath);
  if (stat.type == FileSystemEntityType.notFound) throw const _RemoteFsFailure(RemoteFsErrorCode.notFound);
  if (stat.type != type) throw const _RemoteFsFailure(RemoteFsErrorCode.conflict);
  final isFile = type == FileSystemEntityType.file;
  return RemoteFsEntry(
    name: _basenameRemotePath(relativePath),
    path: relativePath,
    entryType: isFile ? RemoteFsEntryType.file : RemoteFsEntryType.directory,
    size: isFile ? BigInt.from(stat.size) : null,
    modified: stat.modified.toUtc().toIso8601String(),
    mimeType: isFile ? _safeMimeType(lookupMimeType(localPath)) : null,
    capabilities: _localEntryCapabilities(grant, type),
  );
}

Future<RemoteFsEntry> _createLocalDirectory(
  Ref ref,
  RsRemoteFsPeer peer,
  RemoteFsGrant grant,
  String parentPath,
  String name,
  String childPath,
) async {
  final target = await _resolveNewLocalChild(grant, parentPath, name);
  if (await FileSystemEntity.type(target, followLinks: false) != FileSystemEntityType.notFound) {
    throw const _RemoteFsFailure(RemoteFsErrorCode.alreadyExists);
  }
  _ensureGrantCurrent(ref, peer, grant, RemoteFsCapability.createDirectory);
  try {
    await Directory(target).create();
  } on FileSystemException catch (error) {
    throw _mapFileSystemException(error);
  }
  final resolved = await _resolveExistingLocal(grant, childPath);
  return _localEntry(resolved.path, childPath, resolved.type, grant);
}

Future<RemoteFsEntry> _renameLocalEntry(
  Ref ref,
  RsRemoteFsPeer peer,
  RemoteFsGrant grant,
  String sourcePath,
  String newName,
  String renamedPath,
) async {
  final source = await _resolveExistingLocal(grant, sourcePath);
  final destination = await _resolveNewLocalChild(grant, _parentRemotePath(sourcePath), newName);
  if (await FileSystemEntity.type(destination, followLinks: false) != FileSystemEntityType.notFound) {
    throw const _RemoteFsFailure(RemoteFsErrorCode.alreadyExists);
  }
  _ensureGrantCurrent(ref, peer, grant, RemoteFsCapability.rename);
  try {
    if (source.type == FileSystemEntityType.directory) {
      await Directory(source.path).rename(destination);
    } else {
      await File(source.path).rename(destination);
    }
  } on FileSystemException catch (error) {
    throw _mapFileSystemException(error);
  }
  final resolved = await _resolveExistingLocal(grant, renamedPath);
  return _localEntry(resolved.path, renamedPath, resolved.type, grant);
}

Future<RemoteFsEntry> _moveLocalEntry(
  Ref ref,
  RsRemoteFsPeer peer,
  RemoteFsGrant sourceGrant,
  RemoteFsGrant destinationGrant,
  String sourcePath,
  String destinationParentPath,
  String newName,
  String destinationPath,
  bool overwrite,
) async {
  final source = await _resolveExistingLocal(sourceGrant, sourcePath);
  final destination = await _resolveNewLocalChild(destinationGrant, destinationParentPath, newName);
  if (source.type == FileSystemEntityType.directory && _isWithinLocalPath(source.path, destination)) {
    throw const _RemoteFsFailure(RemoteFsErrorCode.conflict);
  }
  final destinationType = await FileSystemEntity.type(destination, followLinks: false);
  if (destinationType != FileSystemEntityType.notFound) {
    if (!overwrite) throw const _RemoteFsFailure(RemoteFsErrorCode.alreadyExists);
    // Replacing the destination before rename would lose it when rename later
    // fails. Atomic replace semantics vary by platform, so F2 rejects it.
    throw const _RemoteFsFailure(RemoteFsErrorCode.unsupported);
  }
  _ensureGrantCurrent(ref, peer, sourceGrant, RemoteFsCapability.move);
  _ensureGrantCurrent(ref, peer, destinationGrant, RemoteFsCapability.write);
  try {
    if (source.type == FileSystemEntityType.directory) {
      await Directory(source.path).rename(destination);
    } else {
      await File(source.path).rename(destination);
    }
  } on FileSystemException catch (error) {
    throw _mapFileSystemException(error);
  }
  final resolved = await _resolveExistingLocal(destinationGrant, destinationPath);
  return _localEntry(resolved.path, destinationPath, resolved.type, destinationGrant);
}

Future<void> _deleteLocalEntry(Ref ref, RsRemoteFsPeer peer, RemoteFsGrant grant, String path, bool recursive) async {
  final source = await _resolveExistingLocal(grant, path);
  if (source.type == FileSystemEntityType.directory && !recursive && !await Directory(source.path).list(followLinks: false).isEmpty) {
    throw const _RemoteFsFailure(RemoteFsErrorCode.directoryNotEmpty);
  }
  _ensureGrantCurrent(ref, peer, grant, RemoteFsCapability.delete);
  try {
    if (source.type == FileSystemEntityType.directory) {
      await Directory(source.path).delete(recursive: recursive);
    } else {
      await File(source.path).delete();
    }
  } on FileSystemException catch (error) {
    throw _mapFileSystemException(error);
  }
}

Future<String> _prepareLocalWriteTarget(RemoteFsGrant grant, String relativePath, bool overwrite) async {
  final name = _basenameRemotePath(relativePath);
  _validateFileName(name);
  final parentPath = _parentRemotePath(relativePath);
  final target = await _resolveNewLocalChild(grant, parentPath, name);
  final type = await FileSystemEntity.type(target, followLinks: false);
  if (type == FileSystemEntityType.link) throw const _RemoteFsFailure(RemoteFsErrorCode.permissionDenied);
  if (type == FileSystemEntityType.directory) throw const _RemoteFsFailure(RemoteFsErrorCode.isDirectory);
  if (type != FileSystemEntityType.notFound && type != FileSystemEntityType.file) {
    throw const _RemoteFsFailure(RemoteFsErrorCode.conflict);
  }
  if (type == FileSystemEntityType.file && !overwrite) throw const _RemoteFsFailure(RemoteFsErrorCode.alreadyExists);
  return target;
}

Future<android_channel.SafDocumentAndroid> _resolveSafDocument(RemoteFsGrant grant, String relativePath) async {
  _validateRelativePath(relativePath);
  try {
    return await android_channel.resolveSafRelativePathAndroid(rootUri: grant.locator, relativePath: relativePath);
  } on PlatformException catch (error) {
    throw _mapSafException(error);
  }
}

Future<List<RemoteFsEntry>> _listSafDirectory(RemoteFsGrant grant, String relativePath) async {
  final directory = await _resolveSafDocument(grant, relativePath);
  if (!directory.isDirectory) throw const _RemoteFsFailure(RemoteFsErrorCode.notDirectory);
  try {
    final documents = await android_channel.listSafDirectoryAndroid(directoryUri: directory.uri);
    return documents
        .where((document) => _validFileName(document.name))
        .where((document) => _validRelativePath(_childRemotePath(relativePath, document.name)))
        .map((document) {
          return _safEntry(document, _childRemotePath(relativePath, document.name), grant);
        })
        .toList(growable: false);
  } on PlatformException catch (error) {
    throw _mapSafException(error);
  }
}

Future<RemoteFsEntry> _safEntryForPath(RemoteFsGrant grant, String relativePath) async {
  return _safEntry(await _resolveSafDocument(grant, relativePath), relativePath, grant);
}

RemoteFsEntry _safEntry(android_channel.SafDocumentAndroid document, String relativePath, RemoteFsGrant grant) {
  final type = document.isDirectory ? RemoteFsEntryType.directory : RemoteFsEntryType.file;
  return RemoteFsEntry(
    name: _basenameRemotePath(relativePath),
    path: relativePath,
    entryType: type,
    size: document.isDirectory || document.size == null ? null : BigInt.from(document.size!),
    modified: document.lastModified == null || document.lastModified == 0
        ? null
        : DateTime.fromMillisecondsSinceEpoch(document.lastModified!, isUtc: true).toIso8601String(),
    mimeType: document.isDirectory ? null : _safeMimeType(document.mimeType),
    capabilities: _safEntryCapabilities(document, grant),
  );
}

Future<RemoteFsEntry> _createSafDirectory(
  Ref ref,
  RsRemoteFsPeer peer,
  RemoteFsGrant grant,
  String parentPath,
  String name,
  String childPath,
) async {
  final parent = await _resolveSafDocument(grant, parentPath);
  if (!parent.isDirectory) throw const _RemoteFsFailure(RemoteFsErrorCode.notDirectory);
  if (await _safChildExists(parent.uri, name)) throw const _RemoteFsFailure(RemoteFsErrorCode.alreadyExists);
  _ensureGrantCurrent(ref, peer, grant, RemoteFsCapability.createDirectory);
  try {
    final created = await android_channel.createSafDirectoryAndroid(parentUri: parent.uri, name: name);
    return _safEntry(created, childPath, grant);
  } on PlatformException catch (error) {
    throw _mapSafException(error);
  }
}

Future<RemoteFsEntry> _renameSafEntry(
  Ref ref,
  RsRemoteFsPeer peer,
  RemoteFsGrant grant,
  String sourcePath,
  String newName,
  String renamedPath,
) async {
  final source = await _resolveSafDocument(grant, sourcePath);
  final parent = await _resolveSafDocument(grant, _parentRemotePath(sourcePath));
  if (await _safChildExists(parent.uri, newName)) throw const _RemoteFsFailure(RemoteFsErrorCode.alreadyExists);
  _ensureGrantCurrent(ref, peer, grant, RemoteFsCapability.rename);
  try {
    final renamed = await android_channel.renameSafDocumentAndroid(uri: source.uri, newName: newName);
    return _safEntry(renamed, renamedPath, grant);
  } on PlatformException catch (error) {
    throw _mapSafException(error);
  }
}

Future<RemoteFsEntry> _moveSafEntry(
  Ref ref,
  RsRemoteFsPeer peer,
  RemoteFsGrant sourceGrant,
  RemoteFsGrant destinationGrant,
  String sourcePath,
  String destinationParentPath,
  String newName,
  String destinationPath,
  bool overwrite,
) async {
  // Android tree capabilities are deliberately not merged across separate
  // grants: native move requires both documents under the same persisted tree.
  if (sourceGrant.id != destinationGrant.id || sourceGrant.locator != destinationGrant.locator) {
    throw const _RemoteFsFailure(RemoteFsErrorCode.unsupported);
  }
  final source = await _resolveSafDocument(sourceGrant, sourcePath);
  final sourceParent = await _resolveSafDocument(sourceGrant, _parentRemotePath(sourcePath));
  final destinationParent = await _resolveSafDocument(destinationGrant, destinationParentPath);
  final existing = await _findSafChild(destinationParent.uri, newName);
  if (existing != null && existing.uri != source.uri) {
    if (!overwrite) throw const _RemoteFsFailure(RemoteFsErrorCode.alreadyExists);
    throw const _RemoteFsFailure(RemoteFsErrorCode.unsupported);
  }
  if (source.name != newName) {
    final originalNameCollision = await _findSafChild(destinationParent.uri, source.name);
    if (originalNameCollision != null && originalNameCollision.uri != source.uri) {
      throw const _RemoteFsFailure(RemoteFsErrorCode.conflict);
    }
  }
  _ensureGrantCurrent(ref, peer, sourceGrant, RemoteFsCapability.move);
  try {
    var moved = await android_channel.moveSafDocumentAndroid(
      uri: source.uri,
      sourceParentUri: sourceParent.uri,
      targetParentUri: destinationParent.uri,
    );
    if (moved.name != newName) {
      try {
        moved = await android_channel.renameSafDocumentAndroid(uri: moved.uri, newName: newName);
      } catch (renameError) {
        if (sourceParent.uri != destinationParent.uri) {
          try {
            await android_channel.moveSafDocumentAndroid(
              uri: moved.uri,
              sourceParentUri: destinationParent.uri,
              targetParentUri: sourceParent.uri,
            );
          } catch (_) {
            // The operation still fails. No provider exception or locator is
            // returned remotely; the local UI can reconcile a partial move.
          }
        }
        rethrow;
      }
    }
    return _safEntry(moved, destinationPath, destinationGrant);
  } on PlatformException catch (error) {
    throw _mapSafException(error);
  }
}

Future<void> _deleteSafEntry(Ref ref, RsRemoteFsPeer peer, RemoteFsGrant grant, String path, bool recursive) async {
  final target = await _resolveSafDocument(grant, path);
  if (target.isDirectory && !recursive) {
    try {
      if ((await android_channel.listSafDirectoryAndroid(directoryUri: target.uri)).isNotEmpty) {
        throw const _RemoteFsFailure(RemoteFsErrorCode.directoryNotEmpty);
      }
    } on PlatformException catch (error) {
      throw _mapSafException(error);
    }
  }
  _ensureGrantCurrent(ref, peer, grant, RemoteFsCapability.delete);
  try {
    await android_channel.deleteSafDocumentAndroid(uri: target.uri);
  } on PlatformException catch (error) {
    throw _mapSafException(error);
  }
}

Future<int> _prepareSafWriteTarget(Ref ref, RsRemoteFsPeer peer, RemoteFsGrant grant, String relativePath, bool overwrite) async {
  final name = _basenameRemotePath(relativePath);
  _validateFileName(name);
  final parent = await _resolveSafDocument(grant, _parentRemotePath(relativePath));
  if (!parent.isDirectory) throw const _RemoteFsFailure(RemoteFsErrorCode.notDirectory);
  final existing = await _findSafChild(parent.uri, name);
  _ensureGrantCurrent(ref, peer, grant, RemoteFsCapability.write);
  try {
    if (existing != null) {
      if (existing.isDirectory) throw const _RemoteFsFailure(RemoteFsErrorCode.isDirectory);
      if (!overwrite) throw const _RemoteFsFailure(RemoteFsErrorCode.alreadyExists);
      return android_channel.openSafDocumentForWritingAndroid(uri: existing.uri, truncate: true);
    }
    final created = await android_channel.createSafFileAndroid(
      parentUri: parent.uri,
      name: name,
      mimeType: lookupMimeType(name) ?? 'application/octet-stream',
    );
    return created.fileDescriptor;
  } on _RemoteFsFailure {
    rethrow;
  } on PlatformException catch (error) {
    throw _mapSafException(error);
  }
}

Future<bool> _safChildExists(String parentUri, String name) async => await _findSafChild(parentUri, name) != null;

Future<android_channel.SafDocumentAndroid?> _findSafChild(String parentUri, String name) async {
  try {
    final matches = (await android_channel.listSafDirectoryAndroid(directoryUri: parentUri)).where((entry) => entry.name == name).toList();
    if (matches.length > 1) throw const _RemoteFsFailure(RemoteFsErrorCode.conflict);
    return matches.firstOrNull;
  } on PlatformException catch (error) {
    throw _mapSafException(error);
  }
}

int _compareRemoteFsEntries(RemoteFsEntry first, RemoteFsEntry second) {
  final type = first.entryType == second.entryType
      ? 0
      : first.entryType == RemoteFsEntryType.directory
      ? -1
      : second.entryType == RemoteFsEntryType.directory
      ? 1
      : 0;
  if (type != 0) return type;
  final folded = first.name.toLowerCase().compareTo(second.name.toLowerCase());
  return folded != 0 ? folded : first.name.compareTo(second.name);
}

int _decodeListCursor(String? cursor) {
  if (cursor == null) return 0;
  final match = RegExp(r'^v1:([0-9]{1,10})$').firstMatch(cursor);
  final offset = match == null ? null : int.tryParse(match.group(1)!);
  if (offset == null || offset < 0) throw const _RemoteFsFailure(RemoteFsErrorCode.invalidRequest);
  return offset;
}

bool _validRelativePath(String path) {
  if (path.isEmpty) return true;
  if (utf8.encode(path).length > 4096 ||
      path.startsWith('/') ||
      path.endsWith('/') ||
      path.contains('\\') ||
      _hasControlCharacter(path) ||
      _isWindowsStyleAbsolute(path)) {
    return false;
  }
  if (path.split('/').any((component) => component.isEmpty || component == '.' || component == '..')) return false;
  return true;
}

void _validateRelativePath(String path) {
  if (!_validRelativePath(path)) throw const _RemoteFsFailure(RemoteFsErrorCode.invalidPath);
}

void _requireEntryPath(String path) {
  _validateRelativePath(path);
  if (path.isEmpty) throw const _RemoteFsFailure(RemoteFsErrorCode.invalidPath);
}

bool _validFileName(String name) {
  return name.isNotEmpty &&
      name != '.' &&
      name != '..' &&
      utf8.encode(name).length <= 1024 &&
      !name.contains('/') &&
      !name.contains('\\') &&
      !_hasControlCharacter(name);
}

void _validateFileName(String name) {
  if (!_validFileName(name)) throw const _RemoteFsFailure(RemoteFsErrorCode.invalidName);
}

String _childRemotePath(String parent, String name) => parent.isEmpty ? name : '$parent/$name';
String _parentRemotePath(String path) => path.contains('/') ? path.substring(0, path.lastIndexOf('/')) : '';
String _basenameRemotePath(String path) => path.contains('/') ? path.substring(path.lastIndexOf('/') + 1) : path;

bool _hasControlCharacter(String value) => value.runes.any((rune) => rune <= 0x1f || (rune >= 0x7f && rune <= 0x9f));

bool _isWindowsStyleAbsolute(String path) => RegExp(r'^[A-Za-z]:').hasMatch(path);

String? _safeMimeType(String? value) {
  if (value == null || utf8.encode(value).length > 255 || _hasControlCharacter(value)) return null;
  return value;
}

bool _sameLocalPath(String first, String second) {
  if (Platform.isWindows) return p.equals(first.toLowerCase(), second.toLowerCase());
  return p.equals(first, second);
}

bool _isWithinLocalPath(String parent, String child) {
  if (Platform.isWindows) return p.isWithin(parent.toLowerCase(), child.toLowerCase());
  return p.isWithin(parent, child);
}

RemoteFsErrorCode _remoteFsErrorCode(Object error) {
  if (error is _RemoteFsFailure) return error.code;
  if (error is PlatformException) return _mapSafException(error).code;
  if (error is FileSystemException) return _mapFileSystemException(error).code;
  return RemoteFsErrorCode.internal;
}

_RemoteFsFailure _mapSafException(PlatformException error) {
  final code = switch (error.code) {
    'INVALID_ARGUMENT' || 'INVALID_PATH' || 'INVALID_ROOT' => RemoteFsErrorCode.invalidPath,
    'INVALID_NAME' => RemoteFsErrorCode.invalidName,
    'UNREGISTERED_URI' || 'PERMISSION_REVOKED' => RemoteFsErrorCode.rootNotFound,
    'PERMISSION_DENIED' || 'OUTSIDE_SHARED_ROOT' || 'ROOT_MUTATION_FORBIDDEN' => RemoteFsErrorCode.permissionDenied,
    'READ_ONLY_ROOT' => RemoteFsErrorCode.readOnly,
    'NOT_FOUND' => RemoteFsErrorCode.notFound,
    'NOT_A_DIRECTORY' => RemoteFsErrorCode.notDirectory,
    'IS_A_DIRECTORY' => RemoteFsErrorCode.isDirectory,
    'UNSUPPORTED_OPERATION' || 'UNSUPPORTED_ANDROID_VERSION' || 'CROSS_PROVIDER_MOVE_UNSUPPORTED' => RemoteFsErrorCode.unsupported,
    'INVALID_MOVE' || 'INVALID_SOURCE_PARENT' || 'AMBIGUOUS_PATH' => RemoteFsErrorCode.conflict,
    'CREATE_FAILED' || 'RENAME_FAILED' || 'MOVE_FAILED' || 'DELETE_FAILED' || 'OPEN_FAILED' => RemoteFsErrorCode.transferFailed,
    'QUERY_FAILED' || 'ANCESTRY_CHECK_FAILED' => RemoteFsErrorCode.unavailable,
    _ => RemoteFsErrorCode.internal,
  };
  return _RemoteFsFailure(code);
}

_RemoteFsFailure _mapFileSystemException(FileSystemException error) {
  final osCode = error.osError?.errorCode;
  final code = switch (osCode) {
    2 || 3 => RemoteFsErrorCode.notFound,
    5 || 13 => RemoteFsErrorCode.permissionDenied,
    17 || 80 || 183 => RemoteFsErrorCode.alreadyExists,
    28 || 112 => RemoteFsErrorCode.storageFull,
    39 || 145 => RemoteFsErrorCode.directoryNotEmpty,
    16 || 32 || 33 => RemoteFsErrorCode.busy,
    _ => RemoteFsErrorCode.unavailable,
  };
  return _RemoteFsFailure(code);
}

class _ResolvedLocalPath {
  final String path;
  final FileSystemEntityType type;

  const _ResolvedLocalPath({required this.path, required this.type});
}

class _RemoteFsFailure implements Exception {
  final RemoteFsErrorCode code;

  const _RemoteFsFailure(this.code);
}

/// Receives a single file without involving the main isolate:
/// resolves the save target, lets the Rust server write the file and applies
/// the post-processing (timestamps, gallery).
///
/// [emit]s [HttpServerFileUploadProgressEvent]s while the file is being
/// received, followed by a final [HttpServerFileUploadResultEvent].
Future<void> _handleFileUpload({
  required Ref ref,
  required _ReceiveSession session,
  required String sessionId,
  required String fileId,
  required FileDto file,
  required void Function(HttpServerEvent event) emit,
}) async {
  final config = session.config;
  final desiredName = config.fileNameMap[fileId]!;
  final dartFile = file.toDart();
  final isImage = dartFile.fileType == FileType.image;
  final shouldSaveToGallery = config.saveToGallery && (isImage || dartFile.fileType == FileType.video);

  void emitFailed(Object e) {
    emit(
      HttpServerFileUploadResultEvent(
        sessionId: sessionId,
        fileId: fileId,
        path: null,
        savedToGallery: false,
        error: e.humanErrorMessage,
      ),
    );
  }

  _logger.info('Saving ${dartFile.fileName}');

  final FileSaveTarget target;
  try {
    // A previous attempt at this file already picked a destination, which this
    // attempt overwrites instead of creating a numbered version.
    final previous = session.targets[fileId];
    target = previous != null
        ? await reopenFileSaveTarget(previous)
        : await prepareFileSaveTarget(
            destinationDirectory: config.destinationDirectory,
            cacheDirectory: config.cacheDirectory,
            fileName: desiredName,
            saveToGallery: shouldSaveToGallery,
            isImage: isImage,
            createdDirectories: session.createdDirectories,
            androidSdkInt: config.androidSdkInt,
          );
    session.targets[fileId] = target;
  } catch (e, st) {
    _logger.severe('Failed to prepare save target', e, st);

    // The Rust server is still waiting for the target; failing it ends the
    // sender's request which would otherwise hang forever.
    try {
      await ref.read(httpServerProvider).failFileUpload(sessionId: sessionId, fileId: fileId);
    } catch (e) {
      _logger.warning('Could not fail the pending file upload', e);
    }

    emitFailed(e);
    return;
  }

  try {
    // The Rust server writes the file and reports the progress.
    final progressStream = ref
        .read(httpServerProvider)
        .respondFileUpload(
          sessionId: sessionId,
          fileId: fileId,
          path: target.path,
          fileDescriptor: target.fileDescriptor,
          fileSize: dartFile.size,
        );
    await for (final progress in progressStream) {
      emit(
        HttpServerFileUploadProgressEvent(
          sessionId: sessionId,
          fileId: fileId,
          progress: progress,
        ),
      );
    }
  } catch (e, st) {
    // The incomplete file is kept: a retry of this file overwrites it, and
    // otherwise it stays behind as the partial file of a failed transfer.
    _logger.severe('Failed to save file', e, st);
    emitFailed(e);
    return;
  }

  try {
    String? filePath;
    bool savedToGallery = false;
    if (shouldSaveToGallery) {
      (savedToGallery, filePath) = await saveCachedFileToGallery(
        cachedPath: target.displayPath,
        destinationDirectory: config.destinationDirectory,
        fileName: desiredName,
        isImage: isImage,
        createdDirectories: session.createdDirectories,
      );
    } else {
      filePath = target.displayPath;
    }

    _logger.info('Saved ${dartFile.fileName}.');
    emit(
      HttpServerFileUploadResultEvent(
        sessionId: sessionId,
        fileId: fileId,
        path: filePath,
        savedToGallery: savedToGallery,
        error: null,
      ),
    );
  } catch (e, st) {
    _logger.severe('Failed to post-process file', e, st);
    emitFailed(e);
  }
}
