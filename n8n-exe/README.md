# MyN8N Windows 安裝程式

本專案將 n8n 打包成 Windows 安裝程式。最終使用者只需要安裝 EXE，即可執行 n8n，不需要自行安裝 Node.js。

## 安裝程式行為

- 採用全機安裝（per-machine），必須使用 Administrator 身分安裝與解除安裝。
- 管理員可在安裝精靈中選擇程式安裝目錄。
- 安裝時會在精靈進度中解壓縮內嵌的 Node.js 與 n8n runtime。
- 共用、唯讀的 runtime 位於 `<安裝目錄>\resources\n8n-runtime`。
- 每位 Windows 使用者的 n8n 資料位於 `%LOCALAPPDATA%\MyN8N\data`。
- 解除安裝只會移除程式與共用 runtime，不會刪除使用者的 workflow 資料。

例如管理員選擇 `D:\Apps\n8n` 作為安裝位置，runtime 會位於：

```text
D:\Apps\n8n\resources\n8n-runtime
```

## 專案結構

```text
build\installer.nsh              NSIS 安裝／解除安裝自訂邏輯
cleanup.ps1                      安全縮減 runtime 體積
main.js                           Electron 啟動程式與 n8n 資料位置
n8n-runtime\                     內嵌 Node.js 與 n8n 依賴來源
scripts\package-runtime.ps1      建立 n8n.7z 與 runtime-manifest.json
scripts\verify-runtime.js         驗證 n8n.7z 與 manifest
scripts\minify-package-json.js    將 package.json 壓縮為單行 JSON
runtime.7z                        包含 node.exe 的封包
n8n.7z                            產生的 n8n node_modules 封包
runtime-manifest.json             產生的 n8n.7z SHA-256 manifest
7za.exe                           封裝腳本使用的 7-Zip 命令列工具
```

## 建置前置需求

請在 Windows 10/11 x64 上建置，並準備：

- Node.js x64 `v24.18.0`（目前 runtime 目標 ABI 為 `137`）
- 網路連線：第一次執行 `npm ci` 與 electron-builder 時，會下載 npm、Electron 與 NSIS 資源
- 至少 5 GB 可用磁碟空間

建置電腦必須安裝 Node.js；最終使用者不需要。

建置前確認 Node.js 版本：

```powershell
node -p "process.version + ' ABI=' + process.versions.modules"
```

預期輸出：

```text
v24.18.0 ABI=137
```

## 在全新電腦建置

將原始碼複製到新電腦，例如：

```text
D:\deploy\n8n-exe
```

必須保留以下來源與設定檔：

```text
package.json
package-lock.json
main.js
preload.js
cleanup.ps1
build\
scripts\
n8n-runtime\package.json
n8n-runtime\package-lock.json
```

以下為產生檔或依賴資料夾，不必複製，建議在新電腦重新產生：

```text
node_modules\
n8n-runtime\node_modules\
dist\
n8n.7z
runtime-manifest.json
```

`runtime.7z` 可以從已驗證的建置複製；若沒有，請依第 3 步重新建立。

### 1. 安裝應用程式建置依賴

在專案根目錄開啟 PowerShell：

```powershell
cd D:\deploy\n8n-exe
npm ci
Copy-Item .\node_modules\7zip-bin\win\x64\7za.exe .\7za.exe -Force
```

`scripts\package-runtime.ps1` 會使用專案根目錄內的 `7za.exe`。

### 2. 安裝 n8n runtime 依賴

```powershell
Push-Location .\n8n-runtime
npm ci --omit=dev
Copy-Item (Get-Command node).Source .\node.exe -Force
Pop-Location
```

`n8n-runtime\package-lock.json` 會鎖定 n8n 依賴樹。請使用與最終內嵌 Node.js 相同 major version 的 Node.js 執行此步驟。

### 3. 建立 `runtime.7z`

`runtime.7z` 必須在 archive 根目錄包含 `node.exe`：

```powershell
Push-Location .\n8n-runtime
..\7za.exe a -t7z ..\runtime.7z .\node.exe -mx=9 -ms=off
Pop-Location

.\7za.exe l .\runtime.7z
```

archive 清單應顯示 `node.exe`，而不是 `n8n-runtime\node.exe`。

## 準備與驗證 n8n runtime

執行：

```powershell
npm run prepare-runtime
npm run verify-runtime
```

`prepare-runtime` 會執行 `scripts\package-runtime.ps1`，流程如下：

1. 對 `n8n-runtime\node_modules` 執行 `cleanup.ps1`。
2. 確認 n8n、sqlite3、AI workflow builder 的必要 runtime 檔案仍存在。
3. 將 `n8n-runtime\node_modules` 壓縮成 `n8n.7z`。
4. 計算 archive 的 SHA-256。
5. 建立 `runtime-manifest.json`，記錄 runtime ID 與必要檔案清單。

`verify-runtime` 會確認 manifest hash 與 `n8n.7z` 相符，並確認 archive 內含所有必要 runtime 檔案。

### 清理原則

`cleanup.ps1` 會改動 runtime dependency 資料夾，但採取保守策略，僅移除：

- TypeScript declaration 檔與 JavaScript source map。
- repository metadata、CI、Docker、coverage 與 editor 設定檔。
- 明確的非 Windows native prebuild 目錄。
- 在 `package.json` 明確宣告為非 Windows 的套件。
- 相依套件內的套件管理器 lock files 與空目錄。
- 合法 `package.json` 中的縮排與換行；JSON 欄位和值維持不變。

它會刻意保留 JavaScript runtime 檔、TypeScript 檔、`tests`、`examples`、`docs` 與套件目錄。不要加入泛用的 `tests`、`examples` 或 `.ts` 刪除規則：部分 n8n 相依套件會在 runtime 載入它們。

若要先預覽清理結果、不實際刪除檔案：

```powershell
.\cleanup.ps1 -WhatIf
```

## 在封裝前進行 n8n smoke test

在第一個 PowerShell 視窗，使用清理後的 runtime 啟動 n8n：

```powershell
$env:N8N_USER_FOLDER = "$PWD\.smoke-data"
$env:N8N_PORT = "5681"
.\n8n-runtime\node.exe .\n8n-runtime\node_modules\n8n\bin\n8n
```

在第二個 PowerShell 視窗檢查 health endpoint：

```powershell
Invoke-WebRequest http://127.0.0.1:5681/healthz
```

回應必須是 HTTP `200`。測試完成後，在第一個視窗按 `Ctrl+C` 停止 n8n。

## 建立安裝程式

若已手動執行 `prepare-runtime` 與 `verify-runtime`，直接建置 NSIS installer：

```powershell
.\node_modules\.bin\electron-builder.cmd --win nsis --config
```

或者執行：

```powershell
npm run build
```

`npm run build` 會在 electron-builder 前自動執行以下 lifecycle：

```text
prebuild
  npm run prepare-runtime
  npm run verify-runtime
build
  electron-builder
```

同一個 release 不需要同時執行兩種建置命令，否則會重複清理與壓縮 runtime。

輸出的安裝檔位於：

```text
dist\n8n Setup 2.31.5.exe
```

## 安裝與解除安裝行為

NSIS 設定使用 `perMachine: true`，並有明確的 `UAC_IsAdmin` 檢查。

- 安裝必須使用 Administrator 權限。
- 解除安裝必須使用 Administrator 權限。
- 安裝精靈會顯示 `runtime.7z` 與 `n8n.7z` 的解壓縮進度。
- 重新安裝會更新所選安裝目錄下的共用 runtime。
- 解除安裝會移除程式與共用 runtime。
- `%LOCALAPPDATA%\MyN8N\data` 會被保留，因此 workflow、credential 與 n8n 資料庫可跨重新安裝與解除安裝保留。

Electron launcher 在 `main.js` 中設定此使用者資料位置：

```js
N8N_USER_FOLDER: path.join(userRoot, "data")
```

## Release 前檢查清單

1. 執行 `npm run prepare-runtime`。
2. 執行 `npm run verify-runtime`。
3. 執行 n8n smoke test，確認 `/healthz` 回傳 `200`。
4. 建置 NSIS installer。
5. 在乾淨的 Windows 帳號或虛擬機測試安裝。
6. 確認安裝與解除安裝均要求 Administrator 權限。
7. 建立一個測試 workflow，解除安裝後重新安裝，確認 workflow 仍存在。

## SmartScreen 注意事項

Administrator 權限與 Microsoft SmartScreen reputation 是不同機制。未簽章的安裝檔仍可能顯示 SmartScreen「不常見／不安全」警告。公開發佈前，請使用 Authenticode code-signing certificate 對最終 EXE 進行簽章。
