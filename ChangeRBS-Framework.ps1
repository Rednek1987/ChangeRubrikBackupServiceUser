[CmdletBinding()]
Param(
    [Parameter(Mandatory=$false,ValueFromPipeline,  #CHANGE
    HelpMessage="This is a comma separated list. You have to define the hostname/FQDN of computers.")]
    [string[]]$HostList = @('gabo-horv-w1'), #CHANGE

    [Parameter(Mandatory=$false)]
    [string]$ConfigFile = 'config.xml'
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
Set-Variable -Name ErrorActionPreference -Value "Continue" -Scope Global -Force

[string]$global:ConfigFile = $ConfigFile
[string]$global:LogFile = "runlog_" + (Get-Date -Format "yyyyMMdd_HHmmss").ToString() + ".log"

#region Reading config file
    Write-Debug "REGION Reading config file"
    $ScriptDirectory = Split-Path -Path $MyInvocation.MyCommand.Definition -Parent
    try {
        Import-Module -Name $ScriptDirectory\modules\HelperFunctions.psd1 -MinimumVersion 1.0.0 -Force 
    }
    catch {
        Write-Error "Error while loading HelperFunctions.psd1!"
        Exit 1
    }

    $ConfigContent = Get-Content -Path $global:ConfigFile
    [xml]$global:Config = $ConfigContent

    Out-Log "########### Starting LOG ###########"
    Out-Log "Status of Preference Variables: $($global:originalVariablePreferences.Keys | ForEach-Object { "   `n`$$($_) = $(Get-Variable -Name $_ -ValueOnly)"})"
    Out-Log "PARAMETER HostList: $($HostList | Out-String)"
    Out-Log "PARAMETER Config file: $($global:ConfigFile)"
    Out-Log "CONFIG: $($global:Config.OuterXml)"
#endregion

#region Preparation and deploy
    Out-Log "REGION Preparation and deploy"
    Out-Log "Deploying the core script ---->" -Severity Host
    $HostList | ForEach-Object {
        $currentHost = $_
        Out-Log "Deploying the core script on $currentHost"
        $session = New-PSSession -ComputerName $currentHost -Credential $(New-Object System.Management.Automation.PSCredential ('pso\gabor.horvath', $(ConvertTo-SecureString 'M1at3tv3sg3c1!' -AsPlainText -Force))) #$(Get-Credential -Message "Please give me the admin credential to deploy the core script!") #CHANGE
        $CreateScriptDirectoryResult = Invoke-Command -Session $session -ScriptBlock {
            Param ($ClientDeployPath)
            if (!(Test-Path -Path $ClientDeployPath)) {
                if (New-Item -Path $ClientDeployPath -ItemType Directory) {
                    return "Directory $ClientDeployPath created"
                } else {
                    return "ERROR: Not able to create the directory $ClientDeployPath!"
                }
            } else {
                return "The directory $ClientDeployPath already exsits."
            }
        } -ArgumentList $global:Config.main.Windows.ClientDeployPath

        if ($CreateScriptDirectoryResult -match "ERROR:") {
            Out-Log "$currentHost : $CreateScriptDirectoryResult" -Severity Error
        } else {
            Out-Log "$currentHost : $CreateScriptDirectoryResult"
        }

        $target = '\\' + $currentHost + '\' + $global:Config.main.Windows.ClientDeployPath -replace ':','$'
        $RobocopyResult = Robocopy.exe .\todeploy $target /mir /r:0 /w:0 /njh /njs
        Out-Log $RobocopyResult -Severity Host

        $RobocopyResult = Robocopy.exe .\modules $target /r:0 /w:0 /njh /njs
        Out-Log $RobocopyResult -Severity Host

        if (!(Test-Path -Path ($target + '\' + $global:Config.main.Windows.CoreScript))) {
            Out-Log "ERROR: The core script doesn't exists: $($target + '\' + $global:Config.main.Windows.CoreScript)" -Severity Error
        }

        Remove-PSSession -Session $session
    }
#endregion

Out-Log "`n`n##########################################################################`n" -Severity Host
Out-Log "Please check the log file $($global:LogFile) to be sure all Windows servers has the core script!`n" -Severity Host
Read-Host -Prompt "Press Enter to continue"

#region Run service user change
    Out-Log "REGION Run service user change"  #TO DO Tesztelni, ha nem sikerült a file-t deploy-olni....
    Out-Log "Starting the core script ---->" -Severity Host
    $HostList | ForEach-Object {
        $currentHost = $_
        Out-Log "$currentHost : Starting the script" -Severity Host
        $session = New-PSSession -ComputerName $currentHost -Credential $(New-Object System.Management.Automation.PSCredential ('pso\gabor.horvath', $(ConvertTo-SecureString 'M1at3tv3sg3c1!' -AsPlainText -Force))) #$(Get-Credential -Message "Please give me the admin credential to deploy the core script!") #CHANGE
        $ScriptStartResult = Invoke-Command -Session $session -ScriptBlock {
            Param ($ClientDeployPath, $CoreScript, $KeyFile, $SecuredCredentialFile, $ScriptFolder)
            Try {
                Invoke-Expression ($ClientDeployPath + "\$CoreScript -KeyFile $KeyFile -SecuredCredentialFile $SecuredCredentialFile -ScriptFolder $ClientDeployPath")
                return "Core script has been successfully started."
            }
            Catch {
                return "ERROR: Core script isn't able to start!"
            }
        } -ArgumentList $global:Config.main.Windows.ClientDeployPath, $global:Config.main.Windows.CoreScript, $global:Config.main.Windows.KeyFile, $global:Config.main.Windows.SecuredCredentialFile
        
        if ($ScriptStartResult -match "ERROR:") {
            Out-Log "$currentHost : $ScriptStartResult" -Severity Error
        } else {
            Out-Log "$currentHost : $ScriptStartResult"
        }
        
        Remove-PSSession -Session $session
    }
#endregion

#region Collecting core logs
    Out-Log "REGION Collecting core logs"
    Out-Log "Collection core logs" -Severity Host
    Remove-Item LOGS\*
    $HostList | ForEach-Object {
        $currentHost = $_
        $source = '\\' + $currentHost + '\' + $global:Config.main.Windows.ClientDeployPath -replace ':','$'
        $RobocopyResult = Robocopy.exe $source .\LOGS 'corelog_*' /r:0 /w:0 /njh /njs
        Out-Log $RobocopyResult -Severity Host
    }

    Out-Log "Summary: " -Severity Host
    Out-Log "Number of hosts: $($HostList.Count)" -Severity Host
    Out-Log "Number of collected logs: $((Get-ChildItem -Path LOGS).Count)" -Severity Host
    Out-Log "`nError exit statuses:" -Severity Host
    Out-Log "`n$((Get-ChildItem -Path LOGS | Get-Content -Last 1) -notlike "Exit code: 0")" -Severity Host
#endregion

Exit-Program