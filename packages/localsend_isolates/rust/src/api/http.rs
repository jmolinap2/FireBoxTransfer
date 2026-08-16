use crate::api::cancel::RsCancellationToken;
use crate::api::stream;
use crate::frb_generated::StreamSink;
use flutter_rust_bridge::frb;
pub use localsend::http::client::{ClientError, LsHttpClientVersion};
use localsend::http::client::{FireboxTransferClient, RemoteFsClientError};
pub use localsend::http::dto::{
    PrepareUploadRequestDto, PrepareUploadResponseDto, PrepareUploadResult, RegisterDto,
    RegisterResponseDto,
};
pub use localsend::http::firebox::{
    RemoteFsCreateDirectoryRequest, RemoteFsDeleteRequest, RemoteFsEntry, RemoteFsErrorCode,
    RemoteFsListRequest, RemoteFsListResponse, RemoteFsLocation, RemoteFsMoveRequest,
    RemoteFsRenameRequest, RemoteFsRoot, RemoteFsWriteResponse,
};
use localsend::model::discovery::ProtocolType;
use localsend::reqwest;
use localsend::util::error::ErrorChain;

pub struct RsHttpClient {
    inner: localsend::http::client::LsHttpClient,
    remote_fs: Option<FireboxTransferClient>,
}

/// Creates an HTTP client.
///
/// `expected_fingerprint` pins the peer to the certificate with that SHA-256
/// fingerprint (uppercase hex). It is enforced during the TLS handshake, so a
/// peer that does not present the expected certificate never receives the
/// request. Pass `None` only for discovery, where the peer is not known yet.
#[frb(sync)]
pub fn create_client(
    private_key: String,
    cert: String,
    version: LsHttpClientVersion,
    expected_fingerprint: Option<String>,
    timeout_ms: Option<u32>,
) -> Result<RsHttpClient, RsHttpClientError> {
    let timeout = timeout_ms.map(|ms| std::time::Duration::from_millis(ms as u64));
    let remote_fs = match expected_fingerprint.clone() {
        Some(expected_fingerprint) => Some(
            FireboxTransferClient::try_new(&private_key, &cert, expected_fingerprint, timeout)
                .map_err(|error| RsHttpClientError::Other(error.to_string()))?,
        ),
        None => None,
    };
    let inner = localsend::http::client::LsHttpClient::new(
        &private_key,
        &cert,
        version,
        expected_fingerprint,
        timeout,
    )
    .map_err(RsHttpClientError::from)?;

    Ok(RsHttpClient { inner, remote_fs })
}

impl RsHttpClient {
    pub async fn register(
        &self,
        protocol: ProtocolType,
        ip: &str,
        port: u16,
        payload: RegisterDto,
    ) -> Result<ResultWithPublicKeyRegisterResponseDto, RsHttpClientError> {
        let response = self
            .inner
            .register(protocol, ip, port, payload)
            .await
            .map_err(RsHttpClientError::from)?;

        Ok(ResultWithPublicKeyRegisterResponseDto {
            public_key: response.public_key,
            body: response.body,
        })
    }

    pub async fn prepare_upload(
        &self,
        protocol: ProtocolType,
        ip: &str,
        port: u16,
        payload: PrepareUploadRequestDto,
        public_key: Option<String>,
        pin: Option<String>,
        cancel_token: &RsCancellationToken,
    ) -> Result<PrepareUploadResult, RsHttpClientError> {
        let response = self
            .inner
            .prepare_upload(
                protocol,
                ip,
                port,
                public_key,
                payload,
                pin.as_deref(),
                cancel_token.inner.clone(),
            )
            .await
            .map_err(RsHttpClientError::from)?;

        Ok(response)
    }

    /// Uploads a single file, emitting [RsUploadEvent]s on [sink].
    ///
    /// Failures are emitted as [RsUploadEvent::Failed] instead of being
    /// returned: flutter_rust_bridge discards the returned `Result` of
    /// functions taking a [StreamSink], so a returned error would become an
    /// uncaught async error killing the calling isolate.
    pub async fn upload(
        &self,
        sink: StreamSink<RsUploadEvent>,
        protocol: ProtocolType,
        ip: &str,
        port: u16,
        public_key: Option<String>,
        session_id: &str,
        file_id: &str,
        token: &str,
        binary: Option<stream::Dart2RustStreamReceiver>,
        path: Option<String>,
        file_descriptor: Option<i32>,
        content_length: u64,
        cancel_token: &RsCancellationToken,
    ) {
        let result = async {
            let content = resolve_file_content(binary, path, file_descriptor)?;
            let last_emit = std::cell::Cell::new(None::<std::time::Instant>);
            let progress_sink = sink.clone();
            let progress = move |sent| {
                let now = std::time::Instant::now();
                let is_final = sent >= content_length;
                if !is_final {
                    if let Some(last) = last_emit.get() {
                        if now.duration_since(last) < std::time::Duration::from_millis(20) {
                            return;
                        }
                    }
                }
                last_emit.set(Some(now));
                let progress = if content_length == 0 {
                    1.0
                } else {
                    (sent as f64 / content_length as f64).min(1.0)
                };
                let _ = progress_sink.add(RsUploadEvent::Progress { progress });
            };

            self.inner
                .upload(
                    protocol,
                    ip,
                    port,
                    public_key,
                    session_id,
                    file_id,
                    token,
                    content,
                    progress,
                    cancel_token.inner.clone(),
                )
                .await
                .map_err(RsHttpClientError::from)?;

            Ok(())
        }
        .await;

        if let Err(error) = result {
            let _ = sink.add(RsUploadEvent::Failed { error });
        }
    }

    pub async fn remote_fs_roots(
        &self,
        ip: &str,
        port: u16,
    ) -> Result<Vec<RemoteFsRoot>, RsRemoteFsClientError> {
        self.require_remote_fs()?
            .roots(ip, port)
            .await
            .map_err(Into::into)
    }

    pub async fn remote_fs_list(
        &self,
        ip: &str,
        port: u16,
        request: RemoteFsListRequest,
    ) -> Result<RemoteFsListResponse, RsRemoteFsClientError> {
        self.require_remote_fs()?
            .list(ip, port, request)
            .await
            .map_err(Into::into)
    }

    pub async fn remote_fs_metadata(
        &self,
        ip: &str,
        port: u16,
        target: RemoteFsLocation,
    ) -> Result<RemoteFsEntry, RsRemoteFsClientError> {
        self.require_remote_fs()?
            .metadata(ip, port, &target)
            .await
            .map_err(Into::into)
    }

    pub async fn remote_fs_create_directory(
        &self,
        ip: &str,
        port: u16,
        request: RemoteFsCreateDirectoryRequest,
    ) -> Result<RemoteFsEntry, RsRemoteFsClientError> {
        self.require_remote_fs()?
            .create_directory(ip, port, &request)
            .await
            .map_err(Into::into)
    }

    pub async fn remote_fs_rename(
        &self,
        ip: &str,
        port: u16,
        request: RemoteFsRenameRequest,
    ) -> Result<RemoteFsEntry, RsRemoteFsClientError> {
        self.require_remote_fs()?
            .rename(ip, port, &request)
            .await
            .map_err(Into::into)
    }

    pub async fn remote_fs_move(
        &self,
        ip: &str,
        port: u16,
        request: RemoteFsMoveRequest,
    ) -> Result<RemoteFsEntry, RsRemoteFsClientError> {
        self.require_remote_fs()?
            .move_entry(ip, port, &request)
            .await
            .map_err(Into::into)
    }

    pub async fn remote_fs_delete(
        &self,
        ip: &str,
        port: u16,
        request: RemoteFsDeleteRequest,
    ) -> Result<(), RsRemoteFsClientError> {
        self.require_remote_fs()?
            .delete(ip, port, &request)
            .await
            .map_err(Into::into)
    }

    /// Opens a pull-based remote read. Dart calls [RsRemoteReadStream::next_chunk]
    /// for each chunk, which provides natural backpressure and bounds memory.
    pub async fn remote_fs_open_read(
        &self,
        ip: &str,
        port: u16,
        target: RemoteFsLocation,
    ) -> Result<RsRemoteReadStream, RsRemoteFsClientError> {
        let response = self
            .require_remote_fs()?
            .read(ip, port, &target)
            .await
            .map_err(RsRemoteFsClientError::from)?;
        let content_length = response.content_length();
        let content_type = response
            .headers()
            .get(reqwest::header::CONTENT_TYPE)
            .and_then(|value| value.to_str().ok())
            .map(str::to_string);
        Ok(RsRemoteReadStream {
            content_length,
            content_type,
            state: tokio::sync::Mutex::new(RemoteReadState {
                response: Some(response),
                received: 0,
            }),
        })
    }

    /// Streams local content to a remote authorized path. The source may be a
    /// Dart stream, a path or an owned Android descriptor; exactly one is set.
    pub async fn remote_fs_write(
        &self,
        sink: StreamSink<RsRemoteFsWriteEvent>,
        ip: &str,
        port: u16,
        target: RemoteFsLocation,
        overwrite: bool,
        binary: Option<stream::Dart2RustStreamReceiver>,
        path: Option<String>,
        file_descriptor: Option<i32>,
        content_length: u64,
        cancel_token: &RsCancellationToken,
    ) {
        let result = async {
            let content = resolve_file_content(binary, path, file_descriptor)
                .map_err(|error| RsRemoteFsClientError::Other(error.message()))?;
            let progress_sink = sink.clone();
            let last_emit = std::cell::Cell::new(None::<std::time::Instant>);
            let progress = move |bytes_written| {
                let now = std::time::Instant::now();
                let is_final = bytes_written >= content_length;
                if !is_final
                    && last_emit.get().is_some_and(|last| {
                        now.duration_since(last) < std::time::Duration::from_millis(20)
                    })
                {
                    return;
                }
                last_emit.set(Some(now));
                let _ = progress_sink.add(RsRemoteFsWriteEvent::Progress { bytes_written });
            };

            self.require_remote_fs()?
                .write(
                    ip,
                    port,
                    &target,
                    content_length,
                    overwrite,
                    content,
                    progress,
                    cancel_token.inner.clone(),
                )
                .await
                .map_err(RsRemoteFsClientError::from)
        }
        .await;

        match result {
            Ok(response) => {
                let _ = sink.add(RsRemoteFsWriteEvent::Completed {
                    bytes_written: response.bytes_written,
                });
            }
            Err(error) => {
                let _ = sink.add(RsRemoteFsWriteEvent::Failed { error });
            }
        }
    }

    fn require_remote_fs(&self) -> Result<&FireboxTransferClient, RsRemoteFsClientError> {
        self.remote_fs.as_ref().ok_or_else(|| {
            RsRemoteFsClientError::Other(
                "Remote filesystem requires a client pinned to the peer certificate".to_string(),
            )
        })
    }

    pub async fn cancel(
        &self,
        protocol: ProtocolType,
        ip: &str,
        port: u16,
        session_id: &str,
    ) -> Result<(), RsHttpClientError> {
        self.inner
            .cancel(protocol, ip, port, session_id)
            .await
            .map_err(RsHttpClientError::from)?;

        Ok(())
    }
}

struct RemoteReadState {
    response: Option<reqwest::Response>,
    received: u64,
}

/// Pull-based remote content stream. Each call reads at most one HTTP chunk,
/// so Dart controls backpressure and the entire file is never held in memory.
pub struct RsRemoteReadStream {
    content_length: Option<u64>,
    content_type: Option<String>,
    state: tokio::sync::Mutex<RemoteReadState>,
}

impl RsRemoteReadStream {
    #[frb(sync)]
    pub fn content_length(&self) -> Option<u64> {
        self.content_length
    }

    #[frb(sync)]
    pub fn content_type(&self) -> Option<String> {
        self.content_type.clone()
    }

    pub async fn next_chunk(
        &self,
        cancel_token: &RsCancellationToken,
    ) -> Result<Option<Vec<u8>>, RsRemoteFsClientError> {
        let mut state = self.state.lock().await;
        let Some(response) = state.response.as_mut() else {
            return Ok(None);
        };
        let outcome = tokio::select! {
            biased;
            _ = cancel_token.inner.cancelled() => None,
            chunk = response.chunk() => Some(chunk),
        };
        let Some(outcome) = outcome else {
            state.response = None;
            return Err(RsRemoteFsClientError::Cancelled);
        };
        let chunk = match outcome {
            Ok(chunk) => chunk,
            Err(error) => {
                state.response = None;
                return Err(RsRemoteFsClientError::Reqwest(
                    ErrorChain(&error).to_string(),
                ));
            }
        };
        match chunk {
            Some(chunk) => {
                state.received = state.received.saturating_add(chunk.len() as u64);
                if self
                    .content_length
                    .is_some_and(|expected| state.received > expected)
                {
                    state.response = None;
                    return Err(RsRemoteFsClientError::InvalidResponse);
                }
                Ok(Some(chunk.to_vec()))
            }
            None => {
                let size_valid = self
                    .content_length
                    .is_none_or(|expected| expected == state.received);
                state.response = None;
                if !size_valid {
                    return Err(RsRemoteFsClientError::InvalidResponse);
                }
                Ok(None)
            }
        }
    }
}

fn resolve_file_content(
    binary: Option<stream::Dart2RustStreamReceiver>,
    path: Option<String>,
    file_descriptor: Option<i32>,
) -> Result<localsend::model::transfer::FileContent, RsHttpClientError> {
    match (binary, path, file_descriptor) {
        (Some(binary), None, None) => Ok(localsend::model::transfer::FileContent::Stream(
            binary.receiver,
        )),
        (None, Some(path), None) => Ok(localsend::model::transfer::FileContent::Path(path.into())),
        (None, None, Some(file_descriptor)) => {
            #[cfg(target_os = "android")]
            {
                Ok(localsend::model::transfer::FileContent::Fd(file_descriptor))
            }
            #[cfg(not(target_os = "android"))]
            {
                let _ = file_descriptor;
                Err(RsHttpClientError::Other(
                    "File descriptors are only supported on Android".into(),
                ))
            }
        }
        _ => Err(RsHttpClientError::Other(
            "Exactly one upload content source must be provided".into(),
        )),
    }
}

/// An event emitted while a file is being uploaded by [RsHttpClient::upload].
#[derive(Clone)]
pub enum RsUploadEvent {
    /// The upload progress as a fraction (0.0 to 1.0). Throttled.
    Progress { progress: f64 },

    /// The upload failed. Always the last event of the stream.
    Failed { error: RsHttpClientError },
}

#[derive(Clone)]
pub enum RsRemoteFsWriteEvent {
    Progress { bytes_written: u64 },
    Completed { bytes_written: u64 },
    Failed { error: RsRemoteFsClientError },
}

#[derive(Clone)]
pub enum RsRemoteFsClientError {
    Remote {
        status: u16,
        code: RemoteFsErrorCode,
        message: String,
    },
    Setup(String),
    Reqwest(String),
    Json(String),
    Io(String),
    InvalidRequest {
        code: RemoteFsErrorCode,
    },
    InvalidResponse,
    Cancelled,
    Other(String),
}

impl From<RemoteFsClientError> for RsRemoteFsClientError {
    fn from(error: RemoteFsClientError) -> Self {
        match error {
            RemoteFsClientError::Setup(error) => Self::Setup(error.to_string()),
            RemoteFsClientError::Remote { status, error } => Self::Remote {
                status,
                code: error.code,
                message: error.message,
            },
            RemoteFsClientError::Reqwest(error) => Self::Reqwest(ErrorChain(&error).to_string()),
            RemoteFsClientError::Json(error) => Self::Json(error.to_string()),
            RemoteFsClientError::Io(error) => Self::Io(error.to_string()),
            RemoteFsClientError::InvalidRequest(code) => Self::InvalidRequest { code },
            RemoteFsClientError::InvalidResponse => Self::InvalidResponse,
            RemoteFsClientError::Cancelled => Self::Cancelled,
        }
    }
}

#[derive(Clone)]
pub enum RsHttpClientError {
    StatusCode {
        status: u16,
        message: Option<String>,
    },
    Reqwest(String),
    Json(String),
    Io(String),
    Other(String),
}

impl From<ClientError> for RsHttpClientError {
    fn from(e: ClientError) -> Self {
        match e {
            ClientError::StatusCode(e) => RsHttpClientError::StatusCode {
                status: e.status,
                message: e.message,
            },
            ClientError::Reqwest(e) => RsHttpClientError::Reqwest(ErrorChain(&e).to_string()),
            ClientError::Json(e) => RsHttpClientError::Json(e.to_string()),
            ClientError::Io(e) => RsHttpClientError::Io(e.to_string()),
            ClientError::Other(e) => RsHttpClientError::Other(e.to_string()),
            ClientError::Cancelled => RsHttpClientError::Other("Upload cancelled".to_string()),
        }
    }
}

impl RsHttpClientError {
    fn message(&self) -> String {
        match self {
            Self::StatusCode { status, message } => match message {
                Some(message) => format!("HTTP {status}: {message}"),
                None => format!("HTTP {status}"),
            },
            Self::Reqwest(message)
            | Self::Json(message)
            | Self::Io(message)
            | Self::Other(message) => message.clone(),
        }
    }
}

#[frb(mirror(LsHttpClientVersion))]
pub enum _LsHttpClientVersion {
    V2,
    V3,
}

#[frb(mirror(PrepareUploadResult))]
pub struct _PrepareUploadResult {
    pub status_code: u16,
    pub response: Option<PrepareUploadResponseDto>,
}

pub struct ResultWithPublicKeyRegisterResponseDto {
    pub public_key: Option<String>,
    pub body: RegisterResponseDto,
}
