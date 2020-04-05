function Merge-Object
{
    param(
        [System.Object] $targetObject,
        [System.Object] $sourceObject
    )
    $newDummyObject = $targetObject.PsObject.Copy()
    foreach($sourceProperty in $sourceObject.psobject.Properties)
    {
        if($sourceProperty.TypeNameOfValue -eq "System.Management.Automation.PSCustomObject" -and $newDummyObject."$($sourceProperty.Name)")
        {
            $newDummyObject."$($sourceProperty.Name)" = Merge-Object -targetObject $newDummyObject."$($sourceProperty.Name)" `
                                                                     -sourceObject $sourceProperty.Value
        }
        else
        {
            Add-Member -InputObject $newDummyObject -MemberType $sourceProperty.MemberType -Name $sourceProperty.Name -Value $sourceProperty.Value -Force
        }
    }
    return $newDummyObject
}

function Merge-MultipleObjects{
    param(
        [System.Object[]] $objectArray
    )
    $newObject = New-Object -TypeName System.Object
    foreach($object in $objectArray)
    {
        foreach($property in $object.psobject.Properties)
        {
            if($property.TypeNameOfValue -eq 'System.Management.Automation.PSCustomObject' -and $newObject."$($property.Name)")
            {
                $newObject."$($property.Name)" = Merge-Object -targetObject $newObject."$($property.Name)" -sourceObject $property.Value
            }
            else
            {
                Add-Member -InputObject $newObject -MemberType $property.MemberType -Name $property.Name -Value $property.Value -Force
            }
        }
    }
    return $newObject
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

function Clone-Object
{
    param(
        [System.Object] $objectToClone,
        [Array] $arrayOfObjectsToClone
    )
    if($null -ne $objectToClone -and $null -eq $arrayOfObjectsToClone)
    {
        $cloneObject = $objectToClone | ConvertTo-Json -depth 100 | ConvertFrom-Json
        return $cloneObject
    }
    elseif($null -eq $objectToClone -and $null -ne $arrayOfObjectsToClone)
    {
        $cloneArray = @()
        foreach($object in $arrayOfObjectsToClone)
        {
            $cloneArray += Clone-Object -objectToClone $object
        }
        return $cloneArray
    }
}

function Find-ObjectPropertiesRecursive
{
    param(
        [System.Object] $object,
        [string] $matchToken = "",
        [string] $pathName = "`$_",
        [int] $maxDepth = 10,
        [int] $startingLevel = 0
    )
    $propertiesArray = @()
    if($null -ne $object)
    {
        $objectType = ($object.GetType()).ToString()
        if($objectType -eq "System.Object[]")
        {
            $position = 0
            foreach($item in $object)
            {
                $propertiesArray += Find-ObjectPropertiesRecursive -object $item `
                                                                -matchToken $matchToken `
                                                                -pathName "$($pathName)[$($position)]" `
                                                                -maxDepth $maxDepth `
                                                                -startingLevel ($startingLevel + 1) 
                $position++
            }
        }
        else
        {
            $rootProperties = $object | Get-Member | Where-Object { $_.MemberType -match "Property" }
            $typesToExclude = @("System.Boolean", "System.String", "System.Int32", "System.Char")
            if($rootProperties.Length -ne 0)
            {
                foreach($property in $rootProperties)
                {
                    if($property.Name -match $matchToken)
                    {
                        $propertiesArray += "$($pathName).$($property.Name)"
                    }
                }
                if($startingLevel -lt $maxDepth)
                {
                    foreach($property in $rootProperties)
                    {
                        $subObject = $object."$($property.Name)"
                        if($null -ne $subObject)
                        {
                            $objectType = ($subObject.GetType()).ToString()
                            if(!($typesToExclude.Contains($objectType)))
                            {
                                if($null -ne $object)
                                {
                                    $propertiesArray += Find-ObjectPropertiesRecursive -object $subObject `
                                                                                        -matchToken $matchToken `
                                                                                        -pathName "$($pathName).$($property.Name)" `
                                                                                        -maxDepth $maxDepth `
                                                                                        -startingLevel ($startingLevel + 1)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    return $propertiesArray
}

function Get-PropertyObjectDynamic
{
    param(
        [System.Object] $object,
        [string] $propertyPath
    )
    $splitPropertypath = $propertyPath.Split(".")
    $property = $splitPropertypath[0]
    $finalObject = $object
    if($splitPropertypath.Count -gt 1)
    {
        $propertyPathSub = ($splitPropertypath[1..($splitPropertypath.Length - 1)] -join ".")
    }
    else
    {
        $propertyPathSub = ""
    }
    if($property -match ".+?(\[[0-9]+\])$")
    {
        $propertySplit = $property.Split("[")
        $property = $propertySplit[0]
        $arrayObject = $object."$($property)"
        foreach($propertySplitPosition in $propertySplit[1..$propertySplit.Length])
        {
            $position = $propertySplitPosition.TrimEnd("]")
            $arrayObject = $arrayObject[$position]
        }
        $finalObject = Get-PropertyObjectDynamic -object $arrayObject `
                                                -propertyPath $propertyPathSub

    }
    elseif($property -match "^(\[[0-9]+\])+$")
    {
        $propertySplit = $property.Split("[")
        $arrayObject = $object
        foreach($propertySplitPosition in $propertySplit[1..$propertySplit.Length])
        {
            $position = $propertySplitPosition.TrimEnd("]")
            $arrayObject = $arrayObject[$position]
        }
        $finalObject = Get-PropertyObjectDynamic -object $arrayObject `
                                                -propertyPath $propertyPathSub
    }
    else 
    {
        $subObject = $object."$($property)"
        if($null -ne $subObject)
        {
            $finalObject = Get-PropertyObjectDynamic -object $subObject `
                                                     -propertyPath $propertyPathSub
        }
    }   
    return $finalObject 
}