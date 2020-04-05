function Create-IamUser
{
    param(
        [string] $userName,
        [switch] $createAccessKey,
        [switch] $storeKeyInSecretManager,
        [switch] $skipExistanceCheck = $false,
        [string] $templateLocation = "$($PSScriptRoot)\..\Templates\Iam\IamUserTemplate.json"
    )

    #Create Empty Objects
    $iamUserObject = New-Object System.Object
    $iamAccessKeyObject = New-Object System.Object
    $iamSecretManagerObject = New-Object System.Object
    $createdObject = New-Object System.Object

    $resourceName = ($userName -replace "[^a-zA-Z0-9]","")
    
    #Validate User Existance
    try
    {
        if(!$skipExistanceCheck)
        {
            $existingUser = Get-IAMUser -UserName $userName
        }
        else
        {
            $existingUser = $null
        }
    }
    catch
    {
        $existingUser = $null
    }
    if($null -ne $existingUser)
    {
        Write-ErrorLog -message "User: $($userName) already exists"
    }
    else
    {
        if($storeKeyInSecretManager -and !$createAccessKey)
        {
            Write-ErrorLog -message "Unable to create SecretManager Resource without creating AccessKey Resource"
        }
        else
        {
            #Generate Octostache Dictionary for replacement
            $iamUserVarDictionary = New-Object Octostache.VariableDictionary
            $iamUserVarDictionary.Add("IamUser", $resourceName)
            $iamUserVarDictionary.Add("IamUserName", $userName)
            $iamUserVarDictionary.Add("IamAccessKey", "$($userName)AccessKey")
            $iamUserVarDictionary.Add("IamSecretStore","$($userName)SecretStore")

            #Generate Iam User
            Write-Log -message "Generating IamUser Object: $($userName)"
            $iamUserFile = Get-Item $templateLocation
            $iamUserText = [System.IO.File]::ReadAllText($iamUserFile)
            $iamUserText = $iamUserVarDictionary.Evaluate($iamUserText)
            $iamUserObject = ConvertFrom-Json $iamUserText

            #Generate the AccessKey if needed
            if($createAccessKey)
            {
                Write-Log -message "Generating IamAccessKey Object: $($userName)AccessKey"
                $iamAccessKeyFile = Get-Item (Join-Path -Path $iamUserFile.Directory.FullName -ChildPath $iamUserObject.ReferenceData.IamAccessKey)
                $iamAccessKeyText = [System.IO.File]::ReadAllText($iamAccessKeyFile)
                $iamAccessKeyText = $iamUserVarDictionary.Evaluate($iamAccessKeyText)
                $iamAccessKeyObject = ConvertFrom-Json $iamAccessKeyText
            }

            #Generate the SecreteManagerStoreage if needed
            if($storeKeyInSecretManager)
            {
                Write-Log -message "Generating SecretManager Store Object: $($userName)SecretStore"
                $iamSecretManagerFile = Get-Item (Join-Path -Path $iamUserFile.Directory.FullName -ChildPath $iamAccessKeyObject.ReferenceData.IamSecretManager)
                $iamSecretManagerText = [System.IO.File]::ReadAllText($iamSecretManagerFile)
                $iamSecretManagerText = $iamUserVarDictionary.Evaluate($iamSecretManagerText)
                $iamSecretManagerObject = ConvertFrom-Json $iamSecretManagerText
            }

            #Merge the created objects
            Write-Log -message "Merging IamUser Object"
            $createdObject = Merge-MultipleObjects -objectArray @($iamUserObject, $iamAccessKeyObject, $iamSecretManagerObject)
            $createdObject.PsObject.Properties.Remove("ReferenceData")

            return $createdObject
        }
    }
}

function Create-MultipleIamUsers
{
    param(
        [string[]] $userNames,
        [switch] $createAccessKey,
        [switch] $storeKeyInSecretManager,
        [string] $templateLocation = "$($PSScriptRoot)\..\Templates\Iam\IamUserTemplate.json"
    )
    
    #Create Empty Object
    $createdObject = New-Object System.Object
    $createdUser = New-Object Syste.Object

    #Validate UserName Uniqueness
    $uniqueUserNames = $userNames | Select-Object -Unique
    if($null -ne (Compare-Object -ReferenceObject $userNames -DifferenceObject $uniqueUserNames))
    {
        Write-ErrorLog -message "Unable to create non-unique UserNames passed, please validate the list."
    }
    else
    {
        if($storeKeyInSecretManager -and !$createAccessKey)
        {
            Write-ErrorLog -message "Unable to create SecretManager Resource without creating AccessKey Resource"
        }
        else
        {
            foreach($userName in $userNames)
            {
                if($createAccessKey -and $storeKeyInSecretManager)
                {
                    $createdUser = Create-IamUser -userName $userName `
                                                -createAccessKey `
                                                -storeKeyInSecretManager `
                                                -templateLocation $templateLocation
                }
                elseif($createAccessKey -and !$storeKeyInSecretManager)
                {
                    $createdUser = Create-IamUser -userName $userName `
                                                -createAccessKey `
                                                -templateLocation $templateLocation
                }
                else
                {
                    $createdUser = Create-IamUser -userName $userName `
                                                -templateLocation $templateLocation
                }
                $createdObject = Merge-MultipleObjects -objectArray @($createdObject, $createdUser)
            }
            return $createdObject
        }
    }
}


function Create-IamRole
{
    param (
        [string] $roleName,
        [string] $serviceName,
        [switch] $ec2InstanceProfile,
        [switch] $skipExistanceCheck = $false,
        [string] $templateLocation = "$($PSScriptRoot)\..\Templates\Iam\IamRoleTemplate.json"
    )
    #Create Empty Objects
    $iamRoleObject = New-Object System.Object
    $iamInstanceProfileObject = New-Object System.Object
    $createdObject = New-Object System.Object

    $resourceName = ($roleName -replace "[^a-zA-Z0-9]","")
    
    #Validate User Existance
    try
    {
        if(!$skipExistanceCheck)
        {
            $existingUser = Get-IAMRole -RoleName $roleName
        }
        else
        {
            $existingUser = $null
        }
    }
    catch
    {
        $existingUser = $null
    }
    if($null -ne $existingUser)
    {
        Write-ErrorLog -message "Role: $($roleName) already exists"
    }
    else
    {
        #Generate Octostache Dictionary for replacement
        $iamRoleVarDictionary = New-Object Octostache.VariableDictionary
        $iamRoleVarDictionary.Add("IamRole", $resourceName)
        $iamRoleVarDictionary.Add("IamRoleName", $roleName)
        $iamRoleVarDictionary.Add("ServiceName", $serviceName)
        $iamRoleVarDictionary.Add("IamInstanceProfile", "$($roleName)InstanceProfile")

        #Generate Iam User
        Write-Log -message "Generating IamRole Object: $($roleName)"
        $iamRoleFile = Get-Item $templateLocation
        $iamRoleText = [System.IO.File]::ReadAllText($iamRoleFile)
        $iamRoleText = $iamRoleVarDictionary.Evaluate($iamRoleText)
        $iamRoleObject = ConvertFrom-Json $iamRoleText

        if($ec2InstanceProfile)
        {
            Write-Log -message "Generating IamInstanceProfile Object: $($roleName)Instance"
            $iamInstanceProfileFile = Get-Item (Join-Path -Path $iamRoleFile.Directory.FullName -ChildPath $iamRoleObject.ReferenceData.InstanceProfile)
            $iamInstanceProfileText = [System.IO.File]::ReadAllText($iamInstanceProfileFile)
            $iamInstanceProfileText = $iamRoleVarDictionary.Evaluate($iamInstanceProfileText)
            $iamInstanceProfileObject = ConvertFrom-Json $iamInstanceProfileText
        }

        $createdObject = Merge-MultipleObjects -objectArray @($iamRoleObject, $iamInstanceProfileObject)
        $createdObject.PsObject.Properties.Remove("ReferenceData")

        return $createdObject
    }
}