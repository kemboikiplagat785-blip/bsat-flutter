param(
    [string]$commitMessage = ""
)

# Step 1: Read current version
$pubspec = Get-Content "pubspec.yaml"
$line = $pubspec | Where-Object { $_ -match "^version:" }
$currentVersion = ($line -split ":")[1].Trim()

# Step 2: Split version and build number
if ($currentVersion -match "^(?<ver>\d+\.\d+\.\d+)(\+(?<build>\d+))?") {
    $ver = $matches['ver']
    $build = if ($matches['build']) { [int]$matches['build'] } else { 0 }
    $parts = $ver -split "\."
    $major = $parts[0]
    $minor = $parts[1]
    $patch = [int]$parts[2] + 1
    $newVersion = "$major.$minor.$patch+$build"
    # $newVersion = "3.7.0+1"
} else {
    throw "Could not parse version string: $currentVersion"
}

# Step 3: Replace version
$newPubspec = $pubspec -replace "version:.*", "version: $newVersion"
$newPubspec | Set-Content "pubspec.yaml"

# Step 4: Git operations
git add .
if ($commitMessage -ne "") {
    git commit -m "$commitMessage"
} else {
    git commit -m "Bump version to $newVersion"
}
git checkout -b "release/v$newVersion"
git push -u origin "release/v$newVersion"

# Step 5: Build APK
flutter build apk --target-platform android-arm64 --analyze-size

# Step 6: Rename APK
$apkSource = "C:\Users\USER\code\bsat-flutter\build\app\outputs\flutter-apk\app-release.apk"
$apkDest = "C:\Users\USER\code\bsat-flutter\build\app\outputs\flutter-apk\bsat.Nitro.$newVersion.apk"
if (Test-Path $apkSource) {
    Rename-Item -Path $apkSource -NewName ("bsat.Nitro.$newVersion.apk")
    Write-Host "APK renamed to bsat.Nitro ($newVersion).apk"
} else {
    Write-Host "APK not found at $apkSource"
}

Write-Host "Version bumped to $newVersion and pushed to git."