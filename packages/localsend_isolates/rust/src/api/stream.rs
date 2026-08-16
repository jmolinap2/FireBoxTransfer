use bytes::Bytes;
use flutter_rust_bridge::frb;
use tokio::sync::mpsc;

const WRITE_BUFFER_SIZE: usize = 512 * 1024;

#[frb(opaque)]
pub struct Dart2RustStreamSink {
    sender: Option<mpsc::Sender<Bytes>>,
}

pub struct Dart2RustStreamReceiver {
    pub(crate) receiver: mpsc::Receiver<Bytes>,
}

pub fn create_stream() -> (Dart2RustStreamSink, Dart2RustStreamReceiver) {
    // We don't need to have a buffer because we already buffer on Dart side.
    // However, a buffer of 1 seems to improve performance.
    let (sender, receiver) = mpsc::channel(1);
    (
        Dart2RustStreamSink {
            sender: Some(sender),
        },
        Dart2RustStreamReceiver { receiver },
    )
}

impl Dart2RustStreamSink {
    pub async fn add(&mut self, data: Vec<u8>) -> Result<(), String> {
        self.sender
            .as_ref()
            .ok_or_else(|| "Stream already closed".to_string())?
            .send(Bytes::from(data))
            .await
            .map_err(|_| "Failed to send data".to_string())
    }

    /// Closes the stream, signaling the end of data to the Rust side.
    #[frb(sync)]
    pub fn close(&mut self) {
        self.sender = None;
    }
}

/// Writes a Dart-produced byte stream to exactly one local target without
/// buffering the complete file in memory. The channel provides backpressure.
///
/// On Android, ownership of `file_descriptor` is transferred to Rust and it
/// is closed on success, error or cancellation. File descriptors are rejected
/// on other platforms. The write succeeds only when exactly `expected_size`
/// bytes were received.
pub async fn write_stream_to_target(
    mut binary: Dart2RustStreamReceiver,
    path: Option<String>,
    file_descriptor: Option<i32>,
    expected_size: u64,
) -> Result<u64, String> {
    use tokio::io::AsyncWriteExt;

    let file = match (path, file_descriptor) {
        (Some(path), None) => tokio::fs::File::create(&path)
            .await
            .map_err(|error| format!("Failed to create target file: {error}"))?,
        (None, Some(file_descriptor)) => {
            #[cfg(target_os = "android")]
            {
                use std::os::fd::FromRawFd;

                // SAFETY: Dart transfers ownership of this descriptor. File
                // owns it from here and closes it whenever this future exits.
                let file = unsafe { std::fs::File::from_raw_fd(file_descriptor) };
                tokio::fs::File::from_std(file)
            }
            #[cfg(not(target_os = "android"))]
            {
                let _ = file_descriptor;
                return Err("File descriptors are only supported on Android".to_string());
            }
        }
        _ => return Err("Exactly one write target must be provided".to_string()),
    };

    let mut file = tokio::io::BufWriter::with_capacity(WRITE_BUFFER_SIZE, file);
    let mut bytes_written = 0_u64;
    while let Some(chunk) = binary.receiver.recv().await {
        bytes_written = bytes_written
            .checked_add(chunk.len() as u64)
            .ok_or_else(|| "Stream size overflow".to_string())?;
        if bytes_written > expected_size {
            return Err(format!(
                "Expected {expected_size} bytes, received at least {bytes_written}"
            ));
        }
        file.write_all(&chunk)
            .await
            .map_err(|error| format!("Failed to write target file: {error}"))?;
    }
    file.flush()
        .await
        .map_err(|error| format!("Failed to flush target file: {error}"))?;

    if bytes_written != expected_size {
        return Err(format!(
            "Expected {expected_size} bytes, received {bytes_written}"
        ));
    }

    let file = file.into_inner();
    if let Err(error) = file.set_len(bytes_written).await {
        // Some Android document providers do not support truncation. Exact
        // byte-count validation above remains authoritative for the stream.
        tracing::warn!("Could not truncate target to {bytes_written} bytes: {error}");
    }
    drop(file);
    Ok(bytes_written)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn writes_stream_with_backpressure_and_exact_size() {
        let path = std::env::temp_dir().join(format!("firebox-stream-{}", uuid::Uuid::new_v4()));
        let (mut sink, receiver) = create_stream();
        let producer = tokio::spawn(async move {
            sink.add(b"hello ".to_vec()).await.unwrap();
            sink.add(b"world".to_vec()).await.unwrap();
            sink.close();
        });

        let written = write_stream_to_target(
            receiver,
            Some(path.to_string_lossy().into_owned()),
            None,
            11,
        )
        .await
        .unwrap();
        producer.await.unwrap();
        assert_eq!(written, 11);
        assert_eq!(tokio::fs::read(&path).await.unwrap(), b"hello world");
        tokio::fs::remove_file(path).await.unwrap();
    }

    #[tokio::test]
    async fn rejects_truncated_stream() {
        let path = std::env::temp_dir().join(format!("firebox-stream-{}", uuid::Uuid::new_v4()));
        let (mut sink, receiver) = create_stream();
        sink.add(b"short".to_vec()).await.unwrap();
        sink.close();

        let error = write_stream_to_target(
            receiver,
            Some(path.to_string_lossy().into_owned()),
            None,
            10,
        )
        .await
        .unwrap_err();
        assert!(error.contains("Expected 10 bytes, received 5"));
        tokio::fs::remove_file(path).await.unwrap();
    }
}
