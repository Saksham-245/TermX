const path = require("node:path");
const { BrowserWindow, app, ipcMain, dialog, Menu } = require("electron");
const {
  validSender,
  validSize,
  sendToRenderer,
  stopSession,
  rendererPath,
} = require("./utils");
const pty = require("node-pty");
const os = require("node:os");

app.setName("TermX");
app.setAboutPanelOptions({
  applicationName: "TermX",
  applicationVersion: app.getVersion(),
  version: app.getVersion(),
});

const sessions = new Map();

let nativeWindow = loadNativeWindow();

let nextSessionNumber = 1;

let currentSettingsJson = "{}";
let currentSettings = {};

let settingsTimer = null;

ipcMain.handle("terminal:start", (event, size) => {
  if (!validSender(event) || !validSize(size)) {
    throw new Error("Invalid terminal request");
  }

  const id = event.sender.id;

  if (sessions.has(id)) return;

  const settings = readNativeSettings().settings;

  const configureShell =
    typeof settings.shellPath === "string" ? settings.shellPath.trim() : "";

  const shell = configureShell || process.env.SHELL || "/bin/zsh";

  const args = settings.loginShell === false ? [] : ["-l"];

  const terminal = pty.spawn(shell, args, {
    name: "xterm-256color",
    cols: size.cols,
    rows: size.rows,
    cwd: os.homedir(),
    env: {
      ...process.env,
      TERM: "xterm-256color",
      COLORTERM: "truecolor",
      TERM_PROGRAM: "TermX",
    },
  });

  sessions.set(id, terminal);

  terminal.onData((data) => {
    if (sessions.get(id) !== terminal) return;

    sendToRenderer(event.sender, "terminal:data", data);
  });

  terminal.onExit(({ exitCode }) => {
    if (sessions.get(id) === terminal) {
      sessions.delete(id);
    }
    sendToRenderer(event.sender, "terminal:exit", exitCode);
  });
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
    throw new Error("Invalid window request");
  }

  const win = BrowserWindow.fromWebContents(event.sender);

  if (!win || win.isDestroyed()) return 0;

  return nativeWindow.topInset(win.getNativeWindowHandle());
});

ipcMain.handle("terminal:get-settings", (event) => {
  if (!validSender(event)) {
    throw new Error("Invalid settings request");
  }

  return readNativeSettings().settings;
});

function normalizeSettings(settings) {
  if (!settings || typeof settings !== "object" || Array.isArray(settings)) {
    return {};
  }

  return {
    ...settings,
  };
}

function createSettingsFingerprint(settings) {
  const keys = Object.keys(settings).sort();

  const orderedSettings = {};

  for (const key of keys) {
    orderedSettings[key] = settings[key];
  }

  return JSON.stringify(orderedSettings);
}

function readNativeSettings() {
  if (!nativeWindow || typeof nativeWindow.getSettings !== "function") {
    return {
      json: currentSettingsJson,
      settings: currentSettings,
    };
  }
  try {
    const nativeJson = nativeWindow.getSettings();
    const parsed = JSON.parse(nativeJson);
    const settings = normalizeSettings(parsed);

    const json = createSettingsFingerprint(settings);

    return {
      json,
      settings,
    };
  } catch (error) {
    console.error("Could not read settings:", error);

    return {
      json: currentSettingsJson,
      settings: currentSettings,
    };
  }
}

function getWindowOpacity(settings) {
  const value = Number(settings.windowOpacity ?? 1);

  if (!Number.isFinite(value)) {
    return 1;
  }

  return Math.min(1, Math.max(0.4, value));
}

function applyWindowSettings(win, settings) {
  if (!win || win.isDestroyed()) {
    return;
  }

  win.setOpacity(getWindowOpacity(settings));
}

function broadcastSettings() {
  const result = readNativeSettings();

  if (result.json === currentSettingsJson) {
    return;
  }

  currentSettingsJson = result.json;
  currentSettings = result.settings;

  for (const win of BrowserWindow.getAllWindows()) {
    if (win.isDestroyed()) continue;

    applyWindowSettings(win, currentSettings);

    sendToRenderer(win.webContents, "terminal:settings", currentSettings);
  }
}

function startSettingsMonitor() {
  if (settingsTimer !== null) {
    return;
  }

  const inital = readNativeSettings();

  currentSettingsJson = inital.json;
  currentSettings = inital.settings;

  settingsTimer = setInterval(broadcastSettings, 250);

  settingsTimer.unref();
}

function getFocusedWindow() {
  const win = BrowserWindow.getFocusedWindow();

  if (!win || win.isDestroyed()) {
    return null;
  }

  return win;
}

function loadNativeWindow() {
  switch (process.platform) {
    case "darwin":
      return require("../../native/macos/build/Release/native_window.node");
    case "linux":
      return require("../../native/linux/build/Release/native_window.node");
    default:
      throw new Error(`Native windows are unsupported on ${process.platform}`);
  }
}

function createNewTerminalTab() {
  const parentWindow = getFocusedWindow();

  createWindow(parentWindow);
}

function installApplicationMenu() {
  const menu = Menu.buildFromTemplate([
    {
      label: app.name,
      submenu: [
        { role: "about" },
        { type: "separator" },
        {
          label: "Settings",
          accelerator: "CommandorControl+,",
          enabled: typeof nativeWindow.showSettings === "function",
          click: () => {
            try {
              nativeWindow.showSettings();
            } catch (error) {
              console.error("Could not show settings:", error);
            }
          },
        },
        ...(process.platform === "darwin"
          ? [
              { type: "separator" },
              { role: "services" },
              { type: "separator" },
              { role: "hide" },
              { role: "hideOthers" },
              { role: "unhide" },
              { type: "separator" },
            ]
          : []),
        { role: "quit" },
      ],
    },
    {
      label: "Shell",
      submenu: [
        {
          label: "New Tab",
          accelerator: "CommandOrControl+T",
          click: createNewTerminalTab,
        },
        {
          label: "New Window",
          accelerator: "CommandOrControl+N",
          click: () => createWindow(),
        },
        { type: "separator" },
        {
          label: "Close Tab",
          accelerator: "CommandOrControl+W",
          role: "close",
        },
      ],
    },
  ]);
  Menu.setApplicationMenu(menu);
}

function createWindow(tabParent = null) {
  const sessionNumber = nextSessionNumber++;
  const sessionTitle = `Terminal ${sessionNumber}`;
  const win = new BrowserWindow({
    title: sessionTitle,
    width: 1100,
    height: 720,
    minWidth: 500,
    minHeight: 320,
    show: false,

    transparent: process.platform === "darwin",
    backgroundColor: process.platform === "darwin" ? "#00000000" : "#111318",
    frame: true,
    titleBarStyle: "default",
    hasShadow: true,

    webPreferences: {
      nodeIntegration: false,
      sandbox: true,
      contextIsolation: true,
      preload: path.join(__dirname, "../preload/index.cjs"),
    },
  });

  const id = win.webContents.id;

  win.webContents.on("page-title-updated", (event) => {
    event.preventDefault();

    if (!win.isDestroyed()) {
      win.setTitle(sessionTitle);
    }
  });

  function notifyWindowLayout() {
    if (win.isDestroyed() || win.webContents.isDestroyed()) return;

    sendToRenderer(win.webContents, "window:layout", null);
  }

  function notifySettledWindowLayout() {
    notifyWindowLayout();

    setTimeout(notifyWindowLayout, 50);
    setTimeout(notifyWindowLayout, 150);
  }

  win.webContents.setWindowOpenHandler(() => ({
    action: "deny",
  }));

  win.webContents.on("will-navigate", (event) => {
    event.preventDefault();
  });

  win.webContents.on("did-start-loading", () => {
    stopSession(id, sessions);
  });

  win.webContents.on("render-process-gone", () => {
    stopSession(id, sessions);
  });
  win.on("closed", () => {
    stopSession(id, sessions);
  });

  win.on("resize", notifySettledWindowLayout);
  win.on("focus", notifySettledWindowLayout);
  win.on("show", notifySettledWindowLayout);
  win.on("restore", notifySettledWindowLayout);
  win.on("enter-full-screen", notifySettledWindowLayout);
  win.on("leave-full-screen", notifySettledWindowLayout);
  win.on("new-window-for-tab", () => {
    createWindow(win);
  });

  try {
    nativeWindow.configure(win.getNativeWindowHandle());

    if (
      process.platform === "darwin" &&
      tabParent &&
      !tabParent.isDestroyed()
    ) {
      nativeWindow.addTab(
        tabParent.getNativeWindowHandle(),
        win.getNativeWindowHandle(),
      );

      if (!tabParent.webContents.isDestroyed()) {
        tabParent.webContents.send("window:layout", null);
      }
    }

    if (
      process.platform === "darwin" &&
      typeof win.setWindowButtonVisibility === "function"
    ) {
      win.setWindowButtonVisibility(true);
    }
    win.loadFile(rendererPath);

    if (win.isDestroyed()) return;

    nativeWindow.configure(win.getNativeWindowHandle());

    applyWindowSettings(win, currentSettings);

    win.show();
    notifySettledWindowLayout();
  } catch (error) {
    if (!win.isDestroyed()) {
      win.destroy();
    }

    throw error;
  }
}

function reportStartupError(error) {
  console.error("TermX startup failed:", error);

  dialog.showErrorBox(
    "TermX could not start",
    `${error.message}\n\nRun npm run build:native and try again.`,
  );
}

app.whenReady().then(async () => {
  try {
    switch (process.platform) {
      case "darwin":
        nativeWindow = require("../../native/macos/build/Release/native_window.node");
        break;

      case "linux":
        nativeWindow = require("../../native/linux/build/Release/native_window.node");
        break;

      default:
        throw new Error(
          `Unsupported native-window platform: ${process.platform}`,
        );
    }
    startSettingsMonitor();
    installApplicationMenu();
    createWindow();

    app.on("activate", () => {
      if (BrowserWindow.getAllWindows().length === 0) {
        createWindow();
      }
    });
  } catch (error) {
    reportStartupError(error);
    app.quit();
  }
});

app.on("window-all-closed", () => {
  app.quit();
});

app.on("before-quit", () => {
  if (settingsTimer !== null) {
    clearInterval(settingsTimer);
    settingsTimer = null;
  }
  for (const id of sessions.keys()) {
    stopSession(id, sessions);
  }
});
