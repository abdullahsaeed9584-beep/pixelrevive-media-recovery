package com.nowdigiverse.media_recovery

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.database.ContentObserver
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.provider.MediaStore
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.security.crypto.EncryptedFile
import androidx.security.crypto.MasterKey
import java.io.File
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

class ProtectionService : Service() {

    companion object {
        private const val TAG = "ProtectionService"
        private const val NOTIFICATION_CHANNEL_ID = "protection_channel"
        private const val ONGOING_NOTIFICATION_ID = 1001

        var monitoredFolders: List<String> = emptyList()
    }

    private val executor: ExecutorService = Executors.newSingleThreadExecutor()
    private lateinit var mediaObserver: ContentObserver
    private lateinit var dbHelper: ProtectionDatabaseHelper

    override fun onCreate() {
        super.onCreate()
        
        dbHelper = ProtectionDatabaseHelper(this)
        
        createNotificationChannel()
        val notification = NotificationCompat.Builder(this, NOTIFICATION_CHANNEL_ID)
            .setContentTitle("Protection Mode Active")
            .setContentText("Monitoring for deleted files")
            .setSmallIcon(android.R.drawable.ic_menu_save)
            .setPriority(NotificationCompat.PRIORITY_MIN)
            .build()
        startForeground(ONGOING_NOTIFICATION_ID, notification)

        mediaObserver = object : ContentObserver(Handler(Looper.getMainLooper())) {
            override fun onChange(selfChange: Boolean, uri: Uri?) {
                super.onChange(selfChange, uri)
                Log.d(TAG, "ContentObserver onChange fired! selfChange=$selfChange, uri=$uri")
                uri?.let {
                    executor.execute { handleMediaChange(it) }
                } ?: run {
                    Log.d(TAG, "onChange received null URI, ignoring.")
                }
            }
        }

        contentResolver.registerContentObserver(
            MediaStore.Files.getContentUri("external"),
            true,
            mediaObserver
        )
    }

    private fun handleMediaChange(uri: Uri) {
        Log.d(TAG, "handleMediaChange triggered for URI: $uri")
        try {
            val projection = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                arrayOf(
                    MediaStore.Files.FileColumns.DATA,
                    MediaStore.Files.FileColumns.DISPLAY_NAME,
                    MediaStore.Files.FileColumns.SIZE,
                    MediaStore.Files.FileColumns.RELATIVE_PATH,
                    MediaStore.Files.FileColumns.BUCKET_DISPLAY_NAME
                )
            } else {
                arrayOf(
                    MediaStore.Files.FileColumns.DATA,
                    MediaStore.Files.FileColumns.DISPLAY_NAME,
                    MediaStore.Files.FileColumns.SIZE
                )
            }

            var filePath: String? = null
            var fileName: String? = null
            var relativePath: String? = null
            var bucketName: String? = null

            val queryArgs = android.os.Bundle().apply {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    putInt(MediaStore.QUERY_ARG_MATCH_TRASHED, MediaStore.MATCH_ONLY)
                }
            }

            contentResolver.query(uri, projection, queryArgs, null)?.use { cursor ->
                if (cursor.moveToFirst()) {
                    filePath = cursor.getString(0)
                    fileName = cursor.getString(1)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        relativePath = cursor.getString(3)
                        bucketName = cursor.getString(4)
                    }
                    Log.d(TAG, "Found trashed file: $fileName at $filePath")
                    Log.d(TAG, "Relative path: $relativePath, Bucket: $bucketName")
                }
            }

            if (filePath == null) {
                contentResolver.query(uri, projection, null, null, null)?.use { cursor ->
                    if (cursor.moveToFirst()) {
                        filePath = cursor.getString(0)
                        fileName = cursor.getString(1)
                    }
                }
            }

            if (filePath == null || fileName == null) {
                // Ignore nulls silently to debounce redundant generic URI callbacks
                return
            }

            Log.d(TAG, "Path before check: $filePath")
            
            var originalFolder = ""
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q && !relativePath.isNullOrBlank()) {
                originalFolder = relativePath!!
            } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q && !bucketName.isNullOrBlank()) {
                originalFolder = bucketName!!
            } else {
                originalFolder = filePath!!
                // Android 11+ Trash often relocates files to hidden trash directories.
                // Strip these prefixes as a fallback.
                val trashPrefixes = listOf("/.trash-storage/", "/.trashBin/", "/.Trash/", "/.trashed-")
                for (prefix in trashPrefixes) {
                    if (originalFolder.contains(prefix)) {
                        originalFolder = originalFolder.replace(prefix, "/")
                    }
                }
            }
            
            Log.d(TAG, "Resolved original folder string (before cache check): $originalFolder")
            Log.d(TAG, "Monitored folders list: $monitoredFolders")

            var shouldBackup = false
            var isTrashed = false
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                val trashProj = arrayOf(MediaStore.Files.FileColumns.IS_TRASHED, MediaStore.Files.FileColumns._ID)
                contentResolver.query(uri, trashProj, queryArgs, null)?.use { c ->
                    if (c.moveToFirst()) {
                        isTrashed = c.getInt(0) == 1
                        val fileId = c.getLong(1)
                        
                        // Fix for OEM Galleries that do manual file moves to .trashBin instead of MediaStore trash
                        if (!isTrashed && filePath != null) {
                            val trashPrefixes = listOf("/.trash-storage/", "/.trashBin/", "/.Trash/", "/.trashed-")
                            if (trashPrefixes.any { filePath!!.contains(it) }) {
                                Log.d(TAG, "File IS_TRASHED is 0, but path implies OEM trash directory. Forcing TRASHED flow.")
                                isTrashed = true
                            }
                        }

                        if (isTrashed) {
                            Log.d(TAG, "File is TRASHED. Looking up original path in cache for ID: $fileId")
                            val cachedOriginalPath = dbHelper.getOriginalFolder(fileId)
                            if (cachedOriginalPath != null) {
                                originalFolder = cachedOriginalPath
                                Log.d(TAG, "Found in cache! Original Path: $originalFolder")
                                
                                val isMonitored = monitoredFolders.any { folder ->
                                    originalFolder.contains(folder, ignoreCase = true) || 
                                    originalFolder.contains("/$folder/", ignoreCase = true)
                                }
                                
                                Log.d(TAG, "Is cached original path monitored? $isMonitored")
                                if (isMonitored) {
                                    shouldBackup = true
                                }
                            } else {
                                Log.d(TAG, "Not found in cache. Cannot backup.")
                            }
                        } else {
                            Log.d(TAG, "File is NOT trashed. Updating cache...")
                            if (filePath != null) {
                                val isMonitored = monitoredFolders.any { folder ->
                                    filePath!!.contains(folder, ignoreCase = true) || filePath!!.contains("/$folder/", ignoreCase = true)
                                }
                                if (isMonitored) {
                                    dbHelper.upsertFileCache(fileId, filePath!!)
                                    Log.d(TAG, "Updated cache for ID $fileId: $filePath")
                                }
                            }
                        }
                    }
                }
            }

            if (!isTrashed) {
                // If not trashed, we already updated the cache above, nothing else to do.
                return
            }

            if (shouldBackup) {
                backupToVault(uri, fileName!!, filePath!!)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error in handleMediaChange: ${e.message}")
        }
    }

    private fun backupToVault(sourceUri: Uri, originalName: String, originalPath: String) {
        try {
            Log.d(TAG, "Starting vault backup process for $originalName")
            val vaultDir = File(filesDir, "vault")
            if (!vaultDir.exists()) vaultDir.mkdirs()

            Log.d(TAG, "Vault directory resolved to: ${vaultDir.absolutePath}")

            val timestamp = System.currentTimeMillis()
            val destFileName = "enc_${timestamp}_$originalName"
            val destFile = File(vaultDir, destFileName)
            
            Log.d(TAG, "Destination encrypted file path: ${destFile.absolutePath}")

            Log.d(TAG, "Building MasterKey...")
            val masterKey = MasterKey.Builder(this)
                .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
                .build()

            Log.d(TAG, "Building EncryptedFile...")
            val encryptedFile = EncryptedFile.Builder(
                this,
                destFile,
                masterKey,
                EncryptedFile.FileEncryptionScheme.AES256_GCM_HKDF_4KB
            ).build()

            Log.d(TAG, "Opening InputStream from URI and writing to EncryptedFile...")
            contentResolver.openInputStream(sourceUri)?.use { input ->
                encryptedFile.openFileOutput().use { output ->
                    input.copyTo(output)
                }
            }
            Log.d(TAG, "Encryption and copy completed successfully for $destFileName")

            // Thumbnail generation and encryption
            try {
                val mimeType = contentResolver.getType(sourceUri)
                var bitmap: android.graphics.Bitmap? = null
                
                if (mimeType?.startsWith("image/") == true || mimeType?.startsWith("video/") == true) {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        bitmap = contentResolver.loadThumbnail(sourceUri, android.util.Size(256, 256), null)
                    }
                }
                
                if (bitmap != null) {
                    val thumbFileName = "thumb_$destFileName"
                    val thumbFile = File(vaultDir, thumbFileName)
                    val encThumb = EncryptedFile.Builder(
                        this,
                        thumbFile,
                        masterKey,
                        EncryptedFile.FileEncryptionScheme.AES256_GCM_HKDF_4KB
                    ).build()
                    
                    encThumb.openFileOutput().use { out ->
                        bitmap.compress(android.graphics.Bitmap.CompressFormat.JPEG, 80, out)
                    }
                    Log.d(TAG, "Thumbnail generated and encrypted successfully.")
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to generate thumbnail for $originalName", e)
            }

            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val alert = NotificationCompat.Builder(this, NOTIFICATION_CHANNEL_ID)
                .setContentTitle("File Protected")
                .setContentText(originalName)
                .setSmallIcon(android.R.drawable.ic_menu_save)
                .setAutoCancel(true)
                .build()

            notificationManager.notify(destFileName.hashCode(), alert)

        } catch (e: Exception) {
            Log.e(TAG, "Failed to backup to vault! Exception: ${e.javaClass.simpleName}, Message: ${e.message}")
            Log.e(TAG, "Full stack trace:", e)
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                NOTIFICATION_CHANNEL_ID,
                "Protection Service",
                NotificationManager.IMPORTANCE_MIN
            )
            val manager = getSystemService(NotificationManager::class.java)
            manager?.createNotificationChannel(channel)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val folders = intent?.getStringArrayListExtra("folders")
        if (folders != null) {
            monitoredFolders = folders
            executor.execute { syncMonitoredFiles() }
        }
        return START_STICKY
    }

    @Volatile
    private var isSyncing = false

    private fun syncMonitoredFiles() {
        if (isSyncing) {
            Log.d(TAG, "syncMonitoredFiles: Sync already in progress, skipping duplicate request.")
            return
        }
        isSyncing = true
        Log.d(TAG, "Starting syncMonitoredFiles() for SQLite cache...")
        try {
            if (monitoredFolders.isEmpty()) return
            
            val projection = arrayOf(
                MediaStore.Files.FileColumns._ID,
                MediaStore.Files.FileColumns.DATA
            )
            
            // Match only non-trashed files
            val queryArgs = android.os.Bundle().apply {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    putInt(MediaStore.QUERY_ARG_MATCH_TRASHED, MediaStore.MATCH_EXCLUDE)
                }
            }

            contentResolver.query(
                MediaStore.Files.getContentUri("external"),
                projection,
                queryArgs,
                null
            )?.use { cursor ->
                val idCol = cursor.getColumnIndexOrThrow(MediaStore.Files.FileColumns._ID)
                val dataCol = cursor.getColumnIndexOrThrow(MediaStore.Files.FileColumns.DATA)
                
                var syncedCount = 0
                while (cursor.moveToNext()) {
                    val id = cursor.getLong(idCol)
                    val path = cursor.getString(dataCol) ?: continue
                    
                    val isMonitored = monitoredFolders.any { folder ->
                        path.contains(folder, ignoreCase = true) || path.contains("/$folder/", ignoreCase = true)
                    }
                    if (isMonitored) {
                        dbHelper.upsertFileCache(id, path)
                        syncedCount++
                    }
                }
                Log.d(TAG, "Finished syncMonitoredFiles(): Cached $syncedCount monitored files.")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error in syncMonitoredFiles: ${e.message}")
        } finally {
            isSyncing = false
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        super.onDestroy()
        contentResolver.unregisterContentObserver(mediaObserver)
        executor.shutdown()
    }
}
