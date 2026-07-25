const { ipcRenderer } = require("electron");

ipcRenderer.on("set-status", (_event, text) => {
    const message = document.getElementById("msg");
    if (message) message.textContent = String(text);
});
