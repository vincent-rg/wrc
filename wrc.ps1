# wrc.ps1 - Remote command launcher client
#
# Usage:
#   Direct execution: .\wrc.ps1 -Command <cmd> -Server <ip> [-Port <port>] [-WorkDir <dir>]
#
#   Source and use:   . .\wrc.ps1
#                     wrc -Command <cmd> -Server <ip> [-Port <port>] [-WorkDir <dir>]
#
# Options:
#   -Command  : Command to execute inside WSB
#   -Server   : IP address of the WRC server (wrc_server.py) running in WSB
#   -Port     : Server port (default: 9000)
#   -WorkDir  : Working directory on the server (default: server's cwd)

function wrc {
    param(
        [Parameter(Mandatory=$true, Position=0)]
        [string]$Command,

        [Parameter(Mandatory=$true)]
        [string]$Server,

        [switch]$Silent = $false,

        [int]$Port = 9000,

        [string]$WorkDir = ""
    )

    $uri     = "http://${Server}:${Port}/run"
    $bodyObj = @{command = $Command}
    if ($WorkDir -ne "") { $bodyObj.workdir = $WorkDir }
    $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes(
        (ConvertTo-Json $bodyObj -Compress)
    )

    if(-not($Silent)) {
        Write-Host "WRC: Sending to ${Server}:${Port} ..." -ForegroundColor Cyan
    }
    
    $exitCode = 1

    try {
        # Connect with retries
        $response   = $null
        $maxRetries = 10
        for ($attempt = 1; $attempt -le $maxRetries; $attempt++) {
            try {
                $request = [System.Net.HttpWebRequest]::Create($uri)
                $request.Method      = 'POST'
                $request.ContentType = 'application/json'
                $request.Timeout     = -1  # No timeout - wait as long as the command runs

                $request.ContentLength = $bodyBytes.Length
                $reqStream = $request.GetRequestStream()
                $reqStream.Write($bodyBytes, 0, $bodyBytes.Length)
                $reqStream.Close()

                $response = $request.GetResponse()
                break
            } catch {
                if ($attempt -lt $maxRetries) {
                    Write-Host "WRC: Attempt $attempt/$maxRetries failed, retrying in 1s..." -ForegroundColor Yellow
                    Start-Sleep -Seconds 1
                } else {
                    throw
                }
            }
        }

        $reader = [System.IO.StreamReader]::new($response.GetResponseStream(), [System.Text.Encoding]::UTF8)
        $obj    = $reader.ReadToEnd() | ConvertFrom-Json
        $exitCode = $obj.exit_code
        $reader.Close()
        $response.Close()
    }
    catch {
        Write-Host "WRC: Connection failed - $_" -ForegroundColor Red
        return 1
    }

    if(-not($Silent))
    {
        if ($exitCode -eq 0) {
            Write-Host "WRC: Done (exit_code=0)" -ForegroundColor Green
        } else {
            Write-Host "WRC: Done (exit_code=$exitCode)" -ForegroundColor Red
        }
    }

    return $exitCode
}

if ($MyInvocation.InvocationName -ne '.') {
    if ($args.Count -gt 0) {
        $exitCode = wrc @args
        exit $exitCode
    } else {
        Write-Host "WRC - Remote Command Launcher" -ForegroundColor Green
        Write-Host "Usage: .\wrc.ps1 -Command <cmd> -Server <ip> [-Port <port>] [-WorkDir <dir>]" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Options:" -ForegroundColor Cyan
        Write-Host "  -Command  : Command to execute inside WSB" -ForegroundColor Gray
        Write-Host "  -Server   : IP address of wrc_server.py running in WSB" -ForegroundColor Gray
        Write-Host "  -Port     : Server port (default: 9000)" -ForegroundColor Gray
        Write-Host "  -WorkDir  : Working directory on the server (default: server's cwd)" -ForegroundColor Gray
        Write-Host ""
        Write-Host "To use as a function, source this script:" -ForegroundColor Cyan
        Write-Host "   . .\wrc.ps1" -ForegroundColor White
        Write-Host "Then call: wrc -Command <cmd> -Server <ip> [-Port <port>] [-WorkDir <dir>]" -ForegroundColor White
    }
}
# When sourced: load silently
