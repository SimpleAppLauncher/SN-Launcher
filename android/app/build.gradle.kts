plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "dev.snlauncher.snlauncher"
    compileSdk = flutter.compileSdkVersion

    // ── Two builds, two applicationIds ─────────────────────────────────────
    //
    // There are two APKs (see docs/BUILDS.md) and they used to share an
    // applicationId, which made them mutually exclusive: installing one silently
    // uninstalled the other, and comparing them meant two devices and a note
    // about which was which.
    //
    // A suffix fixes that and costs one property:
    //
    //     flutter build apk --release                          # reduced
    //     flutter build apk --release -PsnAppIdSuffix=.ef      # ef
    //
    // Default is empty, so the reduced build keeps applicationId
    // dev.snlauncher.snlauncher exactly as before — existing installs survive,
    // and every script in tool/ that hardcodes the package name keeps working.
    // Only the ef build moves, and it moves *aside* rather than replacing.
    //
    // A product-flavour setup would be the idiomatic Android answer and was not
    // used: declaring flavors makes `--flavor` mandatory, so every build command
    // in tool/ would need changing, and the APK filenames would all change too.
    // The property keeps this to four lines.
    val appIdSuffix = (project.findProperty("snAppIdSuffix") as String?) ?: ""

    // `ndkVersion` is now declared, because there *is* native code: the Rust
    // licence filter in native/licence_filter, built by tool/build_rust.sh into
    // src/main/jniLibs/.
    //
    // The previous comment said there was no native code and that declaring an
    // NDK would drag in a ~1 GB download for nothing. That was true then and
    // stopped being true when the Rust library arrived. It is pinned to the
    // version already on this machine so AGP does not shell out to sdkmanager
    // and try to install a different one.
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        // Required for the resValue("string", "app_name", …) above. AGP 8 gates
        // this behind a feature flag and fails configuration with
        // "defaultConfig contains custom resource values, but the feature is
        // disabled" if it is not switched on.
        resValues = true
    }

    // ── Sensitive permissions ────────────────────────────────────────────────
    //
    // Off by default. The base manifest declares no microphone, no calendar,
    // no location and no notification listener, because Google Play Protect
    // warns about all four at install time and the warning is correct: each
    // can read something private.
    //
    // A build that wants them merges src/sensitive/manifest-fragment.xml in:
    //
    //     flutter build apk --release -PsnSensitive=true
    //
    // The merge is done here rather than by keeping two hand-written manifests
    // so the two cannot drift. The fragment is the single place the sensitive
    // declarations live.
    val sensitive: Boolean =
        (project.findProperty("snSensitive") as String?)?.toBoolean() ?: false

    // The sensitive manifest is *generated* from the base one plus the
    // fragment, at configuration time, so the two can never drift. A
    // hand-kept copy is a copy that lies the first time someone edits the
    // base manifest and forgets the other file.
    val sensitiveManifest = layout.buildDirectory.file("generated/sensitive/AndroidManifest.xml")
    if (sensitive) {
        val base = file("src/main/AndroidManifest.xml")
        val fragment = file("src/sensitive/manifest-fragment.xml")
        // A plain text splice at a marker. Deliberately not XML parsing: the
        // fragment is a list of manifest elements, and the simplest thing that
        // cannot fail is a string replacement. The *result* is what gets
        // validated, by the manifest merger, and by the permission dump in
        // tool/verify_permissions.sh.
        val serviceFragment = file("src/sensitive/manifest-service.xml")
        val merged = base.readText()
            .replace("<!-- SENSITIVE-PERMISSIONS -->", fragment.readText().trimEnd())
            .replace("<!-- SENSITIVE-SERVICE -->", serviceFragment.readText().trimEnd())
        sensitiveManifest.get().asFile.apply {
            parentFile.mkdirs()
            writeText(merged)
        }
    }

    sourceSets {
        getByName("main") {
            manifest.srcFile(
                if (sensitive) {
                    sensitiveManifest.get().asFile.path
                } else {
                    "src/main/AndroidManifest.xml"
                },
            )
        }
    }

    defaultConfig {
        applicationId = "dev.snlauncher.snlauncher"
        applicationIdSuffix = appIdSuffix

        // The launcher label, so the two are distinguishable on the home screen
        // and in the recents list rather than only by their applicationId. The
        // manifest references @string/app_name; this is what supplies it.
        resValue(
            "string",
            "app_name",
            "SN-Launcher" + if (appIdSuffix.isEmpty()) "" else " ef",
        )
        // API 21 covers essentially every e-waste Android tablet still in
        // circulation (Android 5.0, 2014) up to current devices.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // ── Hybrid CPU/GPU rendering switch ──────────────────────────────
        // Impeller (Vulkan) is the GPU path and is what we ship with. Some
        // older or badly-finned Mali/Adreno drivers hang or render incorrectly
        // under Vulkan, and there the engine's Skia/OpenGL path is the reliable
        // one.
        //
        // Override per build without editing this file:
        //     flutter build apk --release -PenableImpeller=false
        // or set it in android/gradle.properties. Default: true.
        manifestPlaceholders["enableImpeller"] =
            (project.findProperty("enableImpeller") as String?) ?: "true"
    }

    // No `splits` block here on purpose.
    //
    // Android App Bundles *forbid* ABI splits: with the block enabled,
    // `flutter build appbundle` fails at buildReleasePreBundle with "Multiple
    // shrunk-resources files found". The bundle format already does per-ABI
    // delivery, so splitting it too buys nothing.
    //
    // Per-ABI APKs are still one flag away, and Flutter implements them
    // natively — no Gradle configuration needed:
    //
    //     flutter build apk --release --split-per-abi
    //
    // which matters on this project's hardware: the universal APK is 48 MB
    // because it carries three ABIs, while the arm64 one is 17.6 MB. For a
    // tablet on a metered connection that is a real difference.

    buildTypes {
        release {
            // Replace with a real signing config before publishing.
            signingConfig = signingConfigs.getByName("debug")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }

    packaging {
        resources {
            excludes += setOf("META-INF/*.version")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

// ── Media playback ──────────────────────────────────────────────────────────
//
// Media3, not ExoPlayer directly: it is the maintained line and it is what
// `MediaSessionService` is built on.
//
// Chosen over a `just_audio`-style plugin for one reason that matters on this
// hardware: those run a localhost HTTP proxy inside the app to handle headers
// and caching. That is a second network stack resident in a process that
// already holds the Flutter engine on a tablet with 2 GB of RAM. A plain
// ExoPlayer plus a MethodChannel is a player and a message port.
dependencies {
    implementation("androidx.media3:media3-exoplayer:1.5.1")
    implementation("androidx.media3:media3-session:1.5.1")
    implementation("androidx.media3:media3-common:1.5.1")
}
