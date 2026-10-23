// Partial TMP117 I2C model: temperature, config, and device ID registers.
#include "wokwi-api.h"
#include <stdint.h>
#include <stdbool.h>
#include <stdlib.h>
#include <math.h>

typedef struct {
  uint16_t regs[16], read_word;
  uint8_t pointer, byte;
  bool first_write;
  uint32_t temperature;
} chip_state_t;

static bool connect_cb(void *user_data, uint32_t address, bool read) {
  chip_state_t *s = user_data; s->byte = 0;
  if (!read) s->first_write = true;
  if (read) {
    s->read_word = s->pointer == 0
      ? (uint16_t)(int16_t)lroundf(attr_read_float(s->temperature) * 128.0f)
      : s->regs[s->pointer & 15];
  }
  return true;
}

static bool write_cb(void *user_data, uint8_t value) {
  chip_state_t *s = user_data;
  if (s->first_write) { s->pointer = value & 15; s->first_write = false; return true; }
  if (s->byte++ == 0) s->regs[s->pointer] = (uint16_t)value << 8;
  else { s->regs[s->pointer] |= value; s->byte = 0; }
  return true;
}

static uint8_t read_cb(void *user_data) {
  chip_state_t *s = user_data;
  uint8_t value = s->byte == 0 ? s->read_word >> 8 : s->read_word & 0xff;
  s->byte = (s->byte + 1) & 1;
  return value;
}

void chip_init(void) {
  chip_state_t *s = calloc(1, sizeof(chip_state_t));
  s->temperature = attr_init_float("temperature", 33.5f);
  s->regs[1] = 0x0220; s->regs[15] = 0x0117;
  const i2c_config_t i2c = {
    .address = 0x48,
    .sda = pin_init("SDA", INPUT_PULLUP),
    .scl = pin_init("SCL", INPUT_PULLUP),
    .connect = connect_cb, .read = read_cb, .write = write_cb, .user_data = s
  };
  i2c_init(&i2c);
}
