# ========================================================
#                       SATURNUS
# ========================================================
#
# This utility searches recursively in whatever folder you
# place it in. When placed inside the parent, the SATURNUS
# script will target all of the empty children. After this
# script receives your explicit consent, it will begin its
# feast on the deepest empty children, before moving on to 
# devour the shallowest, ensuring nothing is left behind.
#
# It also has the option to remove folders which have only
# a file of the following safely removable metadata types:
#
#   desktop.ini
#   Thumbs.db
#   .DS_Store
#
#
# SATURNUS.ps1                            Copyright © 2026
# Contact me on GitHub https://github.com/ICraveEfficiency
#
# This script is free to use, redistribute, or modify, for
# personal or commercial use, with attribution & adherence
# to the GNU General Public License v3.0 (GPL-3.0).
#
# This script was developed collaboratively with ChatGPT.
# Approximate creation time: 3.5 hours.
#
# ========================================================
#                      CODE BEGINS
# ========================================================

$ErrorActionPreference = "Stop"

try {

    # ========================================================
    #                  DETERMINE ROOT FOLDER
    # ========================================================

    $RootFolder = $PSScriptRoot

    if ([string]::IsNullOrWhiteSpace($RootFolder)) {
        throw "Unable to determine the script's root folder."
    }

    $RootFolder = [System.IO.Path]::GetFullPath($RootFolder)


    # ========================================================
    #                       HEADER
    # ========================================================

    Write-Host ""
    Write-Host "========================================"
    Write-Host " SATURNUS"
    Write-Host "========================================"
    Write-Host ""

    Write-Host "Root folder:"
    Write-Host "  $RootFolder"
    Write-Host ""

    # Only these exact filenames qualify as disposable
    # metadata for the optional cleanup.
    #
    # Matching is case-insensitive, as is normal on Windows.
    # No other files are treated as disposable.

    $MetadataFileNames = @(
        "desktop.ini"
        "Thumbs.db"
        ".DS_Store"
    )


    # ========================================================
    #                  FIND FOLDERS
    # ========================================================
    #
    # Discover directories one level at a time.
    # Hidden and system directories are included.
    # The root folder itself is never added to the list.
    #
    # Directory junctions and symbolic links are not
    # traversed, preventing scans outside the root folder.
    #
    # Sort deepest-first so parents are processed only
    # after their descendants during the deletion pass.
    # ========================================================

    $folderList = New-Object `
        'System.Collections.Generic.List[System.IO.DirectoryInfo]'

    $pending = New-Object `
        'System.Collections.Generic.Stack[string]'

    $pending.Push($RootFolder)

    $scanFailures = 0

    Write-Host "Discovering directories..."
    Write-Host ""

    while ($pending.Count -gt 0) {

        $currentPath = $pending.Pop()

        try {

            $children = @(
                Get-ChildItem `
                    -LiteralPath $currentPath `
                    -Directory `
                    -Force `
                    -ErrorAction Stop
            )

            foreach ($child in $children) {

                $folderList.Add($child)

                # Do not follow directory junctions or links.

                if (($child.Attributes -band `
                    [System.IO.FileAttributes]::ReparsePoint) -eq 0) {

                    $pending.Push($child.FullName)
                }
            }
        }
        catch {

            $scanFailures++

            Write-Host "DISCOVERY FAILED:" `
                -ForegroundColor Yellow

            Write-Host "  $currentPath"
            Write-Host "  $($_.Exception.Message)"
            Write-Host ""
        }
    }

    # Sort by path length descending.
    # Every descendant path is longer than its ancestor path.

    $folders = @(
        $folderList |
            Sort-Object `
                @{ Expression = { $_.FullName.Length }; Descending = $true },
                @{ Expression = { $_.FullName }; Descending = $true }
    )

    Write-Host "Directories discovered: $($folders.Count)"
    Write-Host ""


    # ========================================================
    #             IDENTIFY EMPTY AND METADATA-ONLY FOLDERS
    # ========================================================

    $emptyFolders = New-Object `
        'System.Collections.Generic.List[System.IO.DirectoryInfo]'

    $metadataOnlyFolders = New-Object `
        'System.Collections.Generic.List[System.IO.DirectoryInfo]'

    Write-Host "Checking directories for contents..."
    Write-Host ""

    foreach ($folder in $folders) {

        try {

            $contents = @(
                Get-ChildItem `
                    -LiteralPath $folder.FullName `
                    -Force `
                    -ErrorAction Stop
            )

            # Genuinely empty folders are always eligible.

            if ($contents.Count -eq 0) {
                $emptyFolders.Add($folder)
                continue
            }

            # A metadata-only folder must contain at least one
            # item, and EVERY item must be an approved file.
            #
            # Directories with approved names do not qualify.
            # Any unapproved file or subfolder disqualifies
            # the entire folder from metadata-only cleanup.

            $metadataOnly = $true

            foreach ($item in $contents) {

                if (
                    $item.PSIsContainer -or
                    $MetadataFileNames -notcontains $item.Name
                ) {
                    $metadataOnly = $false
                    break
                }
            }

            if ($metadataOnly) {
                $metadataOnlyFolders.Add($folder)
            }
        }
        catch {

            $scanFailures++

            Write-Host "SCAN FAILED:" `
                -ForegroundColor Yellow

            Write-Host "  $($folder.FullName)"
            Write-Host "  $($_.Exception.Message)"
            Write-Host ""
        }
    }


    # ========================================================
    #                  INITIAL SUMMARY
    # ========================================================

    Write-Host "========================================"
    Write-Host " SCAN SUMMARY"
    Write-Host "========================================"
    Write-Host ""

    Write-Host "Directories discovered:"
    Write-Host "  $($folders.Count)"
    Write-Host ""

    Write-Host "Genuinely empty folders found:"
    Write-Host "  $($emptyFolders.Count)"
    Write-Host ""

    Write-Host "Folders containing only approved metadata files:"
    Write-Host "  $($metadataOnlyFolders.Count)"
    Write-Host ""

    Write-Host "Scan/discovery failures:"
    Write-Host "  $scanFailures"
    Write-Host ""


    # ========================================================
    #             OPTIONAL METADATA-FOLDER CLEANUP
    # ========================================================

    $includeMetadataFolders = $false

    if ($metadataOnlyFolders.Count -gt 0) {

        Write-Host "The following filenames qualify for optional cleanup:"
        Write-Host "  desktop.ini"
        Write-Host "  Thumbs.db"
        Write-Host "  .DS_Store"
        Write-Host ""

        Write-Host "Only folders containing these files and NOTHING ELSE"
        Write-Host "will qualify. These files will be deleted only when"
        Write-Host "their containing folder is also being deleted."
        Write-Host ""

        $metadataChoice = Read-Host `
            "Also delete metadata-only folders? Type YES to include them"

        if ($metadataChoice -ceq "YES") {

            $includeMetadataFolders = $true

            Write-Host ""
            Write-Host "Metadata-only folders included."
            Write-Host ""
        }
        else {

            Write-Host ""
            Write-Host "Metadata-only cleanup declined."
            Write-Host "Only genuinely empty folders will be considered."
            Write-Host ""
        }
    }
    else {

        Write-Host "No metadata-only folders were found."
        Write-Host ""
    }


    # ========================================================
    #                  BUILD DELETION LIST
    # ========================================================

    $foldersToDelete = New-Object `
        'System.Collections.Generic.List[System.IO.DirectoryInfo]'

    foreach ($folder in $emptyFolders) {
        $foldersToDelete.Add($folder)
    }

    if ($includeMetadataFolders) {

        foreach ($folder in $metadataOnlyFolders) {
            $foldersToDelete.Add($folder)
        }
    }

    # Preserve deepest-first ordering across both categories.

    $foldersToDelete = @(
        $foldersToDelete |
            Sort-Object `
                @{ Expression = { $_.FullName.Length }; Descending = $true },
                @{ Expression = { $_.FullName }; Descending = $true }
    )


    # ========================================================
    #                       PREVIEW
    # ========================================================

    if ($foldersToDelete.Count -eq 0) {

        Write-Host "No eligible folders found."
        Write-Host ""

        Read-Host "Press Enter to close"
        exit
    }

    Write-Host "========================================"
    Write-Host " FOLDERS TO DELETE"
    Write-Host "========================================"
    Write-Host ""

    foreach ($folder in $foldersToDelete) {
        Write-Host $folder.FullName
    }

    Write-Host ""

    Write-Host "Genuinely empty folders:"
    Write-Host "  $($emptyFolders.Count)"
    Write-Host ""

    if ($includeMetadataFolders) {

        Write-Host "Metadata-only folders:"
        Write-Host "  $($metadataOnlyFolders.Count)"
        Write-Host ""
    }

    Write-Host "Total folders scheduled:"
    Write-Host "  $($foldersToDelete.Count)"
    Write-Host ""


    # ========================================================
    #                     CONFIRMATION
    # ========================================================

    Write-Host "========================================" `
        -ForegroundColor Yellow

    Write-Host " WARNING" `
        -ForegroundColor Yellow

    Write-Host "========================================" `
        -ForegroundColor Yellow

    Write-Host ""

    Write-Host "This will permanently remove the eligible folders"
    Write-Host "listed above, along with approved metadata files"
    Write-Host "inside metadata-only folders."
    Write-Host ""

    Write-Host "The root folder itself will NOT be deleted."
    Write-Host ""

    $confirmation = Read-Host "Type YES to continue"

    if ($confirmation -cne "YES") {

        Write-Host ""
        Write-Host "Nothing was deleted."
        Write-Host ""

        Read-Host "Press Enter to close"
        exit
    }


    # ========================================================
    #                       DELETE
    # ========================================================
    #
    # One pass, deepest to shallowest.
    #
    # Each folder is checked immediately before deletion.
    # The script removes a folder only if it is still empty,
    # or if metadata cleanup was enabled and its contents
    # consist exclusively of approved metadata files.
    #
    # No unapproved files or subfolders are deleted.
    # ========================================================

    Write-Host ""
    Write-Host "Deleting eligible folders..."
    Write-Host ""

    $deleted = 0
    $emptyFoldersDeleted = 0
    $metadataFoldersDeleted = 0
    $metadataFilesDeleted = 0
    $failed = 0
    $skipped = 0

    foreach ($folder in $foldersToDelete) {

        $removedMetadataInThisFolder = 0

        try {

            if (-not (Test-Path `
                -LiteralPath $folder.FullName `
                -PathType Container)) {

                $skipped++
                continue
            }

            # Recheck contents immediately before deletion.

            $contents = @(
                Get-ChildItem `
                    -LiteralPath $folder.FullName `
                    -Force `
                    -ErrorAction Stop
            )

            if ($contents.Count -eq 0) {

                # Genuinely empty: safe to remove.

                Remove-Item `
                    -LiteralPath $folder.FullName `
                    -Force `
                    -ErrorAction Stop

                $deleted++
                $emptyFoldersDeleted++

                Write-Host "Deleted empty folder: $($folder.FullName)"

                continue
            }

            # If the folder is no longer empty, only continue
            # when the user explicitly enabled metadata cleanup
            # AND every current item is an approved metadata file.

            if (-not $includeMetadataFolders) {
                continue
            }

            $metadataOnly = $true

            foreach ($item in $contents) {

                if (
                    $item.PSIsContainer -or
                    $MetadataFileNames -notcontains $item.Name
                ) {
                    $metadataOnly = $false
                    break
                }
            }

            if (-not $metadataOnly) {
                continue
            }

            # Delete only the approved files in this folder.

            foreach ($item in $contents) {

                Remove-Item `
                    -LiteralPath $item.FullName `
                    -Force `
                    -ErrorAction Stop

                $removedMetadataInThisFolder++
            }

            # Confirm the folder is empty after removing metadata.
            # This also avoids deleting the folder if something
            # appeared in it during the operation.

            $remainingContents = @(
                Get-ChildItem `
                    -LiteralPath $folder.FullName `
                    -Force `
                    -ErrorAction Stop
            )

            if ($remainingContents.Count -ne 0) {

                throw "The folder is no longer empty after metadata removal. Remaining contents were preserved."
            }

            Remove-Item `
                -LiteralPath $folder.FullName `
                -Force `
                -ErrorAction Stop

            $deleted++
            $metadataFoldersDeleted++
            $metadataFilesDeleted += $removedMetadataInThisFolder

            Write-Host "Deleted metadata-only folder: $($folder.FullName)"
        }
        catch {

            $failed++

            # If one or more metadata files were removed before
            # an error, report that fact in the final totals.

            $metadataFilesDeleted += $removedMetadataInThisFolder

            Write-Host ""
            Write-Host "FAILED:" `
                -ForegroundColor Red

            Write-Host "  $($folder.FullName)" `
                -ForegroundColor Red

            Write-Host "  $($_.Exception.Message)" `
                -ForegroundColor Red

            Write-Host ""
        }
    }


    # ========================================================
    #                   FINAL SUMMARY
    # ========================================================

    Write-Host ""
    Write-Host "========================================"
    Write-Host " COMPLETE"
    Write-Host "========================================"
    Write-Host ""

    Write-Host "Genuinely empty folders found initially:"
    Write-Host "  $($emptyFolders.Count)"
    Write-Host ""

    Write-Host "Metadata-only folders found initially:"
    Write-Host "  $($metadataOnlyFolders.Count)"
    Write-Host ""

    Write-Host "Total folders deleted:"
    Write-Host "  $deleted"
    Write-Host ""

    Write-Host "Empty folders deleted:"
    Write-Host "  $emptyFoldersDeleted"
    Write-Host ""

    Write-Host "Metadata-only folders deleted:"
    Write-Host "  $metadataFoldersDeleted"
    Write-Host ""

    Write-Host "Approved metadata files deleted:"
    Write-Host "  $metadataFilesDeleted"
    Write-Host ""

    Write-Host "Skipped (no longer present):"
    Write-Host "  $skipped"
    Write-Host ""

    Write-Host "Deletion failures:"
    Write-Host "  $failed"
    Write-Host ""

    Write-Host "Scan/discovery failures:"
    Write-Host "  $scanFailures"
    Write-Host ""

}
catch {

    Write-Host ""
    Write-Host "========================================" `
        -ForegroundColor Red

    Write-Host " SCRIPT ERROR" `
        -ForegroundColor Red

    Write-Host "========================================"
    Write-Host ""

    Write-Host $_.Exception.Message `
        -ForegroundColor Red

    Write-Host ""
}

Read-Host "Press Enter to close"
