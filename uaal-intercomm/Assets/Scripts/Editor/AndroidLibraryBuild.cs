using System;
using System.IO;
using System.Linq;
using UnityEditor;
using UnityEditor.Build;
using UnityEditor.Build.Reporting;
using UnityEditor.SceneManagement;
using UnityEngine;

namespace UaalIntercomm.Editor
{
    public static class AndroidLibraryBuild
    {
        public static void Build()
        {
            try
            {
                EditorSceneManager.SaveOpenScenes();
                EditorUserBuildSettings.SwitchActiveBuildTarget(BuildTargetGroup.Android, BuildTarget.Android);
                ContentBuild.Build();

                PlayerSettings.SetScriptingBackend(NamedBuildTarget.Android, ScriptingImplementation.IL2CPP);
                PlayerSettings.Android.targetArchitectures = AndroidArchitecture.ARM64;
                PlayerSettings.Android.minSdkVersion = AndroidSdkVersions.AndroidApiLevel25;
                PlayerSettings.SplashScreen.show = false;
                PlayerSettings.SplashScreen.showUnityLogo = false;
                PlayerSettings.runInBackground = true;
                PlayerSettings.SetApplicationIdentifier(NamedBuildTarget.Android, "dev.uaal.intercomm");
                EditorUserBuildSettings.exportAsGoogleAndroidProject = true;
                EditorUserBuildSettings.androidBuildSystem = AndroidBuildSystem.Gradle;
                EditorUserBuildSettings.development = false;
                EditorUserBuildSettings.connectProfiler = false;
                EditorUserBuildSettings.allowDebugging = false;

                var scenes = EditorBuildSettings.scenes.Where(scene => scene.enabled).Select(scene => scene.path).ToArray();
                if (scenes.Length == 0)
                    throw new InvalidOperationException("ビルド対象のシーンがありません");

                var output = Path.Combine(ContentBuild.RepoRoot, "build", "android", "Export");
                if (Directory.Exists(output))
                    Directory.Delete(output, true);
                Directory.CreateDirectory(output);

                var report = BuildPipeline.BuildPlayer(new BuildPlayerOptions
                {
                    scenes = scenes,
                    locationPathName = output,
                    target = BuildTarget.Android,
                    options = BuildOptions.None,
                });
                if (report.summary.result != BuildResult.Succeeded)
                {
                    throw new InvalidOperationException(
                        "Android export failed: " + report.summary.result
                        + " errors=" + report.summary.totalErrors);
                }

                WriteStatus("ok");
                Debug.Log("[Uaal] Android export -> " + output);
            }
            catch (Exception exception)
            {
                WriteStatus(exception.ToString());
                throw;
            }
        }

        static void WriteStatus(string text)
        {
            var dir = Path.Combine(ContentBuild.RepoRoot, "build", "android");
            Directory.CreateDirectory(dir);
            File.WriteAllText(Path.Combine(dir, "export.status"), text);
        }
    }
}
