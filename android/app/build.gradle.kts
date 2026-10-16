// The Android app: the maths keyboard, the selection menu entries and the
// renderer. No libraries beyond the platform and the engine, so the app has
// nothing to update but itself, and no INTERNET permission to explain.

import groovy.json.JsonSlurper

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

val repository: File = rootDir.parentFile
val version: String = repository.resolve("VERSION").readText().trim()

android {
    namespace = "io.github.superwalrus01.squiggly"
    compileSdk = 36

    defaultConfig {
        applicationId = "io.github.superwalrus01.squiggly"
        // 28 for InputMethodService.switchToPreviousInputMethod, which the
        // keyboard's switch key is built on.
        minSdk = 28
        targetSdk = 36
        versionName = version
        // 0.3.0 is 300: each part gets two digits.
        versionCode = version.split(".").map(String::toInt).let { (a, b, c) -> a * 10000 + b * 100 + c }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    sourceSets["main"].assets.srcDir(layout.buildDirectory.dir("generated/web"))
}

kotlin {
    compilerOptions { jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17) }
}

dependencies {
    implementation(project(":engine"))
}

// The renderer is the extension's own page, as the Mac app's renderer window
// is. web/files.json says where each file comes from, in the same form as
// Sources/LaTeXSquigglyApp/Web/files.json, and this copies them into the
// app's assets under web/.
val copyWeb by tasks.registering(Copy::class) {
    val map = file("web/files.json")
    inputs.file(map)
    @Suppress("UNCHECKED_CAST")
    val files = (JsonSlurper().parse(map) as Map<String, Any>)["files"] as Map<String, String>
    for ((served, source) in files) {
        if (served.endsWith("/")) {
            from(repository.resolve(source)) { into("web/$served") }
        } else {
            from(repository.resolve(source)) {
                into("web/" + served.substringBeforeLast('/', ""))
                rename { served.substringAfterLast('/') }
            }
        }
    }
    into(layout.buildDirectory.dir("generated/web"))
}

tasks.named("preBuild") { dependsOn(copyWeb) }
