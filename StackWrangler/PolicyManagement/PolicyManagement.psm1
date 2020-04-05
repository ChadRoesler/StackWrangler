function Create-ManagedPolicy
{
    param(
        [string] $managedPolicyName,
        [System.Object] $userObject,
        [array] $userList,
        [System.Object] $roleObject,
        [array] $roleList,
        [System.Object] $groupObject,
        [array] $groupList,
        [System.Object] $dependentObject,
        [string] $policyDocument,
        [System.Object] $policyDocumentObject,
        [string] $templateLocation = "$($PSScriptRoot)\..\Templates\Iam\IamManagedPolicyTemplate.json"
    )

    $managedPolicyObject = New-Object System.Object
    
    $policyUsersObject = New-Object System.Object
    $policyUsersObject | Add-Member -MemberType NoteProperty -Name "Users" -Value @()
    
    $policyGroupsObject = New-Object System.Object
    $policyGroupsObject | Add-Member -MemberType NoteProperty -Name "Groups" -Value @()
    
    $policyRolesObject = New-Object System.Object
    $policyRolesObject | Add-Member -MemberType NoteProperty -Name "Roles" -Value @()
    
    $depeondsOnList = @()

    if($userObject.Resources.PsObject.Properties.Count -gt 0)
    {
        Write-Log -message "Creating Policy User List and User Dependancy List from UserObject"
        foreach($user in $userObject.Resources.PsObject.Properties)
        {
            if($userObject.Resources."$($user.Name)".Type -eq "AWS::IAM::User")
            {
                if($depeondsOnList -notcontains $user.Name)
                {
                    $depeondsOnList += $user.Name
                }
                if($policyUsersObject.Users -notcontains $user.Name)
                {
                    $refObject = New-Object System.Object
                    $refObject | Add-Member -MemberType NoteProperty -Name "Ref" -Value $user.Name
                    $policyUsersObject.Users += $refObject
                }
            }
        }
    }
    if($userList.Count -gt 0)
    {
        Write-Log -message "Creating Policy User List from UserList"
        foreach($user in $userList)
        {
            if($policyUsersObject.Users -notcontains $user)
            {
                $policyUsersObject.Users += $user
            }
        }
    }

    if($roleObject.Resources.PsObject.Properties.Count -gt 0)
    {
        Write-Log -message "Creating Policy Role List and Role Dependancy List"
        foreach($role in $roleObject.Resources.PsObject.Properties)
        {
            if($roleObject.Resources."$($role.Name)".Type -eq "AWS::IAM::Role")
            {
                if($depeondsOnList -notcontains $role.Name)
                {
                    $depeondsOnList += $role.Name
                }
                if($policyRolesObject.Roles -notcontains $role.Name)
                {
                    $refObject = New-Object System.Object
                    $refObject | Add-Member -MemberType NoteProperty -Name "Ref" -Value $role.Name
                    $policyRolesObject.Roles += $refObject
                }
            }
        }
    }
    if($roleList.Count -gt 0)
    {
        Write-Log -message "Creating Policy Role List from RoleList"
        foreach($role in $roleList)
        {
            if($policyRolesObject.Roles -notcontains $role)
            {
                $policyRolesObject.Roles += $role
            }
        }
    }

    if($groupObject.Resources.PsObject.Properties.Count -gt 0)
    {
        Write-Log -message "Creating Policy Group List and Group Dependancy List"
        foreach($group in $groupObject.Resources.PsObject.Properties)
        {
            if($groupObject.Resources."$($group.Name)".Type -eq "AWS::IAM::Group")
            {
                if($depeondsOnList -notcontains $group.Name)
                {
                    $depeondsOnList += $group.Name
                }
                if($policyGroupsObject.Groups -notcontains $group.Name)
                {
                    $refObject = New-Object System.Object
                    $refObject | Add-Member -MemberType NoteProperty -Name "Ref" -Value $group.Name
                    $policyGroupsObject.Groups += $refObject
                }
            }
        }
    }
    if($groupList.Count -gt 0)
    {
        Write-Log -message "Creating Policy Group List from GroupList"
        foreach($group in $groupList)
        {
            if($groupObject.Groups -notcontains $group)
            {
                $policyGroupsObject.Groups += $group
            }
        }
    }

    Write-Log -message "Generating Master Depenency List"
    foreach($dependent in $dependentObject.Resources.PsObject.Properties)
    {
        if($depeondsOnList -notcontains $dependent.Name)
        {
            $depeondsOnList += $dependent.Name
        }
    }

    $dependsOnString = "`"$($depeondsOnList -join '","')`""

    Write-Log -message "Generating Managed Policy Object."
    $managedPolicyVarDictionary = New-Object Octostache.VariableDictionary
    $managedPolicyVarDictionary.Add("IamManagedPolicy", $managedPolicyName)

    if($null -ne $policyDocumentObject)
    {
        Write-Log -message "Converting Policy Document Object to string"
        $policyDocument = ConvertTo-Json $policyDocumentObject -Depth 100
    }
    $managedPolicyVarDictionary.Add("PolicyDocument", $policyDocument)
    $managedPolicyVarDictionary.Add("ResourceList", $dependsOnString)

    $managedPolicyFile = Get-Item $templateLocation
    $managedPolicyText = [System.IO.File]::ReadAllText($managedPolicyFile)
    $managedPolicyText = $managedPolicyVarDictionary.Evaluate($managedPolicyText)
    $managedPolicyObject = ConvertFrom-Json $managedPolicyText

    if($policyUsersObject.Users.Count -ne 0)
    {
        $managedPolicyObject.Resources."$($managedPolicyName)".Properties | Add-Member -MemberType NoteProperty -Name "Users" -Value $policyUsersObject.Users
    }
    if($policyRolesObject.Roles.Count -ne 0)
    {
        $managedPolicyObject.Resources."$($managedPolicyName)".Properties | Add-Member -MemberType NoteProperty -Name "Roles" -Value $policyRolesObject.Roles
    }
    if($policyGroupsObject.Groups.Count -ne 0)
    {
        $managedPolicyObject.Resources."$($managedPolicyName)".Properties | Add-Member -MemberType NoteProperty -Name "Groups" -Value $policyGroupsObject.Groups
    }

    return $managedPolicyObject
}

function Create-PolicyDocument
{
    param(
        [string[]] $actions,
        [string[]] $resources,
        [string] $templateLocation = "$($PSScriptRoot)\..\Templates\Iam\PolicyDocumentTemplate.json"
    )

    $actionTemplate = ""
    $resourceTemplate = ""
    Write-Log -message "Generating Action List"
    foreach($action in $actions)
    {
        $actionTemplate = "`"$($action)`","
    }
    Write-Log -message "Generating Resource List"
    foreach($resource in $resources)
    {
        try 
        {
            $validate = ConvertFrom-Json $resource
            $resourceTemplate += "$($resource),"
        }
        catch 
        {
            $resourceTemplate += "`"$($resource)`","
        }
        
    }
    $actionTemplate = $actionTemplate.TrimEnd(",")
    $resourceTemplate = $resourceTemplate.TrimEnd(",")
    $policyDocumentGuid = (([guid]::NewGuid()).ToString()).Replace("-","")

    Write-Log -message "Generating Policy Document"
    $policyStatementVarDictionary = New-Object Octostache.VariableDictionary
    $policyStatementVarDictionary.Add("StatementGuid",$policyDocumentGuid)
    $policyStatementVarDictionary.Add("Actions", $actionTemplate)
    $policyStatementVarDictionary.Add("Resources", $resourceTemplate)

    $policyStatementFile = Get-Item $templateLocation
    $policyStatementText = [System.IO.File]::ReadAllText($policyStatementFile)
    $policyStatementText = $policyStatementVarDictionary.Evaluate($policyStatementText)
    $policyStatementObject = ConvertFrom-Json $policyStatementText
    
    return $policyStatementObject
}


function Merge-PolicyDocuments
{
    param(
        [System.Object[]] $policyDocuments
    )
    #Generate Base Object for policies
    $baseDocument = (Clone-Object -objectToClone $policyDocuments[0])
    $statementGroup = @()
    $policyDocuments = $policyDocuments | Where-Object { $_.Statement.Sid -ne $baseDocument.Statement.Sid }
    foreach($policyDocument in $policyDocuments)
    {
        $baseDocument.Statement += $policyDocument.Statement
    }
    $grouppedDocument = ($baseDocument | Group-Object -Property { $_.Statement.Action }, { $_.Statement.Effect })
    foreach($group in $grouppedDocument)
    {
        $baseStatement = $group.Group.Statement[0].PsObject.Copy()
        $statements = $group.Group.Statement | Where-Object { $_.Sid -ne $baseStatement.Sid }
        foreach($statement in $statements)
        {
            $baseStatement.Resource += $statement.Resource 
        }
        $statementGroup += $baseStatement
    }
    $baseDocument.Statement = $statementGroup
    return $baseDocument
}