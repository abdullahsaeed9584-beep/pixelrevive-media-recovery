package com.nowdigiverse.media_recovery

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import android.provider.BaseColumns

class ProtectionDatabaseHelper(context: Context) : SQLiteOpenHelper(context, DATABASE_NAME, null, DATABASE_VERSION) {

    companion object {
        const val DATABASE_VERSION = 1
        const val DATABASE_NAME = "ProtectionCache.db"

        const val TABLE_NAME = "file_cache"
        const val COLUMN_FILE_ID = "file_id" // Maps to MediaStore _ID
        const val COLUMN_ORIGINAL_FOLDER = "original_folder"
    }

    private val SQL_CREATE_ENTRIES =
        "CREATE TABLE $TABLE_NAME (" +
                "${BaseColumns._ID} INTEGER PRIMARY KEY," +
                "$COLUMN_FILE_ID INTEGER UNIQUE," +
                "$COLUMN_ORIGINAL_FOLDER TEXT)"

    private val SQL_DELETE_ENTRIES = "DROP TABLE IF EXISTS $TABLE_NAME"

    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL(SQL_CREATE_ENTRIES)
        // Add index on file_id for fast lookups
        db.execSQL("CREATE INDEX idx_file_id ON $TABLE_NAME($COLUMN_FILE_ID)")
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        db.execSQL(SQL_DELETE_ENTRIES)
        onCreate(db)
    }

    fun upsertFileCache(fileId: Long, originalFolder: String) {
        val db = writableDatabase
        val values = ContentValues().apply {
            put(COLUMN_FILE_ID, fileId)
            put(COLUMN_ORIGINAL_FOLDER, originalFolder)
        }
        db.insertWithOnConflict(TABLE_NAME, null, values, SQLiteDatabase.CONFLICT_REPLACE)
    }

    fun getOriginalFolder(fileId: Long): String? {
        val db = readableDatabase
        val projection = arrayOf(COLUMN_ORIGINAL_FOLDER)
        val selection = "$COLUMN_FILE_ID = ?"
        val selectionArgs = arrayOf(fileId.toString())

        var originalFolder: String? = null
        db.query(TABLE_NAME, projection, selection, selectionArgs, null, null, null).use { cursor ->
            if (cursor.moveToFirst()) {
                originalFolder = cursor.getString(0)
            }
        }
        return originalFolder
    }

    fun deleteFileCache(fileId: Long) {
        val db = writableDatabase
        val selection = "$COLUMN_FILE_ID = ?"
        val selectionArgs = arrayOf(fileId.toString())
        db.delete(TABLE_NAME, selection, selectionArgs)
    }
}
