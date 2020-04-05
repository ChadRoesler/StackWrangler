<#
 .Synopsis
  Consoidates cloudformation objects and stack files into a layered organised stack.

 .Description
  Consumes cloudforamtion stack files and objects and organizes them into layered stack files for reuseablity.

 .Parameter stackSystemName
  The system name of the stack.

 .Parameter stackDescription
  The description of the stack, overwrites the current descriptions.

 .Parameter cloudformationFiles
  An array of cloudformation stack file paths.

 .Parameter cloudformationObjects
  An array of cloudformation stack objects.

 .Parameter cloudformationFolders
  An array of folder paths containing cloudformation stack files.

 .Parameter recusiveCloudformationFolders
  Recursively search folders passed to cloudformationFolders.

 .Parameter stackOutputDirectoryPath
  The Directory that the stack will be output to, used to override the Stack Management Configuration File's StackDirectory.

  .Parameter overwriteExistingStack
  Overwrite Existing Stacks.

 .Parameter stackManagementConfigurationLocation
  The path to the stack managementConfigurationFile.
#>

function Wrangle-Stack
{
    param(
        [string] $stackSystemName,
        [string] $stackDescription = $null,
        [array] $cloudformationFiles = $null,
        [array] $cloudformationObjects = $null,
        [array] $cloudformationFolders = $null,
        [bool] $recusiveCloudformationFolders = $true,
        [string] $stackOutputDirectoryPath,
        [switch] $overwriteExistingStack,
        [string] $stackManagementConfigurationLocation = "$($PSScriptRoot)\StackManagement.json"
    )

#################################################
# Load Stack Management Configuration
#################################################
    if(Test-Path -Path $stackManagementConfigurationLocation)
    {
        $stackManagementFile = Get-Item $stackManagementConfigurationLocation
        $stackManagementText = [System.IO.File]::ReadAllText($stackManagementFile)
        $stackManagementObject = ConvertFrom-Json $stackManagementText

        $orderedResourceLayerList = $stackManagementObject.ResourceLayers | Sort-Object { $_.Layer }
        $stackReferencedObjectsMap = $stackManagementObject.ReferencedObjectsMap
        $stackArchitecture = $stackManagementObject.StackArchitecture | Sort-Object { $_.Order }
        $stackTransientResources = $stackManagementObject.TransientResources
        $stackRemoveables = $stackManagementObject.Remove
        $stackDirectory = $stackManagementObject.StackDirectory
        if(!([string]::IsNullOrWhiteSpace($stackOutputDirectoryPath)))
        {
            $stackDirectory = $stackOutputDirectoryPath
        }
        $stackPath = Join-Path -Path $stackDirectory -ChildPath $stackSystemName
        if(Test-Path -Path $stackPath)
        {
            if($overwriteExistingStack)
            {
                Write-WarningLog -message "Overwriting existing stack: $($stackSystemName)"
                Remove-Item -Path $stackPath -Recurse -Force
            }
            else 
            {
                Write-ErrorLog -message "Stack: $($stackSystemName) exists in $($stackDirectory)"
            }
        }
        $stackMetaDataFilePath = Join-Path -Path $stackPath -ChildPath "$($stackSystemname).metadata.json"
    }
    else
    {
        Write-ErrorLog -message "Unable to load Stack Management Configuration file: $($stackManagementConfigurationLocation)."    
    }

#################################################
# Root Variables
#################################################
    $managedStackArray = @()
    $dependantResourceArray = @()
    $missingResourceArray = @()
    $unmanagedStackObjects = @()
    $masterStackObjectArray = @()

#################################################
# Load Stack Objects
#################################################
    if($null -ne $cloudformationFiles)
    {
        Write-Log -message "Loading Stacks from Files."
        foreach($cloudformationFile in $cloudformationFiles)
        {
            $stackFile = Get-Item $cloudformationFile
            $stackText = [System.IO.File]::ReadAllText($stackFile)
            $stackObject = ConvertFrom-Json $stackText
            $stackObject | Add-Member -MemberType NoteProperty -Name "OriginFile" -Value $cloudformationFile
            $unmanagedStackObjects += $stackObject
        }
    }
    if($null -ne $cloudformationObjects)
    {
        Write-Log -message "Loading Stacks from Objects."
        foreach($cloudformationObject in $cloudformationObjects)
        {
            $cloudformationObject | Add-Member -MemberType NoteProperty -Name "OriginFile" -Value "ObjectPassed"
            $unmanagedStackObjects += $cloudformationObject
        }
    }
    if($null -ne $cloudformationFolders)
    {
        Write-Log -message "Loading Stacks from Folders."
        foreach($cloudformationFolder in $cloudformationFolders)
        {
            $cloudformationFolderFiles = Get-ChildItem -Path $cloudformationFolder -Filter "*.json" -Recurse:$recusiveCloudformationFolder
            foreach($cloudformationFolderFile in $cloudformationFolderFiles)
            {
                $cloudformationFiles += $cloudformationFolderFile.FullName
                $stackFile = Get-Item $cloudformationFolderFile.FullName
                $stackText = [System.IO.File]::ReadAllText($stackFile)
                $stackObject = ConvertFrom-Json $stackText
                $stackObject | Add-Member -MemberType NoteProperty -Name "OriginFile" -Value $cloudformationFolderFile.FullName
                $unmanagedStackObjects += $stackObject
            }
        }
    }


#################################################
# Generate Base Type objects for sorting
#################################################       
    $stackConditionObjects = New-Object System.Object
    $stackConditionObjects | Add-Member -MemberType NoteProperty -Name "Type" -Value "Conditions"
    $stackConditionObjects | Add-Member -MemberType NoteProperty -Name "Objects" -Value @()

    $stackParameterObjects = New-Object System.Object
    $stackParameterObjects | Add-Member -MemberType NoteProperty -Name "Type" -Value "Parameters"
    $stackParameterObjects | Add-Member -MemberType NoteProperty -Name "Objects" -Value @()

    $stackOutputObjects = New-Object System.Object
    $stackOutputObjects | Add-Member -MemberType NoteProperty -Name "Type" -Value "Outputs"
    $stackOutputObjects | Add-Member -MemberType NoteProperty -Name "Objects" -Value @()

    $stackMappingObjects = New-Object System.Object
    $stackMappingObjects | Add-Member -MemberType NoteProperty -Name "Type" -Value "Mappings"
    $stackMappingObjects | Add-Member -MemberType NoteProperty -Name "Objects" -Value @()

    $stackResourceObjects = New-Object System.Object
    $stackResourceObjects | Add-Member -MemberType NoteProperty -Name "Type" -Value "Resources"
    $stackResourceObjects | Add-Member -MemberType NoteProperty -Name "Objects" -Value @()

    $stackDescriptionObjects = New-Object System.Object
    $stackDescriptionObjects | Add-Member -MemberType NoteProperty -Name "Type" -Value "Description"
    $stackDescriptionObjects | Add-Member -MemberType NoteProperty -Name "Objects" -Value @()

    $stackTemplateVersionObjects = New-Object System.Object
    $stackTemplateVersionObjects | Add-Member -MemberType NoteProperty -Name "Type" -Value "AWSTemplateFormatVersion"
    $stackTemplateVersionObjects | Add-Member -MemberType NoteProperty -Name "Objects" -Value @()

    $stackTransientResourceObjects = New-Object System.Object
    $stackTransientResourceObjects | Add-Member -MemberType NoteProperty -Name "Type" -Value "TransientResources"
    $stackTransientResourceObjects | Add-Member -MemberType NoteProperty -Name "Objects" -Value @()

#################################################
# Spit out objects to their root arrays
#################################################
    Write-Log -message "Splitting and initial sort of Objects."
    foreach($stackObject in $unmanagedStackObjects)
    {
        foreach($removeable in $stackObject.PsObject.Properties | Where-Object { $stackRemoveables -contains $_.Name })
        {
            $stackObject.PsObject.Properties.Remove($removeable)
        }
        if($null -ne $stackObject.Description)
        {
            $stackDescriptionObjects.Objects += $stackObject.Description
            $stackObject.PsObject.Properties.Remove("Description")
        }
        if($null -ne $stackObject.AWSTemplateFormatVersion)
        {
            $stackTemplateVersionObjects.Objects += $stackObject.AWSTemplateFormatVersion
            $stackObject.PsObject.Properties.Remove("AWSTemplateFormatVersion")
        }
        if($null -ne $stackObject.Conditions)
        {
            foreach($condition in $stackObject.Conditions.PsObject.Properties)
            {
                $refObject = New-object System.Object
                $refObject | Add-Member -MemberType NoteProperty -Name $condition.Name -Value (Clone-Object -objectToClone $stackObject.Conditions."$($condition.Name)")

                $conditional = New-Object System.Object
                $conditional | Add-Member -MemberType NoteProperty -Name "Name" -Value $condition.Name
                $conditional | Add-Member -MemberType NoteProperty -Name "ConditionsObject" -Value $refObject
                $conditional | Add-Member -MemberType NoteProperty -Name "OriginFile" -Value $stackObject.OriginFile
                $conditional | Add-Member -MemberType NoteProperty -Name "Layer" -Value 999
                $conditional | Add-Member -MemberType NoteProperty -Name "CreateOutput" -Value $false
                $stackConditionObjects.Objects += $conditional
                
            }
            $stackObject.PsObject.Properties.Remove("Conditions")
        }
        if($null -ne $stackObject.Parameters)
        {
            foreach($parameter in $stackObject.Parameters.PsObject.Properties)
            {
                $refObject = New-object System.Object
                $refObject | Add-Member -MemberType NoteProperty -Name $parameter.Name -Value (Clone-Object -objectToClone $stackObject.Parameters."$($parameter.Name)")

                $parameterization = New-Object System.Object
                $parameterization | Add-Member -MemberType NoteProperty -Name "Name" -Value $parameter.Name
                $parameterization | Add-Member -MemberType NoteProperty -Name "ParametersObject" -Value $refObject
                $parameterization | Add-Member -MemberType NoteProperty -Name "OriginFile" -Value $stackObject.OriginFile
                $parameterization | Add-Member -MemberType NoteProperty -Name "Layer" -Value 999
                $parameterization | Add-Member -MemberType NoteProperty -Name "CreateOutput" -Value $false
                $stackParameterObjects.Objects += $parameterization
            }
            $stackObject.PsObject.Properties.Remove("Parameters")
        }
        if($null -ne $stackObject.Outputs)
        {
            foreach($output in $stackObject.Outputs.PsObject.Properties)
            {
                $refObject = New-object System.Object
                $refObject | Add-Member -MemberType NoteProperty -Name $output.Name -Value (Clone-Object -objectToClone $stackObject.Outputs."$($output.Name)")

                $outputable = New-Object System.Object
                $outputable | Add-Member -MemberType NoteProperty -Name "Name" -Value $output.Name
                $outputable | Add-Member -MemberType NoteProperty -Name "OutputsObject" -Value $refObject
                $outputable | Add-Member -MemberType NoteProperty -Name "OriginFile" -Value $stackObject.OriginFile
                $outputable | Add-Member -MemberType NoteProperty -Name "Layer" -Value 999
                $outputable | Add-Member -MemberType NoteProperty -Name "CreateOutput" -Value $false
                $stackOutputObjects.Objects += $outputable
            }
            $stackObject.PsObject.Properties.Remove("Outputs")
        }
        if($null -ne $stackObject.Mappings)
        {
            foreach($mapping in $stackObject.Mappings.PsObject.Properties)
            {
                $refObject = New-object System.Object
                $refObject | Add-Member -MemberType NoteProperty -Name $mapping.Name -Value (Clone-Object -objectToClone $stackObject.Mappings."$($mapping.Name)")

                $map = New-Object System.Object
                $map | Add-Member -MemberType NoteProperty -Name "Name" -Value $mapping.Name
                $map | Add-Member -MemberType NoteProperty -Name "MappingsObject" -Value $refObject
                $map | Add-Member -MemberType NoteProperty -Name "OriginFile" -Value $stackObject.OriginFile
                $map | Add-Member -MemberType NoteProperty -Name "Layer" -Value 999
                $map | Add-Member -MemberType NoteProperty -Name "CreateOutput" -Value $false
                $stackMappingObjects.Objects += $map
            }
            $stackObject.PsObject.Properties.Remove("Mappings")
        }
        if($null -ne $stackObject.Resources)
        {
            foreach($resource in $stackObject.Resources.PsObject.Properties)
            {
                $refObject = New-Object System.Object
                $refObject | Add-Member -MemberType NoteProperty -Name $resource.Name -Value (Clone-Object -objectToClone $stackObject.Resources."$($resource.Name)")

                $resourceable = New-Object System.Object
                $resourceable | Add-Member -MemberType NoteProperty -Name "Name" -Value $resource.Name
                $resourceable | Add-Member -MemberType NoteProperty -Name "OriginFile" -Value $stackObject.OriginFile
                $resourceable | Add-Member -MemberType NoteProperty -Name "ResourceType" -Value $stackObject.Resources."$($resource.Name)".Type
                $resourceable | Add-Member -MemberType NoteProperty -Name "Layer" -Value 999
                $resourceable | Add-Member -MemberType NoteProperty -Name "CreateOutput" -Value $false
                
                if($stackTransientResources -contains $stackObject.Resources."$($resource.Name)".Type)
                {
                    $resourceable | Add-Member -MemberType NoteProperty -Name "TransientResourcesObject" -Value $refObject
                    $stackTransientResourceObjects.Objects += $resourceable
                }
                else 
                {
                    $resourceable | Add-Member -MemberType NoteProperty -Name "ResourcesObject" -Value $refObject
                    $stackResourceObjects.Objects += $resourceable    
                }
            }
            $stackObject.PsObject.Properties.Remove("Resources")
        }
    }

    if(($stackTemplateVersionObjects.Objects | Select-Object -Unique).Count -gt 1)
    {
        Write-warningLog -message "!!! Mutliple Template Versions Detected, this may cause instabiltity !!!"
    }

    $masterStackObjectArray += $stackConditionObjects
    $masterStackObjectArray += $stackResourceObjects
    $masterStackObjectArray += $stackParameterObjects
    $masterStackObjectArray += $stackOutputObjects
    $masterStackObjectArray += $stackMappingObjects
    $masterStackObjectArray += $stackTransientResourceObjects
    $masterStackObjectArray += $stackDescriptionObjects
    $masterStackObjectArray += $stackTemplateVersionObjects

#################################################
# Organize Resources and Capture Dependencies
#################################################
    Write-Log -message "Ordering Resources to their approrpiate Layers."
    foreach($orderedResourceLayer in $orderedResourceLayerList)
    {
        $orderedResourceList = $orderedResourceLayer.Resources | Sort-Object { $_.Order }  | Select-Object -Property Type
        $resourceLayer = New-Object System.Object
        $resourceLayer | Add-Member -MemberType NoteProperty -Name "Layer" -Value $orderedResourceLayer.Layer
        $resourceLayer | Add-Member -MemberType NoteProperty -Name "Resources" -Value (New-Object System.Object)
        $resourceLayer | Add-Member -MemberType NoteProperty -Name "LayerName" -Value $orderedResourceLayer.LayerName
        
        foreach($orderedResource in $orderedResourceList)
        {
            foreach($resource in $stackResourceObjects.Objects | Where-Object { $_.ResourceType -eq $orderedResource.Type })
            {
                if(($resource.ResourcesObject."$($resource.Name)".PsObject.Properties | Where-Object { $_.Name -eq "DependsOn" }).Length -gt 0)
                {
                    $newRefObject = New-Object System.Object
                    $newRefObject | Add-Member -MemberType NoteProperty -Name "Resource" -Value $resource.Name
                    $newRefObject | Add-Member -MemberType NoteProperty -Name "DependsOn" -Value $resource.ResourcesObject."$($resource.Name)".DependsOn
                    $newRefObject | Add-Member -MemberType NoteProperty -Name "ResourceLayer" -Value $orderedResourceLayer.Layer
                    
                    $dependantResourceArray += $newRefObject
                    $resource.ResourcesObject."$($resource.Name)".PsObject.Properties.Remove("DependsOn")
                }
                $resource.Layer = $orderedResourceLayer.Layer
                $resourceLayer.Resources | Add-Member -MemberType NoteProperty -Name $resource.Name -Value $resource.ResourcesObject."$($resource.Name)"
            }
            
        }
        if(($resourceLayer.Resources | Get-Member | Where-Object { $_.MemberType -match "Property" }).Count -gt 0)
        {
            $managedStackArray += $resourceLayer
        }
    }

#################################################
# Capture Resources that dont have types in the StackManagement Definition
# Attach them at the end of the Layers
#################################################
    if(($stackResourceObjects.Objects | Where-Object { 999 -eq $_.Layer }).Length -gt 0)
    {
        Write-WarningLog -message "Objects of types not contained in the Stack Management Configuration File were found."
        $missingResourceLayerNumber = (($managedStackArray | Sort-Object -Property Layer -Descending | Select-Object -first 1).Layer + 1)
        $missingResourceLayer = New-Object System.Object
        $missingResourceLayer | Add-Member -MemberType NoteProperty -Name "Layer" -Value $missingResourceLayerNumber
        $missingResourceLayer | Add-Member -MemberType NoteProperty -Name "Resources" -Value (New-Object System.Object)
        $missingResourceLayer | Add-Member -MemberType NoteProperty -Name "LayerName" -Value "MissingResources"
        
        $missingResourceArray = @()
        foreach($missingResource in $stackResourceObjects.Objects | Where-Object { $null -eq $_.Layer } | Sort-Object { $_.ResourceType })
        {
            if(($missingResourceArray | Where-Object { $_.ResourceType -eq $($missingResource.ResourcesObject."$($missingResource.Name)".ResourceType) }).Length -eq 0)
            {
                $missingObject = New-Object System.Object
                $missingObject | Add-Member -MemberType NoteProperty -Name "ResourceType" -Value $missingResource.ResourcesObject."$($missingResource.Name)".ResourceType
                $missingObject | Add-Member -MemberType NoteProperty -Name "Names" -Value @($missingResource.Name)
                $missingResourceArray += $missingObject
            }
            else
            {
                $missingObject = $missingResourceArray | Where-Object { $_.ResourceType -eq $($missingResource.ResourcesObject."$($missingResource.Name)".ResourceType) }
                $missingObject.Names += $missingResource.Name
            }
        }
        foreach($missingResource in $missingResourceArray)
        {
            $missingResourceWarning = @"
The Resource Type: $($missingResource.ResourceType) was not found in the Stack Management Configuration File.
The following Resources of that type have been found: $($missingResource.Names -join ', ').
"@
            Write-WarningLog -message $missingResourceWarning
            
        }
        Write-WarningLog -message "The resources listed above will be placed in their own as the last layer"
        foreach($missingResource in $stackResourceObjects.Objects | Where-Object { $null -eq $_.Layer } | Sort-Object { $_.ResourceType })
        {
            
            if(($missingResource.ResourcesObject."$($missingResource.Name)".PsObject.Properties | Where-Object { $_.Name -eq "DependsOn" }).Length -gt 0)
            {
                $newRefObject = New-Object System.Object
                $newRefObject | Add-Member -MemberType NoteProperty -Name "Resource" -Value $missingResource.Name
                $newRefObject | Add-Member -MemberType NoteProperty -Name "DependsOn" -Value $missingResource.ResourcesObject."$($missingResource.Name)".DependsOn
                $newRefObject | Add-Member -MemberType NoteProperty -Name "ResourceLayer" -Value $missingResourceLayer
                    
                $dependantResourceArray += $newRefObject
                $missingResource.ResourcesObject."$($missingResource.Name)".PsObject.Properties.Remove("DependsOn")
            }
            $resource.Layer = $missingResourceLayerNumber
            $missingResourceLayer.Resources | Add-Member -MemberType NoteProperty -Name $missingResource.Name -Value $missingResource.ResourcesObject."$($missingResource.Name)"
        }
        $managedStackArray += $missingResourceLayer
    }

#################################################
# Remove Dependencies that exist to a resource on a higher level
#################################################
    Write-Log -message "Resource Dependency Management"
    foreach($dependantResource in $dependantResourceArray)
    {
        foreach($dependant in $dependantResource.DependsOn)
        {
            $resource = $stackResourceObjects.Objects| Where-Object { $_.Name -eq $dependant }
            if($null -eq $resource)
            {
                $resource = $stackTransientResourceObjects.Objects | Where-Object { $_.Name -eq $dependant }
                $newDependObject = New-Object System.Object
                $newDependObject | Add-Member -MemberType NoteProperty -Name "Name" -Value $dependantResource.Resource
                $newDependObject | Add-Member -MemberType NoteProperty -Name "Layer" -Value $dependantResource.ResourceLayer

                if(($resource.PsObject.Properties | Where-Object { $_.Name -eq "DependantOf" }).Length -eq 0)
                {
                    $resource | Add-Member -MemberType NoteProperty -Name "DependentOf" -Value @()
                }
                $resource.DependentOf += $newDependObject
                
            }
            else
            {
                if($resource.Layer -eq $dependantResource.ResourceLayer)
                {
                    $resourceLayer = $managedStackArray | Where-Object { $_.Layer -eq $resource.Layer }
                    $resourceToSet = $resourceLayer.Resources."$($dependantResource.Resource)"
                    if(($resourceToSet.PsObject.Properties | Where-Object { $_.Name -eq "DependsOn" }).Length -eq 0)
                    {
                        $resourceToSet | Add-Member -MemberType NoteProperty -Name "DependsOn" -Value @()
                    }
                    $resourceToSet.DependsOn += $dependant
                }
                elseif($resource.Layer -gt $dependantResource.ResourceLayer)
                {
                    Write-ErrorLog -message "Resource: $($dependantResource.Resource), has dependancies on a lower layer: $($dependant), please review your stack management configuration"
                }
            }
        }
    }

#################################################
# Gather Object References to other Objects
#################################################
    foreach($stackObjectType in $masterStackObjectArray)
    {
        if($stackObjectType.Objects.Count -gt 0)
        {
            $referenceMap = $stackReferencedObjectsMap | Where-Object { $_.ObjectType -eq $stackObjectType.Type }
            $foundInMap = $referenceMap.FoundIn
            $containsMap = $referenceMap.Contains
            if($foundInMap.Count -gt 0)
            {
                Write-Log -message "Searching for $($stackObjectType.Type) in: $($foundInMap -join ", ") "
                $stackObjectsFoundIn = $masterStackObjectArray | Where-Object { $foundInMap -contains $_.Type }
                foreach($referenceType in $referenceMap.ReferenceTypes)
                {
                    $foundInPropertyPathList = @()
                    for($s = 0; $s -lt $stackObjectsFoundIn.Count; $s++ )
                    {
                        $startingString = "[$($s)]"
                        for($o = 0; $o -lt $stackObjectsFoundIn[$s].Objects.Count; $o++)
                        {
                            $objectPathString = "$($startingString).Objects[$($o)].$($stackObjectsFoundIn[$s].Type)Object"
                            $foundInPropertyPathList += Find-ObjectPropertiesRecursive -object $stackObjectsFoundIn[$s].Objects[$o]."$($stackObjectsFoundIn[$s].Type)Object" -matchToken "^$($referenceType.Name)$" -pathName $objectPathString
                        }
                    }
                    foreach($propertyPath in $foundInPropertyPathList)
                    {
                        $transformedPropertyPath = ($propertyPath -replace "\.$($referenceType.Name)$")
                        $object = Get-PropertyObjectDynamic -object $stackObjectsFoundIn -propertyPath $transformedPropertyPath
                        $rootPosition = $transformedPropertyPath.Split(".")[0] -replace "\[" -replace "\]"
                        $rootObjectPath = $transformedPropertyPath.Split(".")[0..1] -join "."
                        $rootObject = Get-PropertyObjectDynamic -object $stackObjectsFoundIn -propertyPath $rootObjectPath
                        if($object."$($referenceType.Name)".GetType().ToString() -eq $referenceType.Type)
                        {
                            $stackObject = $null
                            if($null -ne $referenceType.ReferenceAt)
                            {
                                $referencedValue = $object."$($referenceType.Name)"[$referenceType.ReferenceAt]
                            }
                            else
                            {
                                $referencedValue = $object."$($referenceType.Name)"
                            }
                            if(!$referencedValue.StartsWith("AWS::"))
                            {
                                if($null -ne $referenceType.SearchString)
                                {
                                    $stackObject = $stackObjectType.Objects | Where-Object { $referencedValue -match ($referenceType.SearchString -replace "ResourceName", $_.Name) }
                                }
                                else
                                {
                                    $stackObject = $stackObjectType.Objects | Where-Object { $_.Name -eq $referencedValue }                   
                                }
                                if($null -ne $stackObject)
                                {
                                    if(($stackObject.PsObject.Properties | Where-Object { $_.Name -eq "FoundIn" }).Length -eq 0)
                                    {
                                        $stackObject | Add-Member -MemberType NoteProperty -Name "FoundIn" -Value @()
                                    }
                                    $trimmedPath = $transformedPropertyPath.Split(".")[1..($transformedPropertyPath.Split(".").Length - 1)] -join "."
                                    $layer = $rootObject.Layer
                                    $newRefObject = New-Object System.Object
                                    $newRefObject | Add-Member -MemberType NoteProperty -Name "ObjectType" -Value $stackObjectsFoundIn[$rootPosition].Type
                                    $newRefObject | Add-Member -MemberType NoteProperty -Name "Path" -Value $trimmedPath
                                    $newRefObject | Add-Member -MemberType NoteProperty -Name "Layer" -Value $layer
                                    $newRefObject | Add-Member -MemberType NoteProperty -Name "Name" -Value $rootObject.Name
                                    $newRefObject | Add-Member -MemberType NoteProperty -Name "ReferenceTypeName" -Value $referenceType.Name
                                    $newRefObject | Add-Member -MemberType NoteProperty -Name "ReferenceAt" -Value $referenceType.ReferenceAt
                                    if(($stackObject.FoundIn | Where-Object { $_.Path -eq $newRefObject.Path }).Length -eq 0)
                                    {
                                        $stackObject.FoundIn += $newRefObject
                                    }
                                }
                            }
                        }
                    }
                }
            }
            if($containsMap.Length -ne 0)
            {
                Write-Log -message "Searching $($stackObjectType.Type) for: $($containsMap -join ", ") "
                $containsObjects = $stackReferencedObjectsMap | Where-Object { $containsMap -contains $_.ObjectType }
                foreach($containsObject in $containsObjects)
                {
                    $containsObjectTypeList = $masterStackObjectArray | Where-Object { $_.Type -eq $containsObject.ObjectType }
                    foreach($referenceType in $containsObject.ReferenceTypes)
                    {
                        $containsPropertyPathList = @()
                        for($i = 0; $i -lt $stackObjectType.Objects.Length; $i++)
                        {
                            $objectPathString = "Objects[$($i)].$($stackObjectType.Type)Object"
                            $containsPropertyPathList += Find-ObjectPropertiesRecursive -object $stackObjectType.Objects[$i]."$($stackObjectType.Type)Object" -matchToken "^$($referenceType.Name)$" -pathName $objectPathString
                        }
                        foreach($propertyPath in $containsPropertyPathList)
                        {
                            $transformedPropertyPath = ($propertyPath -replace "\.$($referenceType.Name)$")
                            $object = Get-PropertyObjectDynamic -object $stackObjectType -propertyPath $transformedPropertyPath
                            $rootObjectPath = $transformedPropertyPath.Split(".")[0]
                            $rootObject = Get-PropertyObjectDynamic -object $stackObjectType -propertyPath $rootObjectPath
                            if($null -ne $referenceType.ReferenceAt)
                            {
                                $referencedValue = $object."$($referenceType.Name)"[$referenceType.ReferenceAt]
                            }
                            else
                            {
                                $referencedValue = $object."$($referenceType.Name)"
                            }
                            if(!$referencedValue.StartsWith("AWS::"))
                            {
                                if($null -ne $referenceType.SearchString)
                                {
                                    $stackObject = $containsObjectTypeList.Objects | Where-Object { $referencedValue -match ($referenceType.SearchString -replace "ResourceName", $_.Name) }
                                }
                                else
                                {
                                    $stackObject = $containsObjectTypeList.Objects | Where-Object { $_.Name -eq $referencedValue }
                                }
                                if($null -ne $stackObject)
                                {
                                    $position = $containsObjectTypeList.Objects.IndexOf($stackObject)
                                    $propertyToPath = "Objects[$($position)].$($containsObjectTypeList.Type)Object"
                                    if(($rootObject.PsObject.Properties | Where-Object { $_.Name -eq "Contains" }).Length -eq 0)
                                    {
                                        $rootObject | Add-Member -MemberType NoteProperty -Name "Contains" -Value @()
                                    }
                                    $layer = $stackObject.Layer
                                    $newRefObject = New-Object System.Object
                                    $newRefObject | Add-Member -MemberType NoteProperty -Name "ObjectType" -Value $containsObjectTypeList.Type
                                    $newRefObject | Add-Member -MemberType NoteProperty -Name "Path" -Value $propertyToPath
                                    $newRefObject | Add-Member -MemberType NoteProperty -Name "Layer" -Value $layer
                                    $newRefObject | Add-Member -MemberType NoteProperty -Name "Name" -Value $stackObject.Name
                                    $newRefObject | Add-Member -MemberType NoteProperty -Name "ReferenceTypeName" -Value $referenceType.Name
                                    $newRefObject | Add-Member -MemberType NoteProperty -Name "ReferenceAt" -Value $referenceType.ReferenceAt
                                    if(($rootObject.Contains | Where-Object { $_.Path -eq $newRefObject.Path }).Length -eq 0)
                                    {
                                        $rootObject.Contains += $newRefObject
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
#################################################
# Gather TransientResources Dependencies
#################################################
    Write-Log -message "Gathering TransientResources Dependencies"
    foreach($stackObject in $stackTransientResourceObjects.Objects)
    {
        if(($stackObject.TransientResourcesObject."$($stackObject.Name)".PsObject.Properties | Where-Object { $_.Name -eq "DependsOn" }).Length -gt 0)
        {
            foreach($dependantResource in $stackObject.TransientResourcesObject."$($stackObject.Name)".DependsOn)
            {
                $resource = $stackResourceObjects.Objects | Where-Object { $_.Name -eq $dependantResource }
                if($null -ne $resource)
                {
                    if(($stackObject.PsObject.Properties | Where-Object { $_.Name -eq "DependsOn" }).Length -eq 0)
                    {
                        $stackObject | Add-Member -MemberType NoteProperty -Name "DependsOn" -Value @()
                    }
                    $newDependObject = New-Object System.Object
                    $newDependObject | Add-Member -MemberType NoteProperty -Name "Name" -Value $resource.Name
                    $newDependObject | Add-Member -MemberType NoteProperty -Name "Layer" -Value $resource.Layer
                    $stackObject.DependsOn += $newDependObject
                }
            }
        }
    }

#################################################
# Manage Resources that reference resources
# Either leave the reference be, or create an output from a highter layer
#################################################
    Write-Log -message "Gathering Resources referenced by other Resources"
    foreach($stackObject in $stackResourceObjects.Objects)
    {
        if($null -ne $stackObject.FoundIn)
        {
            if($stackObject.FoundIn.Length -gt 0)
            {
                $stackLayer = $managedStackArray[$stackObject.Layer]
                $exportObjectName = "$($stackSystemName)$($stackLayer.LayerName)$($stackLayer.Layer)$($stackObject.Name)$($foundObject.Name)"
                $layersIn = @()
                $layersIn = ($stackObject.FoundIn | Where-Object { $_.ObjectType -eq "Resources" } | Select-Object -ExpandProperty "Layer" | Where-Object { $_ -ne $stackObject.Layer } | Select-Object -Unique)
                if($null -ne $layersIn)
                {
                    if(($layersIn | Where-Object { $_ -lt $stackObject.Layer}).Length -gt 1)
                    {
                        Write-ErrorLog "Resource: $($stackObject.Name) is on a Lower layer yet is referenced by Objects on a Higher layer."
                    }
                    else
                    {
                        if(($layersIn | Where-Object { $_ -gt $stackObject.Layer }).Length -gt 0)
                        {
                            if(($stackLayer.PsObject.Properties | Where-Object { $_.Name -eq "Outputs" }).Length -eq 0)
                            {
                                $stackLayer | Add-Member -MemberType NoteProperty -Name "Outputs" -Value (New-Object System.Object)
                            }
                        }
                        foreach($foundObject in $stackObject.FoundIn | Where-Object { $_.Layer -gt $stackObject.Layer -and $_.ObjectType -eq "Resources" })
                        {
                            $stackObjectType = $masterStackObjectArray | Where-Object { $_.Type -eq $foundObject.ObjectType }
                            $splitPath = $foundObject.Path.Split(".")
                            $lastPath = $splitPath[-1]
                            $previousPath = $splitPath[0..($splitPath.Length - 2)] -join "."
                            $rootObjectToModify = Get-PropertyObjectDynamic -object $stackObjectType -propertyPath $previousPath
                            $objectToModify = Get-PropertyObjectDynamic -object $stackObjectType -propertyPath $foundObject.Path
                            $newSubObject = New-Object System.Object
                            $newSubObject | Add-Member -MemberType NoteProperty -Name "Fn::Sub" -Value $exportObjectName
                            $newImpObject = New-Object System.Object
                            $newImpObject | Add-Member -MemberType NoteProperty -Name "Fn::ImportValue" -Value $newSubObject

                            if(($stackLayer.Outputs.PsObject.Properties | Where-Object { $_.Name -eq $exportObjectName }).Length -eq 0)
                            {
                                $newOutputExportObject = New-Object System.Object
                                $newOutputExportObject | Add-Member -MemberType NoteProperty -Name "Name" -Value $exportObjectName
                                $newReferenceExportObject = New-Object System.Object
                                $newReferenceExportObject | Add-Member -MemberType NoteProperty -Name $foundObject.ReferenceTypeName -Value (Clone-Object -objectToClone $objectToModify."$($foundObject.ReferenceTypeName)")
                                $newOutputObject = New-Object System.Object
                                $newOutputObject | Add-Member -MemberType NoteProperty -Name "Value" -Value (Clone-Object -objectToClone $newReferenceExportObject) 
                                $newOutputObject | Add-Member -MemberType NoteProperty -Name "Export" -Value $newOutputExportObject
                                $stackLayer.Outputs | Add-Member -MemberType NoteProperty -Name $exportObjectName -Value $newOutputObject
                            }
                            if($lastPath -match ".+?(\[[0-9]+\])$")
                            {
                                $lastPathSplit = $lastPath.Split("[")
                                $lastPathProperty = $lastPathSplit[0]
                                $position = $lastPathSplit[1].TrimEnd("]")
                                $rootObjectToModify."$($lastPathProperty)"[$position] = $newImpObject
                            }
                            else
                            {
                                $rootObjectToModify."$($lastPath)" = $newImpObject
                            }
                        }
                    }
                }
            }
        }
    }


##########################################
# Manage Outputs Referencing Resources
##########################################
    Write-Log -message "Manage Outputs referenceing Resources"
    foreach($stackObject in $stackOutputObjects.Objects)
    {
        if($null -ne $stackObject.Contains)
        {
            $layersIn = @()
            $otherLayers = @()
            $layersIn = ($stackObject.Contains | Where-Object { $_.ObjectType -eq "Resources" } | Select-Object -ExpandProperty "Layer" | Select-Object -Unique) | Sort-Object -Descending
            if($layersIn.Length -ne 0)
            {
                $initialLayer = $layersIn[0]
                $stackObject.Layer = $initialLayer
                
                if($layersIn.Length -gt 1)
                {
                    $otherLayers = $layersIn[1..($layersIn.Length - 1)]
                }
                $stackLayer = $managedStackArray | Where-Object { $_.Layer -eq $initialLayer }
                if(($stackLayer.PsObject.Properties | Where-Object { $_.Name -eq "Outputs" }).Length -eq 0)
                {
                    $stackLayer | Add-Member -MemberType NoteProperty -Name "Outputs" -Value (New-Object System.Object)
                }
                $stackLayer.Outputs | Add-Member -MemberType NoteProperty -Name $stackObject.Name -Value $stackObject.OutputsObject."$($stackObject.Name)"
                if($otherLayers.Length -gt 0)
                {
                    Write-WarningLog -message "Output: $($stackObject.Name) references Resources on Multiple Layers"
                }
                foreach($container in $stackObject.Contains)
                {
                    $containerObject = Get-PropertyObjectDynamic -object ($masterStackObjectArray | Where-Object { $_.Type -eq $container.ObjectType })[0] -propertyPath $container.Path.Split(".")[0]
                    ($containerObject.FoundIn | Where-Object { $_.Name -eq $stackObject.Name -and $_.ObjectType -eq  "Outputs"}).Layer = $initialLayer
                }
            }
        }
    }

    
##########################################
# Manage Conditions referenced by Resources and Outputs
##########################################
    Write-Log -message "Manage Conditions referenced by Resources and Outputs"
    foreach($stackObject in $stackConditionObjects.Objects)
    {
        if($null -ne $stackObject.FoundIn)
        {
            $layersIn = @()
            $otherLayers = @()
            $layersIn = ($stackObject.FoundIn | Where-Object { @("Resources", "Outputs") -contains $_.ObjectType } | Select-Object -ExpandProperty "Layer" | Where-Object { $_ -ne $stackObject.Layer } | Select-Object -Unique ) | Sort-Object -Descending
            if($layersIn.Length -ne 0)
            {
                $initialLayer = $layersIn[0]
                $stackObject.Layer = $initialLayer
                if($layersIn.Length -gt 1)
                {
                    $otherLayers = $layersIn[1..($layersIn.Length - 1)]
                }
                $stackLayer = $managedStackArray | Where-Object { $_.Layer -eq $initialLayer }
                if(($stackLayer.PsObject.Properties | Where-Object { $_.Name -eq "Conditions" }).Length -eq 0)
                {
                    $stackLayer | Add-Member -MemberType NoteProperty -Name "Conditions" -Value (New-Object System.Object)
                }
                $stackLayer.Conditions | Add-Member -MemberType NoteProperty -Name $stackObject.Name -Value $stackObject.ConditionsObject."$($stackObject.Name)"
                if($otherLayers.Length -gt 0)
                {
                    Write-WarningLog -message "Condition: $($stackObject.Name) is referenced by Multiple Layers"
                }
                foreach($container in $stackObject.Contains)
                {
                    $containerObject = Get-PropertyObjectDynamic -object ($masterStackObjectArray | Where-Object { $_.Type -eq $container.ObjectType })[0] -propertyPath $container.Path.Split(".")[0]
                    ($containerObject.FoundIn | Where-Object { $_.Name -eq $stackObject.Name -and $_.ObjectType -eq  "Conditions"}).Layer = $initialLayer
                }
                foreach($foundin in $stackObject.FoundIn)
                {
                    $foundInObject = Get-PropertyObjectDynamic -object ($masterStackObjectArray | Where-Object { $_.Type -eq $foundin.ObjectType })[0] -propertyPath $foundin.Path.Split(".")[0]
                    ($foundInObject.Contains | Where-Object { $_.Name -eq $stackObject.Name -and $_.ObjectType -eq  "Conditions"}).Layer = $initialLayer
                }
            }
        }
    }

    
    
##########################################
# Manage Conditions referenced by Conditions
##########################################
    Write-Log -message "Manage Conditions referenced by Conditions"
    while (($stackConditionObjects.Objects | Where-Object { $_.Layer -eq 999 }).Length -gt 0)
    {
        foreach($stackObject in $stackConditionObjects.Objects)
        {
            if($null -ne $stackObject.FoundIn)
            {
                $layersIn = @()
                $otherLayers = @()

                $layersIn = ($stackObject.FoundIn | Where-Object { $_.ObjectType -eq "Conditions" } | Select-Object -ExpandProperty "Layer" | Where-Object { $_ -ne $stackObject.Layer } | Select-Object -Unique ) | Sort-Object -Descending
                if($layersIn.Length -ne 0)
                {
                    $initialLayer = $layersIn[0]
                    $stackObject.Layer = $initialLayer
                    if($layersIn.Length -gt 1)
                    {
                        $otherLayers = $layersIn[1..($layersIn.Length - 1)]
                    }
                    $stackLayer = $managedStackArray | Where-Object { $_.Layer -eq $initialLayer }
                    if(($stackLayer.PsObject.Properties | Where-Object { $_.Name -eq "Conditions" }).Length -eq 0)
                    {
                        $stackLayer | Add-Member -MemberType NoteProperty -Name "Conditions" -Value (New-Object System.Object)
                    }
                    $stackLayer.Conditions | Add-Member -MemberType NoteProperty -Name $stackObject.Name -Value $stackObject.ConditionsObject."$($stackObject.Name)"
                    if($otherLayers.Length -gt 0)
                    {
                        Write-WarningLog -message "Condition: $($stackObject.Name) is referenced by Multiple Layers"
                    }
                    foreach($container in $stackObject.Contains)
                    {
                        $containerObject = Get-PropertyObjectDynamic -object ($masterStackObjectArray | Where-Object { $_.Type -eq $container.ObjectType })[0] -propertyPath $container.Path.Split(".")[0]
                        ($containerObject.FoundIn | Where-Object { $_.Name -eq $stackObject.Name -and $_.ObjectType -eq  "Conditions"}).Layer = $initialLayer
                    }
                    foreach($foundin in $stackObject.FoundIn)
                    {
                        $foundInObject = Get-PropertyObjectDynamic -object ($masterStackObjectArray | Where-Object { $_.Type -eq $foundin.ObjectType })[0] -propertyPath $foundin.Path.Split(".")[0]
                        ($foundInObject.Contains | Where-Object { $_.Name -eq $stackObject.Name -and $_.ObjectType -eq  "Conditions"}).Layer = $initialLayer
                    }
                }
            }
        }
    }

    
##########################################
# Manage Parameters referenced by Resources, Outputs, and Conditions
##########################################
    Write-Log -message "Manage Parameters referenced by Resources, Outputs, and Conditions"
    foreach($stackObject in $stackParameterObjects.Objects)
    {
        if($null -ne $stackObject.FoundIn)
        {
            $layersIn = @()
            $otherLayers = @()
            $layersIn = ($stackObject.FoundIn | Where-Object { @("Resources", "Outputs", "Conditions") -contains $_.ObjectType } | Select-Object -ExpandProperty "Layer" | Where-Object { $_ -ne $stackObject.Layer } | Select-Object -Unique ) | Sort-Object -Descending
            if($layersIn.Length -ne 0)
            {
                $initialLayer = $layersIn[0]
                $stackObject.Layer = $initialLayer
                if($layersIn.Length -gt 1)
                {
                    $otherLayers = $layersIn[1..($layersIn.Length - 1)]
                }
                $stackLayer = $managedStackArray | Where-Object { $_.Layer -eq $initialLayer }
                if(($stackLayer.PsObject.Properties | Where-Object { $_.Name -eq "Parameters" }).Length -eq 0)
                {
                    $stackLayer | Add-Member -MemberType NoteProperty -Name "Parameters" -Value (New-Object System.Object)
                }
                $stackLayer.Parameters | Add-Member -MemberType NoteProperty -Name $stackObject.Name -Value $stackObject.ParametersObject."$($stackObject.Name)"
                if($otherLayers.Length -gt 0)
                {
                    Write-WarningLog -message "Parameter: $($stackObject.Name) is referenced by Multiple Layers"
                }
                foreach($foundin in $stackObject.FoundIn)
                {
                    $foundInObject = Get-PropertyObjectDynamic -object ($masterStackObjectArray | Where-Object { $_.Type -eq $foundin.ObjectType })[0] -propertyPath $foundin.Path.Split(".")[0]
                    ($foundInObject.Contains | Where-Object { $_.Name -eq $stackObject.Name -and $_.ObjectType -eq  "Parameters"}).Layer = $initialLayer
                }
            }
        }
    }

##########################################
# Manage Mappings referenced by Resources, Outputs, and Conditions
##########################################
    Write-Log -message "Manage Mappings referenced by Resources, Outputs, and Conditions"
    foreach($stackObject in $stackMappingObjects.Objects)
    {
        if($null -ne $stackObject.FoundIn)
        {
            $layersIn = @()
            $otherLayers = @()
            $layersIn = ($stackObject.FoundIn | Where-Object { @("Resources", "Outputs", "Conditions") -contains $_.ObjectType } | Select-Object -ExpandProperty "Layer" | Where-Object { $_ -ne $stackObject.Layer } | Select-Object -Unique ) | Sort-Object -Descending
            if($layersIn.Length -ne 0)
            {
                $initialLayer = $layersIn[0]
                $stackObject.Layer = $initialLayer
                if($layersIn.Length -gt 1)
                {
                    $otherLayers = $layersIn[1..($layersIn.Length - 1)]
                }
                $stackLayer = $managedStackArray | Where-Object { $_.Layer -eq $initialLayer }
                if(($stackLayer.PsObject.Properties | Where-Object { $_.Name -eq "Mappings" }).Length -eq 0)
                {
                    $stackLayer | Add-Member -MemberType NoteProperty -Name "Mappings" -Value (New-Object System.Object)
                }
                $stackLayer.Mappings | Add-Member -MemberType NoteProperty -Name $stackObject.Name -Value $stackObject.MappingsObject."$($stackObject.Name)"
                if($otherLayers.Length -gt 0)
                {
                    Write-WarningLog -message "Mapping: $($stackObject.Name) is referenced by MultipleLayers"
                }
                foreach($foundin in $stackObject.FoundIn)
                {
                    $foundInObject = Get-PropertyObjectDynamic -object ($masterStackObjectArray | Where-Object { $_.Type -eq $foundin.ObjectType })[0] -propertyPath $foundin.Path.Split(".")[0]
                    ($foundInObject.Contains | Where-Object { $_.Name -eq $stackObject.Name -and $_.ObjectType -eq  "Mappings"}).Layer = $initialLayer
                }
            }
        }
    }
    
##########################################
# Manage Outputs Referencing Conditions, Parameters, and Mappings
##########################################
    Write-Log -message "Manage Outputs referencing Conditions, Parameters, Mappings"
    foreach($stackObject in ($stackOutputObjects.Objects | Where-Object { $_.Layer -eq 999 } ))
    {
        if($null -ne $stackObject.Contains)
        {
            $layersIn = @()
            $otherLayers = @()
            $layersIn = ($stackObject.Contains | Where-Object { @("Resources", "TransientResources") -notcontains $_.ObjectType } | Select-Object -ExpandProperty "Layer" | Select-Object -Unique) | Sort-Object -Descending
            if($layersIn.Length -ne 0)
            {
                $initialLayer = $layersIn[0]
                $stackObject.Layer = $initialLayer
                
                if($layersIn.Length -gt 1)
                {
                    $otherLayers = $layersIn[1..($layersIn.Length - 1)]
                }
                $stackLayer = $managedStackArray | Where-Object { $_.Layer -eq $initialLayer }
                if(($stackLayer.PsObject.Properties | Where-Object { $_.Name -eq "Outputs" }).Length -eq 0)
                {
                    $stackLayer | Add-Member -MemberType NoteProperty -Name "Outputs" -Value (New-Object System.Object)
                }
                $stackLayer.Outputs | Add-Member -MemberType NoteProperty -Name $stackObject.Name -Value $stackObject.OutputsObject."$($stackObject.Name)"
                if($otherLayers.Length -gt 0)
                {
                    Write-WarningLog -message "Output: $($stackObject.Name) references Multiple Layers"
                }
                foreach($container in $stackObject.Contains)
                {
                    $containerObject = Get-PropertyObjectDynamic -object ($masterStackObjectArray | Where-Object { $_.Type -eq $container.ObjectType })[0] -propertyPath $container.Path.Split(".")[0]
                    ($containerObject.FoundIn | Where-Object { $_.Name -eq $stackObject.Name -and $_.ObjectType -eq  "Outputs"}).Layer = $initialLayer
                }
            }
        }
    }

##########################################
# Manage TransientResources
##########################################
    Write-Log -message "Manage Transient Resources"
    while(($stackTransientResourceObjects.Objects | Where-Object { $_.Layer -eq 999 }).Length -gt 0)
    {
        foreach($stackObject in $stackTransientResourceObjects.Objects | Where-Object { $_.Layer -eq 999 })
        {
            $layersIn = @()
            $otherLayers = @()
            $layersIn = @($stackObject.DependentOf | Select-Object -ExpandProperty "Layer" | Select-Object -Unique)
            $layersIn = @($stackObject.DependsOn | Select-Object -ExpandProperty "Layer" | Select-Object -Unique)
            $layersIn += @($stackObject.Contains  | Where-Object { $_.Layer -ne 999 } | Select-Object -ExpandProperty "Layer" | Select-Object -Unique)
            $layersIn += @($stackObject.Foundin  | Where-Object { $_.Layer -ne 999 } | Select-Object -ExpandProperty "Layer" | Select-Object -Unique)
            $layersIn = $layersIn | Select-Object -Unique
            if($layersIn.Length -ne 0)
            {
                $initialLayer = $layersIn[0]
                $stackObject.Layer = $initialLayer
                
                if($layersIn.Length -gt 1)
                {
                    $otherLayers = $layersIn[1..($layersIn.Length - 1)]
                }
                $stackLayer = $managedStackArray | Where-Object { $_.Layer -eq $initialLayer }
                $stackLayer.Resources | Add-Member -MemberType NoteProperty -Name $stackObject.Name -Value $stackObject.TransientResourcesObject."$($stackObject.Name)"
                foreach($container in $stackObject.Contains)
                {
                    $containerObject = Get-PropertyObjectDynamic -object ($masterStackObjectArray | Where-Object { $_.Type -eq $container.ObjectType })[0] -propertyPath $container.Path.Split(".")[0]
                    ($containerObject.FoundIn | Where-Object { $_.Name -eq $stackObject.Name -and $_.ObjectType -eq  "TransientResources"}).Layer = $initialLayer
                }
                if($otherLayers.Length -gt 0)
                {
                    Write-WarningLog -message "TransientResource $($stackObject.Name) is referenced on Multiple Layers"
                }
            }
        }
    }

##########################################
# Manage Description and Version
##########################################
    Write-Log -message "Manage Version"
    $version = $stackTemplateVersionObjects.Objects[0]
    if($null -eq $version)
    {
        $version = "2010-09-09"
    }
    foreach($stackLayer in $managedStackArray)
    {
        $stackLayer | Add-Member -MemberType NoteProperty -Name "AWSTemplateFormatVersion" -Value $version
    }
    if($null -eq $stackDescription)
    {
        $stackDescription = $stackDescriptionObjects.De
    }



##########################################
# Output the Managed Stack to the destination
##########################################
    Write-Log -message "Writing Stack files to: $($stackPath)"
    if(!(Test-Path -Path $stackPath))
    {
        New-Item -Path $stackPath -ItemType "Directory" -Force | Out-Null
    }
    $stackMetaData = New-Object System.Object
    foreach($stackLayer in $managedStackArray)
    {
        $stackLayerObject = New-Object System.Object
        $stackFileName = "$($stackLayer.LayerName)_$($stackLayer.Layer.ToString()).json"
        
        foreach($stackObjectType in $stackArchitecture)
        {
            if($null -ne $stackLayer."$($stackObjectType.Type)")
            {
                $stackLayerObject | Add-Member -MemberType NoteProperty -Name $stackObjectType.Type -Value $stackLayer."$($stackObjectType.Type)"
                if(($stackMetaData.PsObject.Properties | Where-Object { $_.Name -eq "$($stackObjectType.Type)"}).Length -eq 0)
                {
                    $stackMetaData | Add-Member -MemberType NoteProperty -Name "$($stackObjectType.Type)" -Value @()
                }
                foreach($stackObject in $stackLayer."$($stackObjectType.Type)".PsObject.Properties)
                {
                    $metaDataObject = New-Object System.Object
                    $metaDataObject | Add-Member -MemberType NoteProperty -Name "Name" -Value "$($stackObject.Name)"
                    if($stackObjectType.Type -eq "Resources")
                    {
                        $metaDataObject | Add-Member -MemberType NoteProperty -Name "Type" -Value $stackLayer."$($stackObjectType.Type)"."$($stackObject.Name)".Type
                    }
                    $metaDataObject | Add-Member -MemberType NoteProperty -Name "File" -Value $stackFileName
                    $stackMetaData."$($stackObjectType.Type)" += $metaDataObject
                }
            }
        }
        $stackLayerObjectString = ConvertTo-Json $stackLayerObject -Depth 100
        
        $stackFilePath = Join-Path -Path $stackPath -ChildPath $stackFileName
        [IO.File]::WriteAllLines($stackFilePath, $stackLayerObjectString, [System.Text.Encoding]::UTF8)
    }

##########################################
# Output the Metadata file
##########################################
    Write-Log -message "Writing Stack Metadata file to $($stackMetaDataFilePath)"
    $stackMetaDataObjectString = ConvertTo-Json $stackMetaData -Depth 100
    [IO.File]::WriteAllLines($stackMetaDataFilePath, $stackMetaDataObjectString, [System.Text.Encoding]::UTF8)
}


function Load-WrangledStack 
{
    param(
        [string] $stackSystemName = $null,
        [string] $stackDirectoryPath = $null,
        [string] $stackManagementConfigurationLocation = "$($PSScriptRoot)\StackManagement.json"
    )
    $generateMetadata = $false
    $metadataObjectTypes = @("Parameters", "Mappings", "Conditions", "Resources", "Outputs")

    if(Test-Path $stackManagementConfigurationLocation)
    {
        $stackManagementFile = Get-Item $stackManagementConfigurationLocation
        $stackManagementText = [System.IO.File]::ReadAllText($stackManagementFile)
        $stackManagementObject = ConvertFrom-Json $stackManagementText

        $stackDirectory = $stackManagementObject.StackDirectory
        if(!([string]::IsNullOrEmpty($stackDirectoryPath)))
        {
            $stackPath = $stackDirectoryPath
        }
        else
        {
            $stackPath = Join-Path -Path $stackDirectory -ChildPath $stackSystemName
        }
    }
    else
    {
        Write-ErrorLog -message "Unable to load Stack Management Configuration file: $($stackManagementConfigurationLocation)."    
    }
    
    $fullStackObject = New-Object System.Object
    $fullStackObject | Add-Member -MemberType NoteProperty -Name "StackSystemName" -Value $stackSystemName
    $fullStackObject | Add-Member -MemberType NoteProperty -Name "Stacks" -Value (New-Object System.Object)
    
    $stackFiles = Get-ChildItem -Path "$($stackPath)\*" -Filter "*.json" -Exclude "$($stackSystemName).metadata.json"
    
    $metaDataFilePath = Join-Path -Path $stackPath -ChildPath "$($stackSystemName).metadata.json"
    if(!(Test-Path $metaDataFilePath))
    {
        Write-WarningLog -message "The stack does not contain a metadata file, one will be generated"
        $generateMetadata = $true
        $metadataObject = New-Object System.Object
    }
    else
    {
        $metadataFile = Get-Item $metaDataFilePath
        $metadataText = [System.IO.File]::ReadAllText($metaDataFile)
        $metadataObject = ConvertFrom-Json $metaDataText
    }

    foreach($stackFilePath in $stackFiles)
    {
        $stackLayername = ($stackFilePath.Name).Substring(0,($stackFilePath.Name).LastIndexOf("_"))
        $stackLayer = ($stackFilePath.Name).Substring(($stackFilePath.Name).LastIndexOf("_") + 1, ($stackFilePath.Name).LastIndexOf(".") - 1 - ($stackFilePath.Name).LastIndexOf("_"))
        
        $fullStackObject.Stacks | Add-Member -MemberType NoteProperty -Name $stackLayername -Value (New-Object System.Object)
        $fullStackObject.Stacks."$($stackLayername)" | Add-Member -MemberType NoteProperty -Name "File" -Value $stackFilePath.Name
        $fullStackObject.Stacks."$($stackLayername)" | Add-Member -MemberType NoteProperty -Name "Layer" -Value $stackLayer

        $stackFile = Get-Item $stackFilePath
        $stackText = [System.IO.File]::ReadAllText($stackFile)
        $stackObject = ConvertFrom-Json $stackText

        foreach($stackObjectType in $stackObject.PsObject.Properties)
        {
            $fullStackObject.Stacks."$($stackLayername)" | Add-member -MemberType NoteProperty -Name $stackObjectType.Name -Value $stackObject."$($stackObjectType.Name)"
        }

        if($generateMetadata)
        {
            foreach($stack in $fullStackObject.Stacks.PsObject.Properties)
            {
                foreach($objectType in $metadataObjectTypes)
                {
                    foreach($object in $fullStackObject.Stacks."$($stack.Name)"."$($objectType)".PsObject.Properties)
                    {
                        if(($metadataObject.PsObject.Properties | Where-Object { $_.Name -eq $objectType }).Length -eq 0)
                        {
                            $metadataObject | Add-Member -MemberType NoteProperty -Name $objectType -Value @()
                        }
                        $metadataRef = New-Object System.Object
                        $metadataRef | Add-Member -MemberType NoteProperty -Name "Name" -Value $object.name
                        $metadataRef | Add-Member -MemberType NoteProperty -Name "File" -Value $stackFilePath.Name
                        if($objectType -eq "Resources")
                        {
                            $metadataRef | Add-Member -MemberType NoteProperty -Name "Type" -Value $fullStackObject.Stacks."$($stack.Name)"."$($objectType)"."$($object.Name)".Type
                        }
                        $metadataObject."$($objectType)" += $metadataRef
                    }
                }
            }
        }

    }
    $fullStackObject | Add-Member -MemberType NoteProperty -Name "Metadata" -Value $metaDataObject
    return $fullStackObject
}

function Find-InWrangledStack
{
    param(
        [string] $stackSystemName,
        [System.Object] $stackObject = $null,
        [string] $objectType = "Any",
        [string] $searchString = "",
        [string] $resourceType,
        [string] $stackManagementConfigurationLocation = "$($PSScriptRoot)\StackManagement.json"
    )

    $objectsMatchedMetadata = @()
    $stackObjectMatched = @()
    if(!([string]::IsNullOrWhiteSpace($stackSystemName)) -and $null -eq $stackObject)
    {
        if(Test-Path $stackManagementConfigurationLocation)
        {
            $stackManagementFile = Get-Item $stackManagementConfigurationLocation
            $stackManagementText = [System.IO.File]::ReadAllText($stackManagementFile)
            $stackManagementObject = ConvertFrom-Json $stackManagementText
            $stackDirectory = $stackManagementObject.StackDirectory
            if(!([string]::IsNullOrEmpty($stackOutputDirectoryPath)))
            {
                $stackDirectory = $stackOutputDirectoryPath
            }
            $stackPath = Join-Path -Path $stackDirectory -ChildPath $stackSystemName
            $metaDataFilePath = Join-Path -Path $stackPath -ChildPath "$($stackSystemName).metadata.json"
            if(!(Test-Path $metaDataFilePath))
            {
                Write-ErrorLog -message "Unable to locate Metadata File: $($metaDataFilePath)." 
            }
            $metaDataFile = Get-Item $metaDataFilePath
            $metaDataText = [System.IO.File]::ReadAllText($metaDataFile)
            $metaDataObject = ConvertFrom-Json $metaDataText
        }
        else
        {
            Write-ErrorLog -message "Unable to load Stack Management Configuration file: $($stackManagementConfigurationLocation)."    
        }
    }
    else
    {
        if($null -eq $stackObject.Metadata)
        {
            Write-ErrorLog -message "Metadata does not exist on the passed stack object."    
        }
        else
        {
            $metaDataObject = $stackObject.Metadata
        }
    }
    if($null -ne $metaDataObject."$($objectType)")
    {
        if(!([string]::IsNullOrWhiteSpace($resourceType)))
        {
            $objectsMatchedMetadata += $metaDataObject."$($objectType)" | Where-Object { $_.Type -eq $resourceType -and $_.Name -match $searchString }
        }
        else
        {
            $objectsMatchedMetadata += $metaDataObject."$($objectType)" | Where-Object { $_.Name -match $searchString }
        }
        if($null -eq $objectsMatchedMetadata -or $objectsMatchedMetadata.Count -eq 0)
        {
            Write-ErrorLog -message "Stack does not contain any objects with the search string $($searchString)."    
        }
        else
        {
            foreach($objectMatched in $objectsMatchedMetadata)
            {
                $stackFilePath = Join-Path -Path $stackPath -ChildPath $objectMatched.File
                $stackFile = Get-Item $stackFilePath
                $stackText = [System.IO.File]::ReadAllText($stackFile)
                $stackObject = ConvertFrom-Json $stackText 
                $stackObjectRef = New-Object System.Object
                $stackObjectRef | Add-Member -MemberType NoteProperty -Name $objectMatched.Name -Value $stackObject."$($objectType)"."$($objectMatched.Name)"
                $stackObjectMatched += $stackObjectRef
            }
            return $stackObjectMatched
        }
    }
    else
    {
        Write-ErrorLog "Stack does not contain ObjectType: $($objectType)"
    }
}