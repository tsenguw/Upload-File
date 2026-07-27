!macro customInstall
  DetailPrint "Preparing the MyN8N runtime..."
  ; Per-machine installation: runtime is protected in the shared app directory.
  RMDir /r "$INSTDIR\resources\n8n-runtime"
  CreateDirectory "$INSTDIR\resources\n8n-runtime"
  SetOutPath "$INSTDIR\resources\n8n-runtime"

  DetailPrint "Installing bundled Node.js..."
  Nsis7z::Extract "$INSTDIR\resources\runtime.7z"

  DetailPrint "Installing n8n components. This may take a few minutes..."
  Nsis7z::Extract "$INSTDIR\resources\n8n.7z"

  ${IfNot} ${FileExists} "$INSTDIR\resources\n8n-runtime\node.exe"
    MessageBox MB_OK|MB_ICONSTOP "MyN8N runtime installation failed. Please run the installer again."
    Abort
  ${EndIf}
  ${IfNot} ${FileExists} "$INSTDIR\resources\n8n-runtime\node_modules\n8n\bin\n8n"
    MessageBox MB_OK|MB_ICONSTOP "MyN8N runtime installation failed. Please run the installer again."
    Abort
  ${EndIf}
!macroend

!macro customUnInstall
  ; Per-user n8n workflow data is retained; only protected shared binaries are removed.
  DetailPrint "Removing the MyN8N runtime..."
  RMDir /r "$INSTDIR\resources\n8n-runtime"
!macroend
