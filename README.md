# Stack LLM On-Prem - ollama + Open WebUI
**Autore:** Vito Collica  
**Codice variante:** D11  
**Repo:** https://github.com/vitoc-dspa/nv-progettino-d11-collica

## 1. Obiettivo
Il progetto implementa uno stack locale completo per l'inferenza di modelli linguistici (LLM) e Retrieval-Augmented Generation (RAG), pensato per ambienti con vincoli stringenti di privacy e sicurezza, come le Pubbliche Amministrazioni, deployata tramite Docker Compose, garantisce privacy dei dati, funzionamento offline e indipendenza da cloud esterni.

## 2. Architettura

### 2.1. Container
Lo stack è composto da quattro servizi containerizzati, orchestrati e isolati tramite reti Docker dedicate:
- **`openwebui`**: Interfaccia web per chat, gestione modelli, RAG e upload documenti
- **`ollama`**: Motore di inferenza LLM
- **`pgvector`**: Database PostgreSQL esteso per embedding vettoriali e persistenza della memoria a lungo termine
- **`caddy`**: Reverse proxy HTTPS per SSL termination dei servizi Open WebUI e ollama

Open WebUI è configurato per il funzionamento offline tramite il server ollama, ollama è configurato in modalità offline-first (OLLAMA_NO_CLOUD=1), eliminando dipendenze esterne una volta caricato il modello.

### 2.2. Architettura di Rete e Isolamento

La comunicazione tra i servizi è governata da cinque reti Docker distinte, applicando il principio del least privilege. Questo garantisce che ogni componente abbia accesso solo alle risorse strettamente necessarie, minimizzando la superficie di attacco.

Flusso di Comunicazione

```text
Host (Porte 80, 443, 11434)
      │
      ▼
┌─────────────────────────────────────────────────────────────────────┐
│                        Caddy (Reverse Proxy)                        │
│  • Terminazione TLS                                                 │
│  • Porte: 80,443 -> OpenWebUI | 11434 -> Ollama                     │
│  • Reti:                                                            │
│    - proxy (nodi interni)                                           │
│    - portmapping_limited_internet_proxy (outbound/port mapping host)│
└───────┬───────────────────────────────┬─────────────────────────────┘
        │ (Rete: proxy)                 │ (Rete: proxy)
        ▼                               ▼
┌──────────────────────────────┐  ┌──────────────────────────────┐
│        Open WebUI            │  │          Ollama              │
│  • Interfaccia Web           │  │  • Motore Inferenza          │
│  • RAG & Embeddings          │  │  • Gestione Modelli          │
│  • Reti:                     │  │  • Reti:                     │
│    - proxy                   │  │    - proxy                   │
│    - dbnet (DB)              │  │    - internet_ollama (out)   │
│    - internet_openwebui (out)│  └──────────────────────────────┘
└───────┬──────────────────────┘
        │ (Rete: dbnet)
        ▼
┌──────────────────────────────┐
│         PGVector             │
│  • DB PostgreSQL + Vettori   │
│  • Rete: dbnet (Internal)    │
└──────────────────────────────┘
```

**Dettaglio delle Reti**

* **proxy** (Bridge,Internal): Rete privata che collega Caddy, Open WebUI e Ollama. Permette al reverse proxy di instradare le richieste HTTPS verso i backend. Essendo internal, i container su questa rete non hanno accesso diretto a Internet, costringendo il traffico esterno a passare attraverso le reti dedicate.
* **dbnet** (Bridge,Internal): Rete isolata che collega esclusivamente Open WebUI e PGVector. Il database è inaccessibile dall’host o da altri servizi, garantendo che i dati sensibili (chat, embedding, utenti) rimangano confinati.
* **internet_openwebui** (Bridge): Fornisce a Open WebUI l’accesso outbound a Internet per funzionalità RAG (web search), caricamento documenti remoti o chiamate API esterne, isolando questo traffico dal resto dello stack.
* **internet_ollama** (Bridge): Permette a Ollama di effettuare il pull dei modelli e verificare aggiornamenti. Il traffico in uscita è separato da quello di Open WebUI per maggiore controllo e debugging.
* **portmapping_limited_internet_proxy** (Bridge, No Masquerade): Rete dedicata a Caddy per permettere il mapping delle porte verso l’host.
        Nota tecnica: Senza una rete esterna esplicita, il mapping delle porte del proxy all’host potrebbe fallire. Questa rete rappresenta un compromesso necessario: abilita la connettività outward per il proxy mantenendo il NAT limitato, allo scopo di non permettere al proxy l'accesso a internet, o comunque limitarlo.

**Accesso Esterno**

Caddy espone le porte 80 (redirect HTTP→HTTPS), 443 (HTTPS per Open WebUI) e 11434 (API Ollama) all’host. La terminazione SSL è gestita centralmente da Caddy, mascherando le porte interne dei servizi backend.

## 3. Prerequisiti
- **OS:** Linux, Windows (tramite WSL2)
- **Runtime:** Docker Engine, Docker Compose, NVIDIA Container Toolkit (Per il supporto alle GPU)
- **GPU (Opzionale):** Una o piu' GPU Nvidia per il GPU offloading dei modelli
  - Se una GPU nvidia non è presente, è necessario disattivare l'accesso alla GPU nvidia su ollama nel docker-compose
- **Hardware:** RAM + VRAM ≥ 16 GB, i modelli vengono automaticamente distribuiti tra RAM e VRAM
- **Connessione:** Internet necessario solamente per il pull iniziale di immagini/pacchetti/modelli, successivamente funzionamento offline
- **File:** `.env` compilato con parametri e credenziali DB

## 4. Come riprodurre passo-passo

**Nota:** Alternativamente agli step 3, 4, 6, si puo' eseguire lo script di setup in scripts/setup.sh:
* ```bash
   bash scripts/setup.sh
   ```

1. Clona il repository e entra nella directory:
   ```bash
   git clone https://github.com/vitoc-dspa/nv-progettino-d11-collica && cd nv-progettino-d11-collica
   ```
2. Prepara l'ambiente:
   ```bash
   cp .env.example .env
   # Compila le password e le altre variabili nel file .env
   EDITOR .env 
   ```
3. Crea certificati TLS self-signed per Caddy
     ```bash
     mkdir -p certs_mount
     openssl req -x509 -newkey rsa:4096 -sha256 -days 3650 -nodes \
     -keyout certs_mount/key.key \
     -out certs_mount/cert.crt \
     -subj "/CN=localhost"
     chmod 600 certs_mount/key.key
     chmod 644 certs_mount/cert.crt
     ````
4. Avvia lo stack:
   ```bash
   docker compose up -d
   ```
   *Output atteso:* Creazione reti, download immagini, avvio container senza errori. I volumi sono bind mount per facilitare backup e debugging`.
5. Attendi il completamento del boot (~30s) e verifica lo stato:
   ```bash
   docker compose ps
   ```
6. Scarica un modello leggero per la demo (es. `qwen3.5:2b`):
   ```bash
   sudo docker compose exec ollama ollama pull qwen3.5:2b
   ```
7. Accedi all'interfaccia: `https://localhost`
8. Effettua la prima registrazione, configura il system prompt di default nell'UI e avvia una conversazione.

### 5. Verifica del funzionamento
- **Isolamento di rete:**
  ```bash
  curl -k https://localhost            # Homepage, 200 OK (Caddy → OpenWebUI)
  curl http://localhost:5432           # Connection refused (Postgres interno)
  curl -k https://localhost:11434      # "Ollama is running", 200 OK (Ollama via Caddy)
  ```
- **DB & RAG:**
  ```bash
  docker compose exec pgvector psql -U openwebui -d openwebui -c "\dt"
  ```
  *Output atteso:* Elenco tabelle di Open WebUI: `access_grant`, `message`, `skill`, ecc., salvate dentro il DB `pgvector``.
- **Test RAG:** Carica un file `.txt` nell'UI, selezionalo come contesto e invia una query basata sul contenuto.
- **Persistenza:**
  ```bash
  docker compose down
  docker compose up -d
  ```
  Verifica che chat, documenti e configurazione persistano nei bind mount.

## 6. Teardown del sistema
Si puo' eseguire lo script di teardown in scripts/teardown.sh:
* ```bash
   bash scripts/teardown.sh
   ```

## 7. Riflessioni e punti aperti
- **Isolamento del proxy da internet:** Per massimizzare l'isolamento è opportuno bloccare nel host tutto il traffico proveniente dalla rete portmapping_limited_internet_proxy e diretto verso nodi diversi dal computer host.
- **Costi di memoria:** L'uso di `q8_0` per il KV cache riduce l'impatto sulla VRAM.
  - La memoria disponibile rappresenta un collo di bottiglia per modelli più grandi o per carichi di lavoro RAG intensivi; in un ambiente di produzione sarebbe necessario utilizzare sistemi dotati di elevate risorse computazionali e di memoria.
  - Nuovi sistemi, come Google Turboquant, aiutano a ridurre l'impatto sulla memoria ulteriormente
- **Uso dei bind mount:** L’uso di bind mount invece di volumi Docker semplifica il backup manuale e l’audit dei dati, ma richiede una gestione attenta dei permessi e della struttura delle directory.
- **Miglioramenti proposti:**
  - Automatizzare il pull e autoconfigurazione dei modelli
  - Aggiungere healthcheck per i servizi
  - Implementare rate-limiting e logging centralizzato su Caddy
  - Implementare il login tramite SSO (Single Sign On).
  - Integrare un WAF o un reverse proxy più avanzato (es. Nginx con moduli di sicurezza) per gestire firewall complessi e log di audit centralizzati.


## 8. Riferimenti
* Docker Compose: https://docs.docker.com/compose/
* OpenWebUI: https://docs.openwebui.com/
* Ollama & Local LLMs: https://ollama.com/
* pgVector & PostgreSQL: https://github.com/pgvector/pgvector
* Caddy Server: https://caddyserver.com/docs/
* Materiali e slide del corso di Network Softwarization and Virtualization

## 9. Licenza
* Copyright 2026 Vito Collica (vito.collica@students.uniroma2.it)
* I contenuti di questo repository sono distribuiti sotto licenza MIT, consulta il file [LICENSE](LICENSE) per i termini completi.