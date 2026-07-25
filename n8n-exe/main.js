const { app, BrowserWindow, dialog } = require("electron");
const { spawn } = require("child_process");
const fs = require("fs");
const os = require("os");
const path = require("path");

let n8nProcess = null;
let mainWindow = null;
let isQuitting = false;

const resourceRoot = app.isPackaged ? process.resourcesPath : __dirname;
const userRoot = path.join(os.homedir(), "AppData", "Local", "MyN8N");
const logFile = path.join(userRoot, "n8n-launcher.log");
const installedRuntimeRoot = userRoot;
const defaultRequiredFiles = [
    "node.exe",
    "node_modules/n8n/bin/n8n",
    "node_modules/sqlite3/build/Release/node_sqlite3.node",
    "node_modules/@n8n/ai-workflow-builder/dist/prompts/chains/parameter-updater/registry.js",
    "node_modules/@n8n/ai-workflow-builder/dist/prompts/chains/parameter-updater/examples/index.js",
];

const LOADING_HTML = `<!DOCTYPE html><html><head><meta charset="utf-8"><style>
*{margin:0;padding:0;box-sizing:border-box}
body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;display:flex;justify-content:center;align-items:center;height:100vh;background:#1a1a2e;color:#eee;flex-direction:column;text-align:center;padding:20px}
h2{color:#e94560;margin-bottom:10px}.loader{border:4px solid #333;border-top:4px solid #e94560;border-radius:50%;width:40px;height:40px;animation:spin 1s linear infinite;margin-bottom:20px}@keyframes spin{0%{transform:rotate(0deg)}100%{transform:rotate(360deg)}}
p{color:#aaa;font-size:14px;max-width:400px;line-height:1.5}
</style></head><body><div class="loader"></div><h2 id="msg">Starting MyN8N…</h2></body></html>`;

const ERROR_HTML = `<!DOCTYPE html><html><head><meta charset="utf-8"><style>
*{margin:0;padding:0;box-sizing:border-box}
body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;display:flex;justify-content:center;align-items:center;height:100vh;background:#1a1a2e;color:#eee;flex-direction:column;text-align:center;padding:40px}
h2{color:#e94560;margin-bottom:10px}pre{color:#ccc;white-space:pre-wrap;font-size:13px;max-width:600px}
</style></head><body><h2>Unable to start MyN8N</h2><pre id="msg">__MESSAGE__</pre></body></html>`;

function log(message) {
    const line = `[${new Date().toISOString()}] ${message}`;
    try {
        fs.mkdirSync(userRoot, { recursive: true });
        fs.appendFileSync(logFile, `${line}\n`);
    } catch {
        // Logging must never prevent n8n from starting.
    }
    console.log(message);
}

function showLoadingScreen(text) {
    if (!mainWindow || mainWindow.isDestroyed()) return;
    mainWindow.webContents.send("set-status", text);
}

function showErrorPage(message) {
    if (!mainWindow || mainWindow.isDestroyed()) return;
    const escaped = String(message).replace(/[&<>"']/g, (character) => ({
        "&": "&amp;",
        "<": "&lt;",
        ">": "&gt;",
        '"': "&quot;",
        "'": "&#39;",
    })[character]);
    const html = ERROR_HTML.replace("__MESSAGE__", escaped);
    mainWindow.loadURL(`data:text/html;charset=utf-8,${encodeURIComponent(html)}`);
}

function ensureRuntime() {
    const missingFiles = defaultRequiredFiles.filter((requiredFile) =>
        !fs.existsSync(path.join(installedRuntimeRoot, requiredFile)),
    );
    if (missingFiles.length > 0) {
        throw new Error(`The installed n8n runtime is incomplete: ${missingFiles.join(", ")}. Please reinstall MyN8N.`);
    }
    log(`Installed n8n runtime verified: ${installedRuntimeRoot}`);
}

function startN8N() {
    const nodePath = path.join(installedRuntimeRoot, "node.exe");
    const n8nPath = path.join(installedRuntimeRoot, "node_modules", "n8n", "bin", "n8n");
    showLoadingScreen("Starting n8n…");

    n8nProcess = spawn(nodePath, [n8nPath], {
        cwd: userRoot,
        windowsHide: true,
        detached: false,
        env: {
            ...process.env,
            N8N_USER_FOLDER: path.join(userRoot, "data"),
            N8N_PORT: "5678",
        },
    });

    n8nProcess.on("exit", (code, signal) => {
        log(`n8n exited (code=${code}, signal=${signal})`);
        n8nProcess = null;
        if (!isQuitting) showErrorPage(`n8n stopped unexpectedly (exit code ${code ?? "unknown"}).\n\nSee ${logFile} for details.`);
    });
    n8nProcess.on("error", (error) => log(`n8n process error: ${error.message}`));
    n8nProcess.stdout.on("data", (data) => log(`[n8n] ${data.toString().trim()}`));
    n8nProcess.stderr.on("data", (data) => log(`[n8n] ${data.toString().trim()}`));
}

function waitForN8N() {
    const http = require("http");
    let retries = 0;
    const maxRetries = 120;

    function retry() {
        if (!n8nProcess || isQuitting) return;
        retries += 1;
        if (retries >= maxRetries) {
            const message = "n8n did not start within six minutes. Check the launcher log for details.";
            log(message);
            showErrorPage(`${message}\n\n${logFile}`);
            return;
        }
        setTimeout(poll, 3000);
    }

    function poll() {
        const request = http.get("http://127.0.0.1:5678/healthz", (response) => {
            response.resume();
            if (response.statusCode === 200) {
                log("n8n is ready");
                if (mainWindow && !mainWindow.isDestroyed()) mainWindow.loadURL("http://127.0.0.1:5678");
            } else {
                retry();
            }
        });
        request.on("error", retry);
        request.setTimeout(5000, () => request.destroy());
    }

    setTimeout(poll, 1000);
}

function createWindow() {
    mainWindow = new BrowserWindow({
        width: 1200,
        height: 800,
        show: true,
        backgroundColor: "#1a1a2e",
        webPreferences: {
            preload: path.join(__dirname, "preload.js"),
            nodeIntegration: false,
            contextIsolation: true,
        },
    });
    const loaded = new Promise((resolve) => mainWindow.webContents.once("did-finish-load", resolve));
    mainWindow.loadURL(`data:text/html;charset=utf-8,${encodeURIComponent(LOADING_HTML)}`);
    mainWindow.on("closed", () => { mainWindow = null; });
    return loaded;
}

const hasSingleInstanceLock = app.requestSingleInstanceLock();
if (!hasSingleInstanceLock) app.quit();

app.on("second-instance", () => {
    if (!mainWindow) return;
    if (mainWindow.isMinimized()) mainWindow.restore();
    mainWindow.focus();
});

async function startApplication() {
    try {
        await ensureRuntime();
        if (isQuitting || !mainWindow || mainWindow.isDestroyed()) return;
        startN8N();
        waitForN8N();
    } catch (error) {
        if (isQuitting) return;
        log(`FATAL ERROR: ${error.stack || error.message}`);
        showErrorPage(`${error.message}\n\nSee ${logFile} for details.`);
        dialog.showErrorBox("MyN8N startup error", error.message);
    }
}

app.whenReady().then(async () => {
    if (!hasSingleInstanceLock) return;
    log("MyN8N starting");
    log(`Resources: ${resourceRoot}`);
    log(`User data: ${userRoot}`);
    await createWindow();
    void startApplication();
});

app.on("before-quit", () => {
    isQuitting = true;
    if (n8nProcess) {
        try {
            n8nProcess.kill();
            log("n8n process terminated");
        } catch (error) {
            log(`Error terminating n8n: ${error.message}`);
        }
    }
});

app.on("window-all-closed", () => {
    if (process.platform !== "darwin") app.quit();
});
