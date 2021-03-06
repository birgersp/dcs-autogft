$examplesDir = "examples"
$archiveDir = "build-zip"
$versionFile = "version.txt"
$buildDir = "build"

$version = Get-Content -Path $versionFile
$archiveFile = "gws-$($version).zip"
$examplesDestination = "$($buildDir)\examples"
$exampleMission="~\Saved Games\DCS.openbeta\Missions\gws-example.miz"

Remove-Item .\build\* -Recurse -Force
& .\ps\make.ps1
& .\ps\make-docs.ps1

$rootDir = Get-Location
$examplesDirFull = "$($rootDir)\$($examplesDir)"

# Create examples dest dir
[void](New-Item -ItemType Directory -Path $examplesDestination -Force)

# Copy examples
$exampleFiles = Get-ChildItem $examplesDirFull *.lua
for ($i=0; $i -lt $exampleFiles.Count; $i++) {
	$filename = "$($examplesDir)\$($exampleFiles[$i])"
	Write-Host "Including $($filename)"
	Copy-Item $filename $examplesDestination -Force
	# Write-Host $filename
}

# Copy README
Copy-Item README.md $buildDir\README.txt -Force
Copy-Item $exampleMission $buildDir\example-$version.miz

# Copy docs
Write-Host "Copying docs"
Copy-Item -Recurse docs $buildDir

# Create zip dir
[void](New-Item -ItemType Directory -Path $archiveDir -Force)
if (Test-Path $archiveDir\$archiveFile) {
	Remove-Item $archiveDir\$archiveFile
}

# Create zip
7z a .\$archiveDir\$archiveFile .\$buildDir\* .\$buildDir\docs\ .\$buildDir\examples\
