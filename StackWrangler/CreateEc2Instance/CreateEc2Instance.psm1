function Create-Ec2Instance
{
    param(
        [string] $instanceName,
        [string] $instanceType,
        [string] $amiName,
        [string] $amiId,
        [string] $userData,
        [string] $userDataFileLocation,
        [string] $iamRoleName,
        [System.Object] $iamRoleWithInstanceProfile,
        [array] $securityGroupIds,
        [System.Object] $securityGroups,
        [string] $subnetId,
        [string] $keyName,
        [string] $templateLocation = "$($PSScriptRoot)\..\Templates\Ec2\InstanceTemplate.json"
    )

    if(![string]::IsNullOrWhiteSpace($amiName) -and ![string]::IsNullOrWhiteSpace($amiId))
    {
        Write-ErrorLog -message "You may only specifiy either the amiName or the amiId"
    }
    elseif(![string]::IsNullOrWhiteSpace($userData) -and ![string]::IsNullOrWhiteSpace($userDataFileLocation))
    {
        Write-ErrorLog -message "You may only specifiy either the userData or the userDataFileLocation"
    }
    elseif(![string]::IsNullOrWhiteSpace($iamRoleName) -and $null -ne $iamRole)
    {
        Write-ErrorLog -message "You may only specifiy either the iamRoleName or the iamRole"
    }
    else
    {
        if($null -ne $iamRoleWithInstanceProfile)
        {
            $iamRoleInstanceProfileCount = 0
            foreach($instanceProfile in $iamRoleWithInstanceProfile.Resources.PsObject.Properties)
            {
                if($iamRoleWithInstanceProfile.Resources."$($instanceProfile.Name)".Type -eq "AWS::IAM::InstanceProfile")
                {
                    $iamRoleInstanceProfileCount++
                }
            }
            if($iamRoleInstanceProfileCount -gt 1)
            {
                Write-ErrorLog "More than one role has been passed in the Object"
            }
        }
        if(![string]::IsNullOrWhiteSpace($userDataFileLocation))
        {
            $userData = [System.IO.File]::ReadAllText($userDataFileLocation)
        }
        $transformedUserData = $userData -replace "\r\n","#{Return}"
        $transformedUserData = $transformedUserData -replace "\n\r","#{Return}"
        $transformedUserData = $transformedUserData -replace "\r","#{Return}"
        $transformedUserData = $transformedUserData -replace "\n","#{Return}"
        $transformedUserData = $transformedUserData -replace "\#\{Return\}", "`",#{Return}`""
        $transformedUserData = $transformedUserData -split "#{Return}"
        $transformedUserData = $transformedUserData -join "`r`n"
        $transformedUserData = $transformedUserData -replace "`"`",", ""
        $transformedUserData = "`"$($transformedUserData)\n`""

        $resourceName = ($instanceName -replace "[^a-zA-Z0-9]","")

        if(![string]::IsNullOrWhiteSpace($amiName))
        {
            $amiObject = Get-Ec2ImageByName -Name $amiName
            if($null -eq $amiObject)
            {
                Write-ErrorLog -message "The specified ami $($amiName) does not exist"
            }
            else
            {
                $amiId = $amiObject.ImageId
            }
        }
        $depeondsOnList = @()
        $instanceObject = New-Object System.Object
        $securityGroupObject = New-Object System.Object
        $securityGroupObject | Add-Member -MemberType NoteProperty -Name "SecurityGroupIds" -Value @()
        $iamRoleObject = New-Object System.Object
        $iamRoleObject | Add-Member -MemberType Noteproperty -Name "IamRole" -Value ""

        $instanceVarDictionary = New-Object Octostache.VariableDictionary
        $instanceVarDictionary.Add("Instance", $resourceName)
        $instanceVarDictionary.Add("InstanceName", $instanceName)
        $instanceVarDictionary.Add("InstanceType", $instanceType)
        $instanceVarDictionary.Add("ImageId", $amiId)
        $instanceVarDictionary.Add("SubnetId", $subnetId)
        $instanceVarDictionary.Add("KeyName", $keyName)
        $instanceVarDictionary.Add("UserDataLines", $transformedUserData)

        if($securityGroups.Resources.PsObject.Properties.Count -gt 0)
        {
            foreach($securityGroup in $securityGroups.Resources.PsObject.Properties)
            {
                if($securityGroups.Resources."$($securityGroup.Name)".Type -eq "AWS::EC2::SecurityGroup")
                {
                    if($depeondsOnList -notcontains $securityGroup.Name)
                    {
                        $depeondsOnList += $securityGroup.Name
                    }
                    if($securityGroupObject.SecurityGroupIds -notcontains $securityGroup.Name)
                    {
                        $refObject = New-Object System.Object
                        $refObject | Add-Member -MemberType NoteProperty -Name "Ref" -Value $securityGroup.Name
                        $securityGroupObject.SecurityGroupIds += $refObject
                    }
                }
            }
        }
        if($securityGroupIds.Count -gt 0)
        {
            foreach($securityGroupId in $securityGroupIds)
            {
                if($securityGroupObject.SecurityGroupIds -notcontains $securityGroupId)
                {
                    $securityGroupObject.SecurityGroupIds += $securityGroupId
                }
            }
        }
        if($null -ne $iamRoleWithInstanceProfile)
        {
            foreach($instanceProfile in $iamRoleWithInstanceProfile.Resources.PsObject.Properties)
            {
                if($iamRoleWithInstanceProfile.Resources."$($instanceProfile.Name)".Type -eq "AWS::IAM::InstanceProfile")
                {
                    if($depeondsOnList -notcontains $instanceProfile.Name)
                    {
                        $depeondsOnList += $instanceProfile.Name
                    }
                    $refObject = New-Object System.Object
                    $refObject | Add-Member -MemberType NoteProperty -Name "Ref" -Value $instanceProfile.Name
                    $iamRoleObject.IamRole = $refObject
                }
            }
        }
        else 
        {
            $iamRoleObject.IamRole = $iamRoleName
        }

        $dependsOnString = "`"$($depeondsOnList -join '","')`""
        $instanceVarDictionary.Add("ResourceList", $dependsOnString)

        $instanceFile = Get-Item $templateLocation
        $instanceText = [System.IO.File]::ReadAllText($instanceFile)
        $instanceText = $instanceVarDictionary.Evaluate($instanceText)
        $instanceObject = ConvertFrom-Json $instanceText

        $instanceObject.Resources."$($resourceName)".Properties | Add-Member -MemberType NoteProperty -Name "SecurityGroupIds" -Value $securityGroupObject.SecurityGroupIds
        $instanceObject.Resources."$($resourceName)".Properties | Add-Member -MemberType NoteProperty -Name "IamInstanceProfile" -Value $iamRoleObject.IamRole

        return $instanceObject
    }
}
