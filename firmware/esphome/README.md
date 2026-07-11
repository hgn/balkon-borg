# firmware/esphome — ESP32-Frontplatte

ESPHome-Config für den ESP32-DevKitC auf der Trägerplatine. Liest Taster, Encoder,
LD2410B-Radar und BME280 und steuert das **WLED-Licht direkt über MQTT**.

## Pinbelegung

Folgt `../../pcb/docs/board-spec.md`: Taster GPIO13/14/27/26, Taster-LEDs
GPIO4/23/18/19, Encoder A/B/SW GPIO32/33/25, Radar-UART GPIO16(RX)/17(TX),
I²C GPIO21(SDA)/22(SCL). Die Serienwiderstände auf der Platine sind für ESPHome
transparent.

## Bedienung

| Element | Funktion |
|---|---|
| Taster 1 | Licht an/aus (WLED `T`) |
| Taster 2 | Szene „cozy" (WLED-Preset 1) |
| Taster 3 | Szene „party" (WLED-Preset 2) |
| Taster 4 | Präsenz-Automatik an/aus (LED4 zeigt Zustand) |
| Encoder drehen | Helligkeit +/- |
| Encoder drücken | Licht aus |
| Radar | bei aktiver Automatik: Präsenz schaltet Licht an, Abwesenheit (nach 2 min) aus |
| LED1 | Präsenz erkannt |

## Voraussetzungen

- **WLED** muss MQTT aktiviert haben, Device-Topic = `wled/balkon` (sonst
  `substitutions.wled_topic` anpassen). Presets 1/2 in WLED anlegen.
- **Mosquitto** auf dem NAS-Pi, Zugangsdaten in `secrets.yaml`.

## Flashen

```
cp secrets.yaml.example secrets.yaml   # und ausfüllen
esphome run balkon-borg.yaml            # erstes Mal per USB, danach OTA
```

**Wichtig:** den DevKit **vor dem Einbau** flashen (oder aus dem Sockel ziehen),
im Gehäuse ist der USB-Port schlecht erreichbar.
