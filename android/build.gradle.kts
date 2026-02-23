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

// Compatibility shim for older Android library plugins (AGP 8+ requires `namespace`).
subprojects {
    plugins.withId("com.android.library") {
        val androidExt = extensions.findByName("android") ?: return@withId

        val getNamespace =
            androidExt.javaClass.methods.find {
                it.name == "getNamespace" && it.parameterCount == 0
            } ?: return@withId

        val currentNamespace = getNamespace.invoke(androidExt) as? String
        if (!currentNamespace.isNullOrBlank()) return@withId

        val manifestFile = file("src/main/AndroidManifest.xml")
        if (!manifestFile.exists()) return@withId

        val manifestText = manifestFile.readText()
        val pkg =
            Regex("""package="([^"]+)"""")
                .find(manifestText)
                ?.groupValues
                ?.getOrNull(1)
                ?.takeIf { it.isNotBlank() }
                ?: return@withId

        androidExt.javaClass.methods
            .find { it.name == "setNamespace" && it.parameterCount == 1 }
            ?.invoke(androidExt, pkg)
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
