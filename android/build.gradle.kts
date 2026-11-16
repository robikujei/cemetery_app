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
    // image_gallery_saver 2.0.3 predates the Android Gradle Plugin namespace
    // requirement. Keep the compatibility shim in the project (rather than
    // changing the shared Pub cache) so release builds remain reproducible.
    if (name == "image_gallery_saver") {
        plugins.withId("com.android.library") {
            extensions.findByName("android")?.let { androidExtension ->
                androidExtension.javaClass.methods
                    .firstOrNull { method ->
                        method.name == "setNamespace" &&
                            method.parameterTypes.contentEquals(
                                arrayOf(String::class.java),
                            )
                    }
                    ?.invoke(androidExtension, "com.example.imagegallerysaver")
                androidExtension.javaClass.methods
                    .firstOrNull { method ->
                        method.name == "setCompileSdk" &&
                            method.parameterTypes.contentEquals(
                                arrayOf(Int::class.javaPrimitiveType),
                            )
                    }
                    ?.invoke(androidExtension, 35)
            }
            tasks.matching { task -> task.name.endsWith("Kotlin") }
                .configureEach {
                    javaClass.methods
                        .firstOrNull { method ->
                            method.name == "getKotlinOptions" &&
                                method.parameterCount == 0
                        }
                        ?.invoke(this)
                        ?.let { kotlinOptions ->
                            kotlinOptions.javaClass.methods
                                .firstOrNull { method ->
                                    method.name == "setJvmTarget" &&
                                        method.parameterTypes.contentEquals(
                                            arrayOf(String::class.java),
                                        )
                                }
                                ?.invoke(kotlinOptions, "1.8")
                        }
                }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
