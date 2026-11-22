$ErrorActionPreference = 'Stop'

$releaseTag = $env:GITHUB_REF_NAME
$prerelease = 'false'
if ($env:GITHUB_EVENT_NAME -eq 'workflow_dispatch') {
    $releaseTag = $env:REQUESTED_TAG
    $prerelease = $env:REQUESTED_PRERELEASE.ToLowerInvariant()
}

$version = Select-String -Path 'pubspec.yaml' -Pattern '^\s*version:\s*(\S+)\s*$' | Select-Object -First 1
if (-not $version) {
    throw 'Could not read version from pubspec.yaml.'
}
$appVersion = ($version.Matches[0].Groups[1].Value -split '\+')[0]
if ($releaseTag -cne "v$appVersion") {
    throw "Tag $releaseTag does not match pubspec version $appVersion. Expected v$appVersion."
}

$notesFile = ".github/release-notes/$releaseTag.md"
$notesPath = if (Test-Path -LiteralPath $notesFile -PathType Leaf) { $notesFile } else { '' }
@(
    "release_tag=$releaseTag"
    "release_title=EasyCopy $appVersion"
    "app_version=$appVersion"
    "prerelease=$prerelease"
    "release_notes_path=$notesPath"
) | Add-Content -LiteralPath $env:GITHUB_OUTPUT -Encoding utf8
