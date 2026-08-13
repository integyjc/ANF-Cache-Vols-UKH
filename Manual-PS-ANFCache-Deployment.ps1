# ===========================================================================================
# AUTHENTICATION & MODULE VALIDATION
# ===========================================================================================

# Connect to Azure Account
# Replace with your Tenant ID (GUID)
Connect-AzAccount -Tenant "9134ca48-663d-4a05-968a-31a42f0aed3e" 

# Set the subscription context
# Replace with your Subscription ID (GUID)
Set-AzContext -SubscriptionId "7188942e-488b-4a44-baff-c2f9aeac8eb5"

# ===========================================================================================
# CONFIGURATION VARIABLES (REPLACE WITH YOUR ENVIRONMENT DETAILS)
# ===========================================================================================

# Azure Subscription ID
$subsId = "7188942e-488b-4a44-baff-c2f9aeac8eb5"

# Hashtable of required parameters
$params = @{
    ResourceGroupName       = "m-file-anf-uksouth-rg"      # e.g. rg-demo
    AccountName             = "m-file-anf-account"         # e.g. anf-west-europe
    PoolName                = "m-file-anf-standard-pool"       # e.g. Flexcache
    Zone                    = "1"                          # Availability Zone
    Size                    = (50 * 1024 * 1024 * 1024)    # Cache size in bytes
    ProtocolType            = "SMB"
    WriteBack               = "Enabled"
    
    # ONTAP Origin Details (on-prem or CVO)
    OriginPeerAddress       = @("10.40.1.193","10.40.1.194","10.40.1.198","10.40.1.199","10.40.1.224","10.40.1.225")                # e.g. 10.0.0.10
    OriginPeerClusterName   = "HNTAPCLUS01"       # e.g. cluster01
    OriginPeerVserverName   = "HCIFSPOC01"                 # e.g. svm_data
    OriginPeerVolumeName    = "POC01"              # e.g. vol1

    Location                = "uksouth"             # e.g. westeurope
    Name                    = "cachepoc02"               # e.g. cache01
    FilePath                = "anfcachepoc02"           # e.g. anfcache
    EncryptionKeySource     = "Microsoft.NetApp"
    ThroughputMibps         = 80 # This throughput value can be adjusted based on your performance requirements. The minimum is 1 MiB/s, this will depend on the service level of the capacity pool and the workload requirements.

    # Networking
    CacheSubnetResourceId   = "/subscriptions/7188942e-488b-4a44-baff-c2f9aeac8eb5/resourceGroups/m-spokeconfig-uksouth-rg/providers/Microsoft.Network/virtualNetworks/fsdclive-uksouth-vnet/subnets/main-subnet"
    PeeringSubnetResourceId = "/subscriptions/7188942e-488b-4a44-baff-c2f9aeac8eb5/resourceGroups/m-spokeconfig-uksouth-rg/providers/Microsoft.Network/virtualNetworks/fsdclive-uksouth-vnet/subnets/main-subnet"
}

# Variables used for polling CacheState
$ResourceGroupName = $params.ResourceGroupName
$AccountName       = $params.AccountName
$PoolName          = $params.PoolName
$CacheName         = $params.Name

# ===========================================================================================
# STEP 1: CREATE CACHE
# ===========================================================================================

Start-Job -ScriptBlock {
    param($params)
    New-AzNetAppFilesCache @params
} -ArgumentList $params | Out-Null

# ===========================================================================================
# STEP 2: POLL FOR CLUSTER PEERING STATE
# ===========================================================================================

do {
    $state = (Get-AnfCache -ResourceGroupName $ResourceGroupName `
                          -AccountName $AccountName `
                          -PoolName $PoolName `
                          -Name $CacheName).CacheState

    Write-Host "Current CacheState: $state"
    Start-Sleep -Seconds 10

} until ($state -eq "ClusterPeeringOfferSent")

Write-Host "Proceed to cluster peering"

# ===========================================================================================
# STEP 3: RETRIEVE CLUSTER PEERING DETAILS
# ===========================================================================================

Get-AnfCachePeeringPassphrase -ResourceGroupName $ResourceGroupName `
    -CacheName $CacheName `
    -AccountName $AccountName `
    -PoolName $PoolName |
    Select-Object ClusterPeeringCommand, ClusterPeeringPassphrase

# Action guide
Write-Host "1. SSH to the ONTAP cluster" -ForegroundColor Yellow
Write-Host "2. Execute the ClusterPeeringCommand displayed above" -ForegroundColor Yellow
Write-Host "3. Enter the ClusterPeeringPassphrase when prompted" -ForegroundColor Yellow
Write-Host "4. Verify with: cluster peer show" -ForegroundColor Yellow

# ===========================================================================================
# STEP 4: VERIFY NEXT STATE
# ===========================================================================================

Get-AnfCache -ResourceGroupName $ResourceGroupName `
    -AccountName $AccountName `
    -PoolName $PoolName `
    -Name $CacheName

# ===========================================================================================
# STEP 5: RETRIEVE VSERVER PEERING COMMAND
# ===========================================================================================

Get-AnfCachePeeringPassphrase -ResourceGroupName $ResourceGroupName `
    -CacheName $CacheName `
    -AccountName $AccountName `
    -PoolName $PoolName |
    Select-Object VserverPeeringCommand

# ===========================================================================================
# STEP 6: VALIDATE CACHE READY STATE
# ===========================================================================================

$cache = Get-AnfCache -ResourceGroupName $ResourceGroupName `
                     -AccountName $AccountName `
                     -PoolName $PoolName `
                     -Name $CacheName

$cache.MountTargets | Select-Object IPAddress, SmbServerFqdn

# SMB Share name (used for mounting)
$cache.FilePath
