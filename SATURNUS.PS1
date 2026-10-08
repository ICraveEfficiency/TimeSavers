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
# SATURNUS.ps1                            Copyright © 2026
# Contact me on GitHub https://github.com/ICraveEfficiency
#
# This script is free to use, redistribute, or modify, for
# personal or commercial use, with attribute and adherence
# to the GNU General Public License v3.0 (GPL-3.0).
#
# This script was developed collaboratively with ChatGPT.
# Approximate creation time: 2.5 hours.
#
# ========================================================
#                      CODE BEGINS
# ========================================================

$ErrorActionPreference = "Stop"

try {

    # ========================================================
    #                  DETERMINE ROOT FOLDER
    # ========================================================

    $RootFolder = Split-Path `
        -Parent `
        $MyInvocation.MyCommand.Definition


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


    # ========================================================
    #                  FIND FOLDERS
    # ========================================================
    #
    # Get every subfolder beneath the root.
    #
    # The root folder itself is deliberately excluded.
    #
    # Sorting by FullName in descending order and calculating
    # the depth makes ordering explicit and reliable.
    # ========================================================

    $folders = Get-ChildItem `
        -LiteralPath $RootFolder `
        -Directory `
        -Recurse `
        -Force `
        -ErrorAction Stop |
        Sort-Object {
            ($_.FullName -split '[\\\/]').Count
        } -Descending


    # ========================================================
    #                  PREVIEW / IDENTIFICATION
    # ========================================================

    $emptyFolders = New-Object `
        System.Collections.Generic.List[object]

    foreach ($folder in $folders) {

        try {

            $contents = Get-ChildItem `
                -LiteralPath $folder.FullName `
                -Force `
                -ErrorAction Stop

            if ($contents.Count -eq 0) {

                $emptyFolders.Add($folder)
            }
        }
        catch {

            # Ignore folders that cannot be inspected during
            # the initial scan. They will not be deleted.
            continue
        }
    }


    # ========================================================
    #                  INITIAL SUMMARY
    # ========================================================

    Write-Host "Empty folders found:"
    Write-Host "  $($emptyFolders.Count)"
    Write-Host ""

    if ($emptyFolders.Count -eq 0) {

        Write-Host "No empty folders found."
        Write-Host ""

        Read-Host "Press Enter to close"
        exit
    }


    # ========================================================
    #                       PREVIEW
    # ========================================================

    Write-Host "========================================"
    Write-Host " FOLDERS TO DELETE"
    Write-Host "========================================"
    Write-Host ""

    foreach ($folder in $emptyFolders) {

        Write-Host $folder.FullName
    }

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

    Write-Host "This will permanently remove:"
    Write-Host "  Empty folders listed above"
    Write-Host ""

    Write-Host "The root folder itself will NOT be deleted."
    Write-Host ""

    $confirmation = Read-Host "Type YES to continue"

    if ($confirmation -ne "YES") {

        Write-Host ""
        Write-Host "Nothing was deleted."
        Write-Host ""

        Read-Host "Press Enter to close"
        exit
    }


    # ========================================================
    #                       DELETE
    # ========================================================

    Write-Host ""
    Write-Host "Deleting empty folders..."
    Write-Host ""

    $deleted = 0
    $failed = 0


    # --------------------------------------------------------
    # Re-evaluate every folder immediately before deletion.
    #
    # This is important because a folder that was not empty
    # during the initial scan may have become empty after a
    # child was removed.
    # --------------------------------------------------------

    foreach ($folder in $folders) {

        try {

            $contents = Get-ChildItem `
                -LiteralPath $folder.FullName `
                -Force `
                -ErrorAction Stop

            if ($contents.Count -ne 0) {
                continue
            }

            Remove-Item `
                -LiteralPath $folder.FullName `
                -Force `
                -ErrorAction Stop

            $deleted++

            Write-Host "Deleted: $($folder.FullName)"
        }
        catch {

            # A folder may have disappeared because it was
            # removed as part of another operation, or it may
            # simply be inaccessible.
            #
            # Record the failure rather than terminating the
            # entire cleanup.
            $failed++

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

    Write-Host "Empty folders found during initial scan:"
    Write-Host "  $($emptyFolders.Count)"
    Write-Host ""

    Write-Host "Folders deleted:"
    Write-Host "  $deleted"
    Write-Host ""

    Write-Host "Failed:"
    Write-Host "  $failed"
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
