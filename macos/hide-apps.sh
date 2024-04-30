# Array of apps to hide:
apps=(
  "AlDente"
  "CleanMyMac X"
  "Grammarly Desktop"
  "iStat Menus"
  "KeyboardCleanTool"
  "Maccy"
  "WhatsApp"
)

apps_dir="/Applications/"

# command based on parameter "hide" or "unhide"
command=${1:-"hide"}

# loop through the apps array
for app in "${apps[@]}"; do
  # hide or unhide the app
  if [ $command == "unhide" ]; then
    sudo chflags -h nohidden "$apps_dir$app.app"
    echo "Unhiding $app"
  else
    sudo chflags -h hidden "$apps_dir$app.app"
    echo "Hiding $app"
  fi
done

sudo killall Dock
