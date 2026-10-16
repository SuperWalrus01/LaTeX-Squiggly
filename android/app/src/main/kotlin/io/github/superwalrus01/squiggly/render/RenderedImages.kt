package io.github.superwalrus01.squiggly.render

import android.content.ContentProvider
import android.content.ContentValues
import android.content.Context
import android.database.Cursor
import android.database.MatrixCursor
import android.net.Uri
import android.os.ParcelFileDescriptor
import android.os.SystemClock
import android.provider.OpenableColumns
import java.io.File
import java.io.FileNotFoundException

/**
 * The latest rendered image, kept in the app's cache so the clipboard and the
 * keyboard can hand it to other apps by URI.
 *
 * Only the newest image is kept: each copy replaces the last, under a new
 * name, so an app that caches by URI never shows an older equation.
 */
object RenderedImages {

    /** An image waiting to be inserted by the keyboard. */
    class Pending(
        val uri: Uri,
        /** The LaTeX the keyboard took from the text box, which the image replaces. */
        val replaces: String?,
        val description: String,
        private val madeAt: Long = SystemClock.elapsedRealtime(),
    ) {
        // Long enough to go back to the app and tap Insert, short enough that
        // an image copied this morning is not offered in a different chat.
        val isFresh: Boolean get() = SystemClock.elapsedRealtime() - madeAt < 5 * 60 * 1000
    }

    @Volatile
    var pending: Pending? = null
        private set

    fun authority(context: Context) = "${context.packageName}.images"

    private fun folder(context: Context) = File(context.cacheDir, "images").apply { mkdirs() }

    /** Writes the PNG and makes it the pending image. */
    fun store(context: Context, png: ByteArray, latex: String, replaces: String?): Uri {
        val folder = folder(context)
        folder.listFiles()?.forEach { it.delete() }
        val name = "equation-${System.currentTimeMillis()}.png"
        File(folder, name).writeBytes(png)
        val uri = Uri.Builder().scheme("content").authority(authority(context)).appendPath(name).build()
        pending = Pending(uri, replaces, latex)
        return uri
    }

    fun clearPending() {
        pending = null
    }

    internal fun file(context: Context, uri: Uri): File {
        val name = uri.lastPathSegment ?: throw FileNotFoundException("No image named.")
        // Only names this object wrote, so no path can reach outside the folder.
        if (!Regex("equation-[0-9]+\\.png").matches(name)) throw FileNotFoundException(name)
        val file = File(folder(context), name)
        if (!file.isFile) throw FileNotFoundException(name)
        return file
    }
}

/** Serves the rendered images, read only, to apps granted a URI. */
class ImageProvider : ContentProvider() {

    override fun onCreate() = true

    override fun getType(uri: Uri) = "image/png"

    override fun openFile(uri: Uri, mode: String): ParcelFileDescriptor {
        if (mode != "r") throw SecurityException("Rendered images are read only.")
        return ParcelFileDescriptor.open(RenderedImages.file(context!!, uri), ParcelFileDescriptor.MODE_READ_ONLY)
    }

    // Many apps ask for the name and size before reading an image.
    override fun query(
        uri: Uri, projection: Array<out String>?, selection: String?,
        selectionArgs: Array<out String>?, sortOrder: String?,
    ): Cursor {
        val file = RenderedImages.file(context!!, uri)
        val columns = projection ?: arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE)
        val row = columns.map {
            when (it) {
                OpenableColumns.DISPLAY_NAME -> "equation.png"
                OpenableColumns.SIZE -> file.length()
                else -> null
            }
        }
        return MatrixCursor(columns, 1).apply { addRow(row) }
    }

    override fun insert(uri: Uri, values: ContentValues?): Uri? = null
    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?) = 0
    override fun update(uri: Uri, values: ContentValues?, selection: String?, selectionArgs: Array<out String>?) = 0
}
