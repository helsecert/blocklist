if ($env:MSI_SECRET) {
    # Use /tmp for module installation (writable in Flex Consumption)
    $modulePath = '/tmp/PSModules'

    # Add to PSModulePath if not already present
    if ($env:PSModulePath -notlike "*$modulePath*") {
        $env:PSModulePath = "$modulePath;$env:PSModulePath"
    }

    # List all required modules here
    $requiredModules = @('Microsoft.Graph.Authentication', 'Microsoft.Graph.Identity.SignIns')

    # Install and import each module
    foreach ($module in $requiredModules) {
        if (-not (Get-Module -ListAvailable -Name $module)) {
            Write-Host "Installing $module to /tmp..."
            Save-Module -Name $module -Path $modulePath -Force -ErrorAction Stop
        }
        $modulePathObj = Get-ChildItem -Path $modulePath -Recurse -Directory | Where-Object { $_.Name -eq $module } | Select-Object -First 1
        if ($modulePathObj) {
            Import-Module $modulePathObj.FullName -ErrorAction Stop
        } else {
            Write-Error "$module module not found in $modulePath"
        }
    }

    # Authenticate to Microsoft Graph if the authentication module is loaded
    if (Get-Module -Name 'Microsoft.Graph.Authentication') {
        Connect-MgGraph -Identity
    }
}