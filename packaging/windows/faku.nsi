; Silent-by-default NSIS installer wrapping Native's early Windows
; package directory (zig-out/package/faku-windows: bin\faku.exe + ico +
; assets). PKGDIR must be an absolute Windows path with backslashes.
; File /r "${PKGDIR}\bin" preserves bin\. Double-click installs with
; no wizard. /S still works.
;
; Required defines (passed by the release workflow):
;   VERSION          release version, e.g. 0.1.0
;   PRODUCT_VERSION  four-part, e.g. 0.1.0.0 (VIProductVersion)
;   PKGDIR           absolute Windows path to zig-out\package\faku-windows
;   OUTFILE          path to faku-<version>-windows-x64.exe

Unicode True
SilentInstall silent
SilentUnInstall silent
RequestExecutionLevel admin
SetCompressor /SOLID lzma
SetOverwrite on

!ifndef VERSION
  !error "VERSION must be defined"
!endif
!ifndef PRODUCT_VERSION
  !error "PRODUCT_VERSION must be a four-part version (e.g. 0.1.0.0)"
!endif
!ifndef PKGDIR
  !error "PKGDIR must be defined (path to zig-out/package/faku-windows)"
!endif
!ifndef OUTFILE
  !error "OUTFILE must be defined"
!endif

Name "Faku"
OutFile "${OUTFILE}"
InstallDir "$PROGRAMFILES64\Faku"
InstallDirRegKey HKLM "Software\Faku" "InstallDir"

VIProductVersion "${PRODUCT_VERSION}"
VIAddVersionKey "ProductName" "Faku"
VIAddVersionKey "ProductVersion" "${VERSION}"
VIAddVersionKey "FileDescription" "Faku installer"
VIAddVersionKey "FileVersion" "${VERSION}"
VIAddVersionKey "LegalCopyright" "Faku"

!if /FileExists "${PKGDIR}\app-icon.ico"
  Icon "${PKGDIR}\app-icon.ico"
  UninstallIcon "${PKGDIR}\app-icon.ico"
!endif

Section "Install"
  SetOutPath "$INSTDIR"
  File /r "${PKGDIR}\bin"
  File /nonfatal "${PKGDIR}\app-icon.ico"
  File /nonfatal "${PKGDIR}\README.txt"
  File /r /nonfatal "${PKGDIR}\resources"

  WriteUninstaller "$INSTDIR\Uninstall.exe"
  WriteRegStr HKLM "Software\Faku" "InstallDir" "$INSTDIR"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\Faku" "DisplayName" "Faku"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\Faku" "UninstallString" '"$INSTDIR\Uninstall.exe"'
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\Faku" "DisplayIcon" "$INSTDIR\bin\faku.exe"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\Faku" "DisplayVersion" "${VERSION}"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\Faku" "Publisher" "Faku"
  WriteRegDWORD HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\Faku" "NoModify" 1
  WriteRegDWORD HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\Faku" "NoRepair" 1

  CreateDirectory "$SMPROGRAMS\Faku"
  !if /FileExists "${PKGDIR}\app-icon.ico"
    CreateShortCut "$SMPROGRAMS\Faku\Faku.lnk" "$INSTDIR\bin\faku.exe" "" "$INSTDIR\app-icon.ico"
  !else
    CreateShortCut "$SMPROGRAMS\Faku\Faku.lnk" "$INSTDIR\bin\faku.exe"
  !endif
SectionEnd

Section "Uninstall"
  Delete "$SMPROGRAMS\Faku\Faku.lnk"
  RMDir "$SMPROGRAMS\Faku"
  Delete "$INSTDIR\Uninstall.exe"
  RMDir /r "$INSTDIR"
  DeleteRegKey HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\Faku"
  DeleteRegKey HKLM "Software\Faku"
SectionEnd
