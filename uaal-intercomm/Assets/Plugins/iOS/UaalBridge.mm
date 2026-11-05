#import <Foundation/Foundation.h>

typedef void (*UaalBridgeEventHandler)(const char *json);

static UaalBridgeEventHandler uaal_handler = NULL;

extern "C"
{
    __attribute__((visibility("default")))
    void OnBridgeEvent(const char *json)
    {
        if (uaal_handler != NULL && json != NULL)
            uaal_handler(json);
    }

    __attribute__((visibility("default")))
    void UaalSetBridgeEventHandler(UaalBridgeEventHandler handler)
    {
        uaal_handler = handler;
    }
}
