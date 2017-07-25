#Load Incoming JSON
	param (
        [string]$server = 'server',
		    [string]$duration = '0',
        [string]$issue = "SD-000"
    ) 
function JiraComment
{
param( [string]$issue, [string]$comment)
"Calling JiraComment with variables | issue = " + $issue + " And Text = " + $comment
[string]$cmd1 = '.\curl --%  -D- -u user:password -X PUT -d "{\"update\": {\"comment\": [{\"add\": {\"body\":\"' + $comment+ '\"}}]}}"'
[string]$cmd2 = ' -H "Content-Type: application/json" https://jira.company.com/rest/api/2/issue/{0}' -f $issue;
$all_cmds = "$cmd1 $cmd2 "
Invoke-Expression $all_cmds
}

"DURATION = $duration"
$rounded = [math]::round($duration)
"DURATION = $rounded"

Add-Pssnapin swissnapin
$SWServer = 'solarwinds_server' 
$Username = 'user'
$Password = Get-Content c:\scripts\Solarwinds\creds.txt | convertto-securestring
$Cred = new-object System.Management.Automation.PSCredential ($Username, $Password)
$swis = Connect-Swis -Hostname $SWServer -Credential $Cred 

#Umanage node
#[System.Net.Dns]::GetHostByName("$node").HostName
Try { 
$strQuery = "SELECT uri FROM Orion.Nodes WHERE SysName LIKE '" + "$server" + "%'"
$uri = Get-SwisData $swis $strQuery
Set-SwisObject $swis $uri @{Status=9;Unmanaged=$true;UnmanageFrom=[DateTime]::UtcNow;UnmanageUntil=[DateTime]::UtcNow.AddMinutes($rounded)}
}
Catch {
		$ErrorMessage = $_.Exception.InnerException
		$Reply = "Something went wrong when unmanaging node, please check Error: $ErrorMessage "
		JiraComment -issue $issue -comment "$Reply"
	}
$Reply = "Node has been unmanaged for: $rounded min "
JiraComment -issue $issue -comment "$Reply"
