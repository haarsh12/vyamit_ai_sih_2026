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

// --- FIX FOR OLDER PLUGINS (Blue Thermal Printer) ---
// This block safely sets the namespace for libraries that don't have it (Android 14+ requirement)
subprojects {
    // Define the fix logic
    val fixNamespace = {
        if (project.hasProperty("android")) {
            val android = project.extensions.getByName("android")
            try {
                val getNamespace = android.javaClass.getMethod("getNamespace")
                val setNamespace = android.javaClass.getMethod("setNamespace", String::class.java)
                
                // If namespace is missing, set it to the project group
                if (getNamespace.invoke(android) == null) {
                    val newNamespace = project.group.toString()
                    setNamespace.invoke(android, newNamespace)
                }
            } catch (e: Exception) {
                // Ignore reflection errors
            }
        }
    }
    
    // "Smart Check": Run immediately if evaluated, otherwise wait
    if (project.state.executed) {
        fixNamespace()
    } else {
        project.afterEvaluate {
            fixNamespace()
        }
    }
}
