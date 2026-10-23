/* MaatriWatch Wokwi simulation. All physiological inputs are synthetic.
   XIAO: D4/GPIO5 SDA, D5/GPIO6 SCL, D0/GPIO1 SOS to GND.
   D1/GPIO2 is a SIMULATION-ONLY power toggle, not the physical BAT switch.
   No credentials required; no cloud data is written by this sketch.
*/
#include <Wire.h>
#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>
#include <Adafruit_MPU6050.h>
#include <Adafruit_Sensor.h>
#include <MAX30105.h>
#include <math.h>

constexpr int SDA_GPIO = 5, SCL_GPIO = 6, SOS_GPIO = 1, POWER_GPIO = 2;
constexpr int WINDOW = 200;
constexpr float SAMPLE_HZ = 25.0f;
Adafruit_SSD1306 oled(128, 64, &Wire, -1);
Adafruit_MPU6050 imu;
MAX30105 optical;
bool oledReady = false, opticalReady = false, imuReady = false;
bool powered = true, contact = false, buttonRaw = false, buttonStable = false;
bool sosForPress = false;
uint32_t buttonChangedAt = 0, buttonDownAt = 0, sosUntil = 0;
uint32_t lastDisplay = 0, lastSlowRead = 0, lastLog = 0, lastPpg = 0;
uint32_t lastEstimate = 0;
float irSamples[WINDOW], redSamples[WINDOW];
int sampleCount = 0, writeAt = 0, sinceEstimate = 0;
float bpm = NAN, spo2 = NAN, temperature = NAN, movement = NAN;

void clearPpg() {
  sampleCount = 0; writeAt = 0; sinceEstimate = 0;
  bpm = NAN; spo2 = NAN; lastEstimate = 0;
}

// Pedagogical estimator matched to the synthetic waveform. This is not the
// production firmware's oximetry algorithm or a clinically calibrated model.
void estimatePpg() {
  const int n = sampleCount;
  if (n < 125) return; // Five seconds before the first estimate.
  const int oldest = n == WINDOW ? writeAt : 0;
  double meanIr = 0, meanRed = 0;
  for (int i = 0; i < n; ++i) {
    int j = (oldest + i) % WINDOW;
    meanIr += irSamples[j]; meanRed += redSamples[j];
  }
  meanIr /= n; meanRed /= n;
  double sumIr = 0, sumRed = 0;
  for (int i = 0; i < n; ++i) {
    int j = (oldest + i) % WINDOW;
    double a = irSamples[j] - meanIr, b = redSamples[j] - meanRed;
    sumIr += a * a; sumRed += b * b;
  }
  const double rmsIr = sqrt(sumIr / n), rmsRed = sqrt(sumRed / n);
  bpm = NAN; spo2 = NAN;
  if (meanIr < 10000 || meanRed < 10000 || rmsIr / meanIr < 0.002) return;

  // Hysteresis avoids counting repeated crossings around the signal mean.
  float crossings[32]; int found = 0; bool armed = false;
  const double threshold = rmsIr * 0.25;
  for (int i = 1; i < n; ++i) {
    double previous = irSamples[(oldest + i - 1) % WINDOW] - meanIr;
    double current = irSamples[(oldest + i) % WINDOW] - meanIr;
    if (current < -threshold) armed = true;
    if (armed && previous <= 0 && current > 0 && found < 32) {
      crossings[found++] = (i - 1) + (-previous / (current - previous));
      armed = false;
    }
  }
  if (found < 4) return;
  const float period = (crossings[found - 1] - crossings[0]) / (found - 1);
  double variance = 0;
  for (int i = 1; i < found; ++i) {
    double delta = (crossings[i] - crossings[i - 1]) - period;
    variance += delta * delta;
  }
  const double cv = sqrt(variance / (found - 1)) / period;
  const float candidate = 60.0f * SAMPLE_HZ / period;
  // Small tolerance covers sample quantisation at the slider end points.
  if (candidate < 35 || candidate > 185 || cv > 0.15) return;
  bpm = candidate;
  const double ratio = (rmsRed / meanRed) / (rmsIr / meanIr);
  const double candidateSpo2 = 110.0 - 25.0 * ratio;
  if (candidateSpo2 >= 70 && candidateSpo2 <= 100.5)
    spo2 = fmin(candidateSpo2, 100.0);
  lastEstimate = millis();
}

void sampleOptical() {
  if (!opticalReady) return;
  optical.check();
  while (optical.available()) {
    uint32_t red = optical.getFIFORed(), ir = optical.getFIFOIR();
    optical.nextSample();
    lastPpg = millis();
    if (!powered) continue;
    const bool hasContact = ir >= 10000 && red >= 10000;
    if (!hasContact) {
      if (contact) Serial.println("SIM: contact lost; HR/SpO2 cleared");
      contact = false; clearPpg(); continue;
    }
    if (!contact) { clearPpg(); Serial.println("SIM: contact detected; collecting waveform"); }
    contact = true;
    irSamples[writeAt] = ir; redSamples[writeAt] = red;
    writeAt = (writeAt + 1) % WINDOW;
    if (sampleCount < WINDOW) ++sampleCount;
    if (++sinceEstimate >= 25) { sinceEstimate = 0; estimatePpg(); }
  }
  if (millis() - lastPpg > 1500) { contact = false; clearPpg(); }
  if (lastEstimate && millis() - lastEstimate > 1500) { bpm = NAN; spo2 = NAN; }
}

bool readTmp117(float &value) {
  Wire.beginTransmission(0x48); Wire.write(0x00);
  if (Wire.endTransmission(false) != 0) return false;
  if (Wire.requestFrom((uint8_t)0x48, (uint8_t)2) != 2) return false;
  const uint16_t bits = ((uint16_t)Wire.read() << 8) | Wire.read();
  value = (int16_t)bits * 0.0078125f;
  return true;
}

void sampleOtherSensors() {
  if (millis() - lastSlowRead < 250) return;
  lastSlowRead = millis();
  if (!readTmp117(temperature)) temperature = NAN;
  if (imuReady) {
    sensors_event_t a, g, t; imu.getEvent(&a, &g, &t);
    float magnitude = sqrtf(a.acceleration.x * a.acceleration.x +
                            a.acceleration.y * a.acceleration.y +
                            a.acceleration.z * a.acceleration.z) / 9.80665f;
    movement = fabsf(magnitude - 1.0f);
  }
}

void sampleControls() {
  const bool requestedPower = digitalRead(POWER_GPIO) == HIGH;
  if (requestedPower != powered) {
    powered = requestedPower; contact = false; clearPpg();
    buttonRaw = false; buttonStable = false; sosForPress = false;
    buttonChangedAt = millis(); sosUntil = 0;
    if (opticalReady) optical.clearFIFO();
    Serial.println(powered ? "SIM: watch ON" : "SIM: watch OFF");
  }
  if (!powered) return;
  bool pressed = digitalRead(SOS_GPIO) == LOW;
  if (pressed != buttonRaw) { buttonRaw = pressed; buttonChangedAt = millis(); }
  if (millis() - buttonChangedAt >= 35 && buttonStable != buttonRaw) {
    buttonStable = buttonRaw;
    if (buttonStable) { buttonDownAt = millis(); sosForPress = false; }
    else sosForPress = false;
  }
  if (buttonStable && !sosForPress && millis() - buttonDownAt >= 2000) {
    sosForPress = true; sosUntil = millis() + 5000;
    Serial.println("{\"simulation\":true,\"event\":\"sos_pressed\",\"delivery\":\"serial_only\"}");
  }
}

void drawScreen() {
  if (!oledReady || millis() - lastDisplay < 200) return;
  lastDisplay = millis(); oled.clearDisplay();
  oled.setTextColor(SSD1306_WHITE); oled.setTextSize(1);
  oled.setCursor(0, 0); oled.print("MaatriWatch SIM");
  oled.drawLine(0, 11, 127, 11, SSD1306_WHITE);
  if (!powered) { oled.setCursor(25, 30); oled.print("WATCH OFF"); oled.display(); return; }
  oled.setCursor(0, 16); oled.print("HR ");
  if (isnan(bpm)) oled.print("--"); else oled.print((int)lroundf(bpm));
  oled.print(" bpm");
  oled.setCursor(0, 29); oled.print("O2 ");
  if (isnan(spo2)) oled.print("--"); else oled.print((int)lroundf(spo2));
  oled.print(" %");
  oled.setCursor(0, 42); oled.print("Skin ");
  if (isnan(temperature)) oled.print("--"); else oled.print(temperature, 1);
  oled.print(" C");
  oled.setCursor(0, 55);
  if (sosUntil && (int32_t)(sosUntil - millis()) > 0) oled.print("SOS - simulated");
  else if (!opticalReady) oled.print("PPG sensor missing");
  else if (!contact) oled.print("Place finger");
  else if (isnan(bpm)) oled.print("Stabilising...");
  else oled.print(movement > 0.15 ? "Movement - hold still" : "Synthetic readings");
  if (!isnan(bpm) && (millis() % (uint32_t)(60000.0f / bpm)) < 220) {
    oled.fillCircle(113, 23, 3, SSD1306_WHITE);
    oled.fillCircle(119, 23, 3, SSD1306_WHITE);
    oled.fillTriangle(110, 24, 122, 24, 116, 32, SSD1306_WHITE);
  }
  oled.display();
}

void printValue(float value, int decimals) {
  if (isnan(value)) Serial.print("null"); else Serial.print(value, decimals);
}

void printTelemetry() {
  if (!powered || millis() - lastLog < 2000) return;
  lastLog = millis();
  Serial.print("{\"simulation\":true,\"uptime_ms\":"); Serial.print(millis());
  Serial.print(",\"heart_rate_bpm\":"); printValue(bpm, 1);
  Serial.print(",\"spo2_percent\":"); printValue(spo2, 1);
  Serial.print(",\"skin_adjacent_temperature_c\":"); printValue(temperature, 2);
  Serial.print(",\"contact_detected\":"); Serial.print(contact ? "true" : "false");
  Serial.print(",\"movement_g\":"); printValue(movement, 2);
  Serial.println("}");
}

void setup() {
  Serial.begin(115200);
  pinMode(SOS_GPIO, INPUT_PULLUP); pinMode(POWER_GPIO, INPUT_PULLUP);
  Wire.begin(SDA_GPIO, SCL_GPIO); Wire.setClock(100000);
  oledReady = oled.begin(SSD1306_SWITCHCAPVCC, 0x3C);
  opticalReady = optical.begin(Wire, I2C_SPEED_STANDARD, 0x57);
  // 100 raw samples/s averaged by 4 -> 25 FIFO samples/s in both the model
  // and estimator. Use red/IR mode, not the MAX30105 green channel.
  if (opticalReady) optical.setup(0x1F, 4, 2, 100, 411, 4096);
  imuReady = imu.begin(0x68, &Wire);
  powered = digitalRead(POWER_GPIO) == HIGH;
  Serial.println("MaatriWatch simulation: synthetic sensor data; no cloud writes.");
  Serial.printf("OLED=%s MAX30102=%s MPU6050=%s\n",
                oledReady ? "OK" : "missing", opticalReady ? "OK" : "missing",
                imuReady ? "OK" : "missing");
  Serial.println("Adjust custom MAX30102/TMP117 controls. Hold SOS for 2 seconds.");
}

void loop() {
  sampleControls(); sampleOptical();
  if (powered) sampleOtherSensors();
  drawScreen(); printTelemetry(); delay(2);
}
