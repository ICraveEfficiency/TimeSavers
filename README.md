# TimeSavers

This is a collection of scripts I have written with AI to fulfill functions that I found oddly lacking in various programs, websites, etc. 

Use these with caution and at your own risk. **In the case of file management scripts, I recommend testing them on a folder with some example files first.** 

# OUT WITH THE OLD

This PowerShell utility helps you find and permanently remove older items from the Windows Recycle Bin. It specifically targets items that have remained in the Recycle Bin longer than a user-selected retention period.

The script examines the `$I` metadata records of the Windows Recycle Bin to determine each item's original path, original size, and deletion time. This allows it to identify items based on when they were actually deleted rather than relying on the current filesystem timestamps of the internal `$R` files.

OUT WITH THE OLD offers three operating modes: a **Review & Clean Up** mode for scanning and optionally deleting qualifying items, a **Scan Only** mode for reviewing and reporting items without deleting them, and a **Clean Up Using Previous Report CSV** mode for carrying out a previously reviewed cleanup without performing another full scan.

Before anything is permanently removed, the script displays the qualifying items and requires explicit confirmation. During deletion, each item is revalidated against the current Recycle Bin contents to help prevent changed or previously removed items from being deleted unintentionally.

The utility can generate CSV reports containing the scan or cleanup results. Reports use timestamped filenames so that multiple scans and cleanups can be retained separately for reference.

OUT WITH THE OLD does not restore, recover, or inspect the contents of deleted files. It is intended specifically for managing older items that have already been sent to the Windows Recycle Bin and are no longer wanted.


# HOLLOW FOLDER EXPUNGER

This PowerShell utility for finding and permanently removing unnecessary items from the Windows Recycle Bin. It specifically targets: FILES that were originally 0 bytes in size and FOLDERS that were originally empty.

The script examines the $I metadata records of the Windows Recycle Bin to determine the item's original size, path, and deletion time, rather than relying solely on internal $R filenames. This allows it to distinguish genuinely empty items from deleted files and folders that may currently appear empty for other reasons.

Before anything is removed, the script displays the original path and type of every qualifying item and requires explicit confirmation. 

This utility **includes a dry-run mode**, allowing the scan to be tested and its results reviewed without deleting anything.

When deletion is enabled, the qualifying Recycle Bin items and their associated metadata records are permanently removed.

You have the option to generate a CSV log containing the results of the cleanup.

HOLLOW FOLDER EXPUNGER does not attempt to recover, restore, or inspect the contents of ordinary non-empty files. It is intended specifically for cleaning out zero-byte files and originally empty folders that have already been sent to the Windows Recycle Bin.


# THE MIDDEN MINER

This PowerShell utility helps you find and recover items from the Windows Recycle Bin. It examines the `$I` metadata records of the Windows Recycle Bin to determine each item's original path, original size, and deletion time, allowing deleted items to be identified and reconstructed according to their original filesystem locations.

THE MIDDEN MINER offers several operating modes, including a **Scan Only** mode for reviewing and reporting Recycle Bin contents without changing anything, a **Scan and Recover** mode for recovering qualifying items, and a **Recover Using Previous Scan CSV** mode for carrying out a previously reviewed recovery without performing another full scan.

The utility allows items to be filtered by **file type** and **deletion date range** before recovery. Supported categories include pictures, videos, audio files, text files, documents, and archives.

Recovered files are placed in a newly created, timestamped `THE MIDDEN` folder on the user's Desktop. The original drive and directory structure are recreated within the recovery folder so that recovered files can be organized according to where they originally existed. Existing files are not overwritten; if a destination filename already exists, a unique filename is generated instead.

Before any recovery takes place, the script displays the selected recovery criteria and requires explicit confirmation. During recovery, each item is revalidated against the current Recycle Bin contents and its `$I` metadata to help prevent stale, changed, or mismatched records from being recovered unintentionally.

THE MIDDEN MINER can generate CSV reports containing the scan or recovery results. A scan CSV can subsequently be used as a recovery manifest, allowing a previously reviewed set of items to be recovered without repeating the original scan. Reports use timestamped filenames so that multiple scans and recovery operations can be retained separately for reference.

THE MIDDEN MINER is **non-destructive to the Recycle Bin**. It copies qualifying items to the recovery location rather than permanently deleting them from the Recycle Bin. The original Recycle Bin contents remain available unless removed separately by another operation.

The utility is intended specifically for recovering files that are still present in the Windows Recycle Bin. **It does not attempt to recover files that have already been permanently deleted from the Recycle Bin.**
