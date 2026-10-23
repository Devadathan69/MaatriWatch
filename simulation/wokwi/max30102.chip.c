// Partial MAX30102 register/FIFO model for red/IR mode and this sketch.
// Generates synthetic PPG, not optical tissue physics or a medical device.
#include "wokwi-api.h"
#include <stdint.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

typedef struct {
  uint8_t regs[256], pointer, fifo_byte;
  bool first_write;
  uint32_t fifo[32][2]; // red, then IR; each sample has six bytes.
  uint32_t heart_rate, oxygen, contact, noise;
  timer_t timer;
  double phase;
} chip_state_t;

static void set_rate(chip_state_t *s) {
  static const int rates[] = {50, 100, 200, 400, 800, 1000, 1600, 3200};
  static const int averages[] = {1, 2, 4, 8, 16, 32, 32, 32};
  int rate = rates[(s->regs[0x0a] >> 2) & 7];
  int average = averages[(s->regs[0x08] >> 5) & 7];
  timer_start(s->timer, (uint32_t)(1000000.0 * average / rate), true);
}

static void generate_sample(void *user_data) {
  chip_state_t *s = user_data;
  if ((s->regs[0x09] & 0x80) || (s->regs[0x09] & 7) != 3) return;
  static const int rates[] = {50, 100, 200, 400, 800, 1000, 1600, 3200};
  static const int averages[] = {1, 2, 4, 8, 16, 32, 32, 32};
  double hz = (double)rates[(s->regs[0x0a] >> 2) & 7] / averages[(s->regs[0x08] >> 5) & 7];
  s->phase += 6.283185307179586 * attr_read_float(s->heart_rate) / (60.0 * hz);
  if (s->phase >= 6.283185307179586) s->phase -= 6.283185307179586;
  double wave = sin(s->phase) + 0.12 * sin(2.0 * s->phase);
  double ratio = (110.0 - attr_read_float(s->oxygen)) / 25.0;
  // Deterministic high-frequency noise allows a reproducible artifact demo.
  double time = get_sim_nanos() / 1000000000.0;
  double noise = attr_read_float(s->noise) * 80.0 * sin(6.283185307179586 * 7.3 * time);
  uint32_t red = 320, ir = 350;
  if (attr_read(s->contact)) {
    red = (uint32_t)(90000.0 + 2700.0 * ratio * wave + noise * 0.6);
    ir = (uint32_t)(100000.0 + 3000.0 * wave + noise);
  }
  uint8_t wr = s->regs[0x04] & 31, rd = s->regs[0x06] & 31;
  uint8_t next = (wr + 1) & 31;
  if (next == rd) {
    s->regs[0x05] = (s->regs[0x05] + 1) & 31;
    if (!(s->regs[0x08] & 0x10)) return;
    s->regs[0x06] = (rd + 1) & 31; s->fifo_byte = 0;
  }
  s->fifo[wr][0] = red; s->fifo[wr][1] = ir;
  s->regs[0x04] = next; s->regs[0x00] |= 0x40;
}

static bool connect_cb(void *user_data, uint32_t address, bool read) {
  chip_state_t *s = user_data;
  if (!read) s->first_write = true;
  return true;
}

static bool write_cb(void *user_data, uint8_t value) {
  chip_state_t *s = user_data;
  if (s->first_write) { s->pointer = value; s->first_write = false; return true; }
  uint8_t reg = s->pointer++;
  if (reg == 0x09 && (value & 0x40)) {
    memset(s->regs, 0, sizeof(s->regs));
    s->regs[0xff] = 0x15; s->regs[0xfe] = 0x03;
    s->fifo_byte = 0; s->phase = 0; set_rate(s); return true;
  }
  s->regs[reg] = value;
  if (reg == 0x06) s->fifo_byte = 0;
  if (reg == 0x08 || reg == 0x0a) set_rate(s);
  return true;
}

static uint8_t read_cb(void *user_data) {
  chip_state_t *s = user_data;
  if (s->pointer == 0x07) {
    uint8_t rd = s->regs[0x06] & 31;
    uint8_t wr = s->regs[0x04] & 31;
    if (rd == wr) return 0;
    uint32_t sample = s->fifo[rd][s->fifo_byte / 3] & 0x3ffff;
    int shift = 16 - 8 * (s->fifo_byte % 3);
    uint8_t value = (sample >> shift) & 0xff;
    if (++s->fifo_byte == 6) {
      s->fifo_byte = 0; s->regs[0x06] = (rd + 1) & 31;
    }
    return value; // FIFO register address stays at 0x07 during burst reads.
  }
  uint8_t reg = s->pointer++, value = s->regs[reg];
  if (reg == 0x00 || reg == 0x01) s->regs[reg] = 0;
  return value;
}

void chip_init(void) {
  chip_state_t *s = calloc(1, sizeof(chip_state_t));
  s->regs[0xff] = 0x15; s->regs[0xfe] = 0x03;
  s->heart_rate = attr_init_float("heartRate", 78);
  s->oxygen = attr_init_float("oxygen", 98);
  s->contact = attr_init("contact", 1);
  s->noise = attr_init_float("noise", 0);
  const timer_config_t timer = { .callback = generate_sample, .user_data = s };
  s->timer = timer_init(&timer);
  const i2c_config_t i2c = {
    .address = 0x57,
    .sda = pin_init("SDA", INPUT_PULLUP),
    .scl = pin_init("SCL", INPUT_PULLUP),
    .connect = connect_cb, .read = read_cb, .write = write_cb, .user_data = s
  };
  i2c_init(&i2c); set_rate(s);
}
