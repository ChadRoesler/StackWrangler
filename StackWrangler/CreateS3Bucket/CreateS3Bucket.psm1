function Create-S3Bucket
{
    param(
        [string] $bucketName,
        [string] $logBucketName,
        [string] $logFilePrefix = """$($logBucketName)""",
        [string] $logBucketLogFilePrefix = """""",
        [switch] $skipExistanceCheck = $false,
        [string] $templateLocation = "$($PSScriptRoot)\..\Templates\S3\S3BucketTemplate.json"
    )

    if(!$skipExistanceCheck -and $null -ne (Get-S3Bucket -BucketName $bucketName))
    {
        Write-ErrorLog -message "Bucket: $($bucketName) already exists"
    }
    else
    {
        #Create Empty Objects
        $s3BucketObject = New-Object System.Object
        $createdObject = New-Object System.Object
        $logBucketObject = New-Object System.Object

        $resourceName = ($bucketName -replace "[^a-zA-Z0-9]")

        #Create Octostache Dictionary
        $s3BucketVarDictionary = New-Object Octostache.VariableDictionary
        $s3BucketVarDictionary.Add("S3Bucket", $resourceName)
        $s3BucketVarDictionary.Add("S3BucketName", $bucketName)
        $s3BucketVarDictionary.Add("LoggingBucketName", $logBucketName)
        $s3BucketVarDictionary.Add("S3BucketLogFilePrefix", $logFilePrefix)

        Write-Log -message "Generating S3Bucket Object: $($bucketName)"
        $s3BucketFile = Get-Item $templateLocation
        $s3BucketText = [System.IO.File]::ReadAllText($s3BucketFile)
        $s3BucketText = $s3BucketVarDictionary.Evaluate($s3BucketText)
        $s3BucketObject = ConvertFrom-Json $s3BucketText

        if([string]::IsNullOrWhiteSpace($logBucketName))
        {
            $s3BucketObject.Resources."$($bucketName)".Properties.PsObject.Properties.Remove("LoggingConfiguration")
        }
        else
        {
            Write-Log -message "Validating S3 Log Bucket: $($logBucketName) Existance."
            if($skipExistanceCheck)
            {
                $loggingBucket = $null
            }
            else
            {
                $loggingBucket = Get-S3Bucket -BucketName $logBucketName
            }
            if($loggingBucket -eq $null)
            {
                if($skipExistanceCheck)
                {
                    $logBucketObject = Create-S3LoggingBucket -logBucketName $logBucketname -logFilePrefix $logBucketLogFilePrefix -skipExistanceCheck
                }
                else
                {
                    $logBucketObject = Create-S3LoggingBucket -logBucketName $logBucketname -logFilePrefix $logBucketLogFilePrefix
                }
                $logBucketResourceName = ($logBucketName -replace "[^a-zA-Z0-9]")
                $s3BucketObject.Resources."$($bucketName)" | Add-Member -MemberType NoteProperty -Name "DependsOn" -Value $logBucketResourceName
            }
            else 
            {
                Write-Log -message "S3 Log Bucket: $($logBucketName) Exists"    
            }
        }
        Write-Log -message "Merging S3Bucket Object"
        $createdObject = Merge-MultipleObjects -objectArray @($s3BucketObject, $logBucketObject)
        return $createdObject
    }
}

function Create-S3LoggingBucket
{
    param(
        [string] $logBucketName,
        [string] $logFilePrefix = $logBucketName,
        [switch] $skipExistanceCheck = $false,
        [string] $templateLocation = "$($PSScriptRoot)\..\Templates\S3\S3LoggingBucketTemplate.json"
    )
    $s3LogBucketObject = New-Object System.Object

    if(!$skipExistanceCheck -and (Get-S3Bucket -BucketName $logBucketName) -ne $null)
    {
        Write-ErrorLog -message "Logging Bucket: $($logBucketName) already exists"
    }
    else
    {     
        $resourceName = ($logBucketName -replace "[^a-zA-Z0-9]")
        
        $s3LogBucketVarDictionary = New-Object Octostache.VariableDictionary
        $s3LogBucketVarDictionary.Add("S3LogBucket", $resourceName)
        $s3LogBucketVarDictionary.Add("S3LogBucketName", $logBucketName)
        $s3LogBucketVarDictionary.Add("S3LogBucketLogFilePrefix", $logFilePrefix)
        
        Write-Log -message "Generating Logging S3Bucket Object: $($logBucketName)"
        $s3LogBucketFile = Get-Item $templateLocation
        $s3LogBucketText = [System.IO.File]::ReadAllText($s3LogBucketFile)
        $s3LogBucketText = $s3LogBucketVarDictionary.Evaluate($s3LogBucketText)
        $s3LogBucketObject = ConvertFrom-Json $s3LogBucketText

        return $s3LogBucketObject
    }
}

function Create-MultipleS3Buckets
{
    param(
        [string[]] $bucketNames,
        [string] $templateLocation = "$($PSScriptRoot)\..\Templates\S3\S3BucketTemplate.json"
    )

    #Create Empty Objects
    $createdBucket = New-Object System.Object
    $createdObject = New-Object System.Object


    #Validate UserName Uniqueness
    $uniqueBucketNames = $bucketNames | Select -Unique
    if((Compare-Object -ReferenceObject $bucketNames -DifferenceObject $uniqueBucketNames) -ne $null)
    {
        Write-ErrorLog -message "Unable to create non-unique UserNames passed, please validate the list."
    }
    else
    {
        foreach($bucketName in $bucketNames)
        {
            $createdBucket = Create-S3Bucket -bucketName $bucketName `
                                             -templateLocation $templateLocation
            
            $createdObject = Merge-MultipleObjects -objectArray @($createdObject, $createdBucket)
        }
        return $createdObject
    }
}