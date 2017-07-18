#Load Incoming JSON
	param (
        	[string]$user = 'defaultUPN',
        	[string]$title = 'default title',
        	[string]$description = ' default description',
	      	[string]$department = 'default department',
		[string]$dept = 'old department',
	      	[string]$manager = 'default manager',
		[string]$userdn = 'User DN',
	      	[string]$adpath = 'CN=Users,DC=COMPANY,DC=COM',
		[string]$script = 'defaultscript.bat',
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

function Remove
{
$deptgroups | foreach {
Remove-AdGroupMember "$_" $user -Confirm:$false
$GroupDetails = (Get-ADGroup "$_" -Properties Description | Select Name).Name
$Comment += "$GroupDetails; "
}
Write-Log "Removed user from previous department groups: $Comment"
JiraComment -issue $issue -Comment "Removed user from previous department groups: $Comment"
Clear-Variable Comment
}

function Add
{
$deptgroups | foreach {
Add-AdGroupMember "$_" $user -Confirm:$false
$GroupDetails = (Get-ADGroup "$_" -Properties Description | Select Name).Name
$Comment += "$GroupDetails; "
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
	
#Initiate Remote PS Session to local DC
$ADPowerShell = New-PSSession -ComputerName $DC -Authentication Negotiate -Credential $Cred
 
#Import-Module ActiveDirectory
$env:ADPS_LoadDefaultDrive = 0
"Importing Active Directory PowerShell Commandlets"
Invoke-Command -Session $ADPowerShell -scriptblock { import-module ActiveDirectory }
Import-PSSession -Session $ADPowerShell -Module ActiveDirectory -AllowClobber -ErrorAction Stop

#Verify and load accounts
"**team leader = $manager"
"**user cn = $userdn"
"**user distinguished name = $user"
$tl = Get-ADUser $manager -Properties Description | Select Name
$tlname = $tl.name
$ou = Get-ADObject $adpath -Properties Description | Select Name
$ouname = $ou.name

#Error Handling Preferences
$saved=$global:ErrorActionPreference
$global:ErrorActionPreference = 'SilentlyContinue'

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

" | REMOVING OLD DEPT GROUPS | "

# Remove groups from previous team 
$deptgroups = Switch ($dept) { 
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
$Reply = "No group to remove"
Write-Log "$Reply"
JiraComment -issue $issue -Comment "$Reply"
}
else 
{
Remove
}

" | ADDING NEW DEPT GROUPS | "

# Add User to groups for new team 
$deptgroups = Switch ($department) { 
		'Customer Service' {$GroupsCustomerService}
		'Corp Services' {$GroupsCorpServices}
		'Customer Support' {$GroupsCustomerSupport}
		'Claims Recovery and Support' {$GroupsClaimsRecovery}
		'Inpatient Claims' {$GroupsInpatientClaims}
		'Medical Practice' {$GroupsMedicalPractice}
		'Outpatient Claims' {$GroupsOutpatientClaims}
		'Provider Relations' {$GroupsProviderRelations}
		'Corporate Development' {$GroupsCorpDev}
		'Corporate Sales' {$GroupsCorpSales}
		'Individual Sales' {$IndividualSales}
		'Product Development and Pricing' {$ProductDev}
		'Sales and Marketing' {$SalesMarketing}
		'Human Resources' {$GroupsHR}
		'Organisational Development' {$GroupsOrgDev}
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

# Move user to target OU
$error.clear()
Try {
    $global:ErrorActionPreference = 'stop'
    "Moving user: $User to its new OU: $adpath"
    Move-ADObject -Identity $userdn -TargetPath $adpath -ErrorAction Stop
}
Catch {
    $ErrorMessage = $_.Exception.InnerException
}
Finally {
if (!$error) {
        $Reply = "User moved to target OU: $ouname "
        Write-Log $Reply
        JiraComment -issue $issue -comment "$Reply"
    }
else {
    $Reply = "Issue caught while attempting to move user to target OU: $ErrorMessage "
    JiraComment -issue $issue -comment "$Reply"
    Write-Log "$Reply"
    SendToError
    exit
    }
$global:ErrorActionPreference=$saved
}

# Modify AD Account
$error.clear()
Try {
    $Global:ErrorActionPreference = 'Stop'
    Set-ADUser -Identity $user -title "$title" -description "$title" -department "$department" -manager "$manager" -ScriptPath "$script" -server dc -ErrorAction Stop
}
Catch {
    $ErrorMessage = $_.Exception.InnerException
}
Finally {
if (!$error) {
        $Reply = "Set user: $User with new title '$title' and new manager $tlname"
        JiraComment -issue $issue -comment "$Reply"
    }
else {
    $Reply = "Issue caught while attempting to set new Department, Title or Manager: $ErrorMessage "
    JiraComment -issue $issue -comment "$Reply"
    Write-Log "$Reply"
    SendToError
    exit
    }
$global:ErrorActionPreference=$saved
}

#Reload Jira Session and transition issue
New-JiraSession -Credential $Jira_Cred
Invoke-JiraIssueTransition -Issue $issue -Transition 31

#Disconnect Sessions
Remove-PSSession $ADPowerShell	
Get-JiraSession | Remove-JiraSession
