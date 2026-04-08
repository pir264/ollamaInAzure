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

VM-grootte aanpassen: GitHub Variable `VM_SIZE` wijzigen en de deploy workflow opnieuw uitvoeren.

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
2. Wijzig `VM_SIZE` naar de gewenste SKU (zie tabel hieronder)
3. Voer **Deploy Infrastructure** workflow uit

| VM-grootte | vCPU | RAM | Indicatieve kosten/uur |
|------------|------|-----|------------------------|
| `Standard_D4s_v5` | 4 | 16 GB | ~€0,17 |
| `Standard_D8s_v5` | 8 | 32 GB | ~€0,34 |
| `Standard_D16s_v5` | 16 | 64 GB | ~€0,68 |

## Extra model toevoegen

SSH naar de VM en voer uit:

```bash
ollama pull llama3.2
ollama list
```

## Infrastructuur verwijderen

**Actions → Deploy Infrastructure → Run workflow**, vul bij `destroy` de waarde `true` in.

> De Terraform state storage (`rg-terraform-state`) wordt niet verwijderd door Terraform. Die kun je daarna handmatig verwijderen via `az group delete --name rg-terraform-state`.
