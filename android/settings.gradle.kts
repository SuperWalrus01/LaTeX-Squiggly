// The Android app and its engine. The engine is plain Kotlin, checked against
// conformance/reference.json on any JVM; the app needs the Android SDK.
//
//   gradle :engine:conformance                    the engine, on any machine
//   gradle :app:assembleDebug                     the app, with the Android SDK
//   gradle -PengineOnly=true :engine:conformance  where Google's Maven is out of reach

pluginManagement {
    repositories {
        // Only Android's own artifacts come from Google, so the engine resolves
        // from Maven Central alone.
        google {
            content {
                includeGroupByRegex("com\\.android.*")
                includeGroupByRegex("com\\.google.*")
                includeGroupByRegex("androidx.*")
            }
        }
        mavenCentral()
        gradlePluginPortal()
    }
    plugins {
        id("com.android.application") version "8.12.0"
        id("org.jetbrains.kotlin.android") version "2.2.20"
        id("org.jetbrains.kotlin.jvm") version "2.2.20"
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        // Only Android's own artifacts come from Google, so the engine resolves
        // from Maven Central alone.
        google {
            content {
                includeGroupByRegex("com\\.android.*")
                includeGroupByRegex("com\\.google.*")
                includeGroupByRegex("androidx.*")
            }
        }
        mavenCentral()
    }
}

rootProject.name = "latex-squiggly-android"

include(":engine")
if (providers.gradleProperty("engineOnly").orNull != "true") include(":app")
