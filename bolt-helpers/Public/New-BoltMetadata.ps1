function New-BoltMetadata {
    [CmdletBinding()]
    param (
        # The Path to a PowerShell file to write a metadata file for.
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [string[]]
        $Path,

        # The names of any parameters that should be marked Sensitive
        [Parameter(Mandatory = $false)]
        [string[]]
        $SensitiveParam,

        # Add PowerShell common parameters to the metadata
        [Parameter(Mandatory = $false)]
        [switch]
        $IncludeCommonParameters
    )

    begin {
        $commonParameters = @(
            'ErrorAction'
            'InformationAction'
            'Verbose'
            'WarningAction'
        )

        $paramsToRemove = @(
            'Debug'
            'ErrorVariable'
            'InformationVariable'
            'OutVariable'
            'OutBuffer'
            'PipelineVariable'
            'WarningVariable'
        )
    }

    process {
        foreach ($file in $path) {
            $help = Get-help $file
            $command = Get-Command -Name $file
            $attributesCollection = New-object System.Collections.ArrayList

            foreach ($param in $command.Parameters.Values) {
                $description = ($help.parameters.parameter.where( {$_.name -eq $param.name})).description
                @{
                    name              = $param.name
                    type              = $param.ParameterType.Name.Replace('[]', '')
                    isArray           = $param.ParameterType.IsArray
                    isOptional        = !$param.Attributes.Mandatory
                    isCommonParameter = $commonParameters -contains $param.name
                    shouldBeRemoved   = $paramsToRemove -contains $param.name
                    description       = $description
                } `
                    | Where-object shouldBeRemoved -ne $true `
                    | Foreach-Object -Process {$_.type = $_.type.Replace('ActionPreference', 'String'); $_} `
                    | Foreach-object -Process {[void]$attributesCollection.Add($_)}
            }

            foreach ($set in $attributesCollection) {
                $typeString = ''

                if ($set.type -eq 'SwitchParameter') {
                    $typeString = 'Boolean'
                    if (-not $set.isMandatory) {
                        $typeString = "Optional[$typeString]"
                    }
                    $set.typeString = $typeString
                    continue
                }

                if ($set.isArray) {
                    $typeString = "Varient[Array[{0}], {0}]" -f $set.Type
                } else {
                    $typeString = $set.Type
                }

                if ($set.isOptional) {
                    $typeString = "Optional[$typeString]"
                }

                $set.typeString = $typeString
            }

            $metaObject = @{
                puppet_task_version = 1
                input_method        = 'powershell'
                description         = $help.Synopsis
            }

            if ($noop = $attributesCollection.where( {$_.name -eq '_noop'})) {
                $metaObject.suports_noop = $true
                $attributesCollection.remove($noop)
            }

            if (!$IncludeCommonParameters) {
                $attributesCollection = $attributesCollection | Where-Object -FilterScript {$commonParameters -notcontains $_.name}
            }

            $parameters = @{}

            foreach ($param in $attributesCollection) {
                $parameters.$($param.name) = @{
                    description = $param.description
                    type        = $param.typeString
                }
            }

            $metaObject.parameters = $parameters
            $metaObject | ConvertTo-JSON -Depth 99
        }
    }

    end {
    }
}
