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

# Create a credential object we can use to authenticate the web connecton with
$Credential = ([System.Management.Automation.PSCredential]::New($CredentialData.blocklistuser, (ConvertTo-SecureString $CredentialData.blocklistpass -AsPlainText -Force)))

# Try connecting to make sure we can get lists at all so we dont try to do unnesscary work
try {
    $Response = Invoke-WebRequest -Uri "$($EnvData.blocklistdomain)/help" -UseBasicParsing -Credential $Credential -ErrorAction Stop
}
catch {
    $er = $error[0]
    Write-Error "Connection test to blocklist failed"
    if($ErrorScript){
        & $ErrorHandleScriptPath -ErrorMessage "Connection test to blocklist failed" -ErrorObject $er
    }
    Throw "Halting script"
}

# Handle our download location
# First we store the location variable
# This can both be a realtive and explicit path
$TargetDirectory = $EnvData.downloadlocation
# To handle relative paths we step into the $WorkDirectory
Push-Location $WorkDirectory
# Test if $TargetDirectory exists and create if not
if(![System.IO.Directory]::Exists($TargetDirectory)){
    $null = New-Item -Path $TargetDirectory -ItemType Directory -Force
}
# Do a resolve path to make sure we have a full path in the TargetDirectory variable
# Since we are in the working directory this should fully resolve relative paths
$TargetDirectory = (Resolve-Path $TargetDirectory).Path
# Step out of the workdir again
Pop-Location 

# This function will help parse the result of the blocklist
function Parse-Context {
    [CmdletBinding()]
    param (
        # The target is generally the main object of the line, an address or IP-address
        [Parameter(Mandatory)]
        [string]$Target,
        # The context string is the result of using a list query ending on _context
        [string]$ContextString
    )
    # If there is no context string we just return the Target
    if([string]::IsNullOrWhiteSpace($ContextString)){
        return , [PSCustomObject]@{
            Target = $Target.Trim()
        }
    }
    # If we have a context string we split it 8 times (the current known amount of info types)
    $SplitContext = $ContextString -split " ",8
    # Place the context string elements into the right property
    return , [PSCustomObject]@{
        Target = $Target.Trim()
        Timestamp = $SplitContext[0]
        MalwareFamily = $SplitContext[1].Replace("malware_family:","")
        KillChain =  $SplitContext[2].Replace("kill_chain:","")
        FpRate = $SplitContext[3].Replace("fp_rate:","")
        Category = $SplitContext[4].Replace("category:","")
        Confidence = $SplitContext[5].Replace("confidence:","")
        Impact = $SplitContext[6].Replace("impact:","")
        Context = $SplitContext[7].Replace("context:","")
        ContextString = $ContextString
    }
}

# This is the main function to query the blocklist
function Get-Blocklist {
    [CmdletBinding()]
    param (
        # The uri to query for the blocklist at
        # By default we get from the env file
        [string]$BlocklistURI = $EnvData.blocklisturi,
        # The query to use
        # We default to list
        [string]$ListQuery = "f=list",
        # The output file the resulting CSV is saved to
        [Parameter(Mandatory)]
        [string]$TargetFile,
        
        # The credential object used for authentication
        [Parameter(Mandatory)]
        [System.Management.Automation.PSCredential]$BlockListCredential
    )
    # Do our query and report error if it fails
    try {
        $Response = Invoke-WebRequest -Uri "$($BlocklistURI)?$ListQuery" -Credential $BlockListCredential -UseBasicParsing -ErrorAction Stop
    }
    catch {
        $er = $error[0]
        Write-Error "Unable to download blocklist with query $($ListQuery)"
        if($ErrorScript){
            & $ErrorHandleScriptPath -ErrorMessage "Unable to download blocklist with query $($ListQuery)" -ErrorObject $er
        }
    }

    # Process the result
    try {
        # We get the Response content and send it through ConvertFrom-CSV
        # We let the CSV cmdlet do the heavy lifting of cleanly splitting the content stream into lines, we also split by # if there is context information
        $BlocklistResponse = $Response | Select-Object -ExpandProperty Content | convertFrom-csv -Header "Target","Context" -Delimiter "#" -ErrorAction Stop
        # Send our result through the parser an return as an array
        $ParsedResponse = [array]($BlocklistResponse | ForEach-Object {Parse-Context $_.Target $_.Context})
        # Save the result as an utf8 CSV
        $ParsedResponse | Export-Csv -Path $TargetFile -Encoding utf8 -NoTypeInformation -Force
    }
    catch {
        $er = $error[0]
        Write-Error "Unable to convert to CSV blocklist with query $($ListQuery)"
        if($ErrorScript){
            & $ErrorHandleScriptPath -ErrorMessage "Unable to convert to CSV blocklist with query $($ListQuery)" -ErrorObject $er
        }
    }
}

# These are the list we get by default
Get-Blocklist -ListQuery "f=list_context" -TargetFile (Join-Path $TargetDirectory "List.csv") -BlockListCredential $Credential
Get-Blocklist -ListQuery "f=list_cidr" -TargetFile (Join-Path $TargetDirectory "cdirList.csv") -BlockListCredential $Credential
Get-Blocklist -ListQuery "f=list_regex" -TargetFile (Join-Path $TargetDirectory "regexList.csv") -BlockListCredential $Credential