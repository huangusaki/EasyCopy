import java.util.Properties

fun loadSigningProperties(): Properties {
    val properties = Properties()
    val propertiesFile = rootProject.file("key.properties")
    if (propertiesFile.exists()) {
        propertiesFile.inputStream().use { properties.load(it) }
    }
    return properties
}

fun signingValue(
    properties: Properties,
    propertyKey: String,
    vararg envKeys: String,
): String? {
    val propertyValue = properties.getProperty(propertyKey)?.trim().orEmpty()
    if (propertyValue.isNotEmpty()) {
        return propertyValue
    }

    for (envKey in envKeys) {
        val envValue = System.getenv(envKey)?.trim().orEmpty()
        if (envValue.isNotEmpty()) {
            return envValue
        }
    }
    return null
}

val signingProperties = loadSigningProperties()
val releaseStoreFilePath = signingValue(
    signingProperties,
    "storeFile",
    "ANDROID_KEYSTORE_PATH",
    "ANDROID_KEYSTORE_FILE",
)
val releaseStorePassword = signingValue(
    signingProperties,
    "storePassword",
    "ANDROID_STORE_PASSWORD",
    "ANDROID_KEYSTORE_PASSWORD",
)
val releaseKeyAlias = signingValue(
    signingProperties,
    "keyAlias",
    "ANDROID_KEY_ALIAS",
)
val releaseKeyPassword = signingValue(
    signingProperties,
    "keyPassword",
    "ANDROID_KEY_PASSWORD",
)
val releaseStoreFile = releaseStoreFilePath?.let(rootProject::file)
val hasReleaseSigningInputs = listOf(
    releaseStoreFilePath,
    releaseStorePassword,
    releaseKeyAlias,
    releaseKeyPassword,
).all { !it.isNullOrBlank() }
val allowDebugSigning = (
    (findProperty("allowDebugSigning") as String?)
        ?: System.getenv("EASY_COPY_ALLOW_DEBUG_SIGNING")
        ?: "false"
).toBoolean()
val isReleaseBuildRequested = gradle.startParameter.taskNames.any { taskName ->
    taskName.contains("Release", ignoreCase = true)
}

if (hasReleaseSigningInputs) {
    require(releaseStoreFile != null && releaseStoreFile.exists()) {
        "Release keystore file was not found: ${releaseStoreFile?.absolutePath ?: releaseStoreFilePath}"
    }
} else if (isReleaseBuildRequested && !allowDebugSigning) {
    error(
        "Release signing is not configured. Provide android/key.properties or " +
            "ANDROID_KEYSTORE_PATH / ANDROID_STORE_PASSWORD / ANDROID_KEY_ALIAS / " +
            "ANDROID_KEY_PASSWORD. Reuse the same keystore for every published APK, " +
            "otherwise Android users will not be able to upgrade directly.",
    )
}

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.huangusaki.easycopy"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.huangusaki.easycopy"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (hasReleaseSigningInputs) {
                storeFile = releaseStoreFile
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseSigningInputs) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}
