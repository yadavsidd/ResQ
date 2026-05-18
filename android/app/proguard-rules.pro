# Google MediaPipe Tasks & GenAI SDK Rules
-keep class com.google.mediapipe.** { *; }
-keep interface com.google.mediapipe.** { *; }

# Keep Protobuf classes and their serialized fields
-keep class com.google.protobuf.** { *; }
-keepclassmembers class * extends com.google.protobuf.GeneratedMessageLite {
    <fields>;
}

# Keep all native JNI calls intact
-keepclasseswithmembernames class * {
    native <methods>;
}

# Keep AutoValue classes (used internally by MediaPipe)
-keep class com.google.auto.value.** { *; }
-keep @interface com.google.auto.value.**

# Prevent obfuscation completely to secure class and field name reflection inside C++ native libraries
-dontobfuscate
-dontshrink
-dontoptimize
