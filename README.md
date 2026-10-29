# AnyXML Tools

Format and check XML documents in Visual Studio Code.

## Requirements

- **PowerShell** is required for formatting and validation of files over 50 MiB. The extension looks for `pwsh` on macOS and Linux, or `powershell.exe` on Windows. If it is installed somewhere else, set `anyxml.powershellExecutable` to its executable path in VS Code Settings.

## Use AnyXML

For regular XML files, either right-click in the editor or right-click the file in Explorer. Choose:

- **AnyXML: Format XML Document** to format the document. Large file conversions use streaming mode.
- **AnyXML: Convert XML to One Line** to remove formatting whitespace and compact the document. For a regular open document, this replaces its contents; use Undo to reverse it.
- **AnyXML: Validate XML** to check that the document is well-formed. The first syntax error appears in the Problems panel.

### Large files

- VS Code cannot synchronize files over 50 MiB with extensions, so keep these files closed in the editor.
- Right-click the file in Explorer to run a command directly from disk:
  - **AnyXML: Format XML Document** saves a separate `*_formatted.xml` copy.
  - **AnyXML: Convert XML to One Line** saves a separate `*_oneline.xml` copy.
  - **AnyXML: Validate XML** checks the file and reports the first syntax error.
- If an output name already exists, AnyXML adds a number. Formatting and one-line conversion leave the original unchanged.

Validation shows a green or red result in the status bar and a message with the error location. VS Code cannot show editor diagnostics or live validation for these files because they cannot be opened in the editor.

You can also run these commands from the Command Palette (`Cmd+Shift+P` on macOS, `Ctrl+Shift+P` on Windows/Linux). **Format Document** also uses AnyXML for XML files.

## Validation status

The status bar shows green when the active XML file is valid and red when it has a syntax error. Hover over the status to see the error location and message; click it to validate again. Validation runs after edits (debounced by 500 ms) and when you save.

To check another file, click the status bar or run **AnyXML: Validate XML** from the Command Palette or a context menu.

Validation checks XML syntax and well-formedness. It does not validate an XML Schema (XSD).
