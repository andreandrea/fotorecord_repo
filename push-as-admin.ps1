Param(
    [string]$RemoteUrl = $null,
    [string]$CommitMessage = $("Auto commit: $(Get-Date -Format 'yyyy-MM-dd_HH:mm:ss')"),
    [switch]$Force,
    [switch]$AsAdministrator,
    [string]$Branch = "main"
)

# Ensure script runs from the repository root (script location)
$scriptPath = $MyInvocation.MyCommand.Definition
$repoRoot = Split-Path -Parent $scriptPath
Set-Location $repoRoot

function Is-Elevated {
    $current = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $current.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Relaunch elevated if not running as admin
if (-not (Is-Elevated)) {
    Write-Host "Not running as administrator. Relaunching elevated..."
    $argList = @()
    if ($RemoteUrl) { $argList += "-RemoteUrl '$RemoteUrl'" }
    if ($CommitMessage) { $argList += "-CommitMessage '$CommitMessage'" }
    if ($Force) { $argList += "-Force" }
    if ($AsAdministrator) { $argList += "-AsAdministrator" }
    if ($Branch -and $Branch -ne "main") { $argList += "-Branch '$Branch'" }

    # Build argument string safely
    $argsString = $argList -join ' '

    Start-Process -FilePath powershell -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" $argsString"
    exit
}

# Check git installation
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Error "git non trovato. Installa Git e riprova: https://git-scm.com/downloads"
    exit 1
}

# Initialize repo if needed
if (-not (Test-Path .git)) {
    Write-Host "Repository git non trovato. Inizializzo repository..."
    git init | Out-Null
    # Create the chosen branch if possible
    try {
        git checkout -b $Branch | Out-Null
    } catch {
        # If checkout fails, ignore — later pushes can set upstream
    }
}

# Check for changes
$porcelain = git status --porcelain
if (-not $porcelain) {
    Write-Host "Nessuna modifica da committare. (working tree pulito)"
} else {
    Write-Host "Aggiungo e committo le modifiche..."
    git add -A

    if ($AsAdministrator) {
        $author = "Administrator <admin@localhost>"
        git commit -m "$CommitMessage" --author "$author"
        $commitExit = $LASTEXITCODE
        if ($commitExit -ne 0) {
            Write-Error "git commit failed (exit code $commitExit)."
            exit $commitExit
        }
    } else {
        git commit -m "$CommitMessage"
        $commitExit = $LASTEXITCODE
        if ($commitExit -ne 0) {
            Write-Error "git commit failed (exit code $commitExit)."
            exit $commitExit
        }
    }
}

# Determine remote
$originUrl = $null
try { $originUrl = git remote get-url origin 2>$null } catch { }

if (-not $originUrl) {
    if ($RemoteUrl) {
        Write-Host "Imposto remote 'origin' su: $RemoteUrl"
        git remote add origin $RemoteUrl
        $originUrl = $RemoteUrl
    } else {
        Write-Host "Nessun remote 'origin' configurato."
        Write-Host "Passa l'URL del remote con -RemoteUrl 'https://...'", "oppure crea il repository remoto (es. GitHub) e poi esegui:", "git remote add origin <URL>"
        exit 0
    }
}

# Ensure local branch name
$currentBranch = git rev-parse --abbrev-ref HEAD
if (-not $currentBranch -or $currentBranch -eq "HEAD") {
    # Try to set to requested branch
    try { git checkout -b $Branch | Out-Null; $currentBranch = $Branch } catch { }
}

# Push
Write-Host "Push verso $originUrl (branch: $currentBranch)"

# Build push arguments in a PowerShell-compatible way
$pushArgs = @('push', '-u', 'origin', $currentBranch)
if ($Force) { $pushArgs += '--force' }

# Execute push and stream output
$pushResult = & git @pushArgs
$exitCode = $LASTEXITCODE
if ($exitCode -eq 0) {
    Write-Host "Push avvenuto con successo."
} else {
    Write-Error "Push fallito (exit code $exitCode). Controlla le credenziali/remote e riprova."
    exit $exitCode
}
