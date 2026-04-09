# Ollama in Azure

Deployt een [Ollama](https://ollama.com) instantie op een Azure VM via GitHub Actions en Terraform. De VM is alleen toegankelijk vanaf jouw eigen IP-adres en stopt automatisch om 20:00 CET.

## Kenmerken

- **Alleen jouw toegang** — NSG-regels blokkeren alle andere IP-adressen
- **Kosten bewust** — VM staat standaard uit; je betaalt alleen voor opslag (~€20/maand) als de VM niet draait
- **Automatische stop** — VM dealloceert elke dag om 20:00 CET
- **Geen code wijzigen** — VM-grootte en modellen aanpassen via GitHub Variables
- **Persistente modellen** — Ollama-modellen worden opgeslagen op een losse data disk die de VM overleeft

## Kosten

| Scenario | Schatting |
|----------|-----------|
| VM uit (alleen disk + IP) | ~€20/maand |
| Standard_D8s_v5, 8u/dag, 22 werkdagen | ~€90/maand |
| Standard_D4s_v5, 8u/dag, 22 werkdagen | ~€57/maand |
| Standard_NV6ads_A10_v5 Spot, 8u/dag, 22 werkdagen | ~€18/maand |

VM-grootte en Spot aanpassen via GitHub Variables — geen code wijzigen nodig.

## Workflows

| Workflow | Trigger | Beschrijving |
|----------|---------|--------------|
| **Deploy Infrastructure** | Handmatig | Terraform apply — maakt alle Azure-resources aan of werkt ze bij |
| **Start Ollama VM** | Handmatig | Start de VM en toont het IP-adres in de samenvatting |
| **Stop Ollama VM** | Handmatig | Dealloceert de VM (compute-kosten stoppen) |
| **Automatisch stoppen** | Dagelijks 20:00 CET | Dealloceert de VM automatisch |
| **IP-adres bijwerken** | Handmatig | Werkt de NSG-regels bij als jouw thuis-IP is veranderd |

## Vereisten

- Azure-abonnement met Contributor-rechten
- GitHub-repository
- Azure CLI lokaal geïnstalleerd (`winget install Microsoft.AzureCLI`)

## Eenmalige setup

### 1. Terraform state storage aanmaken

```bash
az login

az group create --name "rg-terraform-state" --location "westeurope"

STORAGE_ACCOUNT=$(az storage account create \
  --name "satollamatf$(openssl rand -hex 4)" \
  --resource-group "rg-terraform-state" \
  --location "westeurope" \
  --sku "Standard_LRS" \
  --query name --output tsv)

az storage container create \
  --name "tfstate" \
  --account-name "$STORAGE_ACCOUNT" \
  --auth-mode login

echo "Storage account naam: $STORAGE_ACCOUNT"
```

### 2. Service Principal aanmaken

```bash
SUBSCRIPTION_ID=$(az account show --query id -o tsv)

az ad sp create-for-rbac \
  --name "sp-ollama-github-actions" \
  --role "Contributor" \
  --scopes "/subscriptions/$SUBSCRIPTION_ID" \
  --years 2
```

Sla de output op — het wachtwoord (`password`) is maar één keer zichtbaar.

### 3. SSH-sleutelpaar genereren

Azure ondersteunt alleen RSA-sleutels:

```bash
ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa_ollama -C "ollama-azure"
```

### 4. GitHub Secrets instellen

Ga naar: **Settings → Secrets and variables → Actions → Secrets**

| Secret | Waarde |
|--------|--------|
| `AZURE_CLIENT_ID` | `appId` uit stap 2 |
| `AZURE_CLIENT_SECRET` | `password` uit stap 2 |
| `AZURE_SUBSCRIPTION_ID` | `az account show --query id -o tsv` |
| `AZURE_TENANT_ID` | `tenant` uit stap 2 |
| `TF_BACKEND_RESOURCE_GROUP` | `rg-terraform-state` |
| `TF_BACKEND_STORAGE_ACCOUNT` | naam uit stap 1 |
| `TF_BACKEND_CONTAINER` | `tfstate` |
| `SSH_PUBLIC_KEY` | inhoud van `~/.ssh/id_rsa_ollama.pub` |

### 5. GitHub Variables instellen

Ga naar: **Settings → Secrets and variables → Actions → Variables**

| Variable | Standaard | Beschrijving |
|----------|-----------|--------------|
| `AZURE_LOCATION` | `westeurope` | Azure-regio |
| `VM_SIZE` | `Standard_D8s_v5` | VM-grootte — aanpassen voor meer/minder performance |
| `VM_DATA_DISK_SIZE_GB` | `128` | Schijfruimte voor Ollama-modellen in GB |
| `OLLAMA_PORT` | `11434` | Poort voor de Ollama API |
| `RESOURCE_GROUP_NAME` | `rg-ollama-prod` | Resource group voor de Ollama-resources |
| `VM_NAME` | `vm-ollama` | Naam van de VM |
| `DEFAULT_MODEL` | `gemma4:latest` | Model dat bij eerste boot wordt gepulled |
| `ALLOWED_IP` | jouw IP | Jouw publieke IP-adres (check via [ifconfig.me](https://ifconfig.me)) |
| `USE_SPOT` | `false` | `true` om Azure Spot pricing te gebruiken |

### 6. Deployen

```bash
git add .
git commit -m "Initial Ollama Azure infrastructure"
git push
```

Daarna: **Actions → Deploy Infrastructure → Run workflow**

Na een succesvolle deploy direct **Stop Ollama VM** uitvoeren zodat de VM niet onnodig doorloopt.

## Dagelijks gebruik

1. **Actions → Start Ollama VM → Run workflow**
2. Wacht ~90 seconden
3. IP-adres staat in de workflow-samenvatting
4. Ollama aanroepen:

```bash
curl http://<IP>:11434/api/generate \
  -d '{"model":"gemma4:latest","prompt":"Hallo, hoe gaat het?"}'
```

5. VM stopt automatisch om 20:00 CET

## SSH-verbinding

```bash
ssh -i ~/.ssh/id_rsa_ollama ollamaadmin@<IP>
```

## Thuis-IP veranderd?

Voer de **IP-adres bijwerken** workflow uit en vul jouw nieuwe IP in. Je kunt jouw huidige IP opzoeken via [ifconfig.me](https://ifconfig.me).

## VM-grootte aanpassen

Geen code wijzigen nodig:

1. Ga naar **Settings → Secrets and variables → Actions → Variables**
2. Wijzig `VM_SIZE` en/of `USE_SPOT`
3. Voer **Deploy Infrastructure** workflow uit met `recreate_vm = true`

| VM-grootte | vCPU | RAM | GPU | On-demand/uur | Spot/uur |
|------------|------|-----|-----|---------------|----------|
| `Standard_D4s_v5` | 4 | 16 GB | — | ~€0,17 | ~€0,04 |
| `Standard_D8s_v5` | 8 | 32 GB | — | ~€0,34 | ~€0,07 |
| `Standard_D16s_v5` | 16 | 64 GB | — | ~€0,68 | ~€0,14 |
| `Standard_NV6ads_A10_v5` | 6 | 55 GB | 1/6 A10 | ~€0,45 | ~€0,10 |
| `Standard_NV12ads_A10_v5` | 12 | 110 GB | 1/3 A10 | ~€0,90 | ~€0,20 |
| `Standard_NV36ads_A10_v5` | 36 | 440 GB | 1× A10 | ~€3,60 | ~€0,60 |

> **Spot VMs** kunnen door Azure worden geëvicteerd als de capaciteit nodig is. De VM wordt dan deallocated — jouw modellen op de data disk blijven intact. Herstart via de **Start Ollama VM** workflow.

### VM vervangen (bijv. van CPU naar GPU)

Dit kan in één workflow-run zonder de data disk te verliezen:

**Actions → Deploy Infrastructure → Run workflow**
- `vm_size`: nieuwe SKU (bijv. `Standard_NV6ads_A10_v5`)
- `use_spot`: `true` of `false`
- `recreate_vm`: `true`

---

## Azure Container Apps (ACA) — alternatieve deployment

Naast de VM-gebaseerde setup is er een tweede pipeline die Ollama draait in Azure Container Apps. Voordeel: schaalt automatisch naar **0 replicas** na 15 minuten inactiviteit — je betaalt alleen wanneer je Ollama daadwerkelijk gebruikt.

### Wanneer ACA kiezen vs VM?

| | VM (Spot) | ACA |
|--|-----------|-----|
| Cold start | ~90 sec (VM opstarten) | 30–90 sec container + 1–5 min model laden |
| Altijd-aan kosten | ~€20/maand (disk + IP) | ~€14-17/maand (storage + logs) |
| GPU | A10 Spot (~€0,10/uur) | T4 serverless (~€1/uur) |
| Bediening | Handmatig starten/stoppen via workflow | Automatisch, op basis van requests |
| Toegang | HTTP op poort 11434 | HTTPS op poort 443 |

### Vereiste GitHub Variables (ACA-specifiek)

Ga naar: **Settings → Secrets and variables → Actions → Variables**

| Variable | Standaard | Beschrijving |
|----------|-----------|--------------|
| `ACA_LOCATION` | `swedencentral` | Regio — `westeurope` heeft **geen** GPU ACA-profielen |
| `ACA_RESOURCE_GROUP_NAME` | `rg-ollama-aca-prod` | Aparte resource group van de VM |
| `ACA_STORAGE_ACCOUNT_NAME` | `stollamaacamodels` | Globaal uniek, 3-24 tekens |
| `ACA_WORKLOAD_PROFILE_TYPE` | `Consumption` | GPU opt-in via `Consumption-GPU-NC8as-T4` |

### ACA deployen

**Actions → Deploy ACA Infrastructure → Run workflow**

Optionele inputs:
- `workload_profile_type`: kies `Consumption` (CPU), `Consumption-GPU-NC8as-T4` (T4) of `Consumption-GPU-NC24-A100` (A100)
- `container_cpu` en `container_memory`: worden automatisch ingesteld op basis van het profiel

De workflow toont na deployment de HTTPS URL en kosten-advies in de samenvatting.

### ACA GPU workload profiles

| Profile | GPU | ~Kosten/uur | Budget (2u/dag, 22 werkdagen) |
|---------|-----|-------------|-------------------------------|
| `Consumption` | Geen | ~€0,03 | ~€16/maand totaal |
| `Consumption-GPU-NC8as-T4` | NVIDIA T4 | ~€1,00 | ~€61/maand |
| `Consumption-GPU-NC24-A100` | NVIDIA A100 | ~€3,50 | ~€171/maand ⚠️ |

> ⚠️ GPU-profielen vereisen mogelijk een quota-aanvraag bij Azure Support. Controleer beschikbaarheid via:
> ```bash
> az containerapp env workload-profile list-supported --location swedencentral --output table
> ```

### Ollama aanroepen via ACA

ACA exposeert altijd **HTTPS op poort 443** — niet poort 11434. Stel je client in op de URL uit de workflow-samenvatting:

```bash
# Model pullen (eerste keer)
curl https://<fqdn>/api/pull -d '{"name":"gemma4:latest"}'

# Genereren
curl https://<fqdn>/api/generate \
  -d '{"model":"gemma4:latest","prompt":"Hallo, hoe gaat het?"}'
```

### Cold start

Na 15 minuten inactiviteit schaalt ACA naar 0. De eerste request daarna wacht:
1. ~30–90 sec voor container startup
2. ~1–5 min voor model laden van Azure Files

Stel je client timeout in op minimaal **5 minuten**.

### ACA infrastructuur verwijderen

**Actions → Deploy ACA Infrastructure → Run workflow**, vul bij `destroy` de waarde `true` in.

---

## Extra model toevoegen

SSH naar de VM en voer uit:

```bash
ollama pull llama3.2
ollama list
```

## Infrastructuur verwijderen

**Actions → Deploy Infrastructure → Run workflow**, vul bij `destroy` de waarde `true` in.

> De Terraform state storage (`rg-terraform-state`) wordt niet verwijderd door Terraform. Die kun je daarna handmatig verwijderen via `az group delete --name rg-terraform-state`.
