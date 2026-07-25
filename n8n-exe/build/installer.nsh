!macro customInstall
  DetailPrint "Preparing the MyN8N runtime..."
  RMDir /r "$LOCALAPPDATA\MyN8N\node_modules"
  Delete "$LOCALAPPDATA\MyN8N\node.exe"
  CreateDirectory "$LOCALAPPDATA\MyN8N"
  SetOutPath "$LOCALAPPDATA\MyN8N"

  DetailPrint "Installing bundled Node.js..."
  Nsis7z::Extract "$INSTDIR\resources\runtime.7z"

  DetailPrint "Installing n8n components. This may take a few minutes..."
  Nsis7z::Extract "$INSTDIR\resources\n8n.7z"

  ${IfNot} ${FileExists} "$LOCALAPPDATA\MyN8N\node.exe"
    MessageBox MB_OK|MB_ICONSTOP "MyN8N runtime installation failed. Please run the installer again."
    Abort
  ${EndIf}
  ${IfNot} ${FileExists} "$LOCALAPPDATA\MyN8N\node_modules\n8n\bin\n8n"
    MessageBox MB_OK|MB_ICONSTOP "MyN8N runtime installation failed. Please run the installer again."
    Abort
  ${EndIf}
!macroend
