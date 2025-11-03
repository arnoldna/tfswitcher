@{
    RootModule        = 'tfswitcher.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890'
    Author            = 'jpmicrosoft'
    CompanyName       = 'Unknown'
    Copyright         = '(c) 2025. All rights reserved.'
    Description       = 'PowerShell module for managing and switching between Terraform versions on Windows'
    PowerShellVersion = '5.1'
    FunctionsToExport = '*'
    CmdletsToExport   = '*'
    VariablesToExport = '*'
    AliasesToExport   = '*'
    PrivateData       = @{
        PSData = @{
            Tags       = @('Terraform', 'VersionManager', 'DevOps')
            ProjectUri = 'https://github.com/jpmicrosoft/tfswitcher'
        }
    }
}