using System;
using System.Collections.Generic;
using System.Globalization;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;

namespace UaalIntercomm.Editor
{
    public sealed class IntercommTestWindow : EditorWindow
    {
        const string EntrypointPath = "Assets/Scenes/entrypoint.unity";
        const string RestartKey = "UaalIntercomm.PlayFromEntrypoint";
        const string LogPrefix = "[Bridge] ";
        const int LogLimit = 24;

        static readonly string[] PrefabIds = { "carA", "carB", "carC" };
        static readonly string[] CameraLabels = { "1 正面", "2 側面", "3 上面" };

        readonly List<string> log = new List<string>();
        Vector2 scroll;
        Color color = Color.white;
        int cameraIndex = 1;

        [MenuItem("Window/Uaal Intercomm")]
        static void Open()
        {
            var window = GetWindow<IntercommTestWindow>();
            window.titleContent = new GUIContent("Uaal Intercomm");
            window.Show();
        }

        void OnEnable()
        {
            titleContent = new GUIContent("Uaal Intercomm");
            minSize = new Vector2(320f, 420f);
            Application.logMessageReceived -= OnLog;
            Application.logMessageReceived += OnLog;
            EditorApplication.playModeStateChanged -= OnPlayModeStateChanged;
            EditorApplication.playModeStateChanged += OnPlayModeStateChanged;
            EditorApplication.delayCall += ContinuePlayFromEntrypoint;
        }

        void OnDisable()
        {
            Application.logMessageReceived -= OnLog;
            EditorApplication.playModeStateChanged -= OnPlayModeStateChanged;
        }

        void OnPlayModeStateChanged(PlayModeStateChange state)
        {
            if (state == PlayModeStateChange.ExitingEditMode)
                log.Clear();

            if (state == PlayModeStateChange.EnteredEditMode)
                EditorApplication.delayCall += ContinuePlayFromEntrypoint;

            Repaint();
        }

        static void ContinuePlayFromEntrypoint()
        {
            if (!SessionState.GetBool(RestartKey, false))
                return;

            if (EditorApplication.isPlayingOrWillChangePlaymode)
                return;

            SessionState.EraseBool(RestartKey);
            PlayFromEntrypoint();
        }

        void OnGUI()
        {
            var bridge = FindBridge();

            EditorGUILayout.Space(6f);
            using (new EditorGUILayout.HorizontalScope())
            {
                var label = EditorApplication.isPlaying ? "entrypoint からやり直す" : "entrypoint から再生";
                if (GUILayout.Button(label, GUILayout.Height(28f)))
                    RequestPlayFromEntrypoint();
            }

            if (!EditorApplication.isPlaying)
            {
                EditorGUILayout.HelpBox("entrypoint を再生すると、ネイティブと同じ OnCommand をここから送れます。", MessageType.Info);
            }
            else if (bridge == null)
            {
                EditorGUILayout.HelpBox("Bridge がシーンにありません。entrypoint から再生してください。", MessageType.Warning);
            }

            using (new EditorGUI.DisabledScope(bridge == null))
            {
                EditorGUILayout.Space(8f);
                EditorGUILayout.LabelField("Scene", EditorStyles.boldLabel);
                if (GUILayout.Button("load"))
                    Send(bridge, "{\"op\":\"load\"}");

                EditorGUILayout.Space(8f);
                EditorGUILayout.LabelField("Prefab", EditorStyles.boldLabel);
                using (new EditorGUILayout.HorizontalScope())
                {
                    for (var i = 0; i < PrefabIds.Length; i++)
                    {
                        var id = PrefabIds[i];
                        if (GUILayout.Button(id))
                            Send(bridge, "{\"op\":\"loadPrefab\",\"id\":\"" + id + "\"}");
                    }
                }

                EditorGUILayout.Space(8f);
                EditorGUILayout.LabelField("Color", EditorStyles.boldLabel);
                color = EditorGUILayout.ColorField(color);
                if (GUILayout.Button("setColor"))
                    Send(bridge, ColorCommand(color));

                EditorGUILayout.Space(8f);
                EditorGUILayout.LabelField("Camera", EditorStyles.boldLabel);
                var next = GUILayout.SelectionGrid(cameraIndex - 1, CameraLabels, CameraLabels.Length);
                if (next != cameraIndex - 1)
                {
                    cameraIndex = next + 1;
                    Send(bridge, "{\"op\":\"setCamera\",\"index\":" + cameraIndex.ToString(CultureInfo.InvariantCulture) + "}");
                }
            }

            EditorGUILayout.Space(8f);
            EditorGUILayout.LabelField("Events", EditorStyles.boldLabel);
            using (var view = new EditorGUILayout.ScrollViewScope(scroll, GUILayout.ExpandHeight(true)))
            {
                scroll = view.scrollPosition;
                for (var i = 0; i < log.Count; i++)
                    EditorGUILayout.LabelField(log[i], EditorStyles.wordWrappedLabel);
            }
        }

        static void RequestPlayFromEntrypoint()
        {
            if (EditorApplication.isPlaying)
            {
                SessionState.SetBool(RestartKey, true);
                EditorApplication.isPlaying = false;
                return;
            }

            PlayFromEntrypoint();
        }

        static void PlayFromEntrypoint()
        {
            if (!EditorSceneManager.SaveCurrentModifiedScenesIfUserWantsTo())
                return;

            if (EditorSceneManager.GetActiveScene().path != EntrypointPath)
                EditorSceneManager.OpenScene(EntrypointPath);

            EditorApplication.isPlaying = true;
        }

        static Bridge FindBridge()
        {
            if (!EditorApplication.isPlaying)
                return null;

            return UnityEngine.Object.FindAnyObjectByType<Bridge>();
        }

        void Send(Bridge bridge, string json)
        {
            if (bridge == null)
                return;

            Append("→ " + json);
            bridge.OnCommand(json);
        }

        void OnLog(string condition, string stackTrace, LogType type)
        {
            if (type != LogType.Log || stackTrace == null)
                return;

            if (string.IsNullOrEmpty(condition) || !condition.StartsWith(LogPrefix, StringComparison.Ordinal))
                return;

            Append(condition.Substring(LogPrefix.Length));
        }

        void Append(string line)
        {
            log.Add(line);
            if (log.Count > LogLimit)
                log.RemoveAt(0);

            scroll.y = float.MaxValue;
            Repaint();
        }

        static string ColorCommand(Color value)
        {
            var culture = CultureInfo.InvariantCulture;
            return "{\"op\":\"setColor\",\"r\":" + value.r.ToString(culture)
                + ",\"g\":" + value.g.ToString(culture)
                + ",\"b\":" + value.b.ToString(culture) + "}";
        }
    }
}
