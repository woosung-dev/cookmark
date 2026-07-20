// 파일럿 APK 빌드 계약 — 릴리스 서명은 gitignore된 android/key.properties에서만 온다 (리포 PUBLIC, #141).
//
// import가 필요하다 — 이 스크립트에서 `java`는 패키지가 아니라 JavaPluginExtension 접근자라
// `java.util.Properties()` 완전 수식이 "Unresolved reference 'util'"로 죽는다(settings.gradle.kts는
// 그 확장이 없어 같은 표현이 통한다 — 선례를 복사하면 여기서만 깨진다).
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// 서명 좌표·비밀번호는 리포에 없다. 파운더가 1회 만드는 android/key.properties가 유일한 출처이고
// 그 파일도 .jks도 커밋되지 않는다(android/.gitignore). 생성 절차 = docs/pilot/native-apk-runbook.md 1절.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties =
    Properties().apply {
        if (keystorePropertiesFile.exists()) {
            keystorePropertiesFile.inputStream().use { load(it) }
        }
    }

// 릴리스 태스크를 요청했는데 키가 없으면 여기서 죽는다 — 설정 단계에서, 빌드가 시작되기도 전에.
// 디버그 키 폴백은 의도적으로 막았다. 서명이 바뀌면 Android가 재설치를 "신규 설치"로 처리해
// 파일럿 2주치 로컬 기록(레시피 북·이벤트 로그)이 조용히 전멸한다(#132 · #133).
//
// debug·profile 빌드와 flutter test는 이 파일 없이 그대로 돈다 — 가드가 태스크 이름만 보기 때문이다.
// flutter build apk/appbundle --release → assembleRelease · bundleRelease 이고,
// profile 빌드 타입은 debug 서명을 상속한다(Flutter Gradle 플러그인의 initWith(debug)).
//
// 한계 — 이름에 Release가 없는 집합 태스크(./gradlew build)는 못 잡는다. gradlew는 gitignore라
// 클론에 존재하지 않고 이 리포의 빌드 경로는 flutter build apk 하나뿐이라 도달 불가다(런북 3절).
val releaseTaskRequested =
    gradle.startParameter.taskNames.any { it.contains("Release", ignoreCase = true) }

if (releaseTaskRequested && !keystorePropertiesFile.exists()) {
    throw GradleException(
        """
        릴리스 서명 키가 없다 — ${keystorePropertiesFile.path} 가 존재하지 않는다.

        디버그 키 폴백은 의도적으로 막혀 있다. 서명이 바뀌면 재설치가 신규 설치로 처리되어
        파일럿 2주치 로컬 기록(레시피 북·이벤트 로그)이 전멸한다.

        키스토어 1회 생성 절차는 docs/pilot/native-apk-runbook.md 1절이다.
        """.trimIndent(),
    )
}

fun keystoreProperty(name: String): String =
    keystoreProperties.getProperty(name)
        ?: throw GradleException(
            "key.properties에 $name 가 없다 — docs/pilot/native-apk-runbook.md 1절의 4줄을 그대로 쓴다.",
        )

android {
    namespace = "dev.woosung.cookmark"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // 파운더 결정 — 변경 금지. ID가 바뀌면 Android가 다른 앱으로 취급해 데이터 연속성이 끊긴다(#141).
        applicationId = "dev.woosung.cookmark"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // pubspec.yaml version의 +N에서 온다 — 매 빌드 범프가 재설치 절차의 일부다(런북 6절).
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            // 릴리스 경로는 위 가드를 이미 통과했다. debug·profile 경로에서는 비운 채 지나간다.
            if (keystorePropertiesFile.exists()) {
                // rootProject 기준 — app/build.gradle.kts의 file(...)은 android/app/을 가리켜 틀린다.
                storeFile = rootProject.file(keystoreProperty("storeFile"))
                storePassword = keystoreProperty("storePassword")
                keyAlias = keystoreProperty("keyAlias")
                keyPassword = keystoreProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
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
