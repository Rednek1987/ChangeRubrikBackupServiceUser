<#
.SYNOPSIS
    This script generates an encrypted credentials.

.DESCRIPTION

.PARAMETER KeyFile
   This file is the salt for the encryption mechanism. Default value: AES.key

.PARAMETER NewKeyRequired
    Switch parameter. If the parameter is given than a new key fil will be generate. Attention! It overwrites the existing key!

.PARAMETER NewSecuredCredentialFile
    The encrypted password file. Default parameter: SecCred.txt

.PARAMETER UserName
    User name

.PARAMETER Password
    Password

.NOTES
    Author: Gabor Horvath - Senior Consultant
    Email: gabor.horvath@rubrik.com
    Copyright: Rubrik Inc.
#>

Param(
    [Parameter(Mandatory=$false,
    HelpMessage="This file is the salt for the encryption mechanism. Default value: AES.key")]
    [string]$KeyFile = "AES.key",

    [Parameter(Mandatory=$false,
    HelpMessage="Switch parameter. If the parameter is given than a new key fil will be generate. Attention! It overwrites the existing key!")]
    [switch]$NewKeyRequired,

    [Parameter(Mandatory=$false,
    HelpMessage="The encrypted password file. Default parameter: SecCred.txt")]
    [string]$NewSecuredCredentialFile = "SecCred.txt",

    [Parameter(Mandatory=$true,
    HelpMessage="User name")]
    [ValidateNotNullOrEmpty()]
    [string]$UserName,

    [Parameter(Mandatory=$true,
    HelpMessage="Password")]
    [ValidateNotNullOrEmpty()]
    [Security.SecureString]$Password
)

if ($NewKeyRequired) {
    $Key = New-Object Byte[] 32
    [Security.Cryptography.RNGCryptoServiceProvider]::Create().GetBytes($Key)
    $Key | Out-File $KeyFile
} else {
    $Key = Get-Content $KeyFile
}

$null | Out-File $NewSecuredCredentialFile

$UserNamehash = ConvertTo-SecureString $UserName -AsPlainText -Force
@($UserNamehash, $Password) | ForEach-Object {
    $hashwithkey = $_ | ConvertFrom-SecureString -Key $Key
    $hashwithkey | Out-File $NewSecuredCredentialFile -Append
}