// The engine: no Android, no dependencies beyond the Kotlin standard library,
// so the app and the conformance runner share exactly the same code.

import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    id("org.jetbrains.kotlin.jvm")
}

java {
    sourceCompatibility = JavaVersion.VERSION_17
    targetCompatibility = JavaVersion.VERSION_17
}

kotlin {
    compilerOptions { jvmTarget.set(JvmTarget.JVM_17) }
}

// The runner is its own source set rather than a test, so it needs no test
// framework and prints the same report as the other ports' runners.
sourceSets {
    create("conformance") {
        compileClasspath += sourceSets.main.get().output
        runtimeClasspath += sourceSets.main.get().output
    }
}

configurations["conformanceImplementation"].extendsFrom(configurations.implementation.get())

tasks.register<JavaExec>("conformance") {
    group = "verification"
    description = "Replays conformance/reference.json against this engine."
    classpath = sourceSets["conformance"].runtimeClasspath
    mainClass.set("io.github.superwalrus01.squiggly.engine.ConformanceKt")
    args(rootProject.file("../conformance/reference.json").absolutePath)
}
