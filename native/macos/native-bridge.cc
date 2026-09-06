#include <napi.h>
#include <cstring>

extern "C" double termx_configure(void *view);
extern "C" double termx_top_inset(void *view);

using SwiftFunction = double (*)(void *);

static Napi::Value CallSwift(
    const Napi::CallbackInfo &info,
    SwiftFunction function
) {
    Napi::Env env = info.Env();

    if (info.Length() != 1 || !info[0].IsBuffer()) {
        Napi::TypeError::New(
            env,
            "Expected BrowserWindow.getNativeWindowHandle()"
        ).ThrowAsJavaScriptException();

        return env.Undefined();
    }

    auto buffer = info[0].As<Napi::Buffer<unsigned char>>();

    if (buffer.Length() != sizeof(void *)) {
        Napi::TypeError::New(
            env,
            "Invalid native handle size"
        ).ThrowAsJavaScriptException();

        return env.Undefined();
    }

    void *pointer = nullptr;
    std::memcpy(&pointer, buffer.Data(), sizeof(pointer));

    const double result = function(pointer);

    if (result < 0) {
        Napi::Error::New(
            env,
            "Swift window call failed: use a live window on the main thread"
        ).ThrowAsJavaScriptException();

        return env.Undefined();
    }

    return Napi::Number::New(env, result);
}

static Napi::Object Init(Napi::Env env, Napi::Object exports) {
    exports.Set(
        "configure",
        Napi::Function::New(env, [](const Napi::CallbackInfo &info) {
            return CallSwift(info, termx_configure);
        })
    );

    exports.Set(
        "topInset",
        Napi::Function::New(env, [](const Napi::CallbackInfo &info) {
            return CallSwift(info, termx_top_inset);
        })
    );

    return exports;
}

NODE_API_MODULE(native_window, Init)