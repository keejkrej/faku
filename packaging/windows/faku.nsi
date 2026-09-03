; Template NSIS installer wrapping Native's early Windows package
; directory (zig-out/package/faku-windows: bin\faku.exe + ico + assets).
; The release workflow substitutes @PKGDIR@, @OUTFILE@, @VERSION@, and
; @PRODUCT_VERSION@ at package time. @PKGDIR@ and @OUTFILE@ are absolute
; Windows backslash paths (e.g. D:\a\faku\faku\zig-out\package\faku-windows).
; Paths are inlined so they never pass through makensis -D, which treats
; `\a` in D:\a\ as an escape. Double-click installs with no wizard.

Unicode True
SilentInstall silent
SilentUnInstall silent
RequestExecutionLevel admin
SetCompressor /SOLID lzma
SetOverwrite on

Name "Faku"
OutFile "@OUTFILE@"
InstallDir "$PROGRAMFILES64\Faku"
InstallDirRegKey HKLM "Software\Faku" "InstallDir"

VIProductVersion "@PRODUCT_VERSION@"
VIAddVersionKey "ProductName" "Faku"
VIAddVersionKey "ProductVersion" "@VERSION@"
VIAddVersionKey "FileDescription" "Faku installer"
VIAddVersionKey "FileVersion" "@VERSION@"
VIAddVersionKey "LegalCopyright" "Faku"

!if /FileExists "@PKGDIR@\app-icon.ico"
  Icon "@PKGDIR@\app-icon.ico"
  UninstallIcon "@PKGDIR@\app-icon.ico"
!endif

Section "Install"
  SetOutPath "$INSTDIR\bin"
  File /r "@PKGDIR@\bin\*.*"
  SetOutPath "$INSTDIR"
  File /nonfatal "@PKGDIR@\app-icon.ico"
  File /nonfatal "@PKGDIR@\README.txt"
  SetOutPath "$INSTDIR\resources"
  File /r /nonfatal "@PKGDIR@\resources\*.*"

  WriteUninstaller "$INSTDIR\Uninstall.exe"
  WriteRegStr HKLM "Software\Faku" "InstallDir" "$INSTDIR"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\Faku" "DisplayName" "Faku"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\Faku" "UninstallString" '"$INSTDIR\Uninstall.exe"'
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\Faku" "DisplayIcon" "$INSTDIR\bin\faku.exe"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\Faku" "DisplayVersion" "@VERSION@"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\Faku" "Publisher" "Faku"
  WriteRegDWORD HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\Faku" "NoModify" 1
  WriteRegDWORD HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\Faku" "NoRepair" 1

  CreateDirectory "$SMPROGRAMS\Faku"
  !if /FileExists "@PKGDIR@\app-icon.ico"
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
