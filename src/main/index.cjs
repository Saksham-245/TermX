const path = require("node:path");
const {BrowserWindow, app, ipcMain} = require('electron')
const {validSender, validSize, sendToRenderer, stopSession, rendererPath} = require("./utils");
const pty = require('node-pty')
const os = require("node:os");

app.setName("TermX")
app.setAboutPanelOptions({
    applicationName: "TermX",
    applicationVersion: app.getVersion(),
    version: app.getVersion(),
});

const sessions = new Map();

let nativeWindow;

ipcMain.handle("terminal:start", (event, size) => {
    if (!validSender(event) || !validSize(size)) {
        throw new Error("Invalid terminal request");
    }

    const id = event.sender.id;

    if (sessions.has(id)) return;
    const terminal = pty.spawn(process.env.SHELL || "/bin/zsh", ["-l"], {
        name: "xterm-256color",
        cols: size.cols,
        rows: size.rows,
        cwd: os.homedir(),
        env: {
            ...process.env,
            TERM: "xterm-256color",
            COLORTERM: "truecolor",
            TERM_PROGRAM: "TermX"
        }
    });

    sessions.set(id, terminal);

    terminal.onData((data) => {
        if (sessions.get(id) !== terminal) return;

        sendToRenderer(event.sender, "terminal:data", data);
    });

    terminal.onExit(({exitCode}) => {
        if (sessions.get(id) === terminal) {
            sessions.delete(id);
        }
        sendToRenderer(event.sender, "terminal:exit", exitCode);
    })
});

ipcMain.on("terminal:input", (event, data) => {
    if (!validSender(event) || typeof data !== "string") return;

    const terminal = sessions.get(event.sender.id);

    if (!terminal) return;

    try {
        terminal.write(data);
    } catch (error) {
        console.error("Terminal input failed:", error);
    }
});

ipcMain.on("terminal:resize", (event, size) => {
    if (!validSender(event) || !validSize(size)) return;

    const terminal = sessions.get(event.sender.id);

    if (!terminal) return;

    try {
        terminal.resize(size.cols, size.rows);
    } catch (error) {
        console.error("Terminal resize failed:", error);
    }
});

ipcMain.handle("window:top-inset", (event) => {
    if (!validSender(event)) {
        throw new Error("Invalid window request")
    }

    const win = BrowserWindow.fromWebContents(event.sender);

    if (!win || win.isDestroyed()) return 0;

    return nativeWindow.topInset(
        win.getNativeWindowHandle()
    )
})


function createWindow() {
    const win = new BrowserWindow({
        title: "TermX",
        width: 1100,
        height: 720,
        minWidth: 500,
        minHeight: 320,
        show: false,

        transparent: true,
        backgroundColor: "#00000000",
        frame: true,
        titleBarStyle: "default",
        hasShadow: true,

        webPreferences: {
            nodeIntegration: false,
            sandbox: true,
            contextIsolation: true,
            preload: path.join(__dirname, '../preload/index.cjs'),
        }
    });

    const id = win.webContents.id;

    function notifyWindowLayout() {
        if (win.isDestroyed()) return;

        sendToRenderer(
            win.webContents,
            "window:layout",
            null
        );
    }

    win.webContents.setWindowOpenHandler(() => ({
        action: "deny"
    }));

    win.webContents.on("will-navigate", (event) => {
        event.preventDefault();
    })

    win.webContents.on("did-start-loading", () => {
        stopSession(id, sessions);
    });

    win.webContents.on("render-process-gone", () => {
        stopSession(id, sessions);
    });
    win.on("closed", () => {
        stopSession(id, sessions)
    })

    win.on("resize", notifyWindowLayout)
    win.on("enter-full-screen", notifyWindowLayout);
    win.on("leave-full-screen", notifyWindowLayout)

    try {
        nativeWindow.configure(
            win.getNativeWindowHandle()
        );

        win.setWindowButtonVisibility(true);
        win.loadFile(rendererPath);

        if (win.isDestroyed()) return;

        nativeWindow.configure(
            win.getNativeWindowHandle()
        );

        win.show()
        notifyWindowLayout()

    } catch (error) {
        if (!win.isDestroyed()) {
            win.destroy()
        }

        throw error;
    }

}

function reportStartupError(error) {
    console.error("TermX startup failed:", error);

    dialog.showErrorBox(
        "TermX could not start",
        `${error.message}\n\nRun npm run build:native and try again.`
    );
}

app.whenReady().then(async () => {
    try {
        nativeWindow = require("../../native/macos/build/Release/native_window")

        createWindow();

        app.on("activate", () => {
            if (BrowserWindow.getAllWindows().length === 0) {
                createWindow();
            }
        })
    } catch (error) {
        reportStartupError(error);
        app.quit();
    }
});

app.on("window-all-closed", () => {
    app.quit()
})

app.on("before-quit", () => {
    for (const id of sessions.keys()) {
        stopSession(id, sessions);
    }
})