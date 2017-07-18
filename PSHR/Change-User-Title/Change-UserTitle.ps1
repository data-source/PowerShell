#Load Incoming JSON
	param (
        [string]$user = 'defaultUPN',
        [string]$newtitle = 'default new title',
        [string]$userdn = 'User DN',
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
Invoke-JiraIssueTransition -Issue $issue -Transition 151
Get-JiraSession | Remove-JiraSession
}

#Error Handling Preferences
$saved=$global:ErrorActionPreference
$global:ErrorActionPreference = 'SilentlyContinue'

#Load Jira Session
$Jira_Username = "jiraps"
$Jira_Password = Get-Content c:\scripts\ps\PSHR-Credentials\jira.txt | convertto-securestring
$Jira_Cred = new-object System.Management.Automation.PSCredential ($Jira_Username, $Jira_Password)
Set-JiraConfigServer -Server 'https://jira.company.com'
	
#Load connection variables 
$DC = "dc"
$Username = "domain\user"
$Password = Get-Content c:\scripts\ps\PSHR-Credentials\admin.txt | convertto-securestring
$Cred = new-object System.Management.Automation.PSCredential ($Username, $Password)

#Initiate Remote PS Session to local DC
$ADPowerShell = New-PSSession -ComputerName $DC -Authentication Negotiate -Credential $Cred
 
#Import-Module ActiveDirectory
$env:ADPS_LoadDefaultDrive = 0
"Importing Active Directory PowerShell Commandlets"
Invoke-Command -Session $ADPowerShell -scriptblock { import-module ActiveDirectory }
Import-PSSession -Session $ADPowerShell -Module ActiveDirectory -AllowClobber -ErrorAction Stop

# Modify AD Account
"Setting user: $User new Title"
Try {
$global:ErrorActionPreference = 'stop'
Set-ADUser -Identity $user -title "$newtitle" -description "$newtitle" -server dc -ErrorAction Stop
}
Catch {
	$ErrorMessage = $_.Exception.InnerException
}
Finally { 
if (!$error) {
        $Reply = "Set user with new title '$newtitle' " 
		Write-Log "$Reply"
		JiraComment -issue $issue -comment "$Reply"
    }
	else {
		$Reply = "Issue caught while setting user with new title: $ErrorMessage "
		JiraComment -issue $issue -comment "$Reply"
		Write-Log "$Reply"
		SendToError
        exit
    }
$global:ErrorActionPreference=$saved
}

#Reload Jira Session and transition issue to next step
New-JiraSession -Credential $Jira_Cred
Invoke-JiraIssueTransition -Issue $issue -Transition 21

#Disconnect Session
Remove-PsSession $ADPowerShell
Get-JiraSession | Remove-JiraSession
