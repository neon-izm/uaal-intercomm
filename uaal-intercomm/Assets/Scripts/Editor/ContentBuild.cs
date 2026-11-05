using System;
using System.Collections.Generic;
using System.IO;
using UnityEditor;
using UnityEditor.AddressableAssets;
using UnityEditor.AddressableAssets.Build;
using UnityEditor.AddressableAssets.Settings;
using UnityEngine;

namespace UaalIntercomm.Editor
{
    public static class ContentBuild
    {
        public static string ApplyProfile()
        {
            var hosting = ReadHosting();
            var settings = AddressableAssetSettingsDefaultObject.Settings;
            if (settings == null)
                throw new InvalidOperationException("Addressables settings がありません");

            var loadPath = hosting["R2_PUBLIC_BASE"].TrimEnd('/')
                + "/content/"
                + hosting["CONTENT_VERSION"]
                + "/[BuildTarget]";
            settings.profileSettings.SetValue(
                settings.activeProfileId,
                AddressableAssetSettings.kRemoteLoadPath,
                loadPath);
            settings.profileSettings.SetValue(
                settings.activeProfileId,
                AddressableAssetSettings.kRemoteBuildPath,
                "ServerData/[BuildTarget]");
            settings.OverridePlayerVersion = hosting["CONTENT_VERSION"];
            settings.BuildRemoteCatalog = true;
            settings.BuildAddressablesWithPlayerBuild =
                AddressableAssetSettings.PlayerBuildOption.DoNotBuildWithPlayer;
            EditorUtility.SetDirty(settings);
            AssetDatabase.SaveAssets();
            return loadPath;
        }

        public static string Build()
        {
            var loadPath = ApplyProfile();
            AddressableAssetSettings.BuildPlayerContent(out AddressablesPlayerBuildResult result);
            if (result == null || !string.IsNullOrEmpty(result.Error))
                throw new InvalidOperationException(result == null ? "addressables build failed" : result.Error);
            Debug.Log("[Uaal] content built for " + loadPath + " -> " + result.OutputPath);
            return result.OutputPath ?? "";
        }

        public static string RepoRoot =>
            Directory.GetParent(Application.dataPath).Parent.FullName;

        static Dictionary<string, string> ReadHosting()
        {
            var path = Path.Combine(RepoRoot, "scripts", "hosting.env");
            if (!File.Exists(path))
                throw new FileNotFoundException("hosting.env がありません", path);

            var values = new Dictionary<string, string>();
            foreach (var raw in File.ReadAllLines(path))
            {
                var line = raw.Trim();
                if (line.Length == 0 || line.StartsWith("#", StringComparison.Ordinal))
                    continue;
                var split = line.IndexOf('=');
                if (split <= 0)
                    continue;
                values[line.Substring(0, split).Trim()] = line.Substring(split + 1).Trim();
            }

            if (!values.ContainsKey("R2_PUBLIC_BASE") || !values.ContainsKey("CONTENT_VERSION"))
                throw new InvalidOperationException("hosting.env に R2_PUBLIC_BASE と CONTENT_VERSION が要ります");
            return values;
        }
    }
}
