const { contextBridge, ipcRenderer } = require("electron");

function subscribe(channel, callback) {
  const listener = (_event, value) => callback(value);

  ipcRenderer.on(channel, listener);

  return () => ipcRenderer.removeListener(channel, listener);
}

contextBridge.exposeInMainWorld("terminalApi", {
  start: (size) => ipcRenderer.invoke("terminal:start", size),
  input: (data) => ipcRenderer.send("terminal:input", data),
  resize: (size) => ipcRenderer.send("terminal:resize", size),
  topInset: () => ipcRenderer.invoke("window:top-inset"),
  getSettings: () => ipcRenderer.invoke("terminal:get-settings"),
  onData: (callback) => subscribe("terminal:data", callback),
  onExit: (callback) => subscribe("terminal:exit", callback),
  onWindowLayout: (callback) => subscribe("window:layout", callback),
  onSettings: (callback) => subscribe("terminal:settings", callback),
});
