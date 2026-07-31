# Sicherheitsplan: TetherTTY

**Status:** Plan / Ausstehend Umsetzung
**Erstellt:** 2026-07-31
**Projekt:** TetherTTY (iOS SSH Companion)
**Repository:** `/Users/lukas/code/TetherTTY`
**Build-System:** Xcode-Projekt (`TetherTTY.xcodeproj`), iOS 18.0+
**SwiftNIO-SSH:** 0.14.1 | **SwiftTerm:** 1.15.0

**Wichtig:** Dies ist ein reiner Plan. Keine Implementierung wurde angewendet. Alle Code-Referenzen beziehen sich auf den Stand des Repositorys zum Stichtag 2026-07-31.

---

## 1. Exekutive Empfehlung

### Repository-Release

Das Repository kann nach Erfüllung des Repository-Gates in Abschnitt 7 öffentlich gemacht werden. Laufzeitschwachstellen blockieren die Veröffentlichung des Quellcodes technisch nicht. Ein Fix-first-Vorgehen für SEC-01 und SEC-03 wird dennoch empfohlen, damit die Veröffentlichung dieses Dokuments kein unnötiges Zeitfenster mit bekannten, ungepatchten Schwachstellen erzeugt.

Erforderlich vor Repository-Release:

- Autoritativer Full-History-Secrets-Scan (gitleaks oder trufflehog)
- Keine Signierungsdateien oder privaten Artefakte im Repository
- Lizenz- und Third-Party-Notice-Prüfung abgeschlossen
- SECURITY.md mit GitHub Private Vulnerability Reporting vorhanden
- README vor Release prüfen und Risikostatus dokumentieren
- CI wird dringend empfohlen und kann eine Projekt-Richtlinie sein

Warnung: Die Veröffentlichung dieses detaillierten Plans vor den Fixes macht bekannte Schwachstellen öffentlich. Vor dem Repo-Release ist eine Entscheidung erforderlich: Fixes zuerst umsetzen, Details bis zur Behebung in ein privates Advisory verschieben oder das Offenlegungsrisiko mit Begründung explizit akzeptieren. Phasen 1 bis 5 sind keine technische Voraussetzung für die Veröffentlichung des Quellcodes.

### Öffentliche App / App Store

Alle High- und Medium-Befunde müssen gelöst sein, oder es muss eine explizite, unterzeichnete Risikoakzeptanz mit Besitzer, Begründung, Ablaufdatum und Überprüfungsdatum vorliegen.

Erforderlich vor App-Store-Release:

- Alle Tests frisch bestanden (aktuell 49 XCTest-Methoden)
- Release-Build erfolgreich (Simulator und physisches Device)
- Physisches Device: Background- und App-Switcher-Test
- OSC 52 manueller Regressionstest
- Host-Key-Integrationstest
- Review des Privacy Manifests und der Privacy Nutrition Labels
- Keine ungelösten High- oder Medium-Befunde

---

## 2. Umfang, Methodik, Einschränkungen und Evidenzbasis

### Geltungsbereich

Dieser Plan deckt den vollständigen Produktionscode von TetherTTY ab:

- `TetherTTY/Networking/SSHClient.swift` — SSH-Client-Implementierung (SwiftNIO)
- `TetherTTY/Security/HostKeyTrustEvaluator.swift` — Host-Key-Verifikation
- `TetherTTY/Security/KnownHostStore.swift` — Lokale Known-Hosts-Speicherung
- `TetherTTY/Security/VaultUnlockClient.swift` — LocalAuthentication-Integration
- `TetherTTY/Persistence/CredentialStore.swift` — Keychain-Zugriff
- `TetherTTY/Persistence/ConnectionRepository.swift` — Lokale Persistenz
- `TetherTTY/Features/SSHTerminalView.swift` — Terminal-Emulation und Eingabe
- `TetherTTY/Features/AppShellView.swift` — App-Shell und Lock-Gate
- `TetherTTY/Features/PlainTerminalView.swift` — Terminal-Ansicht und Lifecycle
- `TetherTTY/Features/HostListView.swift` — Host-Liste und Trust-Flow
- `TetherTTY/Features/ConnectionEditorView.swift` — Verbindungsbearbeitung
- `TetherTTY/ViewModels/HostListViewModel.swift` — Host-Liste und Trust-Flow
- `TetherTTY/ViewModels/PlainTerminalViewModel.swift` — Terminal-Verbindungslogik
- `TetherTTY/ViewModels/AppLockViewModel.swift` — App-Lock-Logik
- `TetherTTY/Models/` — Datenmodelle (Connection, KnownHost, TerminalSession, TerminalConnectionRequest, TerminalConnectionState, AppLockState)
- `TetherTTY/Providers/` — Session-Discovery (TmuxSessionProvider, HerdrSessionProvider)
- `TetherTTYTests/` — Bestehende Tests

### Methodik

Die Analyse umfasst:

- Statische Codeanalyse: Manuelle Durchsicht aller Quelldateien auf Schwachstellen, Anti-Patterns und Abweichungen vom Defense-in-Depth-Prinzip.
- Threat-Modellierung: Identifikation von Vertrauensgrenzen, Angriffsvektoren und realistischen Preconditions.
- Test-Review: Prüfung der Testabdeckung gegen identifizierte Schwachstellen.
- Abhängigkeitsprüfung: Review der SPM-Abhängigkeiten gegen bekannte Advisories.
- Konfigurations-Review: iOS-Sicherheitseinstellungen, Keychain-Attribute, App-Lifecycle.
- NIOSSH-Quellcode-Review: Bestätigung der Protokoll-Reihenfolge (Host-Key vor User-Auth).

### Einschränkungen

- Kein dynamischer Security- oder Penetrationstest durchgeführt.
- Keine binäre Analyse oder Reverse-Engineering.
- Keine Pentests gegen entfernte SSH-Server.
- Keine formale Verifikation.
- Keine Prüfung von iOS-System-Schwachstellen oder Jailbreak-Szenarien.
- Ergebnis: qualitativer Audit, keine statistische Aussage.

### Evidenzbasis (Baseline)

| Prüflauf | Ergebnis | Bemerkung |
|---|---|---|
| Secrets-Scan (Regex Current + History) | Keine bekannten Secrets gefunden | Kein Beweis für Abwesenheit, gitleaks/trufflehog nicht vorhanden |
| Dependency Advisory Check (exakte Pins) | Keine bekannten ungepatchten Advisories für aktuelle Pins | Stand: Audit-Datum. Abwesenheit ist kein Beweis. |
| Unit Tests | 49 Tests bestanden | Frischer Lauf am 2026-07-31 auf dem iPhone-17-Simulator |
| Release Build (Simulator) | Erfolgreich | Generisches iOS-Simulator-Ziel |
| Keychain Positive Control | Passwörter werden gespeichert und abgerufen | `KeychainCredentialStore` funktioniert |
| Telemetry / Backend | Nicht vorhanden | Keine Netzwerk-Aufrufe außer SSH |
| Known-Hosts Persistence | UserDefaults-basiert | JSON-gespeichert, nicht verschlüsselt |

---

## 3. Threat-Modell und Vertrauensgrenzen

### Vertrauensannahmen

| Vertrauensgrenze | Vertraut | Nicht vertraut | Bemerkung |
|---|---|---|---|
| iOS-Gerät-Sandbox | Ja | Jailbreak-Umgebung | Standard iOS-Sicherheitsmodell |
| Keychain | Ja | Direkter Zugriff auf Passwörter | `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` |
| LocalAuthentication (Face-ID) | Ja | Umgehung des App-Locks | Nur App-Level-Gate, kein Kryptographie-Element |
| SSH-Transport | Teilweise | Netzwerk-MITM | Host-Key-Verifikation schützt gegen MITM |
| Remote-Host | Nein | Remote-Prozesse, Remote-Benutzer | Kompromittierter Server kontrolliert Terminal-Ausgabe |
| Terminal-Emulation | Nein | Escape-Sequenzen, OSC-Commands | SwiftTerm muss sicher konfiguriert sein |
| Dependencies | Teilweise | Supply-Chain-Angriffe | SwiftNIO-SSH, SwiftTerm |
| Git-Repository | Nein | Offenlegung von Konfiguration | Keine Secrets im Repo |

### Angriffsvektoren (priorisiert)

1. Fail-open an der SSH-Transportgrenze: Ein fehlender Pin oder Store-Fehler wird im tatsächlichen SSH-Delegate akzeptiert, obwohl der normale UI-Flow vorher TOFU ausführt.
2. Kompromittierter Remote-Host: Terminal-Ausgabe kann Befehle, OSC-Escapes oder URL-Schemes enthalten.
3. OSC-52-Clipboard-Schreibzugriff: Ein Remote-Server kann die iOS-Systemzwischenablage überschreiben.
4. App-Lifecycle-Datenexposition: Terminal-Inhalte bleiben beim Wechsel in den Hintergrund sichtbar.
5. Unbegrenzte Terminal-Ausgabe: Ein Remote-Server kann den Speicher durch unlimitierte Ausgabe erschöpfen.
6. Metadaten in Produktions-Logs: Dynamische Verbindungs- und Discovery-Daten gelangen in die Konsole.
7. Unquotierte Startbefehle: Session-Namen können Shell-Metazeichen enthalten.
8. Beliebige URL-Schemes: Terminal-Links können nach einem Benutzer-Tap fremde Schemes öffnen.
9. Supply Chain: Kompromittierte oder verwundbare SPM-Abhängigkeiten.

---

## 4. Befundtabelle

| ID | Schwere | Touchpoint | Voraussetzungen | Auswirkung | Phase |
|---|---|---|---|---|---|
| SEC-01 | High | `SSHClient.swift`, `VerifyingHostKeyDelegate.validateHostKey` | Direkte oder interne Nutzung von `SwiftNIOSSHClient` ohne Preflight; fehlender Pin durch einen State- oder Lifecycle-Defekt; `KnownHostStore`-Lesefehler zwischen Policy und Transport | Die Transportgrenze arbeitet fail-open. Der normale UI-Flow führt vorher TOFU aus und persistiert das Vertrauen synchron. Kein Bypass des normalen Flows und kein Race sind nachgewiesen. | 1 |
| SEC-02 | Low | `HostKeyTrustEvaluator.swift`, Resolver und Capture-Delegate; `HostKeyTrustEvaluator.evaluate`; `HostKeyChallenge` | Der lokale Review von NIOSSH 0.14.1 bestätigt: Host-Key-Validierung und Channel-Close erfolgen vor User-Auth. Eine Passwortübertragung ist nicht nachgewiesen. | Das Passwort durchläuft mehr Schichten als nötig. Defense-in-Depth-Verbesserung, kein nachgewiesener Exploit. | 1 |
| SEC-03 | High | `SSHTerminalView.swift` `clipboardCopy`, `clipboardRead` | Kompromittierter Remote-SSH-Server sendet OSC 52 Escape-Sequenz | Cross-App Clipboard Poisoning. Schreibender Zugriff nur, kein Lesen/Diebstahl. `clipboardRead` gibt bereits nil. | 2 |
| SEC-04 | Medium | `AppShellView.swift`, `PlainTerminalView.swift` scenePhase handler, `AppLockViewModel` | App im Vordergrund mit aktiver SSH-Session, Benutzer wechselt ab oder sperrt Device | Sensitive Terminal-Ausgaben auf Lock Screen oder im App-Switcher sichtbar. | 4 |
| SEC-05 | Medium | `SSHClient.swift`, `ExecCommandHandler` | Remote-Befehl mit extrem viel stdout/stderr oder hängender Befehl ohne Exit-Status | Speicherdruck, OOM-Crash der App oder hängende Verbindung. | 3 |
| SEC-06 | Medium | `SSHClient.swift`, `HostKeyTrustEvaluator.swift`, Provider-Dateien, `HostListViewModel.swift` | App mit aktivem Logging | Exposition von Metadaten wie Host, Benutzername, Fingerprint und roher Discovery-Ausgabe. Aktuell wird kein Passwort mit `print()` ausgegeben. | 3 |
| SEC-07 | Medium | `TerminalSession.swift`, `PlainTerminalViewModel.swift` | Remote-User erstellt tmux/herdr-Session mit Shell-Meta-Zeichen im Namen | Potenzielle Command Injection beim Startup-Command. Kompromittierter Server kontrolliert bereits Ausgabe. | 2 |
| SEC-08 | Low | `SSHTerminalView.swift` `requestOpenLink` | Remote-Server sendet ANSI-Link-Escape mit nicht-https URL; Benutzer tippt auf Link | Öffnen unerwünschter Apps oder URL-Schemes nach User-Interaktion. SwiftTerm erfordert User-Tap. | 2 |
| SEC-09 | Low | `SSHClient.swift` `AcceptAllHostKeysDelegate` | Zukünftiges Refactoring aktiviert toten Code versehentlich | Alle Host-Keys akzeptiert. Nicht im aktuellen Code aktiv. | 1 |
| SEC-10 | Low | Repository-Wurzel | Repository wird öffentlich gemacht | Kein öffentlicher Sicherheitsberichtsweg, keine CI-Pipeline, keine Dependency-Automation. | 6 |
| SEC-11 | Low | `TerminalConnectionState.swift` `TerminalConnectionRequest.password` | Memory-Inspection während aktiver Session | Passwort im RAM während Session. Nie persistent gespeichert oder geloggt. Architekturelle Anmerkung. | Dokumentation |

---

## 5. Phasen-Plan

### Phase 0: Freeze, Baseline und Security-Regression-Fixtures

**Ziel:** Bestehenden Stand einfrieren und Security-Regressionstests erstellen.

**Berührungspunkte:**

- `TetherTTYTests/HostKeySecurityFixturesTests.swift` — Neu
- `TetherTTYTests/TerminalSecurityFixturesTests.swift` — Neu
- `TetherTTYTests/LifecycleSecurityFixturesTests.swift` — Neu

**Designentscheidungen:**

1. Sicherstellen, dass alle bestehenden Tests auch nach Phase 1 bis 6 noch bestehen (Baseline-Commit).
2. Test-Fixture `HostKeySecurityFixturesTests.swift`: Fail-closed bei unbekanntem Host, Fail-closed bei Known-Host-Store-Lesefehler, Compilation-Test dass `HostKeyFingerprintResolver` kein Password-Parameter hat.
3. Test-Fixture `TerminalSecurityFixturesTests.swift`: OSC 52 Blockierung (Mock-basiert: `clipboardCopy` ist No-Op), URL-Scheme Allowlist, Unbounded-Output-Limit.
4. Test-Fixture `LifecycleSecurityFixturesTests.swift`: Privacy-Cover bei Inactive- und Background-Phase, Lock bei Background-Rückkehr.

**Tests:**

- Neue Unit-Tests für jede Security-Property
- Alle bestehenden Tests müssen weiterhin bestanden werden

**Akzeptanzkriterien:**

- Alle bestehenden Tests bestanden.
- Mindestens 8 neue Security-Regressionstests existieren.
- Baseline-Commit ist getrennt von allen Security-Fixes.

**Abhängigkeiten:** Keine.

---

### Phase 1: SSH-Vertrauensgrenze

**Ziel:** SSH-Host-Key-Verifikation fail-closed machen, den Passwortfluss aus der Host-Key-Pipeline entfernen und toten Code löschen.

**Berührungspunkte:**

- `SSHClient.swift` — `VerifyingHostKeyDelegate.validateHostKey`, `AcceptAllHostKeysDelegate`, `ExecCommandHandler`
- `HostKeyTrustEvaluator.swift` — resolver/capture delegate
- `KnownHostStore.swift`
- `KnownHost.swift`
- `TerminalConnectionState.swift`
- `HostListViewModel.swift`
- `TetherTTYTests/HostKeyTrustEvaluatorTests.swift`
- `TetherTTYTests/AppFlowIntegrationTests.swift`

**Designentscheidungen:**

1. **`VerifyingHostKeyDelegate` fail-closed machen (SEC-01):** Bei fehlendem Known-Host-Eintrag: `validationCompletePromise.fail()` mit `SSHClientError.hostKeyUnknown`. Bei Store-Fehler: `validationCompletePromise.fail()` mit `SSHClientError.hostKeyStoreError`. Nur bei explizitem Match: `succeed(())`. TOFU-UX wird durch höheren Layer (`HostListViewModel` + `HostKeyTrustEvaluator`) aufrechterhalten: Preflight-Connect erkennt unbekannten Host und präsentiert Fingerprint zur expliziten Bestätigung.

2. **`AcceptAllHostKeysDelegate` entfernen (SEC-09):** Löschung des toten Codes. Compilation-Test in Regression-Fixtures.

3. **Passwort aus der Host-Key-Pipeline entfernen (SEC-02):** `HostKeyFingerprintResolver` erhält kein Passwort mehr. `HostKeyTrustEvaluator.evaluate()` benötigt für die Fingerprint-Ermittlung ebenfalls kein Passwort. `HostKeyChallenge` enthält kein Passwortfeld mehr. `HostListViewModel` lädt das Passwort nach der Trust-Bestätigung erneut aus dem Keychain.

4. **`CaptureOnlyUserAuthDelegate` einführen:** Der Capture-Flow verwendet einen User-Auth-Delegate, der bei unerwartetem Aufruf fehlschlägt oder kein Auth-Angebot zurückgibt. Er empfängt nur den Host-Key und schließt die Verbindung anschließend. Die Fingerprint-Erfassung erhält eine klar definierte Connect- und Handshake-Deadline zwischen 8 und 15 Sekunden sowie garantiertes Cleanup.

5. **Deadlines und Channel-Ownership festlegen:** `SwiftNIOSSHClient.openShell()` erhält eine Setup- und Connect-Deadline von 15 Sekunden. Bei Setup-Fehler oder Cancellation werden Parent- und Child-Channel geschlossen. Bei Erfolg geht das Channel-Ownership an die zurückgegebene `SSHSession`; deshalb darf der erfolgreiche Pfad kein pauschales `defer close` verwenden. Fingerprint- und Exec-Flows garantieren Cleanup. Interaktive Shells erhalten keinen Lifetime-Timeout.

**Tests:**

- `testUnknownHostFailsClosed` — Neuer Host muss fail-closed sein (auf Delegate-Ebene).
- `testStoreErrorFailsClosed` — Store-Fehler muss fail-closed sein.
- `testKnownHostMatchSucceeds` — Bekannter Host mit Match funktioniert.
- `testKnownHostMismatchFails` — Mismatch wird erkannt.
- `testFingerprintResolverNoPassword` — Interface-Änderung getestet.
- `testHostKeyCaptureWithoutPasswordAuth` — Preflight erhält Key ohne Auth.
- `testConnectTimeout` — Timeout wird ausgelöst.
- `testGuaranteedClose` — Connection wird nach Timeout geschlossen.
- `testAcceptAllHostKeysDelegateRemoved` — Compilation-Test.
- AppFlow-Integrationstests aktualisieren (kein Passwort in der Challenge).

**Akzeptanzkriterien:**

- `VerifyingHostKeyDelegate` failt bei unbekanntem Host oder Store-Fehler.
- `AcceptAllHostKeysDelegate` existiert nicht mehr.
- `HostKeyFingerprintResolver` hat keinen Passwortparameter.
- `HostKeyChallenge` hat kein Passwortfeld.
- Der Preflight-Connect erhält den Host-Key ohne Passwort-Authentifizierung.
- Connect-Timeout funktioniert (getestet).
- Alle bestehenden Tests bestanden.
- TOFU-UX bleibt erhalten: Benutzer sieht Fingerprint und muss bestätigen.

**Abhängigkeiten:** Phase 0.

---

### Phase 2: Terminal-Grenze

**Ziel:** OSC 52 blockieren, URL-Scheme Allowlist einführen, Startup-Commands sicher quoten.

**Berührungspunkte:**

- `SSHTerminalView.swift` — `clipboardCopy`, `requestOpenLink`
- `TerminalSession.swift`
- `PlainTerminalViewModel.swift`

**Designentscheidungen:**

1. **OSC 52 blockieren (SEC-03):** `SSHTerminalView.clipboardCopy(source:content:)` wird zu einem No-Op: keine Operation und kein Zugriff auf `UIPasteboard`. Es besteht keine Abhängigkeit von SwiftTerm-Feature-Flags. `clipboardRead` gibt weiterhin `nil` zurück. Der Test erfolgt über SwiftTerm-Escape-Verarbeitung oder einen direkten Delegate-Aufruf.

2. **URL-Scheme Allowlist (SEC-08):** `requestOpenLink(source:params:)`: Nur `https://` erlauben. Alle anderen Schemes verwerfen (inklusive `http://`). SwiftTerm erfordert einen User-Tap — keine automatischen Öffnungen. Optionaler Bestätigungs-Dialog vor Öffnen von https-URLs als Should-Item.

3. **Typed `TerminalStartupAction` (SEC-07):** Neuen Typ `TerminalStartupAction` einführen statt beliebiger String-Commands. Rendering nur am finalen SSH-Grenze (nach `terminalOpen`, vor erster Interaktion). Raw-Namen-Länge validieren und NUL (`\0`), CR (`\r`), LF (`\n`) vor dem Rendering verwerfen. POSIX Single-Argument Quoting: `'` wird zu `'\''` escaped, umgeben von einfachen Hochkommata. Kein Längenlimit nach dem Quoting. Längenlimit vor dem Quoting auf Raw-Namen anwenden. Dokumentieren: vollständig kompromittierter Server kontrolliert bereits Ausgabe. Relevante Grenze ist lower-trust/malformed Discovery-Ausgabe.

**Tests:**

- `testClipboardCopyIsNoOp` — `clipboardCopy` führt keine Operation aus.
- `testOnlyHttpsUrlsOpened` — Nur HTTPS-URLs werden geöffnet.
- `testHttpUrlsRejected` — http-URLs werden verworfen.
- `testArbitrarySchemeRejected` — `file://` und andere Schemes werden verworfen.
- `testStartupCommandQuoting` — Session-Name mit Sonderzeichen wird korrekt gequotet.
- `testStartupCommandRejectsNulCrLf` — NUL, CR, LF werden verworfen.

**Akzeptanzkriterien:**

- `clipboardCopy` ist ein No-Op.
- Nur `https://`-URLs werden nach einem Benutzer-Tap geöffnet.
- Alle anderen URL-Schemes werden verworfen.
- Startup-Commands verwenden typed `TerminalStartupAction` mit POSIX-Quoting.
- NUL/CR/LF werden verworfen.

**Abhängigkeiten:** Keine.

---

### Phase 3: Ressourcen und Logging

**Ziel:** Begrenzte Ausgabe, Operation-Timeouts, print()-Logs ersetzen.

**Berührungspunkte:**

- `SSHClient.swift` — `ExecCommandHandler`
- `TmuxSessionProvider.swift`
- `HerdrSessionProvider.swift`
- `HostKeyTrustEvaluator.swift`

**Designentscheidungen:**

1. **Kombiniertes stdout+stderr-Limit (SEC-05):** `ExecCommandHandler` erhält ein konfigurierbares kombiniertes Limit von 1 MiB (1.048.576 Bytes) für stdout und stderr. Bei Überschreitung wird die Operation mit `SSHClientError.outputLimitExceeded` genau einmal abgeschlossen und der Channel sofort geschlossen. Die Verbindung darf nicht weiterlaufen. Das Limit gilt für die festen Session-Discovery-Befehle.

2. **Exec-Deadline (SEC-05):** `execute()` erhält ein Gesamt-Timeout von 15 Sekunden. `openShell()` behält nur Setup- und Connect-Deadlines; interaktive Shells erhalten keinen Lifetime-Timeout. Bei erfolgreichem `openShell()` geht das Channel-Ownership an die zurückgegebene Session. Bei Setup-Fehler oder Cancellation wird geschlossen. Fingerprint- und Exec-Flows garantieren Cleanup. Die Exactly-once-Completion bleibt auf dem Channel-Event-Loop, und die Deadline wird bei jeder Completion abbestellt.

3. **`print()`-Logs ersetzen (SEC-06):** Rohe und dynamische Logs entfernen, insbesondere Hostnamen, Benutzernamen, OpenSSH-Key-Strings, Discovery-Ausgaben und stderr. Aktuell wird kein Passwort mit `print()` ausgegeben. Öffentliche Keys und Fingerprints sind keine Secrets, aber schützenswerte Metadaten. Falls reine Ereignisdiagnostik erhalten bleibt, wird `Logger` ohne Host-, Benutzer-, Key-, Output- oder Command-Werte und mit `#if DEBUG` verwendet. `Logger` ist in Release nicht automatisch deaktiviert.

**Tests:**

- `testExecOutputLimitCombined` — Kombiniertes Limit wird erzwungen.
- `testExecCommandTimeout` — Timeout wird ausgelöst.
- `testTimeoutClosesChannel` — Timeout schliesst Channel.
- `testExactlyOnceCompletion` — Completion passiert genau einmal.
- `testNoPrintStatements` — Keine `print()`-Statements im Produktionscode (statisch).

**Akzeptanzkriterien:**

- stdout+stderr kombiniert begrenzt auf 1 MiB.
- Exec-Timeout: 15 Sekunden.
- OpenShell Setup/Connect-Timeout: 15 Sekunden.
- Kein Lifetime-Timeout auf interaktive Shells.
- Exactly-once completion garantiert.
- Keine `print()`-Statements im Produktionscode.
- Verbleibender `Logger` verwendet passende Log-Level und ein DEBUG-Gate.

**Abhängigkeiten:** Phase 0.

---

### Phase 4: Lifecycle und Data Exposure

**Ziel:** Einen zentralen `scenePhase`-Handler in `AppShellView` einführen, bei `.inactive` sofort Inhalte abdecken, bei `.background` sperren und die SSH-Disconnect-Policy festlegen.

**Berührungspunkte:**

- `AppShellView.swift`
- `PlainTerminalView.swift` — scenePhase handler
- `AppLockViewModel.swift`
- `PlainTerminalViewModel.swift`

**Designentscheidungen:**

1. **Root-Level-Privacy-Abdeckung:** `AppShellView` erhält `@Environment(\.scenePhase)`. `.background` und `.inactive` aktivieren synchron ein Privacy-Cover. Damit ist die gesamte App abgedeckt, bevor asynchrone Cleanup-Arbeit beginnt.

2. **`AppLockViewModel.lock()` Methode:** Neue Methode `func lock()` einführen (setzt `lockState = .locked`). Nicht direkt auf `lockState` mutieren (ist `private(set)`).

3. **Lock und Disconnect bei Background:** Bei `.background` wird `lockViewModel.lock()` aufgerufen und die SSH-Session getrennt. Bei `.inactive` wird nur das Privacy-Cover angezeigt; ein transienter Inactive-Zustand erzwingt allein noch keine erneute Authentifizierung.

4. **Authentifizierung bei Rückkehr aus Background:** Ein Reconnect darf erst nach erfolgreichem Unlock neu erzeugt werden. Der Root-Flow entfernt oder pausiert den Terminal-Flow beim Sperren und verhindert dadurch Child-Auto-Reattach. `AppLockViewModel` wird nicht in `PlainTerminalViewModel` injiziert.

5. **Disconnect-Eigentum:** Root-View-Teardown oder `onDisappear` von `PlainTerminalView` besitzt den Disconnect. Kleines Session-Lifecycle-Coordinator-Objekt als Alternative. Privacy-Cover ist synchron und sofort, Disconnect ist async und kann verzögert erfolgen. Privacy-Cover muss vor async disconnect passieren.

6. **Grace-Period-Auto-Reconnect für Background entfernen:** Die Security-Policy überschreibt den bisherigen automatischen Background-Reconnect. Ein Reconnect nach Background erfolgt nur nach erneuter Authentifizierung.

**Tests:**

- `testBackgroundTriggersLock` — Background setzt Lock.
- `testInactiveTriggersPrivacyCover` — Inactive zeigt Privacy-Cover.
- `testPrivacyCoverOnBackground` — Privacy-Cover sichtbar bei Background.
- `testReconnectRequiresAuth` — Reconnect nach Lock erfordert Auth.
- `testReconnectCannotBypassLock` — Reconnect während gelockt wird blockiert.
- `testDisconnectOnDisappear` — Disconnect wird bei View-Ausblendung aufgerufen.

**Akzeptanzkriterien:**

- `AppShellView` zentral scenePhase verarbeitet.
- `AppLockViewModel.lock()` Methode existiert.
- Privacy-Cover bei `.inactive` und `.background` (synchron).
- Lock und Disconnect bei `.background`.
- Transientes `.inactive` nur Cover, kein Re-Auth erzwungen.
- Reconnect erfordert Auth nach Background.
- `AppLockViewModel` nicht in `PlainTerminalViewModel` injiziert.
- Grace-period auto-reconnect für Background entfernt.
- Privacy-Cover vor async disconnect.

**Abhängigkeiten:** Phase 0.

---

### Phase 5: Input- und Data-Hardening

**Ziel:** Host/Username/Alias-Validierung, normalisierte Host-Identität, Known-Hosts-Cleanup bei Endpoint-Edit.

**Berührungspunkte:**

- `ConnectionEditorView.swift`
- `HostListViewModel.swift`
- `ConnectionRepository.swift`
- `KnownHostStore.swift`
- `Connection.swift`

**Designentscheidungen:**

1. **Host-, Benutzername- und Alias-Validierung:** `ConnectionDraft.isValid` erweitern: Host maximal 253 Zeichen, Benutzername maximal 256 Zeichen und Alias maximal 100 Zeichen. Alle Control Characters einschließlich CR, LF, Tab und NUL ablehnen. Führende und nachfolgende Whitespaces trimmen und reine Whitespace-Eingaben ablehnen. Scheme-Präfixe wie `ssh://` oder `http://` ablehnen. DNS-Namen bezüglich Groß- und Kleinschreibung sowie optionalem abschließendem Punkt konsistent normalisieren. IPv4 und IPv6 praktisch unterstützen, ohne pauschale ASCII-only-Regel.

2. **Endpoint Pin Cleanup:** Wenn sich Host oder Port einer Connection ändert: Alten Known-Host-Eintrag entfernen. Ort: `HostListViewModel` oder dediziertes Cleanup-Service. NICHT in `ConnectionRepository`. `ConnectionRepository` bleibt entkoppelt von `KnownHostStore`.

3. **UserDefaults-Metadata:** UserDefaults-Metadaten (Connection-Liste, Known-Hosts) sind unter iOS-Sandbox und Data Protection akzeptabel. Verschlüsselung ist optional, keine erforderliche Schwachstelle. Known-Hosts-Fingerprints sind öffentliche Informationen, keine Secrets.

**Tests:**

- `testHostLengthValidation` — Max-Länge wird erzwungen.
- `testControlCharacterRejection` — Control Characters werden abgelehnt.
- `testUsernameLengthValidation` — Max-Länge wird erzwungen.
- `testAliasLengthValidation` — Max-Länge wird erzwungen.
- `testProtocolPrefixRejection` — `ssh://` und andere Prefixe werden verworfen.
- `testWhitespaceOnlyRejected` — Whitespace-only wird verworfen.
- `testKnownHostRemovedOnHostChange` — Alter Known-Host wird entfernt (in HostListViewModel).
- `testIPv6Normalization` — IPv6-Adressen werden korrekt normalisiert.

**Akzeptanzkriterien:**

- Host/Username/Alias werden validiert.
- Control Characters und reine Whitespace-Eingaben werden abgelehnt.
- Scheme-Präfixe werden abgelehnt.
- Known-Hosts werden bei Host/Port-Change bereinigt (in HostListViewModel).
- `ConnectionRepository` bleibt entkoppelt von `KnownHostStore`.
- IPv4/IPv6/DNS werden korrekt behandelt.

**Abhängigkeiten:** Keine.

---

### Phase 6: Open-Source und Release Operations

**Ziel:** SECURITY.md, CI-Pipeline, Dependency-Automation, Release-Checkliste, Privacy-Compliance.

**Berührungspunkte (neu erstellt):**

- `SECURITY.md`
- `.github/workflows/build-test.yml`
- `CONTRIBUTING.md` (empfohlen, nicht blockierend)
- `CODE_OF_CONDUCT.md` (empfohlen, nicht blockierend)
- `PrivacyInfo.xcprivacy`
- `NOTICE` (falls nötig)
- `README.md` (aktualisieren)

**Designentscheidungen:**

1. **`SECURITY.md`, private Berichterstattung:** GitHub Security Advisory beziehungsweise Private Vulnerability Reporting als primären Berichtsweg verwenden. Der Maintainer muss vor Veröffentlichung einen gültigen Backup-Kontakt festlegen. Keine erfundenen E-Mail-Adressen, Domains oder Response-SLAs.

2. **GitHub Actions, macOS Build/Test:** Workflow auf `push` und `pull_request`. Der Job baut und testet mit einer festgelegten Xcode-Version. Das Simulatorziel wird passend zum installierten Runner-Runtime gewählt. SPM-Caching darf keine Korrektheit oder Pinning umgehen.

3. **Dependency-Update-Automation:** Dependabot für SPM-Abhängigkeiten aktivieren, sofern für das Repository unterstützt; andernfalls Renovate oder geplante Advisory-Checks verwenden. NIOSSH- und SwiftTerm-Advisories regelmäßig prüfen.

4. **Secrets-Scanning, Full History:** gitleaks oder trufflehog nach Installation lokal und in CI verwenden. Die vollständige Git-Historie scannen. Ein Pre-commit-Hook ist optional.

5. **Branch Protection:** `main` branch: Required status checks (build + test). Pull Request reviews required (mindestens 1). No force push.

6. **License und NOTICE-Review:** Apache 2.0 License vorhanden. SPM-Dependency-Lizenzen prüfen. NOTICE-Datei mit Third-Party-Lizenzen erstellen. SBOM-Artifact generieren (optional).

7. **`PrivacyInfo.xcprivacy`, App-Store-Compliance:** Required-Reason-API-Deklarationen sind von Privacy Nutrition Labels getrennt. Das Archive und die API-Reports der Abhängigkeiten prüfen. Nur tatsächlich verwendete API-Kategorien mit aktuellen, von Apple akzeptierten Reason Codes deklarieren; keine Codes raten. Lokal gespeicherte Hostnamen und Benutzernamen gelten nicht automatisch als gesammelt, solange sie das Gerät nicht verlassen.

8. **README aktualisieren:** Security-Beschreibung um Threat Model, bekannte Grenzen, Link auf `SECURITY.md` und den Status dieses Plans ergänzen. Behauptungen zum automatischen Reconnect an die neue Lock-Policy anpassen.

**Tests:**

- CI-Workflow muss erfolgreich durchlaufen.
- gitleaks scan muss keine Secrets melden.
- Die gewählte Dependency-Automation muss Updates erzeugen können.

**Akzeptanzkriterien:**

- `SECURITY.md` vorhanden, GitHub PVR als primärer Weg, Maintainer hat einen gültigen Backup-Kontakt gewählt.
- GitHub Actions Build/Test Pipeline funktioniert.
- Dependabot (oder Ersatz) aktiviert.
- Branch Protection rules konfiguriert.
- `PrivacyInfo.xcprivacy` vorhanden, Dependencies inspiziert, nur tatsaechlich verwendete APIs deklariert.
- README aktualisiert.

**Abhängigkeiten:** Phase 0.

---

## 6. Priorisierter Backlog

### Muss vor jedem Release

| ID | Titel | Größe | Phase |
|---|---|---|---|
| SEC-01 | Fail-Closed Host-Key Verification | S | 1 |
| SEC-09 | Dead AcceptAllHostKeysDelegate entfernen | S | 1 |

### Muss vor öffentlichem App-Release

| ID | Titel | Größe | Phase |
|---|---|---|---|
| SEC-02 | Password aus Host-Key-Pipeline entfernen | L | 1 |
| SEC-03 | OSC 52 Clipboard Poisoning blockieren | S | 2 |
| SEC-04 | Privacy Cover und Lock im Lifecycle | L | 4 |
| SEC-05 | Exec Resource Control implementieren | L | 3 |

### Sollte vor öffentlichem App-Release

| ID | Titel | Größe | Phase |
|---|---|---|---|
| SEC-06 | Production Print-Logs ersetzen | L | 3 |
| SEC-07 | Typed `TerminalStartupAction` einführen | L | 2 |
| SEC-08 | URL-Scheme-Allowlist einführen | S | 2 |
| SEC-10 | SECURITY.md, CI, Dependency Automation | L | 6 |
| SEC-11 | In-Memory Password dokumentieren | S | Dokumentation |
| Input Validation | Host/Username/Alias/IPv6 Validierung | L | 5 |

### Größeneinschätzung

- **S (Small):** Umfang ähnlich wie ein bis zwei fokussierte Änderungen mit Tests.
- **M (Medium):** Umfang ähnlich wie drei bis fünf zusammenhängende Änderungen mit Tests.
- **L (Large):** Umfang ähnlich wie eine ganze Phase über mehrere Dateien und Testebenen.

Keine Kalenderschätzungen, nur relative Komplexität.

---

## 7. Release-Gates

### Gate 1: Repository öffentlich (Open Source)

- [ ] `SECURITY.md` vorhanden mit GitHub PVR (SEC-10).
- [ ] Gültiger Backup-Kontakt für Security Reports festgelegt.
- [ ] Autoritativer Full-History-Secrets-Scan mit gitleaks oder trufflehog bestanden.
- [ ] Keine Signierungsdateien, Provisioning Profiles, privaten Schlüssel oder persönlichen Xcode-Dateien getrackt.
- [ ] Lizenz und Third-Party-Notices geprüft.
- [ ] README kennzeichnet Reifegrad, Threat Model und bekannte Risiken korrekt.
- [ ] Entscheidung dokumentiert, ob ungepatchte Details in dieser Datei öffentlich bleiben, vorab behoben oder in ein privates Advisory verschoben werden.
- [ ] CI und Branch Protection aktiviert, sofern als Projekt-Richtlinie festgelegt.

**Policy:** Runtime-Befunde blockieren die Veröffentlichung des Quellcodes technisch nicht. SEC-01 und SEC-03 sollten dennoch möglichst vor der Veröffentlichung der detaillierten Befunde behoben werden. Eine bewusste Abweichung benötigt Besitzer, Begründung und Überprüfungsdatum.

### Gate 2: Öffentliche App / App Store

- [ ] Alle High-Befunde (SEC-01, SEC-03) implementiert und getestet.
- [ ] Alle Medium-Befunde (SEC-04, SEC-05, SEC-06, SEC-07) implementiert und getestet.
- [ ] Alle Low-Befunde behoben oder als dokumentierte Restrisiken akzeptiert.
- [ ] Alle Tests frisch bestanden, einschließlich der aktuell 49 deklarierten XCTest-Methoden und neuer Security-Tests.
- [ ] Release-Build auf Simulator und physischem Gerät erfolgreich.
- [ ] Physisches Device: Background- und App-Switcher-Test bestanden.
- [ ] OSC 52 manueller Regressionstest bestanden.
- [ ] Host-Key-Integrationstest bestanden.
- [ ] `PrivacyInfo.xcprivacy` vorhanden, Abhängigkeiten inspiziert und nur tatsächlich verwendete API-Kategorien deklariert.
- [ ] App-Store-Privacy-Labels entsprechen dem tatsächlich geprüften Datenfluss.
- [ ] README Threat-Model und Security Claims korrekt und aktuell.
- [ ] Keine ungelösten High- oder Medium-Befunde oder explizite, unterzeichnete Risikoakzeptanz mit Besitzer, Begründung, Ablaufdatum und Überprüfungsdatum.

**Policy:** Keine ungelösten High- oder Medium-Befunde vor App-Store-Release ohne formale Risikoakzeptanz. Ungelöste Low-Befunde müssen behoben oder als dokumentierte Restrisiken akzeptiert werden.

---

## 8. Verifikationsmatrix und Befehle

### Test-Matrix

| Control | Unit-Test | Integration-Test | Manueller Test | Statisch / CI |
|---|---|---|---|---|
| SEC-01: Fail-Closed Host-Key | Ja | Ja | Nein | Ja |
| SEC-02: No Password in HostKey Pipeline | Ja (Compilation) | Nein | Nein | Ja |
| SEC-03: OSC 52 Blockierung (No-Op) | Ja (Mock) | Ja | Ja | Teilweise |
| SEC-04: Privacy-Cover | Ja (ViewModel) | Ja | Ja | Nein |
| SEC-05: Bounded Output / Timeout | Ja | Ja | Nein | Ja |
| SEC-06: No Print Logs | Nein | Nein | Nein | Ja |
| SEC-07: Quoted Commands | Ja | Nein | Nein | Ja |
| SEC-08: URL Scheme Allowlist | Ja | Ja | Ja | Ja |
| SEC-09: Dead Code Removed | Nein | Nein | Nein | Ja |
| SEC-10: CI / SECURITY.md | Nein | Nein | Nein | Ja |
| Lifecycle: Lock on Background | Ja | Ja | Ja | Nein |
| Lifecycle: Reconnect Requires Auth | Ja | Ja | Ja | Nein |
| Input Validation (Phase 5) | Ja | Nein | Ja | Nein |

### Befehle zur Verifikation

```bash
# Alle Tests ausführen
xcodebuild test -project TetherTTY.xcodeproj -scheme TetherTTY \
  -destination 'platform=iOS Simulator,name=iPhone 17'

# Release Build (generic Simulator)
xcodebuild build -project TetherTTY.xcodeproj -scheme TetherTTY \
  -configuration Release \
  -destination 'generic/platform=iOS Simulator'

# Print-Statements Check (erfordert: rg installiert)
rg -n 'print\(' TetherTTY/ --type swift

# Dead Code Check (erfordert: rg installiert)
rg 'AcceptAllHostKeysDelegate' TetherTTY/ --type swift

# Full-History Secrets-Scan (erfordert: gitleaks Installation)
gitleaks detect --source . --report-format json --report-path gitleaks-report-full-history.json --log-opts '--all'

# Alternativ mit trufflehog (erfordert: trufflehog Installation)
trufflehog git --fail --no-update
```

---

## 9. Rollout, Rollback, Restrisiken und Definition of Done

### Rollout-Strategie

1. **Baseline-Commit:** Alle bestehenden Tests bestanden — Commit als `chore: baseline before security remediation`.
2. **Phase 0:** Regression-Fixtures erstellen — Commit als `test: add security regression fixtures`.
3. **Phase 1:** SSH-Trust-Boundary — Commit als `fix(ssh): make host-key verification fail-closed, remove AcceptAll, remove password from host-key pipeline`.
4. **Phase 2:** Terminal-Boundary — Commit als `fix(terminal): make clipboardCopy no-op, deny OSC 52, restrict URL schemes to https-only, introduce typed TerminalStartupAction`.
5. **Phase 3:** Ressourcen und Logging — Commit als `fix(resources): bound exec output to 1MiB, add operation timeout, replace print with os.Logger`.
6. **Phase 4:** Lifecycle — Commit als `fix(lifecycle): central scenePhase handler, privacy cover on inactive, lock on background, require auth on reconnect`.
7. **Phase 5:** Input-Hardening — Commit als `fix(input): validate connection fields, sanitize control characters, cleanup stale known-hosts in HostListViewModel`.
8. **Phase 6:** Release Operations — Commit als `chore: add SECURITY.md, GitHub Actions CI, Dependabot, PrivacyInfo.xcprivacy, update README`.

Jede Phase wird separat committet mit klarer Beschreibung.

### Rollback-Plan

- Jede Phase wird in einem eigenen Branch entwickelt und via PR gemergt.
- Vor jedem Merge: Alle Tests bestanden.
- Bei Regression: PR revert + Hotfix in separatem Branch.
- Baseline-Commit erlaubt einfaches Revert auf den Stand vor Phase 1.

### Restrisiken

| Risiko | Schwere | Gegenmassnahme |
|---|---|---|
| TOFU-MITM beim ersten Kontakt bleibt ohne Out-of-Band-Verifikation möglich | Hoch | Fingerprint anzeigen und explizit bestätigen lassen. Langfristig manuelle Fingerprint-Eingabe oder QR-Code-Verifikation anbieten. |
| Kompromittierter Server kontrolliert Terminal-Ausgabe | Hoch | Nicht vollständig vermeidbar. Terminal-Ausgabe bleibt nicht vertrauenswürdig; gefährliche lokale Seiteneffekte werden begrenzt. |
| iOS Data Protection und Jailbreak-Grenzen | Niedrig | Standard-iOS-Sicherheitsmodell. Jailbreak-Szenarien bleiben außerhalb des Threat Models. |
| Kein Audit beweist die Abwesenheit von Schwachstellen | Informativ | Regelmäßige Re-Audits, Dependency-Checks und Security-Regressionstests einplanen. |
| Supply-Chain-Angriff auf SPM-Abhängigkeiten | Mittel | Gepinnte Revisionen, Update-Automation, Advisory-Review und optionales SBOM. |
| Passwort in `TerminalConnectionRequest` | Niedrig | Nur im Speicher, nicht persistent und nicht geloggt. Optional später durch kurzlebigen Credential-Handle oder Provider ersetzen. |

### Definition of Done

#### Global

- [ ] Alle High-Befunde (SEC-01, SEC-03) behoben und getestet.
- [ ] Alle Medium-Befunde (SEC-04, SEC-05, SEC-06, SEC-07) behoben und getestet.
- [ ] Alle Low-Befunde behoben oder als dokumentierte Restrisiken akzeptiert.
- [ ] Alle bestehenden Tests (aktuell 49 XCTest-Methoden) frisch bestanden.
- [ ] Neue Security-Regressionstests vorhanden und bestanden.
- [ ] Release Build (Simulator und physisches Device) erfolgreich.
- [ ] `SECURITY.md` vorhanden mit GitHub PVR.
- [ ] GitHub Actions Build/Test Pipeline aktiv.
- [ ] `PrivacyInfo.xcprivacy` vorhanden, Abhängigkeiten inspiziert und nur tatsächlich verwendete API-Kategorien deklariert.
- [ ] README aktualisiert.
- [ ] Keine Secrets im Repository (Full-History Scan bestanden).
- [ ] Keine ungelösten High- oder Medium-Befunde ohne formale Risikoakzeptanz.
- [ ] Restrisiken dokumentiert.
