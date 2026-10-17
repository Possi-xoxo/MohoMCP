[CmdletBinding()]
param(
 [ValidateSet('Prepare','Preview','Install','Update','Verify','Rollback','Uninstall')][string]$Action='Preview',
 [string]$Profile,[string]$Package,[string]$Backup,[string]$Output
)
$ErrorActionPreference='Stop'
$node=(Get-Command node -ErrorAction Stop).Source
$deployArgs=@((Join-Path $PSScriptRoot 'scripts/deploy-cli.mjs'),$Action)
if($Profile){$deployArgs+=@('--profile',$Profile)}
if($Package){$deployArgs+=@('--package',$Package)}
if($Backup){$deployArgs+=@('--backup',$Backup)}
if($Output){$deployArgs+=@('--output',$Output)}
& $node @deployArgs
if($LASTEXITCODE -ne 0){throw "Deployment command failed ($LASTEXITCODE). Check the journal before retrying."}
