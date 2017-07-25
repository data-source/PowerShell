#Load Incoming JSON
	param (
        	[string]$servername = 'server name',
		[string]$cluster = ' Cluster_Dev',
    	  	[string]$template = 'Windows Server 2012 R2 - V1.1',
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
$logPath = "C:\scripts\ps\PSINFRA-Issue-Logs\" + $Issue + ".log"
$saved=$global:ErrorActionPreference
$global:ErrorActionPreference = 'SilentlyContinue'

function JiraComment
{
param( [string]$issue, [string]$comment)

"Calling JiraComment with variables | issue = " + $issue + " And Text = " + $comment
[string]$cmd1 = '.\curl --%  -D- -u user:password -X PUT -d "{\"update\": {\"comment\": [{\"add\": {\"body\":\"' + $comment+ '\"}}]}}"'
[string]$cmd2 = ' -H "Content-Type: application/json" https://jira.company.com/rest/api/2/issue/{0}' -f $issue;
$all_cmds = "$cmd1 $cmd2 "
$all_cmds
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
$all_cmds
Invoke-Expression $all_cmds
}

function SendToError
{
New-JiraSession -Credential $Jira_Cred
Invoke-JiraIssueTransition -Issue $issue -Transition 121
Get-JiraSession | Remove-JiraSession
}

#Load Jira Session
$Jira_Username = "jiraps"
$Jira_Password = Get-Content c:\scripts\ps\PSHR-Credentials\jira.txt | convertto-securestring
$Jira_Cred = new-object System.Management.Automation.PSCredential ($Jira_Username, $Jira_Password)
Set-JiraConfigServer -Server 'https://jira.company.com'

#Load snap-in
Add-PSSnapin VMware.VimAutomation.Core 
Start-Sleep -s 10

#Connect to vCenter
$vcenter = "vcenterhost"
$User = "domain\vsphere-account"
$PasswordFile = "C:\scripts\ps\PSINFRA-Credentials\vsphere.txt"
$KeyFile = "C:\scripts\ps\PSINFRA-Credentials\AES.key"
$key = Get-Content $KeyFile
$VIcred = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $User, (Get-Content $PasswordFile | ConvertTo-SecureString -Key $key)
Connect-VIServer $vcenter -Credential $VIcred -WarningAction SilentlyContinue

#Jira Comment on task start 
$Reply = "Deploying Virtual Machine "
JiraComment -issue $issue -comment "$Reply"

#Create VM
Try {
New-VM -Name $servername -Template $template -ResourcePool $cluster -Datastore '$datastore' -DiskStorageFormat EagerZeroedThick
}
Catch {
	$ErrorMessage = $_.Exception.InnerException
}
Finally {
if (!$error) {
    Write-Log "No Error Occured"
    $Reply = "Deployed Virtual Machine with Name: [$servername] using Template: [$template] on Cluster: [$cluster] "
    JiraComment -issue $issue -comment "$Reply"
}
else { 
    $Reply = "Issue caught while deploying VM: $ErrorMessage"
    JiraComment -issue $issue -comment "$Reply"
	Write-Log "$Reply"
	SendToError 
}
}


#Transition Issue 
New-JiraSession -Credential $Jira_Cred
Invoke-JiraIssueTransition -Issue $issue -Transition 131
Get-JiraSession | Remove-JiraSession

Disconnect-VIServer -Server $vcenter
