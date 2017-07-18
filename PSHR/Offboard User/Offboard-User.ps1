#Load Incoming JSON
	param (
        [string]$user = 'defaultUPN',
      	[string]$issue = 'SD-001',
	[string]$tol = 'Definite'
    ) 

#Load Functions
Function Write-Log
{
Param ([string]$Msg)
$dateTime = Get-Date -UFormat "%c"
$Msg = $dateTime + ":" + $Msg
Add-Content $logPath "$Msg"
}
$logPath = "C:\scripts\ps\PSHR-Issue-Logs\" + $Issue + ".log"

function JiraComment
{
param( [string]$issue, [string]$comment)
"Calling JiraComment with variables | issue = " + $issue + " And Text = " + $comment
[string]$cmd1 = '.\curl --%  -D- -u user:password -X PUT -d "{\"update\": {\"comment\": [{\"add\": {\"body\":\"' + $comment+ '\"}}]}}"'
[string]$cmd2 = ' -H "Content-Type: application/json" https://jira.company.com/rest/api/2/issue/{0}' -f $issue;
$all_cmds = "$cmd1 $cmd2 "
Invoke-Expression $all_cmds
}

function SendToError
{
New-JiraSession -Credential $Jira_Cred
Invoke-JiraIssueTransition -Issue $issue -Transition 141
Get-JiraSession | Remove-JiraSession
}

#Load Jira Session
$Jira_Username = "jiraps"
$Jira_Password = Get-Content c:\scripts\ps\PSHR-Credentials\jira.txt | convertto-securestring
$Jira_Cred = new-object System.Management.Automation.PSCredential ($Jira_Username, $Jira_Password)
Set-JiraConfigServer -Server 'https://jira.company.com'

#Load user account
$name= Get-ADUser –Identity "$user"
$UPNSufix = "@company.com" 
$DC = "DC"
$Username = "domain\user"
$Password = Get-Content c:\scripts\ps\PSHR-Credentials\admin.txt | convertto-securestring
$Cred = new-object System.Management.Automation.PSCredential $Username, $Password

#Initiate Remote PS Session to local DC
$ADPowerShell = New-PSSession -ComputerName $DC -Authentication Negotiate -Credential $Cred
 
#Import-Module ActiveDirectory
$env:ADPS_LoadDefaultDrive = 0
Invoke-Command -Session $ADPowerShell -scriptblock { import-module ActiveDirectory }
Import-PSSession -Session $ADPowerShell -Module ActiveDirectory -AllowClobber -ErrorAction Stop
 
#Connect to O365 Online
$Username = "admin@Company.onmicrosoft.com"
$Password = Get-Content c:\scripts\ps\PSHR-Credentials\O365.txt | convertto-securestring
$Cred = new-object System.Management.Automation.PSCredential ($Username, $Password)
$sessionOption = New-PSSessionOption -SkipRevocationCheck -SkipCACheck -SkipCNCheck
$O365Session = New-PSSession -ConfigurationName Microsoft.Exchange -ConnectionUri https://outlook.office365.com/powershell-liveid/ -Credential $Cred -Authentication Basic -AllowRedirection -SessionOption $sessionOption
Import-PSSession $O365Session

#Import Azure Active Directory module into PowerShell session.
Import-Module MSOnline -Cmdlet Get-MsolUser,Set-MsolUserLicense
Start-Sleep -s 4
	
#Establish Online Services connection to Azure Active Directory
Connect-MsolService -Credential $Cred
Start-Sleep -s 4

" | Disable Active Directory User Account & Enable Out Of Office | "
 
#Get Variables
$DisabledDate = Get-Date
$LeaveDate = Get-Date -Format "dddd dd MMMM yyyy"
$DisabledBy = Get-ADUser "$env:username" -properties Mail
$DisabledByEmail = $DisabledBy.Mail
 
#AD Username
$Employee = "$user"
$EmployeeDetails = Get-ADUser $Employee -properties *

#Move to Extended Leave OU if leave is temporary
if ($tol -eq "Temporary" ) {
Try {
"Step1. Modifying user description for audit purposes"
Set-ADUser $Employee -Description "Disabled by $($DisabledBy.name) on $DisabledDate Ticket $issue"
$Reply = "Processing User Description: Disabled by $($DisabledBy.name) on $DisabledDate for Ticket $issue" 
Write-Log "$Reply"
JiraComment -issue $issue -comment "$Reply"

"Step2. Disabling $Employee Active Directory Account."
Disable-ADAccount $Employee -ErrorAction Stop
        $Reply = "Disabled AD Account" 
		Write-Log "$Reply"
		JiraComment -issue $issue -comment "$Reply"

"Step3. Moving $Employee to the Extended Leave OU."
    Move-ADObject -Identity $EmployeeDetails.DistinguishedName -targetpath "OU=Extended Leave,OU=Disabled User Accounts,OU=User Account,OU=Accounts,OU=COMPANY OU,DC=company,DC=com" -ErrorAction Stop
        Write-Log "$Reply"
        JiraComment -issue $issue -comment "$Reply"
        }
Catch {
	$ErrorMessage = $_.Exception.InnerException
    $Reply = "Something went wrong, please check Error: $ErrorMessage "
    Write-Log "$Reply"
	JiraComment -issue $issue -comment "$Reply"
    SendToError    
}

}
Else {
    Try {
		"Refreshing Employee Details for Exchange Modification."
		Get-ADUser $Employee -Properties Description | Format-List Name, Enabled, Description

		"Step 1. Setting Exchange Out Of Office Auto-Responder."
		Set-MailboxAutoReplyConfiguration -Identity $EmployeeDetails.Mail -AutoReplyState enabled -ExternalAudience all -InternalMessage "Please note that I no longer work for company as of $LeaveDate."
        $Reply = "Set Exchange Out Of Office Auto-Responder"
        Write-Log "$Reply"
        JiraComment -issue $issue -comment "$Reply"

		"Step 2. Disabling POP,IMAP, OWA and ActiveSync access for $User" 
		Set-CasMailbox -Identity $EmployeeDetails.mail -OWAEnabled $false -POPEnabled $false -ImapEnabled $false -ActiveSyncEnabled $false
        $Reply = "Disabled POP, IMAP, OWA and ActiveSync"
        Write-Log "$Reply"
        JiraComment -issue $issue -comment "$Reply"

		"Step 3. Reclaim Licence" 
		$msolUser = "$user$UPNSufix"
		$userLicense = Get-MsolUser -UserPrincipalName $msolUser
		Set-MsolUserLicense -UserPrincipalName "$user$UPNSufix" -RemoveLicenses LayaHealthcare:ENTERPRISEWITHSCAL
        $Reply = "Reclaimed O365 License"
        Write-Log "$Reply"
        JiraComment -issue $issue -comment "$Reply"
     
		"Step 4. Placing mailbox $($EmployeeDetails.name) into Litigation hold for 30 days" 
		Set-Mailbox -Identity $EmployeeDetails.mail -LitigationHoldEnabled $true -LitigationHoldDuration 30
        $Reply = "User mailbox placed in litigation hold for 30 days"
        Write-Log "$Reply"
        JiraComment -issue $issue -comment "$Reply"

		"Step 5. Hiding $($EmployeeDetails.name) from Global Address lists" 
		Set-Mailbox -Identity $EmployeeDetails.mail -HiddenFromAddressListsEnabled $true -Verbose
        $Reply = "Recipient hidden from Global Address List"
        Write-Log "$Reply"
        JiraComment -issue $issue -comment "$Reply"

		#Connect to LyncFront 
		$Username = "domain\lync-admin"
		$Password = Get-Content c:\scripts\ps\PSHR-Credentials\lyncfront.txt | convertto-securestring
		$Cred = new-object System.Management.Automation.PSCredential ($Username, $Password)
		$LyncSession = New-PSSession -ConnectionUri https://lyncfront.company.com/ocsPowerShell -Credential $Cred
		Import-PsSession $LyncSession -AllowClobber

		"Step 6. Disabling Lync"
		Disable-CsUser -Identity "$name"
        $Reply = "Disabled Lync"
        Write-Log "$Reply"
        JiraComment -issue $issue -comment "$Reply"
    
		"Step 7.Delete Active Directory User Account " 
		Remove-ADUser $user -confirm:$false
        $Reply = "Deleted AD user account"
        Write-Log "$Reply"
        JiraComment -issue $issue -comment "$Reply"
}
Catch {
		$ErrorMessage = $_.Exception.InnerException
		$Reply = "Something went wrong, please check Error: $ErrorMessage "
		Write-Log "$Reply"
		JiraComment -issue $issue -comment "$Reply"
		SendToError
	}
}
		"Step 8. Delete Citrix folders"
		# Search for user folder on Citrix file server and delete
		$server = "\\Server"
		$locations = @("$server\e$\UserFolderRedir","$server\e$\UsersProfileDEV2016","$server\e$\UsersProfiles","$server\f$\OutlookOSTs")
		$hasfolder = Test-Path -Path $locations -Filter $user
		If ($hasfolder -eq $true) {
			"Processing Citrix folder deletion for $user" 
			ForEach ($location in $locations) {
				Try {
				Get-ChildItem -Path $location -Recurse -Filter $user | Remove-Item -Recurse -Force -ErrorAction stop
				}
				Catch {
				$ErrorMessage = $_.Exception.InnerException
				$Reply = "Something went wrong on $user, please check Error: $ErrorMessage "
				Write-Log  "$Reply"
				JiraComment -issue $issue -comment "$Reply"
				SendToError    
				}
			}
			$Reply = "Processed Citrix folder deletion for $user "
			JiraComment -issue $issue -comment "$Reply"
			Write-Log  "$Reply"
		}
		Else { 
			"No Citrix folder to delete on Server"
		}
		
		"Step 9. Delete H Drive"
		# Search for user folder on FSPServer and delete
		$server = "\\FSPServer"
		$locations = @("$server\Users","$server\User Shares")
		$hasfolder = Test-Path -Path $locations -Filter $user
		If ($hasfolder -eq $true) {
			"Processing H Drive deletion for $user" 
			ForEach ($location in $locations) {
				Try {
				Get-ChildItem -Path $location -Filter $user | Remove-Item -Recurse -Force -ErrorAction stop 
				}
				Catch {
				$ErrorMessage = $_.Exception.InnerException
				$Reply = "Something went wrong on $user, please check Error: $ErrorMessage "
				Write-Log  "$Reply"
				JiraComment -issue $issue -comment "$Reply"
				SendToError    
				}
			}
			$Reply = "Processed H Drive folder deletion for $user "
			JiraComment -issue $issue -comment "$Reply"
			Write-Log  "$Reply"
		}
		Else { 
			"No H Drive folder to delete on FSPServer"
		}

#Reload Jira Session and transition issue to next step
New-JiraSession -Credential $Jira_Cred
Invoke-JiraIssueTransition -Issue $issue -Transition 121

#Disconnect Sessions
Remove-PSSession $O365Session
Remove-PSSession $ADPowerShell
Remove-PsSession $LyncSession
Get-JiraSession | Remove-JiraSession
