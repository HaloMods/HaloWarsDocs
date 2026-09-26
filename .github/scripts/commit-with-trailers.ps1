#Requires -Version 5.1
[CmdletBinding()]
param(
	[Parameter(Mandatory = $true, Position = 0)]
	[ValidateNotNullOrEmpty()]
	[string] $Summary,

	[Parameter(Position = 1, ValueFromRemainingArguments = $true)]
	[AllowEmptyString()]
	[string[]] $Body = @(),

	[Parameter(Mandatory = $true)]
	[ValidateScript({ $_ -ne [guid]::Empty })]
	[guid] $SessionId,

	[Parameter(Mandatory = $true)]
	[ValidateNotNullOrEmpty()]
	[ValidatePattern('\A[^<>\p{Cc}\p{Zl}\p{Zp}]+\z')]
	[string] $CoAuthorName,

	[Parameter(Mandatory = $true)]
	[ValidatePattern('\A[^\s<>@\p{Cc}]+@[^\s<>@\p{Cc}]+\z')]
	[string] $CoAuthorEmail,

	[Parameter(Mandatory = $true)]
	[ValidatePattern('\A[A-Za-z0-9][A-Za-z0-9-]*\z')]
	[string] $SessionTrailerName,

	[string] $RepoPath,

	[switch] $Amend,

	[switch] $NoVerify,

	[switch] $Preview
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$CoAuthorName = $CoAuthorName.Trim()
if ($CoAuthorName.Length -eq 0) {
	throw "CoAuthorName must not be empty."
}
if ($SessionTrailerName -ieq "Co-authored-by") {
	throw "SessionTrailerName must not be Co-authored-by."
}

$CoAuthorTrailer = "Co-authored-by: $CoAuthorName <$CoAuthorEmail>"
$SessionTrailer = "${SessionTrailerName}: $($SessionId.ToString('D'))"
$sessionTrailerNamePattern = [regex]::Escape($SessionTrailerName)

if ([string]::IsNullOrWhiteSpace($RepoPath)) {
	$RepoPath = Join-Path (Split-Path -Parent $PSCommandPath) "..\.."
}

function Normalize-CommitBody {
	param(
		[string[]] $Lines
	)

	if ($null -eq $Lines -or $Lines.Count -eq 0) {
		return ""
	}

	$text = ($Lines -join "`n") -replace "`r`n", "`n" -replace "`r", "`n"
	return $text.Trim()
}

function Assert-NoCommitTrailers {
	param(
		[string] $Text,
		[string] $FieldName
	)

	if ($Text -match "(?mi)^[ \t]*(Co-authored-by|$sessionTrailerNamePattern)[ \t]*:") {
		throw "$FieldName must not include commit trailers. This script appends the required trailer block."
	}
}

if ($Summary -match "[`r`n]") {
	throw "Summary must be exactly one line."
}

$Summary = $Summary.Trim()
if ([string]::IsNullOrWhiteSpace($Summary)) {
	throw "Summary must not be empty."
}

Assert-NoCommitTrailers $Summary "Summary"

$bodyText = Normalize-CommitBody $Body
Assert-NoCommitTrailers $bodyText "Body"

$messageParts = [System.Collections.Generic.List[string]]::new()
$messageParts.Add($Summary)

if ($bodyText.Length -gt 0) {
	$messageParts.Add("")
	$messageParts.Add($bodyText)
}

$messageParts.Add("")
$messageParts.Add($CoAuthorTrailer)
$messageParts.Add($SessionTrailer)

$commitMessage = $messageParts -join "`n"
$expectedTrailerBlock = "$CoAuthorTrailer`n$SessionTrailer"

if (-not $commitMessage.EndsWith($expectedTrailerBlock, [System.StringComparison]::Ordinal)) {
	throw "Commit message trailer block was not appended correctly."
}

if ($commitMessage -match "(?m)^Co-authored-by:.*\n\s*\n${sessionTrailerNamePattern}:") {
	throw "Commit message trailers must be contiguous with no blank line between them."
}

$repositoryPath = (Resolve-Path -LiteralPath $RepoPath -ErrorAction Stop).Path
$insideWorkTree = (& git -C $repositoryPath rev-parse --is-inside-work-tree).Trim()
if ($LASTEXITCODE -ne 0 -or $insideWorkTree -ne "true") {
	throw "RepoPath is not a Git worktree: $repositoryPath"
}

if ($Preview) {
	$commitMessage
	return
}

$messageFile = New-TemporaryFile
try {
	$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
	[System.IO.File]::WriteAllText($messageFile.FullName, $commitMessage + "`n", $utf8NoBom)

	$gitArgs = @("-C", $repositoryPath, "commit")
	if ($Amend) {
		$gitArgs += "--amend"
	}
	if ($NoVerify) {
		$gitArgs += "--no-verify"
	}
	$gitArgs += @("--file", $messageFile.FullName)

	& git @gitArgs
	if ($LASTEXITCODE -ne 0) {
		throw "git commit failed with exit code $LASTEXITCODE."
	}
}
finally {
	Remove-Item -LiteralPath $messageFile.FullName -Force -ErrorAction SilentlyContinue
}
