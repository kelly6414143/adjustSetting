param(
  [int]$Port = 8787,
  [string]$TargetOrigin = "https://api.adjust.com"
)

$ErrorActionPreference = "Stop"

try {
  Add-Type -AssemblyName "System.Net.Http" -ErrorAction Stop
} catch {
  Write-Error "Failed to load System.Net.Http. Please use Windows PowerShell 5.1+ with .NET Framework 4.7.2+."
  exit 1
}

$listener = [System.Net.HttpListener]::new()
$listener.Prefixes.Add("http://localhost:$Port/")
$listener.Start()

$handler = [System.Net.Http.HttpClientHandler]::new()
$handler.AllowAutoRedirect = $false
$client = [System.Net.Http.HttpClient]::new($handler)

$script:UpstreamCookieJar = @{}

function Write-CorsHeaders {
  param([System.Net.HttpListenerResponse]$Response)

  $Response.Headers["Access-Control-Allow-Origin"] = "*"
  $Response.Headers["Access-Control-Allow-Headers"] = "Content-Type, Authorization, x-csrf-token, X-CSRF-Token"
  $Response.Headers["Access-Control-Allow-Methods"] = "GET, POST, PUT, PATCH, DELETE, OPTIONS"
}

function Merge-Cookies {
  param([string]$ClientCookieHeader)

  $merged = @{}
  foreach ($name in $script:UpstreamCookieJar.Keys) {
    $merged[$name] = $script:UpstreamCookieJar[$name]
  }

  if ($ClientCookieHeader) {
    $parts = $ClientCookieHeader -split ";"
    foreach ($part in $parts) {
      $trimmed = $part.Trim()
      if (-not $trimmed) { continue }
      $firstEquals = $trimmed.IndexOf("=")
      if ($firstEquals -le 0) { continue }

      $key = $trimmed.Substring(0, $firstEquals).Trim()
      $value = $trimmed.Substring($firstEquals + 1).Trim()
      if (-not $key) { continue }
      $merged[$key] = $value
    }
  }

  if ($merged.Count -eq 0) {
    return ""
  }

  return (($merged.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join "; ")
}

function Update-UpstreamCookieJar {
  param([System.Net.Http.HttpResponseMessage]$ResponseMessage)

  if (-not $ResponseMessage.Headers.Contains("Set-Cookie")) {
    return
  }

  foreach ($setCookieValue in $ResponseMessage.Headers.GetValues("Set-Cookie")) {
    if (-not $setCookieValue) { continue }

    $firstPart = ($setCookieValue -split ";")[0].Trim()
    if (-not $firstPart) { continue }

    $firstEquals = $firstPart.IndexOf("=")
    if ($firstEquals -le 0) { continue }

    $name = $firstPart.Substring(0, $firstEquals).Trim()
    $value = $firstPart.Substring($firstEquals + 1).Trim()
    if (-not $name) { continue }

    if ([string]::IsNullOrEmpty($value)) {
      $script:UpstreamCookieJar.Remove($name) | Out-Null
      continue
    }

    $script:UpstreamCookieJar[$name] = $value
  }
}

Write-Host "Proxy server running at http://localhost:$Port"

try {
  while ($listener.IsListening) {
    $context = $listener.GetContext()
    $request = $context.Request
    $response = $context.Response

    Write-CorsHeaders -Response $response

    if ($request.HttpMethod -eq "OPTIONS") {
      $response.StatusCode = 204
      $response.Close()
      continue
    }

    try {
      $targetUrl = "{0}{1}" -f $TargetOrigin, $request.RawUrl
      $method = [System.Net.Http.HttpMethod]::new($request.HttpMethod)
      $requestMessage = [System.Net.Http.HttpRequestMessage]::new($method, $targetUrl)

      if ($request.Headers["Authorization"]) {
        $requestMessage.Headers.TryAddWithoutValidation("Authorization", $request.Headers["Authorization"]) | Out-Null
      }
      if ($request.Headers["x-csrf-token"]) {
        $requestMessage.Headers.TryAddWithoutValidation("x-csrf-token", $request.Headers["x-csrf-token"]) | Out-Null
      }

      $mergedCookieHeader = Merge-Cookies -ClientCookieHeader $request.Headers["Cookie"]
      if ($mergedCookieHeader) {
        $requestMessage.Headers.TryAddWithoutValidation("Cookie", $mergedCookieHeader) | Out-Null
      }

      if ($request.HttpMethod -ne "GET" -and $request.HttpMethod -ne "HEAD") {
        $memoryStream = [System.IO.MemoryStream]::new()
        $request.InputStream.CopyTo($memoryStream)
        $bodyBytes = $memoryStream.ToArray()
        $byteContent = [System.Net.Http.ByteArrayContent]::new($bodyBytes)
        $contentType = $request.Headers["Content-Type"]
        if ($contentType) {
          $byteContent.Headers.TryAddWithoutValidation("Content-Type", $contentType) | Out-Null
        } else {
          $byteContent.Headers.TryAddWithoutValidation("Content-Type", "application/json") | Out-Null
        }
        $requestMessage.Content = $byteContent
      }

      $responseMessage = $client.SendAsync($requestMessage).GetAwaiter().GetResult()
      Update-UpstreamCookieJar -ResponseMessage $responseMessage

      $response.StatusCode = [int]$responseMessage.StatusCode
      if ($responseMessage.Content.Headers.ContentType) {
        $response.ContentType = $responseMessage.Content.Headers.ContentType.ToString()
      } else {
        $response.ContentType = "application/json"
      }

      $upstreamBytes = $responseMessage.Content.ReadAsByteArrayAsync().GetAwaiter().GetResult()
      $response.OutputStream.Write($upstreamBytes, 0, $upstreamBytes.Length)
      $response.OutputStream.Flush()
      $response.Close()
    } catch {
      $response.StatusCode = 500
      $response.ContentType = "application/json"
      $errorPayload = @{
        message = "Proxy request failed"
        error = $_.Exception.Message
      } | ConvertTo-Json -Compress

      $errorBytes = [System.Text.Encoding]::UTF8.GetBytes($errorPayload)
      $response.OutputStream.Write($errorBytes, 0, $errorBytes.Length)
      $response.OutputStream.Flush()
      $response.Close()
    }
  }
} finally {
  if ($listener.IsListening) {
    $listener.Stop()
  }
  $client.Dispose()
}
