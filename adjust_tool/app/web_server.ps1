param(
  [int]$Port = 5500,
  [string]$RootPath
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($RootPath)) {
  $RootPath = Split-Path -Parent $MyInvocation.MyCommand.Path
}

$RootPath = [System.IO.Path]::GetFullPath($RootPath)

if (-not (Test-Path -LiteralPath $RootPath)) {
  Write-Error "Root path does not exist: $RootPath"
  exit 1
}

$listener = [System.Net.HttpListener]::new()
$listener.Prefixes.Add("http://localhost:$Port/")
$listener.Start()

Write-Host "Web server running at http://localhost:$Port/"
Write-Host "Serving files from: $RootPath"

function Get-ContentType {
  param([string]$Path)
  switch ([System.IO.Path]::GetExtension($Path).ToLowerInvariant()) {
    ".html" { "text/html; charset=utf-8" }
    ".js"   { "application/javascript; charset=utf-8" }
    ".css"  { "text/css; charset=utf-8" }
    ".json" { "application/json; charset=utf-8" }
    ".png"  { "image/png" }
    ".jpg"  { "image/jpeg" }
    ".jpeg" { "image/jpeg" }
    ".svg"  { "image/svg+xml" }
    ".ico"  { "image/x-icon" }
    ".txt"  { "text/plain; charset=utf-8" }
    default { "application/octet-stream" }
  }
}

try {
  while ($listener.IsListening) {
    $context = $listener.GetContext()
    $request = $context.Request
    $response = $context.Response

    try {
      $pathPart = [System.Uri]::UnescapeDataString($request.Url.AbsolutePath.TrimStart('/'))
      if ([string]::IsNullOrWhiteSpace($pathPart)) {
        $pathPart = "index.html"
      }

      $relativePath = $pathPart.Replace('/', [System.IO.Path]::DirectorySeparatorChar)
      $candidate = Join-Path $RootPath $relativePath
      $fullPath = [System.IO.Path]::GetFullPath($candidate)

      if (-not $fullPath.StartsWith($RootPath, [System.StringComparison]::OrdinalIgnoreCase)) {
        $response.StatusCode = 403
        $response.Close()
        continue
      }

      if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
        $response.StatusCode = 404
        $notFound = [System.Text.Encoding]::UTF8.GetBytes("Not Found")
        $response.ContentType = "text/plain; charset=utf-8"
        $response.OutputStream.Write($notFound, 0, $notFound.Length)
        $response.Close()
        continue
      }

      $bytes = [System.IO.File]::ReadAllBytes($fullPath)
      $response.StatusCode = 200
      $response.ContentType = Get-ContentType -Path $fullPath
      $response.ContentLength64 = $bytes.LongLength
      $response.OutputStream.Write($bytes, 0, $bytes.Length)
      $response.Close()
    } catch {
      $response.StatusCode = 500
      $payload = [System.Text.Encoding]::UTF8.GetBytes("Server Error")
      $response.ContentType = "text/plain; charset=utf-8"
      $response.OutputStream.Write($payload, 0, $payload.Length)
      $response.Close()
    }
  }
} finally {
  if ($listener.IsListening) {
    $listener.Stop()
  }
}
