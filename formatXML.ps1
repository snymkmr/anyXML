#Requires -Version 3.0
param(
    [string]$InputFile = "",
    [string]$OutputFile = "",
    [switch]$Streaming = $false,
    [Alias("OneLine")]
    [switch]$Minify = $false
)

function Format-XMLContent {
    param(
        [string]$xmlString,
        [Alias("OneLine")]
        [switch]$Minify
    )

    $xml = [xml]$xmlString

    $settings = New-Object System.Xml.XmlWriterSettings
    $settings.Indent = -not $Minify
    $settings.IndentChars = "  "
    $settings.NewLineChars = "`n"

    $tempFile = [System.IO.Path]::GetTempFileName()
    $writer = $null
    try {
        $writer = [System.Xml.XmlWriter]::Create($tempFile, $settings)
        $xml.WriteContentTo($writer)
        $writer.Flush()
        $writer.Close()
        $writer = $null

        return [System.IO.File]::ReadAllText($tempFile, [System.Text.Encoding]::UTF8)
    }
    finally {
        if ($null -ne $writer) {
            $writer.Dispose()
        }
        if (Test-Path -LiteralPath $tempFile) {
            Remove-Item -LiteralPath $tempFile -Force
        }
    }
}

function Format-XMLContentStreaming {
    param(
        [string]$inputFilePath,
        [string]$outputFilePath,
        [Alias("OneLine")]
        [switch]$Minify
    )

    $readerSettings = New-Object System.Xml.XmlReaderSettings
    $readerSettings.ConformanceLevel = "Document"
    $readerSettings.IgnoreWhitespace = [bool]$Minify

    $writerSettings = New-Object System.Xml.XmlWriterSettings
    $writerSettings.ConformanceLevel = [System.Xml.ConformanceLevel]::Document
    $writerSettings.Indent = -not $Minify
    $writerSettings.IndentChars = "  "
    $writerSettings.NewLineChars = "`n"
    $writerSettings.Encoding = [System.Text.UTF8Encoding]::new($false)

    $reader = $null
    $writer = $null
    try {
        $reader = [System.Xml.XmlReader]::Create($inputFilePath, $readerSettings)
        $writer = [System.Xml.XmlWriter]::Create($outputFilePath, $writerSettings)

        if ($reader.Read()) {
            do {
                # WriteNode advances the reader to the next sibling, so do not call Read() again here.
                $writer.WriteNode($reader, $false)
            } while (-not $reader.EOF)
        }
    }
    finally {
        if ($null -ne $reader) {
            $reader.Dispose()
        }
        if ($null -ne $writer) {
            $writer.Dispose()
        }
    }
}

# Main logic
if ([string]::IsNullOrWhiteSpace($InputFile)) {
    Write-Host "XML Formatter" -ForegroundColor Cyan
    Write-Host "=============" -ForegroundColor Cyan
    Write-Host ""
    $InputFile = Read-Host "Enter path to XML file"
}

try {
    if (-not (Test-Path -LiteralPath $InputFile -PathType Leaf)) {
        throw "File not found: $InputFile"
    }

    $inputPath = [System.IO.Path]::GetFullPath($InputFile)
    if ([string]::IsNullOrWhiteSpace($OutputFile)) {
        $inputDirectory = [System.IO.Path]::GetDirectoryName($inputPath)
        $inputExtension = [System.IO.Path]::GetExtension($inputPath)
        if ([string]::IsNullOrWhiteSpace($inputExtension)) {
            $inputExtension = ".xml"
        }
        $inputStem = [System.IO.Path]::GetFileNameWithoutExtension($inputPath)
        $baseStem = [System.Text.RegularExpressions.Regex]::Replace(
            $inputStem,
            '_(formatted|minified|oneline)(?:_\d+)?$',
            '',
            [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
        )
        $marker = if ($Minify) { "_minified" } else { "_formatted" }
        $outputStem = $baseStem + $marker
        $OutputFile = [System.IO.Path]::Combine($inputDirectory, $outputStem + $inputExtension)
        $number = 0
        while ([string]::Equals($inputPath, [System.IO.Path]::GetFullPath($OutputFile), [System.StringComparison]::OrdinalIgnoreCase) -or (Test-Path -LiteralPath $OutputFile)) {
            $number++
            $OutputFile = [System.IO.Path]::Combine($inputDirectory, "${outputStem}_${number}${inputExtension}")
        }
    }
    $outputPath = [System.IO.Path]::GetFullPath($OutputFile)
    if ([string]::Equals($inputPath, $outputPath, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "The output file must be different from the input file. The original was not changed."
    }

    $outputDirectory = [System.IO.Path]::GetDirectoryName($outputPath)
    if (-not [System.IO.Directory]::Exists($outputDirectory)) {
        throw "Output directory does not exist: $outputDirectory"
    }
    $temporaryOutputPath = [System.IO.Path]::Combine(
        $outputDirectory,
        "." + [System.IO.Path]::GetFileName($outputPath) + "." + [System.Guid]::NewGuid().ToString("N") + ".tmp"
    )

    $fileSize = (Get-Item -LiteralPath $inputPath).Length / 1MB
    Write-Host "File size: $([Math]::Round($fileSize, 2)) MB" -ForegroundColor Cyan

    # Auto-select streaming for large files
    if ($fileSize -gt 50) {
        Write-Host "Large file detected. Using streaming mode for better performance..." -ForegroundColor Yellow
        $Streaming = $true
    }

    if ($Streaming) {
        $action = if ($Minify) { "minifying" } else { "formatting" }
        Write-Host "Reading and $action XML (streaming mode)..." -ForegroundColor Yellow
        Format-XMLContentStreaming -inputFilePath $inputPath -outputFilePath $temporaryOutputPath -Minify:$Minify
    } else {
        Write-Host "Reading XML file..." -ForegroundColor Yellow
        $xmlContent = Get-Content -LiteralPath $inputPath -Raw

        $action = if ($Minify) { "Minifying" } else { "Formatting" }
        Write-Host "$action XML..." -ForegroundColor Yellow
        $formattedXml = Format-XMLContent -xmlString $xmlContent -Minify:$Minify
        [System.IO.File]::WriteAllText($temporaryOutputPath, $formattedXml, [System.Text.Encoding]::UTF8)
    }

    Move-Item -LiteralPath $temporaryOutputPath -Destination $outputPath -Force
    $resultName = if ($Minify) { "Minified XML" } else { "Formatted XML" }
    Write-Host "Done! $resultName saved to: $outputPath" -ForegroundColor Green
    exit 0
}
catch {
    if ($temporaryOutputPath -and (Test-Path -LiteralPath $temporaryOutputPath)) {
        Remove-Item -LiteralPath $temporaryOutputPath -Force -ErrorAction SilentlyContinue
    }
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
}
