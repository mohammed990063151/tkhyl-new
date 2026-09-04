# Deploy / test SSH for tkhyl-new (same flow as eliteplussa-: rsync over SSH, no git pull)
param(
    [switch]$Test,
    [string]$EnvFile = ".deploy.env"
)

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

function Read-DeployEnv([string]$path) {
    if (-not (Test-Path $path)) {
        throw "Missing $path - copy .deploy.env.example to .deploy.env and fill values."
    }
    $map = @{}
    Get-Content $path | ForEach-Object {
        $line = $_.Trim()
        if ($line -eq "" -or $line.StartsWith("#")) { return }
        $i = $line.IndexOf("=")
        if ($i -lt 1) { return }
        $map[$line.Substring(0, $i).Trim()] = $line.Substring($i + 1).Trim()
    }
    return $map
}

$cfg = Read-DeployEnv $EnvFile
$hostName = $cfg["SSH_HOST"]
$user = $cfg["SSH_USERNAME"]
$port = if ($cfg["SSH_PORT"]) { $cfg["SSH_PORT"] } else { "65002" }
$remotePath = if ($cfg["SSH_PATH"]) { $cfg["SSH_PATH"] } else { "domains/tkhyl-ai.com/public_html/" }
$key = if ($cfg["SSH_KEY"]) { $cfg["SSH_KEY"] } else { "github-deploy" }

if (-not $hostName -or -not $user) {
    throw "SSH_HOST and SSH_USERNAME are required in $EnvFile"
}
if (-not (Test-Path $key)) {
    throw "SSH key not found: $key"
}

$keyFull = (Resolve-Path $key).Path

$sshTarget = "{0}@{1}" -f $user, $hostName
$sshBase = @(
    "-i", $keyFull,
    "-p", $port,
    "-o", "IdentitiesOnly=yes",
    "-o", "StrictHostKeyChecking=accept-new",
    "-o", "ConnectTimeout=20",
    $sshTarget
)

Write-Host ("Target: {0}:{1} -> {2}" -f $sshTarget, $port, $remotePath)

if ($Test) {
    Write-Host "Testing SSH..."
    $remoteTest = "echo OK; hostname; pwd; ls -ld $remotePath"
    & ssh @sshBase $remoteTest
    if ($LASTEXITCODE -ne 0) { throw "SSH connection failed (exit $LASTEXITCODE)" }
    Write-Host "Connection OK."
    exit 0
}

$rsyncCmd = Get-Command rsync -ErrorAction SilentlyContinue
$rsyncPath = $null
if ($rsyncCmd) {
    $rsyncPath = $rsyncCmd.Source
} elseif (Test-Path "C:\Program Files\Git\usr\bin\rsync.exe") {
    $rsyncPath = "C:\Program Files\Git\usr\bin\rsync.exe"
}

if (-not $rsyncPath) {
    Write-Host "rsync not found - using tar+ssh sync (no --delete)."
    $excludeArgs = @(
        "--exclude=.git",
        "--exclude=.github",
        "--exclude=node_modules",
        "--exclude=.env",
        "--exclude=.deploy.env",
        "--exclude=github-deploy",
        "--exclude=github-deploy.pub",
        "--exclude=hisan.zip",
        "--exclude=mo",
        "--exclude=tests",
        "--exclude=.phpunit.result.cache"
    )
    $remoteCmd = "mkdir -p $remotePath; tar -xzf - -C $remotePath"
    Write-Host "Uploading via tar over SSH..."
    $tarProc = Start-Process -FilePath "tar" -ArgumentList (@("-czf", "-") + $excludeArgs + @(".")) -NoNewWindow -PassThru -RedirectStandardOutput ".\.deploy-out.tar.gz"
    Wait-Process -InputObject $tarProc
    if ($tarProc.ExitCode -ne 0) { throw "tar failed" }
    Get-Content ".\.deploy-out.tar.gz" -AsByteStream | & ssh @sshBase $remoteCmd
    Remove-Item ".\.deploy-out.tar.gz" -Force -ErrorAction SilentlyContinue
    if ($LASTEXITCODE -ne 0) { throw "Deploy failed (exit $LASTEXITCODE)" }
} else {
    $sshCmd = "ssh -i `"$keyFull`" -p $port -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=20"
    $dest = "{0}:{1}" -f $sshTarget, $remotePath
    $rsyncArgs = @(
        "-avz", "--checksum",
        "-e", $sshCmd,
        "--exclude=.git/",
        "--exclude=.github/",
        "--exclude=node_modules/",
        "--exclude=.env",
        "--exclude=.env.*",
        "--exclude=.deploy.env",
        "--exclude=github-deploy",
        "--exclude=github-deploy.pub",
        "--exclude=hisan.zip",
        "--exclude=mo/",
        "--exclude=tests/",
        "--exclude=storage/logs/*",
        "--exclude=storage/framework/cache/*",
        "--exclude=storage/framework/sessions/*",
        "--exclude=storage/framework/views/*",
        "./",
        $dest
    )
    Write-Host "Uploading via rsync..."
    & $rsyncPath @rsyncArgs
    if ($LASTEXITCODE -ne 0) { throw "rsync failed (exit $LASTEXITCODE)" }
}

Write-Host "Post-deploy artisan cache..."
$artisanCmd = "cd $remotePath; php artisan optimize:clear; php artisan config:cache"
& ssh @sshBase $artisanCmd
Write-Host "Deploy finished."
