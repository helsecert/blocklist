<#   
.SYNOPSIS
    Download HelseCERT NBP IPv4 Blocklist and uploads to Azure Sentinel watchlist
 
.DESCRIPTION
    Downloads blocklist from HelseCERT NBP and uploads to Azure Sentinel Watchlist for further automations within Azure Sentinel.
 
    Will download file and check if the existing downloaded version matches previous version or not. if it doesnt match, it will upload to Azure Sentinel Watchlist.
 
.NOTES
    Version:       1.2
    Author:        NHNSOC
    Updated date:  2024-02-26
 
    Requirements:
        - Access to HelseCERT NBP Blocklist
        - Installation of "AZ" module
        - App registration with secret authentication
        - App registration with below access rights (recommend custom role with below access)
            - “Microsoft.SecurityInsights/Watchlists/read”
            - “Microsoft.SecurityInsights/Watchlists/write”
            - “Microsoft.SecurityInsights/Watchlists/delete”
 
    Acknowledgements:
        - SysIKT KO for inspiration and initial NBP download code.
        - HelseCERT for providing NBP IP blocklist
 
.PARAMETER transcript
    Determines whether or not to transcript shell output to $env:TEMP.
#>
 
#region REQUIREMENTS ####################################################### - REQUIREMENTS
# Contains list of #requires. see "about_requires" at microsoft documentation
#Requires -Module Az.Accounts
#endregion /REQUIREMENTS ################################################### - /REQUIREMENTS
 
#region PARAMETERS ######################################################### - PARAMETERS
[cmdletbinding()]
param(
    [parameter(Mandatory = $false, HelpMessage = "Determines to transcript shell output to `$env:TEMP or not")]
    [ValidateNotNullOrEmpty()]
    [switch]$transcript
)
#endregion /PARAMETERS ###################################################### - /PARAMETERS
 
#region TRANSCRIPT
if ($transcript -eq $true) {
    #Defines name of script for logging purposes
    $ScriptName = "download_and_upload_blocklist_helsecert"
    $StartTime = get-date -format o
    #Starts transcript of script
    Start-Transcript "$($env:TEMP)\$ScriptName.ps1_log.txt" -Force -Append
    Write-host "-------------------------------------------------------------------" -ForegroundColor cyan
    Write-host "------------------------- Script Start ----------------------------" -ForegroundColor cyan
    Write-host "--- Script started at `'$StartTime`'" -ForegroundColor cyan
}
#endregion /TRANSCRIPT
 
#region VARIABLES ########################################################### - VARIABLES
# Login info to HelseCERT NBP URL
$blocklistapikey = "<NBP_API_Key>" # Password for NBP List access

# HelseCERT NBP Domain
$blocklistdomain = "<NBP_Domain>" # Domain for NBP List access
 
# CSV File destination location
$CsvFilePath = "C:\Blocklist\HelseCERT\Files\HelseCERT_Blocklist_IPv4.csv"
 
# Sentinel tenant information
$subscriptionId = "<din subscription ID>" # Your subscription ID
$resourceGroupName = "<din sentinel ressurs gruppe>" # Your Sentinel resource group
$workspaceName = "<ditt sentinel workspace navn>"  # Your sentinel workspace name
 
# Sentinel API version
$apiVersion = "2023-11-01" # Version of the Sentinel API being used
 
# Authentication information
$tenantId = "<App registration tenant ID>" # Tenant ID where the App Registration exist
$servicePrincipalAppId = "<App Registration Client ID>" # Your App Registration ID
$ServicePrincipalSecret = ConvertTo-SecureString "<App Registration Secret>" -AsPlainText -Force # App registration Secret
 
# Watchlist information
$watchlistAlias = "HelseCERT_Blocklist_IPv4" # Watchlist ALIAS
$CsvHeader = "ipv4" # Header that is added to the list, will also be search key item
$WatchlistDescription = "HelseCERT IP watchlist" # Watchlist Description
#endregion /VARIABLES ####################################################### - /VARIABLES
 
#region FUNCTIONS ########################################################### - FUNCTIONS
function Get-CsvFromHelseCERT {
    param (
        [string]$NBPuser,
        [string]$NBPpass,
        [string]$CsvFilePath
    )
 
    # Ensure the Blocklist location exists
    if (-not (Test-Path $CsvFilePath)) {
        New-Item -Path $CsvFilePath -ItemType File -Force
    }
 
    # Set Parameters for blocklist download from HelseCert
    $url = "https://" + $blocklistdomain + "/v3?apikey=" + $blocklistapikey + "&f=list&t=ipv4&category=phishing"
    $secpasswd = ConvertTo-SecureString $NBPpass -AsPlainText -Force
    $credential = New-Object System.Management.Automation.PSCredential ($NBPuser, $secpasswd)
 
    try {
        # Download blocklist from HelseCERT
        Write-Host "Downloading blocklist..." -ForegroundColor Yellow
        Invoke-WebRequest -Uri $url -Credential $credential -OutFile $CSvFilePath
        Write-Host "Blocklist downloaded to location $($CsvFilePath)" -ForegroundColor Green
    }
    catch {
        Write-Error "An error occurred while trying to request the web resource."
        # Log or output the specific exception message
        $_.Exception.Message
        # Optionally, you can include the error record to get more details
        # $_ | Out-String | Write-Error
        exit
    }
  
}
 
# Function to upload CSV to Sentinel watchlist
function Push-CsvToSentinelWatchlist {
    param (
        [string]$SubscriptionId,
        [string]$ResourceGroupName,
        [string]$WorkspaceName,
        [string]$WatchlistAlias,
        [string]$ApiVersion,
        [string]$CsvFilePath
    )
 
    # Read the CSV content as a string
    $csvContent = Get-Content -Path $CsvFilePath -Raw
 
    # Check if the first line is already a header or not
    $FirstLine = (Get-Content -Path $CsvFilePath | Select-Object -First 1)
    if ($FirstLine -notlike "$CsvHeader*") {
        # Add the header to the raw CSV content.
        # Prepend the header followed by a newline, then add the existing content.
        $csvContentWithHeader = $CsvHeader + "`n" + $csvContent
    } else {
        # If it already contains the header, just use the content as is.
        $csvContentWithHeader = $csvContent
    }
 
    # Define the body of the request
    $body = @{
        properties = @{
            displayName = $WatchlistAlias
            provider = "Powershell Script"
            source = "Local file"
            description = $WatchlistDescription
            itemsSearchKey = $CsvHeader
            watchlistAlias = $WatchlistAlias
            numberOfLinesToSkip = 0  # Assuming the first line of the CSV is the header
            rawContent = $csvContentWithHeader
            contentType = "text/csv"
        }
    }
 
    # Convert to JSON
    $jsonBody = $body | ConvertTo-Json
 
    $azAccessToken = Get-AzAccessToken -ResourceUrl "https://management.azure.com/"
 
    # Set up headers for the REST call
    $headers = @{
        'Content-Type' = 'application/json'
        'Authorization' = "Bearer $($azAccessToken.Token)"
    }
 
    # Set up the URI for the REST call
    $uri = "https://management.azure.com/subscriptions/$($SubscriptionId)/resourceGroups/$($ResourceGroupName)/providers/Microsoft.OperationalInsights/workspaces/$($WorkspaceName)/providers/Microsoft.SecurityInsights/watchlists/$($WatchlistAlias)?api-version=$($ApiVersion)"
 
    try {
        # Authenticate with Azure using your service principal
        # Connect-AzAccount cmdlet will be used before calling this function
 
        # Call the API
        $response = Invoke-RestMethod -Uri $uri -Method Put -Headers $headers -Body $jsonBody -ContentType "application/json"
 
        # Output the response from the server
        return $response
    }
    catch {
        throw $_
        return
    }
}
 
function Remove-SentinelWatchlist {
    param (
        [string]$SubscriptionId,
        [string]$ResourceGroupName,
        [string]$WorkspaceName,
        [string]$WatchlistAlias,
        [string]$ApiVersion
    )
 
    $azAccessToken = Get-AzAccessToken
 
    # Set up headers for the REST call
    $headers = @{
        'Content-Type' = 'application/json'
        'Authorization' = "Bearer $($azAccessToken.Token)"
    }
 
    # Set up the URI for the REST call
    $uri = "https://management.azure.com/subscriptions/$($SubscriptionId)/resourceGroups/$($ResourceGroupName)/providers/Microsoft.OperationalInsights/workspaces/$($WorkspaceName)/providers/Microsoft.SecurityInsights/watchlists/$($WatchlistAlias)?api-version=$($ApiVersion)"
 
    try {
        # Authenticate with Azure using your service principal
        # Connect-AzAccount cmdlet will be used before calling this function
 
        # Call the API
        $response = Invoke-RestMethod -Uri $uri -Method Delete -Headers $headers
 
        # Output the response from the server
        return $response
    }
    catch {
        throw $_
    }
}
#endregion /FUNCTIONS ####################################################### - /FUNCTIONS
 
#region SCRIPT ############################################################## - SCRIPT
# Define temporary file location based on CsvFilePath
$CsvFilePathTemp = $CsvFilePath + ".tmp"
 
# Download HelseCERT NBP IPv4 Blocklist
Write-Host
Get-CsvFromHelseCERT -NBPuser $NBPuser -NBPpass $NBPpass -CsvFilePath $CsvFilePathTemp
 
# Ensure the Blocklist location exists
if (-not (Test-Path $CsvFilePath)) {
    New-Item -Path $CsvFilePath -ItemType File -Force
}
 
# Compute the hashes for the files to compare if there has been an update
$hash1 = Get-FileHash -Path $CsvFilePathTemp -Algorithm SHA256
$hash2 = Get-FileHash -Path $CsvFilePath -Algorithm SHA256
 
# Compare the hash values
write-host "Comparing existing list with new downloaded list"
if ($hash1.Hash -eq $hash2.Hash) {
    Write-Host "The lists match" -ForegroundColor Yellow
    $Newversion = $False
} else {
    Write-Host "The lists do not match. Replacing current list with the new list" -ForegroundColor Green
    Copy-Item -Path $CsvFilePathTemp -Destination $CsvFilePath -Force
    $Newversion = $True
}
 
# Clean up temp file
Remove-Item -Path $CsvFilePathTemp -Force
 
if ($Newversion -eq $True) {
    # Authenticate with Azure using service principal
    Write-Host
 
    # Create a PSCredential object with the service principal ID and the secure string
    $psCredential = New-Object System.Management.Automation.PSCredential ($servicePrincipalAppId, $servicePrincipalSecret)
    Connect-AzAccount -ServicePrincipal -Credential $psCredential -Tenant $tenantId -ErrorAction Stop
 
    Write-Host "Deleting existing watchlist to prevent removed IP's from showing up in list..." -ForegroundColor Yellow
    Remove-SentinelWatchlist -SubscriptionId $subscriptionId -ResourceGroupName $resourceGroupName -WorkspaceName $workspaceName -WatchlistAlias $watchlistAlias -ApiVersion $apiVersion
    Write-Host "Waiting 2 minutes to allow for deletion to complete before uploading new version, ref: (https://github.com/MicrosoftDocs/azure-docs/blob/main/articles/sentinel/watchlists-manage.md)..." -ForegroundColor Yellow
    Start-Sleep -Seconds 120
    Write-Host
 
    # Call the function to upload the watchlist
    Write-Host "Attempting to uploading new file" -ForegroundColor Green
    Push-CsvToSentinelWatchlist -SubscriptionId $subscriptionId -ResourceGroupName $resourceGroupName -WorkspaceName $workspaceName -WatchlistAlias $watchlistAlias -ApiVersion $apiVersion -CsvFilePath $csvFilePath
    Write-Host "Watchlist uploaded successfully" -ForegroundColor Green
} else {
    Write-Host "New version was the same as the old version. Azure upload skipped." -ForegroundColor Yellow
}
#endregion /SCRIPT ########################################################## - /SCRIPT
 
if ($transcript -eq $true) {
    $EndTime = get-date -format o
    Write-Host
    Write-host "--- Script ended at `'$EndTime`'" -ForegroundColor cyan
    Write-host "------------------------- Script Done -----------------------------" -ForegroundColor cyan
    Write-host "-------------------------------------------------------------------" -ForegroundColor cyan
    Write-Host
    Stop-transcript
}
