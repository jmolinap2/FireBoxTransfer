#![cfg(feature = "http")]

use bytes::Bytes;
use localsend::http::client::{FireboxTransferClient, RemoteFsClientError};
use localsend::http::firebox::{
    RemoteFsCapability, RemoteFsCreateDirectoryRequest, RemoteFsDeleteRequest, RemoteFsEntry,
    RemoteFsEntryType, RemoteFsErrorCode, RemoteFsListRequest, RemoteFsListResponse,
    RemoteFsLocation, RemoteFsMoveRequest, RemoteFsRenameRequest, RemoteFsRoot,
};
use localsend::http::server::common::save::FileUploadTarget;
use localsend::http::server::firebox::{RemoteFsEvent, RemoteFsReadSource, RemoteFsServerConfig};
use localsend::http::server::web::{WebConfig, WebI18n};
use localsend::http::server::{start_with_port_and_firebox, TlsConfig};
use localsend::http::state::ClientInfo;
use localsend::model::transfer::FileContent;
use std::sync::atomic::{AtomicU16, Ordering};
use std::sync::Arc;
use tokio::sync::{mpsc, oneshot, Mutex};
use tokio_util::sync::CancellationToken;

struct Identity {
    cert: String,
    private_key: String,
    fingerprint: String,
}

fn generate_identity() -> Identity {
    let identity = localsend::crypto::cert::generate_self_signed().unwrap();
    Identity {
        cert: identity.certificate_pem,
        private_key: identity.private_key_pem,
        fingerprint: identity.fingerprint,
    }
}

fn free_port() -> u16 {
    static PORT_COUNTER: AtomicU16 = AtomicU16::new(45001);
    loop {
        let port = PORT_COUNTER.fetch_add(1, Ordering::SeqCst);
        if std::net::TcpListener::bind(("127.0.0.1", port)).is_ok() {
            return port;
        }
    }
}

fn entry(name: &str, path: &str, entry_type: RemoteFsEntryType) -> RemoteFsEntry {
    RemoteFsEntry {
        name: name.to_string(),
        path: path.to_string(),
        entry_type,
        size: (entry_type == RemoteFsEntryType::File).then_some(12),
        modified: Some("2026-08-12T00:00:00Z".to_string()),
        mime_type: (entry_type == RemoteFsEntryType::File)
            .then_some("application/octet-stream".to_string()),
        capabilities: vec![RemoteFsCapability::Read],
    }
}

fn root() -> RemoteFsRoot {
    RemoteFsRoot {
        id: "downloads".to_string(),
        display_name: "Downloads".to_string(),
        capabilities: vec![
            RemoteFsCapability::Browse,
            RemoteFsCapability::Read,
            RemoteFsCapability::Write,
            RemoteFsCapability::CreateDirectory,
            RemoteFsCapability::Rename,
            RemoteFsCapability::Move,
            RemoteFsCapability::Delete,
        ],
        total_bytes: Some(1_000_000),
        free_bytes: Some(750_000),
    }
}

struct TestServer {
    port: u16,
    _stop_tx: oneshot::Sender<()>,
}

async fn start_server(
    identity: &Identity,
    event_tx: mpsc::Sender<RemoteFsEvent>,
    web: Option<WebConfig>,
    max_write_size: u64,
) -> TestServer {
    let port = free_port();
    let (stop_tx, stop_rx) = oneshot::channel();
    start_with_port_and_firebox(
        port,
        TlsConfig {
            cert: identity.cert.clone(),
            private_key: identity.private_key.clone(),
        },
        ClientInfo {
            alias: "FireBox test server".to_string(),
            version: "2.2".to_string(),
            device_model: Some("Rust".to_string()),
            device_type: None,
            token: identity.fingerprint.clone(),
        },
        None,
        None,
        web,
        RemoteFsServerConfig::new(event_tx).with_max_write_size(max_write_size),
        stop_rx,
    )
    .await
    .unwrap();
    wait_until_reachable(port).await;
    TestServer {
        port,
        _stop_tx: stop_tx,
    }
}

async fn wait_until_reachable(port: u16) {
    for _ in 0..100 {
        if tokio::net::TcpStream::connect(("127.0.0.1", port))
            .await
            .is_ok()
        {
            return;
        }
        tokio::time::sleep(std::time::Duration::from_millis(20)).await;
    }
    panic!("server did not become reachable on {port}");
}

fn client(local: &Identity, remote: &Identity) -> FireboxTransferClient {
    FireboxTransferClient::try_new(
        &local.private_key,
        &local.cert,
        remote.fingerprint.clone(),
        Some(std::time::Duration::from_secs(5)),
    )
    .unwrap()
}

fn raw_authenticated_client(local: &Identity) -> localsend::reqwest::Client {
    let identity = localsend::reqwest::Identity::from_pem(
        format!("{}\n{}", local.cert, local.private_key).as_bytes(),
    )
    .unwrap();
    localsend::reqwest::Client::builder()
        .use_rustls_tls()
        .identity(identity)
        .danger_accept_invalid_certs(true)
        .build()
        .unwrap()
}

async fn assert_public_error(
    response: localsend::reqwest::Response,
    status: u16,
    code: RemoteFsErrorCode,
) {
    assert_eq!(response.status().as_u16(), status);
    let error = response
        .json::<localsend::http::firebox::RemoteFsErrorResponse>()
        .await
        .unwrap();
    assert_eq!(error.code, code);
    assert_eq!(error.message, code.safe_message());
}

#[tokio::test]
async fn complete_authenticated_filesystem_round_trip() {
    let _ = tracing_subscriber::fmt().with_test_writer().try_init();
    let server_identity = generate_identity();
    let client_identity = generate_identity();
    let expected_peer = client_identity.fingerprint.clone();
    let received_write = Arc::new(Mutex::new(Vec::new()));
    let deleted = Arc::new(Mutex::new(Vec::new()));
    let (event_tx, mut event_rx) = mpsc::channel(16);

    tokio::spawn({
        let received_write = received_write.clone();
        let deleted = deleted.clone();
        async move {
            while let Some(event) = event_rx.recv().await {
                let peer_fingerprint = match &event {
                    RemoteFsEvent::Roots { peer, .. }
                    | RemoteFsEvent::List { peer, .. }
                    | RemoteFsEvent::Metadata { peer, .. }
                    | RemoteFsEvent::CreateDirectory { peer, .. }
                    | RemoteFsEvent::Rename { peer, .. }
                    | RemoteFsEvent::Move { peer, .. }
                    | RemoteFsEvent::Delete { peer, .. }
                    | RemoteFsEvent::Read { peer, .. }
                    | RemoteFsEvent::Write { peer, .. } => &peer.certificate_fingerprint,
                };
                assert_eq!(peer_fingerprint, &expected_peer);

                match event {
                    RemoteFsEvent::Roots { response_tx, .. } => {
                        let _ = response_tx.send(Ok(vec![root()]));
                    }
                    RemoteFsEvent::List {
                        request,
                        response_tx,
                        ..
                    } => {
                        assert_eq!(request.location.path, "Music");
                        assert_eq!(request.limit, 50);
                        let _ = response_tx.send(Ok(RemoteFsListResponse {
                            entries: vec![entry(
                                "song.bin",
                                "Music/song.bin",
                                RemoteFsEntryType::File,
                            )],
                            next_cursor: Some("page-2".to_string()),
                        }));
                    }
                    RemoteFsEvent::Metadata {
                        target,
                        response_tx,
                        ..
                    } => {
                        let name = target.path.rsplit('/').next().unwrap();
                        let _ = response_tx.send(Ok(entry(
                            name,
                            &target.path,
                            RemoteFsEntryType::File,
                        )));
                    }
                    RemoteFsEvent::CreateDirectory {
                        request,
                        response_tx,
                        ..
                    } => {
                        let path = format!("{}/{}", request.parent.path, request.name);
                        let _ = response_tx.send(Ok(entry(
                            &request.name,
                            &path,
                            RemoteFsEntryType::Directory,
                        )));
                    }
                    RemoteFsEvent::Rename {
                        request,
                        response_tx,
                        ..
                    } => {
                        let _ = response_tx.send(Ok(entry(
                            &request.new_name,
                            &format!("Music/{}", request.new_name),
                            RemoteFsEntryType::File,
                        )));
                    }
                    RemoteFsEvent::Move {
                        request,
                        response_tx,
                        ..
                    } => {
                        let name = request.new_name.as_deref().unwrap_or("renamed.bin");
                        let path = format!("{}/{}", request.destination_parent.path, name);
                        let _ = response_tx.send(Ok(entry(name, &path, RemoteFsEntryType::File)));
                    }
                    RemoteFsEvent::Delete {
                        request,
                        response_tx,
                        ..
                    } => {
                        deleted.lock().await.push(request.target.path);
                        let _ = response_tx.send(Ok(()));
                    }
                    RemoteFsEvent::Read {
                        target,
                        response_tx,
                        ..
                    } => {
                        let (tx, rx) = mpsc::channel(2);
                        tx.send(Bytes::from_static(b"hello world!")).await.unwrap();
                        drop(tx);
                        let _ = response_tx.send(Ok(RemoteFsReadSource {
                            entry: entry(
                                target.path.rsplit('/').next().unwrap(),
                                &target.path,
                                RemoteFsEntryType::File,
                            ),
                            content: FileContent::Stream(rx),
                        }));
                    }
                    RemoteFsEvent::Write {
                        request, target_tx, ..
                    } => {
                        assert_eq!(request.target.path, "Music/upload.bin");
                        assert_eq!(request.size, 12);
                        assert!(request.overwrite);
                        let (binary_tx, mut binary_rx) = mpsc::channel(4);
                        let (result_tx, result_rx) = oneshot::channel();
                        let _ = target_tx.send(Ok(FileUploadTarget::Stream {
                            binary_tx,
                            result_rx,
                        }));
                        let received_write = received_write.clone();
                        tokio::spawn(async move {
                            let mut content = Vec::new();
                            while let Some(chunk) = binary_rx.recv().await {
                                content.extend_from_slice(&chunk);
                            }
                            *received_write.lock().await = content;
                            let _ = result_tx.send(Ok(()));
                        });
                    }
                }
            }
        }
    });

    let server = start_server(&server_identity, event_tx, None, 1024).await;
    let client = client(&client_identity, &server_identity);

    let roots = client.roots("127.0.0.1", server.port).await.unwrap();
    assert_eq!(roots, vec![root()]);

    let mut list_request =
        RemoteFsListRequest::new(RemoteFsLocation::new("downloads", "Music").unwrap());
    list_request.limit = 50;
    let listed = client
        .list("127.0.0.1", server.port, list_request)
        .await
        .unwrap();
    assert_eq!(listed.entries[0].path, "Music/song.bin");
    assert_eq!(listed.next_cursor.as_deref(), Some("page-2"));

    let song = RemoteFsLocation::new("downloads", "Music/song.bin").unwrap();
    assert_eq!(
        client
            .metadata("127.0.0.1", server.port, &song)
            .await
            .unwrap()
            .name,
        "song.bin"
    );

    let created = client
        .create_directory(
            "127.0.0.1",
            server.port,
            &RemoteFsCreateDirectoryRequest {
                parent: RemoteFsLocation::new("downloads", "Music").unwrap(),
                name: "Albums".to_string(),
            },
        )
        .await
        .unwrap();
    assert_eq!(created.path, "Music/Albums");

    let renamed = client
        .rename(
            "127.0.0.1",
            server.port,
            &RemoteFsRenameRequest {
                source: song.clone(),
                new_name: "renamed.bin".to_string(),
            },
        )
        .await
        .unwrap();
    assert_eq!(renamed.path, "Music/renamed.bin");

    let moved = client
        .move_entry(
            "127.0.0.1",
            server.port,
            &RemoteFsMoveRequest {
                source: RemoteFsLocation::new("downloads", "Music/renamed.bin").unwrap(),
                destination_parent: RemoteFsLocation::new("downloads", "Archive").unwrap(),
                new_name: None,
                overwrite: false,
            },
        )
        .await
        .unwrap();
    assert_eq!(moved.path, "Archive/renamed.bin");

    client
        .delete(
            "127.0.0.1",
            server.port,
            &RemoteFsDeleteRequest {
                target: RemoteFsLocation::new("downloads", "Archive/renamed.bin").unwrap(),
                recursive: false,
            },
        )
        .await
        .unwrap();
    assert_eq!(&*deleted.lock().await, &["Archive/renamed.bin"]);

    let mut downloaded = Vec::new();
    let bytes = client
        .read_to_writer(
            "127.0.0.1",
            server.port,
            &song,
            &mut downloaded,
            |_| {},
            CancellationToken::new(),
        )
        .await
        .unwrap();
    assert_eq!(bytes, 12);
    assert_eq!(downloaded, b"hello world!");

    let upload_location = RemoteFsLocation::new("downloads", "Music/upload.bin").unwrap();
    let (content_tx, content_rx) = mpsc::channel(2);
    content_tx
        .send(Bytes::from_static(b"new content!"))
        .await
        .unwrap();
    drop(content_tx);
    let response = client
        .write(
            "127.0.0.1",
            server.port,
            &upload_location,
            12,
            true,
            FileContent::Stream(content_rx),
            |_| {},
            CancellationToken::new(),
        )
        .await
        .unwrap();
    assert_eq!(response.bytes_written, 12);
    assert_eq!(&*received_write.lock().await, b"new content!");
}

#[tokio::test]
async fn trust_decision_maps_to_safe_public_error() {
    let server_identity = generate_identity();
    let client_identity = generate_identity();
    let (event_tx, mut event_rx) = mpsc::channel(1);
    tokio::spawn(async move {
        if let Some(RemoteFsEvent::Roots { response_tx, .. }) = event_rx.recv().await {
            let _ = response_tx.send(Err(RemoteFsErrorCode::UntrustedDevice));
        }
    });
    let server = start_server(&server_identity, event_tx, None, 1024).await;
    let error = client(&client_identity, &server_identity)
        .roots("127.0.0.1", server.port)
        .await
        .unwrap_err();
    match error {
        RemoteFsClientError::Remote { status, error } => {
            assert_eq!(status, 403);
            assert_eq!(error.code, RemoteFsErrorCode::UntrustedDevice);
            assert_eq!(error.message, "This device is not trusted.");
        }
        error => panic!("unexpected error: {error:?}"),
    }
}

#[tokio::test]
async fn browser_without_client_certificate_cannot_access_api_even_in_web_mode() {
    let server_identity = generate_identity();
    let (event_tx, mut event_rx) = mpsc::channel(1);
    let server = start_server(
        &server_identity,
        event_tx,
        Some(WebConfig {
            send: None,
            upload: true,
            i18n: WebI18n::default(),
        }),
        1024,
    )
    .await;

    let browser = localsend::reqwest::Client::builder()
        .use_rustls_tls()
        .danger_accept_invalid_certs(true)
        .build()
        .unwrap();
    let response = browser
        .get(format!(
            "https://127.0.0.1:{}/api/fireboxtransfer/v1/roots",
            server.port
        ))
        .send()
        .await
        .unwrap();
    assert_eq!(response.status(), 401);
    let error = response
        .json::<localsend::http::firebox::RemoteFsErrorResponse>()
        .await
        .unwrap();
    assert_eq!(error.code, RemoteFsErrorCode::Unauthenticated);
    assert!(
        event_rx.try_recv().is_err(),
        "unauthenticated requests must not emit events"
    );
}

#[tokio::test]
async fn write_larger_than_limit_is_rejected_before_application_event() {
    let server_identity = generate_identity();
    let client_identity = generate_identity();
    let (event_tx, mut event_rx) = mpsc::channel(1);
    let server = start_server(&server_identity, event_tx, None, 4).await;
    let (content_tx, content_rx) = mpsc::channel(1);
    content_tx.send(Bytes::from_static(b"12345")).await.unwrap();
    drop(content_tx);
    let error = client(&client_identity, &server_identity)
        .write(
            "127.0.0.1",
            server.port,
            &RemoteFsLocation::new("downloads", "too-large.bin").unwrap(),
            5,
            false,
            FileContent::Stream(content_rx),
            |_| {},
            CancellationToken::new(),
        )
        .await
        .unwrap_err();
    match error {
        RemoteFsClientError::Remote { status, error } => {
            assert_eq!(status, 413);
            assert_eq!(error.code, RemoteFsErrorCode::PayloadTooLarge);
        }
        error => panic!("unexpected error: {error:?}"),
    }
    assert!(event_rx.try_recv().is_err());
}

#[tokio::test]
async fn mismatching_server_certificate_is_rejected_before_event() {
    let server_identity = generate_identity();
    let client_identity = generate_identity();
    let other_server = generate_identity();
    let (event_tx, mut event_rx) = mpsc::channel(1);
    let server = start_server(&server_identity, event_tx, None, 1024).await;
    let wrong_client = client(&client_identity, &other_server);
    let error = wrong_client
        .roots("127.0.0.1", server.port)
        .await
        .unwrap_err();
    assert!(matches!(error, RemoteFsClientError::Reqwest(_)));
    assert!(event_rx.try_recv().is_err());
}

#[tokio::test]
async fn traversal_and_root_mutations_are_rejected_before_provider_dispatch() {
    let server_identity = generate_identity();
    let client_identity = generate_identity();
    let (event_tx, mut event_rx) = mpsc::channel(8);
    let server = start_server(&server_identity, event_tx, None, 1024).await;
    let client = raw_authenticated_client(&client_identity);
    let base = format!("https://127.0.0.1:{}/api/fireboxtransfer/v1", server.port);

    // Query decoding happens before validation, so an encoded traversal must
    // be rejected just like a literal one.
    assert_public_error(
        client
            .get(format!(
                "{base}/files?rootId=downloads&path=..%2Fprivate&limit=10"
            ))
            .send()
            .await
            .unwrap(),
        400,
        RemoteFsErrorCode::InvalidPath,
    )
    .await;

    // The empty relative path names the grant root. It may be listed and may
    // receive children, but it cannot itself be renamed, moved or deleted.
    assert_public_error(
        client
            .post(format!("{base}/files/rename"))
            .json(&serde_json::json!({
                "source": { "rootId": "downloads", "path": "" },
                "newName": "renamed"
            }))
            .send()
            .await
            .unwrap(),
        400,
        RemoteFsErrorCode::InvalidPath,
    )
    .await;
    assert_public_error(
        client
            .post(format!("{base}/files/move"))
            .json(&serde_json::json!({
                "source": { "rootId": "downloads", "path": "" },
                "destinationParent": { "rootId": "downloads", "path": "Archive" },
                "overwrite": false
            }))
            .send()
            .await
            .unwrap(),
        400,
        RemoteFsErrorCode::InvalidPath,
    )
    .await;
    assert_public_error(
        client
            .delete(format!("{base}/files?rootId=downloads&path="))
            .send()
            .await
            .unwrap(),
        400,
        RemoteFsErrorCode::InvalidPath,
    )
    .await;

    assert!(
        event_rx.try_recv().is_err(),
        "invalid paths and root mutations must not reach the provider"
    );
}
