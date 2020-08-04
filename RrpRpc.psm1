#Requires -Version 2.0
<#
    .Synopsis
        This is a compilation of functions for HTTPS Requests to RRP Proxy API described in https://wiki.rrpproxy.net/api
#>

function Get-RrpErrorDetails ([int]$ReturnCode)
{
    $RrpReturnCodes = @{
        e200 = 'Command completed successfully'
        e210 = 'Domain name available'
        e211 = 'Domain name not available'
        e212 = 'Name server available'
        e213 = 'Name server not available'
        e214 = 'Contact available'
        e215 = 'Contact not available'
        e218 = 'Request is available'
        e219 = 'Request is not available'
        e220 = 'Command completed successfully. Server closing connection'
        e420 = 'Command failed due to server error. Server closing connection'
        e421 = 'Command failed due to server error. Client should try again'
        e422 = 'Abuse detected! The account has been temporarily locked! Please standby some minutes.'
        e423 = 'error (socket error)'
        e500 = 'Invalid command name'
        e501 = 'Invalid command option'
        e502 = 'Invalid entity value'
        e503 = 'Invalid attribute name'
        e504 = 'Missing required attribute'
        e505 = 'Invalid attribute value syntax'
        e506 = 'Invalid option value'
        e507 = 'Invalid command format'
        e508 = 'Missing required entity'
        e509 = 'Missing command option'
        e520 = 'Server closing connection. Client should try opening new connection'
        e521 = 'Too many sessions open. Server closing connection'
        e530 = 'Authentication failed'
        e531 = 'Authorization failed'
        e532 = 'Domain names linked with name server'
        e533 = 'Domain name has active name servers'
        e534 = 'Domain name has not been flagged for transfer'
        e535 = 'Restricted IP address'
        e536 = 'Domain already flagged for transfer'
        e540 = 'Attribute value is not unique'
        e541 = 'Invalid attribute value'
        e542 = 'Invalid old value for an attribute'
        e543 = 'Final or implicit attribute cannot be updated'
        e544 = 'Entity on hold'
        e545 = 'Entity reference not found'
        e546 = 'Credit limit exceeded'
        e547 = 'Invalid command sequence'
        e548 = 'Domain is not up for renewal'
        e549 = 'Command failed'
        e550 = 'Parent domain not registered'
        e551 = 'Parent domain status does not allow for operation'
        e552 = 'Domain status does not allow for operation'
        e553 = 'Operation not allowed. Domain pending transfer'
        e554 = 'Domain already registered'
        e555 = 'Domain already renewed'
        e556 = 'Maximum registration period exceeded'
        e557 = 'Object status prohibits operation'
        e560 = 'Resource is disabled'
        e561 = 'Resource still in use'
        e562 = 'Email address already uses forwarding'
        e563 = 'Email address already uses mailspace'
        e564 = 'Email domain already linked to a different mailspace'
    }
        if(!$RrpReturnCodes.ContainsKey("e$ReturnCode")) 
    {
        Throw "Return code $ReturnCode is undefined"
    }

    $RrpReturnCodes["e$ReturnCode"]
}

function Resolve-URL ([bool]$IsOTE = $true, [string]$Login, [string]$Password, [string]$Command)
{
    if($IsOTE) 
    { 
        $URL = 'https://api-ote.rrpproxy.net/api/call?s_opmode=OTE'
    }
    else 
    {
        $URL = 'https://api.rrpproxy.net/api/call?'
    }

    "$URL&s_login=$Login&s_pw=$Password&Command=$Command"
}

function Get-RrpContext ([bool]$IsOTE = $true, [string]$Login, [string]$Password)
{
    try 
    {
        $Response = Convert-FromRrpResponse (Invoke-RrpRequestRaw (Resolve-URL $IsOTE $Login $Password 'StatusAccount'))
        if($Response.meta_code -lt 300) 
        {
            @{
                IsOTE = $true
                Login = $Login
                Password = $Password
            }
        }
        else
        {
            $ErrorMessage = Get-RrpErrorDetails $Response.meta_code
            Throw "RRP API Error: $($Response.meta_code) - $ErrorMessage"
        }
    
    }
    catch {
        Throw $_.Exception        
    }
}

function Invoke-RrpRequestRaw ([string]$URL)
{
    try 
    {
        $Response = Invoke-WebRequest $URL -ErrorAction Stop
        $Response.Content 
    }
    catch 
    {
        $StatusCode = $_.Exception.Response.StatusCode.value__
        Throw $_.Exception
    }
}

function Invoke-RrpRequest ($Context, $Command, $Parameters)
{
    if(!$Context.Login -or !$Context.Password)
    {
        Throw 'Context is missing or invald'
    }

    $URL = Resolve-URL $Context.IsOTE $Context.Login $Context.Password $Command

    if($Parameters)
    {
        $Parameters.GetEnumerator() | % {
            $URL += "&$($_.Key)=$($_.Value)"
        }
    }

    $Response = Convert-FromRrpResponse (Invoke-RrpRequestRaw $URL)
    if($Response.meta_code -ge 300) 
    {
        $ErrorMessage = Get-RrpErrorDetails $Response.meta_code
        Throw "RRP API Error: $($Response.meta_code) - $ErrorMessage"
    }
    $Response
}
function Convert-FromRrpResponse ($Response)
{
    $Result = @{}
    $Response -split '\r?\n' | % {
        $line = $_
        if($line -ne '[RESPONSE]' -and $line -ne 'EOF')
        {
            if($line -match '([^=]*)= *(.*)')
            {
                $key,$value = $matches[1..2]
                $key = $key.Trim()
                if($key -match 'property\[([^\]]*)\]\[([0-9]*)\]')
                {
                    $column,$row = $matches[1..2]
                    if('total','last','count','limit','first','column' -notcontains $column)
                    {
                        if(!$Result.ContainsKey($column))
                        {
                            $Result[$column]=@()
                        }
                        $Result[$column] += $value
                    }
                }
                else 
                {
                    if('code','description' -contains $key)
                    {
                        $result["meta_$key"] = $value   
                    }
                    elseif ('queuetime','runtime' -notcontains $key)
                    {
                        $result[$key] = $value       
                    }
                }
            }
        }
    }
    $result
}
