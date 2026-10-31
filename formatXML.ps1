#Requires -Version 3.0
param(
    [string]$InputFile = "",
    [string]$OutputFile = "",
    [switch]$Streaming = $false,
    [Alias("OneLine")]
    [switch]$Minify = $false
)

function Write-XMLTextPreservingLineBreaks {
    param(
        [System.Xml.XmlWriter]$writer,
        [string]$value
    )

    $segmentStart = 0
    for ($index = 0; $index -lt $value.Length; $index++) {
        if ($value[$index] -eq "`r" -or $value[$index] -eq "`n") {
            if ($index -gt $segmentStart) {
                $writer.WriteString($value.Substring($segmentStart, $index - $segmentStart))
            }
            $writer.WriteCharEntity($value[$index])
            $segmentStart = $index + 1
        }
    }

    if ($segmentStart -lt $value.Length) {
        $writer.WriteString($value.Substring($segmentStart))
    }
}

function Write-XMLReaderToWriter {
    param(
        [System.Xml.XmlReader]$reader,
        [System.Xml.XmlWriter]$writer
    )

    $elementDepth = 0
    while ($reader.Read()) {
        switch ($reader.NodeType.ToString()) {
            "XmlDeclaration" {
                if ($reader.Value -match 'standalone\s*=\s*["'']yes["'']') {
                    $writer.WriteStartDocument($true)
                } elseif ($reader.Value -match 'standalone\s*=\s*["'']no["'']') {
                    $writer.WriteStartDocument($false)
                } else {
                    $writer.WriteStartDocument()
                }
                break
            }
            "Element" {
                $writer.WriteStartElement($reader.Prefix, $reader.LocalName, $reader.NamespaceURI)
                if ($reader.MoveToFirstAttribute()) {
                    do {
                        $writer.WriteStartAttribute($reader.Prefix, $reader.LocalName, $reader.NamespaceURI)
                        $writer.WriteString($reader.Value)
                        $writer.WriteEndAttribute()
                    } while ($reader.MoveToNextAttribute())
                    $reader.MoveToElement() | Out-Null
                }
                if ($reader.IsEmptyElement) {
                    $writer.WriteEndElement()
                } else {
                    $elementDepth++
                }
                break
            }
            "EndElement" {
                $writer.WriteFullEndElement()
                $elementDepth--
                break
            }
            { $_ -in @("Text", "CDATA") } {
                # CDATA is emitted as ordinary text; character references preserve
                # line breaks while keeping the serialized XML on one line.
                Write-XMLTextPreservingLineBreaks -writer $writer -value $reader.Value
                break
            }
            { $_ -in @("Whitespace", "SignificantWhitespace") } {
                # Ignore document-level whitespace; character references are only
                # valid inside the document element.
                if ($elementDepth -gt 0) {
                    Write-XMLTextPreservingLineBreaks -writer $writer -value $reader.Value
                }
                break
            }
            "Comment" {
                $writer.WriteComment($reader.Value)
                break
            }
            "ProcessingInstruction" {
                $writer.WriteProcessingInstruction($reader.Name, $reader.Value)
                break
            }
            "DocumentType" {
                $writer.WriteDocType(
                    $reader.Name,
                    $reader.GetAttribute("PUBLIC"),
                    $reader.GetAttribute("SYSTEM"),
                    $reader.Value
                )
                break
            }
            "EntityReference" {
                $writer.WriteEntityRef($reader.Name)
                break
            }
        }
    }
}

function Format-XMLContent {
    param(
        [string]$inputFilePath,
        [Alias("OneLine")]
        [switch]$Minify
    )

    if ($Minify) {
        $readerSettings = New-Object System.Xml.XmlReaderSettings
        $readerSettings.ConformanceLevel = "Document"
        $readerSettings.IgnoreWhitespace = $false

        $settings = New-Object System.Xml.XmlWriterSettings
        $settings.Indent = $false
        $settings.NewLineHandling = [System.Xml.NewLineHandling]::Entitize

        $tempFile = [System.IO.Path]::GetTempFileName()
        $reader = $null
        $writer = $null
        try {
            $reader = [System.Xml.XmlReader]::Create($inputFilePath, $readerSettings)
            $writer = [System.Xml.XmlWriter]::Create($tempFile, $settings)
            Write-XMLReaderToWriter -reader $reader -writer $writer
            $writer.Flush()
            $writer.Close()
            $writer = $null
            return [System.IO.File]::ReadAllText($tempFile, [System.Text.Encoding]::UTF8)
        }
        finally {
            if ($null -ne $reader) {
                $reader.Dispose()
            }
            if ($null -ne $writer) {
                $writer.Dispose()
            }
            if (Test-Path -LiteralPath $tempFile) {
                Remove-Item -LiteralPath $tempFile -Force
            }
        }
    }

    $xml = New-Object System.Xml.XmlDocument
    # Loading the file directly lets the XML parser honor its BOM or declared
    # encoding instead of decoding bytes with PowerShell's default text encoding.
    $xml.Load($inputFilePath)

    $settings = New-Object System.Xml.XmlWriterSettings
    $settings.Indent = $true
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
    # XML alone cannot distinguish formatting whitespace from meaningful text.
    # Keep whitespace nodes in minify mode to preserve the document's content.
    $readerSettings.IgnoreWhitespace = $false

    $writerSettings = New-Object System.Xml.XmlWriterSettings
    $writerSettings.ConformanceLevel = [System.Xml.ConformanceLevel]::Document
    $writerSettings.Indent = -not $Minify
    $writerSettings.IndentChars = "  "
    $writerSettings.NewLineChars = "`n"
    if ($Minify) {
        $writerSettings.NewLineHandling = [System.Xml.NewLineHandling]::Entitize
    }
    $writerSettings.Encoding = [System.Text.UTF8Encoding]::new($false)

    $reader = $null
    $writer = $null
    try {
        $reader = [System.Xml.XmlReader]::Create($inputFilePath, $readerSettings)
        $writer = [System.Xml.XmlWriter]::Create($outputFilePath, $writerSettings)

        if ($Minify) {
            Write-XMLReaderToWriter -reader $reader -writer $writer
        } elseif ($reader.Read()) {
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
        $action = if ($Minify) { "Minifying" } else { "Formatting" }
        Write-Host "$action XML..." -ForegroundColor Yellow
        $formattedXml = Format-XMLContent -inputFilePath $inputPath -Minify:$Minify
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
