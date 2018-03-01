$machineName = "m$(Get-Random)";
$computerName = "w$(Get-Random)";
$resourceGroupName = "VirtualMachinesTutorial";
$location = "westeurope";
$publicAddressName = "ip_for_rdp";
$vNetName = "someNet";
$networkCardName = "karta_sieciowa_$(Get-Random)";

function Login
{
    $needLogin = $true
    Try 
    {
        $content = Get-AzureRmContext
        if ($content) 
        {
            $needLogin = ([string]::IsNullOrEmpty($content.Account))
        } 
    } 
    Catch 
    {
        if ($_ -like "*Login-AzureRmAccount to login*") 
        {
            $needLogin = $true
        } 
        else 
        {
            throw
        }
    }

    if ($needLogin)
    {
        Login-AzureRmAccount
    }
}

function CreateGroupIfNotExists($groupName, $location){
    Get-AzureRmResourceGroup -Name $groupName -ev notPresent -ea 0

    if ($notPresent)
    {
        New-AzureRmResourceGroup -Name $groupName -Location $location
    }
    $resourceGroup = $groupName
}

function CreateNewVirtualNetworkIfNotExists($groupName, $location, $vnetName, $vnetAddressPrefix, $subnetName, $subnetAddressPrefix)
{
    Write-Host "Tworzenie wirtualnej sieci: $vnetName => $vnetAddressPrefix, $subnetName => $subnetAddressPrefix";    
    Get-AzureRmVirtualNetwork -Name $vnetName -ResourceGroupName $groupName -ev notPresent -ea 0

    if ($notPresent)
    {
        $subnetConfig = New-AzureRmVirtualNetworkSubnetConfig `
        -Name $subnetName `
        -AddressPrefix $subnetAddressPrefix

        $vnet = New-AzureRmVirtualNetwork `
          -ResourceGroupName $resourceGroupName `
          -Location $location `
          -Name $vnetName `
          -AddressPrefix $vnetAddressPrefix `
          -Subnet $subnetConfig

        return $vnet;
    }
    else{
        return Get-AzureRmVirtualNetwork -Name $vnetName -ResourceGroupName $groupName
    }      
}

function CreatePublicIpIfNotExists($groupName, $location, $name)
{
    Write-Output "Tworzenie publicznego IP o nazwie: $name.";
    Get-AzureRmPublicIpAddress -Name $name -ResourceGroupName $groupName -ev notPresent -ea 0

    if ($notPresent)
    {
       return New-AzureRmPublicIpAddress `
          -ResourceGroupName $resourceGroupName `
          -Location $location `
          -AllocationMethod Static `
          -Name $name `
          -IdleTimeoutInMinutes 4          
    }
    else{
        return Get-AzureRmPublicIpAddress -Name $name -ResourceGroupName $groupName
    }          
}

function CreateNicIfNotExists($groupName, $location, $name, $subnetId, $pipId, $nsgId)
{
    Write-Output "Tworzenie karty sieciowej: {$name}.";    
    Get-AzureRmNetworkInterface -Name $name -ResourceGroupName $groupName -ev notPresent -ea 0

    if ($notPresent)
    {
       $nic = New-AzureRmNetworkInterface `
          -ResourceGroupName $groupName  `
          -Location $location `
          -Name $name `
          -SubnetId $subnetId `
          -PublicIpAddressId $pipId `
          -NetworkSecurityGroupId $nsgId
        return $nic;
    }
    else{
        return Get-AzureRmNetworkInterface -Name $name -ResourceGroupName $groupName
    }

}

function Info()
{
    Write-Output "Tworzenie maszyny wirtualnej zostało rozpoczęte...";
    Write-Output "Nazwa grupy $resourceGroupName";
    Write-Output "Nazwa maszyny: $machineName i nazwa komputera: $computerName";
}

function NewRemoteDesktopRule()
{
    $rdpName = "rdp$(Get-Random)";
    Write-Output "Tworzenie reguły pulpitu zdalnego o nazwie: $rdpName";
    $rule =  New-AzureRmNetworkSecurityRuleConfig -Name $rdpName  -Protocol Tcp `
            -Direction Inbound -Priority 1000 -SourceAddressPrefix * -SourcePortRange * -DestinationAddressPrefix * `
            -DestinationPortRange 3389 -Access Allow;
    return $rule;
}

Info

Login

CreateGroupIfNotExists $resourceGroupName $location

$vnet = CreateNewVirtualNetworkIfNotExists $resourceGroupName $location "Net" 192.168.0.0/16 "NetSubnet" 192.168.1.0/24


$pip = CreatePublicIpIfNotExists $resourceGroupName $location "RDP$(Get-Random)"
#$nic = CreateNicIfNotExists $resourceGroupName $location "Karta_sieciowa" $vnet.Subnets[0].Id $pip[0].Id


$cred = Get-Credential -Message "Enter a username and password for the virtual machine."

$allowRemoteDesktop = NewRemoteDesktopRule;

Write-Output "Tworzenie grupy zabezpieczeń sieciowych...";
$nsg = New-AzureRmNetworkSecurityGroup -ResourceGroupName $resourceGroupName -Location $location `
  -Name myNetworkSecurityGroup -SecurityRules $nsgRuleRDP

$subnetId = $vnet.Subnets[0].Id;
$pipId = $pip.Id;
$nsgId = $nsg.Id;

$nic = CreateNicIfNotExists $resourceGroupName $location $networkCardName $subnetId $pipId $nsgId

Write-Output "Tworzenie konfiguracji maszyny wirtualnej";

$vmConfig = New-AzureRmVMConfig -VMName $machineName -VMSize Standard_D1 | `
Set-AzureRmVMOperatingSystem -Windows -ComputerName $computerName -Credential $cred | `
Set-AzureRmVMSourceImage -PublisherName MicrosoftWindowsServer -Offer WindowsServer -Skus 2016-Datacenter -Version latest | `
Add-AzureRmVMNetworkInterface -Id $nic.Id

Write-Output "Tworzenie maszyny wirtualnej"
New-AzureRmVM -ResourceGroupName $resourceGroupName -Location $location -VM $vmConfig

