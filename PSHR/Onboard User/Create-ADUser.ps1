#Load Incoming JSON
	param (
        [string]$upn = 'defaultUPN',
        [string]$name = 'Firstname Lastname',
	    [string]$firstname = 'default firstname',
	    [string]$lastname = ' default lastname',
        [string]$title = 'default title',
		[string]$description = ' default description',
    	[string]$script = 'defaultscript.bat',
	    [string]$department = 'default department',
	    [string]$manager = 'default manager',
	    [string]$adpath = 'CN=Users,DC=COMPANY,DC=COM',
		[string]$issue = 'SD-000',
		[string]$toc = 'permanent',
		[string]$end_date = '12/08/2017'
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
Invoke-JiraIssueTransition -Issue $issue -Transition 261
Get-JiraSession | Remove-JiraSession
}

#Load Jira Session
$Jira_Username = "jiraps"
$Jira_Password = Get-Content c:\scripts\ps\PSHR-Credentials\jira.txt | convertto-securestring
$Jira_Cred = new-object -typename System.Management.Automation.PSCredential -argumentlist $Jira_Username, $Jira_Password
Set-JiraConfigServer -Server 'https://jira.company.com'

Write-Log " | Starting create_ad_user.ps1 // AD Account Creation | "

#Import-Module ActiveDirectory
$env:ADPS_LoadDefaultDrive = 0
Import-Module ActiveDirectory -Cmdlet Get-ADUser,Set-ADUser,Set-ADAccountExpiration

"0: lastname = $lastname"
"AD Path: $adpath"

#Load session variables
$upnsufix="company.com"
$userprincipal="$upn@$upnsufix"
$password = "password"
$name = "$firstname $lastname"

# Have these as_enter'd variables to be able to keep firstname / lastname case
$firstname_as_entered=$firstname
$lastname_as_entered=$lastname
$firstname=$firstname.toLower()
$lastname=$lastname.toLower()
$firstname=$firstname -replace "\s", "" 
$lastname=$lastname -replace "\s", ""
$firstname=$firstname -replace " ", ""
$lastname=$lastname -replace " ", ""

"2: lastname = $lastname"

"Checking for free username for firstname: $firstname lastname: $lastname" 
$attempt_user=$lastname
$attempt_user+=$firstname.subString(0,1)

"Checking if username is in use: $attempt_user"

$User = Get-ADUser -LDAPFilter "(sAMAccountName=$attempt_user)" -server DC
If ($User -eq $Null) {
     $User=$attempt_user
     "Found free username: $attempt_user" 
  }
Else { 
"username in use: $attempt_user" 
$attempt_user=""
$attempt_user=$lastname
$attempt_user+=$firstname.substring(0,2)
$User = Get-ADUser -LDAPFilter "(sAMAccountName=$attempt_user)" -server DC
    If ($User -eq $Null) {
     $User=$attempt_user
     "Found free username: $attempt_user"
  }
    else {
$attempt_user=""
$attempt_user=$lastname
$attempt_user+=$firstname.substring(0,3)
"Last attempt on username: $attempt_user"
$User = $attempt_user
     }
}

Write-Log "Username set as $attempt_user"

#Create-AD-User
Write-Log "Starting New-ADUser with user: $User"
Try {
$global:ErrorActionPreference = 'stop'
New-ADUser -Verbose -Name "$name" -GivenName "$firstname_as_entered" -Surname "$lastname_as_entered" -SamAccountName $User -UserPrincipalName "$User@$upnsufix" -title "$title" -description "$title" -ScriptPath "$script" -department "$department" -email $email  -manager "$manager" -Path "$adpath"  -Enabled 1 -AccountPassword (ConvertTo-SecureString $password -AsPlainText -force) -server dc -ErrorAction 'stop'
}
Catch {
	$ErrorMessage = $_.Exception.InnerException
    }
Finally {
if (!$error) {
    Write-Log "New-ADUser: No Error Occured"
    JiraComment -issue $issue -Comment "User sucessfully created $User"
    CustomFieldUpdate -issue $issue -customfield "customfield_11404" -customfield_value "$User"
    }
else {
    $Reply = "Issue caught while attempting to create AD Account: $ErrorMessage "
	JiraComment -issue $issue -comment "$Reply"
	Write-Log "$Reply"
	SendToError
    exit
} 
$global:ErrorActionPreference=$saved
}
	
#Set Password change at next logon
$error.clear()
Try {
Set-ADUser -Identity $User -ChangePasswordAtLogon $true -server dc
}
Catch {
	$ErrorMessage = $_.Exception.InnerException
}
Finally {
if (!$error) {
    Write-Log "ChangePasswordAtLogon: No Error Occured"
    }
else {
    $Reply = "Issue caught while attempting to assign ChangePasswordAtLogon: $ErrorMessage "
	JiraComment -issue $issue -comment "$Reply"
	Write-Log "$Reply"
    #No transition to Error status here as it's not a critical error./ 
}
}

#Map H:Drive in AD 
$error.clear()
Try {
Set-ADUser -Identity $User -HomeDirectory \\FSPServer\Users\$User -HomeDrive H: -server dc
}
Catch {
	$ErrorMessage = $_.Exception.InnerException
}
Finally {
if (!$error) {
    Write-Log "HomeDirectory: No Error Occured"	
}
else {
    $Reply = "Issue caught while attempting to map H:Drive: $ErrorMessage - However automation Process was not stopped, please fix manually"
	JiraComment -issue $issue -comment "$Reply"
	Write-Log "$Reply"
	#No transition to Error status here as it's not a critical error./ 
}
}

#Create User's Folder
$error.clear()
Try {
New-item -Path \\FSPServer\Users\$User -type directory -Force
}
Catch {
	$ErrorMessage = $_.Exception.InnerException
}
Finally {
if (!$error) {
    Write-Log "Create Home Folder on FSPServer: No Error Occured"
    $Reply = "Created Home Folder for $User" 
    JiraComment -issue $issue -comment "$Reply"
}
else { 
    $Reply = "Issue caught while attempting to create H:Drive: $ErrorMessage - However automation Process was not stopped, please fix manually"
    JiraComment -issue $issue -comment "$Reply"
	Write-Log "$Reply"
	#No transition to Error status here as it's not a critical error./ 
}
}

#Set expiry on non FTE contract types
if (($toc -eq "Contractor" ) -or ($toc -eq "Work Experience Student" ) -or ($toc -eq "External Contractor" ))
{
$User = Get-ADUser -LDAPFilter "(sAMAccountName=$attempt_user)" -server DC
#Transform Jira Date Format to AD ready format 
$expiry = Get-Date $end_date -Format 'dd/MM/yyyy'

Write-Log " | Setting Active Directory Expiry | " 

#Set expiry
$error.clear()
Try {
Set-ADAccountExpiration -identity $User -dateTime $expiry
}
Catch {
$ErrorMessage = $_.Exception.InnerException
}
Finally {
if (!$error) {
        Write-Log "Account expiry: No Error Occured"
		$setexpiry = (Get-ADUser -Identity $User -Properties AccountExpirationDate | Select-Object -Property SamAccountName, AccountExpirationDate)
		$Reply = "Set expiry as $setexpiry" 
		JiraComment -issue $issue -comment "$Reply"
    }
	else {
		$Reply = "Issue caught while attempting to set account expiry: $ErrorMessage - However automation Process was not stopped, please fix manually"
		JiraComment -issue $issue -comment "$Reply"
		Write-Log "$Reply"
		#No transition to Error status here as it's not a critical error./ 
    }
}
}

#Bypass Exchange/365/Lync if external contractor
if ($toc -eq "External Contractor" ) { 
New-JiraSession -Credential $Jira_Cred
Invoke-JiraIssueTransition -Issue $issue -Transition 61
Get-JiraSession | Remove-JiraSession
}
else 
{
" **************** Done **************** "
New-JiraSession -Credential $Jira_Cred
Invoke-JiraIssueTransition -Issue $issue -Transition 381
Get-JiraSession | Remove-JiraSession
}


