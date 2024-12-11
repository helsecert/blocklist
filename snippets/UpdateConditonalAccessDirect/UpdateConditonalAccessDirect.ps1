# We use a require statement to make sure the modules are available before we even try to run the script
#Requires -Modules Microsoft.Graph.Authentication, Microsoft.Graph.Identity.SignIns
Import-Module -Name Microsoft.Graph.Authentication
Import-Module -Name Microsoft.Graph.Identity.SignIns

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

# Try connecting to make sure we can get lists at all
try {
    $Response = Invoke-WebRequest -Uri "$($EnvData.blocklisturi)/v3?apikey=" + $EnvData.blocklistapikey + "&format=list&type=ipv4" -ErrorAction Stop
}
catch {
    $er = $error[0]
    Write-Error "Connection test to blocklist failed"
    if($ErrorScript){
        & $ErrorHandleScriptPath -ErrorMessage "Connection test to blocklist failed" -ErrorObject $er
    }
    Throw "Halting script"
}

# Get the CDIR formatted blocklist
try {
    $Response = Invoke-WebRequest -Uri "$($EnvData.blocklisturi)/v3?format=list_cidr&type=ipv4&type=ipv4cidr" -ErrorAction Stop
}
catch {
    $er = $error[0]
    Write-Error "Unable to download blocklist with query $($ListQuery)"
    if($ErrorScript){
        & $ErrorHandleScriptPath -ErrorMessage "Unable to download blocklist with query $($ListQuery)" -ErrorObject $er
    }
}
# Split the response by newlines
$Blocklist = $Response -split "\n"

# Only update if the list is not empty
if ($Blocklist.count -gt 0) {

    # Create our list of IP-addresses
    # The expected payload is a an array of hashtables
    # First we create a List object. List objects are much more performant in adding an arbitrary amount of lines than using a syntax like $array +=
    $RangeList = [System.Collections.Generic.List[hashtable]]::New()
    # Iterate through the blocklist and add correctly formatted IPv4Cdir objects
    foreach ($Location in $Blocklist) {
        # Guard against empty strings
        if(![string]::IsNullOrWhiteSpace($Location)){
            $RangeList.Add(
            @{
                "@odata.type" = "#microsoft.graph.iPv4CidrRange"
                "CidrAddress" = $Location
            }
            )
        }
    }
    # Create our properties body
    $Properties = @{
        "@odata.type" = "#microsoft.graph.ipNamedLocation"
        isTrusted     = $false
        # Turn our list of hastables to an array
        IpRanges = $RangeList.ToArray()
    }

    # Clear out any previous Graph connection that could exist
    try { Disconnect-MgGraph -ErrorAction SilentlyContinue }catch {}

    # Use try catch finally to cleanly connect and disconnect
    try {
        # Login to graph API
        # Application needs the permissions "Policy.Read.All" and "Policy.ReadWrite.ConditionalAccess"
        Connect-MgGraph -TenantId $EnvData.TenantId -AppId $EnvData.AppId -CertificateThumbprint $CredentialData.CertificateThumbprint -ContextScope "Process" -ErrorAction Stop -NoWelcome
        # Update the IP list
        # The BodyParameter can be either a well formed object that can convert to correct JSON, or a finished JSON object
        Update-MgIdentityConditionalAccessNamedLocation -NamedLocationId $EnvData.namedlocationid -BodyParameter $Properties -ErrorAction Stop
        Write-Host "Updated location list."
    }
    catch {
        $er = $error[0]
        Write-Error "Unable to update Conditonal access named location"
        if($ErrorScript){
            & $ErrorHandleScriptPath -ErrorMessage "Unable to update Conditonal access named location" -ErrorObject $er
        }
    }
    finally{
        # Disconnect from Graph API cleanly
        write-host "Disconnecting from Graph API" -ForegroundColor Green
        $null = Disconnect-MgGraph -ErrorAction SilentlyContinue 
    }
} 

