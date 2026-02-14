; SwiftDrop Windows Installer — Inno Setup Script
; Build: flutter build windows --release
; Then compile this .iss file with Inno Setup 6+.

[Setup]
AppName=SwiftDrop
AppVersion={#GetStringFileInfo("..\..\build\windows\x64\runner\Release\swiftdrop.exe", "ProductVersion")}
AppPublisher=SwiftDrop
AppPublisherURL=https://github.com/your-username/swiftdrop
DefaultDirName={autopf}\SwiftDrop
DefaultGroupName=SwiftDrop
OutputBaseFilename=SwiftDrop-Setup
SetupIconFile=runner\resources\app_icon.ico
UninstallDisplayIcon={app}\swiftdrop.exe
Compression=lzma2/ultra64
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
WizardStyle=modern
PrivilegesRequired=lowest
OutputDir=..\..\build\installer

[Files]
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: recursesubdirs ignoreversion

[Icons]
Name: "{group}\SwiftDrop"; Filename: "{app}\swiftdrop.exe"
Name: "{group}\Uninstall SwiftDrop"; Filename: "{uninstallexe}"
Name: "{autodesktop}\SwiftDrop"; Filename: "{app}\swiftdrop.exe"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional icons:"

[Run]
Filename: "{app}\swiftdrop.exe"; Description: "Launch SwiftDrop"; Flags: nowait postinstall skipifsilent
