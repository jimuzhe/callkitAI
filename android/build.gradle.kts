import com.android.build.gradle.BaseExtension
import org.gradle.api.tasks.compile.JavaCompile
import org.jetbrains.kotlin.gradle.tasks.KotlinCompile
import java.nio.charset.Charset

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

subprojects {
    if (name == "flutter_native_timezone") {
        val manifestFile = file("src/main/AndroidManifest.xml")
        tasks.matching { it.name == "preBuild" }.configureEach {
            doFirst {
                if (manifestFile.exists()) {
                    val original = manifestFile.readText()
                    val updated = original.replace("package=\"com.whelksoft.flutter_native_timezone\"", "")
                    if (original != updated) {
                        manifestFile.writeText(updated)
                    }
                }
            }
        }
        afterEvaluate {
            extensions.findByName("android")
                ?.let { ext ->
                    val androidExt = ext as? BaseExtension
                    androidExt?.namespace = "com.github.dartsidedev.flutter_native_timezone"
                    androidExt?.compileOptions?.apply {
                        sourceCompatibility = JavaVersion.VERSION_11
                        targetCompatibility = JavaVersion.VERSION_11
                    }
                }
        }
        tasks.withType(JavaCompile::class.java).configureEach {
            sourceCompatibility = JavaVersion.VERSION_11.toString()
            targetCompatibility = JavaVersion.VERSION_11.toString()
        }
        tasks.withType(KotlinCompile::class.java).configureEach {
            kotlinOptions.jvmTarget = JavaVersion.VERSION_11.toString()
        }
        val sourceFile = file("src/main/kotlin/com/whelksoft/flutter_native_timezone/FlutterNativeTimezonePlugin.kt")
        tasks.matching { it.name.contains("compile", ignoreCase = true) && it.name.contains("Kotlin") }
            .configureEach {
                doFirst {
                    if (sourceFile.exists()) {
                        val original = sourceFile.readText(Charset.forName("UTF-8"))
                        var updated = original
                        updated = updated.replace(
                            "import io.flutter.plugin.common.PluginRegistry.Registrar\n",
                            ""
                        )
                        updated = updated.replace(
                            "    companion object {\n        @JvmStatic\n        fun registerWith(registrar: Registrar) {\n            val plugin = FlutterNativeTimezonePlugin()\n            plugin.setupMethodChannel(registrar.messenger())\n        }\n    }\n\n",
                            ""
                        )
                        if (updated != original) {
                            sourceFile.writeText(updated, Charset.forName("UTF-8"))
                        }
                    }
                }
            }
    }
    if (name == "vibration") {
        val sourceFile = file("src/main/java/com/benjaminabel/vibration/VibrationPlugin.java")
        tasks.matching { it.name.contains("compile", ignoreCase = true) && it.name.contains("JavaWithJavac") }
            .configureEach {
                doFirst {
                    if (sourceFile.exists()) {
                        val original = sourceFile.readText()
                        var updated = original
                        updated = updated.replace(
                            "    @SuppressWarnings(\"deprecation\")\n    public static void registerWith(io.flutter.plugin.common.PluginRegistry.Registrar registrar) {\n        final VibrationPlugin vibrationPlugin = new VibrationPlugin();\n\n        vibrationPlugin.setupChannels(registrar.messenger(), registrar.context());\n    }\n\n",
                            ""
                        )
                        if (updated != original) {
                            sourceFile.writeText(updated)
                        }
                    }
                }
            }
    }
    if (name == "flutter_local_notifications") {
        val sourceFile = file("src/main/java/com/dexterous/flutterlocalnotifications/FlutterLocalNotificationsPlugin.java")
        tasks.matching { it.name.contains("compile", ignoreCase = true) && it.name.contains("JavaWithJavac") }
            .configureEach {
                doFirst {
                    if (sourceFile.exists()) {
                        val target = "bigPictureStyle.bigLargeIcon(null);"
                        val replacement = "bigPictureStyle.bigLargeIcon((android.graphics.Bitmap) null);"
                        val original = sourceFile.readText()
                        if (original.contains(target) && !original.contains(replacement)) {
                            sourceFile.writeText(original.replace(target, replacement))
                        }
                    }
                }
            }
    }
    if (name == "opus_flutter_android") {
        afterEvaluate {
            extensions.findByName("android")
                ?.let { ext ->
                    val androidExt = ext as? BaseExtension
                    val current = androidExt?.defaultConfig?.minSdk ?: 0
                    if (current < 21) {
                        androidExt?.defaultConfig?.minSdk = 21
                    }
                }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
