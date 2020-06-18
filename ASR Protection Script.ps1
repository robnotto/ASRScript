Connect-AzAccount
 
#Select Subscription
 $subscription = get-azsubscription | Out-GridView -PassThru -Title "Select the Subscription to work with"
 Select-AzSubscription -Subscription $subscription
 
#Select Source Resource Group
 $ResourceGRoup=Get-azresourcegroup | Out-GridView -PassThru -Title "Select Azure Resource Group to Protect"
 $RG=$ResourceGRoup.ResourceGroupName

 
#Select Recovery Vault
 $vault = get-azrecoveryservicesvault | Out-GridView -PassThru -Title "Select the Vault to work with"
 Set-AzRecoveryServicesAsrVaultContext -Vault $vault
 
#Get Azure ASR Fabric
$fabric=Get-AzRecoveryServicesAsrFabric
$Sourcecontainer = Get-AzRecoveryServicesAsrProtectionContainer -Fabric $fabric[0]
$Targetcontainer = Get-AzRecoveryServicesAsrProtectionContainer -Fabric $fabric[1]
#You can create if it does not exist and assign below
$CacheStorageAccount=Get-AzStorageAccount -Name "kf1wkmasrvaultasrcache" -ResourceGroupName "asrvault"

#Select Existing Azure Site Recovery Policy
 $ASRPolicy=Get-AzRecoveryServicesAsrPolicy | Out-GridView -PassThru -Title "Select Replication Policy to use"

#Select Protection Container Mapping
$Source2TargetMapping=Get-AzRecoveryServicesAsrProtectionContainerMapping -ProtectionContainer $sourcecontainer | Out-GridView -PassThru -Title "Select Source Region"
$Target2SourceMapping=Get-AzRecoveryServicesAsrProtectionContainerMapping -ProtectionContainer $sourcecontainer | Out-GridView -PassThru -Title "Select Target Region"

#Select Target Resources
$TargetRecoveryRG=Get-AzResourceGroup -Name "asrtarget"
$TargetPPG=Get-AzProximityPlacementGroup -ResourceGroupName "ppgeast2" -Name "ppgeast2"
$TargetAvSet=Get-AzAvailabilitySet -ResourceGroupName "asrvault" -name "ASRDEMO-S2D-AS-asr"


#Vm List

$vms=Get-azVm -ResourceGroupName $ResourceGRoup.ResourceGroupName
$VMCount=$vms.Count
$ProtectVMCount=0
 
#Exclude VMs by name

$ExcludeVM="vmname1","vmname2","vmname3"

#Check for Excluded VMs.  
     

Foreach ($vm in $VMs) {


If ($vm.name -notin $ExcludeVM)

{ 
Write-Host "Protecting VM" $vm.Name

#Capture Availability Set
$VMavailabilitySet=$vm.AvailabilitySetReference


 
#Os Disk
$OSdiskId = $vm.StorageProfile.OsDisk.ManagedDisk.Id
$OSDisk = get-azdisk -ResourceGroupName $vm.ResourceGroupName -DiskName $OSdiskId.split('/')[-1]
$RecoveryOSDiskAccountType = $osdisk.sku.name
$RecoveryReplicaDiskAccountType = $osdisk.sku.name

#$RecoveryOSDiskAccountType = $vm.StorageProfile.OsDisk.ManagedDisk.StorageAccountType
#$RecoveryReplicaDiskAccountType = $vm.StorageProfile.OsDisk.ManagedDisk.StorageAccountType
 
$OSDiskReplicationConfig = New-AzRecoveryServicesAsrAzureToAzureDiskReplicationConfig -ManagedDisk -LogStorageAccountId $CacheStorageAccount.id -DiskId $OSdiskId -RecoveryResourceGroupId $TargetRecoveryRG.ResourceId -RecoveryReplicaDiskAccountType $RecoveryReplicaDiskAccountType -RecoveryTargetDiskAccountType $RecoveryOSDiskAccountType
 
#DataDisk

Write-host "Located" $vm.StorageProfile.DataDisks.Count "Data Disks on" $Vm.Name

$datadiskconfigs = @()
 
foreach($datadisk in $vm.StorageProfile.DataDisks)
{
 
    $datadiskId = $datadisk.ManagedDisk.Id
    Write-host $datadiskId "Located as data disk for" $Vm.Name
 
    $DataDiskInfo = get-azdisk -ResourceGroupName $vm.ResourceGroupName -DiskName $datadiskId.split('/')[-1]
    $RecoveryReplicaDiskAccountType = $datadiskinfo.sku.name
    $RecoveryTargetDiskAccountType =  $datadiskinfo.sku.name
  
    $datadiskconfig = New-AzRecoveryServicesAsrAzureToAzureDiskReplicationConfig -ManagedDisk -LogStorageAccountId $CacheStorageAccount.Id -DiskId $datadiskId -RecoveryResourceGroupId $TargetRecoveryRG.ResourceId -RecoveryReplicaDiskAccountType $RecoveryReplicaDiskAccountType -RecoveryTargetDiskAccountType $RecoveryTargetDiskAccountType
 
    $datadiskconfigs += $datadiskconfig
}


$ProtectVMCount=$ProtectVMCount+1

$diskconfigs = @()
$diskconfigs += $OSDiskReplicationConfig
foreach($config in $datadiskconfigs){
     $diskconfigs += $config
}

$TempASRJob = New-AzRecoveryServicesAsrReplicationProtectedItem -AzureToAzure -AzureVmId $VM.Id -Name (New-Guid).Guid -ProtectionContainerMapping $Source2TargetMapping -AzureToAzureDiskReplicationConfiguration $diskconfigs -RecoveryResourceGroupId $TargetRecoveryRG.ResourceId -RecoveryProximityPlacementGroupId $TargetPPG.Id

#Track Job status to check for completion
while (($TempASRJob.State -eq "InProgress") -or ($TempASRJob.State -eq "NotStarted")){
        sleep 10;
        $TempASRJob = Get-AzRecoveryServicesAsrJob -Job $TempASRJob

#Check if the Job completed successfully. The updated job state of a successfully completed job should be "Succeeded"
Write-Output $TempASRJob.State "On VM:"  $VM.Name
        }
    }
}



 
