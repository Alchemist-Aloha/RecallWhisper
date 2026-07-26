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
import androidx.room.migration.Migration
import androidx.sqlite.db.SupportSQLiteDatabase

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
    val sha256Plaintext: String?,
    val encryptionVersion: Int,
    val wrappedKey: String?,
    val wrapNonce: String?,
    val fileNonce: String?,
    val codec: String = "pcm16",
    val sampleRateHz: Int = 16_000,
    val sampleCount: Long,
    val durationMs: Long,
    val continuationGroupId: String?,
    val continuationIndex: Int,
    val overlapMs: Int,
    val uploadState: String = "LOCAL",
    val serverState: String = "UNKNOWN",
    val transcriptText: String? = null,
    val rawTranscriptJson: String? = null,
    val summaryJson: String? = null,
    val processingError: String? = null,
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

    @Query("SELECT * FROM capture_segment WHERE uploadState IN ('LOCAL', 'QUEUED', 'RETRY_WAIT') ORDER BY sequenceNumber LIMIT :limit")
    fun pending(limit: Int = 20): List<CaptureSegment>

    @Query("SELECT * FROM capture_segment WHERE segmentId = :id")
    fun byId(id: String): CaptureSegment?

    @Query("UPDATE capture_segment SET uploadState = :state, serverState = :serverState, updatedAtMs = :now WHERE segmentId = :id")
    fun updateState(id: String, state: String, serverState: String, now: Long)

    @Query("""UPDATE capture_segment SET uploadState = :state, serverState = :serverState,
        transcriptText = :transcript, rawTranscriptJson = :rawTranscript,
        summaryJson = :summary, processingError = :error, updatedAtMs = :now
        WHERE segmentId = :id""")
    fun updateProcessing(
        id: String,
        state: String,
        serverState: String,
        transcript: String?,
        rawTranscript: String?,
        summary: String?,
        error: String?,
        now: Long,
    )

    @Query("""SELECT * FROM capture_segment
        WHERE transcriptText LIKE '%' || :query || '%'
           OR summaryJson LIKE '%' || :query || '%'
        ORDER BY startedAtUtcMs DESC LIMIT 100""")
    fun search(query: String): List<CaptureSegment>

    @Query("SELECT * FROM capture_segment ORDER BY startedAtUtcMs")
    fun all(): List<CaptureSegment>

    @Query("DELETE FROM capture_segment WHERE segmentId = :id")
    fun delete(id: String)
}

@Database(entities = [CaptureSegment::class], version = 3, exportSchema = false)
abstract class RecorderDatabase : RoomDatabase() {
    abstract fun segments(): SegmentDao

    companion object {
        @Volatile private var instance: RecorderDatabase? = null

        fun get(context: Context): RecorderDatabase = instance ?: synchronized(this) {
            instance ?: Room.databaseBuilder(
                context.applicationContext,
                RecorderDatabase::class.java,
                "recorder.db",
            ).addMigrations(MIGRATION_1_2, MIGRATION_2_3).build().also { instance = it }
        }

        private val MIGRATION_1_2 = object : Migration(1, 2) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL("ALTER TABLE capture_segment ADD COLUMN sha256Plaintext TEXT")
                db.execSQL("ALTER TABLE capture_segment ADD COLUMN encryptionVersion INTEGER NOT NULL DEFAULT 0")
                db.execSQL("ALTER TABLE capture_segment ADD COLUMN wrappedKey TEXT")
                db.execSQL("ALTER TABLE capture_segment ADD COLUMN wrapNonce TEXT")
                db.execSQL("ALTER TABLE capture_segment ADD COLUMN fileNonce TEXT")
            }
        }

        private val MIGRATION_2_3 = object : Migration(2, 3) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL("ALTER TABLE capture_segment ADD COLUMN transcriptText TEXT")
                db.execSQL("ALTER TABLE capture_segment ADD COLUMN rawTranscriptJson TEXT")
                db.execSQL("ALTER TABLE capture_segment ADD COLUMN summaryJson TEXT")
                db.execSQL("ALTER TABLE capture_segment ADD COLUMN processingError TEXT")
            }
        }
    }
}
