use crate::frb_generated::StreamSink;
use flutter_rust_bridge::frb;
pub use localsend::http::dto_v2::RegisterDtoV2;
use localsend::http::firebox::{
    RemoteFsCreateDirectoryRequest, RemoteFsDeleteRequest, RemoteFsEntry, RemoteFsErrorCode,
    RemoteFsListRequest, RemoteFsListResponse, RemoteFsLocation, RemoteFsMoveRequest,
    RemoteFsRenameRequest, RemoteFsRoot, RemoteFsWriteRequest,
};
use localsend::http::server::ServerConfigV2;
pub use localsend::http::server::TlsConfig;
use localsend::http::server::common::save::FileUploadTarget;
use localsend::http::server::firebox::{
    DEFAULT_MAX_CONCURRENT_REQUESTS, RemoteFsEvent, RemoteFsPeer, RemoteFsReadSource,
    RemoteFsResult, RemoteFsServerConfig,
};
use localsend::http::server::internal::{InternalConfig, InternalEvent};
pub use localsend::http::server::v2::SessionEndReasonV2;
use localsend::http::server::v2::{PrepareUploadDecisionV2, ServerEventV2};
pub use localsend::http::server::web::WebI18n;
use localsend::http::server::web::{WebConfig, WebSendConfig, WebSendEvent};
use localsend::http::state::ClientInfo;
use localsend::model::discovery::DeviceType;
use localsend::model::discovery::ProtocolType;
use localsend::model::transfer::{FileContent, FileDto};
use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::{Mutex, mpsc, oneshot};

/// Events emitted by the HTTP server that must be handled by the application.
///
/// [RsServerEvent::PrepareUpload] must be answered with [RsHttpServer::respond_prepare_upload]
/// and [RsServerEvent::FileUpload] with [RsHttpServer::respond_file_upload].
///
/// The `ip` of an event renders a link-local IPv6 peer as `fe80::1%3`,
/// including the interface scope, which the Rust HTTP client accepts back as
/// a host.
pub enum RsServerEvent {
    /// A device registered itself via `POST /api/localsend/v2/register`.
    ///
    /// On TLS, this event is only emitted when `info.fingerprint` matches the
    /// fingerprint of the client certificate verified during the mTLS
    /// handshake, so the fingerprint cannot be spoofed.
    Register { ip: String, info: RegisterDtoV2 },

    /// A sender requests to upload files via `POST /api/localsend/v2/prepare-upload`.
    PrepareUpload {
        /// The session ID the upload session will have when the request is accepted.
        session_id: String,
        ip: String,
        info: RegisterDtoV2,
        /// The SHA-256 fingerprint (uppercase hex) of the sender's client
        /// certificate verified during the mTLS handshake. Unlike
        /// `info.fingerprint`, this value cannot be spoofed.
        /// `None` when the server runs without TLS.
        cert_fingerprint: Option<String>,
        files: HashMap<String, FileDto>,
    },

    /// An accepted file is being uploaded via `POST /api/localsend/v2/upload`.
    FileUpload {
        session_id: String,
        file_id: String,
        file: FileDto,
    },

    /// An upload session ended.
    SessionEnd {
        session_id: String,
        reason: SessionEndReasonV2,
    },

    /// A prepare-upload request was aborted before a session was created,
    /// e.g. the sender disconnected while the application was still deciding.
    /// The [RsServerEvent::PrepareUpload] with the same session ID
    /// no longer needs to be answered.
    PrepareUploadAborted { session_id: String },

    /// `POST /api/localsend/v2/cancel` was received for a session this server
    /// does not manage: the remote device cancels a transfer this application
    /// is currently *sending* to it. The application must verify that [ip]
    /// matches the target of the send session before cancelling it.
    CancelReceived { ip: String, session_id: String },

    /// A web client requests to download the shared files via `POST /api/localsend/v2/prepare-download`.
    ///
    /// Must be answered with [RsHttpServer::respond_prepare_download].
    WebPrepareDownload {
        ip: String,
        session_id: String,
        user_agent: Option<String>,
    },

    /// A web client downloads an offered file via `GET /api/localsend/v2/download`.
    ///
    /// Must be answered with [RsHttpServer::respond_file_download].
    WebFileDownload {
        session_id: String,
        file_id: String,
        file: FileDto,
    },

    /// Another application instance requested the running application to show itself
    /// via `POST /api/localsend/v2/show`.
    Show {
        /// Command-line arguments forwarded by the other application instance.
        args: Vec<String>,
    },

    RemoteFsRoots {
        request_id: String,
        peer: RsRemoteFsPeer,
    },
    RemoteFsList {
        request_id: String,
        peer: RsRemoteFsPeer,
        request: RemoteFsListRequest,
    },
    RemoteFsMetadata {
        request_id: String,
        peer: RsRemoteFsPeer,
        target: RemoteFsLocation,
    },
    RemoteFsCreateDirectory {
        request_id: String,
        peer: RsRemoteFsPeer,
        request: RemoteFsCreateDirectoryRequest,
    },
    RemoteFsRename {
        request_id: String,
        peer: RsRemoteFsPeer,
        request: RemoteFsRenameRequest,
    },
    RemoteFsMove {
        request_id: String,
        peer: RsRemoteFsPeer,
        request: RemoteFsMoveRequest,
    },
    RemoteFsDelete {
        request_id: String,
        peer: RsRemoteFsPeer,
        request: RemoteFsDeleteRequest,
    },
    RemoteFsRead {
        request_id: String,
        peer: RsRemoteFsPeer,
        target: RemoteFsLocation,
    },
    RemoteFsWrite {
        request_id: String,
        peer: RsRemoteFsPeer,
        request: RemoteFsWriteRequest,
    },
}

pub struct RsRemoteFsPeer {
    pub ip: String,
    pub certificate_fingerprint: String,
}

impl From<RemoteFsPeer> for RsRemoteFsPeer {
    fn from(peer: RemoteFsPeer) -> Self {
        Self {
            ip: peer.ip.to_string(),
            certificate_fingerprint: peer.certificate_fingerprint,
        }
    }
}

enum PendingRemoteFsResponder {
    Roots(oneshot::Sender<RemoteFsResult<Vec<RemoteFsRoot>>>),
    List(oneshot::Sender<RemoteFsResult<RemoteFsListResponse>>),
    Entry(oneshot::Sender<RemoteFsResult<RemoteFsEntry>>),
    Delete(oneshot::Sender<RemoteFsResult<()>>),
    Read(oneshot::Sender<RemoteFsResult<RemoteFsReadSource>>),
    Write {
        target_tx: oneshot::Sender<RemoteFsResult<FileUploadTarget>>,
        expected_size: u64,
    },
}

impl PendingRemoteFsResponder {
    fn is_closed(&self) -> bool {
        match self {
            Self::Roots(tx) => tx.is_closed(),
            Self::List(tx) => tx.is_closed(),
            Self::Entry(tx) => tx.is_closed(),
            Self::Delete(tx) => tx.is_closed(),
            Self::Read(tx) => tx.is_closed(),
            Self::Write { target_tx, .. } => target_tx.is_closed(),
        }
    }
}

pub struct RsHttpServer {
    instance: Arc<ServerInstance>,
    event_rx: Mutex<Option<mpsc::Receiver<ServerEventV2>>>,
    pending_decision: Mutex<Option<(String, oneshot::Sender<PrepareUploadDecisionV2>)>>,
    pending_uploads: Mutex<HashMap<(String, String), oneshot::Sender<FileUploadTarget>>>,
    web_event_rx: Mutex<Option<mpsc::Receiver<WebSendEvent>>>,
    pending_download_decisions: Mutex<HashMap<String, oneshot::Sender<bool>>>,
    pending_downloads: Mutex<HashMap<(String, String), oneshot::Sender<FileContent>>>,
    internal_event_rx: Mutex<Option<mpsc::Receiver<InternalEvent>>>,
    remote_fs_event_rx: Mutex<Option<mpsc::Receiver<RemoteFsEvent>>>,
    pending_remote_fs: Mutex<HashMap<String, PendingRemoteFsResponder>>,
}

/// The stoppable part of a running server, shared between [RsHttpServer] and
/// [RUNNING_SERVER] so that a leftover instance can be stopped without its
/// Dart owner.
struct ServerInstance {
    handle: localsend::http::server::ServerHandle,
    stop_tx: Mutex<Option<oneshot::Sender<()>>>,
}

impl ServerInstance {
    /// Stops the server and waits until the listeners are closed, so the port
    /// can be bound again. Does nothing when already stopped.
    async fn stop(&self) {
        if let Some(stop_tx) = self.stop_tx.lock().await.take() {
            let _ = stop_tx.send(());
            self.handle.wait_stopped().await;
        }
    }
}

/// The most recently started server. A Flutter hot restart kills all Dart
/// isolates without stopping the Rust server task, which would keep the port
/// bound forever; [start_server] stops such a leftover instance before
/// binding again.
static RUNNING_SERVER: Mutex<Option<Arc<ServerInstance>>> = Mutex::const_new(None);

/// Configuration for the web pages served to browsers. When omitted, the web
/// pages respond with 403 and only the v2 endpoints run.
pub struct WebParams {
    /// Enables web send (the download page): files offered for download by web
    /// browsers. `null` disables the download page and the download API.
    pub send: Option<WebSendParams>,

    /// Serves the upload page so web browsers can upload files via the v2
    /// `prepare-upload`/`upload` endpoints. Ignored when [WebParams::send] is
    /// set: the download page takes precedence at `/`.
    pub upload: bool,

    /// Translations for the web pages, served via `/i18n.json`.
    pub i18n: WebI18n,
}

/// Configuration for web send: files offered for download by web browsers.
///
/// Web send can be enabled independently of the v2 protocol endpoints.
pub struct WebSendParams {
    /// The metadata of the files offered for download, mapped by file ID.
    /// The content is requested per download via [RsServerEvent::WebFileDownload].
    pub files: HashMap<String, FileDto>,

    /// Optional PIN that web clients must provide via the `pin` query parameter.
    pub pin: Option<String>,
}

/// Enables the FireBoxTransfer filesystem API. This is rejected unless [tls]
/// is present, because every request is identified by its verified mTLS
/// client-certificate fingerprint.
pub struct RemoteFsParams {
    pub max_write_size: u64,
}

/// Starts the HTTP server on the given port (IPv4 and IPv6).
/// The server runs until [RsHttpServer::stop] is called.
///
/// Passing [web] additionally serves the web pages: the download page when
/// [WebParams::send] is set (so web browsers can download the offered files)
/// or the upload page when [WebParams::upload] is enabled.
///
/// Passing [show_token] enables the internal `show` endpoint that lets another
/// application instance request this one to show itself (emitted as
/// [RsServerEvent::Show]). The token guards the endpoint against other clients.
///
/// Events are received by listening to [RsHttpServer::listen].
pub async fn start_server(
    port: u16,
    tls: Option<TlsConfig>,
    alias: String,
    version: String,
    device_model: Option<String>,
    device_type: Option<DeviceType>,
    fingerprint: String,
    pin: Option<String>,
    verify_checksums: bool,
    web: Option<WebParams>,
    show_token: Option<String>,
) -> anyhow::Result<RsHttpServer> {
    start_server_impl(
        port,
        tls,
        alias,
        version,
        device_model,
        device_type,
        fingerprint,
        pin,
        verify_checksums,
        web,
        show_token,
        None,
    )
    .await
}

/// Starts the compatible LocalSend server with the authenticated
/// FireBoxTransfer filesystem API enabled. Unlike [start_server], TLS is not
/// optional in this entry point.
pub async fn start_server_with_remote_fs(
    port: u16,
    tls: TlsConfig,
    alias: String,
    version: String,
    device_model: Option<String>,
    device_type: Option<DeviceType>,
    fingerprint: String,
    pin: Option<String>,
    verify_checksums: bool,
    web: Option<WebParams>,
    show_token: Option<String>,
    remote_fs: RemoteFsParams,
) -> anyhow::Result<RsHttpServer> {
    start_server_impl(
        port,
        Some(tls),
        alias,
        version,
        device_model,
        device_type,
        fingerprint,
        pin,
        verify_checksums,
        web,
        show_token,
        Some(remote_fs),
    )
    .await
}

async fn start_server_impl(
    port: u16,
    tls: Option<TlsConfig>,
    alias: String,
    version: String,
    device_model: Option<String>,
    device_type: Option<DeviceType>,
    fingerprint: String,
    pin: Option<String>,
    verify_checksums: bool,
    web: Option<WebParams>,
    show_token: Option<String>,
    remote_fs: Option<RemoteFsParams>,
) -> anyhow::Result<RsHttpServer> {
    // Stop a server left over from before a hot restart (its Dart owner died
    // without calling stop)
    let mut running_server = RUNNING_SERVER.lock().await;
    if let Some(previous) = running_server.take() {
        previous.stop().await;
    }

    let (event_tx, event_rx) = mpsc::channel::<ServerEventV2>(16);
    let (stop_tx, stop_rx) = oneshot::channel::<()>();

    if remote_fs.is_some() && tls.is_none() {
        return Err(anyhow::anyhow!(
            "The FireBoxTransfer filesystem API requires TLS"
        ));
    }

    let (web_config, web_event_rx) = match web {
        Some(web) => {
            let (send_config, web_event_rx) = match web.send {
                Some(send) => {
                    let (web_event_tx, web_event_rx) = mpsc::channel::<WebSendEvent>(16);
                    let config = WebSendConfig {
                        files: send.files,
                        pin: send.pin,
                        event_tx: web_event_tx,
                    };
                    (Some(config), Some(web_event_rx))
                }
                None => (None, None),
            };
            let config = WebConfig {
                send: send_config,
                upload: web.upload,
                i18n: web.i18n,
            };
            (Some(config), web_event_rx)
        }
        None => (None, None),
    };

    let (internal_config, internal_event_rx) = match show_token {
        Some(show_token) => {
            let (internal_event_tx, internal_event_rx) = mpsc::channel::<InternalEvent>(16);
            let config = InternalConfig {
                show_token,
                event_tx: internal_event_tx,
            };
            (Some(config), Some(internal_event_rx))
        }
        None => (None, None),
    };

    let info = ClientInfo {
        alias,
        version,
        device_model,
        device_type,
        token: fingerprint,
    };
    let v2_config = Some(ServerConfigV2 {
        pin,
        verify_checksums,
        event_tx,
    });
    let (handle, remote_fs_event_rx) = match remote_fs {
        Some(remote_fs) => {
            let (remote_fs_event_tx, remote_fs_event_rx) = mpsc::channel::<RemoteFsEvent>(32);
            let tls = tls.expect("TLS checked above");
            let handle = localsend::http::server::start_with_port_and_firebox(
                port,
                tls,
                info,
                internal_config,
                v2_config,
                web_config,
                RemoteFsServerConfig::new(remote_fs_event_tx)
                    .with_max_write_size(remote_fs.max_write_size),
                stop_rx,
            )
            .await?;
            (handle, Some(remote_fs_event_rx))
        }
        None => {
            let handle = localsend::http::server::start_with_port(
                port,
                tls,
                info,
                internal_config,
                v2_config,
                web_config,
                stop_rx,
            )
            .await?;
            (handle, None)
        }
    };

    let instance = Arc::new(ServerInstance {
        handle,
        stop_tx: Mutex::new(Some(stop_tx)),
    });
    *running_server = Some(instance.clone());

    Ok(RsHttpServer {
        instance,
        event_rx: Mutex::new(Some(event_rx)),
        pending_decision: Mutex::new(None),
        pending_uploads: Mutex::new(HashMap::new()),
        web_event_rx: Mutex::new(web_event_rx),
        pending_download_decisions: Mutex::new(HashMap::new()),
        pending_downloads: Mutex::new(HashMap::new()),
        internal_event_rx: Mutex::new(internal_event_rx),
        remote_fs_event_rx: Mutex::new(remote_fs_event_rx),
        pending_remote_fs: Mutex::new(HashMap::new()),
    })
}

impl RsHttpServer {
    /// Emits server events until the server is stopped.
    /// Can only be listened to once.
    ///
    /// The v2 protocol, the web send (download API), and the internal endpoint
    /// events are all emitted on the same stream.
    ///
    /// Also returns when the Dart side of the stream is gone (e.g. after a
    /// hot restart), so this call does not keep the server alive forever.
    pub async fn listen(&self, sink: StreamSink<RsServerEvent>) {
        let Some(mut event_rx) = self.event_rx.lock().await.take() else {
            let _ = sink.add_error(anyhow::anyhow!("Server events already listened to"));
            return;
        };
        let mut web_event_rx = self.web_event_rx.lock().await.take();
        let mut internal_event_rx = self.internal_event_rx.lock().await.take();
        let mut remote_fs_event_rx = self.remote_fs_event_rx.lock().await.take();
        let mut remote_fs_cleanup = tokio::time::interval(std::time::Duration::from_secs(5));
        remote_fs_cleanup.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);

        let mut v2_open = true;
        loop {
            let sink_open = tokio::select! {
                event = event_rx.recv(), if v2_open => {
                    match event {
                        Some(event) => self.handle_server_event(&sink, event).await,
                        None => {
                            v2_open = false;
                            true
                        }
                    }
                }
                event = recv_opt(&mut web_event_rx) => {
                    match event {
                        Some(event) => self.handle_web_event(&sink, event).await,
                        None => {
                            web_event_rx = None;
                            true
                        }
                    }
                }
                event = recv_opt(&mut internal_event_rx) => {
                    match event {
                        Some(InternalEvent::Show { args }) => {
                            sink.add(RsServerEvent::Show { args }).is_ok()
                        }
                        None => {
                            internal_event_rx = None;
                            true
                        }
                    }
                }
                event = recv_opt(&mut remote_fs_event_rx) => {
                    match event {
                        Some(event) => self.handle_remote_fs_event(&sink, event).await,
                        None => {
                            remote_fs_event_rx = None;
                            true
                        }
                    }
                }
                _ = remote_fs_cleanup.tick(), if remote_fs_event_rx.is_some() => {
                    self.prune_closed_remote_fs_responders().await;
                    true
                }
            };

            // The Dart listener is gone; the remaining events have no receiver.
            if !sink_open {
                break;
            }

            if !v2_open
                && web_event_rx.is_none()
                && internal_event_rx.is_none()
                && remote_fs_event_rx.is_none()
            {
                break;
            }
        }

        // A lost Dart listener cannot answer these requests. Dropping every
        // responder releases the HTTP handlers immediately with a safe 503.
        self.pending_remote_fs.lock().await.clear();
    }

    /// Returns whether the sink is still open.
    async fn handle_server_event(
        &self,
        sink: &StreamSink<RsServerEvent>,
        event: ServerEventV2,
    ) -> bool {
        match event {
            ServerEventV2::Register { ip, info } => sink
                .add(RsServerEvent::Register {
                    ip: ip.to_string(),
                    info,
                })
                .is_ok(),
            ServerEventV2::PrepareUpload {
                session_id,
                ip,
                info,
                cert_fingerprint,
                files,
                decision_tx,
            } => {
                *self.pending_decision.lock().await = Some((session_id.clone(), decision_tx));
                sink.add(RsServerEvent::PrepareUpload {
                    session_id,
                    ip: ip.to_string(),
                    info,
                    cert_fingerprint,
                    files,
                })
                .is_ok()
            }
            ServerEventV2::FileUpload {
                session_id,
                file_id,
                file,
                target_tx,
            } => {
                self.pending_uploads
                    .lock()
                    .await
                    .insert((session_id.clone(), file_id.clone()), target_tx);
                sink.add(RsServerEvent::FileUpload {
                    session_id,
                    file_id,
                    file,
                })
                .is_ok()
            }
            ServerEventV2::SessionEnd { session_id, reason } => {
                // Drop stale upload responders of this session (their requests already ended).
                self.pending_uploads
                    .lock()
                    .await
                    .retain(|(sid, _), _| sid != &session_id);
                sink.add(RsServerEvent::SessionEnd { session_id, reason })
                    .is_ok()
            }
            ServerEventV2::PrepareUploadAborted { session_id } => {
                // Drop the stale decision responder (the request already ended).
                // A newer prepare-upload request may already hold the slot;
                // only clear it if it still belongs to the aborted request.
                {
                    let mut pending = self.pending_decision.lock().await;
                    if pending.as_ref().is_some_and(|(sid, _)| sid == &session_id) {
                        *pending = None;
                    }
                }
                sink.add(RsServerEvent::PrepareUploadAborted { session_id })
                    .is_ok()
            }
            ServerEventV2::CancelReceived { ip, session_id } => sink
                .add(RsServerEvent::CancelReceived {
                    ip: ip.to_string(),
                    session_id,
                })
                .is_ok(),
        }
    }

    /// Returns whether the sink is still open.
    async fn handle_web_event(
        &self,
        sink: &StreamSink<RsServerEvent>,
        event: WebSendEvent,
    ) -> bool {
        match event {
            WebSendEvent::PrepareDownload {
                ip,
                session_id,
                user_agent,
                decision_tx,
            } => {
                self.pending_download_decisions
                    .lock()
                    .await
                    .insert(session_id.clone(), decision_tx);
                sink.add(RsServerEvent::WebPrepareDownload {
                    ip: ip.to_string(),
                    session_id,
                    user_agent,
                })
                .is_ok()
            }
            WebSendEvent::FileDownload {
                session_id,
                file_id,
                file,
                content_tx,
            } => {
                self.pending_downloads
                    .lock()
                    .await
                    .insert((session_id.clone(), file_id.clone()), content_tx);
                sink.add(RsServerEvent::WebFileDownload {
                    session_id,
                    file_id,
                    file,
                })
                .is_ok()
            }
        }
    }

    /// Stores the typed responder under a unique request ID before emitting
    /// the event to Dart, so any number of filesystem requests can be pending
    /// concurrently and answered out of order.
    async fn handle_remote_fs_event(
        &self,
        sink: &StreamSink<RsServerEvent>,
        event: RemoteFsEvent,
    ) -> bool {
        let request_id = uuid::Uuid::new_v4().to_string();
        let (responder, event) = match event {
            RemoteFsEvent::Roots { peer, response_tx } => (
                PendingRemoteFsResponder::Roots(response_tx),
                RsServerEvent::RemoteFsRoots {
                    request_id: request_id.clone(),
                    peer: peer.into(),
                },
            ),
            RemoteFsEvent::List {
                peer,
                request,
                response_tx,
            } => (
                PendingRemoteFsResponder::List(response_tx),
                RsServerEvent::RemoteFsList {
                    request_id: request_id.clone(),
                    peer: peer.into(),
                    request,
                },
            ),
            RemoteFsEvent::Metadata {
                peer,
                target,
                response_tx,
            } => (
                PendingRemoteFsResponder::Entry(response_tx),
                RsServerEvent::RemoteFsMetadata {
                    request_id: request_id.clone(),
                    peer: peer.into(),
                    target,
                },
            ),
            RemoteFsEvent::CreateDirectory {
                peer,
                request,
                response_tx,
            } => (
                PendingRemoteFsResponder::Entry(response_tx),
                RsServerEvent::RemoteFsCreateDirectory {
                    request_id: request_id.clone(),
                    peer: peer.into(),
                    request,
                },
            ),
            RemoteFsEvent::Rename {
                peer,
                request,
                response_tx,
            } => (
                PendingRemoteFsResponder::Entry(response_tx),
                RsServerEvent::RemoteFsRename {
                    request_id: request_id.clone(),
                    peer: peer.into(),
                    request,
                },
            ),
            RemoteFsEvent::Move {
                peer,
                request,
                response_tx,
            } => (
                PendingRemoteFsResponder::Entry(response_tx),
                RsServerEvent::RemoteFsMove {
                    request_id: request_id.clone(),
                    peer: peer.into(),
                    request,
                },
            ),
            RemoteFsEvent::Delete {
                peer,
                request,
                response_tx,
            } => (
                PendingRemoteFsResponder::Delete(response_tx),
                RsServerEvent::RemoteFsDelete {
                    request_id: request_id.clone(),
                    peer: peer.into(),
                    request,
                },
            ),
            RemoteFsEvent::Read {
                peer,
                target,
                response_tx,
            } => (
                PendingRemoteFsResponder::Read(response_tx),
                RsServerEvent::RemoteFsRead {
                    request_id: request_id.clone(),
                    peer: peer.into(),
                    target,
                },
            ),
            RemoteFsEvent::Write {
                peer,
                request,
                target_tx,
            } => {
                let expected_size = request.size;
                (
                    PendingRemoteFsResponder::Write {
                        target_tx,
                        expected_size,
                    },
                    RsServerEvent::RemoteFsWrite {
                        request_id: request_id.clone(),
                        peer: peer.into(),
                        request,
                    },
                )
            }
        };

        {
            let mut pending = self.pending_remote_fs.lock().await;
            prune_closed_remote_fs_responders(&mut pending);
            if pending.len() >= DEFAULT_MAX_CONCURRENT_REQUESTS {
                // Core applies the same limit before emitting an event. Keep a
                // defensive bridge-side bound in case configuration diverges.
                tracing::warn!("Rejecting remote filesystem request: responder limit reached");
                return true;
            }
            pending.insert(request_id.clone(), responder);
        }
        if sink.add(event).is_err() {
            self.pending_remote_fs.lock().await.remove(&request_id);
            false
        } else {
            true
        }
    }

    async fn prune_closed_remote_fs_responders(&self) {
        let mut pending = self.pending_remote_fs.lock().await;
        let removed = prune_closed_remote_fs_responders(&mut pending);
        if removed != 0 {
            tracing::debug!(removed, "Pruned ended remote filesystem requests");
        }
    }

    /// Answers the pending [RsServerEvent::PrepareUpload] event.
    ///
    /// Passing the accepted file IDs (a subset of the offered files) accepts the request.
    /// Passing `None` declines the request.
    pub async fn respond_prepare_upload(
        &self,
        accepted_file_ids: Option<Vec<String>>,
    ) -> anyhow::Result<()> {
        let Some((_, decision_tx)) = self.pending_decision.lock().await.take() else {
            return Err(anyhow::anyhow!("No pending prepare-upload request"));
        };

        let decision = match accepted_file_ids {
            Some(ids) => PrepareUploadDecisionV2::Accept(ids.into_iter().collect()),
            None => PrepareUploadDecisionV2::Decline,
        };

        decision_tx
            .send(decision)
            .map_err(|_| anyhow::anyhow!("Prepare-upload request already ended"))?;

        Ok(())
    }

    /// Answers the pending [RsServerEvent::FileUpload] event with the target
    /// the file should be saved to (either a path or a file descriptor)
    /// and waits until the file has been received completely.
    ///
    /// The progress (fraction of [file_size]) is emitted on [sink]
    /// while the file is being received. Failures are emitted on [sink] as
    /// well: flutter_rust_bridge discards the returned `Result` of functions
    /// taking a [StreamSink], so a returned error would become an uncaught
    /// async error killing the calling isolate.
    ///
    /// Timestamps provided in the sender's file metadata are applied to the
    /// written file by the server.
    pub async fn respond_file_upload(
        &self,
        sink: StreamSink<f64>,
        session_id: String,
        file_id: String,
        path: Option<String>,
        file_descriptor: Option<i32>,
        file_size: u64,
    ) {
        let result = async {
            let Some(target_tx) = self
                .pending_uploads
                .lock()
                .await
                .remove(&(session_id, file_id))
            else {
                return Err(anyhow::anyhow!("No pending file upload for this file"));
            };

            let (progress_tx, mut progress_rx) = mpsc::channel::<u64>(16);
            let progress_sink = sink.clone();
            tokio::spawn(async move {
                let mut last_emit = None::<std::time::Instant>;
                while let Some(written) = progress_rx.recv().await {
                    let now = std::time::Instant::now();
                    let is_final = written >= file_size;
                    if !is_final {
                        if let Some(last) = last_emit {
                            if now.duration_since(last) < std::time::Duration::from_millis(20) {
                                continue;
                            }
                        }
                    }
                    last_emit = Some(now);
                    let progress = if file_size == 0 {
                        1.0
                    } else {
                        (written as f64 / file_size as f64).min(1.0)
                    };
                    let _ = progress_sink.add(progress);
                }
            });

            let (result_tx, result_rx) = oneshot::channel::<Result<(), String>>();
            let target = resolve_upload_target(path, file_descriptor, result_tx, progress_tx)?;

            target_tx
                .send(target)
                .map_err(|_| anyhow::anyhow!("Upload request already ended"))?;

            match result_rx.await {
                Ok(Ok(())) => Ok(()),
                Ok(Err(err)) => Err(anyhow::anyhow!(err)),
                Err(_) => Err(anyhow::anyhow!("Upload request aborted")),
            }
        }
        .await;

        if let Err(err) = result {
            let _ = sink.add_error(err);
        }
    }

    /// Fails the pending [RsServerEvent::FileUpload] event, e.g. because
    /// the application failed to prepare a save target for the file.
    ///
    /// The upload request fails with an error response and the file is marked
    /// as failed. Does nothing if the upload was already answered.
    pub async fn fail_file_upload(&self, session_id: String, file_id: String) {
        // Dropping the responder fails the request waiting for the target.
        self.pending_uploads
            .lock()
            .await
            .remove(&(session_id, file_id));
    }

    /// Answers the pending [RsServerEvent::WebPrepareDownload] event.
    ///
    /// Passing `true` accepts the download request, `false` declines it.
    pub async fn respond_prepare_download(
        &self,
        session_id: String,
        accept: bool,
    ) -> anyhow::Result<()> {
        let Some(decision_tx) = self
            .pending_download_decisions
            .lock()
            .await
            .remove(&session_id)
        else {
            return Err(anyhow::anyhow!("No pending prepare-download request"));
        };

        decision_tx
            .send(accept)
            .map_err(|_| anyhow::anyhow!("Prepare-download request already ended"))?;

        Ok(())
    }

    /// Answers the pending [RsServerEvent::WebFileDownload] event with the source
    /// the file content should be read from (either a path or a file descriptor).
    ///
    /// The server reads the content and streams it to the web client.
    pub async fn respond_file_download(
        &self,
        session_id: String,
        file_id: String,
        path: Option<String>,
        file_descriptor: Option<i32>,
    ) -> anyhow::Result<()> {
        let Some(content_tx) = self
            .pending_downloads
            .lock()
            .await
            .remove(&(session_id, file_id))
        else {
            return Err(anyhow::anyhow!("No pending file download for this file"));
        };

        let content = resolve_file_content(path, file_descriptor)?;

        content_tx
            .send(content)
            .map_err(|_| anyhow::anyhow!("Download request already ended"))?;

        Ok(())
    }

    /// Fails the pending [RsServerEvent::WebFileDownload] event, e.g. because
    /// the application failed to resolve a source for the file content.
    ///
    /// The download request fails with an error response.
    /// Does nothing if the download was already answered.
    pub async fn fail_file_download(&self, session_id: String, file_id: String) {
        // Dropping the responder fails the request waiting for the content.
        self.pending_downloads
            .lock()
            .await
            .remove(&(session_id, file_id));
    }

    pub async fn respond_remote_fs_roots(
        &self,
        request_id: String,
        roots: Vec<RemoteFsRoot>,
    ) -> anyhow::Result<()> {
        let responder = self.take_remote_fs_responder(&request_id, "roots").await?;
        let PendingRemoteFsResponder::Roots(response_tx) = responder else {
            unreachable!();
        };
        response_tx
            .send(Ok(roots))
            .map_err(|_| anyhow::anyhow!("Remote filesystem request already ended"))
    }

    pub async fn respond_remote_fs_list(
        &self,
        request_id: String,
        response: RemoteFsListResponse,
    ) -> anyhow::Result<()> {
        let responder = self.take_remote_fs_responder(&request_id, "list").await?;
        let PendingRemoteFsResponder::List(response_tx) = responder else {
            unreachable!();
        };
        response_tx
            .send(Ok(response))
            .map_err(|_| anyhow::anyhow!("Remote filesystem request already ended"))
    }

    /// Answers metadata, create-directory, rename or move, all of which
    /// return one entry. The request ID preserves their concrete HTTP context.
    pub async fn respond_remote_fs_entry(
        &self,
        request_id: String,
        entry: RemoteFsEntry,
    ) -> anyhow::Result<()> {
        let responder = self.take_remote_fs_responder(&request_id, "entry").await?;
        let PendingRemoteFsResponder::Entry(response_tx) = responder else {
            unreachable!();
        };
        response_tx
            .send(Ok(entry))
            .map_err(|_| anyhow::anyhow!("Remote filesystem request already ended"))
    }

    pub async fn respond_remote_fs_delete(&self, request_id: String) -> anyhow::Result<()> {
        let responder = self.take_remote_fs_responder(&request_id, "delete").await?;
        let PendingRemoteFsResponder::Delete(response_tx) = responder else {
            unreachable!();
        };
        response_tx
            .send(Ok(()))
            .map_err(|_| anyhow::anyhow!("Remote filesystem request already ended"))
    }

    /// Supplies a path or owned Android file descriptor for an authenticated
    /// remote read. Core pulls it as a bounded stream and closes the descriptor.
    pub async fn respond_remote_fs_read(
        &self,
        request_id: String,
        entry: RemoteFsEntry,
        path: Option<String>,
        file_descriptor: Option<i32>,
    ) -> anyhow::Result<()> {
        let content = resolve_file_content(path, file_descriptor)?;
        let responder = self.take_remote_fs_responder(&request_id, "read").await?;
        let PendingRemoteFsResponder::Read(response_tx) = responder else {
            unreachable!();
        };
        response_tx
            .send(Ok(RemoteFsReadSource { entry, content }))
            .map_err(|_| anyhow::anyhow!("Remote filesystem request already ended"))
    }

    /// Supplies a path or owned Android file descriptor for an authenticated
    /// remote write and emits throttled progress plus its terminal result.
    pub async fn respond_remote_fs_write(
        &self,
        sink: StreamSink<RsRemoteFsWriteTargetEvent>,
        request_id: String,
        path: Option<String>,
        file_descriptor: Option<i32>,
    ) {
        let result = async {
            let responder = self.take_remote_fs_responder(&request_id, "write").await?;
            let PendingRemoteFsResponder::Write {
                target_tx,
                expected_size,
            } = responder
            else {
                unreachable!();
            };

            let (progress_tx, mut progress_rx) = mpsc::channel::<u64>(16);
            let (result_tx, mut result_rx) = oneshot::channel::<Result<(), String>>();
            let target = resolve_upload_target(path, file_descriptor, result_tx, progress_tx)?;
            target_tx
                .send(Ok(target))
                .map_err(|_| anyhow::anyhow!("Remote filesystem request already ended"))?;

            let mut last_emit = None::<std::time::Instant>;
            let write_result = loop {
                tokio::select! {
                    result = &mut result_rx => break result,
                    progress = progress_rx.recv() => {
                        let Some(bytes_written) = progress else {
                            break result_rx.await;
                        };
                        let now = std::time::Instant::now();
                        let is_final = bytes_written >= expected_size;
                        if !is_final
                            && last_emit.is_some_and(|last| {
                                now.duration_since(last) < std::time::Duration::from_millis(20)
                            })
                        {
                            continue;
                        }
                        last_emit = Some(now);
                        let _ = sink.add(RsRemoteFsWriteTargetEvent::Progress { bytes_written });
                    }
                }
            };
            while let Ok(bytes_written) = progress_rx.try_recv() {
                let _ = sink.add(RsRemoteFsWriteTargetEvent::Progress { bytes_written });
            }

            match write_result {
                Ok(Ok(())) => Ok(expected_size),
                Ok(Err(error)) => Err(anyhow::anyhow!(error)),
                Err(_) => Err(anyhow::anyhow!("Remote filesystem write aborted")),
            }
        }
        .await;

        match result {
            Ok(bytes_written) => {
                let _ = sink.add(RsRemoteFsWriteTargetEvent::Completed { bytes_written });
            }
            Err(error) => {
                let _ = sink.add(RsRemoteFsWriteTargetEvent::Failed {
                    error: error.to_string(),
                });
            }
        }
    }

    /// Rejects any pending remote-filesystem request with a stable public
    /// error. Provider exception text never crosses the HTTP boundary.
    pub async fn respond_remote_fs_error(
        &self,
        request_id: String,
        error: RemoteFsErrorCode,
    ) -> anyhow::Result<()> {
        let responder = self
            .pending_remote_fs
            .lock()
            .await
            .remove(&request_id)
            .ok_or_else(|| anyhow::anyhow!("No pending remote filesystem request"))?;
        let response_ended = match responder {
            PendingRemoteFsResponder::Roots(tx) => tx.send(Err(error)).is_err(),
            PendingRemoteFsResponder::List(tx) => tx.send(Err(error)).is_err(),
            PendingRemoteFsResponder::Entry(tx) => tx.send(Err(error)).is_err(),
            PendingRemoteFsResponder::Delete(tx) => tx.send(Err(error)).is_err(),
            PendingRemoteFsResponder::Read(tx) => tx.send(Err(error)).is_err(),
            PendingRemoteFsResponder::Write { target_tx, .. } => {
                target_tx.send(Err(error)).is_err()
            }
        };
        if response_ended {
            Err(anyhow::anyhow!("Remote filesystem request already ended"))
        } else {
            Ok(())
        }
    }

    async fn take_remote_fs_responder(
        &self,
        request_id: &str,
        expected_kind: &str,
    ) -> anyhow::Result<PendingRemoteFsResponder> {
        let mut pending = self.pending_remote_fs.lock().await;
        let Some(responder) = pending.get(request_id) else {
            return Err(anyhow::anyhow!("No pending remote filesystem request"));
        };
        let matches = matches!(
            (expected_kind, responder),
            ("roots", PendingRemoteFsResponder::Roots(_))
                | ("list", PendingRemoteFsResponder::List(_))
                | ("entry", PendingRemoteFsResponder::Entry(_))
                | ("delete", PendingRemoteFsResponder::Delete(_))
                | ("read", PendingRemoteFsResponder::Read(_))
                | ("write", PendingRemoteFsResponder::Write { .. })
        );
        if !matches {
            return Err(anyhow::anyhow!(
                "Wrong response type for remote filesystem request"
            ));
        }
        Ok(pending.remove(request_id).expect("checked above"))
    }

    /// Cancels the active upload session, e.g. because the user aborted the
    /// transfer on the receiving side.
    ///
    /// Uploads that are already in progress still run to completion, but new
    /// upload requests fail and a new session can be created.
    /// No [RsServerEvent::SessionEnd] is emitted: the application initiated
    /// the cancellation itself.
    pub async fn cancel_session(&self, session_id: String) {
        self.instance.handle.cancel_v2_session(&session_id).await;

        // Drop unanswered upload responders of this session so their requests
        // fail instead of waiting for a target forever.
        self.pending_uploads
            .lock()
            .await
            .retain(|(sid, _), _| sid != &session_id);
    }

    /// Stops the server.
    /// Returns after the listeners are closed, so the port can be bound again.
    pub async fn stop(&self) {
        self.instance.stop().await;

        let mut running_server = RUNNING_SERVER.lock().await;
        if running_server
            .as_ref()
            .is_some_and(|running| Arc::ptr_eq(running, &self.instance))
        {
            *running_server = None;
        }
    }
}

#[derive(Clone)]
pub enum RsRemoteFsWriteTargetEvent {
    Progress { bytes_written: u64 },
    Completed { bytes_written: u64 },
    Failed { error: String },
}

/// Receives the next event from an optional channel, or pends forever when the
/// channel is absent (i.e. that feature is disabled).
async fn recv_opt<T>(rx: &mut Option<mpsc::Receiver<T>>) -> Option<T> {
    match rx {
        Some(rx) => rx.recv().await,
        None => std::future::pending::<Option<T>>().await,
    }
}

fn resolve_upload_target(
    path: Option<String>,
    file_descriptor: Option<i32>,
    result_tx: oneshot::Sender<Result<(), String>>,
    progress_tx: mpsc::Sender<u64>,
) -> anyhow::Result<FileUploadTarget> {
    match (path, file_descriptor) {
        (Some(path), None) => Ok(FileUploadTarget::Path {
            path: path.into(),
            result_tx,
            progress_tx: Some(progress_tx),
        }),
        (None, Some(file_descriptor)) => {
            #[cfg(target_os = "android")]
            {
                Ok(FileUploadTarget::Fd {
                    fd: file_descriptor,
                    result_tx,
                    progress_tx: Some(progress_tx),
                })
            }
            #[cfg(not(target_os = "android"))]
            {
                let _ = (file_descriptor, result_tx, progress_tx);
                Err(anyhow::anyhow!(
                    "File descriptors are only supported on Android"
                ))
            }
        }
        _ => Err(anyhow::anyhow!(
            "Exactly one upload target must be provided"
        )),
    }
}

fn resolve_file_content(
    path: Option<String>,
    file_descriptor: Option<i32>,
) -> anyhow::Result<FileContent> {
    match (path, file_descriptor) {
        (Some(path), None) => Ok(FileContent::Path(path.into())),
        (None, Some(file_descriptor)) => {
            #[cfg(target_os = "android")]
            {
                Ok(FileContent::Fd(file_descriptor))
            }
            #[cfg(not(target_os = "android"))]
            {
                let _ = file_descriptor;
                Err(anyhow::anyhow!(
                    "File descriptors are only supported on Android"
                ))
            }
        }
        _ => Err(anyhow::anyhow!(
            "Exactly one download source must be provided"
        )),
    }
}

fn prune_closed_remote_fs_responders(
    pending: &mut HashMap<String, PendingRemoteFsResponder>,
) -> usize {
    let before = pending.len();
    pending.retain(|_, responder| !responder.is_closed());
    before - pending.len()
}

#[frb(mirror(WebI18n))]
pub struct _WebI18n {
    pub waiting: String,
    pub enter_pin: String,
    pub invalid_pin: String,
    pub too_many_attempts: String,
    pub rejected: String,
    pub upload_rejected: String,
    pub busy: String,
    pub files: String,
    pub file_name: String,
    pub size: String,
}

#[frb(mirror(TlsConfig))]
pub struct _TlsConfig {
    pub cert: String,
    pub private_key: String,
}

#[frb(mirror(RegisterDtoV2))]
pub struct _RegisterDtoV2 {
    pub alias: String,
    pub version: String,
    pub device_model: Option<String>,
    pub device_type: Option<DeviceType>,
    pub fingerprint: String,
    pub port: u16,
    pub protocol: ProtocolType,
    pub download: bool,
}

#[frb(mirror(SessionEndReasonV2))]
pub enum _SessionEndReasonV2 {
    Finished,
    Cancelled,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn timed_out_remote_fs_responders_are_pruned() {
        let (open_tx, open_rx) = oneshot::channel::<RemoteFsResult<Vec<RemoteFsRoot>>>();
        let (closed_tx, closed_rx) = oneshot::channel::<RemoteFsResult<Vec<RemoteFsRoot>>>();
        drop(closed_rx);

        let mut pending = HashMap::from([
            ("open".to_string(), PendingRemoteFsResponder::Roots(open_tx)),
            (
                "closed".to_string(),
                PendingRemoteFsResponder::Roots(closed_tx),
            ),
        ]);

        assert_eq!(prune_closed_remote_fs_responders(&mut pending), 1);
        assert!(pending.contains_key("open"));
        assert!(!pending.contains_key("closed"));
        drop(open_rx);
        assert_eq!(prune_closed_remote_fs_responders(&mut pending), 1);
        assert!(pending.is_empty());
    }
}
