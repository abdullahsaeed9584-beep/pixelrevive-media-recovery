package com.nowdigiverse.media_recovery

import android.content.ContentUris
import android.content.ContentValues
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.ThumbnailUtils
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.util.Size
import androidx.annotation.RequiresApi
import androidx.core.content.FileProvider
import com.topjohnwu.superuser.Shell
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL = "com.nowdigiverse.recovery/core"
        private const val SCAN_STREAM_CHANNEL = "com.nowdigiverse.recovery/scan_stream"

        init {
            Shell.enableVerboseLogging = false
            Shell.setDefaultBuilder(
                Shell.Builder.create()
                    .setFlags(Shell.FLAG_REDIRECT_STDERR)
                    .setTimeout(10)
            )
            System.loadLibrary("carver")
        }
    }

    private external fun carveChunk(chunk: ByteArray, baseOffset: Long): Array<String>

    private var scanEventSink: EventChannel.EventSink? = null

    /** Set to true from Flutter's cancelScan() call — checked inside scan loops. */
    @Volatile
    private var scanCancelled = false

    /** All handler.post calls route to main thread so EventSink is called correctly. */
    private val mainHandler = Handler(Looper.getMainLooper())

    private var pendingSafResult: MethodChannel.Result? = null
    private val SAF_REQUEST_CODE = 9999
    
    private var quickScanRequested = false

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        
        // STUB: Crashlytics Error Handlers
        val defaultHandler = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, exception ->
            android.util.Log.e("CrashlyticsStub", "Uncaught exception in thread ${thread.name}", exception)
            defaultHandler?.uncaughtException(thread, exception)
        }

        if (intent?.action == "ACTION_QUICK_SCAN") {
            quickScanRequested = true
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (intent.action == "ACTION_QUICK_SCAN") {
            quickScanRequested = true
            // If flutter is already running, we can notify it directly via MethodChannel
            // but for simplicity, we let flutter poll or we can invoke a method on flutter channel
            flutterEngine?.dartExecutor?.binaryMessenger?.let { messenger ->
                MethodChannel(messenger, CHANNEL).invokeMethod("triggerQuickScan", null)
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == SAF_REQUEST_CODE) {
            if (resultCode == android.app.Activity.RESULT_OK && data != null) {
                val uri = data.data
                if (uri != null) {
                    contentResolver.takePersistableUriPermission(
                        uri,
                        Intent.FLAG_GRANT_READ_URI_PERMISSION
                    )
                    pendingSafResult?.success(uri.toString())
                } else {
                    pendingSafResult?.success(null)
                }
            } else {
                pendingSafResult?.success(null)
            }
            pendingSafResult = null
        }
    }

    // ──────────────────────────────────────────────────────────────────────────
    // Flutter engine setup
    // ──────────────────────────────────────────────────────────────────────────

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // ── MethodChannel ────────────────────────────────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "checkRootAccess" -> {
                            try {
                                result.success(Shell.isAppGrantedRoot() == true)
                            } catch (e: Exception) {
                                result.success(false)
                            }
                        }
                        "getAndroidApiLevel" -> result.success(Build.VERSION.SDK_INT)
                        "checkQuickScanIntent" -> {
                            val requested = quickScanRequested
                            quickScanRequested = false
                            result.success(requested)
                        }
                        
                        "checkDeviceResources" -> {
                            val bm = getSystemService(android.content.Context.BATTERY_SERVICE) as android.os.BatteryManager
                            val batteryLevel = bm.getIntProperty(android.os.BatteryManager.BATTERY_PROPERTY_CAPACITY)
                            val isCharging = bm.isCharging
                            
                            var isHot = false
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                                val pm = getSystemService(android.content.Context.POWER_SERVICE) as android.os.PowerManager
                                val thermalStatus = pm.currentThermalStatus
                                isHot = thermalStatus >= android.os.PowerManager.THERMAL_STATUS_SEVERE
                            }
                            
                            val map = mapOf(
                                "batteryLevel" to batteryLevel,
                                "isCharging" to isCharging,
                                "isHot" to isHot
                            )
                            result.success(map)
                        }
                        
                        "checkAvailableStorage" -> {
                            val stat = android.os.StatFs(android.os.Environment.getExternalStorageDirectory().path)
                            val bytesAvailable = stat.availableBlocksLong * stat.blockSizeLong
                            result.success(bytesAvailable)
                        }

                        "pickSafFolder" -> {
                            pendingSafResult = result
                            val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE)
                            startActivityForResult(intent, SAF_REQUEST_CODE)
                        }
                        "startScan" -> {
                            val categories = call.argument<List<String>>("categories") ?: emptyList()
                            val safUri = call.argument<String>("safUri")
                            scanCancelled = false
                            Thread { performScan(categories, safUri) }.start()
                            result.success(null)
                        }
                        "startDeepScan" -> {
                            val categories = call.argument<List<String>>("categories") ?: emptyList()
                            scanCancelled = false
                            val intent = Intent(this@MainActivity, DeepScanService::class.java)
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                startForegroundService(intent)
                            } else {
                                startService(intent)
                            }
                            Thread { performDeepScan(categories, resume = false) }.start()
                            result.success(null)
                        }
                        "pauseScan" -> {
                            scanCancelled = true
                            result.success(null)
                        }
                        "checkResumeState" -> {
                            val prefs = getSharedPreferences("ScanCheckpoint", android.content.Context.MODE_PRIVATE)
                            result.success(prefs.contains("lastOffset"))
                        }
                        "resumeDeepScan" -> {
                            scanCancelled = false
                            val intent = Intent(this@MainActivity, DeepScanService::class.java)
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                startForegroundService(intent)
                            } else {
                                startService(intent)
                            }
                            Thread { performDeepScan(emptyList(), resume = true) }.start()
                            result.success(null)
                        }
                        "clearResumeState" -> {
                            getSharedPreferences("ScanCheckpoint", android.content.Context.MODE_PRIVATE).edit().clear().apply()
                            result.success(null)
                        }
                        "cancelScan" -> {
                            scanCancelled = true
                            getSharedPreferences("ScanCheckpoint", android.content.Context.MODE_PRIVATE).edit().clear().apply()
                            stopService(Intent(this@MainActivity, DeepScanService::class.java))
                            result.success(null)
                        }

                    "recoverFiles" -> {
                        @Suppress("UNCHECKED_CAST")
                        val items =
                            call.argument<List<Map<String, Any>>>("items") ?: emptyList()
                        // Run recovery on background thread (can be slow for large files).
                        Thread {
                            val recovered = recoverFiles(items)
                            mainHandler.post { result.success(recovered) }
                        }.start()
                    }

                    "openFile" -> {
                        val path = call.argument<String>("path") ?: ""
                        openFileWithIntent(path)
                        result.success(null)
                    }

                    "startProtection" -> {
                        val folders = call.argument<List<String>>("folders") ?: emptyList()
                        val intent = Intent(this@MainActivity, ProtectionService::class.java).apply {
                            putStringArrayListExtra("folders", ArrayList(folders))
                        }
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(intent)
                        } else {
                            startService(intent)
                        }
                        result.success(null)
                    }

                    "stopProtection" -> {
                        stopService(Intent(this@MainActivity, ProtectionService::class.java))
                        result.success(null)
                    }

                    "sweepVaultFolders" -> {
                        val folders = call.argument<List<String>>("folders") ?: emptyList()
                        Thread {
                            performVaultSweep(folders)
                        }.start()
                        result.success(null)
                    }

                    "getVaultFiles" -> {
                        val vaultDir = File(filesDir, "vault")
                        android.util.Log.d("MainActivity", "getVaultFiles called. Vault directory: ${vaultDir.absolutePath}")
                        if (!vaultDir.exists()) {
                            android.util.Log.d("MainActivity", "Vault directory does not exist.")
                            result.success(emptyList<Map<String, Any>>())
                        } else {
                            val listFiles = vaultDir.listFiles()
                            android.util.Log.d("MainActivity", "Vault directory exists. File count: ${listFiles?.size}")
                            val files = listFiles?.filter { !it.name.startsWith("thumb_") }?.map { file ->
                                val nameParts = file.name.split("_", limit = 3)
                                val date = if (nameParts.size >= 2) nameParts[1].toLongOrNull() ?: 0L else 0L
                                val originalName = if (nameParts.size >= 3) nameParts[2] else file.name
                                mapOf(
                                    "encryptedName" to file.name,
                                    "originalName" to originalName,
                                    "dateProtected" to date,
                                    "size" to file.length(),
                                    "hasThumbnail" to File(vaultDir, "thumb_${file.name}").exists()
                                )
                            } ?: emptyList()
                            android.util.Log.d("MainActivity", "Returning files list of size: ${files.size}")
                            result.success(files)
                        }
                    }

                    "decryptVaultFile" -> {
                        val encryptedName = call.argument<String>("encryptedName") ?: ""
                        Thread {
                            val path = decryptVaultFile(encryptedName)
                            mainHandler.post { result.success(path) }
                        }.start()
                    }

                    "decryptVaultFileToCache" -> {
                        val encryptedName = call.argument<String>("encryptedName") ?: ""
                        val isThumbnail = call.argument<Boolean>("isThumbnail") ?: false
                        Thread {
                            val path = decryptVaultFileToCache(encryptedName, isThumbnail)
                            mainHandler.post { result.success(path) }
                        }.start()
                    }

                    "deleteVaultFile" -> {
                        val encryptedName = call.argument<String>("encryptedName") ?: ""
                        val file = File(File(filesDir, "vault"), encryptedName)
                        val deleted = if (file.exists()) file.delete() else false
                        result.success(deleted)
                    }

                    "setVaultPin" -> {
                        val pin = call.argument<String>("pin") ?: ""
                        getEncryptedPrefs().edit().putString("vault_pin", pin).apply()
                        result.success(true)
                    }

                    "checkVaultPin" -> {
                        val pin = call.argument<String>("pin") ?: ""
                        val storedPin = getEncryptedPrefs().getString("vault_pin", null)
                        result.success(storedPin != null && storedPin == pin)
                    }

                    "hasVaultPin" -> {
                        val storedPin = getEncryptedPrefs().getString("vault_pin", null)
                        result.success(storedPin != null)
                    }

                    else -> result.notImplemented()
                }
                } catch (e: Exception) {
                    android.util.Log.e("CrashlyticsStub", "MethodChannel error for ${call.method}", e)
                    result.error("NATIVE_ERROR", e.message, null)
                }
            }

        // ── EventChannel — streams scan results one-by-one to Flutter ────────
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, SCAN_STREAM_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    scanEventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    scanEventSink = null
                }
            })
    }

    // ──────────────────────────────────────────────────────────────────────────
    // Scan orchestration
    // ──────────────────────────────────────────────────────────────────────────

    private fun performScan(categories: List<String>, safUri: String?) {
        val sink = scanEventSink ?: return

        try {
            val hasRoot = Shell.isAppGrantedRoot() == true
            android.util.Log.d("ScanStats", "Root access detected: $hasRoot")

            if (safUri != null) {
                android.util.Log.d("ScanStats", "Running SAF Scan instead of Quick Scan.")
                scanSafTree(safUri, categories, sink)
                return
            }

            android.util.Log.d("ScanStats", "Starting Quick Scan (Tier 1)")
            var trashCount = 0
            // Tier 1a — MediaStore trash (Android 11+ / API 30+)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                val scanTrash = categories.isEmpty() ||
                        categories.any { it in listOf("photos", "videos", "audio", "documents") }
                if (scanTrash) {
                    trashCount = scanMediaStoreTrash(categories, sink)
                }
            }

            // Tier 1b — WhatsApp media (gallery-invisible files)
            var waCount = 0
            val scanWa = categories.isEmpty() || categories.contains("whatsapp")
            if (scanWa && !scanCancelled) {
                waCount = scanWhatsAppMedia(sink)
            }

            android.util.Log.d("ScanStats", "Quick Scan Complete. MediaStore Trash: $trashCount items. WhatsApp Media: $waCount items.")
        } finally {
            // Always signal done so Flutter stream closes cleanly.
            mainHandler.post { sink.endOfStream() }
        }
    }

    // ──────────────────────────────────────────────────────────────────────────
    // Phase 4: Root Deep Scan
    // ──────────────────────────────────────────────────────────────────────────

    private fun performDeepScan(categoriesArg: List<String>, resume: Boolean) {
        val sink = scanEventSink ?: return
        val prefs = getSharedPreferences("ScanCheckpoint", android.content.Context.MODE_PRIVATE)
        
        try {
            if (Shell.isAppGrantedRoot() != true) {
                return
            }

            var partition: String? = null
            var offset = 0L
            var categories = categoriesArg

            if (resume) {
                partition = prefs.getString("partition", null)
                offset = prefs.getLong("lastOffset", 0L)
                val catsString = prefs.getString("categories", "")
                if (!catsString.isNullOrEmpty()) {
                    categories = catsString.split(",")
                }
            } else {
                // Find userdata partition dynamically
                val candidatePaths = listOf(
                    "/dev/block/bootdevice/by-name/userdata",
                    "/dev/block/by-name/userdata",
                    "/dev/block/platform/soc.0/by-name/userdata",
                    "/dev/block/platform/soc/by-name/userdata"
                )

                for (path in candidatePaths) {
                    if (Shell.cmd("test -e $path").exec().isSuccess) {
                        partition = path
                        break
                    }
                }

                if (partition == null) {
                    val dfRes = Shell.cmd("df /data").exec().out
                    if (dfRes.size > 1) {
                        val parts = dfRes[1].split(Regex("\\s+"))
                        if (parts.isNotEmpty()) {
                            val potentialPart = parts[0]
                            if (potentialPart.startsWith("/dev/block/")) {
                                partition = potentialPart
                            }
                        }
                    }
                }
            }

            if (partition == null) {
                android.util.Log.e("DeepScan", "Could not locate userdata partition")
                return
            }

            // dd uses blocks. bs=4M means each block is 4194304 bytes.
            val bs = 4L * 1024 * 1024
            val skipBlocks = offset / bs
            
            // Realign offset to block boundary
            offset = skipBlocks * bs

            // Execute dd over root and stream stdout using standard Java Process for raw InputStream access
            val process = Runtime.getRuntime().exec(arrayOf("su", "-c", "dd if=$partition bs=4M skip=$skipBlocks"))
            val inputStream = process.inputStream
            
            val buffer = ByteArray(bs.toInt())
            var bytesRead: Int
            var fileCounter = 0
            
            // Checkpoint variables
            val checkpointIntervalBytes = 100L * 1024 * 1024 // 100MB
            var lastCheckpointOffset = offset

            while (!scanCancelled) {
                bytesRead = inputStream.read(buffer)
                if (bytesRead == -1) break
                
                val chunk = if (bytesRead == buffer.size) {
                    buffer
                } else {
                    buffer.copyOf(bytesRead)
                }

                val foundFiles = carveChunk(chunk, offset)

                for (res in foundFiles) {
                    if (scanCancelled) break
                    val parts = res.split(",")
                    if (parts.size == 4) {
                        val fileOffset = parts[0].toLongOrNull() ?: 0L
                        val fileLength = parts[1].toLongOrNull() ?: 0L
                        val mimeType = parts[2]
                        val confidence = parts[3].toIntOrNull() ?: 50

                        if (categories.isNotEmpty() && !matchesCategory(mimeType, categories)) continue
                        
                        fileCounter++
                        val name = "recovered_${mimeType.replace('/', '_')}_${fileCounter}"

                        val resultMap: Map<String, Any?> = mapOf(
                            "uri" to "",
                            "path" to "",
                            "name" to name,
                            "dateDeleted" to System.currentTimeMillis(),
                            "size" to fileLength,
                            "mimeType" to mimeType,
                            "source" to "deep_scan",
                            "confidence" to confidence,
                            "thumbnailPath" to "",
                            "offset" to fileOffset,
                            "partition" to partition
                        )
                        mainHandler.post { sink.success(resultMap) }
                    }
                }
                
                offset += bytesRead
                
                if (offset - lastCheckpointOffset >= checkpointIntervalBytes) {
                    prefs.edit()
                        .putString("partition", partition)
                        .putLong("lastOffset", offset)
                        .putString("categories", categories.joinToString(","))
                        .apply()
                    lastCheckpointOffset = offset
                    
                    // Update progress (approximate fake progress since partition size is unknown)
                    val approxPercent = ((offset / (1024 * 1024 * 50)) % 100).toInt()
                    DeepScanService.updateProgress(this, approxPercent)
                }
            }
            
            inputStream.close()
            process.destroy()
            
            if (scanCancelled) {
                // User paused. Save exact offset
                prefs.edit()
                    .putString("partition", partition)
                    .putLong("lastOffset", offset)
                    .putString("categories", categories.joinToString(","))
                    .apply()
            } else {
                // Finished normally, clear checkpoint
                prefs.edit().clear().apply()
            }
            
        } catch (e: Exception) {
            android.util.Log.e("DeepScan", "Error in deep scan: ${e.message}")
        } finally {
            stopService(Intent(this@MainActivity, DeepScanService::class.java))
            mainHandler.post { sink.endOfStream() }
        }
    }

    // ──────────────────────────────────────────────────────────────────────────
    // SAF Extended Scanner (Phase 3)
    // ──────────────────────────────────────────────────────────────────────────

    private fun scanSafTree(uriString: String, categories: List<String>, sink: EventChannel.EventSink) {
        try {
            val rootUri = Uri.parse(uriString)
            val rootDoc = androidx.documentfile.provider.DocumentFile.fromTreeUri(this, rootUri) ?: return
            traverseSafTree(rootDoc, categories, sink)
        } catch (e: Exception) {
            android.util.Log.e("SAF", "Error scanning SAF tree: ${e.message}")
        }
    }

    private fun traverseSafTree(dir: androidx.documentfile.provider.DocumentFile, categories: List<String>, sink: EventChannel.EventSink) {
        if (scanCancelled) return
        val files = dir.listFiles()
        for (file in files) {
            if (scanCancelled) return
            if (file.isDirectory) {
                traverseSafTree(file, categories, sink)
            } else {
                val name = file.name ?: continue
                val mimeType = file.type ?: getMimeTypeFromName(name)
                
                // Only files NOT indexed in MediaStore
                // We don't easily have absolute path, so we check if MediaStore has this display name or we just surface everything unindexed.
                // Since this is "deep scan", let's check signature headers.
                
                if (!matchesCategory(mimeType, categories)) continue
                
                val uri = file.uri
                
                // Check signature (JPEG FFD8FF, PNG 89504E47, MP4 66747970)
                var hasValidHeader = false
                try {
                    contentResolver.openInputStream(uri)?.use { stream ->
                        val header = ByteArray(8)
                        val bytesRead = stream.read(header)
                        if (bytesRead >= 3) {
                            if (header[0] == 0xFF.toByte() && header[1] == 0xD8.toByte() && header[2] == 0xFF.toByte()) {
                                hasValidHeader = true
                            } else if (bytesRead >= 8 && header[0] == 0x89.toByte() && header[1] == 0x50.toByte() && header[2] == 0x4E.toByte() && header[3] == 0x47.toByte()) {
                                hasValidHeader = true
                            } else if (bytesRead >= 8 && header[4] == 0x66.toByte() && header[5] == 0x74.toByte() && header[6] == 0x79.toByte() && header[7] == 0x70.toByte()) {
                                hasValidHeader = true // MP4 ftyp
                            }
                        }
                    }
                } catch (e: Exception) {}
                
                if (hasValidHeader) {
                    val resultMap: Map<String, Any?> = mapOf(
                        "uri" to uri.toString(),
                        "path" to "",
                        "name" to name,
                        "dateDeleted" to file.lastModified(),
                        "size" to file.length(),
                        "mimeType" to mimeType,
                        "source" to "saf",
                        "confidence" to 85,
                        "thumbnailPath" to "" // SAF thumbnails are trickier, leave empty for now
                    )
                    mainHandler.post { sink.success(resultMap) }
                }
            }
        }
    }

    // ──────────────────────────────────────────────────────────────────────────
    // MediaStore Trash scanner  (API 30+)
    // ──────────────────────────────────────────────────────────────────────────

    @RequiresApi(Build.VERSION_CODES.R)
    private fun scanMediaStoreTrash(
        categories: List<String>,
        sink: EventChannel.EventSink,
    ): Int {
        var count = 0
        val queryUri = MediaStore.Files.getContentUri(MediaStore.VOLUME_EXTERNAL)

        val projection = arrayOf(
            MediaStore.Files.FileColumns._ID,
            MediaStore.Files.FileColumns.DISPLAY_NAME,
            MediaStore.Files.FileColumns.DATE_EXPIRES,
            MediaStore.Files.FileColumns.SIZE,
            MediaStore.Files.FileColumns.MIME_TYPE,
        )

        // MATCH_ONLY is required to see trashed items via the content resolver.
        val queryArgs = Bundle().apply {
            putString(
                android.content.ContentResolver.QUERY_ARG_SQL_SELECTION,
                "${MediaStore.Files.FileColumns.IS_TRASHED} = 1",
            )
            putInt(MediaStore.QUERY_ARG_MATCH_TRASHED, MediaStore.MATCH_ONLY)
            putStringArray(
                android.content.ContentResolver.QUERY_ARG_SORT_COLUMNS,
                arrayOf(MediaStore.Files.FileColumns.DATE_EXPIRES),
            )
            putInt(
                android.content.ContentResolver.QUERY_ARG_SORT_DIRECTION,
                android.content.ContentResolver.QUERY_SORT_DIRECTION_DESCENDING,
            )
        }

        contentResolver.query(queryUri, projection, queryArgs, null)?.use { cursor ->
            val idCol = cursor.getColumnIndexOrThrow(MediaStore.Files.FileColumns._ID)
            val nameCol =
                cursor.getColumnIndexOrThrow(MediaStore.Files.FileColumns.DISPLAY_NAME)
            val expiresCol =
                cursor.getColumnIndexOrThrow(MediaStore.Files.FileColumns.DATE_EXPIRES)
            val sizeCol = cursor.getColumnIndexOrThrow(MediaStore.Files.FileColumns.SIZE)
            val mimeCol =
                cursor.getColumnIndexOrThrow(MediaStore.Files.FileColumns.MIME_TYPE)

            while (cursor.moveToNext() && !scanCancelled) {
                val mimeType = cursor.getString(mimeCol) ?: ""
                if (!matchesCategory(mimeType, categories)) continue

                val id = cursor.getLong(idCol)
                val name = cursor.getString(nameCol) ?: "Unknown"
                // DATE_EXPIRES is Unix seconds — convert to millis for Dart.
                val dateExpires = cursor.getLong(expiresCol) * 1000L
                val size = cursor.getLong(sizeCol)

                val contentUri =
                    ContentUris.withAppendedId(queryUri, id)

                val thumbnailPath =
                    generateUriThumbnail(contentUri, id.toString(), mimeType)

                val resultMap: Map<String, Any?> = mapOf(
                    "uri" to contentUri.toString(),
                    "path" to "",
                    "name" to name,
                    "dateDeleted" to dateExpires,
                    "size" to size,
                    "mimeType" to mimeType,
                    "source" to "trash",
                    "confidence" to 100,
                    "thumbnailPath" to (thumbnailPath ?: ""),
                )

                mainHandler.post { sink.success(resultMap) }
                count++
            }
        }
        return count
    }

    // ──────────────────────────────────────────────────────────────────────────
    // WhatsApp media scanner
    // ──────────────────────────────────────────────────────────────────────────

    private fun scanWhatsAppMedia(sink: EventChannel.EventSink): Int {
        var count = 0
        val sdcard = Environment.getExternalStorageDirectory()

        // Both old and new WhatsApp storage paths.
        val waRoots = listOf(
            File(sdcard, "WhatsApp/Media"),
            File(sdcard, "Android/media/com.whatsapp/WhatsApp/Media"),
        )

        val subFolders = listOf(
            "WhatsApp Images",
            "WhatsApp Images/Sent",
            "WhatsApp Video",
            "WhatsApp Video/Sent",
            "WhatsApp Audio",
            "WhatsApp Audio/Sent",
            "WhatsApp Documents",
            "WhatsApp Documents/Sent",
            ".Statuses",
        )

        val foundFiles = mutableListOf<File>()

        for (root in waRoots) {
            if (!root.exists()) continue
            for (sub in subFolders) {
                if (scanCancelled) return count
                val dir = File(root, sub)
                if (!dir.exists() || !dir.isDirectory) continue

                val files = dir.listFiles() ?: continue
                for (file in files) {
                    if (scanCancelled) return count
                    if (!file.isFile) continue
                    // Skip .nomedia sentinel files.
                    if (file.name.startsWith(".nomedia")) continue
                    foundFiles.add(file)
                }
            }
        }
        
        foundFiles.sortByDescending { it.lastModified() }

        for (file in foundFiles) {
            if (scanCancelled) return count
            val mimeType = getMimeTypeFromName(file.name)
            val filePath = file.absolutePath

            // Only surface files NOT indexed in MediaStore (gallery-invisible).
            if (isFileInMediaStore(filePath)) continue

            val thumbnailPath = generateFileThumbnail(filePath, mimeType)

            val resultMap: Map<String, Any?> = mapOf(
                "uri" to Uri.fromFile(file).toString(),
                "path" to filePath,
                "name" to file.name,
                "dateDeleted" to file.lastModified(),
                "size" to file.length(),
                "mimeType" to mimeType,
                "source" to "whatsapp",
                // Not technically deleted — confidence reflects that.
                "confidence" to 90,
                "thumbnailPath" to (thumbnailPath ?: ""),
            )

            mainHandler.post { sink.success(resultMap) }
            count++
        }
        return count
    }

    // ──────────────────────────────────────────────────────────────────────────
    // File recovery
    // ──────────────────────────────────────────────────────────────────────────

    private fun recoverFiles(items: List<Map<String, Any>>): List<Map<String, Any>> {
        val recoveredDir = File(
            Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS),
            "Recovered",
        )
        recoveredDir.mkdirs()

        return items.map { item ->
            try {
                val name = item["name"] as? String ?: "unknown"
                val uri = item["uri"] as? String ?: ""
                val filePath = item["path"] as? String ?: ""
                val source = item["source"] as? String ?: ""

                // Ensure unique filename if file already exists.
                val destFile = uniqueFile(recoveredDir, name)

                when {
                    source == "trash" && uri.isNotEmpty() -> {
                        // Read from MediaStore trash content URI.
                        val contentUri = Uri.parse(uri)
                        contentResolver.openInputStream(contentUri)?.use { input ->
                            FileOutputStream(destFile).use { input.copyTo(it) }
                        }
                        // Also untrash the original in MediaStore (bonus restore).
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                            try {
                                val values = ContentValues().apply {
                                    put(MediaStore.Files.FileColumns.IS_TRASHED, 0)
                                }
                                contentResolver.update(contentUri, values, null, null)
                            } catch (_: Exception) {
                                // Not fatal — we already copied the file.
                            }
                        }
                    }

                    filePath.isNotEmpty() -> {
                        // WhatsApp or file-path-based recovery.
                        File(filePath).copyTo(destFile, overwrite = true)
                    }

                    else -> throw IllegalArgumentException("No valid URI or path for $name")
                }

                mapOf(
                    "success" to true,
                    "name" to name,
                    "destPath" to destFile.absolutePath,
                )
            } catch (e: Exception) {
                mapOf(
                    "success" to false,
                    "name" to (item["name"] as? String ?: ""),
                    "destPath" to "",
                    "error" to (e.message ?: "Unknown error"),
                )
            }
        }
    }

    // ──────────────────────────────────────────────────────────────────────────
    // Vault helper
    // ──────────────────────────────────────────────────────────────────────────

    private fun getEncryptedPrefs(): android.content.SharedPreferences {
        val masterKey = androidx.security.crypto.MasterKey.Builder(this)
            .setKeyScheme(androidx.security.crypto.MasterKey.KeyScheme.AES256_GCM)
            .build()
        return androidx.security.crypto.EncryptedSharedPreferences.create(
            this,
            "vault_prefs",
            masterKey,
            androidx.security.crypto.EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            androidx.security.crypto.EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
        )
    }

    private fun decryptVaultFile(encryptedName: String): String? {
        try {
            val vaultDir = File(filesDir, "vault")
            val encryptedFile = File(vaultDir, encryptedName)
            if (!encryptedFile.exists()) return null

            val originalName = encryptedName.split("_", limit = 3).getOrNull(2) ?: "restored_file"
            val recoveredDir = File(
                Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS),
                "Recovered"
            )
            recoveredDir.mkdirs()
            val destFile = uniqueFile(recoveredDir, originalName)

            val masterKey = androidx.security.crypto.MasterKey.Builder(this)
                .setKeyScheme(androidx.security.crypto.MasterKey.KeyScheme.AES256_GCM)
                .build()

            val encFile = androidx.security.crypto.EncryptedFile.Builder(
                this,
                encryptedFile,
                masterKey,
                androidx.security.crypto.EncryptedFile.FileEncryptionScheme.AES256_GCM_HKDF_4KB
            ).build()

            encFile.openFileInput().use { input ->
                FileOutputStream(destFile).use { output ->
                    input.copyTo(output)
                }
            }

            return destFile.absolutePath
        } catch (e: Exception) {
            android.util.Log.e("MainActivity", "Decryption failed: ${e.message}")
            return null
        }
    }

    private fun decryptVaultFileToCache(encryptedName: String, isThumbnail: Boolean): String? {
        try {
            val vaultDir = File(filesDir, "vault")
            val targetName = if (isThumbnail) "thumb_$encryptedName" else encryptedName
            val encryptedFile = File(vaultDir, targetName)
            if (!encryptedFile.exists()) return null

            val originalName = encryptedName.split("_", limit = 3).getOrNull(2) ?: "cached_file"
            val destFile = File(cacheDir, "${if (isThumbnail) "thumb_" else ""}$originalName")

            val masterKey = androidx.security.crypto.MasterKey.Builder(this)
                .setKeyScheme(androidx.security.crypto.MasterKey.KeyScheme.AES256_GCM)
                .build()

            val encFile = androidx.security.crypto.EncryptedFile.Builder(
                this,
                encryptedFile,
                masterKey,
                androidx.security.crypto.EncryptedFile.FileEncryptionScheme.AES256_GCM_HKDF_4KB
            ).build()

            encFile.openFileInput().use { input ->
                FileOutputStream(destFile).use { output ->
                    input.copyTo(output)
                }
            }

            return destFile.absolutePath
        } catch (e: Exception) {
            android.util.Log.e("MainActivity", "Cache Decryption failed: ${e.message}")
            return null
        }
    }

    // ──────────────────────────────────────────────────────────────────────────
    // Open recovered file with Android intent
    // ──────────────────────────────────────────────────────────────────────────

    private fun openFileWithIntent(path: String) {
        try {
            val file = File(path)
            val mimeType = getMimeTypeFromName(file.name)
            val uri = FileProvider.getUriForFile(
                this,
                "${packageName}.fileprovider",
                file,
            )
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, mimeType)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(Intent.createChooser(intent, "Open with").apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            })
        } catch (e: Exception) {
            // Silently fail — Flutter side handles empty response.
        }
    }

    // ──────────────────────────────────────────────────────────────────────────
    // Thumbnail helpers
    // ──────────────────────────────────────────────────────────────────────────

    /** Generate thumbnail from a MediaStore content URI (trash items, API 29+). */
    private fun generateUriThumbnail(uri: Uri, id: String, mimeType: String): String? {
        if (!mimeType.startsWith("image/") && !mimeType.startsWith("video/")) return null
        return try {
            val thumbFile = File(cacheDir, "thumb_$id.jpg")
            if (thumbFile.exists()) return thumbFile.absolutePath
            val bitmap: Bitmap? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                contentResolver.loadThumbnail(uri, Size(320, 320), null)
            } else null
            bitmap?.let { writeThumbnail(it, thumbFile) }
        } catch (_: Exception) {
            null
        }
    }

    /** Generate thumbnail from a raw file path (WhatsApp files). */
    private fun generateFileThumbnail(filePath: String, mimeType: String): String? {
        if (!mimeType.startsWith("image/") && !mimeType.startsWith("video/")) return null
        return try {
            val id = filePath.hashCode().let {
                if (it < 0) "n${-it}" else "p$it"
            }
            val thumbFile = File(cacheDir, "thumb_$id.jpg")
            if (thumbFile.exists()) return thumbFile.absolutePath

            @Suppress("DEPRECATION")
            val bitmap: Bitmap? = if (mimeType.startsWith("video/")) {
                ThumbnailUtils.createVideoThumbnail(
                    filePath,
                    MediaStore.Images.Thumbnails.MINI_KIND,
                )
            } else {
                BitmapFactory.decodeFile(filePath)?.let { raw ->
                    val scale = minOf(320f / raw.width, 320f / raw.height)
                    if (scale < 1f)
                        Bitmap.createScaledBitmap(
                            raw,
                            (raw.width * scale).toInt(),
                            (raw.height * scale).toInt(),
                            true,
                        )
                    else raw
                }
            }
            bitmap?.let { writeThumbnail(it, thumbFile) }
        } catch (_: Exception) {
            null
        }
    }

    private fun writeThumbnail(bitmap: Bitmap, file: File): String? {
        return try {
            FileOutputStream(file).use { out ->
                bitmap.compress(Bitmap.CompressFormat.JPEG, 85, out)
            }
            file.absolutePath
        } catch (_: Exception) {
            null
        }
    }

    // ──────────────────────────────────────────────────────────────────────────
    // MediaStore helpers
    // ──────────────────────────────────────────────────────────────────────────

    /** Returns true if [filePath] is indexed in the MediaStore (not gallery-invisible). */
    private fun isFileInMediaStore(filePath: String): Boolean {
        val file = File(filePath)
        val projection = arrayOf(MediaStore.Files.FileColumns._ID)
        val selection = "${MediaStore.Files.FileColumns.DISPLAY_NAME} = ? AND ${MediaStore.Files.FileColumns.SIZE} = ?"
        return try {
            contentResolver.query(
                MediaStore.Files.getContentUri("external"),
                projection,
                selection,
                arrayOf(file.name, file.length().toString()),
                null,
            )?.use { it.count > 0 } ?: false
        } catch (_: Exception) {
            false
        }
    }

    /** Returns true if [mimeType] matches any of the selected [categories]. */
    private fun matchesCategory(mimeType: String, categories: List<String>): Boolean {
        if (categories.isEmpty()) return true
        return when {
            mimeType.startsWith("image/") && categories.contains("photos") -> true
            mimeType.startsWith("video/") && categories.contains("videos") -> true
            mimeType.startsWith("audio/") && categories.contains("audio") -> true
            (mimeType.startsWith("application/") || mimeType.startsWith("text/"))
                    && categories.contains("documents") -> true
            else -> false
        }
    }

    // ──────────────────────────────────────────────────────────────────────────
    // General helpers
    // ──────────────────────────────────────────────────────────────────────────

    private fun getMimeTypeFromName(name: String): String {
        val ext = name.substringAfterLast('.', "").lowercase()
        return when (ext) {
            "jpg", "jpeg" -> "image/jpeg"
            "png" -> "image/png"
            "gif" -> "image/gif"
            "webp" -> "image/webp"
            "heic", "heif" -> "image/heic"
            "mp4" -> "video/mp4"
            "mkv" -> "video/x-matroska"
            "avi" -> "video/avi"
            "mov" -> "video/quicktime"
            "3gp" -> "video/3gpp"
            "mp3" -> "audio/mpeg"
            "ogg" -> "audio/ogg"
            "opus" -> "audio/opus"
            "wav" -> "audio/wav"
            "aac" -> "audio/aac"
            "m4a" -> "audio/m4a"
            "pdf" -> "application/pdf"
            "doc" -> "application/msword"
            "docx" -> "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
            "xls" -> "application/vnd.ms-excel"
            "xlsx" -> "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
            "ppt" -> "application/vnd.ms-powerpoint"
            "pptx" -> "application/vnd.openxmlformats-officedocument.presentationml.presentation"
            "txt" -> "text/plain"
            "zip" -> "application/zip"
            else -> "application/octet-stream"
        }
    }

    /** Returns a File that doesn't yet exist, appending (1), (2), … as needed. */
    private fun uniqueFile(dir: File, name: String): File {
        val baseName = name.substringBeforeLast('.')
        val ext = name.substringAfterLast('.', "")
        var candidate = File(dir, name)
        var counter = 1
        while (candidate.exists()) {
            candidate = File(
                dir,
                if (ext.isEmpty()) "${baseName}_($counter)" else "${baseName}_($counter).$ext",
            )
            counter++
        }
        return candidate
    }

    // ──────────────────────────────────────────────────────────────────────────
    // Phase 6: Vault Sweep
    // ──────────────────────────────────────────────────────────────────────────

    private fun performVaultSweep(folders: List<String>) {
        if (folders.isEmpty()) return
        try {
            val projection = arrayOf(
                android.provider.MediaStore.Files.FileColumns._ID,
                android.provider.MediaStore.Files.FileColumns.DATA,
                android.provider.MediaStore.Files.FileColumns.DISPLAY_NAME,
                android.provider.MediaStore.Files.FileColumns.SIZE
            )

            val queryArgs = android.os.Bundle().apply {
                if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.R) {
                    putInt(android.provider.MediaStore.QUERY_ARG_MATCH_TRASHED, android.provider.MediaStore.MATCH_ONLY)
                }
            }

            val uri = android.provider.MediaStore.Files.getContentUri("external")
            
            contentResolver.query(uri, projection, queryArgs, null)?.use { cursor ->
                val idCol = cursor.getColumnIndexOrThrow(android.provider.MediaStore.Files.FileColumns._ID)
                val dataCol = cursor.getColumnIndexOrThrow(android.provider.MediaStore.Files.FileColumns.DATA)
                val nameCol = cursor.getColumnIndexOrThrow(android.provider.MediaStore.Files.FileColumns.DISPLAY_NAME)
                
                while (cursor.moveToNext()) {
                    val id = cursor.getLong(idCol)
                    val filePath = cursor.getString(dataCol)
                    val fileName = cursor.getString(nameCol)
                    
                    if (filePath == null || fileName == null) continue
                    
                    val isMonitored = folders.any { folder ->
                        filePath.startsWith(folder, ignoreCase = true)
                    }
                    
                    if (isMonitored) {
                        val fileUri = android.content.ContentUris.withAppendedId(uri, id)
                        backupToVault(fileUri, fileName, filePath)
                    }
                }
            }
        } catch (e: Exception) {
            android.util.Log.e("Sweep", "Sweep error: ${e.message}")
        }
    }

    private fun backupToVault(sourceUri: android.net.Uri, originalName: String, originalPath: String) {
        try {
            val vaultDir = File(filesDir, "vault")
            if (!vaultDir.exists()) vaultDir.mkdirs()

            // Check if already backed up recently (could check by originalName)
            val exists = vaultDir.listFiles()?.any { it.name.endsWith("_$originalName") } == true
            if (exists) return

            val timestamp = System.currentTimeMillis()
            val destFileName = "enc_${timestamp}_$originalName"
            val destFile = File(vaultDir, destFileName)

            val masterKey = androidx.security.crypto.MasterKey.Builder(this)
                .setKeyScheme(androidx.security.crypto.MasterKey.KeyScheme.AES256_GCM)
                .build()

            val encryptedFile = androidx.security.crypto.EncryptedFile.Builder(
                this,
                destFile,
                masterKey,
                androidx.security.crypto.EncryptedFile.FileEncryptionScheme.AES256_GCM_HKDF_4KB
            ).build()

            contentResolver.openInputStream(sourceUri)?.use { input ->
                encryptedFile.openFileOutput().use { output ->
                    input.copyTo(output)
                }
            }
        } catch (e: Exception) {
            android.util.Log.e("Sweep", "Failed to backup: ${e.message}")
        }
    }
}
