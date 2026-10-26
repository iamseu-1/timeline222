; Inno Setup 6 script for the standalone timeline app (prototype/app + prototype/engine).
; ASCII only on purpose: every Korean string (app title, store labels and paths) arrives through /D defines
; from package-windows.ps1, which reads them from the bundle's bundle.json (UTF-8). ISCC is a Unicode program,
; so the defines keep their Hangul without depending on the .iss file encoding.
;
; Called by package-windows.ps1:
;   ISCC.exe /DAppVersion=1.1.0 /DSourceDir=<bundle folder> /DOutputDir=<out> /DExeName=archive_prototype.exe
;            /DAppTitle=<title> [/DStore1Db=<rel\path\archive.db of the default store>]
;            [/DStore2Label=<label> /DStore2Db=<rel\path\archive.db>] [/DStore3Label=... /DStore3Db=...]
;            [/DToolsDir=<rel\path of the tools folder>] [/DToolResults=<rel\path of the tools' results folder>] installer.iss
; The bundle folder is the output of prototype/scripts/bundle-app.mjs (Windows\, the stores, the tools folder with the engine
; tool archive-tool.exe and the base pack east-asia.htpack, the guide).
; Installs per user (no administrator rights): the app rewrites a store in place when DLC is added, removed or turned off,
; and keeps the DLC files next to it, so the install folder must be writable.

#ifndef AppVersion
  #error AppVersion is required
#endif
#ifndef SourceDir
  #error SourceDir is required
#endif
#ifndef OutputDir
  #error OutputDir is required
#endif
#ifndef ExeName
  #define ExeName "archive_prototype.exe"
#endif
#ifndef AppTitle
  #define AppTitle "HistoryTimeline"
#endif

[Setup]
; Keep AppId stable across versions so a new version installs over the old one.
AppId={{7A625F02-44AD-4009-AD5A-63AF862FE696}
AppName={#AppTitle}
AppVersion={#AppVersion}
AppVerName={#AppTitle} {#AppVersion}
AppPublisher=HistoryTimeline
AppPublisherURL=https://github.com/iamseu-1
DefaultDirName={localappdata}\Programs\HistoryTimeline-Standalone
DefaultGroupName={#AppTitle}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
OutputDir={#OutputDir}
OutputBaseFilename=HistoryTimeline-{#AppVersion}-windows-x64-setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
UninstallDisplayIcon={app}\Windows\{#ExeName}
UninstallDisplayName={#AppTitle} {#AppVersion}
CloseApplications=yes
RestartApplications=no

[Languages]
; package-windows.ps1 passes /DNoKorean when this Inno Setup has no Languages\Korean.isl (English wizard then).
#ifndef NoKorean
Name: "korean"; MessagesFile: "compiler:Languages\Korean.isl"
#endif
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[InstallDelete]
#ifdef ToolResults
; The tools' results folder holds the base pack the bundle ships (<tools>\prototype\results\compat\east-asia.htpack - the file the
; app points at to bring the base pack back). Cleared on every install so an upgrade never keeps an old base pack.
Type: filesandordirs; Name: "{app}\{#ToolResults}"
#endif
#ifdef ToolsDir
; What older versions put in the tools folder and the bundle root before the app added and removed DLC through its engine
; (plan P4 task 11 / ruling R49): Node.js, the timeline code, the base pack sources, the layout export and add-dlc.mjs, and the
; DLC-*.cmd that rebuilt the store with them. A leftover DLC-*.cmd would build a store without the calendar table, and the app
; refuses to add or remove DLC on such a store (ruling R36) - so an upgrade removes them. Names stay ASCII (wildcard for the cmd).
Type: filesandordirs; Name: "{app}\{#ToolsDir}\node"
Type: filesandordirs; Name: "{app}\{#ToolsDir}\js"
Type: filesandordirs; Name: "{app}\{#ToolsDir}\packs"
Type: filesandordirs; Name: "{app}\{#ToolsDir}\prototype\scripts"
Type: files; Name: "{app}\{#ToolsDir}\index.html"
#endif
; The old DLC-*.cmd in the bundle root does not depend on the tools folder name - removed even when ToolsDir is not passed.
Type: files; Name: "{app}\DLC-*.cmd"
; The stores' SQLite side files from the old version (ruling R58): the app rewrites a store in place, and if it died while writing,
; a hot <store>-journal (or -wal / -shm) stays next to it. The upgrade replaces archive.db, so the engine would roll the old journal
; back into the new file on the next open and corrupt it. package-windows.ps1 passes every store path (Store1Db = the default).
#ifdef Store1Db
Type: files; Name: "{app}\{#Store1Db}-journal"
Type: files; Name: "{app}\{#Store1Db}-wal"
Type: files; Name: "{app}\{#Store1Db}-shm"
#endif
#ifdef Store2Db
Type: files; Name: "{app}\{#Store2Db}-journal"
Type: files; Name: "{app}\{#Store2Db}-wal"
Type: files; Name: "{app}\{#Store2Db}-shm"
#endif
#ifdef Store3Db
Type: files; Name: "{app}\{#Store3Db}-journal"
Type: files; Name: "{app}\{#Store3Db}-wal"
Type: files; Name: "{app}\{#Store3Db}-shm"
#endif
#ifdef Store4Db
Type: files; Name: "{app}\{#Store4Db}-journal"
Type: files; Name: "{app}\{#Store4Db}-wal"
Type: files; Name: "{app}\{#Store4Db}-shm"
#endif

[Files]
; The whole bundle: Windows\ (Flutter runtime, archive_engine.dll, MSVC runtime), the stores, the tools folder (archive-tool.exe and
; the base pack east-asia.htpack - no Node.js) and the guide.
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
; The plain shortcut opens the default store (Windows\prototype.json points at it).
Name: "{autoprograms}\{#AppTitle}"; Filename: "{app}\Windows\{#ExeName}"; WorkingDir: "{app}\Windows"
Name: "{autodesktop}\{#AppTitle}"; Filename: "{app}\Windows\{#ExeName}"; WorkingDir: "{app}\Windows"; Tasks: desktopicon
#ifdef Store2Label
Name: "{autoprograms}\{#AppTitle} - {#Store2Label}"; Filename: "{app}\Windows\{#ExeName}"; Parameters: "--db=""{app}\{#Store2Db}"""; WorkingDir: "{app}\Windows"
#endif
#ifdef Store3Label
Name: "{autoprograms}\{#AppTitle} - {#Store3Label}"; Filename: "{app}\Windows\{#ExeName}"; Parameters: "--db=""{app}\{#Store3Db}"""; WorkingDir: "{app}\Windows"
#endif
#ifdef Store4Label
Name: "{autoprograms}\{#AppTitle} - {#Store4Label}"; Filename: "{app}\Windows\{#ExeName}"; Parameters: "--db=""{app}\{#Store4Db}"""; WorkingDir: "{app}\Windows"
#endif

[Run]
Filename: "{app}\Windows\{#ExeName}"; Description: "{cm:LaunchProgram,{#AppTitle}}"; WorkingDir: "{app}\Windows"; Flags: nowait postinstall skipifsilent

; Files the app makes later (the stores it rewrote, the DLC files the user added, DLC\hidden.json and DLC\sync.json) are left on
; uninstall on purpose.
