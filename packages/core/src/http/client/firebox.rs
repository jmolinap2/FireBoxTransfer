//! Pinned-mTLS client for the FireBoxTransfer remote-filesystem API.

use super::scoped_host;
use super::ClientError;
use crate::http::firebox::{
    validate_entry, validate_file_name, validate_root, RemoteFsCreateDirectoryRequest,
    RemoteFsDeleteRequest, RemoteFsEntry, RemoteFsErrorCode, RemoteFsErrorResponse,
    RemoteFsListRequest, RemoteFsListResponse, RemoteFsLocation, RemoteFsMoveRequest,
    RemoteFsMutationResponse, RemoteFsRenameRequest, RemoteFsRoot, RemoteFsRootsResponse,
    RemoteFsWriteResponse, FIREBOX_API_BASE,
};
use crate::model::transfer::FileContent;
use bytes::BytesMut;
use futures_util::StreamExt;
use reqwest::{Method, Response, StatusCode};
use serde::de::DeserializeOwned;
use std::borrow::Cow;
use std::collections::HashSet;
use tokio::io::AsyncWriteExt;
use tokio_util::sync::CancellationToken;

const MAX_JSON_RESPONSE_SIZE: usize = 8 * 1024 * 1024;
const MAX_ERROR_RESPONSE_SIZE: usize = 64 * 1024;

#[derive(Debug, thiserror::Error)]
pub enum RemoteFsClientError {
    #[error("failed to configure the authenticated HTTP client: {0}")]
    Setup(#[source] ClientError),

    #[error("remote filesystem request failed with HTTP {status}: {error:?}")]
    Remote {
        status: u16,
        error: RemoteFsErrorResponse,
    },

    #[error(transparent)]
    Reqwest(#[from] reqwest::Error),

    #[error(transparent)]
    Json(#[from] serde_json::Error),

    #[error(transparent)]
    Io(#[from] std::io::Error),

    #[error("invalid remote filesystem request: {0:?}")]
    InvalidRequest(RemoteFsErrorCode),

    #[error("the remote filesystem response violated the protocol")]
    InvalidResponse,

    #[error("remote filesystem request cancelled")]
    Cancelled,
}

/// A client that always uses HTTPS, presents the local device certificate and
/// pins the server certificate fingerprint during the TLS handshake.
pub struct FireboxTransferClient {
    client: reqwest::Client,
}

impl FireboxTransferClient {
    pub fn try_new(
        private_key: &str,
        cert: &str,
        expected_server_fingerprint: String,
        timeout: Option<std::time::Duration>,
    ) -> Result<Self, RemoteFsClientError> {
        if !is_certificate_fingerprint(&expected_server_fingerprint) {
            return Err(RemoteFsClientError::InvalidRequest(
                RemoteFsErrorCode::InvalidRequest,
            ));
        }
        let client = super::create_reqwest_client(
            private_key,
            cert,
            Some(expected_server_fingerprint),
            timeout,
        )
        .map_err(RemoteFsClientError::Setup)?;
        Ok(Self { client })
    }

    pub async fn roots(
        &self,
        host: &str,
        port: u16,
    ) -> Result<Vec<RemoteFsRoot>, RemoteFsClientError> {
        let response = self
            .client
            .get(endpoint_url(host, port, "/roots", &[]))
            .send()
            .await?;
        let response: RemoteFsRootsResponse = parse_json_response(response).await?;
        if response.roots.len() > 256 {
            return Err(RemoteFsClientError::InvalidResponse);
        }
        let mut ids = HashSet::with_capacity(response.roots.len());
        for root in &response.roots {
            validate_root(root).map_err(|_| RemoteFsClientError::InvalidResponse)?;
            if !ids.insert(root.id.as_str()) {
                return Err(RemoteFsClientError::InvalidResponse);
            }
        }
        Ok(response.roots)
    }

    pub async fn list(
        &self,
        host: &str,
        port: u16,
        request: RemoteFsListRequest,
    ) -> Result<RemoteFsListResponse, RemoteFsClientError> {
        request
            .validate()
            .map_err(RemoteFsClientError::InvalidRequest)?;
        let limit = request.limit.to_string();
        let mut params = vec![
            ("rootId", request.location.root_id.as_str()),
            ("path", request.location.path.as_str()),
            ("limit", limit.as_str()),
        ];
        if let Some(cursor) = request.cursor.as_deref() {
            params.push(("cursor", cursor));
        }
        let response = self
            .client
            .get(endpoint_url(host, port, "/files", &params))
            .send()
            .await?;
        let response: RemoteFsListResponse = parse_json_response(response).await?;
        if response.entries.len() > request.limit as usize
            || response.next_cursor.as_ref().is_some_and(|cursor| {
                cursor.is_empty() || cursor.len() > 1_024 || cursor.chars().any(char::is_control)
            })
        {
            return Err(RemoteFsClientError::InvalidResponse);
        }
        let mut paths = HashSet::with_capacity(response.entries.len());
        for entry in &response.entries {
            validate_entry(entry, Some(&request.location.path))
                .map_err(|_| RemoteFsClientError::InvalidResponse)?;
            if !paths.insert(entry.path.as_str()) {
                return Err(RemoteFsClientError::InvalidResponse);
            }
        }
        Ok(response)
    }

    pub async fn metadata(
        &self,
        host: &str,
        port: u16,
        target: &RemoteFsLocation,
    ) -> Result<RemoteFsEntry, RemoteFsClientError> {
        validate_entry_location(target)?;
        let response = self
            .client
            .get(endpoint_url(
                host,
                port,
                "/files/metadata",
                &[
                    ("rootId", target.root_id.as_str()),
                    ("path", target.path.as_str()),
                ],
            ))
            .send()
            .await?;
        let entry: RemoteFsEntry = parse_json_response(response).await?;
        validate_exact_response_entry(&entry, &target.path)?;
        Ok(entry)
    }

    pub async fn create_directory(
        &self,
        host: &str,
        port: u16,
        request: &RemoteFsCreateDirectoryRequest,
    ) -> Result<RemoteFsEntry, RemoteFsClientError> {
        request
            .parent
            .validate()
            .map_err(RemoteFsClientError::InvalidRequest)?;
        validate_file_name(&request.name).map_err(RemoteFsClientError::InvalidRequest)?;
        let expected_path = child_path(&request.parent.path, &request.name);
        let response = self
            .client
            .post(endpoint_url(host, port, "/files/directory", &[]))
            .json(request)
            .send()
            .await?;
        parse_mutation_response(response, &expected_path).await
    }

    pub async fn rename(
        &self,
        host: &str,
        port: u16,
        request: &RemoteFsRenameRequest,
    ) -> Result<RemoteFsEntry, RemoteFsClientError> {
        validate_entry_location(&request.source)?;
        validate_file_name(&request.new_name).map_err(RemoteFsClientError::InvalidRequest)?;
        let expected_path = child_path(parent_path(&request.source.path), &request.new_name);
        let response = self
            .client
            .post(endpoint_url(host, port, "/files/rename", &[]))
            .json(request)
            .send()
            .await?;
        parse_mutation_response(response, &expected_path).await
    }

    pub async fn move_entry(
        &self,
        host: &str,
        port: u16,
        request: &RemoteFsMoveRequest,
    ) -> Result<RemoteFsEntry, RemoteFsClientError> {
        validate_entry_location(&request.source)?;
        request
            .destination_parent
            .validate()
            .map_err(RemoteFsClientError::InvalidRequest)?;
        if let Some(name) = &request.new_name {
            validate_file_name(name).map_err(RemoteFsClientError::InvalidRequest)?;
        }
        let source_name = request.source.path.rsplit('/').next().unwrap_or_default();
        let expected_path = child_path(
            &request.destination_parent.path,
            request.new_name.as_deref().unwrap_or(source_name),
        );
        let response = self
            .client
            .post(endpoint_url(host, port, "/files/move", &[]))
            .json(request)
            .send()
            .await?;
        parse_mutation_response(response, &expected_path).await
    }

    pub async fn delete(
        &self,
        host: &str,
        port: u16,
        request: &RemoteFsDeleteRequest,
    ) -> Result<(), RemoteFsClientError> {
        validate_entry_location(&request.target)?;
        let recursive = request.recursive.to_string();
        let response = self
            .client
            .delete(endpoint_url(
                host,
                port,
                "/files",
                &[
                    ("rootId", request.target.root_id.as_str()),
                    ("path", request.target.path.as_str()),
                    ("recursive", recursive.as_str()),
                ],
            ))
            .send()
            .await?;
        parse_empty_response(response, StatusCode::NO_CONTENT).await
    }

    /// Opens a streaming response for a remote file.
    pub async fn read(
        &self,
        host: &str,
        port: u16,
        target: &RemoteFsLocation,
    ) -> Result<Response, RemoteFsClientError> {
        validate_entry_location(target)?;
        let response = self
            .client
            .get(endpoint_url(
                host,
                port,
                "/files/content",
                &[
                    ("rootId", target.root_id.as_str()),
                    ("path", target.path.as_str()),
                ],
            ))
            .send()
            .await?;
        ensure_success(response).await
    }

    pub async fn read_to_writer<W: tokio::io::AsyncWrite + Unpin>(
        &self,
        host: &str,
        port: u16,
        target: &RemoteFsLocation,
        writer: &mut W,
        progress: impl Fn(u64),
        cancel: CancellationToken,
    ) -> Result<u64, RemoteFsClientError> {
        let response = self.read(host, port, target).await?;
        let expected_size = response.content_length();
        let mut stream = response.bytes_stream();
        let mut written = 0_u64;
        loop {
            let next = tokio::select! {
                next = stream.next() => next,
                _ = cancel.cancelled() => return Err(RemoteFsClientError::Cancelled),
            };
            let Some(chunk) = next else {
                break;
            };
            let chunk = chunk?;
            writer.write_all(&chunk).await?;
            written = written.saturating_add(chunk.len() as u64);
            progress(written);
        }
        writer.flush().await?;
        if expected_size.is_some_and(|expected| expected != written) {
            return Err(RemoteFsClientError::InvalidResponse);
        }
        Ok(written)
    }

    #[allow(clippy::too_many_arguments)]
    pub async fn write(
        &self,
        host: &str,
        port: u16,
        target: &RemoteFsLocation,
        size: u64,
        overwrite: bool,
        content: FileContent,
        progress: impl Fn(u64) + Send + 'static,
        cancel: CancellationToken,
    ) -> Result<RemoteFsWriteResponse, RemoteFsClientError> {
        validate_entry_location(target)?;
        let overwrite = overwrite.to_string();
        let body = super::upload_body(content, progress);
        let send = self
            .client
            .request(
                Method::PUT,
                endpoint_url(
                    host,
                    port,
                    "/files/content",
                    &[
                        ("rootId", target.root_id.as_str()),
                        ("path", target.path.as_str()),
                        ("overwrite", overwrite.as_str()),
                    ],
                ),
            )
            .header(reqwest::header::CONTENT_TYPE, "application/octet-stream")
            .header(reqwest::header::CONTENT_LENGTH, size)
            .body(body)
            .send();
        let response = tokio::select! {
            response = send => response?,
            _ = cancel.cancelled() => return Err(RemoteFsClientError::Cancelled),
        };
        let response: RemoteFsWriteResponse = parse_json_response(response).await?;
        if response.bytes_written != size {
            return Err(RemoteFsClientError::InvalidResponse);
        }
        Ok(response)
    }
}

async fn parse_mutation_response(
    response: Response,
    expected_path: &str,
) -> Result<RemoteFsEntry, RemoteFsClientError> {
    let response: RemoteFsMutationResponse = parse_json_response(response).await?;
    validate_exact_response_entry(&response.entry, expected_path)?;
    Ok(response.entry)
}

async fn parse_json_response<T: DeserializeOwned>(
    response: Response,
) -> Result<T, RemoteFsClientError> {
    let response = ensure_success(response).await?;
    let body = collect_bounded_body(response, MAX_JSON_RESPONSE_SIZE).await?;
    Ok(serde_json::from_slice::<T>(&body)?)
}

async fn parse_empty_response(
    response: Response,
    expected: StatusCode,
) -> Result<(), RemoteFsClientError> {
    if response.status() == expected {
        return Ok(());
    }
    let response = ensure_success(response).await?;
    if response.status() != expected {
        return Err(RemoteFsClientError::InvalidResponse);
    }
    Ok(())
}

async fn ensure_success(response: Response) -> Result<Response, RemoteFsClientError> {
    if response.status().is_success() {
        return Ok(response);
    }
    let status = response.status().as_u16();
    let error = match collect_bounded_body(response, MAX_ERROR_RESPONSE_SIZE).await {
        Ok(body) => serde_json::from_slice::<RemoteFsErrorResponse>(&body)
            .unwrap_or_else(|_| RemoteFsErrorResponse::from(RemoteFsErrorCode::Internal)),
        Err(_) => RemoteFsErrorResponse::from(RemoteFsErrorCode::Internal),
    };
    Err(RemoteFsClientError::Remote { status, error })
}

async fn collect_bounded_body(
    response: Response,
    max_size: usize,
) -> Result<BytesMut, RemoteFsClientError> {
    if response
        .content_length()
        .is_some_and(|length| length > max_size as u64)
    {
        return Err(RemoteFsClientError::InvalidResponse);
    }
    let initial_capacity = response
        .content_length()
        .and_then(|length| usize::try_from(length).ok())
        .unwrap_or(8 * 1024)
        .min(max_size);
    let mut body = BytesMut::with_capacity(initial_capacity);
    let mut stream = response.bytes_stream();
    while let Some(chunk) = stream.next().await {
        append_bounded(&mut body, &chunk?, max_size)?;
    }
    Ok(body)
}

fn append_bounded(
    body: &mut BytesMut,
    chunk: &[u8],
    max_size: usize,
) -> Result<(), RemoteFsClientError> {
    if body.len().saturating_add(chunk.len()) > max_size {
        return Err(RemoteFsClientError::InvalidResponse);
    }
    body.extend_from_slice(chunk);
    Ok(())
}

fn validate_entry_location(location: &RemoteFsLocation) -> Result<(), RemoteFsClientError> {
    location
        .validate()
        .map_err(RemoteFsClientError::InvalidRequest)?;
    if location.path.is_empty() {
        return Err(RemoteFsClientError::InvalidRequest(
            RemoteFsErrorCode::InvalidPath,
        ));
    }
    Ok(())
}

fn validate_exact_response_entry(
    entry: &RemoteFsEntry,
    expected_path: &str,
) -> Result<(), RemoteFsClientError> {
    validate_entry(entry, None).map_err(|_| RemoteFsClientError::InvalidResponse)?;
    if entry.path != expected_path {
        return Err(RemoteFsClientError::InvalidResponse);
    }
    Ok(())
}

fn is_certificate_fingerprint(value: &str) -> bool {
    value.len() == 64 && value.bytes().all(|byte| byte.is_ascii_hexdigit())
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

fn endpoint_url(host: &str, port: u16, path: &str, params: &[(&str, &str)]) -> String {
    let host = match scoped_host::encode(host) {
        Some(encoded) => Cow::Owned(encoded),
        None if host.contains(':') => Cow::Owned(format!("[{host}]")),
        None => Cow::Borrowed(host),
    };
    let mut url = format!("https://{host}:{port}{FIREBOX_API_BASE}{path}");
    if !params.is_empty() {
        let query: String = form_urlencoded::Serializer::new(String::new())
            .extend_pairs(params.iter().copied())
            .finish();
        url.push('?');
        url.push_str(&query);
    }
    url
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn builds_encoded_ipv4_url() {
        assert_eq!(
            endpoint_url(
                "192.168.1.2",
                53317,
                "/files",
                &[("rootId", "downloads"), ("path", "Music/A & B")],
            ),
            "https://192.168.1.2:53317/api/fireboxtransfer/v1/files?rootId=downloads&path=Music%2FA+%26+B"
        );
    }

    #[test]
    fn requires_a_real_fingerprint_shape() {
        assert!(is_certificate_fingerprint(&"A".repeat(64)));
        assert!(is_certificate_fingerprint(&"a1".repeat(32)));
        assert!(!is_certificate_fingerprint("server"));
        assert!(!is_certificate_fingerprint(&"G".repeat(64)));
    }

    #[test]
    fn response_body_limit_is_enforced_across_chunks() {
        let mut body = BytesMut::new();
        append_bounded(&mut body, b"123", 5).unwrap();
        append_bounded(&mut body, b"45", 5).unwrap();
        assert_eq!(&body[..], b"12345");
        assert!(matches!(
            append_bounded(&mut body, b"6", 5),
            Err(RemoteFsClientError::InvalidResponse)
        ));
    }
}
