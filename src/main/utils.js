const path = require("node:path");
const { pathToFileURL } = require("node:url");

const rendererPath = path.resolve(
    __dirname,
    "../renderer/index.html"
);

const rendererUrl = pathToFileURL(rendererPath).href;

function validSender(event) {
    return (
        !event.sender.isDestroyed() &&
        event.senderFrame === event.sender.mainFrame &&
        event.senderFrame?.url === rendererUrl
    );
}

function validSize(size) {
    return (
        size !== null &&
        typeof size === "object" &&
        Number.isInteger(size.cols) &&
        Number.isInteger(size.rows) &&
        size.cols >= 2 &&
        size.cols <= 1000 &&
        size.rows >= 1 &&
        size.rows <= 500
    );
}

function stopSession(id, sessions) {
    const terminal = sessions.get(id);

    sessions.delete(id);

    if (terminal) {
        try {
            terminal.kill();
        } catch {
            // The process may already have exited.
        }
    }
}

function sendToRenderer(webContents, channel, value) {
    if (!webContents.isDestroyed()) {
        webContents.send(channel, value);
    }
}

module.exports = {
    rendererPath,
    validSender,
    validSize,
    stopSession,
    sendToRenderer,
};