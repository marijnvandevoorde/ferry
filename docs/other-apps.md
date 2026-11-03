# Importing into other photo apps

This applies to the Mac app (Settings → Destination → A folder), the Windows and Linux app (Settings → Import to)
and `ferryctl import`.

Ferry can put photos in a folder instead of Apple Photos (Settings → Destination → A folder).
Most photo apps can watch a folder and pick up new files from it.

## Lightroom Classic

1. In Lightroom Classic, choose **File → Auto Import → Auto Import Settings…**
2. Pick a **Watched Folder** (an empty folder, for example `~/Pictures/Fuji Inbox`) and a destination for the photos
   Lightroom moves out of it.
3. Turn on **Enable Auto Import**.
4. In Ferry, choose that same watched folder and set **Subfolders** to **No subfolders**:
   Lightroom only watches the folder itself.

## Capture One

1. In Capture One, set up a **hot folder** (in a session: **Capture → Capture Location**, or with a tethered-style hot folder plugin).
2. In Ferry, choose that folder and set **Subfolders** to **No subfolders**.

## Photo Mechanic, Adobe Bridge, darktable, digiKam

Point the app at the folder Ferry uses, and keep the default **Year / Date** subfolders if you like.

## Windows Photos and OneDrive

Use the **Pictures folder** preset. Windows Photos shows everything under Pictures, and OneDrive backs it up when
folder backup is on.

## Photoshop Elements (Windows)

In the Elements Organizer, choose **File → Watch Folders…**, add the folder Ferry uses, and pick
*Automatically add files to Elements Organizer*.

## Shotwell, GNOME Photos (Linux)

Use the **Pictures folder** preset. GNOME Photos indexes Pictures; in Shotwell, turn on
**Preferences → Watch library directory for new files** with Pictures as the library directory.

## digiKam, darktable (Linux, Windows, macOS)

digiKam: add the folder as a collection (Settings → Configure digiKam → Collections); new files appear after a scan.
darktable: **import → add to library…** the folder, or point a lua auto-import script at it.
