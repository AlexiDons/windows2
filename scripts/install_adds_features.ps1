# Installeer alleen de features, geen promotie
Write-Host "Installeren van AD-Domain-Services en DNS features..."

Install-WindowsFeature -Name AD-Domain-Services, DNS -IncludeManagementTools

Write-Host "Features geïnstalleerd. Klaar voor DC promotie."