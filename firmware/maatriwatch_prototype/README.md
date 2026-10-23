# MaatriWatch ESP32 prototype

## Wiring — ESP32 DevKit V1

All modules must share **GND**. Use 3.3 V logic/power for the sensor modules.

| ESP32 pin | Connect to | Notes |
| --- | --- | --- |
| 3V3 | MAX30102 VIN, DHT11 VCC, OLED VCC | Do not use 5 V with an unverified MAX30102/OLED breakout. |
| GND | MAX30102 GND, DHT11 GND, OLED GND | Common ground is mandatory. |
| GPIO 21 | MAX30102 SDA, OLED SDA | I²C bus shared; MAX30102 is normally `0x57`, OLED normally `0x3C`. |
| GPIO 22 | MAX30102 SCL, OLED SCL | I²C bus shared. |
| GPIO 4 | DHT11 DATA | Use a 10 kΩ pull-up to 3V3 if the DHT11 board lacks one. |
| GPIO 27 | One side of push button | Other button side to GND; firmware uses internal pull-up. |

## Power safety

**Never connect a 3.7 V LiPo directly to ESP32 `3V3`, `VIN`, or a sensor.** A
LiPo is 4.2 V when fully charged. With a TP4056-style charger/protection board,
connect battery to `B+`/`B-`; then use the protected `OUT+`/`OUT-` through:

- a regulated **5 V boost converter** to the ESP32 `VIN/5V` pin, or
- a stable **3.3 V buck-boost regulator** to the ESP32 `3V3` pin.

Power the sensors from the ESP32's regulated 3V3 output. Confirm the regulator
can supply ESP32 Wi-Fi current spikes (allow at least 500 mA). Do not charge the
cell while unattended, and use a protected LiPo.

## Flashing

1. Arduino IDE: install **ESP32 by Espressif Systems**; select the exact ESP32
   board and serial port.
2. Install the five libraries named in the sketch header.
3. Copy `secrets.example.h` to `secrets.h`; set the API endpoint, hospital-issued
   `DEVICE_ID`, `DEVICE_KEY`, and the API root CA certificate.
4. Upload. On first boot, connect a hospital phone/laptop to the
   `MaatriWatch-Setup` Wi-Fi network (using `PROVISIONING_PASSWORD`) and complete the captive portal. ESP32
   station mode is the correct internet-connected mode; SoftAP/BLE are suitable
   provisioning transports, not the clinical data channel. [Espressif Wi-Fi documentation](https://espressif-docs.readthedocs-hosted.com/projects/arduino-esp32/en/latest/api/wifi.html)
5. Put a finger gently and still over the MAX30102 for 6–10 seconds. The OLED
   first shows **finding rhythm** and then a four-second SpO₂ settling
   indicator. After it finds a clean PPG waveform, it keeps the last valid
   estimate only while finger contact remains present. Hold the button 1.2
   seconds to issue SOS.

## Reading the OLED and Serial Monitor

The OLED uses a non-blocking pulsing-heart animation and rotating calming
message; it never pauses sensor collection or uploads. It reports:

- `Pulse`: a prototype PPG pulse estimate after finger contact is detected.
- `SpO2`: a prototype ratio-of-ratios estimate after one full four-second
  window is valid. Keep the finger still while it is settling.
- A single short status prompt, only while the watch is acquiring a reading.

Ambient DHT11 temperature/humidity are sent to the dashboard, but intentionally
stay off the watch face so the screen remains readable at a glance. They are
environmental readings, never body temperature.

For hardware diagnosis, open Arduino IDE's Serial Monitor at **115200 baud**.
Every two seconds firmware prints `ir`, `red`, `contact`, `samples`, `bpm`,
`spo2`, `pi`, and DHT failure count. With a finger in place, `contact=yes`
must appear, `samples` should repeatedly climb toward 100, and then
`hrFresh=yes` should appear before `bpm` is sent to the dashboard. SpO₂ needs
one clean 100-sample window. A successful device upload prints `Telemetry
status: 201`; then use the dashboard's **Refresh** once if a live update has
not already arrived. If `ir` stays near 262143, the optical signal is
saturated: confirm the latest firmware is flashed and keep the sensor away
from bright ambient light. If `contact=no` persists, re-check MAX30102 wiring,
its 3.3 V supply, and that the sensor window is fully covered. If
`dhtFailures` keeps increasing, re-check the DHT11 data pin and its pull-up
resistor.

## Hospital lifecycle

1. Administrator registers the physical serial number and saves the one-time
   returned device secret in the hospital provisioning record.
2. Doctor/admin assigns the device to the selected patient. Only then will the
   backend accept telemetry from it.
3. Patient logs into the app. The app resolves their patient record, and shows
   the assigned device and its live readings without a separate Bluetooth pair.
4. On return, clinician resolves outstanding alerts, exports/retains records per
   policy, unassigns the watch, rotates its device key, and re-provisions it for
   the next assignment. Keep the Wi-Fi network hospital-controlled; clear stored
   Wi-Fi settings only through a supervised service/reflash procedure when a
   watch moves to a different network.

The DHT11 is intentionally shown only as **ambient** temperature/humidity. It
must not be used as body temperature. MAX30102 pulse/SpO₂ readings from this
prototype are not diagnostic or clinically validated. A single MAX30102 does
not directly measure blood pressure; the dashboard reserves BP for a validated
cuff reading. Do not derive or alert on a maternal BP value without a
patient-specific cuff-calibrated model and a completed validation study.

### Device lifecycle API

The clinician dashboard already displays assigned devices. Until the dedicated
inventory screen is added, an authenticated hospital administrator can register
a device with `POST /api/v1/hospitals/{hospitalId}/devices` and a clinician or
administrator can assign/unassign it with `PATCH
/api/v1/hospitals/{hospitalId}/devices/{deviceId}/assignment`, sending
`{"patient_id":"<uuid>"}` or `{"patient_id":null}`. The registration response
is the only time the backend returns `device_key`; record it securely before
flashing the watch. For a returned or lost watch, `POST
/api/v1/hospitals/{hospitalId}/devices/{deviceId}/rotate-key` invalidates the
old secret and returns a replacement once.
