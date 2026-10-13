if ($env:MSI_SECRET) {
    # Use /tmp for module installation (writable in Flex Consumption)
    $modulePath = '/tmp/PSModules'

    # Add to PSModulePath if not already present
    if ($env:PSModulePath -notlike "*$modulePath*") {
        $env:PSModulePath = "$modulePath;$env:PSModulePath"
        New-Item -Path $modulePath -ItemType Directory
        Write-Host "Creating directory: $modulePath"
    }

    # List all required modules here
    $requiredModules = @('Microsoft.Graph.Authentication', 'Microsoft.Graph.Identity.SignIns')

    # Install all modules before importing any of them.
    foreach ($module in $requiredModules) {
        if (-not (Get-Module -ListAvailable -Name $module)) {
            Write-Host "Installing $module to /tmp..."
            Save-Module -Name $module -Path $modulePath -RequiredVersion '2.40.0' -ErrorAction Stop
        }
    }

    # Import each module
    foreach ($module in $requiredModules) {
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
