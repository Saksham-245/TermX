import { Terminal } from "@xterm/xterm";
import "@xterm/xterm/css/xterm.css";
import { FitAddon } from "@xterm/addon-fit";
import "./styles.css";
import {SearchAddon} from "@xterm/addon-search";

const container = document.getElementById("terminal");

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
  },
});

const fit = new FitAddon();
terminal.loadAddon(fit);
const search = new SearchAddon();
terminal.loadAddon(search)
terminal.open(container);

const searchForm = document.getElementById("terminal-search");
const searchInput = document.getElementById("terminal-search-input");
const searchStatus = document.getElementById("terminal-search-status");

const searchOptions = {
  caseSensitive: true,
  incremental: true,
  decorations: {
    matchBackground: "#5777a955",
    matchBorder: "#91b6ff",
    matchOverviewRuler: "#91b6ff",
    activeMatchBackground: "#91b6ff99",
    activeMatchBorder: "#edf1f7",
    activeMatchColorOverviewRuler: "#edf1f7",
  },
}

function runSearch(direction = "next") {
  const query = searchInput.value;

  if (!query) {
    search.clearDecorations();
    searchStatus.textContent = ""
    return;
  }

  const found = direction === "previous" ? search.findPrevious(query, searchOptions)
      : search.findNext(query, searchOptions);

  searchStatus.textContent = found ? "" : "No matches";
}

function openSearch() {
  searchForm.hidden = false;

  const selectedText = document.getSelection().trim();

  if (selectedText && !searchInput.value) {
    searchInput.value = selectedText;

    requestAnimationFrame(() => {
      searchInput.focus();
      searchInput.select();

      if (searchInput.value) {
        runSearch();
      }
    })
  }
}

function closeSearch() {
  searchForm.hidden = true;
  searchStatus.textContent = "";
  search.clearDecorations();
  terminal.focus();
}

function handleSearchShortcut(event) {
  if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "f") {
    event.preventDefault();
    openSearch();
    return;
  }

  if (event.key === "Escape" && !searchForm.hidden) {
    event.preventDefault();
    closeSearch();
  }
}

function handleSearchSubmit(event) {
  event.preventDefault();
  runSearch(event.shiftKey ? "previous" : "next");
}

function handleSearchClick(event) {
  const action = event.target.closest("[data-search-action]")?.dataset.searchAction;

  if (action === "close") {
    closeSearch();
  } else if (action === "previous" || action === "next") {
    runSearch(action);
    searchInput.focus()
  }
}

function handleSearchInput() {
  runSearch()
}

document.addEventListener("keydown", handleSearchShortcut);
document.addEventListener("submit", handleSearchSubmit);
document.addEventListener("click", handleSearchClick);
document.addEventListener("input", handleSearchInput);

let running = false;
let exited = false;
let disposed = false;

let fitFrame = 0;
let layoutFrame = 0;
let latestInsetRequest = 0;

let lastTerminalCols = 0;
let lastTerminalRows = 0;

function validSettingNumber(value, fallback, minimum, maximum) {
  const number = Number(value);

  if (!Number.isFinite(number)) {
    return fallback;
  }

  return Math.min(maximum, Math.max(minimum, number));
}

function applySettings(settings) {
  if (disposed || !settings || typeof settings !== "object") {
    return;
  }

  const configuredFont =
    typeof settings.fontFamily === "string" ? settings.fontFamily.trim() : "";

  const fontFamily = configuredFont || "Menlo";

  terminal.options.fontFamily = `"${fontFamily}", Monaco, "SF Mono", monospace`;

  terminal.options.fontSize = validSettingNumber(settings.fontSize, 14, 8, 72);

  terminal.options.lineHeight = validSettingNumber(
    settings.lineHeight,
    1.25,
    0.8,
    3,
  );

  terminal.options.scrollback = Math.round(
    validSettingNumber(settings.scrollback, 10000, 100, 1000000),
  );

  const validCursorStyles = new Set(["bar", "block", "underline"]);

  terminal.options.cursorStyle = validCursorStyles.has(settings.cursorStyle)
    ? settings.cursorStyle
    : "bar";

  terminal.options.cursorBlink = settings.cursorBlink !== false;

  terminal.options.theme = {
    background: settings.background || "#00000000",

    foreground: settings.foreground || "#edf1f7",

    cursor: settings.cursor || "#a9c9ff",

    selectionBackground: settings.selection || "#91b6ff55",

    black: settings.black || "#38404d",

    red: settings.red || "#ff8090",

    green: settings.green || "#a3dfaa",

    yellow: settings.yellow || "#f2d49b",

    blue: settings.blue || "#94baff",

    magenta: settings.magenta || "#d7b0ff",

    cyan: settings.cyan || "#95dce5",

    white: settings.white || "#edf1f7",
  };

  // Font and line-height changes alter the terminal dimensions.
  scheduleFit();
}

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

  fit.fit();

  if (!running) return;

  if (
    terminal.cols === lastTerminalCols &&
    terminal.rows === lastTerminalRows
  ) {
    return;
  }

  lastTerminalCols = terminal.cols;
  lastTerminalRows = terminal.rows;
  window.terminalApi.resize({
    cols: terminal.cols,
    rows: terminal.rows,
  });
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
      // throw new Error("Invalid native title-bar inset");
    }

    document.documentElement.style.setProperty(
      "--native-titlebar-inset",
      `${inset}px`,
    );
  } catch (error) {
    if (!disposed) {
      console.error("Native title-bar measurement failed:", error);
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

const removeWindowLayout =
  window.terminalApi.onWindowLayout(scheduleNativeLayout);

const removeSettings = window.terminalApi.onSettings(applySettings);

const observer = new ResizeObserver(scheduleFit);

observer.observe(container);

window.addEventListener("resize", scheduleNativeLayout);

async function start() {
  try {
    await document.fonts.ready;

    const initialSettings = await window.terminalApi.getSettings();

    applySettings(initialSettings);
    await updateNativeInset();

    if (disposed) return;

    fitTerminal();

    await window.terminalApi.start({
      cols: terminal.cols,
      rows: terminal.rows,
    });

    lastTerminalCols = terminal.cols;
    lastTerminalRows = terminal.rows;

    if (disposed || exited) return;

    running = true;
    fitTerminal();
    terminal.focus();
  } catch (error) {
    if (!disposed) {
      terminal.writeln(`\r\n[Could not start shell]\r\n${error.message}`);
    }
  }
}

window.addEventListener("beforeunload", () => {
  disposed = true;
  running = false;
  cancelAnimationFrame(fitFrame);
  cancelAnimationFrame(layoutFrame);
  observer.disconnect();
  window.removeEventListener("resize", scheduleNativeLayout);
  inputSub.dispose();
  removeData();
  removeExit();
  removeWindowLayout();
  removeSettings();
  document.removeEventListener("keydown", handleSearchShortcut);
  document.removeEventListener("submit", handleSearchSubmit);
  document.removeEventListener("click", handleSearchClick);
  document.removeEventListener("input", handleSearchInput);
  terminal.dispose();
});

void start();
