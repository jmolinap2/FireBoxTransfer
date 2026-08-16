use flutter_rust_bridge::frb;
pub use localsend::http::dto::{
    PrepareUploadRequestDto, PrepareUploadResponseDto, RegisterDto, RegisterResponseDto,
};
pub use localsend::http::firebox::{
    RemoteFsCapability, RemoteFsCreateDirectoryRequest, RemoteFsDeleteRequest, RemoteFsEntry,
    RemoteFsEntryType, RemoteFsErrorCode, RemoteFsListRequest, RemoteFsListResponse,
    RemoteFsLocation, RemoteFsMoveRequest, RemoteFsRenameRequest, RemoteFsRoot,
    RemoteFsWriteRequest, RemoteFsWriteResponse,
};
pub use localsend::model::discovery::DeviceType;
pub use localsend::model::discovery::ProtocolType;
pub use localsend::model::transfer::{FileDto, FileMetadata};
use std::collections::HashMap;

#[frb(mirror(RegisterDto))]
pub struct _RegisterDto {
    pub alias: String,
    pub version: String,
    pub device_model: Option<String>,
    pub device_type: Option<DeviceType>,
    pub token: String,
    pub port: u16,
    pub protocol: ProtocolType,
    pub has_web_interface: bool,
}

#[frb(mirror(RegisterResponseDto))]
pub struct _RegisterResponseDto {
    pub alias: String,
    pub version: String,
    pub device_model: Option<String>,
    pub device_type: Option<DeviceType>,
    pub token: String,
    pub has_web_interface: bool,
}

#[frb(mirror(DeviceType))]
pub enum _DeviceType {
    Mobile,
    Desktop,
    Web,
    Headless,
    Server,
}

#[frb(mirror(ProtocolType))]
pub enum _ProtocolType {
    Http,
    Https,
}

#[frb(mirror(FileDto))]
pub struct _FileDto {
    pub id: String,
    pub file_name: String,
    pub size: u64,
    pub file_type: String,
    pub sha256: Option<String>,
    pub preview: Option<String>,
    pub metadata: Option<FileMetadata>,
}

#[frb(mirror(FileMetadata))]
pub struct _FileMetadata {
    pub modified: Option<String>,
    pub accessed: Option<String>,
}

#[frb(mirror(PrepareUploadRequestDto))]
pub struct _PrepareUploadRequestDto {
    pub info: RegisterDto,
    pub files: HashMap<String, FileDto>,
}

#[frb(mirror(PrepareUploadResponseDto))]
pub struct _PrepareUploadResponseDto {
    pub session_id: String,
    pub files: HashMap<String, String>,
}

#[frb(mirror(RemoteFsCapability))]
pub enum _RemoteFsCapability {
    Browse,
    Read,
    Write,
    CreateDirectory,
    Rename,
    Move,
    Delete,
}

#[frb(mirror(RemoteFsEntryType))]
pub enum _RemoteFsEntryType {
    File,
    Directory,
    Other,
}

#[frb(mirror(RemoteFsRoot))]
pub struct _RemoteFsRoot {
    pub id: String,
    pub display_name: String,
    pub capabilities: Vec<RemoteFsCapability>,
    pub total_bytes: Option<u64>,
    pub free_bytes: Option<u64>,
}

#[frb(mirror(RemoteFsLocation))]
pub struct _RemoteFsLocation {
    pub root_id: String,
    pub path: String,
}

#[frb(mirror(RemoteFsEntry))]
pub struct _RemoteFsEntry {
    pub name: String,
    pub path: String,
    pub entry_type: RemoteFsEntryType,
    pub size: Option<u64>,
    pub modified: Option<String>,
    pub mime_type: Option<String>,
    pub capabilities: Vec<RemoteFsCapability>,
}

#[frb(mirror(RemoteFsListRequest))]
pub struct _RemoteFsListRequest {
    pub location: RemoteFsLocation,
    pub cursor: Option<String>,
    pub limit: u16,
}

#[frb(mirror(RemoteFsListResponse))]
pub struct _RemoteFsListResponse {
    pub entries: Vec<RemoteFsEntry>,
    pub next_cursor: Option<String>,
}

#[frb(mirror(RemoteFsCreateDirectoryRequest))]
pub struct _RemoteFsCreateDirectoryRequest {
    pub parent: RemoteFsLocation,
    pub name: String,
}

#[frb(mirror(RemoteFsRenameRequest))]
pub struct _RemoteFsRenameRequest {
    pub source: RemoteFsLocation,
    pub new_name: String,
}

#[frb(mirror(RemoteFsMoveRequest))]
pub struct _RemoteFsMoveRequest {
    pub source: RemoteFsLocation,
    pub destination_parent: RemoteFsLocation,
    pub new_name: Option<String>,
    pub overwrite: bool,
}

#[frb(mirror(RemoteFsDeleteRequest))]
pub struct _RemoteFsDeleteRequest {
    pub target: RemoteFsLocation,
    pub recursive: bool,
}

#[frb(mirror(RemoteFsWriteRequest))]
pub struct _RemoteFsWriteRequest {
    pub target: RemoteFsLocation,
    pub size: u64,
    pub overwrite: bool,
}

#[frb(mirror(RemoteFsWriteResponse))]
pub struct _RemoteFsWriteResponse {
    pub bytes_written: u64,
}

#[frb(mirror(RemoteFsErrorCode))]
pub enum _RemoteFsErrorCode {
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
