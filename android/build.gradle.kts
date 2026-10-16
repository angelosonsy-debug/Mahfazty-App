// mahfazty: google_mobile_ads Gradle 8.11+ compatibility patch
// ─────────────────────────────────────────────────────────────────────
// بنطبّق shim بيرجّع configurations.all(Closure) كـ method حقيقية
// (alias لـ configureEach) — التفاصيل في mahfazty_gma_shim.gradle
// جمب الملف ده مباشرة. لازم يتطبّق أول حاجة في الملف الجذري، قبل أي
// مشروع فرعي (زي :google_mobile_ads) يتقرأ.
apply(from = "mahfazty_gma_shim.gradle")
apply(from = "mahfazty_compile_sdk_enforcement.gradle")

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
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
