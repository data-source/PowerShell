#Load Incoming JSON
param (
        [string]$upn = 'defaultUPN',
        [string]$name = 'Firstname Lastname',
		[string]$issue = 'SD-000'
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

Write-Log " | Starting Create-ExchangeMailbox.ps1 / Local Exchange | "

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
Invoke-JiraIssueTransition -Issue $issue -Transition 271
Get-JiraSession | Remove-JiraSession
}

#Set variables 
$365domain = "@Company.mail.onmicrosoft.com"
$UPNSufix = "@company.com"
$Pass = "password"
$UserPass = $Pass | ConvertTo-SecureString -AsPlainText –Force

#Load Jira Session
$Jira_Username = "jiraps"
$Jira_Password = Get-Content c:\scripts\ps\PSHR-Credentials\jira.txt | convertto-securestring
$Jira_Cred = new-object System.Management.Automation.PSCredential ($Jira_Username, $Jira_Password)
Set-JiraConfigServer -Server 'https://jira.company.com'

#Connect to local exchange (EXCH)
$Username = "domain\user"
$Password = Get-Content c:\scripts\ps\PSHR-Credentials\admin.txt | convertto-securestring 
$Cred = new-object System.Management.Automation.PSCredential ($Username, $Password)
$ExchangeSession = New-PSSession -ConfigurationName Microsoft.Exchange -ConnectionUri http://EXCH.company.com/PowerShell/ -Authentication Kerberos -Credential $Cred
Import-PSSession $ExchangeSession -AllowClobber
Start-Sleep -s 30

#Create Mailbox
Try {
$global:ErrorActionPreference = 'stop'
Enable-RemoteMailbox "$upn" -RemoteRoutingAddress "$upn$365domain" -ErrorAction Stop
}
Catch {
	$ErrorMessage = $_.Exception
}
Finally { 
if (!$error) {
        $Reply = "User $upn on premise email account sucessfully created" 
		Write-Log "$Reply"
		JiraComment -issue $issue -comment "$Reply"
    }
	else {
		$Reply = "Issue caught while attempting to Enable RemoteMailbox: $ErrorMessage "
		JiraComment -issue $issue -comment "$Reply"
		Write-Log "$Reply"
		SendToError
        exit
    }
$global:ErrorActionPreference=$saved
}

#Enable Archiving (EXCH)
$error.clear()
Try {	
$global:ErrorActionPreference = 'stop'
Enable-RemoteMailbox "$name" -Archive -ErrorAction Stop
}
Catch {
	$ErrorMessage = $_.Exception.InnerException
}
Finally {
if (!$error) 
    {
        Write-Log "Archive: No Error Occured"
    }
	else {
		$Reply = "Issue caught while attempting to Enable Archiving on EXCH: $ErrorMessage "
		JiraComment -issue $issue -comment "$Reply"
		Write-Log "$Reply"
		SendToError
        exit
    }
$global:ErrorActionPreference=$saved
}

#Load post commands variables	
$mailbox = Get-RemoteMailbox "$upn"
$archivestatus = $mailbox.ArchiveStatus
$status = $mailbox.IsValid
$address = (Get-RemoteMailbox "$upn").PrimarySmtpAddress	
"Mailbox Is Valid = $status"
"Archive in place = $archivestatus"

#Update Email Address field 
CustomFieldUpdate -issue $issue -customfield "customfield_12004" -customfield_value "$address"

#Check Dirsync Status and Synchronise local AD with Azure AD  
$state = Invoke-Command -Credential $Cred -Authentication Kerberos {Get-ADSyncConnectorRunStatus} -ComputerName ADFS –Verbose
$ErrorMessage = $_.Exception.InnerException
$ErrorActionPreference='Stop'
Start-Sleep -s 10
    
If ($state -ne $Null) {Write-Warning "A sync is already in progress"}
Else {
    Write-Output "Initializing Azure AD Delta Sync..." 
    Try {
		$Global:ErrorActionPreference = 'Stop'
        Invoke-Command -Credential $Cred -Authentication Kerberos {Start-ADSyncSyncCycle -PolicyType Delta } -ComputerName ADFS -ErrorAction Stop

        #Wait 10 seconds for the sync connector to wake up.
        Start-Sleep -Seconds 10

        #Display a progress indicator and hold up the rest of the script while the sync completes.
        While($state){
            Write-Output "." -NoNewline
            Start-Sleep -Seconds 10
        }
		Write-Log " | DirSync Succesfully Completed"
    }
    Catch {Write-Error $_}
    $HOST.UI.RawUI.Flushinputbuffer()
}

Sleep 300

#Reload Jira Session and transition issue
New-JiraSession -Credential $Jira_Cred
Invoke-JiraIssueTransition -Issue $issue -Transition 211

#Disconnect Session
Remove-PSSession $ExchangeSession	
Get-JiraSession | Remove-JiraSession
