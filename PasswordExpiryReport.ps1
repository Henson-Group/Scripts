Param 
( 
    [Parameter(Mandatory = $false)] 
    [switch]$PwdNeverExpires, 
    [switch]$PwdExpired, 
    [switch]$LicensedUserOnly, 
    [int]$SoonToExpire, 
    [int]$RecentPwdChanges,
    [switch]$EnabledUsersOnly,
    [string]$TenantId,
    [string]$ClientId,
    [string]$CertificateThumbprint
) 

$MsGraphBetaModule =  Get-Module Microsoft.Graph.Beta -ListAvailable
if($MsGraphBetaModule -eq $null)
{ 
    Write-host "Important: Microsoft Graph Beta module is unavailable. It is mandatory to have this module installed in the system to run the script successfully." 
    $confirm = Read-Host Are you sure you want to install Microsoft Graph Beta module? [Y] Yes [N] No  
    if($confirm -match "[yY]") 
    { 
        Write-host "Installing Microsoft Graph Beta module..."
        Install-Module Microsoft.Graph.Beta -Scope CurrentUser -AllowClobber
        Write-host "Microsoft Graph Beta module is installed in the machine successfully" -ForegroundColor Magenta 
    } 
    else
    { 
        Write-host "Exiting. `nNote: Microsoft Graph Beta module must be available in your system to run the script" -ForegroundColor Red
        Exit 
    } 
}
Write-Host "Connecting to MS Graph PowerShell..."
if(($TenantId -ne "") -and ($ClientId -ne "") -and ($CertificateThumbprint -ne ""))  
{  
    Connect-MgGraph  -TenantId $TenantId -AppId $ClientId -CertificateThumbprint $CertificateThumbprint -ErrorAction SilentlyContinue -ErrorVariable ConnectionError|Out-Null
    if($ConnectionError -ne $null)
    {    
        Write-Host $ConnectionError -Foregroundcolor Red
        Exit
    }
}
else
{
    Connect-MgGraph -Scopes "Directory.Read.All"  -ErrorAction SilentlyContinue -Errorvariable ConnectionError |Out-Null
    if($ConnectionError -ne $null)
    {
        Write-Host "$ConnectionError" -Foregroundcolor Red
        Exit
    }
}


$UserCount = 0 
$PrintedUser = 0 
$Result = ""
$PwdPolicy=@{}
#Output file declaration 
$Location=Get-Location
$ExportCSV = "$Location\PasswordExpiryReport_$((Get-Date -format yyyy-MMM-dd-ddd` hh-mm-ss` tt).ToString()).csv" 

#Getting Password policy for the domain
$Domains = Get-MgBetaDomain   #-Status Verified
foreach($Domain in $Domains)
{ 
    #Check for federated domain
    if($Domain.AuthenticationType -eq "Federated")
    {
        $PwdValidity = 0
    }
    else
    {
        $PwdValidity = $Domain.PasswordValidityPeriodInDays
        if($PwdValidity -eq $null)
        {
            $PwdValidity = 90
        }
    }
    $PwdPolicy.Add($Domain.Id,$PwdValidity)
}
Write-Host "Generating M365 users' password expiry report..." -ForegroundColor Magenta
#Loop through each user 
Get-MgBetaUser -All -Property DisplayName,UserPrincipalName,LastPasswordChangeDateTime,PasswordPolicies,AssignedLicenses,AccountEnabled,SigninActivity | foreach{ 
    $UPN = $_.UserPrincipalName
    $DisplayName = $_.DisplayName
    [boolean]$Federated = $false
    $UserCount++
    Write-Progress -Activity "`n     Processed user count: $UserCount "`n"  Currently Processing: $DisplayName"
    #Remove external users
    if($UPN -like "*#EXT#*")
    {
        return
    }
    $PwdLastChange = $_.LastPasswordChangeDateTime
    $PwdPolicies = $_.PasswordPolicies
    $LicenseStatus = $_.AssignedLicenses
    $LastSignInDate=$_.SignInActivity.LastSignInDateTime
    #Calculate Inactive days
    if($LastSignInDate -eq $null)
    { 
     $LastSignInDate="Never Logged-in"
     $InactiveDays= "-"
    }
    else
    {
     $InactiveDays= (New-TimeSpan -Start $LastSignInDate).Days
    }
    $Print = 0
    
    if($LicenseStatus -ne $null)
    {
        $LicenseStatus = "Licensed"
    }
    else
    {
        $LicenseStatus = "Unlicensed"
    }
    if($_.AccountEnabled -eq $true)
    {
        $AccountStatus = "Enabled"
    }
    else
    {
        $AccountStatus = "Disabled"
    }
    #Finding password validity period for user
    $UserDomain= $UPN -Split "@" | Select-Object -Last 1 
    $PwdValidityPeriod=$PwdPolicy[$UserDomain]
    #Check for Pwd never expires set from pwd policy
    if([int]$PwdValidityPeriod -eq 2147483647)
    {
        $PwdNeverExpire = $true
        $PwdExpireIn = "Never Expires"
        $PwdExpiryDate = "-"
        $PwdExpiresIn = "-"
    }
    elseif($PwdValidityPeriod -eq 0) #Users from federated domain
    {
        $Federated = $true
        $PwdExpireIn = "Insufficient data in O365"
        $PwdExpiryDate = "-"
        $PwdExpiresIn = "-"
    }
    elseif($PwdPolicies -eq "none" -or $PwdPolicies -eq "DisableStrongPassword") #Check for Pwd never expires set from Set-MsolUser
    {
        $PwdExpiryDate = $PwdLastChange.AddDays($PwdValidityPeriod)
        $PwdExpiresIn = (New-TimeSpan -Start (Get-Date) -End $PwdExpiryDate).Days
        if($PwdExpiresIn -gt 0)
        {
            $PwdExpireIn = "Will expire in $PwdExpiresIn days"
        }
        elseif($PwdExpiresIn -lt 0)
        {
            #Write-host `n $PwdExpiresIn
            $PwdExpireIn = $PwdExpiresIn * (-1)
            #Write-Host ************$pwdexpiresin
            $PwdExpireIn = "Expired $PwdExpireIn days ago"
        }
        else
        {
            $PwdExpireIn = "Today"
        }
    }
    else
    {
        $PwdExpireIn = "Never Expires"
        $PwdExpiryDate = "-"
        $PwdExpiresIn = "-"
    }
    #Calculating Password since last set
    $PwdSinceLastSet = (New-TimeSpan -Start $PwdLastChange).Days
    #Filter for enabled users
    if(($EnabledUsersOnly.IsPresent) -and ($_.AccountEnabled -eq $false))
    {
        return
    }
    #Filter for user with Password nerver expires
    if(($PwdNeverExpires.IsPresent) -and ($PwdExpireIn -ne "Never Expires"))
    {
        return
    }
 
    #Filter for password expired users
    if(($PwdExpired.IsPresent) -and (($PwdExpiresIn -ge 0) -or ($PwdExpiresIn -eq "-")))
    { 
        return
    }

    #Filter for licensed users
    if(($LicensedUserOnly.IsPresent) -and ($LicenseStatus -eq "Unlicensed"))
    {
        return
    }

    #Filter for soon to expire pwd users
    if(($SoonToExpire -ne "") -and (($PwdExpiryDate -eq "-") -or ($SoonToExpire -lt $PwdExpiresIn) -or ($PwdExpiresIn -lt 0)))
    { 
        return
    }

    #Filter for recently password changed users
    if(($RecentPwdChanges -ne "") -and ($PwdSinceLastSet -gt $RecentPwdChanges))
    {
        return
    }
    if($Federated -eq $true)
    {
        $PwdExpiryDate = "Insufficient data in O365"
        $PwdExpiresIn = "Insufficient data in O365"
    }
    $PrintedUser++ 
    #Export result to csv
    $Result = [PSCustomObject]@{'Display Name'=$_.DisplayName;'User Principal Name'=$UPN;'Pwd Last Change Date'=$PwdLastChange;'Days since Pwd Last Set'=$PwdSinceLastSet;'Pwd Expiry Date'=$PwdExpiryDate;'Friendly Expiry Time'=$PwdExpireIn ;'Days since Expiry(-) / Days to Expiry(+)'=$PwdExpiresIn;'License Status'=$LicenseStatus;'Account Status'=$AccountStatus;'Last Sign-in Date'=$LastSignInDate;'Inactive Days'=$InactiveDays}
    $Result | Export-Csv -Path $ExportCSV -Notype -Append 
}
if($UserCount -eq 0)
{
    Write-Host No records found
}
else
{
    Write-Host "`nThe output file contains " -NoNewline
    Write-Host  $PrintedUser users. -ForegroundColor Green
    if((Test-Path -Path $ExportCSV) -eq "True") 
    {
        Write-Host `n "The Output file availble in:" -NoNewline -ForegroundColor Yellow; Write-Host "$ExportCSV" `n 
   
        $Prompt = New-Object -ComObject wscript.shell   
        $UserInput = $Prompt.popup("Do you want to open output file?",` 0,"Open Output File",4)   
        if ($UserInput -eq 6)   
        {   
            Invoke-Item "$ExportCSV"   
        } 
    }
}

Disconnect-MgGraph | Out-Null
