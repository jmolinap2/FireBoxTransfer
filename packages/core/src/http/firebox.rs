//! Shared wire models for the FireBoxTransfer remote-filesystem API.
//!
//! The protocol deliberately addresses files by an opaque root ID plus a
//! normalized relative path. Native paths and Android SAF URIs never cross the
//! network boundary.

use serde::{Deserialize, Serialize};

pub const FIREBOX_API_BASE: &str = "/api/fireboxtransfer/v1";
pub const DEFAULT_LIST_LIMIT: u16 = 200;
pub const MAX_LIST_LIMIT: u16 = 1_000;

const MAX_ROOT_ID_BYTES: usize = 128;
const MAX_PATH_BYTES: usize = 4_096;
const MAX_NAME_BYTES: usize = 1_024;
const MAX_CURSOR_BYTES: usize = 1_024;

#[derive(Clone, Copy, Debug, Deserialize, Eq, Hash, PartialEq, Serialize)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum RemoteFsCapability {
    Browse,
    Read,
    Write,
    CreateDirectory,
    Rename,
    Move,
    Delete,
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum RemoteFsEntryType {
    File,
    Directory,
    Other,
}

/// A server-local grant. `id` is an opaque handle, never a filesystem path or
/// an Android document URI.
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RemoteFsRoot {
    pub id: String,
    pub display_name: String,
    pub capabilities: Vec<RemoteFsCapability>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub total_bytes: Option<u64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub free_bytes: Option<u64>,
}

/// A location below an authorized root. The empty path means the root itself.
#[derive(Clone, Debug, Deserialize, Eq, Hash, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RemoteFsLocation {
    pub root_id: String,
    #[serde(default)]
    pub path: String,
}

impl RemoteFsLocation {
    pub fn new(
        root_id: impl Into<String>,
        path: impl Into<String>,
    ) -> Result<Self, RemoteFsErrorCode> {
        let location = Self {
            root_id: root_id.into(),
            path: path.into(),
        };
        location.validate()?;
        Ok(location)
    }

    pub fn validate(&self) -> Result<(), RemoteFsErrorCode> {
        validate_root_id(&self.root_id)?;
        validate_relative_path(&self.path)
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RemoteFsEntry {
    pub name: String,
    /// Normalized path relative to the root that produced this entry.
    pub path: String,
    pub entry_type: RemoteFsEntryType,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub size: Option<u64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub modified: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub mime_type: Option<String>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub capabilities: Vec<RemoteFsCapability>,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RemoteFsRootsResponse {
    pub roots: Vec<RemoteFsRoot>,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RemoteFsListRequest {
    pub location: RemoteFsLocation,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub cursor: Option<String>,
    pub limit: u16,
}

impl RemoteFsListRequest {
    pub fn new(location: RemoteFsLocation) -> Self {
        Self {
            location,
            cursor: None,
            limit: DEFAULT_LIST_LIMIT,
        }
    }

    pub fn validate(&self) -> Result<(), RemoteFsErrorCode> {
        self.location.validate()?;
        if !(1..=MAX_LIST_LIMIT).contains(&self.limit) {
            return Err(RemoteFsErrorCode::InvalidRequest);
        }
        if let Some(cursor) = &self.cursor {
            if cursor.is_empty()
                || cursor.len() > MAX_CURSOR_BYTES
                || cursor.chars().any(char::is_control)
            {
                return Err(RemoteFsErrorCode::InvalidRequest);
            }
        }
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RemoteFsListResponse {
    pub entries: Vec<RemoteFsEntry>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub next_cursor: Option<String>,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RemoteFsCreateDirectoryRequest {
    pub parent: RemoteFsLocation,
    pub name: String,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RemoteFsRenameRequest {
    pub source: RemoteFsLocation,
    pub new_name: String,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RemoteFsMoveRequest {
    pub source: RemoteFsLocation,
    pub destination_parent: RemoteFsLocation,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub new_name: Option<String>,
    #[serde(default)]
    pub overwrite: bool,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RemoteFsDeleteRequest {
    pub target: RemoteFsLocation,
    #[serde(default)]
    pub recursive: bool,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RemoteFsWriteRequest {
    pub target: RemoteFsLocation,
    pub size: u64,
    #[serde(default)]
    pub overwrite: bool,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RemoteFsMutationResponse {
    pub entry: RemoteFsEntry,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RemoteFsWriteResponse {
    pub bytes_written: u64,
}

/// Stable, localizable error codes. The server emits a fixed safe message for
/// each code and never returns provider exception strings or native paths.
#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum RemoteFsErrorCode {
    Unauthenticated,
    UntrustedDevice,
    PermissionDenied,
    InvalidRequest,
    InvalidPath,
    InvalidName,
    RootNotFound,
    NotFound,
    AlreadyExists,
    NotDirectory,
    IsDirectory,
    DirectoryNotEmpty,
    Conflict,
    ReadOnly,
    StorageFull,
    PayloadTooLarge,
    Unsupported,
    Busy,
    TransferFailed,
    Unavailable,
    Internal,
}

impl RemoteFsErrorCode {
    pub fn safe_message(self) -> &'static str {
        match self {
            Self::Unauthenticated => "A verified client certificate is required.",
            Self::UntrustedDevice => "This device is not trusted.",
            Self::PermissionDenied => "This operation is not permitted.",
            Self::InvalidRequest => "The request is invalid.",
            Self::InvalidPath => "The relative path is invalid.",
            Self::InvalidName => "The file name is invalid.",
            Self::RootNotFound => "The authorized root is not available.",
            Self::NotFound => "The requested entry was not found.",
            Self::AlreadyExists => "An entry with that name already exists.",
            Self::NotDirectory => "The requested entry is not a directory.",
            Self::IsDirectory => "The requested entry is a directory.",
            Self::DirectoryNotEmpty => "The directory is not empty.",
            Self::Conflict => "The operation conflicts with the current state.",
            Self::ReadOnly => "The authorized root is read-only.",
            Self::StorageFull => "There is not enough free storage.",
            Self::PayloadTooLarge => "The content is larger than the configured limit.",
            Self::Unsupported => "This operation is not supported.",
            Self::Busy => "The filesystem is busy.",
            Self::TransferFailed => "The content transfer did not complete.",
            Self::Unavailable => "The filesystem provider is temporarily unavailable.",
            Self::Internal => "An internal error occurred.",
        }
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RemoteFsErrorResponse {
    pub code: RemoteFsErrorCode,
    pub message: String,
}

impl From<RemoteFsErrorCode> for RemoteFsErrorResponse {
    fn from(code: RemoteFsErrorCode) -> Self {
        Self {
            code,
            message: code.safe_message().to_string(),
        }
    }
}

pub fn validate_file_name(name: &str) -> Result<(), RemoteFsErrorCode> {
    if name.is_empty()
        || name == "."
        || name == ".."
        || name.len() > MAX_NAME_BYTES
        || name.contains('/')
        || name.contains('\\')
        || name.chars().any(char::is_control)
    {
        return Err(RemoteFsErrorCode::InvalidName);
    }
    Ok(())
}

fn validate_root_id(root_id: &str) -> Result<(), RemoteFsErrorCode> {
    if root_id.is_empty()
        || root_id.len() > MAX_ROOT_ID_BYTES
        || !root_id
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || matches!(b, b'-' | b'_' | b'.' | b'~'))
    {
        return Err(RemoteFsErrorCode::InvalidRequest);
    }
    Ok(())
}

fn validate_relative_path(path: &str) -> Result<(), RemoteFsErrorCode> {
    if path.is_empty() {
        return Ok(());
    }
    if path.len() > MAX_PATH_BYTES
        || path.starts_with('/')
        || path.ends_with('/')
        || path.contains('\\')
        || path.chars().any(char::is_control)
        || is_windows_absolute(path)
        || path
            .split('/')
            .any(|component| component.is_empty() || component == "." || component == "..")
    {
        return Err(RemoteFsErrorCode::InvalidPath);
    }
    Ok(())
}

fn is_windows_absolute(path: &str) -> bool {
    let bytes = path.as_bytes();
    bytes.len() >= 2 && bytes[0].is_ascii_alphabetic() && bytes[1] == b':'
}

pub(crate) fn validate_root(root: &RemoteFsRoot) -> Result<(), RemoteFsErrorCode> {
    validate_root_id(&root.id)?;
    if root.display_name.is_empty()
        || root.display_name.len() > 256
        || root.display_name.chars().any(char::is_control)
        || matches!((root.free_bytes, root.total_bytes), (Some(free), Some(total)) if free > total)
    {
        return Err(RemoteFsErrorCode::Internal);
    }
    Ok(())
}

pub(crate) fn validate_entry(
    entry: &RemoteFsEntry,
    expected_parent: Option<&str>,
) -> Result<(), RemoteFsErrorCode> {
    validate_file_name(&entry.name).map_err(|_| RemoteFsErrorCode::Internal)?;
    validate_relative_path(&entry.path).map_err(|_| RemoteFsErrorCode::Internal)?;

    if let Some(parent) = expected_parent {
        let expected = if parent.is_empty() {
            entry.name.clone()
        } else {
            format!("{parent}/{}", entry.name)
        };
        if entry.path != expected {
            return Err(RemoteFsErrorCode::Internal);
        }
    } else if entry.path.rsplit('/').next() != Some(entry.name.as_str()) {
        return Err(RemoteFsErrorCode::Internal);
    }

    if entry
        .modified
        .as_ref()
        .is_some_and(|value| value.len() > 64 || value.chars().any(char::is_control))
        || entry
            .mime_type
            .as_ref()
            .is_some_and(|value| value.len() > 255 || value.chars().any(char::is_control))
    {
        return Err(RemoteFsErrorCode::Internal);
    }

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn accepts_root_and_nested_relative_paths() {
        assert!(RemoteFsLocation::new("downloads", "").is_ok());
        assert!(RemoteFsLocation::new("saf-tree_1", "Music/Album/song.mp3").is_ok());
        assert!(RemoteFsLocation::new("root", "Fotos de José/2026").is_ok());
    }

    #[test]
    fn rejects_traversal_absolute_and_ambiguous_paths() {
        for path in [
            "../secret",
            "folder/../secret",
            "/storage/emulated/0",
            r"C:\\Users\\secret",
            "C:/Users/secret",
            "folder//file",
            "folder/./file",
            "folder/",
        ] {
            assert_eq!(
                RemoteFsLocation::new("root", path),
                Err(RemoteFsErrorCode::InvalidPath),
                "path {path:?} should be rejected"
            );
        }
    }

    #[test]
    fn root_ids_cannot_smuggle_native_locations() {
        for root_id in ["", "content://tree/primary", "../root", "root id"] {
            assert_eq!(
                RemoteFsLocation::new(root_id, ""),
                Err(RemoteFsErrorCode::InvalidRequest)
            );
        }
    }

    #[test]
    fn validates_names_independently_from_paths() {
        assert!(validate_file_name("résumé 2026.pdf").is_ok());
        for name in ["", ".", "..", "a/b", r"a\b", "bad\0name"] {
            assert_eq!(
                validate_file_name(name),
                Err(RemoteFsErrorCode::InvalidName)
            );
        }
    }

    #[test]
    fn list_limits_and_cursors_are_bounded() {
        let location = RemoteFsLocation::new("root", "").unwrap();
        let mut request = RemoteFsListRequest::new(location);
        assert!(request.validate().is_ok());
        request.limit = 0;
        assert_eq!(request.validate(), Err(RemoteFsErrorCode::InvalidRequest));
        request.limit = MAX_LIST_LIMIT;
        request.cursor = Some("next-page".to_string());
        assert!(request.validate().is_ok());
    }
}
