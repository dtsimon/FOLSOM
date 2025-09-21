#! /bin/zsh

# --------------------------------------------------------------------------------
# FOLSOM: Fast OneDrive Links to Sharepoint On Mac
#
# Script to get the "share with existing access" url for a file synced locally
# with OneDrive. Meant to work on personal and "shared-with-me" files
#
# https://github.com/dtsimon/FOLSOM
# --------------------------------------------------------------------------------


# --- Debug controls -----------------------------------------------------------
# Use: ./FOLSOMv1.1.sh --debug <path>   or   DEBUG=1 ./FOLSOMv1.1.sh <path>
if [[ ${1:-} == "--debug" ]]; then export DEBUG=1; shift; fi
DEBUG=${DEBUG:-0}
say(){ printf "%s\n" "$*" >&2; }
dbg(){ [[ "$DEBUG" = 1 ]] && say "DEBUG: $*"; }

# Normalize Unicode to NFC (fixes composed vs decomposed diacritics in paths)
nfc() {
  /usr/bin/python3 - "$1" <<'PY'
import sys, unicodedata
print(unicodedata.normalize('NFC', sys.argv[1]))
PY
}

# Start by setting the clipboard. 
# FOLSOM takes a few seconds, so set the clipboard to a short message explaining this.
#echo -n "FOLSOM is processing..." | pbcopy
dbg "Starting FOLSOM v1.1"

# The script is meant to start with a file path from a Finder action
# inputPath=`readlink -f $@`
# Accept input from argv, or $FOLSOM_INPUT, or ~/.FOLSOM_lookup_input (Automator)
inputPath="${1:-}" 
if [[ -z "$inputPath" && -n "${FOLSOM_INPUT:-}" ]]; then
  inputPath="$FOLSOM_INPUT"
  dbg "inputPath source: FOLSOM_INPUT env"
elif [[ -z "$inputPath" && -f "$HOME/.FOLSOM_lookup_input" ]]; then
  inputPath=$(<"$HOME/.FOLSOM_lookup_input")
  dbg "inputPath source: ~/.FOLSOM_lookup_input"
else
  [[ -n "$inputPath" ]] && dbg "inputPath source: argv"
fi

dbg "inputPath: $inputPath"
if [[ -z "$inputPath" ]]; then 
  say "Usage: FOLSOMv1.1.sh [--debug] <path>  (or set FOLSOM_INPUT, or write to ~/.FOLSOM_lookup_input)"; 
  exit 1; 
fi
if [[ ! -e "$inputPath" ]]; then say "Path does not exist: $inputPath"; exit 1; fi

inputPathN=$(nfc "$inputPath")
dbg "inputPathNFC: $inputPathN"

# Check if the inputPath is synced through OneDrive
# If it isn't, skip to the end... if it is, run the full script
# 1. Get the OneDrive paths

# !!!! fileproviderctl listprovider broken in macOS 14.4!!
# onedriveFileProviderPaths=`fileproviderctl listproviders | grep -E "OneDrive-mac" | sed "s|com.microsoft.OneDrive-mac.FileProvider|$HOME|g"`
# This solution is much slower as it requires a (even limited!) dump
# onedriveFileProviderPaths=`fileproviderctl dump --limit-dump-size | grep -F "com.apple.file-provider-domain-id:" | sort | uniq | grep -F "OneDrive-mac" | sed "s|.*OneDrive\-mac\.FileProvider|$HOME|g" `
# Prefer a fast discovery from the standard CloudStorage location (macOS 12.3+)
# Fall back to `fileproviderctl dump` only if nothing is found.
{
  # Collect roots in an array (safer than string with \n)
  typeset -a onedriveFileProviderPathsArray
  onedriveFileProviderPathsArray=()
  dbg "Discovering OneDrive roots via CloudStorage fast path"
  used_fallback=0
  # Fast path: look for OneDrive roots under ~/Library/CloudStorage
  for p in "$HOME"/Library/CloudStorage/OneDrive*; do
    [[ -e "$p" ]] || continue
    dbg "Found CloudStorage root: $p"
    # Add only the visible CloudStorage mount; do NOT resolve with readlink here
    onedriveFileProviderPathsArray+=("$p")
  done
  # Also include visible alias roots (OneDrive creates these in $HOME)
  for p in "$HOME"/OneDrive*; do
    [[ -e "$p" ]] || continue
    dbg "Found visible OneDrive alias root: $p"
    onedriveFileProviderPathsArray+=("$p")
  done
  # If nothing was discovered, use the slower dump as a fallback
  if [[ ${#onedriveFileProviderPathsArray[@]} -eq 0 ]]; then
    used_fallback=1
    dbg "CloudStorage fast path empty; using fileproviderctl dump fallback"
    # macOS 14.4+ removed/changed `listproviders`; dump is slower but works
    # Append discovered roots to the array
    onedriveFileProviderPathsArray+=( "${(@f)$(fileproviderctl dump --limit-dump-size \
      | grep -F "com.apple.file-provider-domain-id:" \
      | sort | uniq \
      | grep -F "OneDrive-mac" \
      | sed "s|.*OneDrive\-mac\.FileProvider|$HOME|g")}" )
    # Debug print each fallback root
    for _p in "${onedriveFileProviderPathsArray[@]}"; do dbg "  fallback root: $_p"; done
  fi
} 

# 2. Debug list discovered roots (already in array)
if [[ ${#onedriveFileProviderPathsArray[@]} -eq 0 ]]; then
  dbg "No OneDrive roots discovered"
else
  dbg "All discovered roots (array):"
  for _p in "${onedriveFileProviderPathsArray[@]}"; do dbg "  - $_p"; done
fi
dbg "Root array has ${#onedriveFileProviderPathsArray[@]} entries"

# 3. Get the original paths for the onedriveFileProviderPaths
dbg "Resolving original paths; used_fallback=${used_fallback:-0}"
for singleOnedrivePath in "${onedriveFileProviderPathsArray[@]}"; do
    dbg "Candidate root: $singleOnedrivePath"
    originalPath=$singleOnedrivePath
    # If the fallback method was used, follow the link to the real original folder
    if [[ ${used_fallback:-0} -eq 1 ]]; then
        originalPath=$(readlink "$singleOnedrivePath")
        dbg "readlink resolved to: $originalPath"
        [[ -n "$originalPath" ]] && onedriveFileProviderPathsArray+=("$originalPath") && dbg "Added original path: $originalPath"
    fi
done

# 4. Set a flag to indicate if the inputPath is found
dbg "Matching input path against discovered roots"
isOnedrive=0
# Initialize normalized local path clean variable
localPathCleanN=""
# 5. Iterate over the array and check if the inputPath contains any of the paths
for singleOnedrivePath in "${onedriveFileProviderPathsArray[@]}"; do
  dbg "Testing match against: $singleOnedrivePath"
  candN=$(nfc "$singleOnedrivePath")
  dbg "Testing NFC match against: $candN"
  if [[ "$inputPathN" == "$candN"* ]]; then
    dbg "Matched root (NFC): $candN"
    isOnedrive=1
    # Remove the root prefix from the normalized input
    localPathCleanN="${inputPathN#$candN/}"
    # Also keep a non-normalized version for display if needed
    localPathClean="$localPathCleanN"
    break
  fi
done

# 6. Choose what to do if is or isn't OneDrive path
if [[ $isOnedrive -eq 0 ]]; then
    dbg "Input is NOT under OneDrive; copying plain breadcrumb"
    # It's just a regular path outside of OneDrive
    # Generate basic output path
    # Remove initial "/" anc convert intermediate "/" --> " > "
    outputPath=`echo $inputPath | sed 's|^/||g' | sed 's|/| > |g'`
    dbg "Plain breadcrumb: $outputPath"
    osascript -e "set the clipboard to \""$outputPath"\""

elif [[ $isOnedrive -eq 1 ]]; then
    dbg "onedriveRootFolderLocal: $onedriveRootFolderLocal"
    # It IS a OneDrive path... proceed with rest of script

# -------------------------------------------------------
# BEGINNING OF IS-ONEDRIVE IF SECTION
# -------------------------------------------------------

# Process the inputPath
# Get the local base OneDrive folder name
onedriveRootFolderLocal=`echo $localPathClean | cut -d "/" -f1`
dbg "onedriveRootFolderLocal: $onedriveRootFolderLocal"

# Check if it's in MySite (personal OneDrive structure)
if [[ $singleOnedrivePath != *"Shared"* ]];  then
    dbg "Detected personal MySite (non-Shared)"
    # It's inside own OneDrive structure
    onedriveRootSite="MySite"
    myPathPrefix=`id -F`"/"
    # For personal MySite, the web path includes the local root (e.g., Documents/Personal/...)
    intermediatePath="$onedriveRootFolderLocal/"
    dbg "intermediatePath (personal): $intermediatePath"
    is_shared=0
else
    dbg "Detected Shared/Team/Other: rootSite=$onedriveRootSite rootShare=$onedriveRootShare"
    # It's shared with me, on Sharepoint/Teams, or someone else's OneDrive
    # Split the local base folder into site/person and share name
    onedriveRootSite=`echo $onedriveRootFolderLocal | sed 's/\ -\ .*//g'`
    onedriveRootShare=`echo $onedriveRootFolderLocal | sed 's/.*\ -\ //g'`
    dbg "Detected Shared/Team/Other: rootSite=$onedriveRootSite rootShare=$onedriveRootShare"
    # For SharePoint/Teams libraries, the first folder under the document library is the channel/share (e.g., General)
    intermediatePath="$onedriveRootShare/"
    dbg "intermediatePath (shared): $intermediatePath"
    is_shared=1
fi

# Get the relative path to the file past the root folder
relativePath=`echo $localPathClean | sed "s|$onedriveRootFolderLocal/||g"`
dbg "relativePath: $relativePath"

# Retrieve OneDrive sync info
dbg "Reading OneDrive INI settings (Business1)"
cd ~/"Library/Containers/com.microsoft.OneDrive-mac/Data/Library/Application Support/OneDrive/settings/Business1"
libraryScope=`grep -E "^libraryScope.*\s5\s\"$onedriveRootSite\"\s" *.ini | sed "s|.*\"$onedriveRootSite\"||g" | awk '{print $3}'  | sed 's/\"//g'`
dbg "libraryScope: $libraryScope"
davUrlNamespace=`grep -hF $libraryScope *.ini | grep -E "DavUrlNamespace" | sed 's|DavUrlNamespace = ||g'`
dbg "davUrlNamespace: $davUrlNamespace"
userName=`grep -E "MySite" *.ini | sed "s|.*personal/||g" | sed "s|\"\ .*||g"`
dbg "userName: $userName"

# For shared libraries, avoid duplicating the document library name (e.g., "Documents" or localized like "Delade dokument")
if [[ ${is_shared:-0} -eq 1 ]]; then
  libSegment=$(/usr/bin/python3 - "$davUrlNamespace" <<'PY'
import sys, urllib.parse
p = urllib.parse.urlsplit(sys.argv[1]).path.rstrip('/')
print(p.rsplit('/', 1)[-1])
PY
)
  dbg "davUrlNamespace library segment: $libSegment"
  libSegmentN=$(nfc "$libSegment")
  rootShareN=$(nfc "$onedriveRootShare")
  if [[ "$rootShareN" == "Documents" || "$rootShareN" == "$libSegmentN" ]]; then
    dbg "Root share equals library segment; clearing intermediatePath to avoid duplication"
    intermediatePath=""
  fi
fi

dbg "Evaluating whether URL is personal vs shared"
# Check if the Sharepoint URL is a "site" (Team or Sharepoint) or "personal" (user's OneDrive)
if [[ $davUrlNamespace == *"personal"* ]] && [[ "$davUrlNamespace" != *$userName* ]]; then
    # The URL is pointing toward a personal OneDrive share
    # need to get the intermediate folder structure
    # from lookup table or interactively
    lookupCount=`grep -cF "$onedriveRootShare;;;" ~/.FOLSOM_lookup.txt`
    dbg "Lookup count for $onedriveRootShare in ~/.FOLSOM_lookup.txt: $lookupCount"
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
    dbg "Using lookup intermediatePath for $onedriveRootFolderLocal"
    intermediatePath=`grep -F $onedriveRootFolderLocal ~/.FOLSOM_lookup.txt | sed "s|$onedriveRootFolderLocal;;;||g"`
fi

# Generate the full share link (raw), then URL-encode the path
rawShareLink=$davUrlNamespace$intermediatePath$relativePath"?csf=1&web=1"
dbg "rawShareLink (pre-encode): $rawShareLink"
fullShareLink=$(python3 - "$rawShareLink" <<'PY'
import sys, urllib.parse
url = sys.argv[1]
s = urllib.parse.urlsplit(url)
path_enc = urllib.parse.quote(s.path, safe="/")
print(urllib.parse.urlunsplit((s.scheme, s.netloc, path_enc, s.query, s.fragment)))
PY
)
dbg "fullShareLink (encoded): $fullShareLink"

# DTSIMON possible issue: backslashes in fullShareLink \? \&

# Generate HTML text for clipboard
outputPath=`echo $myPathPrefix$localPathClean | sed 's|^/||g' | sed 's|/| > |g'`
dbg "outputPath (breadcrumb before link injection): $outputPath"
# replace "pathLastElement" (i.e. final file or folder) with
# <a href=" $fullShareLink "> $pathLastElement </>
#pathLastElement=`basename $inputPath`
#htmlOutputPath=`echo $outputPath | sed "s|$pathLastElement|<a href=\"$fullShareLink\">$pathLastElement</a>|g"`
pathLastElement=`basename "$inputPath"`
# Escape regex metacharacters in the match pattern (filename)
safePathLast=$(printf '%s' "$pathLastElement" | sed -e 's/[.[\\*^$]/\\&/g')
# Escape ampersands in the replacement so sed doesn't re-insert the match
escapedFullLink=${fullShareLink//&/\\&}
htmlOutputPath=$(echo "$outputPath" | sed "s|$safePathLast|<a href=\"$escapedFullLink\">$pathLastElement</a>|g")
dbg "htmlOutputPath (with hyperlink): $htmlOutputPath"
fullHtmlOutput="<span style=\"font:Helvetica;font-size:9pt;\">"$htmlOutputPath"</span>"

# Put the HTML text on the clipboard (via https://assortedarray.com/posts/copy-rich-text-cmd-mac/)
# THIS DOESN'T SEEM TO WORK ANYMORE
# echo $fullHtmlOutput | hexdump -ve '1/1 "%.2x"' | xargs printf "set the clipboard to {text:\" \", «class HTML»:«data HTML%s»}" | osascript -

# Try a new method to paste RTF to clipboard
dbg "Copying RTF with link to clipboard"
echo $fullHtmlOutput | textutil -format html -convert rtf -inputencoding UTF-8 -encoding UTF-8 -stdin -stdout | sed 's|\\froman\\fcharset0 Times-Roman|\\fswiss\\fcharset0 Helvetica|' | pbcopy -Prefer rtf

# -------------------------------------------------------
# END OF IS-ONEDRIVE IF SECTION
# -------------------------------------------------------

else
    echo "The script can't identify if the input path is or isn't a OneDrive path."
fi






