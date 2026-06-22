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

// Force every Android plugin module to compile against at least SDK 36.
// Some plugins (e.g. file_picker) still pin compileSdk 34, but
// flutter_plugin_android_lifecycle requires 36. Registered BEFORE the
// evaluationDependsOn block so the projects aren't evaluated yet.
subprojects {
    afterEvaluate {
        extensions.findByName("android")?.let { ext ->
            val android = ext as com.android.build.gradle.BaseExtension
            val current = android.compileSdkVersion
                ?.substringAfter("android-")
                ?.toIntOrNull() ?: 0
            if (current < 36) {
                android.compileSdkVersion(36)
            }
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
