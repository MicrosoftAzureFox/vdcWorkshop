﻿#
# Azure Virtual WAN Workshop
#
# Use your corporate credentials to login (your @microsoft.com account) to Azure
#
#
# Step 1 Create a vWAN, a vWAN Hub, and vWAN VPN Gateway
# Step 2 Create a NetFoundry Virtual Appliance
# Step 3 Create a Cisco CSR Virtual Appliance
# Step 4 Connect the two Azure VNets to the vWAN Hub
# Step 5 Configure and Connect Site 1 (NetFoundry) using the partner experience
# Step 6 Configure and Connect Site 2 (Cisco) using manual VPN provisioning
# (Not included in workshop) Step 7 Configure and Connect Client01, a Point-to-Site manual VPN connection
# (Not included in workshop) Step 8 Configure and Connect ExpressRoute to vWAN Hub
# 

# Step 5 Configure and Connect Site 1 (NetFoundry) using the partner experience
# 5.1 Validate and Initialize
# 5.2 Notifiy student of NetFoundry onboarding process
# 5.3 Configure the NetFoundry device
# 5.3.1 Get NetFoundry OAuth Token and build common header
# 5.3.2 Get NetworkID
# 5.3.3 Get DataCenterID
# 5.3.4 Create NetFoundry Endpoint
# 5.3.4.1 Check if Endpoint exists
# 5.3.4.2 Create if Endpoint doesn't exist
# 5.3.5 Create NetFoundry Gateway
# 5.3.5.1 Check if Gateway exists
# 5.3.5.2 Create if Gateway doesn't exist
# 5.3.5.3 Deploy Az vWAN Site
# 5.4 Associate Site 01 to the vWAN hub
# 5.5 Instructions to register NetFoundry NVA device
#

# 5.1 Validate and Initialize
# Az Module Test
$ModCheck = Get-Module Az.Network -ListAvailable
If ($Null -eq $ModCheck) {
    Write-Warning "The Az PowerShell module was not found. This script uses the Az modules for PowerShell"
    Write-Warning "See the blob post for more information at: https://azure.microsoft.com/blog/how-to-migrate-from-azurerm-to-az-in-azure-powershell/"
    Return
    }

# Load Initialization Variables
$ScriptDir = Split-Path $script:MyInvocation.MyCommand.Path
If (Test-Path -Path $ScriptDir\init.txt) {
        Get-Content $ScriptDir\init.txt | Foreach-Object{
        $var = $_.Split('=')
        Try {New-Variable -Name $var[0].Trim() -Value $var[1].Trim() -ErrorAction Stop}
        Catch {Set-Variable -Name $var[0].Trim() -Value $var[1].Trim()}}}
Else {Write-Warning "init.txt file not found, please change to the directory where these scripts reside ($ScriptDir) and ensure this file is present.";Return}

# Non-configurable Variable Initialization (ie don't modify these)
$ShortRegion = "westus2"
$kvName = "Company" + $CompanyID + "-kv"
$hubRGName = "Company" + $CompanyID + "-Hub01"
$hubNameStub = "C" + $CompanyID + "-vWAN01"
$hubName = $hubNameStub + "-Hub01"
$site01RGName = "Company" + $CompanyID + "-Site01"
$site01NameStub = "C" + $CompanyID + "-Site01"
$site01VNetName = $site01NameStub + "-VNet01"
$site01BGPASN = "65001"
$site01BGPIP = "10.17." + $CompanyID +".133"

# Start nicely
Write-Host
Write-Host (Get-Date)' - ' -NoNewline
Write-Host "Starting step 5, estimated total time 5 minutes" -ForegroundColor Cyan

# Login and permissions check
Write-Host (Get-Date)' - ' -NoNewline
Write-Host "Checking login and permissions" -ForegroundColor Cyan
Try {Get-AzResourceGroup -Name $hubRGName -ErrorAction Stop | Out-Null}
Catch {# Login and set subscription for ARM
       Write-Host "Logging in to ARM"
       Try {$Sub = (Set-AzContext -Subscription $SubID -ErrorAction Stop).Subscription}
       Catch {Connect-AzAccount | Out-Null
              $Sub = (Set-AzContext -Subscription $SubID -ErrorAction Stop).Subscription}
       Write-Host "Current Sub:",$Sub.Name,"(",$Sub.Id,")"
       Try {Get-AzResourceGroup -Name $hubRGName -ErrorAction Stop | Out-Null}
       Catch {Write-Warning "Permission check failed, ensure company id is set correctly!"
              Return}
}

# Initialize vWAN, Hub gateway variables and check for Site01
Try {$wan=Get-AzVirtualWan -ResourceGroupName $hubRGName -Name $hubNameStub}
Catch {Write-Warning "vWAN wasn't found, please run step 1 before running this script"
       Return}

Try {$hubgw=Get-AzVpnGateway -ResourceGroupName $hubRGName -Name $hubName'-gw-vpn' -ErrorAction Stop}
Catch {Write-Warning "Hub gateway wasn't found, please run step 1 before running this script"
       Return}

Try {Get-AzVirtualNetwork -ResourceGroupName $site01RGName -Name $site01VNetName -ErrorAction Stop | Out-Null}
Catch {Write-Warning "Site 1 wasn't found, please run step 0 before running this script"
       Return}

Try {$ipRemotePeerSite1=(Get-AzPublicIpAddress -ResourceGroupName $site01RGName -Name $site01NameStub'-Router01-pip' -ErrorAction Stop).IpAddress}
Catch {Write-Warning "Site 1 Router IP wasn't found, please run step 2 before running this script"
       Return}

# Get the NetFoundry Client ID
$NetFoundryClientID = (Get-AzKeyVaultSecret -VaultName $kvName -Name "NetFoundryClientID" -ErrorAction Stop).SecretValueText
If ($null -eq $NetFoundryClientID) {Write-Warning "NetFoundry Client ID not found, please see the instructor"
       Return}

# Get the NetFoundry Secret
$NetFoundrySecret = (Get-AzKeyVaultSecret -VaultName $kvName -Name "NetFoundrySecret" -ErrorAction Stop).SecretValueText
If ($null -eq $NetFoundrySecret) {Write-Warning "NetFoundry Secret not found, please see the instructor"
       Return}

# Get the NetFoundry OrgID
$NetFoundryOrgID = (Get-AzKeyVaultSecret -VaultName $kvName -Name "NetFoundryOrgID" -ErrorAction Stop).SecretValueText
If ($null -eq $NetFoundryOrgID) {Write-Warning "NetFoundry Org ID not found, please see the instructor"
       Return}

# Ensure NetFoundry SP is on the Hub Resource Group
If ($null -eq (Get-AzRoleAssignment -ObjectId "abf6f2a4-d951-438e-8ff7-4f9360d8973b" -RoleDefinitionName "Contributor" -ResourceGroupName $hubRGName)) {
               New-AzRoleAssignment -ObjectId "abf6f2a4-d951-438e-8ff7-4f9360d8973b" -RoleDefinitionName "Contributor" -ResourceGroupName $hubRGName}

# 5.2 Notifiy student of NetFoundry onboarding process
Write-Host
Write-Host "This script does many behind the scenes operations to make the onboarding process quicker and easy."
Write-Host
Write-Host "You can navigate to the below link to see the entire onboarding process for NetFoundry appliances"
Write-Host "https://netfoundry.zendesk.com/hc/en-us/articles/360018137891-Create-and-Manage-Azure-Virtual-WAN-Sites" -ForegroundColor Green
Write-Host
Write-Host

# 5.3 Configure the NetFoundry device
# 5.3.1 Get NetFoundry OAuth Token and build common header
Write-Host (Get-Date)' - ' -NoNewline
Write-Host "Create NetFoundry Endpoint (register applicance with NetFoundry controller)" -ForegroundColor Cyan
Write-Host "  Getting OAuth token"
$TokenURI = "https://netfoundry-staging.auth0.com/oauth/token"
$TokenBody = "{" + 
             "  ""client_id"": ""$NetFoundryClientID""," +
             "  ""client_secret"": ""$NetFoundrySecret""," +
             "  ""audience"": ""https://gateway.staging.netfoundry.io/""," +
             "  ""grant_type"": ""client_credentials""" +
             "}"
$token = Invoke-RestMethod -Method Post -Uri $TokenURI -Body $TokenBody -ContentType application/json

$ConnHeader = @{"Authorization" = "Bearer $($token.access_token)"
                "Cache-Control" = "no-cache"
                "NF-OrganizationId" = "$NetFoundryOrgID"}

# 5.3.2 Create NetFoundry Endpoint
# List Networks
$ConnURI = "https://gateway.staging.netfoundry.io/rest/v1/networks"
$networks = Invoke-RestMethod -Method Get -Uri $ConnURI -Headers $ConnHeader -ContentType "application/json" -ErrorAction Stop

# Get Network ID
$ConnNetURI = ""
Foreach ($network in $networks._embedded.networks) {
       If ($network.Name -eq ("Company" + $CompanyID)) {
           $ConnNetURI = $network._links.Self.href
       }
   }
If ($ConnNetURI -eq "") {Write-Warning "Network was not found at NetFoundry, please contact the instuctor"
       Return}

# 5.3.3 Get Data Center ID (Required for Endpoint Creation) 
$ConnURI = "https://gateway.staging.netfoundry.io/rest/v1/dataCenters/?locationCode=$ShortRegion"
$datacenter = Invoke-RestMethod -Method Get -Uri $ConnURI -Headers $ConnHeader -ContentType "application/json" -ErrorAction Stop
$DataCenterID = $datacenter._links.self.href.split("/")[6]

# 5.3.4 Create NetFoundry Endpoint
# Get Network Endpoints
$ConnURI = $ConnNetURI + "/endpoints"
$endpoints = Invoke-RestMethod -Method Get -Uri $ConnURI -Headers $ConnHeader -ContentType "application/json" -ErrorAction Stop

# 5.3.4.1 Check if Endpoint exists
$EndPointExists = $False
Foreach ($endpoint in $endpoints._embedded.endpoints) {
    If ($endpoint.Name -eq "$site01NameStub-vpn") {
              $response = $endpoints._embedded.endpoints    
              $EndPointExists = $true}
}

# 5.3.4.2 Create if Endpoint doesn't exist
If ($EndPointExists) {Write-Host "  Endpoint already exists, skipping"}
Else {Write-Host "  Submitting endpoint creation request"
      $ConnURI = $ConnNetURI + "/endpoints"
      $ConnBody = "{" + 
                  "  ""name"": ""$site01NameStub-vpn""," +
                  "  ""endpointType"": ""AVWGW""," +
                  "  ""geoRegionId"": null," +
                  "  ""dataCenterId"": ""$DataCenterID""," +
                  "  ""haEndpointType"": null" +
                  "}"
      $response = Invoke-RestMethod -Method Post -Uri $ConnURI -Headers $ConnHeader -ContentType "application/json" -Body $ConnBody -ErrorAction Stop
}
$EndPointID = $response._links.self.href.split("/")[8]
$RegKey = $response.registrationKey

# 5.3.5 Create Az vWAN Site at NetFoundry
# Get Subscriptions
$ConnURI = "https://gateway.staging.netfoundry.io/rest/v1/azureSubscriptions"
$subscriptions = Invoke-RestMethod -Method Get -Uri $ConnURI -Headers $ConnHeader -ContentType "application/json" -ErrorAction Stop
$nfSubscriptionId = $subscriptions._embedded.azureSubscriptions._links.self.href.split("/")[6]

# Get Azure vWAN Sites
$ConnURI = $ConnNetURI + "/virtualWanSites"
$vwansites = Invoke-RestMethod -Method Get -Uri $ConnURI -Headers $ConnHeader -ContentType "application/json" -ErrorAction Stop

# 5.3.5.1 Check if Az vWAN Site at NetFoundry exists
$vWANSiteExists = $False
Foreach ($vwansite in $vwansites._embedded.azureVirtualWanSites) {
    If ($vwansite.name -eq "$site01NameStub-vpn") {
              $response = $vwansite   
              $vWANSiteExists = $true}
}

# 5.3.5.2 Create if Az vWAN Site at NetFoundry doesn't exist
If ($vWANSiteExists) {Write-Host "  Az vWAN Site at NetFoundry already exists, skipping"}
Else {Write-Host "  Submitting Az vWAN Site at NetFoundry creation request"  
      $ConnURI = $ConnNetURI + "/virtualWanSites"
      $ConnBody = "{`n" + 
                  "  ""name"" : ""$site01NameStub-vpn"",`n" +
                  "  ""endpointId"" : ""$EndPointID"",`n" +
                  "  ""dataCenterId"" : ""$DataCenterID"",`n" +
                  "  ""azureSubscriptionId"" : ""$nfSubscriptionId"",`n" +
                  "  ""azureResourceGroupName"" : ""$hubRGName"",`n" +
                  "  ""azureVirtualWanId"" : ""$($wan.Id)"",`n" +
                  "  ""publicIpAddress"" : ""$ipRemotePeerSite1"",`n" +
                  "  ""bgp"" : {`n" +
                  "    ""localPeeringAddress"" : {`n" +
                  "      ""ipAddress"" : ""$site01BGPIP"",`n" +
                  "      ""asn"" : $site01BGPASN`n" +
                  "    }`n" + #,`n" +
                  "  }`n" +
                  "}"
      $response = Invoke-RestMethod -Method Post -Uri $ConnURI -Headers $ConnHeader -ContentType "application/json" -Body $ConnBody -ErrorAction Stop
}
$vWANSiteID = $response._links.self.href

# 5.3.5.3 Deploy Az vWAN Site
$ConnURI = $vWANSiteID + "/deploy"
$response = Invoke-RestMethod -Method Put -Uri $ConnURI -Headers $ConnHeader -ContentType "application/json" -ErrorAction Stop

# 5.4 Associate Site 01 to the vWAN hub
Write-Host (Get-Date)' - ' -NoNewline
Write-Host "Associating Site 01 to the vWAN hub" -ForegroundColor Cyan
Try {Get-AzVpnConnection -ParentObject $hubgw -Name $hubName'-conn-vpn-Site01' -ErrorAction Stop | Out-Null
     Write-Host "  Site 01 association exists, skipping"}
Catch {$vpnSites = Get-AzVpnSite -ResourceGroupName $hubRGName
       Foreach ($Site in $vpnSites ) {
              If ($Site.Name -eq "$site01NameStub-vpn") {$vpnSite1 = $Site}
       }
       New-AzVpnConnection -ParentObject $hubgw -Name $hubName'-conn-vpn-Site01' -VpnSite $vpnSite1 `
                           -EnableBgp -VpnConnectionProtocolType IKEv2 | Out-Null}

# 5.5 Instructions to register NetFoundry NVA device
If ($RegKey -eq "") {Write-Host "  Appliance is already activated, skipping"}
Else {# Set a new alias to access the clipboard
      New-Alias Out-Clipboard $env:SystemRoot\System32\Clip.exe -ErrorAction SilentlyContinue
      $MyOutput = @"
The NetFoundry Appliance needs to be activated.
To do this, open a new PowerShell window (but NOT an ISE window!)
Run the following three commands:
       ssh.exe nfadmin@$ipRemotePeerSite1
       sudo nfnreg -e staging $RegKey
       sudo systemctl status dvn

The first command will open a Shell to the NetFoundry device
The Second command will register the device
The thrid command will show the status of the service on the device and should be "running"
You many now close the command window (type exit twice)
It will take about 15 minutues after the device is registered for the tunnel to come up.
If you want to monitor this from the NetFoundry appliacnce you can run:
       sudo ip xfrm monitor
"@

       $MyOutput | Out-Clipboard
       $MyOutput
}

# End nicely
Write-Host (Get-Date)' - ' -NoNewline
Write-Host "Step 5 completed successfully" -ForegroundColor Green
If ($response.registrationKey -eq "") {
       Write-host "  Trying pinging the remote servers in Azure 01 and Azure 02."
}
Else {
       Write-Host "  Follow the instructions above to configure the NetFoundry device. These instructions have also been copied to the clipboard, you may also open Notepad and paste the instructions for better readability. If you need the instructions again, rerun this script and the instructions will be reloaded to the clipboard."
       Write-host "  Once the NetFoundry device is configured, trying pinging the remote servers in Azure 01 and Azure 02."
}
 Write-Host
