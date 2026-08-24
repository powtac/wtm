# WTM — Local LLM Inventory for macOS

| Feld | Wert |
|---|---|
| Status | **Proposed** |
| Version | 0.1.7 |
| Datum | 2026-08-24 |
| Plattform | macOS, Apple Silicon |
| Ziel | Allgemeine, veröffentlichbare Open-Source-App auf GitHub |
| Dokumentsprache | Deutsch |
| Produktsprache | Englisch |
| Öffentliche Inhalte | Englisch; einzige Ausnahme ist dieses normative deutsche `REQUIREMENTS.md` |
| Normativer Stil | MUST / SHOULD / MAY gemäß RFC 2119 und RFC 8174 |

> Arbeitsname: **WTM — What The Model**. Produktkategorie und Untertitel: **Local LLM Inventory for macOS**. Name, Marke, Domain und GitHub-Verfügbarkeit sind vor Veröffentlichung zu prüfen.

> **Sprachentscheidung:** Dieses deutschsprachige `REQUIREMENTS.md` ist die normative Produktspezifikation und wird im GitHub-Repository versioniert. App, Website, README, technische Dokumentation, ADRs, Issues, Pull Requests, Releases und Community-Kommunikation bleiben vollständig Englisch. Eine zweite normative englische Requirements-Kopie wird nicht gepflegt.

## 1. Kurzfassung

WTM ist eine allgemeine macOS-App zur Inventarisierung lokal gespeicherter LLMs, unabhängig von einem bestimmten Nutzer, Rechner, Provider, Laufwerk oder Laufzeitsystem. Sie ordnet physische Dateien auf internen und zusätzlichen Datenträgern logischen Modellen, Providern, Konfigurationen und ausführbaren Tools zu. Primäres Ziel ist eine belastbare Antwort auf drei Fragen: **Welche Modelle sind lokal gespeichert oder aktuell in eine Runtime geladen, welche sind nutzbar und wie alt beziehungsweise zuletzt verwendet sind sie?**

Die App ist **kein allgemeiner Disk-Scanner**, kein Model-Marktplatz und kein eigener Inference-Host. Ihr Kernwert ist eine korrekte, providerübergreifende Bestands- und Abhängigkeitsansicht.

Lokale Installationen dienen ausschließlich als Test- und Nutzungsumgebung. Pfade, Provider, Modelle, Hardwarewerte und persönliche Konfigurationen dürfen nicht als Produktannahmen fest codiert werden.

## 2. Kritische Einordnung

1. **Der schwierige Teil ist nicht die Baumansicht, sondern die Identität.** Ein Modell kann aus mehreren Dateien bestehen; Hugging Face kann Blobs über Snapshots teilen; Ollama trennt Manifeste und Blobs; dieselbe GGUF-Datei kann von mehreren Tools referenziert werden. Naives Addieren oder Löschen wäre fachlich falsch.
2. **„Download-Datum“ ist nicht zuverlässig allgemein ermittelbar.** Dateierstellung, Änderung und erster Fund sind verschiedene Zeitpunkte. Die UI MUST Quelle und Vertrauensniveau jedes Datums ausweisen.
3. **„Lauffähig“ ist kein einzelnes Boolean.** Vorhanden, strukturell vollständig, formatkompatibel, Runtime erreichbar, durch echte Modellinferenz verifiziert und aktuell laufend sind getrennte Zustände. Ein minimaler Request kann trotzdem das gesamte Modell in den Speicher laden.
4. **Löschen ist die risikoreichste Funktion.** Shared Blobs, LoRA-Basismodelle, mmproj-Dateien, Tokenizer und externe Config-Referenzen dürfen nicht beschädigt werden. Provider-APIs oder providerseitige Löschpläne haben Vorrang vor rohen Dateisystemoperationen.
5. **Mac App Store und Vollautomatik passen schlecht zusammen.** App Sandbox verlangt benutzergewählten Zugriff; sie beschränkt außerdem das Ausführen externer Programme. Automatische Provider-Erkennung plus konfigurierbare CLI-Starts spricht für direkte, Developer-ID-signierte und notarized Distribution.
6. **Provider, Runtime und Client sind verschiedene Rollen.** Hugging Face und Ollama speichern Modelle. `llama.cpp` und Unsloth können Modelle ausführen. OpenClaw konsumiert einen lokalen Endpoint. Die Architektur MUST diese Rollen trennen.
7. **Swift besitzt keine automatische Rails-artige Runtime-Konventionserkennung.** WTM verwendet deshalb Protocols, SwiftPM-Module, eine explizite Adapter-Registry und das Prinzip `Defaults + Discovery Conventions + User Overrides`. SwiftPM-Plugins sind Build-Werkzeuge und keine sicheren App-Runtime-Plugins.

## 3. Ziele und Nicht-Ziele

### 3.1 Ziele

- Providerübergreifendes Inventar mit belastbarer Speicherzuordnung.
- Einheitliche Inventarisierung über interne und zusätzliche lokale HDDs/SSDs.
- Schnelle Antwort auf: *Was ist lokal vorhanden, wo liegt es, wem gehört es, wie viel Platz belegt es ungefähr und womit läuft es?*
- Erkennung vollständiger, unvollständiger, verwaister und beschädigter Bestände.
- Verknüpfung von Modellen, Konfigurationen, Adaptern und Runtime-Tools.
- Klare Trennung von `lokal gespeichert`, `in Runtime geladen`, `nutzbar` und `alt`.
- Erweiterbare Integrationslisten und Regeln ohne UI-Hardcoding.
- Sichere, nachvollziehbare und möglichst reversible Aktionen.
- Native macOS-UX nach Apple Human Interface Guidelines.
- Erweiterbare Adapterarchitektur ohne unsichere In-Process-Plugins.
- Ehrliche Best-effort-Speicherwerte statt vorgetäuschter forensischer Byte-Genauigkeit.

### 3.2 Nicht-Ziele der Read-only Beta

- Kein vollständiger Dateisystem- oder Duplikat-Scanner.
- Kein eigener Model-Downloader oder Model-Hub-Browser.
- Kein eigener Inference-, Training- oder Chat-Stack.
- Keine Windows- oder Linux-Version.
- Keine Cloud-Synchronisierung, Accounts oder Telemetrie.
- Keine automatische Modellkonvertierung oder Quantisierung.
- Keine root-Rechte, kein privilegierter Helper und kein Full-Disk-Access-Zwang.
- Kein automatisches Löschen oder Starten ohne Nutzeraktion.
- Keine bytegenaue Datenträgerforensik oder Garantie, dass angezeigte Dateibytes exakt dem nach einer Löschung freien APFS-Speicher entsprechen.

## 4. Zielgruppe und primäre Use Cases

### 4.1 Zielgruppen

- Entwickler mit mehreren lokalen Runtimes und Caches.
- ML Engineers mit GGUF-, Safetensors-, MLX- und Adapter-Beständen.
- Mac-Nutzer, die Speicherplatz zurückgewinnen wollen, ohne Installationen zu beschädigen.

### 4.2 Kern-Use-Cases

| ID | Use Case | Erfolgskriterium |
|---|---|---|
| UC-01 | Lokale Modelle erfassen | Alle aktivierten Quellen erscheinen mit Provider, Pfad und Größe. |
| UC-02 | Speicherfresser verstehen | Logische, allokierte und best-effort freigebbare Bytes sind getrennt. |
| UC-03 | Teil-Downloads finden | Provider-spezifische Fragmente erscheinen mit Grund und Größe. |
| UC-04 | Configs finden | Zugeordnete Config-Dateien sind sichtbar und im Finder aufrufbar. |
| UC-05 | Lauffähigkeit prüfen | Der Zustand enthält Evidenz, Zeitpunkt und konkreten Blocker. |
| UC-06 | Modell starten | Eine kompatible Runtime startet mit überprüfbaren Argumenten. |
| UC-07 | Modell sicher entfernen | Vorschau, Abhängigkeiten und erwartete Freigabe werden vor Bestätigung gezeigt. |
| UC-08 | Eigene Tools konfigurieren | Executable, Argumente und unterstützte Formate sind ohne Shell-Interpolation definierbar. |
| UC-09 | Zusätzliche Datenträger erfassen | Aktivierte HDDs/SSDs bleiben als eigene Quellen identifizierbar und werden nach erneutem Mounten wiedererkannt. |
| UC-10 | Kompaktstatus sehen | Das Menüleisten-Symbol zeigt Bestand, Speicher, Probleme und laufende Modelle ohne Öffnen des Hauptfensters. |
| UC-11 | Speicheranteil vergleichen | Nutzer wechseln zwischen absoluten Größen und Prozentanteilen am gesamten gefundenen Modellbestand. |
| UC-12 | Model Card öffnen | Ein bestätigter Providerlink öffnet die zugehörige Model Card im Standardbrowser. |
| UC-13 | Bestand und Alter verstehen | Gespeicherte, geladene, nutzbare, alte und zeitlich unbekannte Modelle sind getrennt filterbar. |
| UC-14 | Scan-Zugriff korrigieren | Abgelehnter oder falsch gewählter Zugriff kann jederzeit erklärt, erneut angefordert oder geändert werden. |
| UC-15 | Integration erweitern | Datenbasierte Quellen, Tools, Clients und Linkregeln sind in Settings erweiterbar; neue Parser oder Prozess-/Löschsemantik gelangen ausschließlich per Adapter-PR ins Produkt. |

## 5. Produktentscheidungen

| ID | Entscheidung | Begründung |
|---|---|---|
| ADR-001 | Swift 6, SwiftUI; AppKit nur für macOS-spezifische Lücken | Native UX, geringe Runtime-Komplexität, Accessibility und langfristige Wartbarkeit. |
| ADR-002 | **Accepted:** Direkte Distribution außerhalb des Mac App Store | Vollständige Provider-Erkennung und externe Tool-Starts sind mit App Sandbox stark eingeschränkt. |
| ADR-003 | Developer ID, Hardened Runtime, Notarisierung und Stapling | Gatekeeper-kompatible Standarddistribution. |
| ADR-004 | Apple Silicon und macOS 15+ in der ersten Beta | Enger, testbarer Hardwarekorridor für lokale Inference. |
| ADR-005 | SQLite für normalisierten Index; Dateien bleiben Source of Truth | Schnelle Suche ohne proprietäre Model-Datenbank. |
| ADR-006 | **Accepted:** Feldbezogene Autoritätsmatrix statt globaler Quellenreihenfolge | Dateisystem, Provider-API, Manifest und Prozesszustand beantworten unterschiedliche Fragen; jede Aussage behält ihre Provenienz. |
| ADR-007 | Keine dynamisch geladenen Drittanbieter-Bundles | Kein Aufweichen von Library Validation oder Hardened Runtime. |
| ADR-008 | Tool-Definitionen als `executable + argv[]`, niemals als Shell-String | Verhindert Shell-Injection und fehlerhafte Pfadquotierung. |
| ADR-009 | Provider-, Runtime- und Client-Adapter sind getrennte Protokolle | Ollama, HF, llama.cpp, Unsloth und OpenClaw haben verschiedene Verantwortungen. |
| ADR-010 | **Accepted:** App Sandbox ist für die direkte Distribution deaktiviert | WTM kann ausgewählte HDD-/SSD-Wurzeln mit den Rechten des Nutzers lesen. TCC und POSIX-Rechte werden respektiert; Full Disk Access, root-Rechte und privilegierte Helper sind ausgeschlossen. Read-only ist eine WTM-Architekturgarantie, keine Kernel-Sandbox. |
| ADR-011 | **Accepted:** `Defaults + Discovery Conventions + User Overrides` | Swift hat keine passende automatische Runtime-Discovery; explizite, testbare Konventionen bleiben nachvollziehbar. |
| ADR-012 | **Accepted:** Keine nachladbaren Code-Plugins | Providerlogik wird als SwiftPM-Modul kompiliert; nutzerseitige Erweiterungen sind ausschließlich validierte Datenmanifeste. |
| ADR-013 | **Accepted:** GitHub-native Entwicklung und Distribution | Issues, Discussions, Projects, Pull Requests, Actions, Releases, Security und Pages bilden den öffentlichen Projektworkflow. |
| ADR-014 | **Accepted:** Private-first, public-ready | Das Repository startet privat unter GitHub Free, darf aber keine Architektur oder Historie erzeugen, die eine spätere Veröffentlichung blockiert. |
| ADR-015 | **Accepted:** English-only Product mit deutscher Requirements-Ausnahme | App-UI, Website und alle öffentlichen GitHub-Inhalte sind Englisch; ausschließlich das normative `REQUIREMENTS.md` bleibt Deutsch. |

## 6. Systemkontext

```text
WTMApp / SwiftUI
├── ConsentPolicy
├── InventoryCoordinator
│   └── ReadOnlyScanner ──► AdapterRegistry ──► Identity & Dependency Graph ──► SQLite
├── ActionExecutor
│   └── unveränderlicher Plan + Generation Token + Revalidierung
└── RuntimeBroker
    └── Ollama / llama.cpp / Unsloth / Clients
```

### 6.1 Adapterrollen

| Adaptertyp | Verantwortung | Sicherheitsgrenze |
|---|---|---|
| `StorageProviderAdapter` | Read-only-Inventar, Metadaten, Vollständigkeit und Artefaktgraph | Keine Mutation und kein Prozessstart |
| `StorageActionAdapter` | Providerbezogener Löschplan, Revalidierung und explizite Ausführung | Erst ab Phase 2 über `ActionExecutor` |
| `RuntimeAdapter` | Kompatibilität, Readiness, Start, Stop und laufende Instanzen | Erst ab Phase 3 über `RuntimeBroker` |
| `ClientAdapter` | Übergabe eines Modells oder lokalen Endpoints an eine App beziehungsweise ein Tool | Externe Vertrauensgrenze; erst ab Phase 4 |
| `ManualFolderAdapter` | Konservative read-only Dateierkennung ohne behauptete Providersemantik | Keine Provider- oder Löschsemantik |

Ein Produkt kann mehrere Rollen implementieren. Ollama ist beispielsweise Storage Provider und Runtime; OpenClaw ist primär Client.

### 6.2 Modularität und Erweiterungspunkte

- `WTMCore` MUST keine konkreten Provider-, Runtime- oder Clienttypen importieren.
- Jeder Adapter MUST in einem separaten SwiftPM-Target liegen und mindestens eine der Adapterrollen implementieren.
- Eine explizite `AdapterRegistry` injiziert aktivierte Implementierungen beim App-Start. UI und Scanner arbeiten ausschließlich gegen Protokolle und Capability-Abfragen.
- Gemeinsames Verhalten MUST über Protocol Extensions und kleine, komponierbare Services bereitgestellt werden; Adapter dürfen keine globalen Singletons voraussetzen.
- Community-Codeadapter werden durch Pull Requests, Review, Contract Tests und einen normalen signierten App-Release ausgeliefert.
- Nutzerseitige Erweiterungen dürfen keine Swift-Binaries, dylibs, Skripte oder Shell-Kommandos in den App-Prozess laden. Zulässig sind nur versionierte, schema-validierte Datenmanifeste.
- `ReadOnlyScanner` und Adapter-Inventarisierung exponieren keine Mutations- oder Prozessstart-API. Löschen und Prozessstarts liegen ausschließlich in `ActionExecutor` beziehungsweise `RuntimeBroker` und werden in Phase 1 nicht ausgeliefert.

### 6.3 Autoritätsmatrix

| Aussage | Primäre Evidenz | Ergänzende Evidenz |
|---|---|---|
| Datei vorhanden, Pfad, logische/allokierte Größe | Dateisystem innerhalb aktivierter Wurzeln | Provider-Manifest |
| Partial, Orphan, Shared Blob | Providerstruktur plus Dateisystem | Heuristik mit sichtbarer Confidence |
| Logische Modell-ID, Revision, Abhängigkeiten | Provider-Manifest oder lokale API | CLI nur als dokumentierter Fallback |
| Runtime installiert oder laufend | Lokale Runtime-API beziehungsweise kontrollierter Prozess | Executable-Präsenz ist nur statische Evidenz |
| Providerlöschung | Offizielle lokale API oder CLI | Dateisystem nur für nachträglichen Best-effort-Abgleich |

Eine Quelle ist nicht global „besser“ als eine andere. Adapter MUST pro Feld Evidenz, Zeitpunkt und Confidence liefern; widersprüchliche Beobachtungen bleiben sichtbar.

### 6.4 Convention-over-Configuration-Profil

WTM verwendet eine kontrollierte Konventionskette. Spätere Ebenen überschreiben frühere, ohne sie zu verändern:

| Priorität | Ebene | Beispiel |
|---:|---|---|
| 1 | Built-in Defaults | Bekannte Providerpfade, Bundle-IDs, ausführbare Namen, sichere Linktemplates |
| 2 | Discovery Conventions | Umgebungsvariablen, Standardordner, App-Bundles, lokale API-Endpunkte |
| 3 | User Overrides | Eigene Pfade, Tools, Argumente, Ports, Altersgrenzen, aktivierte Quellen |
| 4 | Session Override | Einmalige Auswahl oder Testkonfiguration ohne persistente Mutation |

Jeder effektive Wert MUST in Settings seine Herkunft zeigen und auf den Default zurücksetzbar sein. Konventionen dürfen Komfort schaffen, aber niemals eine Löschung oder Prozessausführung ohne Bestätigung autorisieren.

## 7. Unterstützte Integrationen

| Integration | Rolle | Erste Zielphase | Mindestumfang |
|---|---|---:|---|
| Ollama | Storage + Runtime | 1 Storage / 3 Runtime | Dateisystem- und API-Inventar; Löschen sowie Start/Stop erst in den jeweiligen späteren Phasen |
| Hugging Face Hub Cache | Storage | 1 Inventar / 2 Löschen | Repos, Revisionen, Shared Blobs, `.incomplete`, später Löschplan |
| Manuelle Ordner | Storage | 1 Inventar / 2 Löschen | GGUF, Safetensors-Ordner, MLX-Strukturen, Config-Zuordnung, später Papierkorb |
| llama.cpp | Runtime | 3 | GGUF-Kompatibilität, Start über validiertes Executable, lokaler Endpoint |
| Unsloth Studio | Runtime + Tool | 4 | Installation erkennen, Modell übergeben oder Studio öffnen |
| OpenClaw | Client | 4 | Installation erkennen, über Ollama oder konfigurierten Endpoint starten |
| MLX-basierte Stores/Runtimes | Storage + Runtime | 4 | Allgemeiner Adapter für dokumentierte MLX-Strukturen ohne produktspezifische Sonderlogik im Core |
| Weitere Tools | Runtime/Client | 3–4 | Nutzerkonfiguration über versioniertes, validiertes Schema |

Diese Integrationsmatrix definiert Shipping Defaults, keine geschlossene Allowlist. Providerpfade, Tools, Runtimes, Clients und sichere Linkresolver MUST konfigurierbar und erweiterbar sein. Standardwerte sind nur Vorschläge, weil Umgebungsvariablen, Versionen und externe Volumes sie ändern können.

## 8. Fachliches Datenmodell

### 8.1 Entitäten

#### `ModelIdentity`

- Stabile interne UUID für das providerübergreifende Modellkonzept.
- Bestätigte Upstream-ID, Familie/Architektur, Modalitäten und Fähigkeiten, jeweils mit Provenienz.
- Lizenzname oder `unknown`; keine Lizenzannahme aus Modell- oder Dateinamen.
- Keine lokalen Pfade, Runtimezustände oder Quantisierung.

#### `ModelVariant`

- Stabile UUID sowie Beziehung zu genau einer `ModelIdentity` oder zu `unknown identity`.
- Revision, Format, Quantisierung, Parameterklasse und optionale Architekturdetails.
- Null oder mehrere Config-, Adapter-, Tokenizer- und Projection-Beziehungen.
- Zwei Varianten dürfen dieselben physischen Artefakte referenzieren.

#### `ModelInstallation`

- Stabile UUID sowie Beziehung zu genau einer `ModelVariant`.
- Storage Provider, providerseitige ID, Source-ID, Volume-ID und Installationswurzel.
- Eine oder mehrere `ArtifactReference`-Beziehungen.
- Präsenz-, Integritäts- und Zeitstempelzustände einschließlich `lastUsedAt`, jeweils mit `value`, `source` und `confidence`.
- Eine Variante kann gleichzeitig in mehreren Providern, Ordnern oder Volumes installiert sein.

#### `Artifact`

- Kanonischer URL/Pfad und File-System-Identität.
- Typ: Weight, Manifest, Config, Tokenizer, Adapter, Projection, Cache Blob, Temp, Unknown.
- Logische Größe, allokierte Größe und best-effort physische Identität.
- Digest nur, wenn vom Provider geliefert oder explizit berechnet.
- Eigentümer/Referenzen und Shared-Status.
- Zugriffsfehler ohne Eskalation von Berechtigungen.

#### `ToolDefinition`

- Schema-Version und UUID.
- Rolle: Runtime oder Client.
- App-Bundle-URL oder Executable-URL.
- Argumentarray mit streng definierten Platzhaltern.
- Unterstützte Formate und optionale lokale API-Adresse.
- Optionaler Arbeitsordner und allowlist-basierte Umgebungsvariablen.
- Letzter statischer Validierungszeitpunkt, Code-Signing-Status, Version und optionaler Binär-Hash.

#### `RuntimeInstance`

- RuntimeAdapter, `ModelInstallation`, Prozess- oder Providerinstanz-ID und lokaler Endpoint.
- Zustand, Startzeit, Eigentümer `startedByWTM` oder `providerManaged` und letzte erfolgreiche Erreichbarkeits-/Inference-Prüfung.
- Laufzeitdaten werden nicht in `ModelIdentity` oder `ModelVariant` persistiert.

#### `Observation`

- Adapter, Version, Zeitpunkt, Ergebnis und Evidenz.
- Fehlercode, technische Kurzursache und nutzerverständliche Maßnahme.
- Ablaufzeit für volatile Ergebnisse wie `running` oder `verified`.

#### `ExternalModelLink`

- Linktyp, mindestens `modelCard`, `repository`, `license` und `documentation`.
- Kanonische HTTPS-URL, Provider, optionale Revision und ermittelte Modell-ID.
- Herkunft `provider`, `embeddedMetadata`, `userProvided` oder `heuristic`.
- Confidence und letzter Validierungszeitpunkt; heuristische Links gelten nie als bestätigt.

#### `ExtensionManifest`

- Schema-Version, stabile ID, Anzeigename, Herkunft und minimale WTM-Version.
- Typ: Tool, Runtime, Client, Source Convention oder Link Resolver.
- Reine Datenstruktur ohne ausführbaren Code oder Shell-String.
- Herkunft `builtIn`, `userCreated` oder `imported`, Validierungsstatus und optionaler Digest.
- Ein Digest erkennt Veränderungen, beweist aber keine vertrauenswürdige Herkunft. Signaturen und Remote-Updates sind nicht Bestandteil der ersten Beta.

#### `ScanAuthorization`

- Source-ID, angezeigter Pfad, Zweck, angeforderter Modus und Nutzerentscheidung.
- Getrennter Zustand für WTM-Zustimmung und tatsächlichen Betriebssystem-/Dateisystemzugriff.
- Zeitpunkt, UI-Version, letzter erfolgreicher Preflight und optionaler Widerruf.

### 8.2 Größenbegriffe

| Begriff | Definition |
|---|---|
| Logische Größe | Summe der sichtbaren Dateilängen; kann Shared Content mehrfach zählen. |
| Allokierte Größe | Vom Dateisystem gemeldeter Speicher; best effort. |
| Exklusive Größe | Bytes, die nur dieses logische Modell referenziert. |
| Erwartet freigebbare Größe | Best-effort-Schätzung eines validierten Löschplans; keine Garantie für die anschließende Änderung des freien Volume-Speichers. |
| Unvollständige Größe | Erkannte Staging-, Partial- oder Incomplete-Artefakte. |
| Aktiver Speicherbestand | Aktuell beobachtete Bytes ausschließlich auf verbundenen und aktivierten Quellen. |
| Offline-Snapshot | Zuletzt beobachteter Bestand einer nicht verbundenen Quelle mit Scanzeitpunkt; kein aktueller physischer Messwert. |

Die UI MUST Begriff, Scope und Messzeitpunkt nennen. Sie darf eine unsichere Schätzung nicht als exakte freigebbare oder physische Größe darstellen. Ziel ist ein verständlicher, richtungsweisender Speicherüberblick, keine APFS-Forensik.

## 9. Funktionale Anforderungen

`P0`, `P1` und `P2` bezeichnen die Wichtigkeit innerhalb der jeweiligen Zielphase, nicht automatisch den Umfang der ersten Beta. Die Release-Zuordnung erfolgt verbindlich über Abschnitt 17 und den Phasenplan in Abschnitt 18.

| Zielphase | Anforderungsumfang |
|---:|---|
| 1 | Sources, Permission UX, read-only Scanning, Inventar ohne Menüleisten-Popover, Links, Zeit/Alter, Configzuordnung und grundlegende Settings |
| 2 | `FR-DEL-*`, `StorageActionAdapter`, Lösch-Audit und Best-effort-Verifikation |
| 3 | `FR-HLT-*`, `FR-RUN-*`, `RuntimeAdapter` und ausführbare Tooldefinitionen |
| 4 | `ClientAdapter`, OpenClaw, Unsloth, weitere Integrationen sowie `FR-INV-010`–`FR-INV-012` für das Menüleisten-Symbol |
| 5 | stabile Public-Release-, Community-, Website- und vollständige Release-Pipeline-Gates |
| 6 | `FR-DWN-*` und weitere ausdrücklich optionale Funktionen |

Gemischte Requirements gelten erst in der höchsten benötigten Phase; Phase 1 darf daraus keine Mutations- oder Prozessfähigkeit ableiten.

### 9.1 Quellen und Berechtigungen

- **FR-SRC-001 (P0):** Die App MUST bekannte Quellen für Ollama und den Hugging-Face-Cache vorschlagen.
- **FR-SRC-002 (P0):** Nutzer MUST beliebige lokale Ordner und externe Volumes hinzufügen, deaktivieren und entfernen können.
- **FR-SRC-003 (P0):** Vor dem ersten Scan MUST die App die konkreten Scan-Wurzeln anzeigen.
- **FR-SRC-004 (P0):** Die App MUST nur konfigurierte Wurzeln traversieren und symlink-bedingte Ausbrüche aus dem Scope verhindern.
- **FR-SRC-005 (P0):** Fehlende, getrennte oder nicht lesbare Quellen MUST als Zustand erscheinen; die App darf keine erhöhten Rechte anfordern.
- **FR-SRC-006 (P0):** Externe Volumes MUST über Volume-ID und relativen Pfad wiedererkannt werden, ohne einen zufälligen neuen Mount als identisch anzunehmen.
- **FR-SRC-007 (P1):** Ein optionaler Login-Start MUST ausschließlich nach expliziter Aktivierung über Apples unterstützte Service-Management-API erfolgen.
- **FR-SRC-008 (P0):** Der Quellen-Dialog MUST zusätzlich gemountete lokale HDDs und SSDs mit Volumename, Kapazität, freiem Platz, Dateisystem, Mountpfad und Read-only-Status anzeigen.
- **FR-SRC-009 (P0):** Ein ausgewähltes, nicht verbundenes Volume MUST als `offline` erhalten bleiben. Modelle dürfen deshalb nicht als gelöscht oder verwaist umklassifiziert werden.
- **FR-SRC-010 (P0):** Mount- und Unmount-Ereignisse MUST erkannt werden. Laufende Scans sind sicher abzubrechen; nach erneutem Mounten ist nur die betroffene Quelle neu zu prüfen.
- **FR-SRC-011 (P1):** Neue Datenträger dürfen nicht ungefragt vollständig gescannt werden. Die Quelle wird erst nach expliziter Aktivierung inventarisiert.
- **FR-SRC-012 (P0):** Beliebige Ordner und Volume-Wurzeln werden über `NSOpenPanel` ausgewählt. WTM speichert Volume-ID, relativen Pfad und einen stabilen URL-Bookmark zur Wiedererkennung, behauptet im direkten Distributionsprofil aber keinen Security Scope.

### 9.2 Scan-Freigabe und Recovery

- **FR-PER-001 (P0):** Vor dem ersten Scan MUST ein kurzer Einrichtungsdialog erklären: was gelesen wird, warum, welche Ordner betroffen sind, dass Daten lokal bleiben und dass noch nichts gelöscht oder gestartet wird.
- **FR-PER-002 (P0):** Jede vorgeschlagene Quelle MUST einzeln mit Provider, vollständigem Pfad, Zugriffsmodus und verständlichem Zweck aktivierbar sein. Vorschläge dürfen nicht still vorausgewählt werden.
- **FR-PER-003 (P0):** WTM-Zustimmung und tatsächlicher macOS-/POSIX-Zugriff MUST getrennt modelliert werden. Ein zugestimmter, aber technisch verweigerter Pfad gilt nicht als freigegeben.
- **FR-PER-004 (P0):** Phase 1 ist technisch scan-only: Sie enthält weder `ActionExecutor` noch `RuntimeBroker` und exponiert keine Mutation, Config-Änderung oder Prozessausführung. Spätere Aktionen benötigen eigene kontextbezogene Bestätigungen.
- **FR-PER-005 (P0):** Die Settings-Seite `Security & Scan Access` MUST pro Quelle `Not Set Up`, `Allowed`, `Limited`, `Denied`, `Offline` oder `Stale` sowie die nächste mögliche Aktion zeigen.
- **FR-PER-006 (P0):** Nach Ablehnung oder falscher Auswahl MUST `Grant Access Again` jederzeit verfügbar sein. Die Aktion öffnet erneut die passende Ordnerauswahl beziehungsweise eine unterstützte macOS-Einstellungsseite; andernfalls zeigt sie genaue manuelle Schritte.
- **FR-PER-007 (P0):** Die App darf verweigerte Systemprompts nicht in einer Schleife erneut auslösen. Ein erneuter Versuch erfolgt nur nach einer neuen Nutzeraktion.
- **FR-PER-008 (P0):** Vor jedem Scan MUST ein schneller Preflight tatsächliche Lesbarkeit, Volume-Identität und Scope-Grenzen prüfen. Fehlschläge verändern keine bestehenden Inventardaten in `gelöscht`.
- **FR-PER-009 (P0):** Nutzer MUST eine Quelle widerrufen können. Dabei wählen sie getrennt, ob nur künftige Scans stoppen oder auch die lokalen Indexdaten dieser Quelle entfernt werden.
- **FR-PER-010 (P0):** WTM darf Full Disk Access weder voraussetzen noch als pauschale Problemlösung empfehlen. Geschützte Quellen werden einzeln erklärt und ausgewählt.
- **FR-PER-011 (P0):** Freigabetexte MUST konkrete englische Verben verwenden (`Read model files`, `Calculate storage`, `Inspect manifests`) und unbestimmte Formulierungen wie `Optimize full access` vermeiden.
- **FR-PER-012 (P1):** Ein lokales, secrets-freies Permission-Protokoll SHOULD Zustimmung, Widerruf, Fehler und Recovery dokumentieren und vollständig löschbar sein.
- **FR-PER-013 (P0):** Der Scanner MUST Quelldateien ausschließlich über lesende APIs beziehungsweise `O_RDONLY` öffnen. Diese WTM-Garantie ist von TCC-, POSIX-/ACL- und Volume-Read-only-Zuständen getrennt darzustellen.
- **FR-PER-014 (P0):** `Grant Access Again` darf nur dann eine macOS-Einstellungsseite anbieten, wenn TCC für den betroffenen Ort anwendbar ist. Bei POSIX-/ACL-Fehlern zeigt WTM den Fehler und manuelle Dateirechte-Hinweise, behauptet aber keine systemseitige Freigabeaktion.
- **FR-PER-015 (P0):** Release-Builds MUST ausschließlich die tatsächlich benötigten englischen TCC Usage Descriptions enthalten, insbesondere für Removable Volumes, Network Volumes oder geschützte Standardordner. Texte nennen den konkreten Scan-Zweck und versprechen keinen Schreibschutz durch macOS.

### 9.3 Scanning und Identität

- **FR-SCN-001 (P0):** Ein initialer Scan MUST abbrechbar sein und Ergebnisse inkrementell anzeigen.
- **FR-SCN-002 (P0):** Folgescans MUST Änderungen inkrementell verarbeiten; ein manueller Full Rescan MUST verfügbar sein.
- **FR-SCN-003 (P0):** Provideradapter MUST logische Modelle aus providerseitigen Manifesten/APIs ableiten, nicht nur aus Dateiendungen.
- **FR-SCN-004 (P0):** Der Scanner MUST Symlinks, Hardlinks und bekannte Shared-Blob-Strukturen erkennen und Doppelzählung kennzeichnen.
- **FR-SCN-005 (P0):** Teildownloads MUST über providerseitige Marker erkannt werden; generische Heuristiken müssen als solche beschriftet sein.
- **FR-SCN-006 (P0):** Hugging-Face-`.incomplete`-Dateien MUST separat von committed Snapshots erscheinen.
- **FR-SCN-007 (P0):** Nicht lesbare oder inkonsistente Manifeste MUST den übrigen Scan nicht abbrechen.
- **FR-SCN-008 (P0):** Große Weight-Dateien dürfen im normalen Scan nicht vollständig gehasht werden. Bestehende Digests sind zu übernehmen; Hashing ist opt-in.
- **FR-SCN-009 (P1):** Live-Aktualisierung über FSEvents ist nach der Read-only Beta optional. Wenn sie aktiviert wird, MUST WTM Events bündeln; Eventstürme dürfen keinen Full Rescan pro Event auslösen.
- **FR-SCN-010 (P1):** Alias- und Duplikatverdacht MUST getrennt von bestätigter physischer Identität dargestellt werden.
- **FR-SCN-011 (P1):** Eine aktivierte FSEvents-Implementierung MUST `MustScanSubDirs`, `UserDropped`, `KernelDropped`, `RootChanged` sowie Unmount behandeln. Bei verlorenen Events wird die betroffene Quelle kontrolliert vollständig neu gescannt; ohne FSEvents bleibt manueller Rescan verfügbar.

### 9.4 Inventar und Navigation

- **FR-INV-001 (P0):** Die Hauptansicht MUST Modelle nach Provider, Format, Zustand, Quelle und Runtime filtern können.
- **FR-INV-002 (P0):** Die Tabelle MUST mindestens Name, Provider, Format/Quantisierung, Zustand, Größe, freigebbare Größe, Datum und Pfad zeigen.
- **FR-INV-003 (P0):** Nutzer MUST Spalten sortieren, ein-/ausblenden und ihre Breite persistent speichern können.
- **FR-INV-004 (P0):** Eine Detailansicht MUST Artefakte, Configs, Abhängigkeiten, Zeitstempelquellen, Kompatibilität und letzte Prüfungen zeigen.
- **FR-INV-005 (P0):** Die Seitenleiste MUST mindestens `All Models`, `Providers`, `Incomplete`, `Issues`, `Usable` und `Running` enthalten.
- **FR-INV-006 (P0):** Suche MUST Namen, IDs, Familie, Quantisierung, Format und Pfad abdecken.
- **FR-INV-007 (P0):** „Im Finder zeigen“ MUST das konkrete Artefakt auswählen oder den zugehörigen Ordner öffnen.
- **FR-INV-008 (P1):** Ein Storage-Treemap-/Sunburst-Modus MAY die Tabelle ergänzen, aber niemals ersetzen.
- **FR-INV-009 (P1):** Export als JSON und CSV MUST ohne Secrets möglich sein; das JSON-Schema ist zu versionieren.
- **FR-INV-010 (P0):** Die App MUST ein vom Nutzer deaktivierbares macOS-Menüleisten-Symbol anbieten.
- **FR-INV-011 (P0):** Die vereinfachte Menüleisten-Übersicht MUST Anzahl gefundener Modelle, gesamten Modellbestand, alte Modelle, unvollständige Bytes, Problemzahl, laufende Modelle, Offline-Quellen und Zeitpunkt des letzten erfolgreichen Scans zeigen.
- **FR-INV-012 (P0):** Das Menüleisten-Popover MUST mindestens `Open WTM`, `Scan Now`, Problemübersicht und laufende Modelle anbieten. Detailaktionen öffnen das Hauptfenster im passenden Kontext.
- **FR-INV-013 (P0):** Hauptansicht und Speichervisualisierung MUST zwischen `Absolute` und `Share of Model Inventory` umschaltbar sein.
- **FR-INV-014 (P0):** Die absolute Ansicht MUST den gewählten Größenbegriff und exakte Einheit anzeigen; Standard ist die allokierte Größe.
- **FR-INV-015 (P0):** Der standardmäßige prozentuale Anteil MUST sich ausschließlich auf den aktiven Speicherbestand verbundener Quellen beziehen. Der sichtbare Nenner wird nicht still durch Tabellenfilter oder Offline-Snapshots verändert.
- **FR-INV-016 (P0):** Innerhalb eines klar benannten Scopes werden best-effort eindeutig gezählte, allokierte Bytes verwendet. Shared oder nicht sicher zuordenbare Artefakte erscheinen einmalig als `Shared` beziehungsweise `Unknown`; alle sichtbaren Kategorien dieses Scopes ergeben 100 Prozent.
- **FR-INV-017 (P1):** Nutzer MAY die Prozentansicht explizit auf einen Provider oder ein Volume begrenzen; der aktive Scope und neue Nenner müssen deutlich sichtbar sein.
- **FR-INV-018 (P0):** Modelle einer aktiven, aber nicht verbundenen Quelle MUST mit ihrem letzten erfolgreichen Snapshot erhalten bleiben und als `Offline Snapshot · <scan date>` erscheinen. Sie sind aus aktuellen Speicherprozenten ausgeschlossen und nur in einem expliziten historischen Inventory-Scope enthalten.
- **FR-INV-019 (P1):** Bei unvollständiger Zuordnung MUST die UI Messqualität oder bekannte Abdeckung sichtbar machen. Eine grobe Schätzung ist zulässig, eine unbelegte Exaktheit nicht.

### 9.5 Model Cards und externe Links

- **FR-LNK-001 (P0):** Die Detailansicht MUST bestätigte Model-Card- und Repository-Links des Providers anzeigen.
- **FR-LNK-002 (P0):** Hugging-Face-Links MUST aus einer bestätigten Repository-ID aufgebaut werden und MAY auf die erkannte Revision verweisen.
- **FR-LNK-003 (P0):** Weitere Provider definieren kanonische Model-Card-URLs ausschließlich über ihren Adapter.
- **FR-LNK-004 (P0):** Bei mehreren möglichen Ursprüngen MUST die App alle Kandidaten mit Provider und Confidence zeigen, statt einen Link still auszuwählen.
- **FR-LNK-005 (P0):** Aus Dateinamen allein darf kein bestätigter Link entstehen. Für manuelle Modelle MUST ein Nutzer einen Link ergänzen oder korrigieren können.
- **FR-LNK-006 (P0):** Externe Links MUST HTTPS verwenden, vor dem Öffnen validiert und erst nach Nutzeraktion über den Standardbrowser geöffnet werden. Die App lädt Model-Card-Inhalte in der Read-only Beta nicht automatisch.

### 9.6 Zeitstempel

- **FR-TIM-001 (P0):** Die App MUST `providerDownloadedAt`, `fileCreatedAt`, `fileModifiedAt` und `firstSeenAt` getrennt modellieren.
- **FR-TIM-002 (P0):** Fehlt ein echtes Provider-Download-Datum, MUST die UI `File Created`, `File Modified` oder `First Seen` statt `Downloaded` anzeigen.
- **FR-TIM-003 (P0):** Zeitstempel MUST mit lokaler Zeitzone angezeigt und intern als absolute Zeit gespeichert werden.
- **FR-TIM-004 (P1):** Bei mehreren Artefakten MUST die Aggregationsregel sichtbar sein, zum Beispiel „neueste Provider-Änderung“.

### 9.7 Lokale Präsenz, Nutzung und Alter

- **FR-AGE-001 (P0):** Die UI MUST `Stored` für auf Datenträger vorhandene Modelle und `Loaded` ausschließlich für aktuell von einer Runtime im Speicher gehaltene Modelle verwenden.
- **FR-AGE-002 (P0):** Dashboard und Filter MUST mindestens `Stored`, `Loaded`, `Usable`, `Old`, `Age Unknown` und `Incomplete` anbieten.
- **FR-AGE-003 (P0):** `lastUsedAt` darf nur aus einer dokumentierten Provider-/Runtimequelle stammen. Dateisystem-Access-Time allein gilt nicht als belastbarer Nutzungsnachweis.
- **FR-AGE-004 (P0):** Die Altersansicht MUST den verwendeten Bezugszeitpunkt ausweisen: Provider-Download, letzte bestätigte Nutzung, Datei erstellt/geändert oder zuerst erkannt.
- **FR-AGE-005 (P0):** Fehlt ein belastbarer Zeitpunkt, MUST `Age Unknown` erscheinen; die App darf keinen Ersatzwert als tatsächliches Download- oder Nutzungsdatum ausgeben.
- **FR-AGE-006 (P0):** Nutzer MUST die Altersgrenze in Settings konfigurieren können, mindestens mit 30, 90, 180 Tagen und einem freien Wert. Der Default beträgt 90 Tage und ist sichtbar.
- **FR-AGE-007 (P0):** `Old` bedeutet ausschließlich, dass der konfigurierte Schwellenwert auf die ausgewählte und sichtbare Zeitquelle zutrifft. `Old` bedeutet nicht automatisch `Unused` oder `Safe to Delete`.
- **FR-AGE-008 (P0):** Modelle MUST nach Alter und letzter bestätigter Nutzung sortierbar sein; unbekannte Werte bilden eine eigene Gruppe.
- **FR-AGE-009 (P1):** Provideradapter SHOULD eine belastbare `lastUsedAt`-Quelle liefern, falls der Provider sie besitzt; der Core erzwingt keine providerübergreifend erfundene Semantik.

### 9.8 Configs und sensible Daten

- **FR-CFG-001 (P0):** Die App MUST relevante Configs anhand providerseitiger Referenzen und einer begrenzten Dateityp-Allowlist zuordnen.
- **FR-CFG-002 (P0):** Config-Vorschauen MUST Größenlimits, binäre Erkennung und sichere Parser verwenden.
- **FR-CFG-003 (P0):** Bekannte Private-Key-, Token-, Credential-, Cookie- und Secret-Dateien dürfen nicht für Vorschau oder Indexinhalt geöffnet werden. Secretwerte aus erlaubten Configtypen dürfen niemals angezeigt, persistiert, exportiert oder geloggt werden.
- **FR-CFG-004 (P0):** Secret-verdächtige Dateien dürfen nur mit Name, Pfad, Typ und Warnhinweis erscheinen. Parser speichern ausschließlich allowlisted, nicht sensible Felder.
- **FR-CFG-005 (P1):** Nutzer MAY eine Config in der registrierten Standard-App öffnen; WTM editiert sie in der Read-only Beta nicht.
- **FR-CFG-006 (P1):** Verwaiste Referenzen auf nicht vorhandene Modelle SHOULD als eigener Befund erscheinen.
- **FR-CFG-007 (P0):** Ein führender Punkt im Dateinamen gilt nicht automatisch als Secret. Harmlose versteckte Metadaten dürfen nur über die Dateityp-Allowlist gelesen werden; bekannte Secretmuster wie `.env`, `.netrc`, Key-Dateien und Credential-Stores sind ausgeschlossen.

### 9.9 Zustands- und Readiness-Prüfung

- **FR-HLT-001 (P0):** Die App MUST folgende getrennte Achsen führen: `integrity`, `compatibility`, `validation`, `runtime`.
- **FR-HLT-002 (P0):** `integrity` MUST mindestens `unknown`, `partial`, `complete`, `corrupt` und `orphaned` unterstützen.
- **FR-HLT-003 (P0):** `compatibility` MUST Runtime installiert, Format unterstützt, Hardware/Architektur und best-effort Speicherbedarf prüfen.
- **FR-HLT-004 (P0):** `validation` MUST mindestens `untested`, `blocked`, `static-compatible`, `runtime-reachable` und `inference-verified` unterscheiden.
- **FR-HLT-005 (P0):** `runtime` MUST `stopped`, `starting`, `running`, `stopping` und `failed` unterscheiden.
- **FR-HLT-006 (P0):** Jede Aussage außer statischer Dateipräsenz MUST Prüfzeitpunkt und Adapterversion zeigen.
- **FR-HLT-007 (P0):** Ein echter Teststart darf nur explizit ausgelöst werden und MUST vorher Executable beziehungsweise Runtime, finale Argumente, geschätzten Speicherbedarf, Endpoint und Stop-Verhalten zeigen. Die UI erklärt, dass auch ein minimaler Request das gesamte Modell laden kann.
- **FR-HLT-008 (P0):** Providerstatus oder installierte Dateien allein dürfen nicht als `inference-verified` gelten. `runtime-reachable` benötigt einen erfolgreichen lokalen Healthcheck; `inference-verified` benötigt zusätzlich einen erfolgreichen minimalen Modellrequest.
- **FR-HLT-009 (P1):** Speicherbedarfsschätzungen MUST als Schätzung markiert werden und Kontextlänge, Quantisierung und Runtime berücksichtigen, soweit bekannt.

### 9.10 Löschen und Aufräumen

- **FR-DEL-001 (P0):** Vor jeder Löschung MUST eine Vorschau Modell, Artefakte, Shared-Abhängigkeiten, erwartete Freigabe und Reversibilität zeigen.
- **FR-DEL-002 (P0):** Shared Artefacts dürfen nur gelöscht werden, wenn der Provider-Löschplan keine verbleibende Referenz ausweist.
- **FR-DEL-003 (P0):** Ollama-Modelle MUST bevorzugt über die lokale API oder offizielle CLI entfernt werden.
- **FR-DEL-004 (P0):** Hugging-Face-Revisionen MUST über einen providerbewussten Delete-Plan entfernt werden; Blob-Dateien dürfen nicht ad hoc gelöscht werden.
- **FR-DEL-005 (P0):** Manuelle, nicht geteilte Dateien MUST in den macOS-Papierkorb verschoben werden; permanentes Raw Delete ist in Phase 2 verboten.
- **FR-DEL-006 (P0):** Irreversible Providerlöschung MUST explizit als irreversibel bezeichnet und separat bestätigt werden.
- **FR-DEL-007 (P0):** Aktuell laufende oder von einem laufenden Prozess geöffnete Modelle MUST vor Löschung blockiert oder kontrolliert gestoppt werden.
- **FR-DEL-008 (P0):** Identitäts-, Credential- und globale Provider-Config-Dateien sind niemals Teil einer Modelllöschung.
- **FR-DEL-009 (P0):** Nach der Aktion MUST ein gezielter Rescan prüfen, ob Zielartefakte entfernt, Providerzustand aktualisiert und verbleibende Referenzen konsistent sind. Die Änderung des freien Volume-Speichers MAY als Best-effort-Beobachtung erscheinen, gilt aber nicht als exakter Erfolgsnachweis.
- **FR-DEL-010 (P1):** Batch-Löschung MUST pro Modell einen Plan erzeugen und vor Ausführung einen Konfliktgraphen bilden.
- **FR-DEL-011 (P1):** Die App SHOULD einen lokalen, secrets-freien Auditverlauf mit Zeit, Aktion, Adapter und Ergebnis führen; Nutzer können ihn löschen.

### 9.11 Starten, Stoppen und Toolkonfiguration

- **FR-RUN-001 (P0):** Die UI MUST pro Modell nur kompatible Runtimes anbieten; `Try Anyway` ist eine bewusste Sekundäraktion.
- **FR-RUN-002 (P0):** Lokale APIs auf Loopback MUST vor CLI-Aufrufen bevorzugt werden.
- **FR-RUN-003 (P0):** Externe Prozesse MUST mit einem absoluten Executable-Pfad und separatem Argumentarray gestartet werden. `/bin/sh -c`, `/bin/zsh -c`, `eval` und Stringinterpolation sind verboten.
- **FR-RUN-004 (P0):** Zulässige Platzhalter sind versioniert und typisiert, mindestens `{modelPath}`, `{modelId}`, `{endpoint}`, `{port}` und `{configPath}`.
- **FR-RUN-005 (P0):** Beim ersten Start eines benutzerdefinierten Tools MUST die App Executable, Signaturstatus und finale Argumente anzeigen und bestätigen lassen.
- **FR-RUN-006 (P0):** Logs MUST in der App begrenzt, rotierend und secret-redacted gespeichert werden.
- **FR-RUN-007 (P0):** `Stop` darf nur einen von der App gestarteten Prozess oder eine eindeutig providerverwaltete Instanz adressieren.
- **FR-RUN-008 (P0):** Ports MUST vor Start geprüft werden; automatische Alternativports müssen dem Client korrekt übergeben werden.
- **FR-RUN-009 (P1):** OpenClaw MUST über einen ClientAdapter an einen bereits validierten lokalen Endpoint gebunden werden; es ist nicht als Model-Store darzustellen.
- **FR-RUN-010 (P1):** Unsloth MUST als separate Runtime/Studio-Integration behandelt werden; Training wird nicht von der Inventar-App orchestriert.
- **FR-RUN-011 (P1):** Tooldefinitionen MUST importierbar/exportierbar, schema-validiert und standardmäßig deaktiviert sein.
- **FR-RUN-012 (P1):** App-Bundles SHOULD über `NSWorkspace` geöffnet werden; CLI-Prozesse über `Process` ohne Shell.
- **FR-RUN-013 (P0):** `Run Test` startet bekannte CLI-Runtimes direkt über `Process` und zeigt begrenztes, redigiertes `stdout`/`stderr` in einer WTM-Konsole. WTM öffnet standardmäßig weder Terminal noch eine interaktive Shell und benötigt dafür keine Apple-Events-Automation.
- **FR-RUN-014 (P0):** Vor der ersten Ausführung eines benutzerdefinierten Executables erfolgt ausschließlich eine statische Prüfung von kanonischem Pfad, Symlink-Ziel, Eigentümer/Dateimodus, Signaturstatus, Version und optionalem Hash. Die anschließende echte Ausführung ist eine getrennte bewusste Nutzeraktion; bei geänderter Binäridentität ist erneut zu bestätigen.
- **FR-RUN-015 (P0):** Ein Test gilt erst nach erfolgreichem Prozess-/Runtime-Start, lokalem Healthcheck und optionalem minimalen Inference-Request als entsprechend verifiziert. Timeout beendet nur eine von WTM gestartete Instanz; fremde Providerprozesse werden nicht ungefragt beendet.

### 9.12 Downloads — optionale spätere Phase

- **FR-DWN-001 (P2):** Direkte Downloads MAY erst nach separatem Threat Model und Lizenz-UX ergänzt werden.
- **FR-DWN-002 (P2):** Downloads MUST pausierbar, wiederaufnehmbar, atomar finalisierbar und checksum-verifiziert sein.
- **FR-DWN-003 (P2):** Die UI MUST Lizenz, Quelle, erwartete Größe, freien Platz und Zielprovider vor Start anzeigen.
- **FR-DWN-004 (P2):** Authentifizierung MUST über Keychain bzw. offizielle Providermechanismen erfolgen; Tokens dürfen nie in Projekt- oder Toolconfigs geschrieben werden.

### 9.13 Settings und Erweiterbarkeit

- **FR-EXT-001 (P0):** Settings MUST eine kleine stabile Top-Level-Struktur `General`, `Sources`, `Integrations`, `Security` und `Advanced` verwenden. Storage Providers, Runtimes, Clients, Tools und Model-Card-Resolver werden innerhalb `Integrations` nach Rolle gefiltert, nicht als eigene Top-Level-Panes dargestellt.
- **FR-EXT-002 (P0):** Listenaktionen richten sich nach Capabilities. Built-in-Adapter können aktiviert, konfiguriert und zurückgesetzt, aber nicht dupliziert oder in ihrer Implementierung editiert werden; nutzerdefinierte Datenobjekte dürfen dupliziert und bearbeitet werden.
- **FR-EXT-003 (P0):** Built-in-Einträge bleiben unverändert referenzierbar. Nutzeränderungen werden als Override gespeichert und können einzeln oder vollständig auf Default zurückgesetzt werden.
- **FR-EXT-004 (P0):** Effektive Werte MUST ihre Herkunft `Built-in`, `Discovered`, `User Override` oder `Session` zeigen.
- **FR-EXT-005 (P0):** Neue Tool-, Runtime- und Clientdefinitionen MUST in Settings ohne Shell-String angelegt und statisch validiert werden können. Ein echter Testlauf ist ausdrücklich keine sichere Trockenprüfung und folgt FR-RUN-013 bis FR-RUN-015.
- **FR-EXT-006 (P0):** Datenmanifeste MUST versioniert, vor Import vollständig angezeigt, schema-validiert, mit Herkunft und optionalem Digest gekennzeichnet und standardmäßig deaktiviert werden.
- **FR-EXT-007 (P0):** Datenmanifeste dürfen keine ausführbaren Inhalte, Skripte, dynamischen Bibliotheken, versteckten Netzwerkrequests oder neue Löschsemantik definieren.
- **FR-EXT-008 (P0):** Neue Providerparser benötigen einen kompilierten `StorageProviderAdapter`; destruktive Provideraktionen einen getrennten `StorageActionAdapter`. Beide benötigen Review und Contract Tests und sind nicht per Settings freischaltbar.
- **FR-EXT-009 (P0):** Core-UI, Scanner und Persistenz dürfen keine feste Fallunterscheidung auf konkrete Toolnamen enthalten. Verhalten wird über Rollen und Capabilities gesteuert.
- **FR-EXT-010 (P1):** Settings MUST validierte Definitionen exportieren/importieren können; Secrets, lokale Benutzernamen und absolute persönliche Pfade sind standardmäßig zu entfernen.
- **FR-EXT-011 (P1):** Schemaänderungen MUST Migration, Backup und verständlichen Fehlerzustand unterstützen; unbekannte neuere Schemas werden read-only angezeigt.
- **FR-EXT-012 (P1):** Settings SHOULD durchsuchbar sein und pro Eintrag `Test`, `Reveal in Finder`, `Reset` und `Diagnostics` anbieten, soweit anwendbar.
- **FR-EXT-013 (P0):** Jede erweiterbare Integrationsliste MUST ein kleines Info-Element mit dem englischen Linktext `How to extend this list` anbieten. Es öffnet den passenden Abschnitt der öffentlichen Adapterdokumentation; eine kurze lokale Erklärung bleibt ohne Netzwerk verfügbar.
- **FR-EXT-014 (P0):** Die Hilfe MUST klar unterscheiden: Datenkonfiguration in Settings, Datenmanifest per Import, neuer kompilierter Adapter per GitHub Pull Request und nicht unterstützte dynamische Code-Plugins.

## 10. Einheitliches Zustandsmodell

Die UI zeigt keinen mehrdeutigen grünen Punkt. Ein Modell erhält eine kompakte Zusammenfassung plus Details:

| Achse | Beispiel | Bedeutung |
|---|---|---|
| Präsenz | `Stored · Offline SSD` | Modell ist lokal inventarisiert; Quelle kann aktuell offline sein. |
| Integrität | `Complete` | Providerstruktur und erforderliche Artefakte sind vorhanden. |
| Kompatibilität | `llama.cpp compatible` | Format und Runtime passen statisch zusammen. |
| Validierung | `Inference verified 14:32` | Ein lokaler Modellrequest war erfolgreich; der Test kann das gesamte Modell geladen haben. |
| Runtime | `Running :8080` | Eine konkrete Instanz antwortet aktuell. |
| Alter | `Last used 112 days ago` | Sichtbare Zeitquelle und Schwellenwert bestimmen die Einordnung. |

Farben dürfen Information nur unterstützen. Status MUST zusätzlich Text, Symbol und Accessibility-Label besitzen.

Die englischen Produktbegriffe sind normativ: `Stored` bezeichnet Datenträgerpräsenz, `Loaded` Runtime-Speicher, `Usable` eine zeitgebundene Kompatibilitäts-/Validierungsaussage und `Old` eine konfigurierbare Zeitauswertung. Sie dürfen in UI, öffentlicher Dokumentation und Issues nicht synonym verwendet werden.

## 11. macOS UX und Apple-Standards

### 11.1 Fenster und Navigation

- Native `NavigationSplitView`-Struktur: Sidebar, sortierbare Tabelle, Inspector/Detail.
- Standard-Toolbar mit Scan, Suche, Filter und kontextabhängiger Primäraktion.
- Alle Aktionen zusätzlich über Menüleiste und sinnvolle Tastaturkürzel.
- Kontextmenüs für Finder, Config öffnen, Readiness prüfen, Start/Stop und Löschen.
- Sidebar muss ein-/ausblendbar sein und System-Akzentfarbe respektieren.
- Window-Restore darf keine bereits entfernten Pfade oder Secrets serialisieren.

### 11.2 Menüleisten-Symbol

- Native Umsetzung als macOS-Status-Item mit monochromem Template-Icon; kein dauerhaftes Textlabel in der Menüleiste.
- Das Popover zeigt ausschließlich den vereinfachten Status und kurze Aktionen, keine verkleinerte Kopie der Haupttabelle.
- Warn- und Laufzustände dürfen nicht ausschließlich über Farbe kommuniziert werden.
- Das Symbol ist in den Einstellungen deaktivierbar; die Haupt-App bleibt eine reguläre Dock-App.
- Login-Start und Sichtbarkeit des Menüleisten-Symbols sind getrennte Einstellungen.

### 11.3 Scan-Freigabe

- Onboarding verwendet einen kurzen Drei-Schritt-Ablauf: Zweck erklären, Quellen einzeln wählen, read-only Scan bestätigen.
- Jede Quelle zeigt Pfad, Provider, Zugriffsmodus und lokale Verarbeitung vor der Bestätigung.
- Ein sichtbarer `Why does WTM need access?`-Link erklärt Scan, Index und spätere getrennte Löschberechtigung.
- Ablehnung ist ein gültiger Zustand ohne Sackgasse; `Set Up Later` und `Grant Access Again` bleiben dauerhaft auffindbar.
- Systemfehler und WTM-interne Deaktivierung werden sprachlich und visuell getrennt.
- Die App darf Nutzer nicht mit Full-Disk-Access-Anweisungen unter Druck setzen.

### 11.4 Accessibility

- Vollständig mit VoiceOver und Tastatur bedienbar.
- Fokusreihenfolge entspricht visueller Hierarchie.
- Keine ausschließlich farbcodierten Zustände.
- Dynamische Systemschrift, ausreichender Kontrast und Unterstützung von Reduce Motion/Transparency.
- Custom Icons benötigen Accessibility-Labels; dekorative Elemente werden ausgeblendet.
- Klickziele erfüllen Apples macOS-Mindestgrößen; destruktive Primäraktionen erhalten ausreichenden Abstand.
- Accessibility Inspector und VoiceOver-Test sind Release-Gates.

### 11.5 Logo und App Icon

- Eigenständiges, textfreies Kernmotiv; Empfehlung: gestapelte Model-Blöcke kombiniert mit einer abstrahierten Baum-/Speicherstruktur.
- 1024 × 1024 px Master, zentrierter Safe-Bereich, Layer für aktuelle macOS-Icon-Darstellung.
- Keine vorab maskierten runden Ecken.
- Keine SF Symbols als App-Icon, Logo oder Marke; SF Symbols sind nur für UI-Aktionen zulässig.
- Keine Logos von Ollama, Hugging Face, Apple oder anderen Projekten ohne geklärte Nutzungsrechte.
- Varianten müssen in Default, Dark, Clear und Tinted erkennbar bleiben.
- Repository erhält ein separates, skalierbares Wort-/Bildzeichen als SVG und eine monochrome Variante.

### 11.6 Settings

- Settings öffnen nativ über den App-Menübefehl `Settings…` und `Command-,` in einem eigenen Fenster.
- Die Top-Level-Panes bleiben auf `General`, `Sources`, `Integrations`, `Security` und `Advanced` begrenzt; der zuletzt verwendete Pane wird wiederhergestellt.
- Häufige, taskbezogene Aktionen wie Scan, Reveal, Test, Start, Stop oder Delete bleiben im Hauptfenster beziehungsweise Inspector und werden nicht in Settings versteckt.
- `How to extend this list` ist eine sekundäre Infoaktion mit Textlabel und Accessibility-Label, kein unbeschriftetes, schwer auffindbares Symbol.

## 12. Security und Privacy

- **SEC-001:** Alle Inventardaten bleiben standardmäßig lokal.
- **SEC-002:** Keine Telemetrie in den initialen Releases. Crashreports nur nach explizitem Opt-in und vor Upload einsehbar.
- **SEC-003:** Netzwerkzugriff ist für Inventar und lokale Aktionen nicht erforderlich; Runtimezugriffe sind standardmäßig auf Loopback beschränkt.
- **SEC-004:** Provider- und Tool-Inputs gelten als untrusted. Pfade, Manifeste, JSON/TOML/YAML und Prozessausgaben sind begrenzt und sicher zu parsen.
- **SEC-005:** Pfadtraversal, Symlink-Escape, Command Injection und TOCTOU zwischen Löschvorschau und Ausführung sind explizite Threat-Model-Fälle.
- **SEC-006:** Löschpläne enthalten File-System-Identitäten; vor Ausführung MUST jede Identität erneut geprüft werden.
- **SEC-007:** Keine Secrets in Logs, Exporten, Diagnosedaten oder UI-Vorschauen.
- **SEC-008:** Keine Runtime-Ausnahmen, deaktivierte Library Validation oder unsigned executable memory ohne genehmigtes ADR und Security Review.
- **SEC-009:** Release-Builds sind Developer-ID-signiert, mit Hardened Runtime notarized und das Ticket ist gestapelt.
- **SEC-010:** Abhängigkeiten sind minimiert, versioniert, automatisiert geprüft und mit SBOM veröffentlicht.
- **SEC-011:** Das Projekt MUST `SECURITY.md`, Responsible-Disclosure-Prozess und unterstützte Versionen dokumentieren.
- **SEC-012:** Diagnosepakete benötigen Vorschau, Redaction-Test und explizite Nutzerfreigabe.
- **SEC-013:** Scan-Zustimmung ist least-privilege, pro Quelle widerrufbar und getrennt von destruktiven Berechtigungen.
- **SEC-014:** Importierte Extension-Manifeste sind untrusted data; unbekannte Felder, Schemafehler oder ausführbare Payloads führen zur Ablehnung.
- **SEC-015:** GitHub-Release-Secrets dürfen nur in geschützten Release-Environments und niemals in Workflows aus Fork-Pull-Requests verfügbar sein.
- **SEC-016:** Actions von Drittanbietern MUST auf einen geprüften vollständigen Commit-SHA gepinnt werden.
- **SEC-017:** Der Phase-1-Build ist scan-only und enthält keinen aus UI oder Adapter erreichbaren Lösch-, Schreib- oder Prozessstartpfad. Dies wird durch Architekturtests geprüft.
- **SEC-018:** Ein gestartetes externes Tool verlässt die WTM-Vertrauensgrenze und besitzt grundsätzlich die Rechte des angemeldeten Nutzers. Die erste Ausführung MUST diesen Umstand verständlich anzeigen.

## 13. Nichtfunktionale Anforderungen

### 13.1 Performance

- **NFR-PERF-001:** Erste gefundene Einträge innerhalb von 2 Sekunden nach Scanstart auf einem Apple-Silicon-Mac mit internem SSD-Speicher.
- **NFR-PERF-002:** Scan von 100.000 Verzeichniseinträgen ohne Hashing in höchstens 30 Sekunden als Release-Benchmark.
- **NFR-PERF-003:** UI-Interaktionen blockieren den Main Thread nicht länger als 100 ms.
- **NFR-PERF-004:** Idle-CPU nach abgeschlossenem Scan unter 1 % im 5-Minuten-Mittel; Speicherziel unter 300 MB bei 10.000 Modell-/Artefakteinträgen.
- **NFR-PERF-005:** Wenn FSEvents aktiviert ist, werden Events mindestens 500 ms gebündelt und background-priorisiert verarbeitet.

### 13.2 Zuverlässigkeit

- **NFR-REL-001:** Scanner und Index sind crash-safe; unvollständige Transaktionen werden beim Start verworfen oder wiederholt.
- **NFR-REL-002:** Eine defekte Quelle oder ein defektes Manifest darf andere Quellen nicht blockieren.
- **NFR-REL-003:** Der Index ist vollständig regenerierbar; er ist nie alleinige Quelle für eine Löschentscheidung.
- **NFR-REL-004:** Provideradapter haben Capability Negotiation und Versionsgrenzen; unbekannte Versionen degradieren auf read-only.
- **NFR-REL-005:** Destruktive Aktionen sind idempotent oder liefern einen klaren partiellen Ergebnisbericht.

### 13.3 Wartbarkeit

- **NFR-MNT-001:** Swift 6 Strict Concurrency; keine ungeprüften `@unchecked Sendable`-Workarounds im Core.
- **NFR-MNT-002:** Adapter sind über öffentliche interne Protokolle und Contract Tests entkoppelt.
- **NFR-MNT-003:** Core-Logik erreicht mindestens 85 % Branch Coverage; Löschplan- und Pfadschutzlogik 100 %.
- **NFR-MNT-004:** Keine realen Nutzerverzeichnisse in Tests. Fixtures und temporäre Verzeichnisse sind Pflicht.
- **NFR-MNT-005:** Öffentliche Datenformate und Tool-Schemas sind semantisch versioniert und migrationsfähig.

### 13.4 Kompatibilität und Lokalisierung

- **NFR-CMP-001:** Deployment Target macOS 15; Release-Tests auf macOS 15 und den zwei jeweils aktuellen Major-Versionen.
- **NFR-CMP-002:** Apple-Silicon-native Release-Builds; Intel wird als Entscheidung einer späteren Phase geführt.
- **NFR-L10N-001:** Produktsprache ist ausschließlich Englisch. Alle UI-Texte, Menüs, Fehlermeldungen, Accessibility-Labels, Onboarding-Texte und Release-Artefakte MUST Englisch sein.
- **NFR-L10N-002:** Architektur MUST String Catalogs und stabile Localization Keys verwenden; sichtbare Strings dürfen nicht im Swift-Code hardcodiert werden. Weitere Produktsprachen sind eine spätere Entscheidung.
- **NFR-L10N-003:** Dieses deutschsprachige `REQUIREMENTS.md` ist die einzige zulässige nicht-englische Datei im öffentlichen Repository und die normative Produktspezifikation.
- **NFR-L10N-004:** Mit Ausnahme von `REQUIREMENTS.md` MUST jeder öffentliche GitHub-Inhalt Englisch sein, einschließlich README, Docs, ADRs, Issues, Forms, Discussions, Project, PRs, Changelog, Release Notes, Code Comments und Commit-/Tag-Beschreibungen.
- **NFR-L10N-005:** Website, DMG-Texte, Update-Feed, Support- und Security-Kommunikation MUST Englisch sein.
- **NFR-L10N-006:** Größen nutzen dezimale GB in der UI; exakte Bytes sind im Inspector verfügbar. Datums- und Zahlenformatierung folgt der Nutzer-Locale, obwohl die Produktoberfläche Englisch bleibt.

### 13.5 Swift Code Style und Qualität

- **NFR-STYLE-001:** Swift-Code MUST den offiziellen Swift API Design Guidelines folgen. Klarheit am Aufrufort hat Vorrang vor Kürze; Namen bilden Fachsprache und keine Implementierungsdetails ab.
- **NFR-STYLE-002:** Das Repository MUST genau eine versionierte Root-Konfiguration `.swift-format` verwenden. Format und Lint laufen mit dem `swift-format` der gepinnten Xcode-/Swift-Toolchain; `swift-format lint --strict` ist merge-blockierend.
- **NFR-STYLE-003:** Es wird initial kein zweiter, überlappender Style-Linter eingeführt. SwiftLint oder eigene Regeln benötigen einen belegten, von `swift-format` nicht abgedeckten Zweck und ein ADR.
- **NFR-STYLE-004:** CI- und Release-Builds behandeln Compilerwarnungen als Fehler. Einzelne Warning-Suppressions benötigen einen lokalen Kommentar mit Begründung; projektweite pauschale Suppressionen sind verboten.
- **NFR-STYLE-005:** Swift 6 Strict Concurrency ist für alle eigenen Targets aktiv. UI-Zustand liegt auf `@MainActor`; Scanning, SQLite, Parsing und Prozesse blockieren niemals den Main Actor.
- **NFR-STYLE-006:** Bevorzugt werden unveränderliche `struct`-/`enum`-Werte mit explizitem `Sendable`. Globale veränderliche Zustände, Service-Locator und Singletons außer unveränderlichen Systemfacades sind verboten.
- **NFR-STYLE-007:** `@unchecked Sendable`, `Task.detached`, Force Casts, Force Unwraps und `try!` sind in Produktcode standardmäßig verboten. Jede unvermeidbare Ausnahme benötigt minimale Kapselung, Begründung und fokussierte Tests.
- **NFR-STYLE-008:** Fehler werden als typisierte Domänenfehler propagiert und erst an UI-/Diagnosegrenzen in nutzerverständliche Meldungen übersetzt. Eingaben oder Providerfehler dürfen keinen `fatalError`, `preconditionFailure` oder Prozessabbruch auslösen.
- **NFR-STYLE-009:** Produktcode verwendet `Logger`/OSLog mit stabilem Subsystem und Modul-Kategorien statt `print`. Dynamische Pfade, Modell-IDs, Argumente und sonstige Nutzerdaten sind standardmäßig private und dürfen nur nach Security Review als public geloggt werden.
- **NFR-STYLE-010:** Öffentliche oder modulübergreifende Protokolle, Capabilities, Datenmodelle und nicht offensichtliche Sicherheitsinvarianten MUST DocC-kompatible Dokumentationskommentare und mindestens ein verständliches Nutzungsbeispiel besitzen.
- **NFR-STYLE-011:** Vage Sammelnamen wie `Manager`, `Helper`, `Utils` oder `Common` sind ohne klar definierte Fachverantwortung zu vermeiden. Dateien und Typen werden nach Capability oder Domäne benannt.
- **NFR-STYLE-012:** Abhängigkeiten werden ausschließlich über Swift Package Manager und Apple-Systemframeworks eingebunden, minimiert und in `Package.resolved` fixiert. Private APIs, ungeprüfte Binärframeworks und Copy-paste Vendorcode sind verboten.

### 13.6 Projektstruktur und Modulgrenzen

Die App verwendet ein dünnes Xcode-App-Target und ein lokales Swift Package. Apple empfiehlt lokale Packages zur Modularisierung; mehrere unabhängige Packages oder Repositories werden erst bei einem belegten Release- oder Ownership-Bedarf eingeführt.

```text
WTM.xcodeproj
App/
├── WTMApp/
│   ├── Application/          # App lifecycle and composition root
│   ├── Features/             # SwiftUI feature slices
│   └── Resources/            # Asset and String Catalogs
├── WTMAppTests/            # App-bound integration tests
└── WTMAppUITests/          # XCUITest and launch scenarios
Packages/
└── WTMKit/
    ├── Package.swift
    ├── Sources/
    │   ├── WTMDomain/
    │   ├── WTMAdapterContracts/
    │   ├── WTMInventory/
    │   ├── WTMPersistence/
    │   ├── WTMSecurity/
    │   ├── AdapterOllama/
    │   ├── AdapterHuggingFace/
    │   └── AdapterManual/
    └── Tests/<TargetName>Tests/Fixtures/
    # Later phase targets, not linked into the Phase-1 app:
    # WTMActions, ActionOllama, ActionHuggingFace, ActionManual
    # WTMRuntime, RuntimeOllama, RuntimeLlamaCpp, WTMClients
Config/                     # Versioned xcconfig files; never secrets
docs/                       # English architecture and contributor docs
website/                    # English static GitHub Pages site
scripts/                    # Versioned local/CI entry points
.github/                    # Workflows, forms, templates, ownership
```

- **NFR-STR-001:** Verzeichnisstruktur auf Disk und Xcode-Navigator MUST übereinstimmen. File-system-synchronized Groups werden bevorzugt, um unnötige `project.pbxproj`-Konflikte zu vermeiden.
- **NFR-STR-002:** `WTMApp` ist Composition Root und UI-Shell. SwiftUI Views dürfen weder Dateisystem, SQLite, lokale HTTP-APIs noch `Process` direkt verwenden.
- **NFR-STR-003:** `WTMDomain` enthält Entitäten, Value Types und fachliche Zustände ohne Import konkreter Adapter, AppKit/SwiftUI, SQLite oder Prozessausführung.
- **NFR-STR-004:** `WTMAdapterContracts` enthält Protokolle und Capabilities. Jeder konkrete Provider-/Runtime-/Clientadapter besitzt einen eigenen SwiftPM-Target und darf nur nach innen auf Contracts und Domain abhängen.
- **NFR-STR-005:** Target-Abhängigkeiten bilden einen gerichteten, zyklusfreien Graphen. Konkrete Adapter werden ausschließlich im Composition Root registriert; kein Core-Target importiert einen konkreten Adapter.
- **NFR-STR-006:** Scan-only, Actions und Runtimes bleiben auch auf Targetebene getrennt. Phase 1 verlinkt keine Action- oder Runtime-Implementierung; spätere Targets exponieren nur capability-spezifische Protokolle.
- **NFR-STR-007:** Gemeinsame Testdaten liegen im jeweiligen Testtarget oder einem expliziten `TestSupport`-Target und gelangen nie in das Release-Bundle. Reale Nutzerpfade und nicht redistribuierbare Modelldateien sind verboten.
- **NFR-STR-008:** Buildkonfigurationen liegen in versionierten `.xcconfig`-Dateien. Shared Schemes und Test Plans werden versioniert; Team-ID, Zertifikate, Notarisierungszugänge und sonstige Secrets liegen weder dort noch im Projektfile.
- **NFR-STR-009:** Neue Targets benötigen klaren Owner, eine einzelne fachliche Verantwortung, dokumentierte Abhängigkeiten und Tests. Ein Target wird nicht allein zur Verkürzung von Dateien oder zur Erzeugung vermeintlicher Modularität angelegt.
- **NFR-STR-010:** Swift Testing ist Standard für Unit-, Contract- und direkt aufrufende Integrationstests. XCTest/XCUITest bleibt für UI-Automation und dort, wo Swift Testing die benötigte Xcode-Funktion nicht abdeckt.

## 14. Fehler- und Diagnosemodell

Jeder Fehler besitzt:

- stabilen internen Code, zum Beispiel `HF_CACHE_CORRUPT`;
- kurze Nutzerbeschreibung;
- betroffene Quelle/Modell-ID;
- technische Evidenz ohne Secrets;
- konkrete nächste Aktion;
- Schweregrad `info`, `warning`, `error`, `blocking`;
- Zeitpunkt und Adapterversion.

Die App darf `nicht erkannt`, `nicht installiert`, `nicht kompatibel`, `nicht getestet`, `Test fehlgeschlagen` und `kein Traffic/kein Request` nicht vermischen.

## 15. Teststrategie und Release-Gates

### 15.1 Automatisierte Tests

- Unit Tests für Pfadnormalisierung, Identität, Größenrechnung, Datumsprovenienz und Zustandsautomaten.
- Unit Tests für die Trennung von `ModelIdentity`, `ModelVariant`, `ModelInstallation`, `Artifact` und `RuntimeInstance`, einschließlich gleicher Varianten auf mehreren Volumes.
- Fixture-basierte Tests für Ollama-Manifeste, HF-Snapshots/Blobs/Refs/`.incomplete`, GGUF und Safetensors-Verzeichnisse.
- Contract Tests pro Adapter gegen unterstützte Versionen.
- Contract Tests für Registry, Capability Negotiation, Defaults/Overrides und Manifestmigration.
- Property-/Fuzz-Tests für untrusted Manifeste und Tool-Schemas.
- Integrationstests für lokale APIs mit Stub-Servern.
- Destruktive Tests ausschließlich in isolierten temporären Verzeichnissen.
- UI-Tests für Scan, Filter, Finder, Startvorschau, Löschvorschau und Tastaturnavigation.
- UI-Tests für Ablehnen, späteres Erlauben, falschen Ordner, Widerruf und erneute Freigabe.
- Tests für gespeicherte/geladene Zustände, Altersquellen, unbekanntes Alter und konfigurierbare Schwellenwerte.
- Architekturtest, dass der Phase-1-Build keinen `ActionExecutor`, `RuntimeBroker` oder schreibenden Dateiöffnungspfad enthält.
- Tests für Config-Allowlist, ausgeschlossene Secretmuster und harmlose Dotfiles.
- Falls FSEvents aktiviert wird: Tests für Dropped Events, `MustScanSubDirs`, Root-Wechsel und Unmount während des Scans.
- Linktests zwischen Settings-Hilfe, `docs/adapters.md` und den Ankern der Website-Seite `Extend WTM`.

### 15.2 Manuelle Release-Gates

- VoiceOver und Accessibility Inspector ohne kritische Befunde.
- Light/Dark, reduzierte Bewegung, hohe Kontraste und verschiedene Systemsprachen.
- Getrenntes externes Volume, offline Volume, Read-only-Quelle und gebrochene Symlinks.
- Mehrere zusätzliche HDDs/SSDs, Unmount während eines Scans und Wiedererkennung nach erneutem Mounten.
- Große und geteilte HF-/Ollama-Caches mit erwarteter Freigabeprüfung.
- Absolute und prozentuale Speicheransicht mit sichtbaren `Shared`-/`Unknown`-Kategorien, explizitem Active-/Offline-Scope und einer 100-Prozent-Summe nur innerhalb des gewählten Scopes.
- Menüleisten-Popover, deaktiviertes Symbol und Navigation vom Kompaktstatus ins Hauptfenster.
- Bestätigte, mehrdeutige und manuell ergänzte Model-Card-Links ohne automatischen Netzwerkabruf.
- Erstfreigabe, Ablehnung, Recovery, Widerruf und read-only Preflight auf einem sauberen Benutzerkonto.
- Settings-Erweiterungen, Reset auf Defaults, ungültige/neue Schemas und Export ohne persönliche Pfade.
- Gatekeeper-Test auf sauberem Mac-Benutzerkonto.
- `codesign`, Hardened Runtime, Notarisierung, Stapling und `spctl` erfolgreich.
- Keine Secrets in Diagnoseexport, Logs oder Crashfixtures.

## 16. GitHub- und Open-Source-Anforderungen

### 16.1 Operating Model

- **GH-OPS-001:** GitHub ist Source of Truth für Code, das normative deutsche `REQUIREMENTS.md`, Architekturentscheidungen, Bugs, Roadmap, Community, Dokumentation und Releases.
- **GH-OPS-002:** Das Repository startet privat unter GitHub Free und wird erst nach Public-Readiness-Review veröffentlicht.
- **GH-OPS-003:** Private Entwicklung darf keine Secrets, proprietären Fixtures, persönlichen Pfade oder inkompatible Lizenzen in Commit-Historie aufnehmen; bloßes Löschen vor Veröffentlichung reicht nicht.
- **GH-OPS-004:** Es werden alle fachlich relevanten GitHub-Funktionen genutzt. Nicht benötigte Produkte wie Wiki, Packages oder Codespaces werden nicht ohne konkreten Owner und Use Case aktiviert.
- **GH-OPS-005:** Repository- und Releaseoperationen SHOULD über versionierte Skripte und `gh` CLI wiederholbar und nachvollziehbar sein; kritische Einstellungen werden in `docs/github-configuration.md` dokumentiert.
- **GH-OPS-006:** Repositoryname, Topics, Description, Social Preview, Dateien, Commit Messages, Branches, Issues, Discussions, Projects, Pull Requests und Releases MUST vollständig Englisch sein; einzige Dateiausnahme ist `REQUIREMENTS.md`.
- **GH-OPS-007:** `REQUIREMENTS.md` wird in deutscher Sprache versioniert und ist normativ. Englische Produkt- und Entwicklerdokumentation darf Anforderungen erklären oder verlinken, bildet aber keine zweite normative Requirements-Kopie.
- **GH-OPS-008:** README und Website verlinken die Datei sichtbar als `Requirements (German, normative)` und weisen darauf hin, dass Browser-/Nutzerübersetzungen nicht vom Projekt gepflegt oder normativ sind.

### 16.2 Repository und Community

Das Repository MUST enthalten:

- `README.md` mit Problem, Screenshots, Status, Support-Matrix, Installation, Sicherheitsmodell, Grenzen und Roadmap-Link.
- `LICENSE` — Empfehlung: Apache-2.0; finale Wahl vor öffentlicher Veröffentlichung.
- `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, `SUPPORT.md`, `SECURITY.md`, `CHANGELOG.md` und `CITATION.cff`.
- `docs/architecture.md`, `docs/adapters.md`, `docs/threat-model.md`, `docs/github-configuration.md` und `docs/decisions/`.
- `docs/adapters.md` MUST die Rollen `StorageProviderAdapter`, `StorageActionAdapter`, `RuntimeAdapter`, `ClientAdapter`, `ManualFolderAdapter`, datenbasierte Tool-/Source-/Linkdefinitionen sowie deren Capability- und Sicherheitsgrenzen erklären.
- Der Adapterguide MUST pro Erweiterungsart zeigen, welche Änderungen nur Settings oder ein Datenmanifest benötigen und welche einen SwiftPM-Adapter, Fixtures, Contract Tests, Security Review und Pull Request erfordern.
- `CODEOWNERS`, Pull-Request-Template und Issue Forms für Bug, Feature, Provider/Runtime-Support und Dokumentation.
- Root-`.swift-format`, versionierte `Config/*.xcconfig`, Shared Schemes und mindestens einen versionierten Xcode Test Plan.
- `docs/code-style.md` und `docs/project-structure.md` als englische, beitragstaugliche Kurzfassung von Abschnitt 13.5 und 13.6.
- Reproduzierbare Xcode-/SwiftPM-Buildanweisung und lokale Entsprechung jedes verpflichtenden CI-Checks.
- Screenshots und Fixtures ohne private Pfade, Benutzernamen, Modelllizenzen oder Tokens.

- **GH-COM-001:** GitHub Issues erfassen konkrete, reproduzierbare Bugs und umsetzbare Tasks. Bug Forms fragen WTM-Version, macOS, Architektur, Provider, redigierte Logs und Reproduktionsschritte ab.
- **GH-COM-002:** GitHub Discussions dienen Q&A, Ideen, Showcases und allgemeiner Adapterplanung; bestätigte Arbeit wird in ein Issue überführt.
- **GH-COM-003:** Sicherheitslücken dürfen nicht als öffentliches Issue gemeldet werden; `SECURITY.md` verweist auf GitHub Private Vulnerability Reporting/Security Advisories.
- **GH-COM-004:** Ein GitHub Project bildet Roadmap und Status ab. Unter GitHub Free wird maximal der verfügbare automatische Auto-add-Workflow vorausgesetzt.
- **GH-COM-005:** Labels MUST mindestens `bug`, `enhancement`, `provider`, `runtime`, `security`, `accessibility`, `good first issue`, `help wanted`, `needs reproduction` und Prioritäten abdecken.
- **GH-COM-006:** Pull Requests MUST klein, reviewbar und mit Tests, Changelog-/Dokumentationswirkung und aktualisierten Adapterfixtures versehen sein.
- **GH-COM-007:** Releases und geschlossene Milestones erzeugen Community-taugliche Release Notes; Breaking Changes und Migrationen stehen zuerst.
- **GH-COM-008:** Eine englische Issue Form `Adapter proposal` fragt Rolle, Provider-/Toolversion, Discoverypfade oder API, Capability-Umfang, Lösch-/Prozessrisiko, Beispiel-Fixtures und Teststrategie ab. Bestätigte Adapterarbeit erfolgt als reviewbarer Pull Request.

### 16.3 GitHub Actions und Standardtests

- **GH-CI-001:** `ci.yml` läuft auf jedem Pull Request und Push auf `main` mit Concurrency-Cancel für überholte Runs.
- **GH-CI-002:** Pflichtjobs sind Format/Lint, SwiftPM-Core-Build, Unit Tests, Adapter Contract Tests, Manifest-/Fixture-Validierung, Xcode-App-Build und UI-Smoke-Test.
- **GH-CI-003:** Die macOS-Matrix deckt das Deployment Target und die aktuelle stabile Runner-/Xcode-Kombination ab. Preview-Runner sind nicht merge-blockierend.
- **GH-CI-004:** Performance-, Fuzz- und vollständige UI-Tests laufen geplant oder vor Release, nicht bei jeder Dokumentationsänderung.
- **GH-CI-005:** Private-Repo-Workflows MUST die GitHub-Free-Minuten durch Path Filter, Caches, Concurrency-Cancel und sparsame macOS-Jobs schützen. Paid Overages sind standardmäßig deaktiviert.
- **GH-CI-006:** Der private Free-Plan MUST einen gepinnten OSS-Secret-Scan ausführen, solange GitHubs vollständiges Secret Scanning/Push Protection nicht verfügbar ist.
- **GH-CI-007:** Nach Veröffentlichung werden Dependency Graph, Dependabot Alerts/Updates, Secret Scanning, Push Protection, Dependency Review und Code Scanning aktiviert, soweit im öffentlichen Free-Repository verfügbar.
- **GH-CI-008:** Workflow-Berechtigungen folgen least privilege; `GITHUB_TOKEN` erhält pro Job nur explizit benötigte Scopes.
- **GH-CI-009:** Merge auf `main` erfordert grüne Pflichtchecks und gelöste Review-Kommentare, soweit der aktuelle Plan dies technisch erzwingen kann.
- **GH-CI-010:** CI verwendet die dokumentierte Xcode-/Swift-Toolchain für `swift-format`; lokal und CI laufen dieselben versionierten Skript-Einstiegspunkte. Formatierungsänderungen werden nicht still im CI-Workspace geschrieben, sondern als Fehler gemeldet.
- **GH-CI-011:** Ein Architekturcheck validiert erlaubte Target-Abhängigkeiten, verbotene Core-→Adapter-Imports und das Fehlen von Action-/Runtime-Targets im Phase-1-Release-Graph.
- **GH-CI-012:** Pflichtchecks wachsen phasenweise mit Abschnitt 18.1. Eine neue Capability darf nicht gemergt oder ausgeliefert werden, bevor ihr Phase-Gate als Test beziehungsweise dokumentierter manueller Check existiert.

### 16.4 DMG- und Release-Pipeline

- **GH-REL-001:** `release.yml` startet ausschließlich für einen freigegebenen SemVer-Tag und ein geschütztes GitHub-Environment `release`.
- **GH-REL-002:** Die Pipeline erzeugt die Release-App wiederholbar und nachvollziehbar aus einem eindeutigen Commit, importiert Developer-ID- und Notarisierungscredentials nur zur Laufzeit und entfernt sie anschließend aus dem Runner-Keychain. Eine byteidentische Reproduzierbarkeit des signierten/notarisierten DMG wird nicht behauptet.
- **GH-REL-003:** Die App und alle eingebetteten Executables werden signiert, mit Hardened Runtime gebaut, notarized und das Ticket wird gestapelt.
- **GH-REL-004:** Die Pipeline rendert eine gebrandete DMG mit App, `Applications`-Verknüpfung, versioniertem Hintergrund und dokumentiertem Layout.
- **GH-REL-005:** Release-Gates sind `codesign --verify --deep --strict`, `stapler validate`, `spctl`, DMG-Mount, Kopier-/Start-Smoke-Test und Malware-/Secret-Prüfung der Artefakte.
- **GH-REL-006:** GitHub Release enthält DMG, SHA-256-Prüfsumme, SPDX- oder CycloneDX-SBOM, Release Notes und – nach öffentlicher Verfügbarkeit – Artifact Attestation.
- **GH-REL-007:** Kein Signing- oder Notarisierungssecret ist für Fork-PRs verfügbar. Releases aus nicht vertrauenswürdigem Code sind technisch ausgeschlossen.
- **GH-REL-008:** Ein fehlgeschlagenes Release darf weder `latest` noch Update-Feed verändern; Veröffentlichung erfolgt erst nach allen Gates atomar.
- **GH-REL-009:** Release-Metadaten dokumentieren Commit-SHA, SemVer, macOS-/Xcode-/Swift-Version, Dependency-Lockfile, Workflow-Run, Checksummen und Notarisierungsergebnis. Ein unsigned App-Payload MAY separat auf Reproduzierbarkeit geprüft werden.

### 16.5 GitHub Pages Website

- **GH-WEB-001:** Eine kleine statische Produktwebsite liegt versioniert unter `website/` und wird über GitHub Actions auf GitHub Pages veröffentlicht.
- **GH-WEB-002:** Standardadresse ist `https://<owner>.github.io/<repository>/`; eine Custom Domain ist optional.
- **GH-WEB-003:** Die Website enthält Nutzenversprechen, Screenshots, Feature-/Provider-Matrix, Downloadlink zur neuesten GitHub Release, Sicherheits-/Privacy-Kurzfassung, Dokumentation, Erweiterungsleitfaden und Communitylinks.
- **GH-WEB-004:** Pages-Deployment nutzt minimale Berechtigungen `contents: read`, `pages: write`, `id-token: write` und das Environment `github-pages`.
- **GH-WEB-005:** Unter GitHub Free ist Pages für das private Repository nicht verfügbar. Website und Workflow werden privat vorbereitet, aber erst mit dem Public-Schalten veröffentlicht; alternativ wäre ein bewusst separates öffentliches Pages-Repository nötig.
- **GH-WEB-006:** Website-Build, interne Links, Accessibility und fehlende Assets sind Pflichtchecks vor Pages-Deployment.
- **GH-WEB-007:** Sämtlicher Website-Content, Metadaten, Alt-Text, Fehlermeldungen und SEO-Text MUST Englisch sein.
- **GH-WEB-008:** Eine kompakte englische Seite `Extend WTM` MUST die Adaptertypen, erlaubte Datenmanifeste, Capability-Grenzen und den GitHub-Weg `Proposal issue → implementation → fixtures/contract tests → review → signed release` erklären. Jeder Settings-Link `How to extend this list` führt auf den passenden Anker dieser Seite.

### 16.6 Badges und Public-Readiness

- **GH-PUB-001:** README MUST dynamische Badges für CI, Tests/Coverage, Latest Release, macOS, Swift und Lizenz enthalten. Badges verlinken auf ihre überprüfbare Quelle und dürfen keinen manuellen Fantasiestatus zeigen.
- **GH-PUB-002:** Optionale Badges für offene Issues, Discussions und Downloads sind erst nach öffentlicher Aktivierung zulässig.
- **GH-PUB-003:** Vor Veröffentlichung MUST ein History-/Secret-/PII-Audit, Lizenzreview, Fixture-Review, Markencheck und Security Review abgeschlossen sein.
- **GH-PUB-004:** Beim Umschalten auf public werden Pages, Discussions, öffentliche Issue Forms, Dependabot-/Security-Funktionen, Artifact Attestations und Community-Links in einem dokumentierten Launch-Runbook aktiviert.
- **GH-PUB-005:** Der private Free-Plan hat begrenzte Actions-Minuten; öffentliche Standardrunner sind kostenlos. Planannahmen werden vor Aktivierung jeder kostenrelevanten Pipeline erneut geprüft und dokumentiert.

## 17. Abnahmekriterien der Phase 1 — Read-only Beta

Die erste nutzbare Beta ist bewusst klein und scan-only. Sie ist fertig, wenn alle folgenden Punkte erfüllt sind:

1. Ollama-, Hugging-Face- und frei gewählte Modellordner werden auf einem frischen Benutzerkonto gefunden.
2. Ausgewählte interne sowie zusätzliche HDDs/SSDs werden getrennt inventarisiert, nach erneutem Mounten wiedererkannt und offline nicht als gelöscht interpretiert.
3. Scan-Zweck und einzelne Quellen werden vor dem Zugriff verständlich erklärt; Ablehnung, falsche Auswahl, Widerruf und erneute Freigabe sind ohne Sackgasse testbar.
4. Der ausgelieferte Phase-1-Build enthält keinen erreichbaren Schreib-, Lösch- oder Prozessstartpfad; Quelldateien werden ausschließlich lesend geöffnet.
5. ModelIdentity, ModelVariant, ModelInstallation und Artifact sind getrennt persistiert; gleiche Varianten auf mehreren Volumes werden nicht zu einer Installation zusammengezogen.
6. Geteilte HF-/Ollama-Artefakte werden nicht naiv mehrfach gezählt; unsichere Zuordnung erscheint als `Shared` oder `Unknown`.
7. Mindestens ein realer und ein Fixture-basierter Teildownload werden korrekt erkannt.
8. Zeitstempel zeigen ihre Herkunft; `Stored`, `Old`, `Age Unknown` und `Incomplete` sind getrennt sichtbar. Runtimezustände sind nicht Teil der Phase-1-Abnahme.
9. Config-Dateien sind zugeordnet und Finder-fähig. Bekannte Secret-Dateien werden nicht für Vorschauen geöffnet; harmlose Dotfiles gelten nicht automatisch als geheim.
10. Absolute Größe und prozentualer aktiver Speicherbestand sind umschaltbar. Offline-Snapshots sind separat und verändern den aktuellen Nenner nicht.
11. Bestätigte Model Cards öffnen über HTTPS; mehrdeutige oder nur aus Dateinamen vermutete Links werden nicht als bestätigt dargestellt.
12. Sources und datenbasierte Integrationsdefinitionen sind ohne Core-UI-Sonderfälle konfigurierbar; `How to extend this list` erklärt den späteren PR-Weg für Codeadapter.
13. Automatisierte Core-, Adapter-, Permission-, Pfad- und Sprachtests sind grün.
14. App, DMG und alle öffentlichen Inhalte außer `REQUIREMENTS.md` sind Englisch; `REQUIREMENTS.md` ist Deutsch und normativ.
15. Ein verteiltes Beta-Artefakt ist Developer-ID-signiert, mit Hardened Runtime notarized, gestapelt und wird von Gatekeeper akzeptiert.

## 18. Phasenplan

| Phase | Inhalt | Ergebnis |
|---|---|---|
| 0 — Foundation | Adapter-Registry, Defaults/Overrides, GitHub-Struktur, Providerfixtures, Distributionstest | Erweiterbare Architektur und CI-Grundlage bestätigt |
| 1 — Read-only Beta | Permission UX, Scan, Inventar, Alter, Suche, Größen, Configs, Finder, grundlegende Settings | Nutzbarer Speicherüberblick ohne Mutationen oder Prozessstarts |
| 2 — Safe Actions | Löschpläne, Papierkorb, Audit, Verifikation | Kontrolliertes Aufräumen |
| 3 — Runtimes | Readiness, Ollama, llama.cpp, Tooldefinitionsschema | Kontrollierter Start/Stop |
| 4 — Integrationen | OpenClaw, Unsloth, MLX-Runtimes, Menüleiste | Erweiterter lokaler Workflow |
| 5 — Stable Public Release | vollständige DMG-Pipeline, GitHub Release, Pages, Community, Security-Aktivierung | Verifizierte stabile Veröffentlichung |
| 6 — Optional | Downloads, Lizenzen, Resume, Checksums | Separat freizugebender Scope |

### 18.1 Implementierungsreihenfolge und Phase Gates

Die Phasen sind die verbindliche Umsetzungsreihenfolge. Jede Phase ist ein vertikaler, testbarer Produktstand und wird erst abgeschlossen, wenn ihr Scope implementiert, dokumentiert und durch die definierten Gates nachgewiesen ist.

1. Scope und betroffene Requirements werden vor Implementierung der Phase festgelegt.
2. Architektur-, Datenmodell- oder Security-Änderungen aktualisieren ADRs und Threat Model vor dem Merge der Implementierung.
3. Implementierung erfolgt mit Unit-, Contract- und Integrationstests im selben Pull Request; sicherheitskritische Pfade erhalten negative und Race-/Failure-Tests.
4. UI-Funktionalität erhält Tastatur-, Accessibility- und mindestens einen End-to-End-Smoke-Test.
5. Phase-spezifische automatisierte Checks, manuelle Release-Gates und Dokumentation müssen grün sein.
6. Erst danach wird die Phase als GitHub Milestone geschlossen und die nächste Shipping-Phase begonnen.

Spätere Research-Spikes MAY parallel auf separaten Branches oder hinter nicht ausgelieferten Buildkonfigurationen stattfinden. Sie dürfen keine Capability in das Release-Target einer früheren Phase einschleusen und dessen Security-Grenzen nicht aufweichen.

| Phase | Obligatorische Test- und Release-Gates |
|---:|---|
| 0 | Modulgraph-/Architekturtests, Swift-6-Build, Formatter/Lint, Fixture-Lizenzprüfung, minimaler signierter/notarisierter Distribution-Smoke-Test |
| 1 | Scanner-/Parser-Unit- und Contract-Tests, reale und synthetische Cachefixtures, Permission-/TCC-/POSIX-UI-Tests, externe Volume-/Unmount-Tests, Speicher- und Identitätsrechnung, Scan-only-Architekturtest, Accessibility-Smoke-Test |
| 2 | Löschplan-/Referenzgraph-Tests, Property-/Fuzz-Tests, TOCTOU- und Symlink-Angriffe, Papierkorb-/Provider-Recovery, partielle Fehler und ausschließlich isolierte temporäre Volumes |
| 3 | Executable-/Argumentvalidierung, Process-Lifecycle, Portkonflikte, Timeout/Cancel/Stop, Loopback-Healthcheck, minimaler Inference-Request, RAM-Warnung und Log-Redaction |
| 4 | Client-Handoff, OpenClaw-/Unsloth-Contracts, Menüleisten-Lifecycle, Login-Item-Verhalten, Settings-Capabilities und Links zum Adapterguide |
| 5 | komplette OS-/Xcode-Matrix, UI-/Accessibility-Regressionssuite, Performance-Benchmarks, Security-/License-/History-Audit, DMG/Code Sign/Notarization/Stapling/Gatekeeper, SBOM/Attestation und Pages-Deployment |
| 6 | Eigenes ADR, Threat Model, Lizenz-UX, Download-Resume/Atomicity/Checksum und separate Freigabeentscheidung |

**Senior-Empfehlung:** Phase 1 kann privat getestet und anschließend als read-only Beta veröffentlicht werden. Löschung und Prozessstart werden erst nach realen Cachefixtures, Threat Model und telemetriefreien Fehlerrückmeldungen in separaten Releases freigeschaltet. Es gibt keinen phasenübergreifenden „MVP“-Sammelbegriff.

## 19. Hauptrisiken

| Risiko | Auswirkung | Gegenmaßnahme |
|---|---|---|
| Provider ändert Cacheformat | Falsches Inventar oder Löschplan | Versionserkennung, read-only Fallback, Contract Fixtures |
| Shared Content wird falsch gezählt | Irreführende Speicherwerte | Dependency Graph, getrennte Größenbegriffe |
| Shared Content wird gelöscht | Beschädigte Modelle | Providerplan, Revalidation, Block bei Unsicherheit |
| Tooldefinition wird missbraucht | Command Execution | Kein Shell-String, absolute Pfade, Bestätigung, Redaction |
| Datumsmetadaten werden überschätzt | Falsche Historie | Provenienz und Confidence verpflichtend |
| Inference-Verifikation lädt riesiges Modell | RAM-/Swap-Spitze | Opt-in, Schätzung, expliziter Hinweis, Timeout und kontrolliertes Stop-Verhalten |
| Altersanzeige suggeriert falsche Nutzung | Fehlentscheidung beim Löschen | Zeitquelle/Confidence sichtbar, unbekannt statt erfunden |
| Scan-Berechtigung wirkt zu weitreichend | Vertrauensverlust oder Abbruch | Pro Quelle, read-only, klare Zwecke, dauerhaftes Recovery |
| Konfigurierbarkeit wird zu Codeausführung | Supply-Chain-/RCE-Risiko | Datenmanifeste, Schema-Allowlist, keine Runtime-Code-Plugins |
| Adapterzahl erzeugt Core-Sonderfälle | Unwartbare Architektur | Protokolle, Capabilities, Registry, Contract Tests |
| Private Actions verbrauchen Free-Kontingent | CI-Ausfall oder Kosten | Path Filter, Cancel, Budgetstopp, sparsame macOS-Matrix |
| App-Store-Ziel wird spät gefordert | Architekturbruch | Distribution vor Implementierung verbindlich entscheiden |
| Produktlogos werden unzulässig genutzt | Marken-/Release-Risiko | Eigenes Branding, Text-Supportmatrix, Rechteprüfung |

## 20. Verbindliche Architekturentscheidung

**Entschieden:** WTM wird außerhalb des Mac App Store direkt über GitHub beziehungsweise die Projektwebsite verteilt. Die App wird mit Developer ID signiert, nutzt Hardened Runtime, wird notarized und mit einem gestapelten Notarisierungsticket ausgeliefert. App Sandbox ist in diesem Distributionsprofil deaktiviert.

Damit bleiben automatische Standardpfad-Erkennung und die spätere konfigurierbare externe Tool-Liste möglich. Die App respektiert weiterhin TCC und POSIX-/ACL-Rechte, scannt ausschließlich bekannte oder explizit konfigurierte Wurzeln und fordert weder Full Disk Access noch root-Rechte oder einen privilegierten Helper an. Phase 1 ist durch fehlende Mutations- und Prozessstartpfade sowie ausschließlich lesende Datei-APIs scan-only; dies ist eine Produkt- und Architekturgarantie, keine vom Betriebssystem erzwungene Sandbox.

Eine spätere Mac-App-Store-Ausgabe wäre ein separates, funktional reduziertes Distributionsprofil: benutzergewählte Ordner mit Security-Scoped Bookmarks, lokale APIs und das Öffnen anderer Apps; beliebige externe CLI-Starts entfallen.

## 21. Normative Referenzen

### Apple

- [Accessing files from the macOS App Sandbox](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox)
- [Preparing your app for distribution](https://developer.apple.com/documentation/xcode/preparing-your-app-for-distribution)
- [Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
- [Hardened Runtime](https://developer.apple.com/documentation/security/hardened-runtime)
- [Human Interface Guidelines: Sidebars](https://developer.apple.com/design/human-interface-guidelines/sidebars)
- [Human Interface Guidelines: Lists and tables](https://developer.apple.com/design/human-interface-guidelines/lists-and-tables)
- [Human Interface Guidelines: Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)
- [Human Interface Guidelines: Settings](https://developer.apple.com/design/human-interface-guidelines/settings)
- [Human Interface Guidelines: Privacy](https://developer.apple.com/design/human-interface-guidelines/privacy)
- [Human Interface Guidelines: App icons](https://developer.apple.com/design/human-interface-guidelines/app-icons/)
- [Human Interface Guidelines: SF Symbols](https://developer.apple.com/design/human-interface-guidelines/sf-symbols)
- [NSWorkspace](https://developer.apple.com/documentation/appkit/nsworkspace)
- [SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice)
- [Using the File System Events API](https://developer.apple.com/library/archive/documentation/Darwin/Conceptual/FSEvents_ProgGuide/UsingtheFSEventsFramework/UsingtheFSEventsFramework.html)
- [Controlling app access to files in macOS](https://support.apple.com/guide/security/controlling-app-access-to-files-secddd1d86a6/web)
- [Organizing your code with local packages](https://developer.apple.com/documentation/xcode/organizing-your-code-with-local-packages)
- [Managing files and folders in your Xcode project](https://developer.apple.com/documentation/xcode/managing-files-and-folders-in-your-xcode-project)
- [Swift Testing](https://developer.apple.com/documentation/testing)
- [Logger](https://developer.apple.com/documentation/os/logger)

### Provider und Runtimes

- [Ollama: List models API](https://docs.ollama.com/api/tags)
- [Ollama: List running models API](https://docs.ollama.com/api/ps)
- [Ollama: Delete a model API](https://docs.ollama.com/api/delete)
- [Ollama: macOS storage](https://docs.ollama.com/macos)
- [Hugging Face Hub: Cache-system reference](https://huggingface.co/docs/huggingface_hub/en/package_reference/cache)
- [Hugging Face Hub: Manage cache](https://huggingface.co/docs/huggingface_hub/guides/manage-cache)
- [llama.cpp](https://github.com/ggml-org/llama.cpp)
- [Unsloth](https://github.com/unslothai/unsloth)

### Swift und Erweiterbarkeit

- [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/)
- [swift-format](https://github.com/swiftlang/swift-format)
- [The Swift Programming Language: Protocols](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/protocols/)
- [Swift Package Manager: Plugins](https://docs.swift.org/swiftpm/documentation/packagemanagerdocs/plugins/)

### GitHub

- [GitHub-hosted runners](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)
- [GitHub Pages](https://docs.github.com/en/pages/getting-started-with-github-pages)
- [Custom workflows with GitHub Pages](https://docs.github.com/en/pages/getting-started-with-github-pages/using-custom-workflows-with-github-pages)
- [GitHub security features](https://docs.github.com/en/code-security/getting-started/github-security-features)
- [GitHub Discussions](https://docs.github.com/en/discussions/quickstart)
- [GitHub product usage by plan](https://docs.github.com/en/billing/reference/product-usage-included)

### Requirements-Sprache

- [RFC 2119](https://www.rfc-editor.org/rfc/rfc2119)
- [RFC 8174](https://www.rfc-editor.org/rfc/rfc8174)
