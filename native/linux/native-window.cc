#include <napi.h>

#include <X11/Xatom.h>
#include <X11/Xlib.h>

#include <cstdint>
#include <cstring>
#include <mutex>
#include <stdexcept>

namespace {

struct MotifWmHints {
    unsigned long flags;
    unsigned long functions;
    unsigned long decorations;
    long inputMode;
    unsigned long status;
};

constexpr unsigned long MWM_HINTS_DECORATIONS = 1L << 1;
constexpr unsigned long MWM_DECOR_ALL = 1L;

std::mutex xErrorMutex;
bool xErrorOccurred = false;

int CaptureXError(
    Display*,
    XErrorEvent*
) {
    xErrorOccurred = true;
    return 0;
}

bool ReadWindowHandle(
    const Napi::Value& value,
    Window* window
) {
    if (!value.IsBuffer() || window == nullptr) {
        return false;
    }

    const auto buffer =
        value.As<Napi::Buffer<unsigned char>>();

    if (buffer.Length() == sizeof(std::uint32_t)) {
        std::uint32_t xid = 0;

        std::memcpy(
            &xid,
            buffer.Data(),
            sizeof(xid)
        );

        *window = static_cast<Window>(xid);
        return xid != 0;
    }

    if (buffer.Length() == sizeof(Window)) {
        Window xid = 0;

        std::memcpy(
            &xid,
            buffer.Data(),
            sizeof(xid)
        );

        *window = xid;
        return xid != 0;
    }

    return false;
}

Window RequireWindow(
    const Napi::CallbackInfo& info
) {
    if (info.Length() != 1) {
        throw std::invalid_argument(
            "Expected one BrowserWindow native handle"
        );
    }

    Window window = 0;

    if (!ReadWindowHandle(info[0], &window)) {
        throw std::invalid_argument(
            "Expected BrowserWindow.getNativeWindowHandle() "
            "containing an X11 Window ID"
        );
    }

    return window;
}

Display* RequireDisplay() {
    Display* display = XOpenDisplay(nullptr);

    if (display == nullptr) {
        throw std::runtime_error(
            "Cannot connect to the X11 display. "
            "Start Electron with --ozone-platform=x11."
        );
    }

    return display;
}

bool IsValidWindow(
    Display* display,
    Window window
) {
    std::lock_guard<std::mutex> lock(xErrorMutex);

    /*
     * Finish earlier requests before installing our temporary handler.
     */
    XSync(display, False);

    xErrorOccurred = false;

    int (*previousHandler)(Display*, XErrorEvent*) =
        XSetErrorHandler(CaptureXError);

    XWindowAttributes attributes{};

    const Status status = XGetWindowAttributes(
        display,
        window,
        &attributes
    );

    XSync(display, False);
    XSetErrorHandler(previousHandler);

    return status != 0 && !xErrorOccurred;
}

bool SetNativeDecorations(
    Display* display,
    Window window
) {
    std::lock_guard<std::mutex> lock(xErrorMutex);

    XSync(display, False);
    xErrorOccurred = false;

    int (*previousHandler)(Display*, XErrorEvent*) =
        XSetErrorHandler(CaptureXError);

    const Atom motifHintsAtom = XInternAtom(
        display,
        "_MOTIF_WM_HINTS",
        False
    );

    MotifWmHints hints{};
    hints.flags = MWM_HINTS_DECORATIONS;
    hints.decorations = MWM_DECOR_ALL;

    XChangeProperty(
        display,
        window,
        motifHintsAtom,
        motifHintsAtom,
        32,
        PropModeReplace,
        reinterpret_cast<unsigned char*>(&hints),
        5
    );

    XFlush(display);
    XSync(display, False);

    XSetErrorHandler(previousHandler);

    return !xErrorOccurred;
}

double ReadTopFrameExtent(
    Display* display,
    Window window
) {
    const Atom frameExtentsAtom = XInternAtom(
        display,
        "_NET_FRAME_EXTENTS",
        True
    );

    if (frameExtentsAtom == None) {
        return 0;
    }

    std::lock_guard<std::mutex> lock(xErrorMutex);

    XSync(display, False);
    xErrorOccurred = false;

    int (*previousHandler)(Display*, XErrorEvent*) =
        XSetErrorHandler(CaptureXError);

    Atom actualType = None;
    int actualFormat = 0;
    unsigned long itemCount = 0;
    unsigned long bytesRemaining = 0;
    unsigned char* data = nullptr;

    const int status = XGetWindowProperty(
        display,
        window,
        frameExtentsAtom,
        0,
        4,
        False,
        XA_CARDINAL,
        &actualType,
        &actualFormat,
        &itemCount,
        &bytesRemaining,
        &data
    );

    XSync(display, False);
    XSetErrorHandler(previousHandler);

    double topInset = 0;

    /*
     * _NET_FRAME_EXTENTS:
     * left, right, top, bottom
     */
    if (
        !xErrorOccurred &&
        status == Success &&
        actualType == XA_CARDINAL &&
        actualFormat == 32 &&
        itemCount >= 4 &&
        data != nullptr
    ) {
        const auto* extents =
            reinterpret_cast<unsigned long*>(data);

        topInset = static_cast<double>(extents[2]);
    }

    if (data != nullptr) {
        XFree(data);
    }

    return topInset;
}

Napi::Value Configure(
    const Napi::CallbackInfo& info
) {
    Napi::Env env = info.Env();
    Display* display = nullptr;

    try {
        const Window window = RequireWindow(info);
        display = RequireDisplay();

        if (!IsValidWindow(display, window)) {
            XCloseDisplay(display);
            display = nullptr;

            throw std::runtime_error(
                "Electron did not provide a valid X11 Window. "
                "Start Electron with --ozone-platform=x11."
            );
        }

        if (!SetNativeDecorations(display, window)) {
            XCloseDisplay(display);
            display = nullptr;

            throw std::runtime_error(
                "Failed to configure native X11 window decorations"
            );
        }

        XCloseDisplay(display);
        display = nullptr;

        return Napi::Number::New(env, 0);
    } catch (const std::exception& error) {
        if (display != nullptr) {
            XCloseDisplay(display);
        }

        Napi::Error::New(env, error.what())
            .ThrowAsJavaScriptException();

        return env.Undefined();
    }
}

Napi::Value TopInset(
    const Napi::CallbackInfo& info
) {
    Napi::Env env = info.Env();
    Display* display = nullptr;

    try {
        const Window window = RequireWindow(info);
        display = RequireDisplay();

        if (!IsValidWindow(display, window)) {
            XCloseDisplay(display);
            display = nullptr;

            throw std::runtime_error(
                "Cannot measure native frame extents because "
                "the supplied handle is not a valid X11 Window"
            );
        }

        /*
         * Read the native value so the integration can verify that the
         * window manager has decorated the window.
         */
        const double nativeTopExtent =
            ReadTopFrameExtent(display, window);

        XCloseDisplay(display);
        display = nullptr;

        /*
         * With Electron frame:true, the web content begins below the
         * native title bar. Therefore the renderer requires no additional
         * top padding.
         *
         * Change this to `nativeTopExtent` only if using an overlay title
         * bar where web content extends beneath the native decoration.
         */
        static_cast<void>(nativeTopExtent);

        return Napi::Number::New(env, 0);
    } catch (const std::exception& error) {
        if (display != nullptr) {
            XCloseDisplay(display);
        }

        Napi::Error::New(env, error.what())
            .ThrowAsJavaScriptException();

        return env.Undefined();
    }
}

Napi::Value UnsupportedTabOperation(
    const Napi::CallbackInfo& info
) {
    Napi::Env env = info.Env();

    Napi::Error::New(
        env,
        "Linux window managers do not provide "
        "macOS-style native window tabs"
    ).ThrowAsJavaScriptException();

    return env.Undefined();
}

Napi::Object Init(
    Napi::Env env,
    Napi::Object exports
) {
    exports.Set(
        "configure",
        Napi::Function::New(env, Configure)
    );

    exports.Set(
        "topInset",
        Napi::Function::New(env, TopInset)
    );

    exports.Set(
        "addTab",
        Napi::Function::New(
            env,
            UnsupportedTabOperation
        )
    );

    exports.Set(
        "selectNextTab",
        Napi::Function::New(
            env,
            UnsupportedTabOperation
        )
    );

    exports.Set(
        "selectPreviousTab",
        Napi::Function::New(
            env,
            UnsupportedTabOperation
        )
    );

    exports.Set(
        "showTabOverview",
        Napi::Function::New(
            env,
            UnsupportedTabOperation
        )
    );

    exports.Set(
        "moveTabToNewWindow",
        Napi::Function::New(
            env,
            UnsupportedTabOperation
        )
    );

    exports.Set(
        "mergeAllWindows",
        Napi::Function::New(
            env,
            UnsupportedTabOperation
        )
    );

    exports.Set(
        "toggleTabBar",
        Napi::Function::New(
            env,
            UnsupportedTabOperation
        )
    );

    return exports;
}

} // namespace

NODE_API_MODULE(native_window, Init)