#Load Incoming JSON
    param (
        [string]$upn = 'defaultUPN',
        [string]$name = 'Firstname Lastname',
	[string]$issue = 'SD-001'
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
	
Write-Log " | Starting Lync.ps1 // Lync Account | "

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
	
#Connect to LyncFront 
$Username = "domain\lync-admin"
$Password = Get-Content c:\scripts\ps\PSHR-Credentials\lyncfront.txt | convertto-securestring
$Cred = new-object System.Management.Automation.PSCredential ($Username, $Password)
$LyncSession = New-PSSession -ConnectionUri https://lyncfront.company.com/ocsPowerShell -Credential $Cred
	
#Import-Remote cmdlets
Import-PsSession $LyncSession
	
#Load Jira Session
$Jira_Username = "jiraps"
$Jira_Password = Get-Content c:\scripts\ps\PSHR-Credentials\jira.txt | convertto-securestring
$Jira_Cred = new-object System.Management.Automation.PSCredential ($Jira_Username, $Jira_Password)
Set-JiraConfigServer -Server 'https://jira.company.com'
New-JiraSession -Credential $Jira_Cred	

Start-Sleep -s 10

# Enable lync account
$error.clear()
Try {
$Global:ErrorActionPreference = 'Stop'
Enable-CsUser -Identity "$upn@company.com" -RegistrarPool LyncFront.company.com -SipAddressType EmailAddress -ErrorAction Stop
}
Catch {
		$ErrorMessage = $_.Exception.InnerException
	}
Finally {
if (!$error) {
    $Reply = "Lync account enabled"
    Write-Log "$Reply"
	JiraComment -issue $issue -comment "$Reply" 
	CustomFieldUpdate -issue $issue -customfield "customfield_12006" -customfield_value "True"
	Invoke-JiraIssueTransition -Issue $issue -Transition 61
    }
else {
	$Reply = "Issue caught while attempting to create Lync Account: $ErrorMessage "
	JiraComment -issue $issue -comment "$Reply"
	Write-Log "$Reply"
	New-JiraSession -Credential $Jira_Cred
	Invoke-JiraIssueTransition -Issue $issue -Transition 291
    exit
}
$global:ErrorActionPreference=$saved
}
	
#Disconnect Sessions
Remove-PsSession $LyncSession
Get-JiraSession | Remove-JiraSession
