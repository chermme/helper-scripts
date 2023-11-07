npm run --prefix /Users/petercherm/git/AnyJunk/react-ux build

react_ux_folder=/Users/petercherm/git/AnyJunk/react-ux/dist
original_folder="/Users/petercherm/git/AnyJunk/react-v2/node_modules/@hss-proservice/react-ux/dist"
target_folder="/Users/petercherm/git/AnyJunk/react-v2/node_modules/@hss-proservice/react-ux/dist_original"

# Check if the target folder already exists
if [ ! -d "$target_folder" ]; then
  # If it doesn't exist, rename the original folder to the target folder name
  mv "$original_folder" "$target_folder"
  mkdir "$original_folder"
  echo "Folder has been renamed."
else
  # If it exists, print an error message
  echo "The target folder already exists. No changes were made."
fi

cp -Rf $react_ux_folder/*.* $original_folder
