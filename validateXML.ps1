#Requires -Version 3.0
param(
    [Parameter(Mandatory = $true)]
    [string]$InputFile
)

$reader = $null
$exitCode = 0

try {
    $settings = New-Object System.Xml.XmlReaderSettings
    $settings.DtdProcessing = [System.Xml.DtdProcessing]::Prohibit
    $settings.XmlResolver = $null
    $reader = [System.Xml.XmlReader]::Create($InputFile, $settings)

    while ($reader.Read()) { }

    [Console]::Out.WriteLine("ANYXML_VALID")
}
catch [System.Xml.XmlException] {
    $exception = $_.Exception
    $message = $exception.Message -replace "[\r\n\t]+", " "
    [Console]::Out.WriteLine("ANYXML_ERROR`t$($exception.LineNumber)`t$($exception.LinePosition)`t$message")
    $exitCode = 2
}
catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    $exitCode = 1
}
finally {
    if ($null -ne $reader) {
        $reader.Dispose()
    }
}

exit $exitCode
