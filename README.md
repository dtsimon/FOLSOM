# FOLSOM
FOLSOM provides <ins>F</ins>ast <ins>O</ins>neDrive <ins>L</ins>inks to <ins>S</ins>harepoint <ins>O</ins>n <ins>M</ins>ac.

## What does FOLSOM do?
FOLSOM uses information that OneDrive stores locally on your Mac to generate share links (nearly) instantly... and copy them to the clipboard so you can paste into email, etc. What you get is a linked path on your clipboard, ready to paste into Mail.app, for example: 

**User - Documents > Project folder 1 > Sub-project fantastic > [Secret plans.docx](https://www.youtube.com/watch?v=fcMl1oOVrMk)**

## INSTALL and how to use
FOLSOM is basically just a single shell script, plus a lookup table (see below). There's also a sample Automator quickaction workflow so you can run it from the Finder context menu.

I personally put the `FOLSOM.sh` file at `~/Applications/`. Whereever you put it, you'll need to run `chmod +x FOLSOM.sh` on it.

The `FOLSOM_lookup.txt` should be placed in your home directory and renamed with a dot at the start, to `.FOLSOM_lookup.txt` and (again, details below).

You can create your own Automator quick action or modify the one included here. Read [Apple's guide to Automator quick actions here](https://support.apple.com/en-gb/guide/automator/aut73234890a/mac).

## The lookup table
URLs to files that are synced through "sites" (group Sharepoint sites, Teams, etc.) are pretty easy to construct with OneDrives local data. But files synced through someone else's (i.e., not your) OneDrive are harder to deal with. There's an intermediate part of the URL that OneDrive doesn't seem to store locally (in an easy, non-API way to deal with). For example:
`https://company.sharepoint.com/personal/username/Documents/[INTERMEDIATE PATH]/Word_document.docx?csf=1&web=1`

Currently, FOLSOM uses the *manually filled-in* `~/.FOLSOM-lookup.txt` file to access the `[INTERMEDIATE PATH]`. The way to add new entries to the lookup file is like this:
1. Run FOLSOM on the file you want to share. You'll get an Applescript dialog asking to open the lookup file. Open it and keep it open.
2. Get the share link to a file within the share (using OneDrive's Finder extension or directly through SharePoint/OneDrive online)
3. Figure out the `[INTERMEDIATE PATH]` from the share link. This will usually be *after* ~Documents/ and before the root of the share as you see it in Finder (basically, the missing path elements from Finder).
4. Add the intermediate path at the indicated place in `~/.FOLSOM-lookup.txt`. Save and close the file.
5. You can now run FOLSOM again and it should generate the linked path!

## Origin story... or why FOLSOM
I work with lots of files synced to my Mac through OneDrive Business and (very) frequently need to share them with colleagues.

So to share files (to people with existing access), I have to use the (very slow) Finder extension: right-click, Copy Link, wait several seconds, then explain in the email what the file path is (in case my colleagues want to find the file themselves), and then add the clipboard link myself. In other words, a total pain.

I know that Outlook does this automatically, but for various reasons, I don't want to use Outlook. So... FOLSOM.

## What does it actually do?
FOLSOM gets the local path, then uses OneDrive's local sync settings files to piece together a "share with people with existing access" link that (ideally) open in a browser.

In more detail, FOLSOM uses `fileproviderctl` to discover the OneDrive sync folders, and the various `*.ini` files in `~/Library/Containers/com.microsoft.OneDrive-mac/Data/Library/Application Support/OneDrive/settings/Business1` to piece together a working link. The advantages of using the `*.ini` files are:

1. No need for REST API and Microsoft auth tokens
2. The already-running OneDrive app does all the heavy lifting to keep links up to date
3. It's fast! (no need to access the internet while generating the link)

## (Significant) Limitations
I just a hobbyist with minimal coding experience. The code is **not** great... or well organized... but it mostly works. Some current limitations are:
1. Only set up for a (single) OneDrive Business account. It only scans through the `~/Library/Containers/com.microsoft.OneDrive-mac/Data/Library/Application Support/OneDrive/settings/Business1` folder.
2. The method to force the final links to open in a Word/Excel/Powerpoint online editor (and not download the target file) is to append `?csf=1&web=1` at the end of the link. This works *most* of the time...
3. There's no automatic way to populate the lookup table. From what I can tell, this *would* require accessing the OneDrive API. Currently this is done by hand.
4. I'm not sure how this would work if your system isn't set to English. The OneDrive settings folder may have a different name, and the share folders may have a name that doesn't contain "Shared".
5. Probably many others I haven't discovered yet...
