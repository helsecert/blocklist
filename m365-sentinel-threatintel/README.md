# Integrasjon for Sentinel Threat Intelligence

Denne løsningen henter indikatorer fra Helse- og KommuneCERTs blokkeringslister og sender dem inn til Sentinel Threat Intelligence via Threat Intelligence Upload API.  


## Forutsetninger

Det er et par ting som må på plass for å få løsningen til å fungere.  

**Azure Rolle**  
Vi trenger en SPN med `Microsoft Sentinel Contributer` rolle i Log Analytic Workspace.  
For veiledning til å opprette applikasjon og sette opp rollen kan du sjekke her: [Microsoft Learn](https://learn.microsoft.com/en-us/azure/sentinel/connect-threat-intelligence-upload-api#register-an-azure-ad-application)  


**Helse- og KommuneCERT API key**  
Du trenger selvfølgelig API-nøkkel til API'et.  


## Oppsett

1. Installer løsningen på din foretrukne måte  
   Virtualenv:  
   ```bash
   python3 -m venv .venv
   source .venv/bin/activate
   pip install git+https://github.com/helsecert/blocklist/#subdirectory=m365-sentinel-threatintel
   ```
   eventuellt pipx:  
   ```bash
   pipx install git+https://github.com/helsecert/blocklist/#subdirectory=m365-sentinel-threatintel
   ```

2. Sett opp nødvendige miljøvariabler:
   ```bash
   export WORKSPACE_ID="your-sentinel-workspace-id"
   export SUBSCRIPTION_ID="your-azure-subscription-id"
   export BLOCKLIST_API_KEY="your-hkcert-api-key"
   export AZURE_CLIENT_ID="your-application-id"
   export AZURE_TENANT_ID="your-tenant-id"
   export AZURE_CLIENT_SECRET="your-application-secret"
   export LOG_LEVEL="INFO"  # ikke påkrevd, satt til INFO som standard
   ```

## Kjør scriptet

```bash
hkc-blocklist-to-sentinel
``` 

## Autentisering
Scriptet støtter autentisering via miljøvariabler med applikasjonshemmelighet som demonstrert over. Men i tillegg så kan du bruke `az cli`. Det gir litt fleksibilitet ift hvor scriptet blir eksekvert fra. Det er også forholdsvis enkelt å bytte over til Managed Identity og gi en User Managed Identity rollen i LAW heller.


## BlocklistClient
Vi har tatt interaksjonen med API'et ut i en egen klient for enkel gjenbruk i lignende løsninger.  
Dette ligger under `./hkcblocklist2sentinel/hkcblocklist.py`.  

**Eksempel på bruk**
```py
import hkcblocklist

client = hkcblocklist.BlocklistClient(BLOCKLIST_API_KEY)
indicators = client.get_blocklist(type='domain')

for indicator in indicators:
   print(f"Indicator value: {indicator.value}")
   print(f"Date added: {indicator.date_added}")
```


## Referanser
[Sentinel Threat intelligence upload API reference](https://learn.microsoft.com/en-us/azure/sentinel/stix-objects-api)  
[Threat Intelligence in Microsoft Sentinel](https://learn.microsoft.com/en-us/azure/sentinel/understand-threat-intelligence)  