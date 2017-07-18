#Load Incoming JSON
	param (
        [string]$upn = 'defaultUPN',
        [string]$name = 'Firstname Lastname',
        [string]$issue = "SD-000"
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
$saved=$global:ErrorActionPreference
$global:ErrorActionPreference = 'SilentlyContinue'

function JiraComment
{
param( [string]$issue, [string]$comment)
"Calling JiraComment with variables | issue = " + $issue + " And Text = " + $comment
[string]$cmd1 = '.\curl --%  -D- -u user:password -X PUT -d "{\"update\": {\"comment\": [{\"add\": {\"body\":\"' + $comment+ '\"}}]}}"'
[string]$cmd2 = ' -H "Content-Type: application/json" https://jira.company.com/rest/api/2/issue/{0}' -f $issue;
$all_cmds = "$cmd1 $cmd2 " 
Invoke-Expression $all_cmds
}

function CustomFieldUpdate 
{
param( [string]$issue, [string]$customfield, [string]$customfield_value)
"Calling CustomFieldUpdate with variables | issue = " + $issue + " And Text = " + $comment
#[string]$cmd1 = '.\curl --%  -D- -u user:password -X PUT -d "{	\"update\": {\"comment\": [{\"add\": {\"body\":\"' + $comment+ '\"}}]}}"'
[string]$cmd1 = '.\curl --%  -D- -u user:password -X PUT -d "{ \"fields\": { \"' + $customfield + '\":\"' + $customfield_value + '\"}}"'
[string]$cmd2 = ' -H "Content-Type: application/json" https://jira.company.com/rest/api/2/issue/{0}' -f $issue;
$all_cmds = "$cmd1 $cmd2 "
Invoke-Expression $all_cmds
}

function SendToError
{
New-JiraSession -Credential $Jira_Cred
Invoke-JiraIssueTransition -Issue $issue -Transition 281
Get-JiraSession | Remove-JiraSession
}

Write-Log " | Starting o365.ps1 // Office 365 | "

#Set Variables
$365domain = "@Company.mail.onmicrosoft.com"
$UPNSufix = "@company.com"

#Load Jira Session
$Jira_Username = "jiraps"
$Jira_Password = Get-Content c:\scripts\ps\PSHR-Credentials\jira.txt | convertto-securestring
$Jira_Cred = new-object System.Management.Automation.PSCredential ($Jira_Username, $Jira_Password)
Set-JiraConfigServer -Server 'https://jira.company.com'

#Connect to O365 Online
$Username = "admin@Company.onmicrosoft.com"
$Password = Get-Content c:\scripts\ps\PSHR-Credentials\O365.txt | convertto-securestring
$Cred = new-object System.Management.Automation.PSCredential ($Username, $Password)
$sessionOption = New-PSSessionOption -SkipRevocationCheck -SkipCACheck -SkipCNCheck
$O365Session = New-PSSession -ConfigurationName Microsoft.Exchange -ConnectionUri https://outlook.office365.com/powershell-liveid/ -Credential $Cred -Authentication Basic -AllowRedirection -SessionOption $sessionOption
#Export-PSSession $O365Session -outputmodule o365 -Force
Start-Sleep -s 5
Import-PSSession $O365Session
Start-Sleep -s 10
	
#This first command will import the Azure Active Directory module into your PowerShell session.
Import-Module MSOnline -Cmdlet Set-MsolUser,Set-MsolUserLicense,Get-Mailbox
Start-Sleep -s 4
	
#Establishes Online Services connection to Azure Active Directory  
Connect-MsolService -Credential $Cred
Start-Sleep -s 20
$checkifmailboxexists = Get-Mailbox "$upn$UPNSufix" -ErrorAction SilentlyContinue
	do	{
		$checkifmailboxexists
		Sleep 120
		Write-Output "Checking if Mailbox exists"
		}	While (!$checkifmailboxexists)

#Set Location with correct country code
Try {
$global:ErrorActionPreference = 'stop'
Set-MsolUser -UserPrincipalName "$upn$UPNSufix" -UsageLocation UK -ErrorAction Stop
}
Catch {
	$ErrorMessage = $_.Exception.InnerException
        
}
Finally {
if (!$error) {
        $Reply = "Office 365 user created, locale set to UK"
		Write-Log "$Reply"
        JiraComment -issue $issue -comment "$Reply"
}
else {
		$Reply = "Issue caught while attempting to create 365 Account: $ErrorMessage "
		JiraComment -issue $issue -comment "$Reply"
		Write-Log "$Reply"
		SendToError
        exit
}
$global:ErrorActionPreference=$saved
}
	
#Assign Correct Licence
#Company:ENTERPRISEWITHSCAL \\This license is the other type
$error.clear()
Try {
$global:ErrorActionPreference = 'stop'
Set-MsolUserLicense -UserPrincipalName "$upn$UPNSufix" -AddLicenses Company:ENTERPRISEPACK -ErrorAction Stop
}
Catch {
	$ErrorMessage = $_.Exception.InnerException
}
Finally {
if (!$error) {
        $Reply = "User License assigned"
        Write-Log "$Reply"
		JiraComment -issue $issue -comment "$Reply"
    }
	else {
		$Reply = "Issue caught while attempting to assign License: $ErrorMessage "
		JiraComment -issue $issue -comment "$Reply"
		Write-Log "$Reply"
		SendToError
        exit
}
$global:ErrorActionPreference=$saved
}

#Change Archive Rule to 6 Months
$error.clear()
Try {
$global:ErrorActionPreference = 'stop'
Set-Mailbox "$name" -RetentionPolicy "6 Month Archive Policy" -ErrorAction Stop
}
Catch {
	$ErrorMessage = $_.Exception.InnerException
}
Finally {
if (!$error) {
        $Reply = "6 Month Archive Policy Set"
		Write-Log "$Reply"
        JiraComment -issue $issue -comment "$Reply"
    }
	else {
		$Reply = "Issue caught while attempting to set archive policy: $ErrorMessage "
		JiraComment -issue $issue -comment "$Reply"
		Write-Log "$Reply"
		SendToError
}
$global:ErrorActionPreference=$saved
}

#Disable Exchange Active Sync
$error.clear()
Try {
$global:ErrorActionPreference = 'stop'
Set-CASMailbox -Identity "$name" -ActiveSyncEnabled $false -ErrorAction Stop
}
Catch {
	$ErrorMessage = $_.Exception.InnerException
}
Finally {
if (!$error) {
        $Reply = "ActiveSync successfully disabled"
		Write-Log "$Reply"
        JiraComment -issue $issue -comment "$Reply"
    }
	else {
		$Reply = "Issue caught while attempting to disable ActiveSync: $ErrorMessage "
		JiraComment -issue $issue -comment "$Reply"
		Write-Log "$Reply"
		SendToError
        exit
}
$global:ErrorActionPreference=$saved
}

#Disable Exchange OWA
$error.clear()
Try {
$global:ErrorActionPreference = 'stop'
Set-CASMailbox -Identity "$name" -OWAEnabled $false -ErrorAction Stop
}
Catch {
	$ErrorMessage = $_.Exception.InnerException
}
Finally {
if (!$error) {
        $Reply = "OWA successfully disabled"
		Write-Log "$Reply"
        JiraComment -issue $issue -comment "$Reply"
    }
else 
{
	$Reply = "Issue caught while attempting to disable OWA: $ErrorMessage "
	JiraComment -issue $issue -comment "$Reply"
	Write-Log "$Reply"
	SendToError
    exit
}
$global:ErrorActionPreference=$saved
}
	
#Check that the remote account exists, then put this in custom fields in JIRA.
$msolUser = "$upn$UPNSufix"
$userLicense = Get-MsolUser -UserPrincipalName $msolUser
$License = (Get-MsolUser -UserPrincipalName $msolUser).Licenses.AccountSKUid
$mailbox = Get-CASMailbox -Identity "$msolUser"
$activesync_enabled = $mailbox.ActiveSyncEnabled
$owa_enabled = $mailbox.OWAEnabled
$retention = Get-Mailbox "$name"
$retention_policy = $retention.retentionpolicy
$validity = (Get-CASMailbox -Identity "$msolUser").IsValid
	
#Update Jira 365 fields 
CustomFieldUpdate -issue $issue -customfield "customfield_12005" -customfield_value "$validity"
CustomFieldUpdate -issue $issue -customfield "customfield_12007" -customfield_value "$License"
CustomFieldUpdate -issue $issue -customfield "customfield_12008" -customfield_value "$activesync_enabled"
CustomFieldUpdate -issue $issue -customfield "customfield_12009" -customfield_value "$owa_enabled"
CustomFieldUpdate -issue $issue -customfield "customfield_12010" -customfield_value "$retention_policy"

#Transition issue to next step
New-JiraSession -Credential $Jira_Cred
Invoke-JiraIssueTransition -Issue $issue -Transition 221

#Disconnect sessions 
Remove-PsSession $O365session
Get-JiraSession | Remove-JiraSession
