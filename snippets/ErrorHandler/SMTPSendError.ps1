param(
    [parameter(Mandatory)]
    [string]$ErrorMessage,
    [System.Management.Automation.ErrorRecord]$ErrorObject
)

$HandleErrorObject = $false
if($null -ne $ErrorObject){
    $HandleErrorObject = $true
}

# Simple wrapped function to set a consistent enviroment based on an .env file and .env.secret file in the local directory
function GetEnvData {
    param(
        # Error handler is assumed to accept a [string] object on the parameter -ErrorMessage and a [System.Management.Automation.ErrorRecord] on the parameter -ErrorObject
        $ErrorHandlerScript = "..\ErrorHandler\SMTPSendError.ps1"
    )
    # Set the $WorkDirectory to the Script scope and set it to the location of the running script
    # Technically you could use $PSScriptRoot directly, but doing it this way is reliable when you debug (becuse $WorkDirectory is populated, but $PSScriptRoot is only populated when a script is actually run)
    $script:WorkDirectory = $PSScriptRoot

    # Set our location to the work directory
    Push-Location $WorkDirectory
    # Get the .env file paths
    $EnvFilePath = (Join-Path $WorkDirectory ".env")
    $CredentialFilePath = (Join-Path $WorkDirectory ".env.credential")
    # Try and process the env files as StringData
    # We expect both .env and .env.credential to exist and be parsable as StringData
    # But they strictly don't need to contain any actual data
    try {
        $script:EnvData = Get-Content -Path $EnvFilePath -Encoding UTF8 -ErrorAction Stop | ConvertFrom-StringData -ErrorAction Stop
        $script:CredentialData = Get-Content -Path $CredentialFilePath -Encoding UTF8 -ErrorAction Stop | ConvertFrom-StringData -ErrorAction Stop
    }
    catch {
        $er = $error[0]
        $er
        Throw "Unable to get data from an .env file, halting script"
    }
    # Define the external error handler if it exists
    $script:ErrorScript = $false
    try {
        $script:ErrorHandleScriptPath = (Resolve-Path $ErrorHandlerScript -ErrorAction Stop).Path
        $script:ErrorScript = $true
    }
    catch {
        Write-Warning "Unable to resolve the path for the error handler script, errors will only be printed to console"
    }

    Pop-Location
}
# Call our Env Data function
GetEnvData

# Construct a mail parameter object to use with splatting on the Send-MailMessage cmdlet
$MailMessageConstruct = @{
    SmtpServer = $EnvData.smtpserver 
    From = $EnvData.smtpfrom 
    To = $EnvData.smtpto
    Subject = "Script on $env:COMPUTERNAME reported error: $ErrorMessage"
    # We do a bit extra in the body to print out relevant parts of the error object
    # Technically we could convert the exception to for example JSON to get even more details out directly
    # But the exception object may contain credential info if you go deep enough into the command evaluations.
    Body = @"
A script on $env:COMPUTERNAME has reported the following error message:
$ErrorMessage

## Error object data:
## ScriptStackTrace:
$(($ErrorObject.ScriptStackTrace | Out-String).Trim())

## InvocationInfo:
$(($ErrorObject.InvocationInfo  | Out-String).Trim())

## FullyQualifiedErrorId:
$(($ErrorObject.FullyQualifiedErrorId | Out-String).Trim())

## CategoryInfo:
$(($ErrorObject.CategoryInfo | Out-String).Trim())

## Exception:
$(($ErrorObject.Exception | Out-String).Trim())

# End of message
"@
}

# Add credentials if they are not null/empty
if(![string]::IsNullOrWhiteSpace($CredentialData.smtpuser) -and ![string]::IsNullOrWhiteSpace($CredentialData.password) ){
    $MailMessageConstruct.Add("Credential",([System.Management.Automation.PSCredential]::New($CredentialData.smtpuser, (ConvertTo-SecureString $CredentialData.password -AsPlainText -Force))))
}

# Send our mail object
Send-MailMessage @MailMessageConstruct 
