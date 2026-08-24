on run arguments
  if (count of arguments) is not 1 then error "Expected the mounted volume name."
  set volumeName to item 1 of arguments

  tell application "Finder"
    tell disk volumeName
      open
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
