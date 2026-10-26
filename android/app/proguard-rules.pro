# WorkManager (pulled in by the Google Mobile Ads SDK) creates its Room
# database by name; without these rules R8 strips WorkDatabase_Impl and the
# app crashes at launch with "Failed to create an instance of WorkDatabase".
-keep class androidx.work.impl.WorkDatabase_Impl { *; }
-keep class * extends androidx.room.RoomDatabase
-keep class androidx.work.** { *; }
-dontwarn androidx.work.**
