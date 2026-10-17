# Flutter engine + plugin registrant
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Firebase Messaging (activated when google-services.json is added)
-keep class com.google.firebase.** { *; }
-dontwarn com.google.firebase.**

# Google Play Core is not bundled (deferred components unused)
-dontwarn com.google.android.play.core.**

# home_widget resolves the provider with
# Class.forName("<package>.CadenceWidgetProvider") from the androidName string
# passed in Dart. AGP keeps manifest-declared receivers today, so this is
# belt-and-braces — but the failure mode is a widget that silently stops
# updating, which is worth one line to rule out.
-keep class com.harishram.cadence.CadenceWidgetProvider { *; }

# flutter_local_notifications (habit reminders).
# It GSON-serializes its model classes into SharedPreferences so pending
# notifications survive a reboot. R8 renames those fields, deserialization
# then fails silently, and every scheduled reminder is lost on restart —
# the package ships no consumer rules, so these have to live here.
-keep class com.dexterous.** { *; }
-dontwarn com.dexterous.**
-keep class com.google.gson.** { *; }
-keepattributes Signature
-keepattributes *Annotation*
# GSON reflects over generic type tokens and the fields it populates.
-keep class * extends com.google.gson.reflect.TypeToken { *; }
-keepclassmembers,allowobfuscation class * {
    @com.google.gson.annotations.SerializedName <fields>;
}
