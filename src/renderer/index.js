import {Terminal} from "@xterm/xterm";
import '@xterm/xterm/css/xterm.css'
import {FitAddon} from "@xterm/addon-fit";
import './styles.css'

const container = document.getElementById('terminal');

const terminal = new Terminal({
    allowTransparency: true,
    cursorBlink: true,
    cursorStyle: "bar",
    fontFamily: 'Menlo, Monaco, "SF Mono", monospace',
    fontSize: 14,
    lineHeight: 1.25,
    scrollback: 10000,

    theme: {
        background: "#00000000",
        foreground: "#edf1f7",
        cursor: "#a9c9ff",
        selectionBackground: "#91b6ff55",
        black: "#38404d",
        red: "#ff8090",
        green: "#a3dfaa",
        yellow: "#f2d49b",
        blue: "#94baff",
        magenta: "#d7b0ff",
        cyan: "#95dce5",
        white: "#edf1f7",
    }
});

const fit = new FitAddon();
terminal.loadAddon(fit);
terminal.open(container)

let running = false;
let exited = false;
let disposed = false

let fitFrame = 0;
let layoutFrame = 0;
let latestInsetRequest = 0;

const removeExit = window.terminalApi.onExit((code) => {
    exited = true;
    running = false;

    if (!disposed) {
        terminal.writeln(`\r\n[Shell exited with code ${code}]`);
    }
});

const inputSub = terminal.onData((data) => {
    if (running && !disposed) window.terminalApi.input(data);
});

function fitTerminal() {
    if (disposed) return;
    if (!container.clientWidth || !container.clientHeight) return;

    fit.fit()

    if (running) {
        window.terminalApi.resize({
            cols: terminal.cols,
            rows: terminal.rows,
        });
    }
}

function scheduleFit() {
    if (disposed) return;
    cancelAnimationFrame(fitFrame);
    fitFrame = requestAnimationFrame(fitTerminal);
}

async function updateNativeInset() {
    if (disposed) return;

    const request = ++latestInsetRequest;

    try {
        const inset = await window.terminalApi.topInset();

        if (disposed || request !== latestInsetRequest) return;

        if (!Number.isFinite(inset) || inset < 0) {
            throw new Error("Invalid native title-bar inset");
        }

        document.documentElement.style.setProperty(
            "--native-titlebar-inset",
            `${inset}px`
        );
    } catch (error) {
        if (!disposed) {
            console.error(
                "Native title-bar measurement failed:",
                error
            );
        }
    }
}

function scheduleNativeLayout() {
    if (disposed) return;

    cancelAnimationFrame(layoutFrame);

    layoutFrame = requestAnimationFrame(() => {
        void updateNativeInset();
    });
}

const removeData = window.terminalApi.onData((data) => {
    if (!disposed) {
        terminal.write(data);
    }
});

const removeWindowLayout = window.terminalApi.onWindowLayout(scheduleNativeLayout)

const observer = new ResizeObserver(scheduleFit);

observer.observe(container);

window.addEventListener("resize", scheduleNativeLayout)

async function start() {
    try {
        await document.fonts.ready;
        await updateNativeInset();

        if (disposed) return;

        fitTerminal()

        await window.terminalApi.start({
            cols: terminal.cols,
            rows: terminal.rows
        });

        if (disposed || exited) return;

        running = true
        fitTerminal()
        terminal.focus();
    } catch (error) {
        if (!disposed) {
            terminal.writeln(`\r\n[Could not start shell]\r\n${error.message}`)
        }
    }

}

window.addEventListener("beforeunload", () => {
    disposed = true
    running = false
    cancelAnimationFrame(fitFrame);
    cancelAnimationFrame(layoutFrame)
    observer.disconnect()
    window.removeEventListener("resize", scheduleNativeLayout);
    inputSub.dispose();
    removeData()
    removeExit();
    removeWindowLayout();
    terminal.dispose();
});

void start();
