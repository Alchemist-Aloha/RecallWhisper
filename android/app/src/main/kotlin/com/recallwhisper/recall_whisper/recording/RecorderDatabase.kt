package com.recallwhisper.recall_whisper.recording

import android.content.Context
import androidx.room.Dao
import androidx.room.Database
import androidx.room.Entity
import androidx.room.Insert
import androidx.room.PrimaryKey
import androidx.room.Query
import androidx.room.Room
import androidx.room.RoomDatabase

@Entity(tableName = "capture_segment")
data class CaptureSegment(
    @PrimaryKey val segmentId: String,
    val deviceId: String,
    val bootId: String,
    val sequenceNumber: Long,
    val startedAtUtcMs: Long,
    val endedAtUtcMs: Long,
    val elapsedStartNs: Long,
    val elapsedEndNs: Long,
    val timezoneName: String,
    val utcOffsetMinutes: Int,
    val filePath: String,
    val fileSizeBytes: Long,
    val sha256: String,
    val codec: String = "pcm16",
    val sampleRateHz: Int = 16_000,
    val sampleCount: Long,
    val durationMs: Long,
    val continuationGroupId: String?,
    val continuationIndex: Int,
    val overlapMs: Int,
    val uploadState: String = "LOCAL",
    val serverState: String = "UNKNOWN",
    val createdAtMs: Long,
    val updatedAtMs: Long,
)

@Dao
interface SegmentDao {
    @Insert
    fun insert(segment: CaptureSegment)

    @Query("SELECT * FROM capture_segment ORDER BY startedAtUtcMs DESC LIMIT 200")
    fun recent(): List<CaptureSegment>

    @Query("SELECT COALESCE(MAX(sequenceNumber), 0) + 1 FROM capture_segment")
    fun nextSequence(): Long
}

@Database(entities = [CaptureSegment::class], version = 1, exportSchema = false)
abstract class RecorderDatabase : RoomDatabase() {
    abstract fun segments(): SegmentDao

    companion object {
        @Volatile private var instance: RecorderDatabase? = null

        fun get(context: Context): RecorderDatabase = instance ?: synchronized(this) {
            instance ?: Room.databaseBuilder(
                context.applicationContext,
                RecorderDatabase::class.java,
                "recorder.db",
            ).build().also { instance = it }
        }
    }
}
