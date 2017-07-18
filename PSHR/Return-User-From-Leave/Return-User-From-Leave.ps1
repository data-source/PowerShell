#Load Incoming JSON
	param (
        	[string]$user = 'defaultUPN',
        	[string]$name = 'Firstname Lastname',
	     	[string]$firstname = 'default firstname',
	      	[string]$lastname = 'default lastname',
        	[string]$title = 'default title',
		[string]$adpath = 'CN=Users,DC=COMPANY,DC=COM',
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

function JiraComment {
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
Invoke-JiraIssueTransition -Issue $issue -Transition 161
Get-JiraSession | Remove-JiraSession
}

#Load Jira Session
$Jira_Username = "jiraps"
$Jira_Password = Get-Content c:\scripts\ps\PSHR-Credentials\jira.txt | convertto-securestring
$Jira_Cred = new-object System.Management.Automation.PSCredential ($Jira_Username, $Jira_Password)
Set-JiraConfigServer -Server 'https://jira.company.com'

#Load connection variables
$DC = "DC"
$Username = "domain\user"
$Password = Get-Content c:\scripts\ps\PSHR-Credentials\admin.txt | convertto-securestring
$Cred = new-object System.Management.Automation.PSCredential ($Username, $Password)
 
#Initiate Remote PS Session to local DC
$ADPowerShell = New-PSSession -ComputerName $DC -Authentication Negotiate -Credential $Cred
 
#Import-Module ActiveDirectory
$env:ADPS_LoadDefaultDrive = 0
Invoke-Command -Session $ADPowerShell -scriptblock { import-module ActiveDirectory }
Import-PSSession -Session $ADPowerShell -Module ActiveDirectory -AllowClobber -ErrorAction Stop
 
#AD Username
$Employee = "$user"
$EmployeeDetails = Get-ADUser $Employee -properties *
"$EmployeeDetails"

Try { 

#Re-Enable AD Account
"Re-enabling $Employee Active Directory Account."
Enable-ADAccount $Employee
$Reply = "Re-enabled AD Account"
JiraComment -issue $issue -comment "$Reply"
Write-Log "$Reply"

#Move to original OU
"Moved $Employee back to original OU: $adpath "
Move-ADObject -Identity $EmployeeDetails.DistinguishedName -targetpath $adpath
$Reply = "Moved back to original user's OU: $adpath"
JiraComment -issue $issue -comment "$Reply"
Write-Log "$Reply"
}
Catch {
	$ErrorMessage = $_.Exception.InnerException
    	$Reply = "Something went wrong, please check Error: $ErrorMessage "
    	Write-Log "$Reply"
	JiraComment -issue $issue -comment "$Reply"
   	 SendToError
}

#Reload Jira Session and transition issue to next step
New-JiraSession -Credential $Jira_Cred
Invoke-JiraIssueTransition -Issue $issue -Transition 121

#Disconnect Sessions
Remove-PSSession $ADPowerShell
Get-JiraSession | Remove-JiraSession
