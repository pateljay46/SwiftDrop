# SwiftDrop ProGuard rules
# Flutter-specific rules are auto-included by the Flutter Gradle plugin.

# Keep PointyCastle crypto classes (reflection-based).
-keep class org.bouncycastle.** { *; }
-dontwarn org.bouncycastle.**

# Keep Hive TypeAdapters.
-keep class * extends com.hive.** { *; }

# Don't warn about missing annotation references.
-dontwarn javax.annotation.**
