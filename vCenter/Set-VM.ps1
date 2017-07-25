#Load Incoming JSON
	param (
        [string]$servername = 'server name',
        [string]$cpucount = '2',
	      [string]$ram = '16',
		    [string]$network = '',
    	  [string]$ipaddress = '10.40.0.0',
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
[string]$cmd1 = '.\curl --%  -D- -u user:admin -X PUT -d "{\"update\": {\"comment\": [{\"add\": {\"body\":\"' + $comment+ '\"}}]}}"'
[string]$cmd2 = ' -H "Content-Type: application/json" https://jira.company.com/rest/api/2/issue/{0}' -f $issue;
$all_cmds = "$cmd1 $cmd2 "
$all_cmds
Invoke-Expression $all_cmds
}

function CustomFieldUpdate 
{
param( [string]$issue, [string]$customfield, [string]$customfield_value)

"Calling CustomFieldUpdate with variables | issue = " + $issue + " And Text = " + $comment
#[string]$cmd1 = '.\curl --%  -D- -u user:admin -X PUT -d "{	\"update\": {\"comment\": [{\"add\": {\"body\":\"' + $comment+ '\"}}]}}"'
[string]$cmd1 = '.\curl --%  -D- -u user:admin -X PUT -d "{ \"fields\": { \"' + $customfield + '\":\"' + $customfield_value + '\"}}"'
[string]$cmd2 = ' -H "Content-Type: application/json" https://jira.company.com/rest/api/2/issue/{0}' -f $issue;
$all_cmds = "$cmd1 $cmd2 "
$all_cmds
Invoke-Expression $all_cmds
}

function SendToError
{
New-JiraSession -Credential $Jira_Cred
Invoke-JiraIssueTransition -Issue $issue -Transition 151
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
$User = "domain\vsphereaccount"
$PasswordFile = "C:\scripts\ps\PSINFRA-Credentials\vsphere.txt"
$KeyFile = "C:\scripts\ps\PSINFRA-Credentials\AES.key"
$key = Get-Content $KeyFile
$VIcred = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $User, (Get-Content $PasswordFile | ConvertTo-SecureString -Key $key)
Connect-VIServer $vcenter -Credential $VIcred -WarningAction SilentlyContinue

$VM = $servername 

"Setting VM"
#Set VM 
Set-VM -VM $VM -NumCpu $cpucount -MemoryGB $ram -Confirm:$false -Verbose

#Set PortGroup on incoming JSON
if ($network -eq "105") {
	$NetworkName = "105_QHC_RHS_Server"
	$gateway = "10.40.105.250"
	}
	elseif ($network -eq "106") {
	$NetworkName = "106_QHC_LHS_Server"
	$gateway = "10.40.106.250"
}

#Set Networking: PortGroup  
$gVM = Get-VM $VM
Try {
$gVM | Get-NetworkAdapter | Set-NetworkAdapter -NetworkName $NetworkName -confirm:$false -Verbose 
}
Catch {
	$ErrorMessage = $_
}
Finally {
if (!$error) {
			$Reply = "Set Networkadapter [$NetworkName] "
			Write-Log $Reply
			JiraComment -issue $issue -comment "$Reply"
		}
		else { 
			$Reply = "Issue caught while setting Network: $ErrorMessage"
			JiraComment -issue $issue -comment "$Reply"
			Write-Log "$Reply"
			SendToError 
}
}

#Start-VM
$PowerState = (Get-VM $VM | Select PowerState).PowerState
If ($PowerState -eq 'PoweredOff') { 
	Start-VM -VM $VM -Verbose
	}
	Else { 
	"VM $VM already powered on" 
	} 

#Wait for vmWare Tools
do {
    Start-Sleep -milliseconds 200
    $stat=(Get-VM $VM | Get-View).Guest.ToolsStatus
    Write-Host $VM $stat
    } until($stat -eq "toolsOk")

#Move VM to Server OU
$DC = "DC"
$Username = "domain\account"
$Password = cat C:\scripts\ps\cred.txt | convertto-securestring
$Cred = new-object -typename System.Management.Automation.PSCredential -argumentlist $Username, $Password

#Initiate Remote PS Session to local DC
$ADPowerShell = New-PSSession -ComputerName $DC -Authentication Negotiate -Credential $Cred
 
#Import-Module ActiveDirectory
write-host "Importing Active Directory PowerShell Commandlets"
Invoke-Command -Session $ADPowerShell -scriptblock { import-module ActiveDirectory }
Import-PSSession -Session $ADPowerShell -Module ActiveDirectory -AllowClobber -ErrorAction Stop

$TargetOU = "OU=Servers,OU=Machines,OU=COMPANY OU,DC=ACME,DC=COM"
$machine = Get-ADComputer $VM
"Machine = $machine" 
$machinedn = $machine.DistinguishedName
$machinedn | Move-ADObject -TargetPath $TargetOU -Verbose 

Remove-PSSession $ADPowerShell

$Reply = "Moved Server to Server OU"
JiraComment -issue $issue -comment "$Reply"
Write-Log "$Reply" 

#Set Networking
$LocalUser = "user"
$LocalPWord = ConvertTo-SecureString -String "password" -AsPlainText -Force
$LocalCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $LocalUser, $LocalPWord
$NetworkSettings = @"
netsh interface ip set address "Ethernet" static $ipaddress 255.255.255.0 $gateway
"@
Invoke-VMScript -ScriptText $NetworkSettings -VM $VM -GuestCredential $LocalCredential

#Change hostname via custom sysprep 
$MasterSysprep = "C:\scripts\ps\PSINFRA\mastersysprep.xml"
$CustomSysprep = "C:\scripts\ps\PSINFRA\customsysprep.xml"
$ReplaceHost = "CHANGEHOSTNAME"
$guestuser = "machine\user"
$GuestPassword = "password"

#Cleans up prior local sysprep output file and replaces hostname in sysprep.xml
remove-item $CustomSysprep -ErrorAction SilentlyContinue

#Sets new sysprep for current host 
$content = Get-Content $MasterSysprep
$content | foreach { $_.Replace($ReplaceHost, $VM) } | Set-Content $CustomSysprep
write-host $VM Custom sysprep file created

# Creates setupcomplete.cmd file to delete sysprep XML files post-sysprep. File must not already exist.
$script1 = @"
echo `"del /F /Q c:\windows\panther\unattend.xml c:\windows\system32\sysprep\customsysprep.xml`" | out-file -encoding ASCII c:\windows\setup\setupcomplete.cmd
"@
invoke-vmscript -scripttext $script1 -VM $VM -guestuser $guestuser -GuestPassword $GuestPassword -Verbose
write-host $vm setupcomplete.cmd uploaded
# Copies sysprep.xml to guest and executes asynchronously
$script2 = @"
c:\windows\system32\sysprep\sysprep.exe /generalize /oobe /unattend:c:\windows\system32\sysprep\customsysprep.xml /reboot
"@
copy-vmguestfile -source $CustomSysprep -destination c:\windows\system32\sysprep -VM $VM -localtoguest -guestuser $guestuser -guestpassword $guestpassword -Verbose 

invoke-vmscript -scripttext $script2 -VM $VM -guestuser $guestuser -GuestPassword $GuestPassword -scripttype bat -runasync -Verbose
write-host $vm Sysprep executed

$Reply = "Changing Server hostname, this can take a few min"
JiraComment -issue $issue -comment "$Reply"
Write-Log "$Reply"
Start-Sleep -s 400 

$Reply = "Server hostname changed to [$VM] "
JiraComment -issue $issue -comment "$Reply"
Write-Log "$Reply"

#Set Networking
$LocalUser = "user"
$LocalPWord = ConvertTo-SecureString -String "password" -AsPlainText -Force
$LocalCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $LocalUser, $LocalPWord
$NetworkSettings = @"
netsh interface ip set address "Ethernet" static $ipaddress 255.255.255.0 $gateway
"@
Invoke-VMScript -ScriptText $NetworkSettings -VM $VM -GuestCredential $LocalCredential

$Reply = "Set new IP configuration: IP:[$ipaddress] - Gateway: [$gateway]"
JiraComment -issue $issue -comment "$Reply"
Write-Log "$Reply"

#Transition Issue 
New-JiraSession -Credential $Jira_Cred
Invoke-JiraIssueTransition -Issue $issue -Transition 161
Get-JiraSession | Remove-JiraSession

Disconnect-VIServer -Server $vcenter
