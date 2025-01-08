
# PowerShell script to set the registry keys
$registryPath1 = "HKCU:\Software\Policies\Microsoft\office\16.0\outlook\preferences"
$registryPath2 = "HKCU:\Software\Microsoft\Office\16.0\Outlook\Options\General"
$Name1 = "NewOutlookMigrationUserSetting"
$Name2 = "DoNewOutlookAutoMigration"
$value = 0

# Check if the first registry path exists
if (-not (Test-Path $registryPath1)) {
    New-Item -Path $registryPath1 -Force
}

# Set the first registry key value
Set-ItemProperty -Path $registryPath1 -Name $Name1 -Value $value -Type DWord

# Check if the second registry path exists
if (-not (Test-Path $registryPath2)) {
    New-Item -Path $registryPath2 -Force
}

# Set the second registry key value
Set-ItemProperty -Path $registryPath2 -Name $Name2 -Value $value -Type DWord
