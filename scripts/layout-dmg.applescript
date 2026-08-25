on run arguments
  if (count of arguments) is not 1 then error "Expected the mounted volume path."
  set mountedPath to item 1 of arguments
  set mountedFolderAlias to POSIX file mountedPath as alias

  tell application "Finder"
    set mountedFolder to folder mountedFolderAlias
    open mountedFolder
    repeat with attemptNumber from 1 to 30
      if exists container window of mountedFolder then exit repeat
      delay 1
    end repeat
    if not (exists container window of mountedFolder) then error "Mounted volume path did not open in Finder: " & mountedPath
    if not ((exists item "WTM.app" of mountedFolder) and (exists item "Applications" of mountedFolder)) then error "Mounted volume is missing WTM.app or Applications: " & mountedPath

    set layoutWindow to container window of mountedFolder
    set current view of layoutWindow to icon view
    set toolbar visible of layoutWindow to false
    set statusbar visible of layoutWindow to false
    set bounds of layoutWindow to {120, 120, 780, 540}
    set theViewOptions to icon view options of layoutWindow
    set arrangement of theViewOptions to not arranged
    set icon size of theViewOptions to 96
    set text size of theViewOptions to 13
    set background picture of theViewOptions to file "background.png" of folder ".background" of mountedFolder
    set position of item "WTM.app" of mountedFolder to {190, 218}
    set position of item "Applications" of mountedFolder to {470, 218}
    close layoutWindow
    open mountedFolder
    update mountedFolder without registering applications
    delay 2
  end tell
end run
