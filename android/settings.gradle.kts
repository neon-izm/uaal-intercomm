pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
        maven { url = uri("https://pub-9480de868c60413c80b39cefa6089251.r2.dev/android/maven") }
    }
}

rootProject.name = "uaal-intercomm-android"
include(":uaal-intercomm")
