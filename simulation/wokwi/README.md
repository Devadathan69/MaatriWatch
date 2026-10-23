# MaatriWatch Wokwi watch simulation

## Files to copy into Wokwi

- `sketch.ino`: simulation firmware.
- `diagram.json`: complete circuit and coloured connections.
- `libraries.txt`: library dependencies.
- `max30102.chip.c` and `max30102.chip.json`: synthetic red/IR PPG model.
- `tmp117.chip.c` and `tmp117.chip.json`: temperature-register model.

These are local project files. No Firebase passwords or existing watch secrets
are needed. This sketch prints simulated telemetry to Serial Monitor and does
not send it into the existing patient database.

## Browser setup

1. Go to https://wokwi.com and create an Arduino ESP32 project. The starter
   ESP32 board will be replaced by the XIAO through `diagram.json`.
2. Paste `sketch.ino` into the code tab.
3. In the circuit editor, click **+**, choose **Custom Chip**, name it exactly
   `max30102`, and choose **C**. Wokwi creates `.chip.c` and `.chip.json` tabs.
4. Replace those two tabs with the provided `max30102` files.
5. Repeat with a custom chip named exactly `tmp117` and paste its two files.
6. Replace the complete `diagram.json` tab with the provided diagram. This
   supplies the XIAO, OLED, MPU6050, button, switch, and both custom chips.
7. Add the six libraries from `libraries.txt` using Library Manager (or paste
   that file into a `libraries.txt` tab if your project exposes it).
8. Click **Run**. The Serial Monitor uses 115200 baud. With finger contact = 1,
   the first heart-rate estimate appears after approximately 5–6 simulated
   seconds. The default inputs are pulse 78 bpm, oxygen 98%, temperature 33.5 C.

The chip creation workflow is documented at
https://docs.wokwi.com/chips-api/getting-started .

## Connections

| XIAO | Wokwi connection |
|---|---|
| D4 / GPIO5 | SDA of OLED, MAX30102, TMP117, MPU6050 |
| D5 / GPIO6 | SCL of all four I2C devices |
| 3V3 | VCC of all four I2C devices |
| GND | GND of all four I2C devices; MPU6050 AD0 |
| D0 / GPIO1 | One SOS button terminal; other to GND |
| D1 / GPIO2 | Slide-switch centre terminal (simulation-only virtual power) |
| GND / 3V3 | Two outer terminals of the simulation slide switch |

**The D1 switch wiring is only for the simulator.** Your real watch switch
remains in series with battery positive to BAT+. Wokwi's XIAO board exposes
the main GPIO/header pins rather than a LiPo battery/charging simulation.
With the simulated switch OFF the sketch clears PPG and stops telemetry,
while the microcontroller keeps running to implement the virtual power state.

I2C addresses: OLED `0x3C`, TMP117 `0x48`, MAX30102 `0x57`, MPU6050 `0x68`.

## Presentation controls

Click the MAX30102 custom chip while the simulation is running:

- **Synthetic pulse** changes waveform frequency, 40–180 bpm.
- **Synthetic oxygen** changes the red/IR AC/DC relationship, 75–100%.
- **Finger** = 0 removes contact; OLED HR and SpO2 clear promptly.
- **Finger** = 1 restores contact and starts a new stabilisation window.
- **Optical noise** introduces deterministic waveform artifacts; sufficient
  noise can make the quality gate reject estimates.

Click TMP117 to adjust device/skin-adjacent temperature. Click MPU6050 to
adjust acceleration. Hold the red button for at least two seconds to show
an SOS and print a synthetic SOS event. Each press produces one event.

Input changes take up to one 8-second sample window to fully replace old
samples. Toggling contact off and on clears the old sample window immediately.
Displayed outputs are computed estimates and can differ slightly from the
input sliders.

## Model scope

The MAX30102 implements the identification/configuration registers, timed
red/IR samples, and a 32-entry FIFO needed for this sketch's SparkFun driver.
Only red/IR mode is modelled. TMP117 implements a signed temperature word
with 0.0078125 C/LSB, plus a basic config and ID register. These are partial
behavioural models rather than complete silicon, optical or thermal models.

The teaching sketch computes HR from hysteresis-controlled waveform crossings
and SpO2 from a simplified linear red/IR ratio that is matched to the generated
waveform. This is separate from the enclosed watch firmware and cannot validate
its real-world optical performance. The OLED is labelled SIM and every serial
telemetry event includes `simulation: true`.

No blood-pressure signal is generated because this circuit has no pressure
measurement source. The LiPo battery, charging, electrical faults, battery
life, and radio range are not validated by this simulation.

## Sources

- XIAO part/pin definition: https://github.com/wokwi/wokwi-boards/blob/main/boards/xiao-esp32-s3/board.json
- Wokwi I2C chip API: https://docs.wokwi.com/chips-api/i2c
- Wokwi chip controls: https://docs.wokwi.com/chips-api/chip-json
- SparkFun MAX3010x driver: https://github.com/sparkfun/SparkFun_MAX3010x_Sensor_Library
- TI TMP117 documentation: https://www.ti.com/product/TMP117
