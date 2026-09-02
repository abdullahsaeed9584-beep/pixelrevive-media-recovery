allprojects {
    repositories {
        google()
        mavenCentral()
        maven { url = uri("https://jitpack.io") } // libsu — root shell (Phase 0)
    }
}

// Redirect only the :app build output to ../../build so Flutter can find the APK.
// Plugin subprojects are intentionally excluded — they build inside the pub cache on C:\,
// and redirecting them to E:\ causes Kotlin cross-drive path failures.
subprojects {
    project.evaluationDependsOn(":app")
    if (project.name == "app") {
        val newBuildDir: Directory =
            rootProject.layout.buildDirectory
                .dir("../../build")
                .get()
        project.layout.buildDirectory.value(newBuildDir.dir(project.name))
    }
}

// The rootProject build dir also needs to point to ../../build so Flutter's
// output path resolution works correctly.
val flutterBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(flutterBuildDir)

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
