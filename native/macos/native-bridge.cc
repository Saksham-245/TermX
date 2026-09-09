#include <cstdint>
#include <napi.h>

extern "C" double termx_configure(void *view);
extern "C" double termx_top_inset(void *view);

extern "C" double termx_add_tab(
    void *parentView,
    void *childView
);

extern "C" double termx_select_next_tab(void *view);
extern "C" double termx_select_previous_tab(void *view);
extern "C" double termx_show_tab_overview(void *view);
extern "C" double termx_move_tab_to_new_window(void *view);
extern "C" double termx_merge_all_windows(void *view);
extern "C" double termx_toggle_tab_bar(void *view);

extern "C" double termx_show_settings();
extern "C" int32_t termx_get_settings(
    char *buffer,
    int32_t capacity
);


using UnarySwiftFunction = double (*)(void *);
using BinarySwiftFunction = double (*)(void *, void *);

static bool ReadNativeHandle(
    const Napi::Value &value,
    void **pointer
) {
    if (!value.IsBuffer()) {
        return false;
    }

    const auto buffer =
        value.As<Napi::Buffer<unsigned char>>();

    if (buffer.Length() != sizeof(void *)) {
        return false;
    }

    std::memcpy(
        pointer,
        buffer.Data(),
        sizeof(void *)
    );

    return *pointer != nullptr;
}

static Napi::Value CallUnarySwift(
    const Napi::CallbackInfo &info,
    UnarySwiftFunction function
) {
    Napi::Env env = info.Env();

    void *pointer = nullptr;

    if (
        info.Length() != 1 ||
        !ReadNativeHandle(info[0], &pointer)
    ) {
        Napi::TypeError::New(
            env,
            "Expected BrowserWindow.getNativeWindowHandle()"
        ).ThrowAsJavaScriptException();

        return env.Undefined();
    }

    const double result = function(pointer);

    if (result < 0) {
        Napi::Error::New(
            env,
            "Swift window operation failed"
        ).ThrowAsJavaScriptException();

        return env.Undefined();
    }

    return Napi::Number::New(env, result);
}

static Napi::Value CallBinarySwift(
    const Napi::CallbackInfo &info,
    BinarySwiftFunction function
) {
    Napi::Env env = info.Env();

    void *firstPointer = nullptr;
    void *secondPointer = nullptr;

    if (
        info.Length() != 2 ||
        !ReadNativeHandle(info[0], &firstPointer) ||
        !ReadNativeHandle(info[1], &secondPointer)
    ) {
        Napi::TypeError::New(
            env,
            "Expected two BrowserWindow native handles"
        ).ThrowAsJavaScriptException();

        return env.Undefined();
    }

    const double result = function(
        firstPointer,
        secondPointer
    );

    if (result < 0) {
        Napi::Error::New(
            env,
            "Swift tab operation failed"
        ).ThrowAsJavaScriptException();

        return env.Undefined();
    }

    return Napi::Number::New(env, result);
}

static Napi::Value ShowSettings(
    const Napi::CallbackInfo &info
) {
    Napi::Env env = info.Env();

    const double result = termx_show_settings();

    if (result < 0) {
        Napi::Error::New(
            env,
            "Could not show native settings"
        ).ThrowAsJavaScriptException();

        return env.Undefined();
    }

    return env.Undefined();
}

static Napi::Value GetSettings(
    const Napi::CallbackInfo &info
) {
    Napi::Env env = info.Env();

    constexpr int32_t capacity = 16 * 1024;
    char buffer[capacity] = {};

    const int32_t length = termx_get_settings(buffer, capacity);

    if (length < 0) {
        Napi::Error::New(
            env,
            "Could not read native settings"
        ).ThrowAsJavaScriptException();

        return env.Undefined();
    }

    return Napi::String::New(
        env,
        buffer,
        static_cast<size_t>(length)
    );
}

static Napi::Object Init(
    Napi::Env env,
    Napi::Object exports
) {
    exports.Set(
        "configure",
        Napi::Function::New(
            env,
            [](const Napi::CallbackInfo &info) {
                return CallUnarySwift(
                    info,
                    termx_configure
                );
            }
        )
    );

    exports.Set(
        "topInset",
        Napi::Function::New(
            env,
            [](const Napi::CallbackInfo &info) {
                return CallUnarySwift(
                    info,
                    termx_top_inset
                );
            }
        )
    );

    exports.Set(
        "addTab",
        Napi::Function::New(
            env,
            [](const Napi::CallbackInfo &info) {
                return CallBinarySwift(
                    info,
                    termx_add_tab
                );
            }
        )
    );

    exports.Set(
        "selectNextTab",
        Napi::Function::New(
            env,
            [](const Napi::CallbackInfo &info) {
                return CallUnarySwift(
                    info,
                    termx_select_next_tab
                );
            }
        )
    );

    exports.Set(
        "selectPreviousTab",
        Napi::Function::New(
            env,
            [](const Napi::CallbackInfo &info) {
                return CallUnarySwift(
                    info,
                    termx_select_previous_tab
                );
            }
        )
    );

    exports.Set(
        "showTabOverview",
        Napi::Function::New(
            env,
            [](const Napi::CallbackInfo &info) {
                return CallUnarySwift(
                    info,
                    termx_show_tab_overview
                );
            }
        )
    );

    exports.Set(
        "moveTabToNewWindow",
        Napi::Function::New(
            env,
            [](const Napi::CallbackInfo &info) {
                return CallUnarySwift(
                    info,
                    termx_move_tab_to_new_window
                );
            }
        )
    );

    exports.Set(
        "mergeAllWindows",
        Napi::Function::New(
            env,
            [](const Napi::CallbackInfo &info) {
                return CallUnarySwift(
                    info,
                    termx_merge_all_windows
                );
            }
        )
    );

    exports.Set(
        "toggleTabBar",
        Napi::Function::New(
            env,
            [](const Napi::CallbackInfo &info) {
                return CallUnarySwift(
                    info,
                    termx_toggle_tab_bar
                );
            }
        )
    );

    exports.Set(
        "showSettings",
        Napi::Function::New(env, ShowSettings)
    );

    exports.Set(
        "getSettings",
        Napi::Function::New(env, GetSettings)
    );

    return exports;
}

NODE_API_MODULE(native_window, Init)