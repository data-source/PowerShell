$username = 'user'
$Password = 'password'
 
function ConvertTo-Base64($string) {
    $bytes  = [System.Text.Encoding]::UTF8.GetBytes($string);
    $encoded = [System.Convert]::ToBase64String($bytes);
    return $encoded;
}
 
function Get-HttpBasicHeader([string]$username, [string]$password, $Headers = @{}) {
    $b64 = ConvertTo-Base64 "$($username):$($Password)"
    $Headers["Authorization"] = "Basic $b64"
    $Headers["X-Atlassian-Token"] = "nocheck"
    return $Headers
}
 
function add_comment([string]$issueKey,[string]$comment) {
    $body = ('{"body": "'+$comment+'"}')
    $comment=(Invoke-RestMethod -uri ($restapiuri +"issue/$issueKey/comment") -Headers $headers -Method POST -ContentType "application/json" -Body $body).id   
    return $comment
}
 
$restapiuri = "https://jira.company.com/rest/api/2/"
$headers = Get-HttpBasicHeader "$username" "$Password"
 
add_comment "ID-3243" "Test Comment"
