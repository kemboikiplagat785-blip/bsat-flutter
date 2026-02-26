# param(
#     [string]$commitMessage = "",
#     [Alias('v')][string]$Version = ""
# )

# # Step 1: Read current version
# $pubspec = Get-Content "pubspec.yaml"
# $line = $pubspec | Where-Object { $_ -match "^version:" }
# $currentVersion = ($line -split ":")[1].Trim()

# # Step 2: Split version and build number
# if ($currentVersion -match "^(?<ver>\d+\.\d+\.\d+)(\+(?<build>\d+))?") {
#     $ver = $matches['ver']
#     # Changed $build to $currentBuild to fix the missing variable bug in Step 3
#     $currentBuild = if ($matches['build']) { [int]$matches['build'] } else { 0 }
#     $parts = $ver -split "\."
#     $major = $parts[0]
#     $minor = $parts[1]
#     $patch = [int]$parts[2]
# } else {
#     throw "Could not parse version string: $currentVersion"
# }

# # Step 3: Decide new version
# if (-not [string]::IsNullOrWhiteSpace($Version)) {
#     if ($Version -match "^(?<ver>\d+\.\d+\.\d+)(\+(?<build>\d+))?$") {
#         $targetVer = $matches['ver']
#         $targetBuild = if ($matches['build']) { [int]$matches['build'] } else { $currentBuild }
#         $newVersion = "$targetVer+$targetBuild"
#     } else {
#         throw "Invalid -v value. Use x.y.z or x.y.z+build (e.g., 3.7.0 or 3.7.0+2)."
#     }
# } else {
#     $patch = $patch + 1
#     $newVersion = "$major.$minor.$patch+$currentBuild"
# }

# # force ver 4.0.0
# $newVersion = "4.0.0+$currentBuild"

# # --- NEW STEP: Write new version to pubspec.yaml ---
# Write-Host "Bumping version from $currentVersion to $newVersion in pubspec.yaml..."
# $pubspecContent = Get-Content "pubspec.yaml"
# $pubspecContent = $pubspecContent | ForEach-Object {
#     if ($_ -match "^version:") {
#         "version: $newVersion"
#     } else {
#         $_
#     }
# }
# # Explicitly use UTF8 encoding to prevent formatting issues in pubspec
# Set-Content -Path "pubspec.yaml" -Value $pubspecContent -Encoding UTF8
# # ---------------------------------------------------

# # Step 4: Git operations
# git add .
# if ($commitMessage -ne "") {
#     git commit -m "$commitMessage"
# } else {
#     git commit -m "Bump version to $newVersion"
# }
# git checkout -b "release/v$newVersion"
# git push -u origin "release/v$newVersion"

# # Step 5: Build APK
# flutter build apk --target-platform android-arm64 --analyze-size

# # Step 6: Rename APK
# $apkSource = "C:\Users\USER\code\bsat-flutter\build\app\outputs\flutter-apk\app-release.apk"
# $apkDest = "C:\Users\USER\code\bsat-flutter\build\app\outputs\flutter-apk\bsat.Nitro.$newVersion.apk"
# if (Test-Path $apkSource) {
#     Rename-Item -Path $apkSource -NewName ("bsat.Nitro.$newVersion.apk")
#     Write-Host "APK renamed to bsat.Nitro.$newVersion.apk"
# } else {
#     Write-Host "APK not found at $apkSource" -ForegroundColor Red
# }
 
# Write-Host "Version bumped to $newVersion and pushed to git." -ForegroundColor Green






###################
#
# --- VESION 2 ----
#
###################






param(
    [string]$commitMessage = "",
    [Alias('v')][string]$Version = ""
)

# Step 1: Read current version
$pubspec = Get-Content "pubspec.yaml"
$line = $pubspec | Where-Object { $_ -match "^version:" }
$currentVersion = ($line -split ":")[1].Trim()

# Step 2: Split version and build number
if ($currentVersion -match "^(?<ver>\d+\.\d+\.\d+)(\+(?<build>\d+))?") {
    $ver = $matches['ver']
    $currentBuild = if ($matches['build']) { [int]$matches['build'] } else { 0 }
    $parts = $ver -split "\."
    $major = $parts[0]
    $minor = $parts[1]
    $patch = [int]$parts[2]
} else {
    throw "Could not parse version string: $currentVersion"
}

# Step 3: Decide new version
if (-not [string]::IsNullOrWhiteSpace($Version)) {
    if ($Version -match "^(?<ver>\d+\.\d+\.\d+)(\+(?<build>\d+))?$") {
        $targetVer = $matches['ver']
        $targetBuild = if ($matches['build']) { [int]$matches['build'] } else { $currentBuild }
        $newVersion = "$targetVer+$targetBuild"
    } else {
        throw "Invalid -v value. Use x.y.z or x.y.z+build (e.g., 3.7.0 or 3.7.0+2)."
    }
} else {
    $patch = $patch + 1
    $newVersion = "$major.$minor.$patch+$currentBuild"
}

# $newVersion = "4.0.0+$currentBuild"

# Step 4: Write new version to pubspec.yaml
Write-Host "Bumping version from $currentVersion to $newVersion in pubspec.yaml..."
$pubspecContent = Get-Content "pubspec.yaml"
$pubspecContent = $pubspecContent | ForEach-Object {
    if ($_ -match "^version:") {
        "version: $newVersion"
    } else {
        $_
    }
}
Set-Content -Path "pubspec.yaml" -Value $pubspecContent -Encoding UTF8

# Step 5: Git operations
git add .
if ($commitMessage -ne "") {
    git commit -m "$commitMessage"
} else {
    git commit -m "Bump version to $newVersion"
}
git checkout -b "release/v$newVersion"
git push -u origin "release/v$newVersion"

# Step 6: Build APKs (split by architecture)
Write-Host "Building APKs for all architectures..."
# Note: --analyze-size is removed because it works best targeting a single platform.
# --split-per-abi creates separate APKs for arm64-v8a, armeabi-v7a, and x86_64.
flutter build apk --split-per-abi 

# Step 7: Rename all generated APKs
$basePath = "C:\Users\USER\code\bsat-flutter\build\app\outputs\flutter-apk"
$abis = @("arm64-v8a", "armeabi-v7a", "x86_64")

foreach ($abi in $abis) {
    $apkSource = "$basePath\app-$abi-release.apk"
    $newName = "bsat.Nitro.$newVersion-$abi.apk"
    
    if (Test-Path $apkSource) {
        Rename-Item -Path $apkSource -NewName $newName -Force
        Write-Host "APK renamed to $newName" -ForegroundColor Cyan
    } else {
        Write-Host "APK not found at $apkSource" -ForegroundColor Red
    }
}

Write-Host "Version bumped to $newVersion, pushed to git, and all APKs built!" -ForegroundColor Green
