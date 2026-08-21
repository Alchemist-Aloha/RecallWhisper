package com.recallwhisper.recall_whisper.recording

import android.content.Context
import androidx.room.Dao
import androidx.room.Database
import androidx.room.Entity
import androidx.room.Insert
import androidx.room.OnConflictStrategy
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
    val transcriptionState: String = "PENDING",
    val summaryState: String = "WAITING",
    val transcriptionError: String? = null,
    val summaryError: String? = null,
    val createdAtMs: Long,
    val updatedAtMs: Long,
)

@Entity(tableName = "topic")
data class Topic(
    @PrimaryKey val topicId: String,
    val canonicalTitle: String,
    val description: String,
    val currentSummary: String,
    val topicPathJson: String,
    val firstSeenUtcMs: Long,
    val lastSeenUtcMs: Long,
)

@Entity(tableName = "topic_episode")
data class TopicEpisode(
    @PrimaryKey val episodeId: String,
    val topicId: String,
    val startedAtUtcMs: Long,
    val endedAtUtcMs: Long,
    val localTitle: String,
    val summaryJson: String,
    val keywordsJson: String,
    val secondaryTopicsJson: String,
    val segmentationStatus: String = "provisional",
)

@Entity(
    tableName = "episode_segment",
    primaryKeys = ["episodeId", "segmentId"],
)
data class EpisodeSegment(
    val episodeId: String,
    val segmentId: String,
    val sequenceNumber: Int,
)

@Entity(tableName = "todo_item")
data class TodoItem(
    @PrimaryKey val todoId: String,
    val text: String,
    val completed: Boolean = false,
    val createdAtUtcMs: Long,
    val completedAtUtcMs: Long? = null,
    val sourceEpisodeId: String? = null,
    val sourceTitle: String? = null,
)

@Dao
interface SegmentDao {
    @Insert
    fun insert(segment: CaptureSegment)

    @Query("SELECT * FROM capture_segment ORDER BY startedAtUtcMs DESC LIMIT 200")
    fun recent(): List<CaptureSegment>

    @Query("SELECT COALESCE(MAX(sequenceNumber), 0) + 1 FROM capture_segment")
    fun nextSequence(): Long

    @Query("""SELECT * FROM capture_segment
        WHERE transcriptText IS NULL
          AND transcriptionState IN ('PENDING', 'PROCESSING', 'RETRY_WAIT')
        ORDER BY sequenceNumber LIMIT :limit""")
    fun pendingTranscription(limit: Int = 20): List<CaptureSegment>

    @Query("""SELECT capture_segment.* FROM capture_segment
        LEFT JOIN episode_segment
          ON episode_segment.segmentId = capture_segment.segmentId
        WHERE capture_segment.transcriptText IS NOT NULL
          AND episode_segment.segmentId IS NULL
        ORDER BY capture_segment.sequenceNumber LIMIT :limit""")
    fun pendingSummary(limit: Int = 200): List<CaptureSegment>

    @Query("SELECT * FROM topic ORDER BY lastSeenUtcMs DESC LIMIT :limit")
    fun recentTopics(limit: Int = 50): List<Topic>

    @Query("SELECT * FROM topic_episode ORDER BY startedAtUtcMs DESC LIMIT :limit")
    fun recentEpisodes(limit: Int = 200): List<TopicEpisode>

    @Query("SELECT * FROM episode_segment ORDER BY episodeId, sequenceNumber")
    fun episodeSegments(): List<EpisodeSegment>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    fun saveTopic(topic: Topic)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    fun saveEpisode(episode: TopicEpisode)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    fun saveEpisodeSegments(segments: List<EpisodeSegment>)

    @Query("SELECT * FROM capture_segment WHERE segmentId = :id")
    fun byId(id: String): CaptureSegment?

    @Query("""UPDATE capture_segment SET uploadState = :uploadState,
        serverState = :serverState, transcriptText = :transcript,
        rawTranscriptJson = :rawTranscript, processingError = :error,
        transcriptionState = :state, transcriptionError = :error,
        summaryState = CASE
            WHEN :state = 'COMPLETE' THEN 'PENDING'
            WHEN :state = 'EMPTY' THEN 'EMPTY'
            ELSE summaryState
        END,
        updatedAtMs = :now WHERE segmentId = :id""")
    fun updateTranscription(
        id: String,
        state: String,
        uploadState: String,
        serverState: String,
        transcript: String?,
        rawTranscript: String?,
        error: String?,
        now: Long,
    )

    @Query("""UPDATE capture_segment SET serverState = :serverState,
        summaryJson = :summary, processingError = :error,
        summaryState = :state, summaryError = :error,
        updatedAtMs = :now WHERE segmentId = :id""")
    fun updateSummary(
        id: String,
        state: String,
        serverState: String,
        summary: String?,
        error: String?,
        now: Long,
    )

    @Query("""UPDATE capture_segment SET uploadState = 'PENDING',
        serverState = 'QUEUED', processingError = NULL,
        transcriptionState = 'PENDING', transcriptionError = NULL,
        updatedAtMs = :now WHERE segmentId = :id AND transcriptText IS NULL
        AND transcriptionState IN ('FAILED', 'RETRY_WAIT')""")
    fun retryTranscription(id: String, now: Long): Int

    @Query("""UPDATE capture_segment SET serverState = 'QUEUED',
        processingError = NULL, summaryState = 'PENDING', summaryError = NULL,
        updatedAtMs = :now WHERE segmentId = :id AND transcriptText IS NOT NULL
        AND summaryState IN ('FAILED', 'RETRY_WAIT')""")
    fun retrySummary(id: String, now: Long): Int

    @Query("""UPDATE capture_segment SET uploadState = 'PENDING',
        serverState = 'QUEUED', processingError = NULL,
        transcriptionState = 'PENDING', transcriptionError = NULL,
        updatedAtMs = :now WHERE transcriptText IS NULL
        AND transcriptionState IN ('FAILED', 'RETRY_WAIT')""")
    fun retryFailedTranscriptions(now: Long): Int

    @Query("""UPDATE capture_segment SET serverState = 'QUEUED',
        processingError = NULL, summaryState = 'PENDING', summaryError = NULL,
        updatedAtMs = :now WHERE transcriptText IS NOT NULL
        AND summaryState IN ('FAILED', 'RETRY_WAIT')""")
    fun retryFailedSummaries(now: Long): Int

    @Query("""UPDATE capture_segment SET uploadState = 'PENDING',
        serverState = 'QUEUED', processingError = NULL,
        transcriptionState = 'PENDING', transcriptionError = NULL,
        updatedAtMs = :now WHERE transcriptionState = 'PROCESSING'""")
    fun stopTranscription(now: Long): Int

    @Query("""UPDATE capture_segment SET serverState = 'QUEUED',
        processingError = NULL, summaryState = 'PENDING', summaryError = NULL,
        updatedAtMs = :now
        WHERE summaryState = 'PROCESSING'""")
    fun stopSummary(now: Long): Int

    @Query("""SELECT * FROM capture_segment
        WHERE transcriptText LIKE '%' || :query || '%'
           OR summaryJson LIKE '%' || :query || '%'
        ORDER BY startedAtUtcMs DESC LIMIT 100""")
    fun search(query: String): List<CaptureSegment>

    @Query("SELECT * FROM capture_segment ORDER BY startedAtUtcMs")
    fun all(): List<CaptureSegment>

    @Query("DELETE FROM capture_segment WHERE segmentId = :id")
    fun delete(id: String)

    @Query("SELECT * FROM episode_segment WHERE episodeId = :episodeId")
    fun episodeSegments(episodeId: String): List<EpisodeSegment>

    @Query("DELETE FROM episode_segment WHERE episodeId = :episodeId")
    fun deleteEpisodeSegments(episodeId: String)

    @Query("DELETE FROM topic_episode WHERE episodeId = :episodeId")
    fun deleteEpisode(episodeId: String)

    @Query(
        """DELETE FROM topic WHERE topicId NOT IN
        (SELECT DISTINCT topicId FROM topic_episode)""",
    )
    fun deleteOrphanTopics()

    @Query("SELECT * FROM todo_item ORDER BY completed ASC, createdAtUtcMs DESC")
    fun todos(): List<TodoItem>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    fun insertTodo(todo: TodoItem)

    @Query("""UPDATE todo_item SET completed = :completed,
        completedAtUtcMs = CASE WHEN :completed THEN :now ELSE NULL END
        WHERE todoId = :id""")
    fun setTodoCompleted(id: String, completed: Boolean, now: Long): Int

    @Query("DELETE FROM todo_item WHERE todoId = :id")
    fun deleteTodo(id: String)

    @Query("""SELECT COUNT(*) FROM todo_item WHERE sourceEpisodeId = :episodeId
        AND LOWER(TRIM(text)) = LOWER(TRIM(:text))""")
    fun countTodo(episodeId: String, text: String): Int
}

@Database(
    entities = [
        CaptureSegment::class,
        Topic::class,
        TopicEpisode::class,
        EpisodeSegment::class,
        TodoItem::class,
    ],
    version = 6,
    exportSchema = false,
)
abstract class RecorderDatabase : RoomDatabase() {
    abstract fun segments(): SegmentDao

    companion object {
        @Volatile private var instance: RecorderDatabase? = null

        fun get(context: Context): RecorderDatabase = instance ?: synchronized(this) {
            instance ?: Room.databaseBuilder(
                context.applicationContext,
                RecorderDatabase::class.java,
                "recorder.db",
            ).addMigrations(
            MIGRATION_1_2,
            MIGRATION_2_3,
            MIGRATION_3_4,
            MIGRATION_4_5,
            MIGRATION_5_6,
        )
                .build().also { instance = it }
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

        private val MIGRATION_3_4 = object : Migration(3, 4) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL("ALTER TABLE capture_segment ADD COLUMN transcriptionState TEXT NOT NULL DEFAULT 'PENDING'")
                db.execSQL("ALTER TABLE capture_segment ADD COLUMN summaryState TEXT NOT NULL DEFAULT 'WAITING'")
                db.execSQL("ALTER TABLE capture_segment ADD COLUMN transcriptionError TEXT")
                db.execSQL("ALTER TABLE capture_segment ADD COLUMN summaryError TEXT")
                db.execSQL("UPDATE capture_segment SET transcriptionState = 'COMPLETE' WHERE transcriptText IS NOT NULL")
                db.execSQL("UPDATE capture_segment SET summaryState = 'PENDING' WHERE transcriptText IS NOT NULL")
                db.execSQL("UPDATE capture_segment SET summaryState = 'COMPLETE' WHERE summaryJson IS NOT NULL")
            }
        }

        private val MIGRATION_4_5 = object : Migration(4, 5) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL(
                    """CREATE TABLE IF NOT EXISTS `topic` (
                        `topicId` TEXT NOT NULL,
                        `canonicalTitle` TEXT NOT NULL,
                        `description` TEXT NOT NULL,
                        `currentSummary` TEXT NOT NULL,
                        `topicPathJson` TEXT NOT NULL,
                        `firstSeenUtcMs` INTEGER NOT NULL,
                        `lastSeenUtcMs` INTEGER NOT NULL,
                        PRIMARY KEY(`topicId`)
                    )""",
                )
                db.execSQL(
                    """CREATE TABLE IF NOT EXISTS `topic_episode` (
                        `episodeId` TEXT NOT NULL,
                        `topicId` TEXT NOT NULL,
                        `startedAtUtcMs` INTEGER NOT NULL,
                        `endedAtUtcMs` INTEGER NOT NULL,
                        `localTitle` TEXT NOT NULL,
                        `summaryJson` TEXT NOT NULL,
                        `keywordsJson` TEXT NOT NULL,
                        `secondaryTopicsJson` TEXT NOT NULL,
                        `segmentationStatus` TEXT NOT NULL,
                        PRIMARY KEY(`episodeId`)
                    )""",
                )
                db.execSQL(
                    """CREATE TABLE IF NOT EXISTS `episode_segment` (
                        `episodeId` TEXT NOT NULL,
                        `segmentId` TEXT NOT NULL,
                        `sequenceNumber` INTEGER NOT NULL,
                        PRIMARY KEY(`episodeId`, `segmentId`)
                    )""",
                )
            }
        }

        private val MIGRATION_5_6 = object : Migration(5, 6) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL(
                    """CREATE TABLE IF NOT EXISTS `todo_item` (
                        `todoId` TEXT NOT NULL,
                        `text` TEXT NOT NULL,
                        `completed` INTEGER NOT NULL,
                        `createdAtUtcMs` INTEGER NOT NULL,
                        `completedAtUtcMs` INTEGER,
                        `sourceEpisodeId` TEXT,
                        `sourceTitle` TEXT,
                        PRIMARY KEY(`todoId`)
                    )""",
                )
            }
        }
    }
}
