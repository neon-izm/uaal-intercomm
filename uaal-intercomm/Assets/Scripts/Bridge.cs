using System;
using System.Collections;
using System.Runtime.InteropServices;
using UnityEngine;
using UnityEngine.AddressableAssets;
using UnityEngine.ResourceManagement.AsyncOperations;
using UnityEngine.SceneManagement;

namespace UaalIntercomm
{
    public sealed class Bridge : MonoBehaviour
    {
        public const string ObjectName = "Bridge";
        public const string AndroidCallbackClass = "dev.uaal.intercomm.UnityCallbacks";
        public const string AndroidCallbackMethod = "onBridgeEvent";

        const string MainScene = "main";

        bool ready;
        bool busy;
        AsyncOperationHandle<GameObject> prefabHandle;

        void Awake()
        {
            DontDestroyOnLoad(gameObject);
        }

        void Start()
        {
            ready = true;
            Emit("{\"event\":\"ready\"}");
        }

        void OnDestroy()
        {
            ReleasePrefab();
        }

        public void OnCommand(string json)
        {
            if (!ready)
            {
                Fail("command", "not ready");
                return;
            }

            var command = JsonUtility.FromJson<CommandDto>(json);
            if (command == null || string.IsNullOrEmpty(command.op))
            {
                Fail("command", "invalid command");
                return;
            }

            if (!TryGetKind(command.op, out var kind))
            {
                Fail(command.op, "unknown op");
                return;
            }

            switch (kind)
            {
                case CommandKind.Load:
                    StartCoroutine(LoadMain());
                    break;
                case CommandKind.LoadPrefab:
                    StartCoroutine(LoadPrefab(command.id));
                    break;
                case CommandKind.SetColor:
                    ApplyColor(command.r, command.g, command.b);
                    break;
                case CommandKind.SetCamera:
                    ApplyCamera(command.index);
                    break;
                default:
                    throw new ArgumentOutOfRangeException(nameof(kind), kind, null);
            }
        }

        IEnumerator LoadMain()
        {
            if (busy)
            {
                Fail("load", "busy");
                yield break;
            }

            var scene = SceneManager.GetSceneByName(MainScene);
            if (scene.isLoaded)
            {
                Emit("{\"event\":\"loaded\"}");
                yield break;
            }

            busy = true;
            var operation = SceneManager.LoadSceneAsync(MainScene, LoadSceneMode.Additive);
            yield return operation;
            busy = false;

            if (operation == null || !operation.isDone || MainStage.Current == null)
            {
                Fail("load", "scene load failed");
                yield break;
            }

            Emit("{\"event\":\"loaded\"}");
        }

        IEnumerator LoadPrefab(string id)
        {
            if (!IsKnownPrefab(id))
            {
                Fail("loadPrefab", "unknown prefab");
                yield break;
            }

            if (MainStage.Current == null)
            {
                Fail("loadPrefab", "main is not loaded");
                yield break;
            }

            if (busy)
            {
                Fail("loadPrefab", "busy");
                yield break;
            }

            busy = true;
            var operation = Addressables.LoadAssetAsync<GameObject>(id);
            yield return operation;
            busy = false;

            if (operation.Status != AsyncOperationStatus.Succeeded || operation.Result == null)
            {
                if (operation.IsValid())
                    Addressables.Release(operation);
                Fail("loadPrefab", "prefab load failed");
                yield break;
            }

            var stage = MainStage.Current;
            if (stage == null)
            {
                Addressables.Release(operation);
                Fail("loadPrefab", "main is not loaded");
                yield break;
            }

            ReleasePrefab();
            prefabHandle = operation;
            var instance = Instantiate(operation.Result, stage.Anchor);
            instance.name = id;
            stage.AttachCar(instance);
            Emit($"{{\"event\":\"prefabLoaded\",\"id\":\"{id}\"}}");
        }

        void ApplyColor(float r, float g, float b)
        {
            if (MainStage.Current == null)
            {
                Fail("setColor", "main is not loaded");
                return;
            }

            if (MainStage.Current.HasCar == false)
            {
                Fail("setColor", "no car");
                return;
            }

            if (IsUnit(r) == false || IsUnit(g) == false || IsUnit(b) == false)
            {
                Fail("setColor", "color out of range");
                return;
            }

            MainStage.Current.SetColor(new Color(r, g, b, 1f));
        }

        void ApplyCamera(int index)
        {
            if (index != 1 && index != 2 && index != 3)
            {
                Fail("setCamera", "camera index out of range");
                return;
            }

            if (MainStage.Current == null)
            {
                Fail("setCamera", "main is not loaded");
                return;
            }

            MainStage.Current.SetCamera(index);
        }

        void ReleasePrefab()
        {
            if (prefabHandle.IsValid())
                Addressables.Release(prefabHandle);
            prefabHandle = default;
        }

        static bool IsKnownPrefab(string id)
        {
            return id == "carA" || id == "carB" || id == "carC";
        }

        static bool IsUnit(float value)
        {
            return float.IsNaN(value) == false && value >= 0f && value <= 1f;
        }

        static bool TryGetKind(string op, out CommandKind kind)
        {
            switch (op)
            {
                case "load":
                    kind = CommandKind.Load;
                    return true;
                case "loadPrefab":
                    kind = CommandKind.LoadPrefab;
                    return true;
                case "setColor":
                    kind = CommandKind.SetColor;
                    return true;
                case "setCamera":
                    kind = CommandKind.SetCamera;
                    return true;
                default:
                    kind = default;
                    return false;
            }
        }

        static void Emit(string json)
        {
            Debug.Log("[Bridge] " + json);
#if UNITY_IOS && !UNITY_EDITOR
            OnBridgeEvent(json);
#elif UNITY_ANDROID && !UNITY_EDITOR
            using var callbacks = new AndroidJavaClass(AndroidCallbackClass);
            callbacks.CallStatic(AndroidCallbackMethod, json);
#endif
        }

        static void Fail(string op, string message)
        {
            Emit($"{{\"event\":\"error\",\"op\":\"{op}\",\"message\":\"{message}\"}}");
        }

#if UNITY_IOS && !UNITY_EDITOR
        [DllImport("__Internal")]
        static extern void OnBridgeEvent(string json);
#endif

        enum CommandKind
        {
            Load,
            LoadPrefab,
            SetColor,
            SetCamera,
        }

        [Serializable]
        sealed class CommandDto
        {
            public string op;
            public string id;
            public float r;
            public float g;
            public float b;
            public int index;
        }
    }
}
