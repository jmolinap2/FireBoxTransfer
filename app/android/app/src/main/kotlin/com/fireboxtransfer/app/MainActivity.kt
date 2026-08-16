package com.fireboxtransfer.app

import android.annotation.SuppressLint
import android.app.Activity
import android.content.ContentResolver
import android.content.Context
import android.content.Intent
import android.database.Cursor
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.DocumentsContract
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors


private const val CHANNEL = "com.fireboxtransfer.app/fireboxtransfer"
private const val REQUEST_CODE_PICK_DIRECTORY = 1
private const val REQUEST_CODE_PICK_DIRECTORY_PATH = 2
private const val REQUEST_CODE_PICK_FILE = 3
private const val REQUEST_CODE_PICK_SHARED_ROOT = 4
private const val SHARED_ROOTS_PREFERENCES = "fireboxtransfer_saf"
private const val SHARED_ROOTS_KEY = "shared_roots"
private val SAF_DOCUMENT_PROJECTION = arrayOf(
    DocumentsContract.Document.COLUMN_DOCUMENT_ID,
    DocumentsContract.Document.COLUMN_DISPLAY_NAME,
    DocumentsContract.Document.COLUMN_MIME_TYPE,
    DocumentsContract.Document.COLUMN_SIZE,
    DocumentsContract.Document.COLUMN_LAST_MODIFIED,
    DocumentsContract.Document.COLUMN_FLAGS,
)

class MainActivity : FlutterActivity() {
    private var pendingResult: MethodChannel.Result? = null
    private val safExecutor: ExecutorService = Executors.newSingleThreadExecutor()

    // Overriding the static methods we need from the Java class, as described
    // in the documentation of `FlutterActivity.NewEngineIntentBuilder`
    companion object {
        fun withNewEngine(): NewEngineIntentBuilder {
            return NewEngineIntentBuilder(MainActivity::class.java)
        }

        fun createDefaultIntent(launchContext: Context): Intent {
            return withNewEngine().build(launchContext)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "pickDirectory" -> {
                    pendingResult = result
                    openDirectoryPicker(onlyPath = false)
                }

                "pickFiles" -> {
                    pendingResult = result
                    openFilePicker()
                }

                "pickDirectoryPath" -> {
                    pendingResult = result
                    openDirectoryPicker(onlyPath = true)
                }

                "listDirectory" -> handleListDirectory(call, result)

                "safPickSharedRoot" -> {
                    if (pendingResult != null) {
                        result.error("PICKER_BUSY", "Another Android picker is already open", null)
                    } else {
                        pendingResult = result
                        openSharedRootPicker()
                    }
                }

                "safListSharedRoots" -> handleListSharedRoots(result)

                "safReleaseSharedRoot" -> handleReleaseSharedRoot(call, result)

                "safListDirectory" -> handleSafListDirectory(call, result)

                "safGetMetadata" -> handleSafGetMetadata(call, result)

                "safResolvePath" -> handleSafResolvePath(call, result)

                "safCreateDirectory" -> handleSafCreateDirectory(call, result)

                "safCreateFile" -> handleSafCreateFile(call, result)

                "safRename" -> handleSafRename(call, result)

                "safMove" -> handleSafMove(call, result)

                "safDelete" -> handleSafDelete(call, result)

                "safOpenRead" -> handleSafOpenRead(call, result)

                "safOpenWrite" -> handleSafOpenWrite(call, result)

                "createDirectory" -> handleCreateDirectory(call, result)

                "getFileDescriptor" -> handleGetFileDescriptor(call, result)

                "createFile" -> handleCreateFile(call, result)

                "openFileForWriting" -> handleOpenFileForWriting(call, result)

                "openContentUri" -> {
                    openUri(context, call.argument<String>("uri")!!)
                    result.success(null)
                }

                "openGallery" -> {
                    openGallery()
                    result.success(null)
                }

                "isAnimationsEnabled" -> {
                    result.success(isAnimationsEnabled())
                }

                "getDownloadsDirectory" -> {
                    result.success(getDownloadsDirectory())
                }

                else -> result.notImplemented()
            }
        }
    }

    /// Absolute path of the shared "Download" directory (usually /storage/emulated/0/Download).
    @Suppress("DEPRECATION")
    private fun getDownloadsDirectory(): String {
        return Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS).absolutePath
    }

    private fun isAnimationsEnabled() : Boolean {
        return Settings.Global.getFloat(this.getContentResolver(),
            Settings.Global.ANIMATOR_DURATION_SCALE, 1.0f) != 0.0f;
    }

    private fun handleGetFileDescriptor(call: MethodCall, result: MethodChannel.Result) {
        val uriString = call.argument<String>("uri")
        if (uriString == null) {
            result.error("INVALID_ARGUMENT", "Missing content URI", null)
            return
        }

        val uri = Uri.parse(uriString)
        if (uri.scheme != ContentResolver.SCHEME_CONTENT) {
            result.error("INVALID_ARGUMENT", "Expected a content:// URI", null)
            return
        }

        try {
            val parcelFileDescriptor = contentResolver.openFileDescriptor(uri, "r")
            if (parcelFileDescriptor == null) {
                result.error("OPEN_FAILED", "The content provider did not return a file descriptor", null)
                return
            }

            // Ownership of the detached descriptor is transferred to the caller. It must be
            // closed by Rust (or whichever native consumer receives it) after use.
            parcelFileDescriptor.use {
                result.success(it.detachFd())
            }
        } catch (e: SecurityException) {
            result.error("PERMISSION_DENIED", e.message ?: "Permission denied for content URI", null)
        } catch (e: Exception) {
            result.error("OPEN_FAILED", e.message ?: "Failed to open content URI", null)
        }
    }

    /// Creates a new file inside a SAF directory and opens it for writing.
    ///
    /// Returns the URI of the created document (Android may rename the file on
    /// collisions) and an owned writable file descriptor. The descriptor must be
    /// closed by the native consumer it is passed to.
    private fun handleCreateFile(call: MethodCall, result: MethodChannel.Result) {
        val parentUriString = call.argument<String>("parentUri")
        val fileName = call.argument<String>("fileName")
        val mimeType = call.argument<String>("mimeType") ?: "application/octet-stream"
        if (parentUriString == null || fileName == null) {
            result.error("INVALID_ARGUMENT", "Missing parentUri or fileName", null)
            return
        }

        try {
            val parentUri = Uri.parse(parentUriString)

            // A pure tree URI (content://…/tree/X) must be converted to its
            // document form before it can be used as a parent document.
            val segments = parentUri.pathSegments
            val parentDocumentUri = if (segments.size == 2 && segments[0] == "tree") {
                DocumentsContract.buildDocumentUriUsingTree(
                    parentUri,
                    DocumentsContract.getTreeDocumentId(parentUri)
                )
            } else {
                parentUri
            }

            val documentUri =
                DocumentsContract.createDocument(contentResolver, parentDocumentUri, mimeType, fileName)
            if (documentUri == null) {
                result.error("CREATE_FAILED", "Could not create $fileName in $parentUriString", null)
                return
            }

            // "wt" is write + truncate: the document is new, unless the provider
            // handed out an existing one instead of creating a second document.
            val parcelFileDescriptor = contentResolver.openFileDescriptor(documentUri, "wt")
            if (parcelFileDescriptor == null) {
                result.error("OPEN_FAILED", "The content provider did not return a file descriptor", null)
                return
            }

            parcelFileDescriptor.use {
                result.success(
                    mapOf(
                        "uri" to documentUri.toString(),
                        "fd" to it.detachFd(),
                    )
                )
            }
        } catch (e: SecurityException) {
            result.error("PERMISSION_DENIED", e.message ?: "Permission denied for content URI", null)
        } catch (e: Exception) {
            result.error("CREATE_FAILED", e.message ?: "Failed to create file", null)
        }
    }

    /// Opens an existing document created by [handleCreateFile] for writing,
    /// discarding its current content.
    ///
    /// Used to write a file again after a failed attempt, so that it keeps its
    /// name instead of being created a second time under a numbered one.
    ///
    /// Returns an owned writable file descriptor. It stays open after this call
    /// and must be closed by the native consumer it is passed to.
    private fun handleOpenFileForWriting(call: MethodCall, result: MethodChannel.Result) {
        val uriString = call.argument<String>("uri")
        if (uriString == null) {
            result.error("INVALID_ARGUMENT", "Missing content URI", null)
            return
        }

        val uri = Uri.parse(uriString)
        if (uri.scheme != ContentResolver.SCHEME_CONTENT) {
            result.error("INVALID_ARGUMENT", "Expected a content:// URI", null)
            return
        }

        try {
            // "wt" is write + truncate. A document provider may ignore the
            // truncation, so the writer additionally shortens the file itself.
            val parcelFileDescriptor = contentResolver.openFileDescriptor(uri, "wt")
            if (parcelFileDescriptor == null) {
                result.error("OPEN_FAILED", "The content provider did not return a file descriptor", null)
                return
            }

            parcelFileDescriptor.use {
                result.success(it.detachFd())
            }
        } catch (e: SecurityException) {
            result.error("PERMISSION_DENIED", e.message ?: "Permission denied for content URI", null)
        } catch (e: Exception) {
            result.error("OPEN_FAILED", e.message ?: "Failed to open content URI", null)
        }
    }

    private fun openDirectoryPicker(onlyPath: Boolean) {
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE)
        intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
        startActivityForResult(
            intent,
            if (onlyPath) REQUEST_CODE_PICK_DIRECTORY_PATH else REQUEST_CODE_PICK_DIRECTORY
        )
    }

    /**
     * Selects a directory capability without recursively enumerating it.
     *
     * A root selected here is explicitly registered for remote browsing. Trees
     * selected by the legacy send/receive pickers are intentionally not shared.
     */
    private fun openSharedRootPicker() {
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(
                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                    Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION
            )
        }
        startActivityForResult(intent, REQUEST_CODE_PICK_SHARED_ROOT)
    }

    private fun openFilePicker() {
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
            putExtra("multi-pick", true)
            type = "*/*"
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
        }
        startActivityForResult(intent, REQUEST_CODE_PICK_FILE)
    }

    @SuppressLint("WrongConstant")
    @Override
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (resultCode == Activity.RESULT_CANCELED) {
            pendingResult?.error("CANCELED", "Canceled", null)
            pendingResult = null
            return
        }

        if (resultCode != Activity.RESULT_OK || data == null) {
            pendingResult?.error("Error $resultCode", "Failed to access directory or file", null)
            pendingResult = null
            return
        }

        when (requestCode) {
            REQUEST_CODE_PICK_DIRECTORY -> {
                val uri: Uri? = data.data
                val takeFlags: Int =
                    data.flags and (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
                if (uri != null) {
                    contentResolver.takePersistableUriPermission(uri, takeFlags)

                    val files = mutableListOf<FileInfo>()
                    listFiles(uri, files)
                    val resultData = PickDirectoryResult(uri.toString(), files)
                    pendingResult?.success(resultData.toMap())
                    pendingResult = null
                } else {
                    pendingResult?.error("Error", "Failed to access directory", null)
                    pendingResult = null
                }
            }

            REQUEST_CODE_PICK_DIRECTORY_PATH -> {
                val uri: Uri? = data.data
                val takeFlags: Int =
                    data.flags and (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
                if (uri != null) {
                    contentResolver.takePersistableUriPermission(uri, takeFlags)
                    pendingResult?.success(uri.toString())
                    pendingResult = null
                } else {
                    pendingResult?.error("Error", "Failed to access directory", null)
                    pendingResult = null
                }
            }

            REQUEST_CODE_PICK_SHARED_ROOT -> {
                val treeUri = data.data
                if (treeUri == null || treeUri.scheme != ContentResolver.SCHEME_CONTENT || !DocumentsContract.isTreeUri(treeUri)) {
                    pendingResult?.error("INVALID_ROOT", "The selected provider did not return a SAF tree URI", null)
                    pendingResult = null
                    return
                }

                val takeFlags = data.flags and (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
                if (takeFlags and Intent.FLAG_GRANT_READ_URI_PERMISSION == 0) {
                    pendingResult?.error("PERMISSION_DENIED", "The selected directory did not grant read access", null)
                    pendingResult = null
                    return
                }

                var registered = false
                try {
                    contentResolver.takePersistableUriPermission(treeUri, takeFlags)
                    registerSharedRoot(treeUri)
                    registered = true
                    val grantedRoot = requireGrantedDocument(treeUri.toString(), write = false)
                    pendingResult?.success(sharedRootMap(grantedRoot))
                } catch (e: SecurityException) {
                    if (registered) {
                        unregisterSharedRoot(treeUri)
                        runCatching { releasePersistedPermission(treeUri) }
                    }
                    pendingResult?.error("PERMISSION_DENIED", e.message ?: "Could not persist access to the selected directory", null)
                } catch (e: Exception) {
                    if (registered) {
                        unregisterSharedRoot(treeUri)
                        runCatching { releasePersistedPermission(treeUri) }
                    }
                    pendingResult?.error("ROOT_FAILED", e.message ?: "Could not register the selected directory", null)
                } finally {
                    pendingResult = null
                }
            }

            REQUEST_CODE_PICK_FILE -> {
                val uriList: List<Uri> = when {
                    data.clipData != null -> {
                        val clipData = data.clipData
                        val uris = mutableListOf<Uri>()
                        for (i in 0 until clipData!!.itemCount) {
                            uris.add(clipData.getItemAt(i).uri)
                        }
                        uris
                    }

                    data.data != null -> listOf(data.data!!)
                    else -> {
                        pendingResult?.error("Error", "Failed to access file", null)
                        return
                    }
                }

                val takeFlags: Int =
                    data.flags and (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)

                val resultList = mutableListOf<FileInfo>()
                for (uri in uriList) {
                    contentResolver.takePersistableUriPermission(uri, takeFlags)
                    val documentFile = FastDocumentFile.fromDocumentUri(this, uri)
                    if (documentFile == null) {
                        pendingResult?.error("Error", "Failed to access file", null)
                        return
                    }
                    resultList.add(
                        FileInfo(
                            name = documentFile.name,
                            size = documentFile.size,
                            uri = uri.toString(),
                            lastModified = documentFile.lastModified,
                        )
                    )
                }

                pendingResult?.success(resultList.map { it.toMap() })
                pendingResult = null
            }
        }
    }

    private fun listFiles(uri: Uri, files: MutableList<FileInfo>) {
        val pickedDir: FastDocumentFile = FastDocumentFile.fromTreeUri(this, uri)

        for (file in pickedDir.listFiles()) {
            if (file.isDirectory) {
                // Recursive call
                listFiles(file.uri, files)
            } else if (file.isFile) {
                files.add(
                    FileInfo(
                        name = file.name,
                        size = file.size,
                        uri = file.uri.toString(),
                        lastModified = file.lastModified,
                    ),
                )
            }
        }
    }

    override fun onDestroy() {
        safExecutor.shutdownNow()
        super.onDestroy()
    }

    private fun handleListSharedRoots(result: MethodChannel.Result) {
        handleSafResult(result, "ROOTS_FAILED") {
            registeredSharedRootUris().mapNotNull { rootUri ->
                try {
                    sharedRootMap(requireGrantedDocument(rootUri.toString(), write = false))
                } catch (_: Exception) {
                    // A provider or the user may revoke an Android grant outside the app.
                    // Such a root remains registered but is not advertised as accessible.
                    null
                }
            }
        }
    }

    private fun handleReleaseSharedRoot(call: MethodCall, result: MethodChannel.Result) {
        handleSafResult(result, "RELEASE_FAILED") {
            val requestedUri = parseContentUri(requiredString(call, "rootUri"))
            val registeredUri = registeredSharedRootUris().firstOrNull { sameTree(it, requestedUri) }
                ?: return@handleSafResult false
            val requestedDocumentId = if (DocumentsContract.isDocumentUri(this, requestedUri)) {
                DocumentsContract.getDocumentId(requestedUri)
            } else {
                DocumentsContract.getTreeDocumentId(requestedUri)
            }
            if (requestedDocumentId != DocumentsContract.getTreeDocumentId(registeredUri)) {
                throw SafOperationException("INVALID_ROOT", "Only the shared root itself can be released")
            }

            try {
                releasePersistedPermission(registeredUri)
            } finally {
                unregisterSharedRoot(registeredUri)
            }
            true
        }
    }

    private fun handleSafListDirectory(call: MethodCall, result: MethodChannel.Result) {
        handleSafResult(result, "LIST_FAILED") {
            val directory = requireGrantedDocument(requiredString(call, "directoryUri"), write = false)
            val directoryMetadata = queryDocumentMetadata(directory)
            if (!directoryMetadata.isDirectory) throw SafOperationException("NOT_A_DIRECTORY", "The requested document is not a directory")

            val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(
                directory.documentUri,
                DocumentsContract.getDocumentId(directory.documentUri),
            )
            val cursor = contentResolver.query(childrenUri, SAF_DOCUMENT_PROJECTION, null, null, null)
                ?: throw SafOperationException("QUERY_FAILED", "The content provider returned no directory cursor")
            cursor.use {
                val documents = mutableListOf<Map<String, Any?>>()
                while (it.moveToNext()) {
                    val documentId = it.requiredString(DocumentsContract.Document.COLUMN_DOCUMENT_ID)
                    val childUri = DocumentsContract.buildDocumentUriUsingTree(directory.treeUri, documentId)
                    documents.add(documentMetadataMap(metadataFromCursor(it, childUri), directory))
                }
                documents
            }
        }
    }

    private fun handleSafGetMetadata(call: MethodCall, result: MethodChannel.Result) {
        handleSafResult(result, "METADATA_FAILED") {
            val document = requireGrantedDocument(requiredString(call, "uri"), write = false)
            documentMetadataMap(queryDocumentMetadata(document), document)
        }
    }

    /** Resolves a relative path by querying children; document IDs are never fabricated from path text. */
    private fun handleSafResolvePath(call: MethodCall, result: MethodChannel.Result) {
        handleSafResult(result, "RESOLVE_FAILED") {
            var current = requireGrantedDocument(requiredString(call, "rootUri"), write = false)
            if (DocumentsContract.getDocumentId(current.documentUri) != current.rootDocumentId) {
                throw SafOperationException("INVALID_ROOT", "rootUri must identify the root of a shared tree")
            }
            val relativePath = call.argument<String>("relativePath") ?: ""
            if (relativePath.length > 4096) {
                throw SafOperationException("INVALID_PATH", "The relative path is too long")
            }
            if (relativePath.startsWith('/') || relativePath.startsWith('\\')) {
                throw SafOperationException("INVALID_PATH", "Only paths relative to the shared root are accepted")
            }
            val segments = relativePath.replace('\\', '/').split('/').filter { it.isNotEmpty() }
            if (segments.size > 256 || segments.any { it == "." || it == ".." || it.indexOf('\u0000') >= 0 }) {
                throw SafOperationException("INVALID_PATH", "The relative path contains a forbidden segment")
            }

            for (segment in segments) {
                val metadata = queryDocumentMetadata(current)
                if (!metadata.isDirectory) throw SafOperationException("NOT_A_DIRECTORY", "${metadata.name} is not a directory")
                val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(
                    current.documentUri,
                    DocumentsContract.getDocumentId(current.documentUri),
                )
                val cursor = contentResolver.query(
                    childrenUri,
                    arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID, DocumentsContract.Document.COLUMN_DISPLAY_NAME),
                    null,
                    null,
                    null,
                ) ?: throw SafOperationException("QUERY_FAILED", "The content provider returned no directory cursor")
                val matches = cursor.use {
                    val ids = mutableListOf<String>()
                    while (it.moveToNext()) {
                        if (it.requiredString(DocumentsContract.Document.COLUMN_DISPLAY_NAME) == segment) {
                            ids.add(it.requiredString(DocumentsContract.Document.COLUMN_DOCUMENT_ID))
                        }
                    }
                    ids
                }
                if (matches.isEmpty()) throw SafOperationException("NOT_FOUND", "No document named $segment exists in the requested directory")
                if (matches.size > 1) throw SafOperationException("AMBIGUOUS_PATH", "More than one document is named $segment")
                current = requireGrantedDocument(
                    DocumentsContract.buildDocumentUriUsingTree(current.treeUri, matches.single()).toString(),
                    write = false,
                )
            }
            documentMetadataMap(queryDocumentMetadata(current), current)
        }
    }

    private fun handleSafCreateDirectory(call: MethodCall, result: MethodChannel.Result) {
        handleSafResult(result, "CREATE_FAILED") {
            val parent = requireGrantedDocument(requiredString(call, "parentUri"), write = true)
            val parentMetadata = queryDocumentMetadata(parent)
            requireCreatableDirectory(parentMetadata)
            val name = validateDocumentName(requiredString(call, "name"))
            val createdUri = DocumentsContract.createDocument(
                contentResolver,
                parent.documentUri,
                DocumentsContract.Document.MIME_TYPE_DIR,
                name,
            ) ?: throw SafOperationException("CREATE_FAILED", "The content provider could not create the directory")
            val created = normalizeReturnedDocument(parent, createdUri, write = true)
            documentMetadataMap(queryDocumentMetadata(created), created)
        }
    }

    private fun handleSafCreateFile(call: MethodCall, result: MethodChannel.Result) {
        handleSafResult(result, "CREATE_FAILED") {
            val parent = requireGrantedDocument(requiredString(call, "parentUri"), write = true)
            requireCreatableDirectory(queryDocumentMetadata(parent))
            val name = validateDocumentName(requiredString(call, "name"))
            val mimeType = call.argument<String>("mimeType")?.takeIf { it.isNotBlank() } ?: "application/octet-stream"
            if (mimeType == DocumentsContract.Document.MIME_TYPE_DIR) {
                throw SafOperationException("INVALID_MIME_TYPE", "Use create directory to create a directory")
            }
            val createdUri = DocumentsContract.createDocument(contentResolver, parent.documentUri, mimeType, name)
                ?: throw SafOperationException("CREATE_FAILED", "The content provider could not create the file")
            val created = normalizeReturnedDocument(parent, createdUri, write = true)

            try {
                val descriptor = contentResolver.openFileDescriptor(created.documentUri, "wt")
                    ?: throw SafOperationException("OPEN_FAILED", "The content provider returned no writable file descriptor")
                descriptor.use {
                    mapOf(
                        "uri" to created.documentUri.toString(),
                        "fd" to it.detachFd(),
                    )
                }
            } catch (e: Exception) {
                // Avoid leaving an empty orphan when creation succeeded but opening failed.
                try {
                    DocumentsContract.deleteDocument(contentResolver, created.documentUri)
                } catch (_: Exception) {
                    // Preserve the original failure.
                }
                throw e
            }
        }
    }

    private fun handleSafRename(call: MethodCall, result: MethodChannel.Result) {
        handleSafResult(result, "RENAME_FAILED") {
            val document = requireGrantedDocument(requiredString(call, "uri"), write = true)
            preventRootMutation(document)
            val metadata = queryDocumentMetadata(document)
            if (!metadata.supports(DocumentsContract.Document.FLAG_SUPPORTS_RENAME)) {
                throw SafOperationException("UNSUPPORTED_OPERATION", "The content provider does not support renaming this document")
            }
            val newName = validateDocumentName(requiredString(call, "newName"))
            val renamedUri = DocumentsContract.renameDocument(contentResolver, document.documentUri, newName) ?: document.documentUri
            val renamed = normalizeReturnedDocument(document, renamedUri, write = true)
            documentMetadataMap(queryDocumentMetadata(renamed), renamed)
        }
    }

    private fun handleSafMove(call: MethodCall, result: MethodChannel.Result) {
        handleSafResult(result, "MOVE_FAILED") {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) {
                throw SafOperationException("UNSUPPORTED_ANDROID_VERSION", "Moving SAF documents requires Android 7.0 or newer")
            }

            val document = requireGrantedDocument(requiredString(call, "uri"), write = true)
            val sourceParent = requireGrantedDocument(requiredString(call, "sourceParentUri"), write = true)
            val targetParent = requireGrantedDocument(requiredString(call, "targetParentUri"), write = true)
            preventRootMutation(document)
            if (document.documentUri.authority != sourceParent.documentUri.authority || document.documentUri.authority != targetParent.documentUri.authority) {
                throw SafOperationException("CROSS_PROVIDER_MOVE_UNSUPPORTED", "Android cannot atomically move documents between different providers")
            }

            val metadata = queryDocumentMetadata(document)
            if (!queryDocumentMetadata(sourceParent).isDirectory || !queryDocumentMetadata(targetParent).isDirectory) {
                throw SafOperationException("NOT_A_DIRECTORY", "Both the source and destination parents must be directories")
            }
            if (!directoryContainsDocumentId(sourceParent, DocumentsContract.getDocumentId(document.documentUri))) {
                throw SafOperationException("INVALID_SOURCE_PARENT", "The supplied source parent does not directly contain this document")
            }
            if (DocumentsContract.getDocumentId(sourceParent.documentUri) == DocumentsContract.getDocumentId(targetParent.documentUri)) {
                return@handleSafResult documentMetadataMap(metadata, document)
            }
            if (metadata.isDirectory) {
                if (DocumentsContract.getDocumentId(document.documentUri) == DocumentsContract.getDocumentId(targetParent.documentUri)) {
                    throw SafOperationException("INVALID_MOVE", "A directory cannot be moved inside itself")
                }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q && DocumentsContract.isChildDocument(
                        contentResolver,
                        document.documentUri,
                        targetParent.documentUri,
                    )
                ) {
                    throw SafOperationException("INVALID_MOVE", "A directory cannot be moved inside itself")
                }
            }

            val movedUri = if (metadata.supports(DocumentsContract.Document.FLAG_SUPPORTS_MOVE)) {
                DocumentsContract.moveDocument(
                    contentResolver,
                    document.documentUri,
                    sourceParent.documentUri,
                    targetParent.documentUri,
                ) ?: throw SafOperationException("MOVE_FAILED", "The content provider did not move the document")
            } else {
                copyThenDeleteForMove(document, targetParent, metadata)
            }
            val moved = normalizeReturnedDocument(targetParent, movedUri, write = true)
            documentMetadataMap(queryDocumentMetadata(moved), moved)
        }
    }

    /**
     * Provider-native, non-atomic fallback for providers without moveDocument.
     * If deleting the source fails, the copied document is removed again when
     * possible, so callers never receive a successful result for a mere copy.
     */
    private fun copyThenDeleteForMove(
        document: GrantedSafDocument,
        targetParent: GrantedSafDocument,
        metadata: SafDocumentMetadataNative,
    ): Uri {
        if (!metadata.supports(DocumentsContract.Document.FLAG_SUPPORTS_COPY) ||
            !metadata.supports(DocumentsContract.Document.FLAG_SUPPORTS_DELETE)
        ) {
            throw SafOperationException(
                "UNSUPPORTED_OPERATION",
                "The content provider supports neither an atomic move nor a safe copy-and-delete fallback",
            )
        }

        val copiedUri = DocumentsContract.copyDocument(contentResolver, document.documentUri, targetParent.documentUri)
            ?: throw SafOperationException("MOVE_FAILED", "The content provider could not copy the document to its destination")
        val copied = normalizeReturnedDocument(targetParent, copiedUri, write = true)
        try {
            if (!DocumentsContract.deleteDocument(contentResolver, document.documentUri)) {
                throw SafOperationException("MOVE_FAILED", "The source document could not be deleted after it was copied")
            }
        } catch (deleteError: Exception) {
            try {
                DocumentsContract.deleteDocument(contentResolver, copied.documentUri)
            } catch (_: Exception) {
                // The provider may leave a duplicate. The move still fails and
                // the server can surface that it needs user reconciliation.
            }
            throw deleteError
        }
        return copied.documentUri
    }

    private fun handleSafDelete(call: MethodCall, result: MethodChannel.Result) {
        handleSafResult(result, "DELETE_FAILED") {
            val document = requireGrantedDocument(requiredString(call, "uri"), write = true)
            preventRootMutation(document)
            val metadata = queryDocumentMetadata(document)
            if (!metadata.supports(DocumentsContract.Document.FLAG_SUPPORTS_DELETE)) {
                throw SafOperationException("UNSUPPORTED_OPERATION", "The content provider does not support deleting this document")
            }
            if (!DocumentsContract.deleteDocument(contentResolver, document.documentUri)) {
                throw SafOperationException("DELETE_FAILED", "The content provider did not delete the document")
            }
            null
        }
    }

    private fun handleSafOpenRead(call: MethodCall, result: MethodChannel.Result) {
        handleSafResult(result, "OPEN_FAILED") {
            val document = requireGrantedDocument(requiredString(call, "uri"), write = false)
            if (queryDocumentMetadata(document).isDirectory) throw SafOperationException("IS_A_DIRECTORY", "A directory cannot be opened as a file")
            val descriptor = contentResolver.openFileDescriptor(document.documentUri, "r")
                ?: throw SafOperationException("OPEN_FAILED", "The content provider returned no readable file descriptor")
            descriptor.use { it.detachFd() }
        }
    }

    private fun handleSafOpenWrite(call: MethodCall, result: MethodChannel.Result) {
        handleSafResult(result, "OPEN_FAILED") {
            val document = requireGrantedDocument(requiredString(call, "uri"), write = true)
            val metadata = queryDocumentMetadata(document)
            if (metadata.isDirectory) throw SafOperationException("IS_A_DIRECTORY", "A directory cannot be opened as a file")
            if (!metadata.supports(DocumentsContract.Document.FLAG_SUPPORTS_WRITE)) {
                throw SafOperationException("UNSUPPORTED_OPERATION", "The content provider does not support writing this document")
            }
            val truncate = call.argument<Boolean>("truncate") ?: true
            val descriptor = contentResolver.openFileDescriptor(document.documentUri, if (truncate) "wt" else "rw")
                ?: throw SafOperationException("OPEN_FAILED", "The content provider returned no writable file descriptor")
            descriptor.use { it.detachFd() }
        }
    }

    private fun registerSharedRoot(treeUri: Uri) {
        val preferences = getSharedPreferences(SHARED_ROOTS_PREFERENCES, Context.MODE_PRIVATE)
        val roots = preferences.getStringSet(SHARED_ROOTS_KEY, emptySet())?.toMutableSet() ?: mutableSetOf()
        roots.removeAll { stored -> runCatching { sameTree(Uri.parse(stored), treeUri) }.getOrDefault(false) }
        roots.add(treeUri.toString())
        preferences.edit().putStringSet(SHARED_ROOTS_KEY, roots).apply()
    }

    private fun releasePersistedPermission(treeUri: Uri) {
        val permission = contentResolver.persistedUriPermissions.firstOrNull { sameTree(it.uri, treeUri) } ?: return
        var flags = 0
        if (permission.isReadPermission) flags = flags or Intent.FLAG_GRANT_READ_URI_PERMISSION
        if (permission.isWritePermission) flags = flags or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
        if (flags != 0) contentResolver.releasePersistableUriPermission(permission.uri, flags)
    }

    private fun unregisterSharedRoot(treeUri: Uri) {
        val preferences = getSharedPreferences(SHARED_ROOTS_PREFERENCES, Context.MODE_PRIVATE)
        val roots = preferences.getStringSet(SHARED_ROOTS_KEY, emptySet())?.toMutableSet() ?: mutableSetOf()
        roots.removeAll { stored -> runCatching { sameTree(Uri.parse(stored), treeUri) }.getOrDefault(false) }
        preferences.edit().putStringSet(SHARED_ROOTS_KEY, roots).apply()
    }

    private fun registeredSharedRootUris(): List<Uri> {
        val roots = getSharedPreferences(SHARED_ROOTS_PREFERENCES, Context.MODE_PRIVATE).getStringSet(SHARED_ROOTS_KEY, emptySet()) ?: emptySet()
        return roots.mapNotNull { stored ->
            runCatching { parseContentUri(stored) }.getOrNull()?.takeIf { DocumentsContract.isTreeUri(it) }
        }
    }

    private fun requireGrantedDocument(uriString: String, write: Boolean): GrantedSafDocument {
        val requestedUri = parseContentUri(uriString)
        if (!DocumentsContract.isTreeUri(requestedUri)) {
            throw SafOperationException("UNREGISTERED_URI", "The URI is not derived from a registered SAF tree")
        }

        val registeredTree = registeredSharedRootUris().firstOrNull { sameTree(it, requestedUri) }
            ?: throw SafOperationException("UNREGISTERED_URI", "The URI does not belong to a directory shared by the user")
        val permission = contentResolver.persistedUriPermissions.firstOrNull { sameTree(it.uri, registeredTree) }
            ?: throw SafOperationException("PERMISSION_REVOKED", "Android no longer grants access to this shared directory")
        if (write && !permission.isWritePermission) {
            throw SafOperationException("READ_ONLY_ROOT", "The shared directory was granted without write access")
        }
        if (!write && !permission.isReadPermission) {
            throw SafOperationException("PERMISSION_REVOKED", "The shared directory was granted without read access")
        }

        val rootDocumentId = DocumentsContract.getTreeDocumentId(registeredTree)
        val requestedDocumentId = if (DocumentsContract.isDocumentUri(this, requestedUri)) {
            DocumentsContract.getDocumentId(requestedUri)
        } else {
            DocumentsContract.getTreeDocumentId(requestedUri)
        }
        val rootDocumentUri = DocumentsContract.buildDocumentUriUsingTree(registeredTree, rootDocumentId)
        val documentUri = DocumentsContract.buildDocumentUriUsingTree(registeredTree, requestedDocumentId)

        // Since Android 10 the framework can ask the provider to prove actual
        // ancestry. On earlier versions the DocumentsProvider enforces the tree
        // grant when the normalized URI is used.
        if (requestedDocumentId != rootDocumentId && Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val isChild = try {
                DocumentsContract.isChildDocument(contentResolver, rootDocumentUri, documentUri)
            } catch (e: Exception) {
                throw SafOperationException("ANCESTRY_CHECK_FAILED", "The provider could not validate this document inside the shared tree", e)
            }
            if (!isChild) throw SafOperationException("OUTSIDE_SHARED_ROOT", "The document is outside the shared directory")
        }

        return GrantedSafDocument(
            treeUri = registeredTree,
            rootDocumentId = rootDocumentId,
            documentUri = documentUri,
            canRead = permission.isReadPermission,
            canWrite = permission.isWritePermission,
        )
    }

    private fun normalizeReturnedDocument(parent: GrantedSafDocument, returnedUri: Uri, write: Boolean): GrantedSafDocument {
        if (returnedUri.scheme != ContentResolver.SCHEME_CONTENT || returnedUri.authority != parent.treeUri.authority) {
            throw SafOperationException("INVALID_PROVIDER_RESPONSE", "The content provider returned a document outside its authority")
        }
        val documentId = DocumentsContract.getDocumentId(returnedUri)
        val normalizedUri = DocumentsContract.buildDocumentUriUsingTree(parent.treeUri, documentId)
        return requireGrantedDocument(normalizedUri.toString(), write)
    }

    private fun queryDocumentMetadata(document: GrantedSafDocument): SafDocumentMetadataNative {
        val cursor = contentResolver.query(document.documentUri, SAF_DOCUMENT_PROJECTION, null, null, null)
            ?: throw SafOperationException("QUERY_FAILED", "The content provider returned no metadata cursor")
        cursor.use {
            if (!it.moveToFirst()) throw SafOperationException("NOT_FOUND", "The requested document no longer exists")
            return metadataFromCursor(it, document.documentUri)
        }
    }

    private fun directoryContainsDocumentId(directory: GrantedSafDocument, documentId: String): Boolean {
        val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(
            directory.documentUri,
            DocumentsContract.getDocumentId(directory.documentUri),
        )
        val cursor = contentResolver.query(
            childrenUri,
            arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID),
            null,
            null,
            null,
        ) ?: throw SafOperationException("QUERY_FAILED", "The content provider returned no directory cursor")
        cursor.use {
            while (it.moveToNext()) {
                if (it.requiredString(DocumentsContract.Document.COLUMN_DOCUMENT_ID) == documentId) return true
            }
        }
        return false
    }

    private fun metadataFromCursor(cursor: Cursor, uri: Uri): SafDocumentMetadataNative {
        val mimeType = cursor.optionalString(DocumentsContract.Document.COLUMN_MIME_TYPE) ?: "application/octet-stream"
        return SafDocumentMetadataNative(
            uri = uri,
            name = cursor.optionalString(DocumentsContract.Document.COLUMN_DISPLAY_NAME) ?: DocumentsContract.getDocumentId(uri),
            mimeType = mimeType,
            size = cursor.optionalLong(DocumentsContract.Document.COLUMN_SIZE),
            lastModified = cursor.optionalLong(DocumentsContract.Document.COLUMN_LAST_MODIFIED),
            flags = cursor.optionalLong(DocumentsContract.Document.COLUMN_FLAGS) ?: 0L,
            isDirectory = mimeType == DocumentsContract.Document.MIME_TYPE_DIR,
        )
    }

    private fun documentMetadataMap(metadata: SafDocumentMetadataNative, grant: GrantedSafDocument): Map<String, Any?> {
        val canWriteFile = grant.canWrite && !metadata.isDirectory && metadata.supports(DocumentsContract.Document.FLAG_SUPPORTS_WRITE)
        return mapOf(
            "uri" to metadata.uri.toString(),
            "name" to metadata.name,
            "mimeType" to metadata.mimeType,
            "size" to metadata.size,
            "lastModified" to metadata.lastModified,
            "flags" to metadata.flags,
            "isDirectory" to metadata.isDirectory,
            "canRead" to grant.canRead,
            "canWrite" to canWriteFile,
            "canCreate" to (grant.canWrite && metadata.isDirectory && metadata.supports(DocumentsContract.Document.FLAG_DIR_SUPPORTS_CREATE)),
            "canRename" to (grant.canWrite && metadata.supports(DocumentsContract.Document.FLAG_SUPPORTS_RENAME)),
            "canMove" to (grant.canWrite && metadata.supports(DocumentsContract.Document.FLAG_SUPPORTS_MOVE)),
            "canDelete" to (grant.canWrite && metadata.supports(DocumentsContract.Document.FLAG_SUPPORTS_DELETE)),
        )
    }

    private fun sharedRootMap(root: GrantedSafDocument): Map<String, Any?> {
        val metadata = queryDocumentMetadata(root)
        return mapOf(
            "uri" to root.treeUri.toString(),
            "name" to metadata.name,
            "canRead" to root.canRead,
            "canWrite" to root.canWrite,
        )
    }

    private fun requireCreatableDirectory(metadata: SafDocumentMetadataNative) {
        if (!metadata.isDirectory) throw SafOperationException("NOT_A_DIRECTORY", "The destination is not a directory")
        if (!metadata.supports(DocumentsContract.Document.FLAG_DIR_SUPPORTS_CREATE)) {
            throw SafOperationException("UNSUPPORTED_OPERATION", "The content provider does not allow creating documents in this directory")
        }
    }

    private fun preventRootMutation(document: GrantedSafDocument) {
        if (DocumentsContract.getDocumentId(document.documentUri) == document.rootDocumentId) {
            throw SafOperationException("ROOT_MUTATION_FORBIDDEN", "A shared root cannot be renamed, moved, or deleted remotely")
        }
    }

    private fun validateDocumentName(name: String): String {
        if (name.length > 255 || name.isBlank() || name == "." || name == ".." || name.any { it == '/' || it == '\\' || it == '\u0000' }) {
            throw SafOperationException("INVALID_NAME", "The document name is empty, too long, or contains a forbidden character")
        }
        return name
    }

    private fun requiredString(call: MethodCall, name: String): String {
        return call.argument<String>(name)?.takeIf { it.isNotBlank() }
            ?: throw SafOperationException("INVALID_ARGUMENT", "Missing $name")
    }

    private fun parseContentUri(value: String): Uri {
        val uri = Uri.parse(value)
        if (uri.scheme != ContentResolver.SCHEME_CONTENT || uri.authority.isNullOrBlank()) {
            throw SafOperationException("INVALID_ARGUMENT", "Expected a content:// URI")
        }
        return uri
    }

    private fun sameTree(first: Uri, second: Uri): Boolean {
        return first.scheme == ContentResolver.SCHEME_CONTENT &&
            second.scheme == ContentResolver.SCHEME_CONTENT &&
            first.authority == second.authority &&
            DocumentsContract.isTreeUri(first) &&
            DocumentsContract.isTreeUri(second) &&
            DocumentsContract.getTreeDocumentId(first) == DocumentsContract.getTreeDocumentId(second)
    }

    private fun Cursor.requiredString(columnName: String): String {
        return optionalString(columnName) ?: throw SafOperationException("INVALID_PROVIDER_RESPONSE", "Missing $columnName in provider response")
    }

    private fun Cursor.optionalString(columnName: String): String? {
        val index = getColumnIndex(columnName)
        return if (index < 0 || isNull(index)) null else getString(index)
    }

    private fun Cursor.optionalLong(columnName: String): Long? {
        val index = getColumnIndex(columnName)
        return if (index < 0 || isNull(index)) null else getLong(index)
    }

    private fun handleSafResult(result: MethodChannel.Result, defaultCode: String, operation: () -> Any?) {
        safExecutor.execute {
            try {
                result.success(operation())
            } catch (e: SafOperationException) {
                result.error(e.code, e.message, null)
            } catch (e: SecurityException) {
                result.error("PERMISSION_DENIED", e.message ?: "Android denied access to the document", null)
            } catch (e: UnsupportedOperationException) {
                result.error("UNSUPPORTED_OPERATION", e.message ?: "The content provider does not support this operation", null)
            } catch (e: IllegalArgumentException) {
                result.error("INVALID_ARGUMENT", e.message ?: "Invalid SAF argument", null)
            } catch (e: Exception) {
                result.error(defaultCode, e.message ?: "Android SAF operation failed", null)
            }
        }
    }

    @SuppressLint("WrongConstant")
    private fun handleCreateDirectory(call: MethodCall, result: MethodChannel.Result) {
        val documentUri = Uri.parse(call.argument<String>("documentUri")!!)
        val directoryName = call.argument<String>("directoryName")!!

        if (folderExists(documentUri, directoryName)) {
            result.success(null)
            return
        }

        DocumentsContract.createDocument(
            context.contentResolver, documentUri, DocumentsContract.Document.MIME_TYPE_DIR,
            directoryName
        )

        result.success(null)
    }

    private fun folderExists(documentUri: Uri, folderName: String): Boolean {
        var cursor: Cursor? = null
        try {
            val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(documentUri, DocumentsContract.getDocumentId(documentUri))
            cursor = contentResolver.query(
                childrenUri,
                arrayOf(
                    DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                    DocumentsContract.Document.COLUMN_MIME_TYPE
                ),
                null,
                null,
                null,
            )

            if (cursor != null) {
                while (cursor.moveToNext()) {
                    val displayName = cursor.getString(0)
                    val mimeType = cursor.getString(1)

                    if (folderName == displayName && DocumentsContract.Document.MIME_TYPE_DIR == mimeType) {
                        return true
                    }
                }
            }
        } finally {
            cursor?.close()
        }
        return false
    }

    /**
     * Lists one SAF directory that the user has explicitly granted to the app.
     * The returned document URIs stay opaque to Dart: callers must never turn
     * them into filesystem paths or use them outside the granted tree.
     */
    private fun handleListDirectory(call: MethodCall, result: MethodChannel.Result) {
        val uriString = call.argument<String>("directoryUri")
        if (uriString.isNullOrBlank()) {
            result.error("INVALID_ARGUMENT", "Missing directory URI", null)
            return
        }

        try {
            val directory = FastDocumentFile.fromTreeUri(this, Uri.parse(uriString))
            result.success(directory.listFiles().map { file ->
                mapOf(
                    "name" to file.name,
                    "uri" to file.uri.toString(),
                    "size" to file.size,
                    "lastModified" to file.lastModified,
                    "isDirectory" to file.isDirectory,
                )
            })
        } catch (e: SecurityException) {
            result.error("PERMISSION_DENIED", e.message ?: "Permission denied for directory", null)
        } catch (e: Exception) {
            result.error("LIST_FAILED", e.message ?: "Failed to list directory", null)
        }
    }

    private fun openGallery() {
        val intent = Intent()
        intent.action = Intent.ACTION_VIEW
        intent.type = "image/*"
        startActivity(intent)
    }
}

data class PickDirectoryResult(
    val directoryUri: String,
    val files: List<FileInfo>,
) {
    fun toMap(): Map<String, Any> {
        return mapOf(
            "directoryUri" to directoryUri,
            "files" to files.map { it.toMap() }
        )
    }
}

data class FileInfo(
    val name: String,
    val size: Long,
    val uri: String,
    val lastModified: Long
) {
    fun toMap(): Map<String, Any> {
        return mapOf(
            "name" to name,
            "size" to size,
            "uri" to uri,
            "lastModified" to lastModified
        )
    }
}

private data class GrantedSafDocument(
    val treeUri: Uri,
    val rootDocumentId: String,
    val documentUri: Uri,
    val canRead: Boolean,
    val canWrite: Boolean,
)

private data class SafDocumentMetadataNative(
    val uri: Uri,
    val name: String,
    val mimeType: String,
    val size: Long?,
    val lastModified: Long?,
    val flags: Long,
    val isDirectory: Boolean,
) {
    fun supports(flag: Int): Boolean = flags and flag.toLong() != 0L
}

private class SafOperationException(
    val code: String,
    override val message: String,
    cause: Throwable? = null,
) : Exception(message, cause)
