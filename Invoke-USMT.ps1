<#
.SYNOPSIS
    This tool helps migrate data using USMT from a domain-joined source computer to a destination computer.
.EXAMPLE
    $Credential = Get-Credential
     C:\Scripts\PowerShell> invoke-USMT -SourceComputer 'win7' -DestinationComputer 'win10' -UserName 'dfrancis' -Credential $Credential -SharePath '\\FileServer\USMT$\' -USMTFilesPath '\\FileServer\USMT$\USMTFiles\' -Domain 'DOMAIN'
#>
function Invoke-USMT {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$SourceComputer,
        [Parameter(Mandatory=$true)]
        [string]$DestinationComputer,
        [Parameter(Mandatory=$true)]
        [string]$UserName,
        [Parameter(Mandatory=$true)]
        [string]$SharePath,
        [Parameter(Mandatory=$true)]
        [string]$USMTFilesPath,
        [Parameter(Mandatory=$true)]
        [string]$Domain,
        [Parameter(Mandatory=$true, HelpMessage='Enter USMT key')]
        [Security.SecureString]$SecureKey,
        [pscredential]$Credential
    )
    
    begin 
    {
        if (!(Test-Connection -ComputerName $SourceComputer -Count 2))
        {
            Write-Warning -Message "Count not ping $SourceComputer"
            Break
        }
         if (!(Test-Connection -ComputerName $DestinationComputer -Count 2))
        {
            Write-Warning -Message "Count not ping $DestinationComputer"
            Break
        }
    }
    
    process 
    {
        #Copy USMT files to remote computers
        Try 
        {
            Copy-Item -Path $USMTFilesPath -Destination "\\$SourceComputer\C$\" -ErrorAction Stop -Recurse -force -con
            Copy-Item -Path $USMTFilesPath -Destination "\\$DestinationComputer\C$\" -ErrorAction Stop -Recurse -force
        }
        Catch 
        {
            Write-Error $_
            Break
        }
        #Enable CredSSP
        Invoke-Command -ComputerName $SourceComputer -Credential $Credential -ScriptBlock {Enable-WSManCredSSP -Role server -Force} 
        Invoke-Command -ComputerName $DestinationComputer -Credential $Credential -ScriptBlock {Enable-WSManCredSSP -Role server -Force} 
        Enable-WSManCredSSP -Role client -DelegateComputer $SourceComputer -Force
        Enable-WSManCredSSP -Role client -DelegateComputer $DestinationComputer -Force 
        
        #Start startscan on source
        Invoke-Command -ComputerName $SourceComputer -Authentication Credssp -Credential $Credential -Scriptblock {
            $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Using:SecureKey)
            $Key = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
            c:\USMTFiles\scanstate.exe "$Using:SharePath\$Using:Username" /i:c:\usmtfiles\printers.xml /i:c:\usmtfiles\custom.xml /i:c:\usmtfiles\migdocs.xml /i:c:\usmtfiles\migapp.xml /v:13 /ui:$Using:Domain\$Using:UserName /c /localonly /encrypt /key:$Key /listfiles:c:\usmtfiles\listfiles.txt /ue:pcadmin /ue:$Using:Domain\*
        } -ArgumentList {$UserName,$SharePath,$SecureKey,$SourceComputer,$Domain}
#
        #Start loadscan on destination
        Invoke-Command -ComputerName $DestinationComputer -Authentication Credssp -Credential $Credential -Scriptblock {
            $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Using:SecureKey)
            $Key = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
            c:\USMTFiles\loadstate.exe "$Using:SharePath\$Using:Username" /i:c:\usmtfiles\printers.xml /i:c:\usmtfiles\custom.xml /i:c:\usmtfiles\migdocs.xml /i:c:\usmtfiles\migapp.xml /v:13 /ui:$Using:Domain\$Using:username /c /decrypt /key:$Key
        } -ArgumentList {$UserName,$SharePath,$SecureKey,$DestinationComputer,$Domain}

        #Remove USMT files on remote computers
        Remove-Item \\$SourceComputer\C$\USMTFiles -Force -Recurse
        Remove-Item \\$DestinationComputer\C$\USMTFiles -Force -Recurse

        #Disable CredSSP on remote computers
        Invoke-Command -ComputerName $SourceComputer -Credential $Credential -ScriptBlock {Disable-WSManCredSSP -Role server }
        Invoke-Command -ComputerName $DestinationComputer -Credential $Credential -ScriptBlock {Disable-WSManCredSSP -Role server }  
        Disable-WSManCredSSP -Role client        
     }
}
