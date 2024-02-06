$fileDir = Read-Host -Prompt "Enter directory to scan for files"
Set-Location -LiteralPath $fileDir
If ($fileDir[-1] -ne '\'){
	$fileDir = $fileDir + "\"
}

# Debug:
# Write-Host "DEBUG:`nLocation:",$(Get-Location)
# Read-Host

# Choose up or down and build index
# Based on files over 10MB
$up = {Get-ChildItem *.mp4,*.avi,*.mov,*.webm,*.mkv -Recurse -File | Where-Object {($_.Name -notlike '*x265*') -and ($_.Length -gt 10MB)} | Sort-Object -Property Length}
$down = {Get-ChildItem *.mp4,*.avi,*.mov,*.webm,*.mkv -Recurse -File | Where-Object {($_.Name -notlike '*x265*') -and ($_.Length -gt 10MB)} | Sort-Object -Property Length -Descending}
$ud = Read-Host "Up or down? u/d"

# Directory and file paths
$scriptDir = "D:\System\FFMPEG\Batch H265 Conversion\"
Write-Host "Save logs to script directory or file directory? (s/f)"
Write-Host "Script dir: $scriptDir"
Write-Host "File dir: $fileDir"
$lg = Read-Host
While ("s","f" -NotContains $lg) {
	Write-Host "Try again. Save logs to script directory or file directory? (s/f)"
	$lg = Read-Host
}
If ($lg -like 's'){
	$logDir = $scriptDir
} Else {
	$logDir = $fileDir
}
$transcript = $logDir + "Transcript-" + (Get-Date -Format "yyyyMMdd-HHmmss") + ".txt"
$index = $logDir + "Index-" + (Get-Date -Format "yyyyMMdd-HHmmss") + ".json"
$processed_log = $logDir + "Processed_Files.json"
$pause = $logDir + "Pause.txt"

Write-Host "`nStarting transcript log..."
Start-Transcript -Path $transcript -Append

$files = @()
Write-Host "`nBuilding file index..."
If ($ud -like "u"){
    $files += &$up
} ElseIf ($ud -like "d") {
    $files += &$down
}
Write-Host "Finished building index."
Write-Host "Found",$files.Count,"files to convert."
Write-Host "Writing index to file $index"
ConvertTo-Json -WarningAction SilentlyContinue -Depth 1 -InputObject $($files | Select-Object -Property Directory,Name,FullName,Extension,Length,CreationTime,LastAccessTime) | Out-File $index

# Get current processed files object:
Write-Host "`nGetting current conversion logs..."
$processed = @()
If (Test-Path $processed_log){
    $processed += Get-Content $processed_log | ConvertFrom-Json
}
# Else {
#     $processed = @()
# }

# Debug:
# Write-Host "DEBUG:`nFiles:",$files
# Read-Host

Write-Host "Press Enter to begin conversions" -NoNewline
Read-Host
Write-Host "Beginning conversions..."
# Iterate through video files
$files | ForEach-Object {
    Set-Location -LiteralPath $_.Directory
    
    Write-Host "`n========================================================="
    Write-Host "Current directory:",(Get-Location).Path -ForegroundColor Green
    Write-Host "Current file:",$_.Name
    Write-Host "[Total: $($files.Count)]","[Remaining: $($files.Count - $files.IndexOf($_))]"
    
    # Debug:
    # Write-Host "`nDone Location..."

    # Loop until file is done. Means you can pause the loop using the text file and continue afterwards, without moving to next file.
    # Text file: "D:\System\FFMPEG\Batch H265 Conversion\Pause.txt"
    $completed = $false
    While ($completed -eq $false){
        
        # Debug:
        # Write-Host "`nDone Completed..."

        # Check processing hasn't been paused
        If (!(Test-Path $pause)){
            # Check file hasn't already been processed (it still exists)
            If (Test-Path -LiteralPath $_){
                
                # Debug:
                # Write-Host "`nDone Test-Path..."

                # Initialise variables
                $info = $newres = $resize = $null
                
                # Check resolution and which way around the resize needs to be
                # New version using jquery (jq)
                $fullinfo = mediainfo --output=JSON $_.Name
                $vinfo = $fullinfo | jq '.media.track[1] | {Width: .Width, Height: .Height, Format: .Format}' | ConvertFrom-Json
                $ainfo = $fullinfo | jq '.media.track[2] | {Format: .Format}' | ConvertFrom-Json
                
                $width = $vinfo.Width
                $height = $vinfo.Height
                $format = $vinfo.Format
				$bitrate = $vinfo.BitRate
                
                # Original version
                # $info = (mediainfo '--Output=Video;%Width%,%Height%,%Format%' $_.Name) -split ','
                # $width = $info[0]
                # $height = $info[1]
                # $format = $info[2]
                
                If ($format -ne 'HEVC'){
                    If ($width -gt $height){
                        Switch ($width) {
                            "4096"    								{$newres = '-filter:v "scale=width=1920:height=-2"';$resize = '-r'}
							{$_ -le "3840" -and $_ -gt "1920"}		{$newres = '-filter:v "scale=width=1920:height=-2"';$resize = '-r'}
							{$_ -le "1920"}							{$newres = '-filter:v mpdecimate';$resize = $null}
							# "1920"    {$newres = '-filter:v mpdecimate';$resize = $null}
                            # "1440"    {$newres = '-filter:v mpdecimate';$resize = $null}
                            # "1280"    {$newres = '-filter:v mpdecimate';$resize = $null}
                        }
                    } Else {
                        Switch ($height) {
                            "4096"    								{$newres = '-filter:v "scale=width=-2:height=1920"';$resize = '-r'}
                            {$_ -le "3840" -and $_ -gt "1920"}		{$newres = '-filter:v "scale=width=-2:height=1920"';$resize = '-r'}
							{$_ -le "1920"}							{$newres = '-filter:v mpdecimate';$resize = $null}
							# "1920"    {$newres = '-filter:v mpdecimate';$resize = $null}
                            # "1440"    {$newres = '-filter:v mpdecimate';$resize = $null}
                            # "1280"    {$newres = '-filter:v mpdecimate';$resize = $null}
                        }
                    }
                    
                    # Naming:
                    # -x265v1 = -x265-crf28-medium-nodupes[-resized]
                    # -x265v2 = -x265-crf28-medium-nodupes[-r]

                    $oldname = '"' + $_.Name + '"'
                    $newname = '"' + ($_.Name -replace $_.Extension,("-x265v2$resize.mp4")) + '"'
                    
                    # Removed '-map 0' due to tag errors
                    $ffmpegargs = "-hide_banner -i",$oldname,"-c:v libx265 -crf 28 -preset medium -vtag hvc1 -pix_fmt yuv420p -movflags use_metadata_tags",$newres,"-c:a aac -b:a 192k",$newname

                    # Debug:
                    # Force error for debugging:
                    # $ffmpegargs = "-i",$oldname,"-c:libx265 -crf 28 -preset medium -vtag hvc1 -pix_fmt yuv420p -movflags use_metadata_tags -map 0 -vf mpdecimate",$newres,"-c:a copy",$newname," -loglevel debug"
                    # Write-Host "DEBUG-`nOldname:",$oldname,"`nNewname:",$newname,"`nFFMPEG Args:",$ffmpegargs
                    # Read-Host

                    # Check it hasn't already been started by other process then start
                    If (!(Test-Path -LiteralPath $($newname -replace '"',''))){
                        Write-Host "Beginning conversion for $_" -ForegroundColor Green
                        Write-Host "$(Get-Date -Format "MM/dd/yyyy HH:mm:ss")" -ForegroundColor Red
                        Write-Host "========================================================="
                        Start-Process -FilePath ffmpeg -ArgumentList $ffmpegargs -Wait -NoNewWindow
                        # -RedirectStandardOutput stdout.txt -RedirectStandardError stderr.txt
                        
                        # Allow new file creation to finish before measuring new file size
                        # Start-Sleep 2s
                        
                        # Get object for newly created item
                        $newFile = Get-Item -LiteralPath ($newname -replace '"','')
                        
                        # Delete original
                        If ($? -and ($newFile -ne $null) -and ($newFile.Length -gt 0)){
                            Write-Host "`nFFMPEG completed successfully" -ForegroundColor Green
                            
                            # Debug
                            # Read-Host -Prompt "Test completed and file should be ok to delete. Press enter to continue"
                            try {
                                # Record in log
                                [long]$OldSize = "{0:N2}" -f (($_ | Measure-Object -Property Length -Sum).Sum)
                                [long]$NewSize = "{0:N2}" -f (($newFile | Measure-Object -Property Length -Sum).Sum)
                                $processed += [PSCustomObject]@{
                                    Path = (Get-Location).Path
                                    OldName = $_.Name
                                    NewName = $newFile.Name
                                    OldSize = $OldSize
                                    NewSize = $NewSize
                                    Saving = $OldSize - $NewSize
                                }
                                # Need to update this if I want to run multiple instances, as would need to add to end of file instead of replace the whole file
                                $processed | ConvertTo-Json | Set-Content $processed_log

                                # Remove original file
                                Write-Host "Removing original file" -ForegroundColor Red
                                Remove-Item -LiteralPath $_.Name -Force
                                Write-Host "========================================================="
                            }
                            catch {
                                Write-Host "Error during log creation. File deletion skipped."
                                Write-Host $_
                                Write-Host $_.ScriptStackTrace
                                Write-Host "========================================================="
                            }
                        } Else {
                            Write-Host "FFMPEG Error. Check files for $($_.FullName).`nSkipping to next file." -ForegroundColor Red
                            Write-Host "========================================================="
                        }
                        $completed = $true
                    } Else {
                        Write-Host "File already created for $newname.`nSkipping to next file." -ForegroundColor DarkYellow
                        Write-Host "========================================================="
                        $completed = $true
                    }
                # } ElseIf {
					### Move this block up to the initial comparison If statement
					# Write-Host "HEVC format already present for $($_.FullName) but bitrate is high so will proceed to reencode." -ForegroundColor DarkYellow
                    # Write-Host "========================================================="
					# ($fullinfo | jq '.media.track[1].BitRate' | ConvertFrom-Json) / 1000 -gt 2000
				} Else {
                    Write-Host "HEVC format already present for $($_.FullName) at a low bitrate.`nSkipping to next file." -ForegroundColor DarkYellow
                    Write-Host "========================================================="
                    $completed = $true
                }
            }
        } Else {
            Write-Host "$(Get-Date -Format "MM/dd/yyyy HH:mm:ss")","::: Looping paused. Waiting 30s."
            Start-Sleep 30s
            
            # Debugging:
            # Write-Host "Debugging:"
            # Write-Host 'Test-Path $_ :::',"`t",(Test-Path $_)
            # Write-Host 'Test-Path -LiteralPath $_ :::',"`t",(Test-Path -LiteralPath $_)
            # Write-Host '!(Test-Path "D:\System\FFMPEG\Batch H265 Conversion\Pause.txt") :::',"`t",(!(Test-Path "D:\System\FFMPEG\Batch H265 Conversion\Pause.txt"))
            # Write-Host '((Test-Path $_) -and !(Test-Path "D:\System\FFMPEG\Batch H265 Conversion\Pause.txt"))',"`t",((Test-Path $_) -and !(Test-Path "D:\System\FFMPEG\Batch H265 Conversion\Pause.txt"))
            # Write-Host '((Test-Path -LiteralPath $_) -and !(Test-Path "D:\System\FFMPEG\Batch H265 Conversion\Pause.txt"))',"`t",((Test-Path -LiteralPath $_) -and !(Test-Path "D:\System\FFMPEG\Batch H265 Conversion\Pause.txt"))
            # Read-Host
        }
    }
}
Write-Host "`nCompleted." -ForegroundColor Green
Write-Host "Stopping transcript."
Stop-Transcript
Read-Host
