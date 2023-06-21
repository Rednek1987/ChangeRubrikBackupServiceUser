[CmdletBinding()]
Param(
    [Parameter(Mandatory=$false)]
    [string]$KeyFile = 'AES.key',

    [Parameter(Mandatory=$false)]
    [string]$SecuredCredentialFile = 'SecCred.txt',

    [Parameter(Mandatory=$false)]
    $ScriptFolder = "C:\Script\RBSServiceUserChange"
)

Write-Debug "Start (after parameter definition)"

$global:originalVariablePreferences = @{"DebugPreference" = $DebugPreference;
                                        "InformationPreference" = $InformationPreference;
                                        "WarningPreference" = $WarningPreference;
                                        "ErrorActionPreference" = $ErrorActionPreference
                                       }

Set-Variable -Name DebugPreference -Value "Continue" -Scope Global -Force   #CHANGE
Set-Variable -Name InformationPreference -Value "Continue" -Scope Global -Force
Set-Variable -Name WarningPreference -Value "Continue" -Scope Global -Force
Set-Variable -Name ErrorActionPreference -Value "Stop" -Scope Global -Force

$Exitcode = 0

#region Importing module
    Write-Debug "REGION Importing module"
    Set-Location -Path $ScriptFolder
    $ScriptDirectory = Split-Path -Path $MyInvocation.MyCommand.Definition -Parent
    [string]$global:LogFile = $ScriptDirectory + "\corelog_$($env:computername)_" + (Get-Date -Format "yyyyMMdd_HHmmss").ToString() + ".log"
    try {
        Import-Module -Name $ScriptDirectory\HelperFunctions.psd1 -MinimumVersion 1.0.0 -Force 
    }
    catch {
        Write-Error "Error while loading HelperFunctions.psd1!"
        Exit 1
    }

    Out-Log "########### Starting LOG ###########"
    Out-Log "PARAMETER KeyFile: $KeyFile"
    Out-Log "PARAMETER SecuredCredentialFile: $SecuredCredentialFile"
#endregion

#region User change
    Out-Log "REGION User change"
    Out-Log "Checking Rubrik Backup Service..."
    if ($svc_Obj= Get-WmiObject Win32_Service -filter "name='Rubrik Backup Service'") {
        Out-Log "Stopping Rubrik Backup Service" -Severity Host
        $StopStatus = $svc_Obj.StopService() 
        if ($StopStatus.ReturnValue -eq "0") {
            Out-Log "Rubrik Backup Service Stopped successfully" -Severity Host
        } else {
            Out-Log "Failed to Stop Rubrik Backup Service. Error code: $($StopStatus.ReturnValue)" -Severity Error
            Exit-Program -Exitcode $StopStatus.ReturnValue
        }

        Start-Sleep -Seconds 2

        $ServiceCredential = Get-SecuredCredential -KeyFile $KeyFile -SecuredCredentialFile $SecuredCredentialFile
        $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($ServiceCredential.Password)
        $Password = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
        Out-Log "Changing service user..." -Severity Host
        $ChangeStatus = $svc_Obj.change($null,$null,$null,$null,$null,$null, $ServiceCredential.UserName,$Password,$null,$null,$null)
        
        if ($ChangeStatus.ReturnValue -eq "0")  {
            Out-Log "Log on account updated sucessfully for Rubrik Backup Service" -Severity Host
        } else {
            Out-Log "Failed to update service account in Rubrik Backup Service. Error code: $($ChangeStatus.ReturnValue)" -Severity Error
            Exit-Program -Exitcode $ChangeStatus.ReturnValue
        }

        $StartStatus = $svc_Obj.StartService()
        if ($StartStatus.ReturnValue -eq "0")  {
            Out-Log "Rubrik Backup Service Started successfully" -Severity Host
        } else {
            Out-Log "Failed to Start Rubrik Backup Service. Error code: $($StartStatus.ReturnValue)" -Severity Error
            Exit-Program -Exitcode $StartStatus.ReturnValue
        }
    } else {
        Out-Log "Rubrik Backup Service not present." -Severity Warning
        $Exitcode = 2
    }
#endregion

Exit-Program -Exitcode $Exitcode