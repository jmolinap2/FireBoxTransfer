//! FireBoxTransfer remote-filesystem HTTP handlers.
//!
//! Core owns transport validation and mTLS identity. The application owns the
//! trust store, root grants and platform filesystem implementation, and must
//! answer every event with either a typed result or a typed public error.

use crate::http::firebox::{
    validate_entry, validate_file_name, validate_root, RemoteFsCreateDirectoryRequest,
    RemoteFsDeleteRequest, RemoteFsEntry, RemoteFsEntryType, RemoteFsErrorCode,
    RemoteFsErrorResponse, RemoteFsListRequest, RemoteFsListResponse, RemoteFsLocation,
    RemoteFsMoveRequest, RemoteFsMutationResponse, RemoteFsRenameRequest, RemoteFsRoot,
    RemoteFsRootsResponse, RemoteFsWriteRequest, RemoteFsWriteResponse, DEFAULT_LIST_LIMIT,
    MAX_LIST_LIMIT,
};
use crate::http::server::common::query::parse_query;
use crate::http::server::common::response::{empty_body, BoxedBody, JsonResponse};
use crate::http::server::common::save::{
    save_req_to_target, FileTimestamps, FileUploadTarget, SaveResult,
};
use crate::http::server::{AppState, PeerIp, RequestClientInfo};
use crate::model::transfer::FileContent;
use bytes::{Bytes, BytesMut};
use futures_util::StreamExt;
use http_body_util::{BodyExt, StreamBody};
use hyper::body::{Frame, Incoming};
use hyper::{http, Method, Request, Response, StatusCode};
use serde::de::DeserializeOwned;
use std::collections::HashSet;
use std::num::NonZeroUsize;
use std::sync::Arc;
use std::time::Duration;
use tokio::sync::{mpsc, oneshot, OwnedSemaphorePermit, Semaphore};
use tokio_stream::wrappers::ReceiverStream;

const MAX_JSON_BODY_SIZE: usize = 64 * 1024;
const EVENT_RESPONSE_TIMEOUT: Duration = Duration::from_secs(30);
const DEFAULT_MAX_WRITE_SIZE: u64 = 1 << 40; // 1 TiB
pub const DEFAULT_MAX_CONCURRENT_REQUESTS: usize = 64;

pub type RemoteFsResult<T> = Result<T, RemoteFsErrorCode>;

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct RemoteFsPeer {
    pub ip: PeerIp,
    /// Uppercase-hex SHA-256 of the verified client certificate DER.
    pub certificate_fingerprint: String,
}

#[derive(Debug)]
pub struct RemoteFsReadSource {
    pub entry: RemoteFsEntry,
    pub content: FileContent,
}

/// Events that bridge authenticated HTTP requests to the application's trust
/// store and platform filesystem provider.
#[derive(Debug)]
pub enum RemoteFsEvent {
    Roots {
        peer: RemoteFsPeer,
        response_tx: oneshot::Sender<RemoteFsResult<Vec<RemoteFsRoot>>>,
    },
    List {
        peer: RemoteFsPeer,
        request: RemoteFsListRequest,
        response_tx: oneshot::Sender<RemoteFsResult<RemoteFsListResponse>>,
    },
    Metadata {
        peer: RemoteFsPeer,
        target: RemoteFsLocation,
        response_tx: oneshot::Sender<RemoteFsResult<RemoteFsEntry>>,
    },
    CreateDirectory {
        peer: RemoteFsPeer,
        request: RemoteFsCreateDirectoryRequest,
        response_tx: oneshot::Sender<RemoteFsResult<RemoteFsEntry>>,
    },
    Rename {
        peer: RemoteFsPeer,
        request: RemoteFsRenameRequest,
        response_tx: oneshot::Sender<RemoteFsResult<RemoteFsEntry>>,
    },
    Move {
        peer: RemoteFsPeer,
        request: RemoteFsMoveRequest,
        response_tx: oneshot::Sender<RemoteFsResult<RemoteFsEntry>>,
    },
    Delete {
        peer: RemoteFsPeer,
        request: RemoteFsDeleteRequest,
        response_tx: oneshot::Sender<RemoteFsResult<()>>,
    },
    Read {
        peer: RemoteFsPeer,
        target: RemoteFsLocation,
        response_tx: oneshot::Sender<RemoteFsResult<RemoteFsReadSource>>,
    },
    Write {
        peer: RemoteFsPeer,
        request: RemoteFsWriteRequest,
        /// The application authorizes the request and supplies a streaming,
        /// path or Android-FD target. Returning an error rejects the body
        /// before core begins reading it.
        target_tx: oneshot::Sender<RemoteFsResult<FileUploadTarget>>,
    },
}

pub struct RemoteFsServerConfig {
    pub event_tx: mpsc::Sender<RemoteFsEvent>,
    /// Maximum accepted `Content-Length` for a single write request.
    pub max_write_size: u64,
    /// Maximum number of requests waiting on the application/provider. New
    /// requests fail with `BUSY` instead of allocating an unbounded queue.
    pub max_concurrent_requests: NonZeroUsize,
}

impl RemoteFsServerConfig {
    pub fn new(event_tx: mpsc::Sender<RemoteFsEvent>) -> Self {
        Self {
            event_tx,
            max_write_size: DEFAULT_MAX_WRITE_SIZE,
            max_concurrent_requests: NonZeroUsize::new(DEFAULT_MAX_CONCURRENT_REQUESTS)
                .expect("default is non-zero"),
        }
    }

    pub fn with_max_write_size(mut self, max_write_size: u64) -> Self {
        self.max_write_size = max_write_size;
        self
    }

    pub fn with_max_concurrent_requests(mut self, max_concurrent_requests: NonZeroUsize) -> Self {
        self.max_concurrent_requests = max_concurrent_requests;
        self
    }
}

pub(crate) struct RemoteFsState {
    event_tx: mpsc::Sender<RemoteFsEvent>,
    max_write_size: u64,
    request_slots: Arc<Semaphore>,
}

impl RemoteFsState {
    pub(crate) fn new(config: RemoteFsServerConfig) -> Self {
        Self {
            event_tx: config.event_tx,
            max_write_size: config.max_write_size,
            request_slots: Arc::new(Semaphore::new(config.max_concurrent_requests.get())),
        }
    }

    fn try_acquire_request(&self) -> RemoteFsResult<OwnedSemaphorePermit> {
        self.request_slots
            .clone()
            .try_acquire_owned()
            .map_err(|_| RemoteFsErrorCode::Busy)
    }
}

pub(crate) async fn handle(
    req: Request<Incoming>,
    state: AppState,
    client_info: RequestClientInfo,
) -> Response<BoxedBody> {
    match handle_inner(req, state, client_info).await {
        Ok(response) => response,
        Err(code) => error_response(code),
    }
}

async fn handle_inner(
    req: Request<Incoming>,
    state: AppState,
    client_info: RequestClientInfo,
) -> RemoteFsResult<Response<BoxedBody>> {
    let remote_fs = state.remote_fs.clone().ok_or(RemoteFsErrorCode::NotFound)?;
    let peer = authenticated_peer(client_info)?;
    // Bound the complete operation, not only the provider decision. For reads,
    // the permit moves into the response body and survives until EOF or client
    // disconnect; writes hold it while the request body is consumed.
    let mut request_permit = Some(remote_fs.try_acquire_request()?);

    match (req.method(), req.uri().path()) {
        (&Method::GET, "/api/fireboxtransfer/v1/roots") => roots(remote_fs, peer).await,
        (&Method::GET, "/api/fireboxtransfer/v1/files") => list(req, remote_fs, peer).await,
        (&Method::GET, "/api/fireboxtransfer/v1/files/metadata") => {
            metadata(req, remote_fs, peer).await
        }
        (&Method::POST, "/api/fireboxtransfer/v1/files/directory") => {
            create_directory(req, remote_fs, peer).await
        }
        (&Method::POST, "/api/fireboxtransfer/v1/files/rename") => {
            rename(req, remote_fs, peer).await
        }
        (&Method::POST, "/api/fireboxtransfer/v1/files/move") => {
            move_entry(req, remote_fs, peer).await
        }
        (&Method::DELETE, "/api/fireboxtransfer/v1/files") => delete(req, remote_fs, peer).await,
        (&Method::GET, "/api/fireboxtransfer/v1/files/content") => {
            read(
                req,
                remote_fs,
                peer,
                request_permit.take().expect("request permit is present"),
            )
            .await
        }
        (&Method::PUT, "/api/fireboxtransfer/v1/files/content") => {
            write(req, remote_fs, peer).await
        }
        _ => Err(RemoteFsErrorCode::NotFound),
    }
}

fn authenticated_peer(client_info: RequestClientInfo) -> RemoteFsResult<RemoteFsPeer> {
    let certificate_fingerprint = client_info
        .cert_fingerprint()
        .ok_or(RemoteFsErrorCode::Unauthenticated)?;
    Ok(RemoteFsPeer {
        ip: client_info.ip,
        certificate_fingerprint,
    })
}

async fn roots(
    state: Arc<RemoteFsState>,
    peer: RemoteFsPeer,
) -> RemoteFsResult<Response<BoxedBody>> {
    let roots = dispatch(&state, |response_tx| RemoteFsEvent::Roots {
        peer,
        response_tx,
    })
    .await?;

    if roots.len() > 256 {
        return Err(RemoteFsErrorCode::Internal);
    }
    let mut ids = HashSet::with_capacity(roots.len());
    for root in &roots {
        validate_root(root)?;
        if !ids.insert(root.id.as_str()) {
            return Err(RemoteFsErrorCode::Internal);
        }
    }

    Ok(json_response(
        StatusCode::OK,
        RemoteFsRootsResponse { roots },
    ))
}

async fn list(
    req: Request<Incoming>,
    state: Arc<RemoteFsState>,
    peer: RemoteFsPeer,
) -> RemoteFsResult<Response<BoxedBody>> {
    let query = parse_query(req.uri().query());
    let location = location_from_query(&query)?;
    let limit = match query.get("limit") {
        Some(value) => value
            .parse::<u16>()
            .ok()
            .filter(|limit| (1..=MAX_LIST_LIMIT).contains(limit))
            .ok_or(RemoteFsErrorCode::InvalidRequest)?,
        None => DEFAULT_LIST_LIMIT,
    };
    let request = RemoteFsListRequest {
        location,
        cursor: query.get("cursor").cloned(),
        limit,
    };
    request.validate()?;

    let response = dispatch(&state, |response_tx| RemoteFsEvent::List {
        peer,
        request: request.clone(),
        response_tx,
    })
    .await?;

    if response.entries.len() > request.limit as usize {
        return Err(RemoteFsErrorCode::Internal);
    }
    let mut paths = HashSet::with_capacity(response.entries.len());
    for entry in &response.entries {
        validate_entry(entry, Some(&request.location.path))?;
        if !paths.insert(entry.path.as_str()) {
            return Err(RemoteFsErrorCode::Internal);
        }
    }
    validate_cursor(response.next_cursor.as_deref())?;

    Ok(json_response(StatusCode::OK, response))
}

async fn metadata(
    req: Request<Incoming>,
    state: Arc<RemoteFsState>,
    peer: RemoteFsPeer,
) -> RemoteFsResult<Response<BoxedBody>> {
    let query = parse_query(req.uri().query());
    let target = location_from_query(&query)?;
    require_entry_path(&target)?;

    let entry = dispatch(&state, |response_tx| RemoteFsEvent::Metadata {
        peer,
        target: target.clone(),
        response_tx,
    })
    .await?;
    validate_exact_entry(&entry, &target.path)?;

    Ok(json_response(StatusCode::OK, entry))
}

async fn create_directory(
    req: Request<Incoming>,
    state: Arc<RemoteFsState>,
    peer: RemoteFsPeer,
) -> RemoteFsResult<Response<BoxedBody>> {
    let request = collect_json::<RemoteFsCreateDirectoryRequest>(req.into_body()).await?;
    request.parent.validate()?;
    validate_file_name(&request.name)?;
    let expected_path = child_path(&request.parent.path, &request.name);

    let entry = dispatch(&state, |response_tx| RemoteFsEvent::CreateDirectory {
        peer,
        request,
        response_tx,
    })
    .await?;
    validate_exact_entry(&entry, &expected_path)?;
    if entry.entry_type != RemoteFsEntryType::Directory {
        return Err(RemoteFsErrorCode::Internal);
    }

    Ok(json_response(
        StatusCode::CREATED,
        RemoteFsMutationResponse { entry },
    ))
}

async fn rename(
    req: Request<Incoming>,
    state: Arc<RemoteFsState>,
    peer: RemoteFsPeer,
) -> RemoteFsResult<Response<BoxedBody>> {
    let request = collect_json::<RemoteFsRenameRequest>(req.into_body()).await?;
    request.source.validate()?;
    require_entry_path(&request.source)?;
    validate_file_name(&request.new_name)?;
    let parent = parent_path(&request.source.path);
    let expected_path = child_path(parent, &request.new_name);

    let entry = dispatch(&state, |response_tx| RemoteFsEvent::Rename {
        peer,
        request,
        response_tx,
    })
    .await?;
    validate_exact_entry(&entry, &expected_path)?;

    Ok(json_response(
        StatusCode::OK,
        RemoteFsMutationResponse { entry },
    ))
}

async fn move_entry(
    req: Request<Incoming>,
    state: Arc<RemoteFsState>,
    peer: RemoteFsPeer,
) -> RemoteFsResult<Response<BoxedBody>> {
    let request = collect_json::<RemoteFsMoveRequest>(req.into_body()).await?;
    request.source.validate()?;
    require_entry_path(&request.source)?;
    request.destination_parent.validate()?;
    if let Some(name) = &request.new_name {
        validate_file_name(name)?;
    }
    let source_name = request.source.path.rsplit('/').next().unwrap_or_default();
    let expected_path = child_path(
        &request.destination_parent.path,
        request.new_name.as_deref().unwrap_or(source_name),
    );

    let entry = dispatch(&state, |response_tx| RemoteFsEvent::Move {
        peer,
        request,
        response_tx,
    })
    .await?;
    validate_exact_entry(&entry, &expected_path)?;

    Ok(json_response(
        StatusCode::OK,
        RemoteFsMutationResponse { entry },
    ))
}

async fn delete(
    req: Request<Incoming>,
    state: Arc<RemoteFsState>,
    peer: RemoteFsPeer,
) -> RemoteFsResult<Response<BoxedBody>> {
    let query = parse_query(req.uri().query());
    let target = location_from_query(&query)?;
    require_entry_path(&target)?;
    let recursive = parse_bool(query.get("recursive"), false)?;
    let request = RemoteFsDeleteRequest { target, recursive };

    dispatch(&state, |response_tx| RemoteFsEvent::Delete {
        peer,
        request,
        response_tx,
    })
    .await?;

    Ok(status_response(StatusCode::NO_CONTENT))
}

async fn read(
    req: Request<Incoming>,
    state: Arc<RemoteFsState>,
    peer: RemoteFsPeer,
    request_permit: OwnedSemaphorePermit,
) -> RemoteFsResult<Response<BoxedBody>> {
    let query = parse_query(req.uri().query());
    let target = location_from_query(&query)?;
    require_entry_path(&target)?;

    let source = dispatch(&state, |response_tx| RemoteFsEvent::Read {
        peer,
        target: target.clone(),
        response_tx,
    })
    .await?;
    validate_exact_entry(&source.entry, &target.path)?;
    if source.entry.entry_type != RemoteFsEntryType::File {
        return Err(RemoteFsErrorCode::IsDirectory);
    }
    let size = source.entry.size.ok_or(RemoteFsErrorCode::Internal)?;

    let mut response = Response::new(receiver_stream_body(
        source.content.into_receiver(),
        request_permit,
    ));
    response
        .headers_mut()
        .insert(http::header::CONTENT_LENGTH, http::HeaderValue::from(size));
    let content_type = source
        .entry
        .mime_type
        .as_deref()
        .and_then(|mime| http::HeaderValue::from_str(mime).ok())
        .unwrap_or_else(|| http::HeaderValue::from_static("application/octet-stream"));
    response
        .headers_mut()
        .insert(http::header::CONTENT_TYPE, content_type);
    Ok(response)
}

async fn write(
    req: Request<Incoming>,
    state: Arc<RemoteFsState>,
    peer: RemoteFsPeer,
) -> RemoteFsResult<Response<BoxedBody>> {
    let query = parse_query(req.uri().query());
    let target = location_from_query(&query)?;
    require_entry_path(&target)?;
    let overwrite = parse_bool(query.get("overwrite"), false)?;
    let size = req
        .headers()
        .get(http::header::CONTENT_LENGTH)
        .and_then(|value| value.to_str().ok())
        .and_then(|value| value.parse::<u64>().ok())
        .ok_or(RemoteFsErrorCode::InvalidRequest)?;
    if size > state.max_write_size {
        return Err(RemoteFsErrorCode::PayloadTooLarge);
    }

    let request = RemoteFsWriteRequest {
        target,
        size,
        overwrite,
    };
    let target = dispatch(&state, |target_tx| RemoteFsEvent::Write {
        peer,
        request,
        target_tx,
    })
    .await?;

    let result = save_req_to_target(req, target, size, None, FileTimestamps::default()).await;
    match result {
        SaveResult::Success => Ok(json_response(
            StatusCode::OK,
            RemoteFsWriteResponse {
                bytes_written: size,
            },
        )),
        SaveResult::Failed | SaveResult::HashMismatch => Err(RemoteFsErrorCode::TransferFailed),
    }
}

async fn dispatch<T>(
    state: &RemoteFsState,
    event: impl FnOnce(oneshot::Sender<RemoteFsResult<T>>) -> RemoteFsEvent,
) -> RemoteFsResult<T> {
    let (response_tx, response_rx) = oneshot::channel();
    let exchange = async {
        state
            .event_tx
            .send(event(response_tx))
            .await
            .map_err(|_| RemoteFsErrorCode::Unavailable)?;
        response_rx
            .await
            .map_err(|_| RemoteFsErrorCode::Unavailable)?
    };
    tokio::time::timeout(EVENT_RESPONSE_TIMEOUT, exchange)
        .await
        .map_err(|_| RemoteFsErrorCode::Unavailable)?
}

async fn collect_json<T: DeserializeOwned>(body: Incoming) -> RemoteFsResult<T> {
    let mut body = body;
    let mut bytes = BytesMut::new();
    while let Some(frame) = body.frame().await {
        let frame = frame.map_err(|_| RemoteFsErrorCode::InvalidRequest)?;
        let Ok(data) = frame.into_data() else {
            continue;
        };
        if bytes.len().saturating_add(data.len()) > MAX_JSON_BODY_SIZE {
            return Err(RemoteFsErrorCode::PayloadTooLarge);
        }
        bytes.extend_from_slice(&data);
    }
    serde_json::from_slice(&bytes).map_err(|_| RemoteFsErrorCode::InvalidRequest)
}

fn location_from_query(
    query: &std::collections::HashMap<String, String>,
) -> RemoteFsResult<RemoteFsLocation> {
    let root_id = query
        .get("rootId")
        .cloned()
        .ok_or(RemoteFsErrorCode::InvalidRequest)?;
    RemoteFsLocation::new(root_id, query.get("path").cloned().unwrap_or_default())
}

fn require_entry_path(location: &RemoteFsLocation) -> RemoteFsResult<()> {
    if location.path.is_empty() {
        return Err(RemoteFsErrorCode::InvalidPath);
    }
    Ok(())
}

fn validate_exact_entry(entry: &RemoteFsEntry, expected_path: &str) -> RemoteFsResult<()> {
    validate_entry(entry, None)?;
    if entry.path != expected_path {
        return Err(RemoteFsErrorCode::Internal);
    }
    Ok(())
}

fn validate_cursor(cursor: Option<&str>) -> RemoteFsResult<()> {
    if cursor.is_some_and(|cursor| {
        cursor.is_empty() || cursor.len() > 1_024 || cursor.chars().any(char::is_control)
    }) {
        return Err(RemoteFsErrorCode::Internal);
    }
    Ok(())
}

fn parse_bool(value: Option<&String>, default: bool) -> RemoteFsResult<bool> {
    match value.map(String::as_str) {
        None => Ok(default),
        Some("true") => Ok(true),
        Some("false") => Ok(false),
        Some(_) => Err(RemoteFsErrorCode::InvalidRequest),
    }
}

fn parent_path(path: &str) -> &str {
    path.rsplit_once('/').map_or("", |(parent, _)| parent)
}

fn child_path(parent: &str, name: &str) -> String {
    if parent.is_empty() {
        name.to_string()
    } else {
        format!("{parent}/{name}")
    }
}

fn receiver_stream_body(
    binary_rx: mpsc::Receiver<Bytes>,
    request_permit: OwnedSemaphorePermit,
) -> BoxedBody {
    let stream = ReceiverStream::new(binary_rx).map(move |chunk| {
        // Capturing the permit keeps this request accounted for even while
        // HTTP backpressure pauses body polling.
        let _keep_request_slot = &request_permit;
        Ok::<_, std::io::Error>(Frame::data(chunk))
    });
    BodyExt::boxed(StreamBody::new(stream))
}

fn json_response<T: serde::Serialize>(status: StatusCode, body: T) -> Response<BoxedBody> {
    JsonResponse { status, body }.into_response()
}

fn status_response(status: StatusCode) -> Response<BoxedBody> {
    let mut response = Response::new(empty_body());
    *response.status_mut() = status;
    response
}

fn error_response(code: RemoteFsErrorCode) -> Response<BoxedBody> {
    json_response(error_status(code), RemoteFsErrorResponse::from(code))
}

fn error_status(code: RemoteFsErrorCode) -> StatusCode {
    match code {
        RemoteFsErrorCode::Unauthenticated => StatusCode::UNAUTHORIZED,
        RemoteFsErrorCode::UntrustedDevice
        | RemoteFsErrorCode::PermissionDenied
        | RemoteFsErrorCode::ReadOnly => StatusCode::FORBIDDEN,
        RemoteFsErrorCode::InvalidRequest
        | RemoteFsErrorCode::InvalidPath
        | RemoteFsErrorCode::InvalidName => StatusCode::BAD_REQUEST,
        RemoteFsErrorCode::RootNotFound | RemoteFsErrorCode::NotFound => StatusCode::NOT_FOUND,
        RemoteFsErrorCode::AlreadyExists
        | RemoteFsErrorCode::NotDirectory
        | RemoteFsErrorCode::IsDirectory
        | RemoteFsErrorCode::DirectoryNotEmpty
        | RemoteFsErrorCode::Conflict => StatusCode::CONFLICT,
        RemoteFsErrorCode::PayloadTooLarge => StatusCode::PAYLOAD_TOO_LARGE,
        RemoteFsErrorCode::StorageFull => StatusCode::INSUFFICIENT_STORAGE,
        RemoteFsErrorCode::Unsupported => StatusCode::NOT_IMPLEMENTED,
        RemoteFsErrorCode::Busy => StatusCode::TOO_MANY_REQUESTS,
        RemoteFsErrorCode::TransferFailed => StatusCode::UNPROCESSABLE_ENTITY,
        RemoteFsErrorCode::Unavailable => StatusCode::SERVICE_UNAVAILABLE,
        RemoteFsErrorCode::Internal => StatusCode::INTERNAL_SERVER_ERROR,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn active_requests_are_bounded_and_read_bodies_hold_their_slot() {
        let (event_tx, _event_rx) = mpsc::channel(2);
        let state = RemoteFsState::new(
            RemoteFsServerConfig::new(event_tx)
                .with_max_concurrent_requests(NonZeroUsize::new(1).unwrap()),
        );

        let permit = state.try_acquire_request().unwrap();
        assert!(matches!(
            state.try_acquire_request(),
            Err(RemoteFsErrorCode::Busy)
        ));

        let (_content_tx, content_rx) = mpsc::channel(1);
        let body = receiver_stream_body(content_rx, permit);
        assert!(matches!(
            state.try_acquire_request(),
            Err(RemoteFsErrorCode::Busy)
        ));

        // Disconnecting the reader drops the body and releases the slot even
        // when no content frame was produced.
        drop(body);
        assert!(state.try_acquire_request().is_ok());
    }
}
