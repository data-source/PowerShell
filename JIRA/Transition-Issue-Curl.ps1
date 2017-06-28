function CustomFieldUpdate 
{
param( [string]$issue, [string]$customfield, [string]$customfield_value)

"Calling CustomFieldUpdate with variables | issue = " + $issue + " And Text = " + $comment
#[string]$cmd1 = '.\curl --%  -D- -u user:pass -X PUT -d "{	\"update\": {\"comment\": [{\"add\": {\"body\":\"' + $comment+ '\"}}]}}"'
[string]$cmd1 = '.\curl --%  -D- -u user:pass -X PUT -d "{ \"fields\": { \"' + $customfield + '\":\"' + $customfield_value + '\"}}"'
[string]$cmd2 = ' -H "Content-Type: application/json" https://jira.company.com/rest/api/2/issue/{0}' -f $issue;
$all_cmds = "$cmd1 $cmd2 "
$all_cmds
Invoke-Expression $all_cmds
}
