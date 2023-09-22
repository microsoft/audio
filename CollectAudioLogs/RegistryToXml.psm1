# Copyright (c) Microsoft Corporation. All rights reserved.

# Generates XML for a registry key in the same format as Diagtrack
function Get-RegKeyQueryXml {
    Param
    (
        [Parameter(Mandatory=$True)]
        [Microsoft.Win32.RegistryHive]$hive,

        [Parameter(Mandatory=$True)]
        [string]$subkey
    )

    # Create xml document with declaration
    $xml = New-Object xml;
    $decl = $xml.CreateXmlDeclaration('1.0', 'UTF-8', 'yes');
    $null = $xml.InsertBefore($decl, $xml.DocumentElement);

    # Create root node and add to the document
    $root = $xml.CreateElement('regkeyquery');
    $null = $xml.AppendChild($root);

    # Generate xml for registry and add to the document

    try {
        $hklm = [Microsoft.Win32.RegistryKey]::OpenBaseKey($hive, [Microsoft.Win32.RegistryView]::Registry64);
        $key = $hklm.OpenSubKey($subkey);

        $keyNode = Get-RegistryXml -key $key -xml $xml;
        $null = $root.AppendChild($keyNode);
    }
    catch {}

    return $xml;
}

# Generates XML from the given registry key and all its values and subkeys
function Get-RegistryXml {
    Param
    (
        [Parameter(Mandatory=$True)]
        [Microsoft.Win32.RegistryKey]$key,

        [Parameter(Mandatory=$True)]
        [System.Xml.XmlDocument]$xml
    )
    $keyNode = $xml.CreateElement('key');
    $nameNode = $xml.CreateElement('name');
    $nameNode.InnerText = $key.Name;
    $null = $keyNode.AppendChild($nameNode);

    $key.GetValueNames() | ForEach-Object {
        $name = $_;
        $type = $key.GetValueKind($name);
        $data = $key.GetValue($name);

        # Convert name, type, and data to friendly xml formats
        switch($type)
        {
            'String' {
                $type = 'REG_SZ';
                break;
            }
            'Binary' {
                $type = 'REG_BINARY';
                $data = ($data | ForEach-Object { $_.ToString("X2") }) -join ""; 
                break;
            }
            'DWord' {
                $type = 'REG_DWORD';
                $data = "0x$($data.ToString('X'))"; 
                break;
            }
            'QWord' {
                $type = 'REG_QWORD';
                $data = "0x$($data.ToString('X'))"; 
                break;
            }
            'MultiString' {
                $type = 'REG_MULTI_SZ'; 
                $data = ($data -join '|'); 
                break;
            }
            'ExpandString' {
                $type = 'REG_EXPAND_SZ';
                break;
            }
            'Unknown' {
                break;
            }
            default {
                Write-Host "Unrecognized registry data type $type";
                break;
            }
        }

        $valueNode = $xml.CreateElement('value');
        
        $nameNode = $xml.CreateElement('name');
        $nameNode.InnerText = $name;
        $null = $valueNode.AppendChild($nameNode);

        $typeNode = $xml.CreateElement('type');
        $typeNode.InnerText = $type;
        $null = $valueNode.AppendChild($typeNode);

        $dataNode = $xml.CreateElement('data');
        $dataNode.InnerText = $data;
        $null = $valueNode.AppendChild($dataNode);

        $null = $keyNode.AppendChild($valueNode);
    };

    $key.GetSubKeyNames() | ForEach-Object {
        try {
            $subKey = $key.OpenSubKey($_);
        } catch {
            return;
        }

        $subKeyNode = Get-RegistryXml -key $subKey -xml $xml;
        $null = $keyNode.AppendChild($subKeyNode);
    };

    return $keyNode;
}
