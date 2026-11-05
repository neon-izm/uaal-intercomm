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
    public static class IosLibraryBuild
    {
        public static void BuildForDevice()
        {
            Build(iOSSdkVersion.DeviceSDK, "DeviceSDK", buildContent: true);
        }

        public static void BuildForSimulator()
        {
            Build(iOSSdkVersion.SimulatorSDK, "SimulatorSDK", buildContent: false);
        }

        static void Build(iOSSdkVersion sdk, string folder, bool buildContent)
        {
            var statusName = folder == "DeviceSDK" ? "device.status" : "simulator.status";
            try
            {
                if (buildContent)
                    ContentBuild.Build();
                else
                    ContentBuild.ApplyProfile();

                EditorSceneManager.SaveOpenScenes();
                EditorUserBuildSettings.SwitchActiveBuildTarget(BuildTargetGroup.iOS, BuildTarget.iOS);
                UseArm64Simulator();
                PlayerSettings.iOS.sdkVersion = sdk;
                PlayerSettings.iOS.targetOSVersionString = "15.0";
                PlayerSettings.SetScriptingBackend(NamedBuildTarget.iOS, ScriptingImplementation.IL2CPP);
                PlayerSettings.SplashScreen.show = false;
                PlayerSettings.SplashScreen.showUnityLogo = false;
                PlayerSettings.runInBackground = true;
                EditorUserBuildSettings.development = false;
                EditorUserBuildSettings.connectProfiler = false;
                EditorUserBuildSettings.allowDebugging = false;

                var scenes = EditorBuildSettings.scenes.Where(scene => scene.enabled).Select(scene => scene.path).ToArray();
                if (scenes.Length == 0)
                    throw new InvalidOperationException("ビルド対象のシーンがありません");

                var output = Path.Combine(ContentBuild.RepoRoot, "build", "ios", folder);
                if (Directory.Exists(output))
                    Directory.Delete(output, true);
                Directory.CreateDirectory(output);

                var report = BuildPipeline.BuildPlayer(new BuildPlayerOptions
                {
                    scenes = scenes,
                    locationPathName = output,
                    target = BuildTarget.iOS,
                    options = BuildOptions.None,
                });
                if (report.summary.result != BuildResult.Succeeded)
                {
                    throw new InvalidOperationException(
                        "iOS player build failed: " + report.summary.result
                        + " errors=" + report.summary.totalErrors);
                }

                WriteStatus(statusName, "ok");
                Debug.Log("[Uaal] iOS export " + sdk + " -> " + output);
            }
            catch (Exception exception)
            {
                WriteStatus(statusName, exception.ToString());
                throw;
            }
        }

        static void UseArm64Simulator()
        {
            var playerSettings = Unsupported.GetSerializedAssetInterfaceSingleton("PlayerSettings");
            var serialized = new SerializedObject(playerSettings);
            var architecture = serialized.FindProperty("iOSSimulatorArchitecture");
            if (architecture == null)
                throw new InvalidOperationException("iOSSimulatorArchitecture がありません");
            architecture.intValue = 1;
            serialized.ApplyModifiedProperties();
        }

        static void WriteStatus(string name, string text)
        {
            var dir = Path.Combine(ContentBuild.RepoRoot, "build", "ios");
            Directory.CreateDirectory(dir);
            File.WriteAllText(Path.Combine(dir, name), text);
        }
    }
}
