allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// Gradle 산출물을 apps/mobile/build/ 로 옮긴다(스톡 템플릿 그대로). 되돌리지 말 것 —
// flutter_tools의 AndroidProject.buildDirectory가 parent.buildDirectory로 하드코딩이라
// (project.dart:868) Gradle 쪽만 옮기면 flutter가 APK를 못 찾는다. 서브프로젝트마다 형제
// 디렉터리가 하나씩 생기므로 Android 플러그인을 추가하면 .vercelignore에 한 줄 는다(#141).
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

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
