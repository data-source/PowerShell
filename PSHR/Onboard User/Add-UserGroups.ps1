#Load Incoming JSON
	param (
	    	[string]$firstname = 'default firstname',
	    	[string]$lastname = ' default lastname',
	    	[string]$team_dl = 'All Team',
		[string]$department = 'Customer Service',
		[string]$manager = 'default manager',
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

function Add
{
$deptgroups | foreach {
Add-AdGroupMember "$_" $Userdn -Confirm:$false
$GroupDetails = (Get-ADGroup "$_" -Properties Description | Select Name).Name
$Comment += "$GroupDetails ; "
}
Write-Log "Added user to new department groups: $Comment"
JiraComment -issue $issue -Comment "Added user to new department groups: $Comment"
Clear-Variable Comment
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
	
#Load ADPowershell Session
$ADPowerShell = New-PSSession -ComputerName $DC -Authentication Negotiate -Credential $Cred
 
Write-Log " | Starting add_user_to_groups.ps1 | "

#Import-Module ActiveDirectory
$env:ADPS_LoadDefaultDrive = 0
"Importing Active Directory PowerShell Commandlets"
Invoke-Command -Session $ADPowerShell -scriptblock { import-module ActiveDirectory }
Import-PSSession -Session $ADPowerShell -Module ActiveDirectory -AllowClobber -ErrorAction Stop

$name = "$firstname $lastname"
"First Name: $firstname | Last Name: $lastname | Name: $name"
$Userdn = Get-ADUser -Filter "cn -eq '$name'" | select -expand DistinguishedName
$User = Get-ADUser $Userdn -properties memberof -server $DC 

#Customer Service Groups depending on Manager
$os = "CN=Team,OU=Distribution Lists,OU=Distribution Lists,OU=Groups,OU=COMPANY OU,DC=company,DC=com"
$om = "CN=Team,OU=Distribution Lists,OU=Distribution Lists,OU=Groups,OU=COMPANY OU,DC=company,DC=com"
$wi = "CN=Team,OU=Distribution Lists,OU=Distribution Lists,OU=Groups,OU=COMPANY OU,DC=company,DC=com"
$Ge = "CN=Team,OU=Distribution Lists,OU=Distribution Lists,OU=Groups,OU=COMPANY OU,DC=company,DC=com"
$sh = "CN=Team,OU=Distribution Lists,OU=Distribution Lists,OU=Groups,OU=COMPANY OU,DC=company,DC=com"
$mu = "CN=Team,OU=Distribution Lists,OU=Distribution Lists,OU=Groups,OU=COMPANY OU,DC=company,DC=com"  
$ry = "CN=Team,OU=Distribution Lists,OU=Distribution Lists,OU=Groups,OU=COMPANY OU,DC=company,DC=com"
$ba = "CN=Team,OU=Distribution Lists,OU=Distribution Lists,OU=Groups,OU=COMPANY OU,DC=company,DC=com"
$be = "CN=Team,OU=Distribution Lists,OU=Distribution Lists,OU=Groups,OU=COMPANY OU,DC=company,DC=com"

# DEPARTMENT'S DISTRIBUTION LISTS AND GROUPS
$location = "c:\scripts\ps\PSHR-Distribution-Groups"
 
$CorpDev = @(GC $($location + "\Corp-Dev.txt"))
$CorpSales = @(GC $($location + "\Corp-Sales.txt"))
$IndividualSales = @(GC $($location + "\Individual-Sales.txt"))
$ProductDev = @(GC $($location + "\Product-Dev.txt"))
$SalesMarketing = @(GC $($location + "\Sales-Marketing.txt"))
$ClaimsRecovery = @(GC $($location + "\Claims-Recovery.txt"))
$InpatientClaims = @(GC $($location + "\Inpatient-Claims.txt"))
$MedicalPractice = @(GC $($location + "\Medical-Practice.txt"))
$OutpatientClaims = @(GC $($location + "\Outpatient-Claims.txt"))
$ProviderRelations = @(GC $($location + "\Provider-Relations.txt"))
$CorpServices = @(GC $($location + "\Corp-Services.txt"))
$CustomerService = @(GC $($location + "\Customer-Service.txt"))
$CustomerSupport = @(GC $($location + "\Customer-Support.txt"))
$HR = @(GC $($location + "\Human-Resources.txt"))
$OrgDev = @(GC $($location + "\Org-Dev.txt"))
$ITBP = @(GC $($location + "\ITBP.txt"))
$MIS = @(GC $($location + "\MIS.txt")) 
$MISDataControl = @(GC $($location + "\MIS-Data-Control.txt"))
$Systems = @(GC $($location + "\Systems.txt"))
$SalesSupport = @(GC $($location + "\Sales-Support.txt"))

# Add User to groups for new team 
$deptgroups = Switch ($department) { 
		'Customer Service' {$CustomerService}
		'Corp Services' {$CorpServices}
		'Customer Support' {$CustomerSupport}
		'Claims Recovery and Support' {$ClaimsRecovery}
		'Inpatient Claims' {$InpatientClaims}
		'Medical Practice' {$MedicalPractice}
		'Outpatient Claims' {$OutpatientClaims}
		'Provider Relations' {$ProviderRelations}
		'Corporate Development' {$CorpDev}
		'Corporate Sales' {$CorpSales}
		'Individual Sales' {$IndividualSales}
		'Product Development and Pricing' {$ProductDev}
		'Sales and Marketing' {$SalesMarketing}
		'Human Resources' {$HR}
		'Organisational Development' {$OrgDev}
		'IT Business Planning' {$ITBP}
		'MIS' {$MIS}
		'MIS-Data Control' {$MISDataControl}
		'Systems' {$Systems}
		'Sales Support' {$SalesSupport}
		}
If ($deptgroups -eq $null) {
$Reply = "Groups not defined for this Department yet, no group added"
Write-Log "$Reply"
JiraComment -issue $issue -Comment "$Reply"
}
else 
{
Add
}

# Add User to groups for Customer Service team 
$deptgroups = Switch ($manager) { 
		'os' {$os}
		'om' {$om}
		'wi' {$wi}
		'Ge' {$Ge}
		'sh' {$sh}
		'mu' {$mu}
		'ry' {$ry}
		'ba' {$ba}
		'be' {$be}
		}
If ($deptgroups -eq $null) {
$Reply = "No Team Leader specific Customer Service group"
Write-Log "$Reply"
}
else 
{
Add
}

Sleep 100

#Transition Issue
New-JiraSession -Credential $Jira_Cred
Invoke-JiraIssueTransition -Issue $issue -Transition 21

#Disconnect Sessions
Remove-PsSession $ADPowerShell
Get-JiraSession | Remove-JiraSession
