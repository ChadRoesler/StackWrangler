function Create-SecurityGroup
{
    param(
        [string] $securityGroupName,
        [string] $vpcId,
        [System.Object[]] $egresses,
        [System.Object[]] $ingresses,
        [switch] $skipExistanceCheck = $false,
        [string] $templateLocation = "$($PSScriptRoot)\..\Templates\Ec2\SecurityGroupTemplate.json"
    )

    try
    {
        if(!$skipExistanceCheck)
        {
            $existingSecurityGroup = Get-EC2SecurityGroup -GroupName $securityGroupName
        }
        else
        {
            $existingSecurityGroup = $null
        }
    }
    catch
    {
        $existingSecurityGroup = $null
    }

    if($null -ne $existingSecurityGroup)
    {
        Write-ErrorLog -message "SecurityGroyp: $($securityGroupName) already exists"
    }
    else
    {
        $securityGroupObject = New-Object System.Object

        $resourceName = ($securityGroupName -replace "[^a-zA-Z0-9]","")

        $securityGroupVarDictionary = New-Object Octostache.VariableDictionary
        $securityGroupVarDictionary.Add("SecurityGroup", $resourceName)
        $securityGroupVarDictionary.Add("SecurityGroupName", $securityGroupName)
        $securityGroupVarDictionary.Add("VpcId", $vpcId)

        Write-Log -message "Generating SecurityGroup Object: $($securityGroupName)"
        $securityGroupFile = Get-Item $templateLocation
        $securityGroupText = [System.IO.File]::ReadAllText($securityGroupFile)
        $securityGroupText = $securityGroupVarDictionary.Evaluate($securityGroupText)
        $securityGroupObject = ConvertFrom-Json $securityGroupText

        if($egresses.Count -gt 0)
        {
            $securityGroupObject.Resources."$($securityGroupName)".Properties | Add-Member -MemberType NoteProperty -Name "SecurityGroupEgress" -Value $egresses
        }

        if($ingresses.Count -gt 0)
        {
            $securityGroupObject.Resources."$($securityGroupName)".Properties | Add-Member -MemberType NoteProperty -Name "SecurityGroupIngress" -Value $ingresses
        }

        return $securityGroupObject
    }
}

function Create-SecruirtyGroupGress
{
    param(
        [string] $protocol,
        [int] $fromPort,
        [int] $toPort,
        [string[]] $cidrIpArray,
        [string] $templateLocation = "$($PSScriptRoot)\..\Templates\Ec2\GressTemplate.json"
    )

    $securityGroupGressObjectArray = @()
    foreach($cidrIp in $cidrIpArray)
    {
        $securityGroupGressObject = New-Object System.Object

        $securityGroupGressVarDictionary = New-Object Octostache.VariableDictionary
        $securityGroupGressVarDictionary.Add("Protocol", $protocol)
        $securityGroupGressVarDictionary.Add("FromPort", $fromPort)
        $securityGroupGressVarDictionary.Add("ToPort", $toPort)
        $securityGroupGressVarDictionary.Add("CidrIp", $cidrIp)

        $securityGroupGressFile = Get-Item $templateLocation
        $securityGroupGressText = [System.IO.File]::ReadAllText($securityGroupGressFile)
        $securityGroupGressText = $securityGroupGressVarDictionary.Evaluate($securityGroupGressText)
        $securityGroupGressObject = ConvertFrom-Json $securityGroupGressText
        $securityGroupGressObjectArray += $securityGroupGressObject
    }

    return $securityGroupGressObjectArray

}