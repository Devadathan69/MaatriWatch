/*
  MaatriWatch XIAO ESP32-S3 sensor diagnostic

  USB-powered bench test only. It verifies the shared I2C bus, OLED,
  MAX30102 raw optical signal, TMP117 temperature, MPU6050 motion, and SOS
  button. It deliberately does NOT calculate heart rate, SpO2, or blood
  pressure.

  XIAO ESP32-S3 wiring:
    D4 / GPIO5 -> SDA on OLED, MAX30102, TMP117, MPU6050
    D5 / GPIO6 -> SCL on OLED, MAX30102, TMP117, MPU6050
    3V3        -> VCC/VIN/3V3 on every sensor module
    GND        -> GND on every sensor module and one side of SOS button
    D1 / GPIO2 -> other side of SOS button

  Required Arduino libraries (Library Manager):
    - Adafruit GFX Library
    - Adafruit SSD1306
    - Adafruit TMP117
    - Adafruit MPU6050
    - Adafruit Unified Sensor
    - SparkFun MAX3010x Pulse and Proximity Sensor Library
*/

#include <Wire.h>
#include <Adafruit_GFX.h>
#include <Adafruit_MPU6050.h>
#include <Adafruit_SSD1306.h>
#include <Adafruit_Sensor.h>
#include <Adafruit_TMP117.h>
#include <MAX30105.h>

constexpr uint8_t I2C_SDA_PIN = 5;  // XIAO D4
constexpr uint8_t I2C_SCL_PIN = 6;  // XIAO D5
constexpr uint8_t SOS_BUTTON_PIN = 2;  // XIAO D1, wired to GND when pressed

constexpr uint8_t OLED_ADDRESS = 0x3C;
constexpr uint8_t TMP117_ADDRESS = 0x48;
constexpr uint8_t MAX30102_ADDRESS = 0x57;
constexpr uint8_t MPU6050_ADDRESS = 0x68;

constexpr uint32_t SERIAL_BAUD = 115200;
constexpr uint32_t REPORT_INTERVAL_MS = 1000;
constexpr uint32_t OLED_INTERVAL_MS = 250;

Adafruit_SSD1306 display(128, 64, &Wire, -1);
Adafruit_TMP117 tmp117;
Adafruit_MPU6050 mpu;
MAX30105 max30102;

bool oledReady = false;
bool tmpReady = false;
bool mpuReady = false;
bool maxReady = false;

float tmpC = NAN;
float accelX = NAN;
float accelY = NAN;
float accelZ = NAN;
float gyroX = NAN;
float gyroY = NAN;
float gyroZ = NAN;
uint32_t maxRed = 0;
uint32_t maxIr = 0;
bool maxSampleSeen = false;

uint32_t lastReportMs = 0;
uint32_t lastOledMs = 0;

bool addressResponds(uint8_t address) {
  Wire.beginTransmission(address);
  return Wire.endTransmission() == 0;
}

void printAddressScan() {
  Serial.println("\nI2C scan:");
  uint8_t found = 0;
  for (uint8_t address = 1; address < 127; ++address) {
    if (addressResponds(address)) {
      Serial.printf("  found 0x%02X", address);
      if (address == OLED_ADDRESS) Serial.print("  OLED");
      if (address == TMP117_ADDRESS) Serial.print("  TMP117");
      if (address == MAX30102_ADDRESS) Serial.print("  MAX30102");
      if (address == MPU6050_ADDRESS || address == 0x69) Serial.print("  MPU6050");
      Serial.println();
      ++found;
    }
  }
  Serial.printf("I2C devices detected: %u\n\n", found);
}

void initialiseOled() {
  if (!addressResponds(OLED_ADDRESS)) {
    Serial.println("OLED: not detected at 0x3C (Serial diagnostics will continue).");
    return;
  }

  oledReady = display.begin(SSD1306_SWITCHCAPVCC, OLED_ADDRESS);
  Serial.println(oledReady ? "OLED: OK" : "OLED: address responds, but initialisation failed.");
  if (oledReady) {
    display.clearDisplay();
    display.setTextColor(SSD1306_WHITE);
    display.setTextSize(1);
    display.setCursor(0, 0);
    display.println("MaatriWatch");
    display.println("XIAO sensor test");
    display.display();
  }
}

void initialiseTmp117() {
  if (!addressResponds(TMP117_ADDRESS)) {
    Serial.println("TMP117: not detected at 0x48.");
    return;
  }

  tmpReady = tmp117.begin(TMP117_ADDRESS, &Wire);
  Serial.println(tmpReady ? "TMP117: OK" : "TMP117: address responds, but initialisation failed.");
}

void initialiseMpu6050() {
  uint8_t address = addressResponds(MPU6050_ADDRESS) ? MPU6050_ADDRESS : 0x69;
  if (!addressResponds(address)) {
    Serial.println("MPU6050: not detected at 0x68 or 0x69.");
    return;
  }

  mpuReady = mpu.begin(address, &Wire, 0);
  Serial.println(mpuReady ? "MPU6050: OK" : "MPU6050: address responds, but initialisation failed.");
  if (mpuReady) {
    mpu.setAccelerometerRange(MPU6050_RANGE_4_G);
    mpu.setGyroRange(MPU6050_RANGE_500_DEG);
    mpu.setFilterBandwidth(MPU6050_BAND_21_HZ);
  }
}

void initialiseMax30102() {
  if (!addressResponds(MAX30102_ADDRESS)) {
    Serial.println("MAX30102: not detected at 0x57.");
    return;
  }

  maxReady = max30102.begin(Wire, I2C_SPEED_FAST);
  Serial.println(maxReady ? "MAX30102: OK" : "MAX30102: address responds, but initialisation failed.");
  if (maxReady) {
    // Red + IR mode, 100 samples/s. This is signal validation, not a vital-sign algorithm.
    max30102.setup(0x1F, 4, 2, 100, 411, 4096);
    max30102.setPulseAmplitudeGreen(0);
  }
}

void readTmp117() {
  if (!tmpReady) return;
  sensors_event_t event;
  tmp117.getEvent(&event);
  tmpC = event.temperature;
}

void readMpu6050() {
  if (!mpuReady) return;
  sensors_event_t acceleration;
  sensors_event_t gyro;
  sensors_event_t temperature;
  mpu.getEvent(&acceleration, &gyro, &temperature);
  accelX = acceleration.acceleration.x;
  accelY = acceleration.acceleration.y;
  accelZ = acceleration.acceleration.z;
  gyroX = gyro.gyro.x;
  gyroY = gyro.gyro.y;
  gyroZ = gyro.gyro.z;
}

void readMax30102() {
  if (!maxReady) return;

  max30102.check();
  while (max30102.available()) {
    maxRed = max30102.getRed();
    maxIr = max30102.getIR();
    maxSampleSeen = true;
    max30102.nextSample();
  }
}

void updateOled() {
  if (!oledReady) return;

  display.clearDisplay();
  display.setTextColor(SSD1306_WHITE);
  display.setTextSize(1);
  display.setCursor(0, 0);
  display.println("MW XIAO TEST");

  display.print("MAX ");
  display.println(maxReady && maxSampleSeen ? "OK" : "--");
  display.print("IR ");
  display.println(maxSampleSeen ? maxIr : 0);

  display.print("TMP ");
  if (tmpReady && !isnan(tmpC)) display.printf("%.1f C\n", tmpC);
  else display.println("--");

  display.print("MPU Z ");
  if (mpuReady && !isnan(accelZ)) display.printf("%.1f\n", accelZ);
  else display.println("--");

  display.print("SOS ");
  display.println(digitalRead(SOS_BUTTON_PIN) == LOW ? "PRESSED" : "ready");
  display.display();
}

void printReport() {
  const bool buttonPressed = digitalRead(SOS_BUTTON_PIN) == LOW;
  Serial.println("--- MaatriWatch XIAO diagnostic ---");
  Serial.printf("OLED: %s | TMP117: %s | MPU6050: %s | MAX30102: %s\n",
                oledReady ? "OK" : "missing",
                tmpReady ? "OK" : "missing",
                mpuReady ? "OK" : "missing",
                maxReady ? "OK" : "missing");

  if (tmpReady && !isnan(tmpC)) Serial.printf("TMP117: %.2f C (local sensor temperature only)\n", tmpC);
  if (mpuReady && !isnan(accelZ)) {
    Serial.printf("MPU6050 accel m/s2: X=%.2f Y=%.2f Z=%.2f | gyro rad/s: X=%.2f Y=%.2f Z=%.2f\n",
                  accelX, accelY, accelZ, gyroX, gyroY, gyroZ);
  }
  if (maxReady) {
    Serial.printf("MAX30102 raw: red=%lu ir=%lu sample=%s\n",
                  static_cast<unsigned long>(maxRed),
                  static_cast<unsigned long>(maxIr),
                  maxSampleSeen ? "yes" : "waiting");
  }
  Serial.printf("SOS button: %s\n", buttonPressed ? "PRESSED" : "released");
}

void setup() {
  pinMode(SOS_BUTTON_PIN, INPUT_PULLUP);
  Serial.begin(SERIAL_BAUD);
  delay(1200);

  Wire.begin(I2C_SDA_PIN, I2C_SCL_PIN);
  Wire.setClock(400000);

  Serial.println("\nMaatriWatch XIAO ESP32-S3 sensor diagnostic");
  Serial.println("Use USB power only for this first test.");
  printAddressScan();

  initialiseOled();
  initialiseTmp117();
  initialiseMpu6050();
  initialiseMax30102();
  Serial.println("Move the MPU6050, cover/uncover MAX30102, and press SOS.");
}

void loop() {
  readTmp117();
  readMpu6050();
  readMax30102();

  const uint32_t now = millis();
  if (now - lastOledMs >= OLED_INTERVAL_MS) {
    lastOledMs = now;
    updateOled();
  }
  if (now - lastReportMs >= REPORT_INTERVAL_MS) {
    lastReportMs = now;
    printReport();
  }
}
