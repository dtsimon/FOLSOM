#! /bin/zsh

# --------------------------------------------------------------------------------
# FOLSOM: Fast OneDrive Links to Sharepoint On Mac
#
# Script to get the "share with existing access" url for a file synced locally
# with OneDrive. Meant to work on personal and "shared-with-me" files
#
# https://github.com/dtsimon/FOLSOM
# --------------------------------------------------------------------------------

# Start by setting the clipboard. 
# FOLSOM takes a few seconds, so set the clipboard to a short message explaining this.
echo -n "FOLSOM is processing..." | pbcopy

# The script is meant to start with a file path from a Finder action
inputPath=`readlink -f $1`

# Check if the inputPath is synced through OneDrive
# If it isn't, skip to the end... if it is, run the full script
# 1. Get the OneDrive paths

# !!!! fileproviderctl listprovider broken in macOS 14.4!!
# onedriveFileProviderPaths=`fileproviderctl listproviders | grep -E "OneDrive-mac" | sed "s|com.microsoft.OneDrive-mac.FileProvider|$HOME|g"`
# This solution is much slower as it requires a (even limited!) dump
onedriveFileProviderPaths=`fileproviderctl dump --limit-dump-size -P | grep -F "com.apple.file-provider-domain-id:" | sort | uniq | grep -F "OneDrive-mac" | sed "s|.*OneDrive\-mac\.FileProvider|$HOME|g" `

# 2. Convert the onedriveFileProviderPaths variable into an array
onedriveFileProviderPathsArray=("${(@f)onedriveFileProviderPaths}")
# 3. Get the original paths for the onedriveFileProviderPaths
for singleOnedrivePath in $onedriveFileProviderPathsArray; do
    originalPath=`readlink $singleOnedrivePath`    
    onedriveFileProviderPaths="$onedriveFileProviderPaths\n$originalPath"
    onedriveFileProviderPathsArray+=("$originalPath")
done
# 4. Set a flag to indicate if the inputPath is found
isOnedrive=0
# 5. Iterate over the array and check if the inputPath contains any of the paths
for singleOnedrivePath in $onedriveFileProviderPathsArray; do
  if [[ $inputPath == *$singleOnedrivePath* ]]; then
    # It's a Onedrive synced file!
    isOnedrive=1
    # Clean up the path, removing the local folder parts
    localPathClean=`echo $inputPath | sed "s|$singleOnedrivePath/||g"`
    break
  fi
done

# 6. Choose what to do if is or isn't OneDrive path
if [[ $isOnedrive -eq 0 ]]; then
    # It's just a regular path outside of OneDrive
    # Generate basic output path
    # Remove initial "/" anc convert intermediate "/" --> " > "
    outputPath=`echo $inputPath | sed 's|^/||g' | sed 's|/| > |g'`
    osascript -e "set the clipboard to \""$outputPath"\""

elif [[ $isOnedrive -eq 1 ]]; then
    # It IS a OneDrive path... proceed with rest of script

# -------------------------------------------------------
# BEGINNING OF IS-ONEDRIVE IF SECTION
# -------------------------------------------------------

# Process the inputPath
# Get the local base OneDrive folder name
onedriveRootFolderLocal=`echo $localPathClean | cut -d "/" -f1`

# Check if it's in MySite (personal OneDrive structure)
if [[ $singleOnedrivePath != *"Shared"* ]];  then
    # It's inside own OneDrive structure
    onedriveRootSite="MySite"
    myPathPrefix=`id -F`"/"
else
    # It's shared with me, on Sharepoint/Teams, or someone else's OneDrive
    # Split the local base folder into site/person and share name
    onedriveRootSite=`echo $onedriveRootFolderLocal | sed 's/\ -\ .*//g'`
    onedriveRootShare=`echo $onedriveRootFolderLocal | sed 's/.*\ -\ //g'`
fi
# Get the relative path to the file past the root folder
relativePath=`echo $localPathClean | sed "s|$onedriveRootFolderLocal/||g"`

# Retrieve OneDrive sync info
cd ~/"Library/Containers/com.microsoft.OneDrive-mac/Data/Library/Application Support/OneDrive/settings/Business1"
libraryScope=`grep -E "^libraryScope.*\s5\s\"$onedriveRootSite\"\s" *.ini | sed "s|.*\"$onedriveRootSite\"||g" | awk '{print $3}'  | sed 's/\"//g'`
davUrlNamespace=`grep -hF $libraryScope *.ini | grep -E "DavUrlNamespace" | sed 's|DavUrlNamespace = ||g'`
userName=`grep -E "MySite" *.ini | sed "s|.*personal/||g" | sed "s|\"\ .*||g"`

# Check if the Sharepoint URL is a "site" (Team or Sharepoint) or "personal" (user's OneDrive)
if [[ $davUrlNamespace == *"personal"* ]] && [[ "$davUrlNamespace" != *$userName* ]]; then
    # The URL is pointing toward a personal OneDrive share
    # need to get the intermediate folder structure
    # from lookup table or interactively
    lookupCount=`grep -cF "$onedriveRootShare;;;" ~/.FOLSOM_lookup.txt`
    if [[ $lookupCount -ne 1 ]]; then
        # the personal share wasn't found in the lookup table
        # alert the user with Applescript
        osascript -e "set dialogText to \"The file you selected is shared through a personal OneDrive folder, but the intermediate URL for share [$onedriveRootFolderLocal] was not found in ~/.FOLSOM_lookup.txt. The output path will not contain an active link.\"" \
            -e "set dialogResult to display dialog dialogText with icon caution buttons {\"Cancel\", \"Open file\"} default button \"Cancel\"" \
            -e "if button returned of dialogResult is \"Open file\" then" \
            -e "   do shell script \"echo \\\"$onedriveRootFolderLocal(;;;(put intermediate path here and remove all parentheses))\\\" >> ~/.FOLSOM_lookup.txt; open -e ~/.FOLSOM_lookup.txt\"" \
            -e "end if"
        #End the script here, with the cleaned-up path, but no active link
        outputPath=`echo $localPathClean | sed 's|^/||g' | sed 's|/| > |g'`
        osascript -e "set the clipboard to \""$outputPath"\""
        return 0
    fi
    intermediatePath=`grep -F $onedriveRootFolderLocal ~/.FOLSOM_lookup.txt | sed "s|$onedriveRootFolderLocal;;;||g"`
fi

# Generate the full share link
fullShareLink=$davUrlNamespace$intermediatePath$relativePath"\?csf=1\&web=1"

# Generate HTML text for clipboard
outputPath=`echo $myPathPrefix$localPathClean | sed 's|^/||g' | sed 's|/| > |g'`
# replace "pathLastElement" (i.e. final file or folder) with
# <a href=" $fullShareLink "> $pathLastElement </>
pathLastElement=`basename $inputPath`
htmlOutputPath=`echo $outputPath | sed "s|$pathLastElement|<a href=\"$fullShareLink\">$pathLastElement</a>|g"`
fullHtmlOutput="<span style=\"font:Helvetica;font-size:9pt;\">"$htmlOutputPath"</span>"

# Put the HTML text on the clipboard (via https://assortedarray.com/posts/copy-rich-text-cmd-mac/)
echo $fullHtmlOutput | hexdump -ve '1/1 "%.2x"' | xargs printf "set the clipboard to {text:\" \", «class HTML»:«data HTML%s»}" | osascript -

# -------------------------------------------------------
# END OF IS-ONEDRIVE IF SECTION
# -------------------------------------------------------


else
    echo "The script can't identify if the input path is or isn't a OneDrive path."
fi






