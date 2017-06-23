$url = "https://jira.company.com/rest/api/2/user"

$user = "jira-admin"
$pass = "password"
$cred = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$user`:$pass"))
$headers = @{Authorization=("Basic $cred")} 

$userObject = @{
    name     = "test";
    emailAddress = "test@company.com"
    displayName  = "Test";
    notification = $false;
}

$restParameters = @{
    Uri = $url;
    ContentType = "application/json";
    Method = "POST";
    Body = (ConvertTo-Json $userObject).ToString();
    Headers = $headers;
}

$response = Invoke-RestMethod @restParameters
