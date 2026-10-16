@{
    RootModule            = 'InventarioTI.psm1'
    ModuleVersion         = '1.0.0'
    GUID                  = 'e91fb4c8-a23f-4095-a65e-34af06866aac'
    Author                = 'Guilherme'
    Copyright             = '(c) 2026 Guilherme. MIT License.'
    Description           = 'Inventario de ativos de TI em redes Windows: coleta via CIM, execucao paralela e relatorios CSV, JSON e HTML.'
    PowerShellVersion     = '5.1'
    CompatiblePSEditions  = @('Desktop', 'Core')
    FunctionsToExport     = @('Get-InventarioMaquina', 'Invoke-InventarioRede', 'Export-InventarioRelatorio')
    CmdletsToExport       = @()
    VariablesToExport     = @()
    AliasesToExport       = @()
    PrivateData           = @{
        PSData = @{
            Tags         = @('inventario', 'inventory', 'asset-management', 'cim', 'wmi', 'windows', 'sysadmin', 'report')
            LicenseUri   = 'https://github.com/guifqz/inventario-ti-powershell/blob/main/LICENSE'
            ProjectUri   = 'https://github.com/guifqz/inventario-ti-powershell'
            ReleaseNotes = 'Primeira versao publica.'
        }
    }
}
