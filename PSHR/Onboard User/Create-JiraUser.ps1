#Load Incoming JSON
param (
        [string]$user = 'defaultUPN',
	[string]$firstname = 'default firstname',
	[string]$lastname = ' default lastname',
	[string]$email = ' user@company.com',
	[string]$toc = 'permanent',
	[string]$issue = 'SD-000'
    )
	
"upn = $upn"
"user = $user"
"first name = $firstname"
"last name = $lastname"
"email = $email"
"Type of contract = $toc" 
"Issue = $issue"
	
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

Write-Log " | Starting Create-Jira.ps1  | "

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
Invoke-JiraIssueTransition -Issue $issue -Transition 81
Get-JiraSession | Remove-JiraSession
}

#Load Jira Session
$Jira_Username = "jiraps"
$Jira_Password = Get-Content c:\scripts\ps\PSHR-Credentials\jira.txt | convertto-securestring
$Jira_Cred = new-object System.Management.Automation.PSCredential ($Jira_Username, $Jira_Password)
Set-JiraConfigServer -Server 'https://jira.company.com'

#Check if user exists first
New-JiraSession -Credential $Jira_Cred
$account = Get-JiraUser -UserName $user
if ($account.name -eq $null) {
#Check if user is external contractor
if ($toc -eq "External Contractor" ) {
	New-JiraUser -UserName $user -EmailAddress "email@company.com" -DisplayName "$firstname $lastname"
	$account = Get-JiraUser $user
		if ($account.name) {
			Write-Log "New-JiraAccount: No Error Occured"
			JiraComment -issue $issue -Comment "User sucessfully created $user."
			}
		else {
			$Reply = "Issue caught while attempting to create Jira Account, check logs "
			JiraComment -issue $issue -comment "$Reply"
			Write-Log "$Reply"
			SendToError
			exit
		}
}

Else {
	New-JiraUser -UserName $user -EmailAddress $email -DisplayName "$firstname $lastname"
	$account = Get-JiraUser $user
		if ($account.name) {
			Write-Log "New-JiraAccount: No Error Occured"
			JiraComment -issue $issue -Comment "User sucessfully created $user."
			}
		else {
			$Reply = "Issue caught while attempting to create Jira Account, check logs "
			JiraComment -issue $issue -comment "$Reply"
			Write-Log "$Reply"
			SendToError
			exit
		}
}
#Transition issue
Invoke-JiraIssueTransition -Issue $issue -Transition 21
}
Else {
JiraComment -issue $issue -comment "User already exists"
SendToError
}

#Disconnect Session
Get-JiraSession | Remove-JiraSession
