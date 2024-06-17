param (
    [Parameter(Mandatory = $false)]
    [string]$Meeting_Id, 
    [string]$userUPN,
    [Nullable[DateTime]]$StartDate,
    [Nullable[DateTime]]$EndDate,
    [string]$UserName,
    [string]$Password,
    [string]$Organization,
    [string]$ClientId,
    [string]$CertificateThumbPrint
)

Function Connect_Module {
    #Check for Exchange Online module installation
    $ExchangeModule = Get-Module ExchangeOnlineManagement -ListAvailable
    if($ExchangeModule.count -eq 0) {
        Write-Host ExchangeOnline module is not available -ForegroundColor Yellow
        $confirm = Read-Host Do you want to Install ExchangeOnline module? [Y] Yes  [N] No
        if($confirm -match "[Yy]") {
            Write-Host "Installing ExchangeOnline module ..."
            Install-Module ExchangeOnlineManagement -Repository PSGallery -AllowClobber -Force -Scope CurrentUser
            Import-Module ExchangeOnlineManagement
        }    
        else {
            Write-Host "ExchangeOnline Module is required. To Install ExchangeOnline module use 'Install-Module ExchangeOnlineManagement' cmdlet."
            Exit
        }
    }

    #Connect Exchange Online module
    Write-Host "`nConnecting Exchange Online module ..." -ForegroundColor Yellow
    if(($UserName -ne "") -and ($Password -ne "")) {
        $SecuredPassword = ConvertTo-SecureString -AsPlainText $Password -Force
        $Credential  = New-Object System.Management.Automation.PSCredential $UserName,$SecuredPassword
        Connect-ExchangeOnline -Credential $Credential 
    }
    elseif($Organization -ne "" -and $ClientId -ne "" -and $CertificateThumbprint -ne "") {
        Connect-ExchangeOnline -AppId $ClientId -CertificateThumbprint $CertificateThumbprint -Organization $Organization -ShowBanner:$false
    }
    else {
        Connect-ExchangeOnline
    }
}

$MaxStartDate = ((Get-Date).AddDays(-180)).Date

#Retrieving Audit log for the past 180 days
if(($StartDate -eq $null) -and ($EndDate -eq $null)) {
    $EndDate = (Get-Date)  #.Date
    $StartDate = $MaxStartDate
}

#Getting start date for audit report
While($true) {
    if ($StartDate -eq $null) {
        $StartDate = Read-Host Enter start time for report generation '(Eg:MM/DD/YYYY)'
    }
    Try {
        $Date=[DateTime]$StartDate
        if($Date -ge $MaxStartDate) { 
            break
        }
        else {
            Write-Host `nAudit can be retrieved only for the past 180 days. Please select a date after $MaxStartDate -ForegroundColor Red
            return
        }
    }
    Catch {
        Write-Host `nNot a valid date -ForegroundColor Red
    }
}

#Getting end date to retrieve audit log
While($true) {
    if ($EndDate -eq $null) {
        $EndDate = Read-Host Enter End time for report generation '(Eg: MM/DD/YYYY)'
    }
    Try {
        $Date=[DateTime]$EndDate
        if($EndDate -lt ($StartDate)) {
            Write-Host End time should be later than start time -ForegroundColor Red
            return
        }
        break
    }
    Catch {
      Write-Host `nNot a valid date -ForegroundColor Red
    }
}

#get file directory
$outputFilePath =  $PSScriptRoot
$OutputCSV = "$outputFilePath\TeamsDeviceUsageReport_$((Get-Date -format yyyy-MMM-dd-ddd` hh-mm` tt).ToString()).csv"
$IntervalTimeInMinutes = 1440    #$IntervalTimeInMinutes=Read-Host Enter interval time period '(in minutes)'
$CurrentStart = $StartDate
$CurrentEnd = $CurrentStart.AddMinutes($IntervalTimeInMinutes)

#Check whether CurrentEnd exceeds EndDate
if($CurrentEnd -gt $EndDate) {
    $CurrentEnd = $EndDate
}

if($CurrentStart -eq $CurrentEnd) {
    Write-Host Start and end time are same.Please enter different time range -ForegroundColor Red
    Exit
}

Connect_Module

# Write-Host initialize variable -ForegroundColor Green
$CurrentResultCount = 0
Write-Host `nRetrieving Teams meeting device usage from $StartDate to $EndDate... -ForegroundColor Yellow
$i = 0
$ExportResult = ""   
$ExportResults = @()  
$Operations = "MeetingParticipantDetail"

while($true) { 
    #Getting audit data for the given time range
    $Results=Search-UnifiedAuditLog -StartDate $CurrentStart -EndDate $CurrentEnd -Operations $Operations -SessionId s -SessionCommand ReturnLargeSet -ResultSize 5000
    $ResultCount=($Results | Measure-Object).count
    foreach($Result in $Results) {
        $i++
        $PrintFlag = "True"
        $AuditData = $Result.auditdata | ConvertFrom-Json
        $MeetingID = $AuditData.MeetingDetailId
        $AttendeesInfo = ($AuditData.Attendees)
        $Attendees = $AttendeesInfo.DisplayName
        $CreatedBy = $Result.UserIDs
        $AttendeesType=$AttendeesInfo.RecipientType
        $AttendeesUPN  =  $AttendeesInfo.UPN
        $JoinTime=(Get-Date($AuditData.JoinTime)).ToLocalTime()
        $LeaveTime=(Get-Date($AuditData.LeaveTime)).ToLocalTime()
        $DeviceUsed = $AuditData.DeviceInformation
        $Duration = $JoinTime - $LeaveTime
        $DurationinSeconds = ($Duration).TotalSeconds
        $TimeSpanDuration =  [timespan]::fromseconds($DurationinSeconds)
        $AttendedDuration = ("{0:hh\:mm\:ss}" -f $TimeSpanDuration)

        #Conditions for device usage report
        if(($Meeting_Id -ne "") -and ($Meeting_Id -ne $MeetingID)) {
            $PrintFlag = "False"
        }
        if(($userUPN -ne "") -and ($userUPN -ne $AttendeesUPN)) {
            $PrintFlag = "False"
        }

        #Export result to csv
        if($PrintFlag -eq "True") {
            $OutputEvents++
            $ExportResult = @{'Meeting Id' = $MeetingID;'Created By'=$CreatedBy;'Attendees' = $Attendees;'Attendees UPN' = $AttendeesUPN;'Attendee Type'=$AttendeesType;'Device Used' = $DeviceUsed;'Joined Time' = $JoinTime;'Left Time' = $LeaveTime;'Duration' = $AttendedDuration}
            $ExportResults = New-Object PSObject -Property $ExportResult  
            $ExportResults | Select-Object 'Meeting Id','Created By','Attendees','Attendees UPN','Attendee Type','Device Used','Joined Time','Left Time','Duration' | Export-Csv -Path $OutputCSV -NoTypeInformation -Append 
        }
    }

    Write-Progress -Activity "`n     Retrieving Teams meeting device usage from $StartDate to $EndDate.."`n" Processed audit record count: $i"
    $currentResultCount=$CurrentResultCount+$ResultCount
    
    if($CurrentResultCount -ge 50000) {
        Write-Host Retrieved max record for current range.Proceeding further may cause data loss or rerun the script with reduced time interval. -ForegroundColor Red
        $Confirm = Read-Host `nAre you sure you want to continue? [Y] Yes [N] No
        if($Confirm -match "[Y]") {
            Write-Host Proceeding audit log collection with data loss
            [DateTime]$CurrentStart = $CurrentEnd
            [DateTime]$CurrentEnd = $CurrentStart.AddMinutes($IntervalTimeInMinutes)
            $CurrentResultCount = 0
            if($CurrentEnd -gt $EndDate) {
                $CurrentEnd = $EndDate
            }
        }
        else {
            Write-Host Please rerun the script with reduced time interval -ForegroundColor Red
            Exit
        }
    }
    
    if($ResultCount -lt 5000) { 
        if($CurrentEnd -eq $EndDate) {
            break
        }
        $CurrentStart = $CurrentEnd 
        if($CurrentStart -gt (Get-Date)) {
            break
        }
        $CurrentEnd = $CurrentStart.AddMinutes($IntervalTimeInMinutes)
        $CurrentResultCount = 0
        if($CurrentEnd -gt $EndDate) {
            $CurrentEnd = $EndDate
        }
    }
    $ResultCount = 0
}


#Open output file after execution
If($OutputEvents -eq 0) {
    Write-Host No records found
}
else {
    Write-Host `nThe output file contains $OutputEvents audit records
    if((Test-Path -Path $OutputCSV) -eq "True") {
        Write-Host `n "The Output file availble in:" -NoNewline -ForegroundColor Yellow; Write-Host "$OutputCSV" `n 
        $Prompt = New-Object -ComObject wscript.shell   
        $UserInput = $Prompt.popup("Do you want to open output file?",0,"Open Output File",4)   
        If ($UserInput -eq 6) {   
            Invoke-Item "$OutputCSV"   
        } 
    }
}


#Disconnect Exchange Online session
Disconnect-ExchangeOnline -Confirm:$false
