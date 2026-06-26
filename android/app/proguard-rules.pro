# ─── WorkManager ────────────────────────────────────────────────────────────
# WorkManager uses Room + reflection-based initialisation via ContentProvider.
# R8 strips the internal classes without these rules, causing the fatal
# InitializationProvider crash seen on first launch of the release APK.
-keep class androidx.work.** { *; }
-keep class androidx.work.impl.** { *; }
-dontwarn androidx.work.**

# ─── Room (WorkManager bundles its own Room database) ───────────────────────
-keep class * extends androidx.room.RoomDatabase
-keep @androidx.room.Entity class *
-dontwarn androidx.room.paging.**

# ─── flutter_secure_storage ──────────────────────────────────────────────────
# Uses Android Keystore via reflection; keep the implementation classes.
-keep class com.it_nomads.fluttersecurestorage.** { *; }
-dontwarn com.it_nomads.fluttersecurestorage.**

# ─── google_sign_in / Google Play Services ──────────────────────────────────
# Play Services ships its own consumer rules via AAR, but keep the surface
# classes explicitly to guard against partial stripping.
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.android.gms.**

# ─── flutter_local_notifications ────────────────────────────────────────────
-keep class com.dexterous.flutterlocalnotifications.** { *; }
-dontwarn com.dexterous.flutterlocalnotifications.**

# ─── image_cropper (uCrop) ──────────────────────────────────────────────────
-dontwarn com.yalantis.ucrop.**
-keep class com.yalantis.ucrop.** { *; }
-keep interface com.yalantis.ucrop.** { *; }

# ─── sqflite ────────────────────────────────────────────────────────────────
-keep class io.flutter.plugins.sqflite.** { *; }

# ─── local_auth ─────────────────────────────────────────────────────────────
-keep class io.flutter.plugins.localauth.** { *; }

# ─── disk_space_plus ────────────────────────────────────────────────────────
-keep class com.example.disk_space_plus.** { *; }
-dontwarn com.example.disk_space_plus.**

# ─── Flutter engine / plugin registry ───────────────────────────────────────
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.**
