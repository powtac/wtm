on run arguments
  if (count of arguments) is not 1 then error "Expected the mounted volume name."
  set volumeName to item 1 of arguments

  tell application "Finder"
    repeat with attemptNumber from 1 to 30
      if exists disk volumeName then exit repeat
      delay 1
    end repeat
    if not (exists disk volumeName) then error "Mounted volume did not become visible in Finder: " & volumeName
    tell disk volumeName
      open
      repeat with attemptNumber from 1 to 15
        if (exists item "WTM.app" of container window) and (exists item "Applications" of container window) then exit repeat
        delay 1
      end repeat
      set current view of container window to icon view
      set toolbar visible of container window to false
      set statusbar visible of container window to false
      set bounds of container window to {120, 120, 780, 540}
      set theViewOptions to icon view options of container window
      set arrangement of theViewOptions to not arranged
      set icon size of theViewOptions to 96
      set text size of theViewOptions to 13
      set background picture of theViewOptions to file ".background:background.png"
      set position of item "WTM.app" of container window to {190, 218}
      set position of item "Applications" of container window to {470, 218}
      close
      open
      update without registering applications
      delay 2
    end tell
  end tell
end run
