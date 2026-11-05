using UnityEngine;

namespace UaalIntercomm
{
    public sealed class MainStage : MonoBehaviour
    {
        public static MainStage Current { get; private set; }

        Transform anchor;
        Camera front;
        Camera side;
        Camera top;
        GameObject car;
        MaterialPropertyBlock block;
        Color color = Color.white;

        public bool HasCar => car != null;

        void Awake()
        {
            anchor = transform.Find("Anchor");
            front = transform.Find("Camera1").GetComponent<Camera>();
            side = transform.Find("Camera2").GetComponent<Camera>();
            top = transform.Find("Camera3").GetComponent<Camera>();
            Current = this;
            ApplyCamera(1);
        }

        void OnDestroy()
        {
            if (Current == this)
                Current = null;
        }

        public Transform Anchor => anchor;

        public void AttachCar(GameObject instance)
        {
            if (car != null)
                Destroy(car);

            car = instance;
            if (car != null)
                ApplyColor();
        }

        public void SetColor(Color next)
        {
            color = next;
            ApplyColor();
        }

        public void SetCamera(int index)
        {
            ApplyCamera(index);
        }

        void ApplyCamera(int index)
        {
            front.gameObject.SetActive(index == 1);
            side.gameObject.SetActive(index == 2);
            top.gameObject.SetActive(index == 3);
        }

        void ApplyColor()
        {
            if (car == null)
                return;

            block ??= new MaterialPropertyBlock();
            var renderers = car.GetComponentsInChildren<Renderer>(true);
            for (var i = 0; i < renderers.Length; i++)
            {
                var renderer = renderers[i];
                renderer.GetPropertyBlock(block);
                block.SetColor("_BaseColor", color);
                renderer.SetPropertyBlock(block);
            }
        }
    }
}
