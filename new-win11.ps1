[CmdletBinding()]
param ()

$timer = [System.Diagnostics.Stopwatch]::StartNew()
$ErrorActionPreference = "Stop"
$ProgressPreference = 'SilentlyContinue'

$IsAdmin = (New-Object System.Security.Principal.WindowsPrincipal([System.Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $IsAdmin) {
    throw "You need to run this from an elevated pwsh prompt"
}

Write-Host "Setting execution policy" -ForegroundColor Magenta
Set-ExecutionPolicy RemoteSigned

# Windows PowerShell 5.1 = C:\Users\User\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1
# PowerShell 7 = C:\Users\User\Documents\PowerShell\Microsoft.PowerShell_profile.ps1

$PwshProfile = "$HOME\Documents\PowerShell\Microsoft.PowerShell_profile.ps1"

Write-Host "Create PowerShell profile if does not exists" -ForegroundColor Magenta
if (-not (Test-Path $PwshProfile)) {
    New-Item $PwshProfile -ItemType File -Force
    Write-Host "`tPowerShell profile created" -ForegroundColor Magenta
}

Write-Host "Installing WSL stuff and the default 'Ubuntu on Windows' distribution" -ForegroundColor Magenta
wsl --install

Write-Host "Installing apps via winget" -ForegroundColor Magenta
winget import -i .\winget-packages.json --accept-package-agreements --accept-source-agreements --disable-interactivity --verbose

# If you are running this on a VM you might get this error:
# "Error: 0x80370102 The virtual machine could not be started because a required feature is not installed."
# See https://learn.microsoft.com/en-us/windows/wsl/troubleshooting#error-0x80370102-the-virtual-machine-could-not-be-started-because-a-required-feature-is-not-installed
# Basically you need to run this on your host machine Set-VMProcessor -VMName [NameOfMyVM] -ExposeVirtualizationExtensions $true

Write-Progress -Activity "Installing chocolatey"
Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))

Write-Host "`tReloading PowerShell profile" -ForegroundColor Magenta
. $PwshProfile

Write-Progress -Activity "Installing chocolatey packages"
$chocoPackages = @(
    "baretail"
    "smtp4dev"
)
foreach ($package in $chocoPackages) {
    Write-Host "`tInstalling choco package: $package" -ForegroundColor Magenta
    choco install -y $package
    refreshenv
}

Write-Host "Removing pre-loaded Windows 11(22H2) Apps" -ForegroundColor Magenta
$unWantedApps = @(
    "Disney.37853FC22B2CE_6rarf9sa4v8jt"
    "Microsoft.MicrosoftOfficeHub_8wekyb3d8bbwe"
    "Microsoft.MicrosoftSolitaireCollection_8wekyb3d8bbwe"
    "Microsoft.MicrosoftStickyNotes_8wekyb3d8bbwe"
    "Microsoft.Todos_8wekyb3d8bbwe"
    "SpotifyAB.SpotifyMusic_zpdnekdrzrea0"
)
foreach ($unWantedApp in $unWantedApps) {
    winget uninstall --id $unWantedApp
    Write-Host "`tRemoved: '$unWantedApp'" -ForegroundColor Magenta
}

Write-Host "Installing nuget package provider" -ForegroundColor Magenta
Install-PackageProvider -Name NuGet -Force

Write-Host "Ensuring PowerShell Gallery is trusted" -ForegroundColor Magenta
if (-not ((Get-PackageSource -Name "PSGallery").IsTrusted)) {
    $null = Set-PackageSource -Name "PSGallery" -Trusted
}

Write-Host "Installing Powershell modules" -ForegroundColor Magenta
$ModulesToInstall = @(
    "posh-git"
    "Terminal-Icons"
    "DockerCompletion"
)
foreach ($Module in $ModulesToInstall) {
    if ($null -eq (Get-Module -Name $Module -ListAvailable)) {
        Write-Host ("`tInstalling PowerShell Module - {0}" -f $Module) -ForegroundColor Magenta
        $null = Install-Module -Name $Module -Force
    }
    else {
        $InstalledVersion = (Get-Module -Name $Module -ListAvailable)[0].version
        $LatestVersion = (Find-Module -Name $Module)[0].version

        if ($InstalledVersion -lt $LatestVersion) {
            if ($null -eq (Get-Package -Name $Module -ErrorAction SilentlyContinue)) {
                Write-Host ("`tForce Installing PowerShell Module - {0}" -f $Module) -ForegroundColor Magenta
                $null = Install-Module -Name $Module -Force
            }
            else {
                Write-Host ("`tUpdating PowerShell Module - {0}" -f $Module) -ForegroundColor Magenta
                $null = Update-Module -Name $Module -Force
            }
        }
    }
}

Write-Host "Adding contents to PwshProfile" -ForegroundColor Magenta
$Contents = @'
oh-my-posh init pwsh --config "$env:POSH_THEMES_PATH\atomic.omp.json" | Invoke-Expression

Import-Module -Name DockerCompletion
Import-Module -Name Terminal-Icons
Import-Module -Name posh-git

Import-Module -Name PSReadLine
Set-PSReadLineOption -PredictionSource History
Set-PSReadLineOption -PredictionViewStyle ListView
Set-PSReadLineOption -EditMode Windows

Set-Alias -Name "d" -Value "docker"
Set-Alias -Name "k" -Value "kubectl"
'@
Add-Content $PwshProfile $Contents

Write-Host "Setting git aliases" -ForegroundColor Magenta
git config --global alias.co "checkout"
git config --global alias.cob "checkout -b"
git config --global alias.df "diff"
git config --global alias.ec "config --global -e"
git config --global alias.f "fetch origin --prune"
git config --global alias.l "log -n 20 --oneline"
git config --global alias.lga "log --graph --oneline --all --decorate"
git config --global alias.st "status"

Write-Host "Setting VS Code as the Git editor" -ForegroundColor Magenta
git config --global core.editor "code --wait"

git config --global core.fsmonitor=true
git config --global core.autocrlf=true

# https://cscheng.info/2017/01/26/git-tip-autostash-with-git-pull-rebase.html
Write-Host "Setting autostash with git pull --rebase" -ForegroundColor Magenta
git config --global pull.rebase true
git config --global rebase.autoStash true

git config --global push.autoSetupRemote true

$directories = @(
    "c:\repos"
    "c:\temp"
    "c:\games"
)
foreach ($directory in $directories) {
    Write-Host "Creating '$directory' folder" -ForegroundColor Magenta
    if (-not (Test-Path $directory)) {
        New-Item $directory -ItemType Directory
    }
}

Write-Host "Enabling windows features" -ForegroundColor Magenta
$features = @(
    "Microsoft-Hyper-V-All"
    "Containers"
    "HypervisorPlatform"
)
foreach ($feature in $features) {
    Write-Host "`tEnabling windows feature: $feature" -ForegroundColor Magenta
    Enable-WindowsOptionalFeature -Online -NoRestart -FeatureName $feature
}

$DownloadsDir = "$HOME\Downloads"
$CascadiaCodeNerdFontZip = "$DownloadsDir\CascadiaCodeNF.zip"
Invoke-WebRequest -Uri "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/CascadiaCode.zip" -OutFile $CascadiaCodeNerdFontZip
Expand-Archive -Path $CascadiaCodeNerdFontZip -DestinationPath "$DownloadsDir\CascadiaCodeNF" -Force
Write-Host "See 'Downloads folder' and install the fonts manually for now, I only need 'Caskaydia Cove Nerd Font Complete Windows Compatible Regular.otf'"
# Ref: https://github.com/ryanoasis/nerd-fonts/tree/master/patched-fonts/CascadiaCode#which-font

$timer.Stop()
Write-Host ""
Write-Host "Script ran for '$($timer.Elapsed.ToString("hh\:mm\:ss"))' on '$env:COMPUTERNAME'" -ForegroundColor Green
Write-Host "Now do the following:"  -ForegroundColor Yellow
Write-Host "`t1. Reboot."  -ForegroundColor Yellow
Write-Host "`t2. Finalized the installation of WSL distros by running them."  -ForegroundColor Yellow
Write-Host "`t3. Do a windows update."  -ForegroundColor Yellow
Write-Host "`t4. Update apps from Microsoft Store."  -ForegroundColor Yellow
Write-Host ""
Read-Host -Prompt "(*^_^*) All done, press [ENTER] to restart your computer O.O"
Restart-Computer
