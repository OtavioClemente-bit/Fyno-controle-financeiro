import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Lê o arquivo android/key.properties (senhas e caminho do keystore)
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
require(keystorePropertiesFile.exists()) {
    "key.properties não encontrado em: ${keystorePropertiesFile.absolutePath}"
}

keystoreProperties.load(FileInputStream(keystorePropertiesFile))

require(!keystoreProperties["storeFile"].toString().isBlank()) {
    "storeFile vazio no key.properties"
}
android {
    namespace = "com.fyno.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    defaultConfig {
        applicationId = "com.fyno.app"

        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion

        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Config de assinatura RELEASE usando key.properties
    signingConfigs {
        create("release") {
            // Só configura se o key.properties existir
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // ✅ Assina com RELEASE (e não debug)
            signingConfig = signingConfigs.getByName("release")

            // Mantém simples (pode otimizar depois)
            isMinifyEnabled = false
            isShrinkResources = false
        }

        debug {
            // debug padrão
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    testImplementation("junit:junit:4.13.2")
}
