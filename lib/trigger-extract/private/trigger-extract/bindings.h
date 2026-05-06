#include <stdint.h>
#include <stddef.h>

#define LED_FFI_OK 0

#define LED_FFI_ERR_NULL_POINTER 1

#define LED_FFI_ERR_INVALID_UTF8 2

#define LED_FFI_ERR_INVALID_OPTION 3

#define LED_FFI_ERR_RUNTIME 4

#define LED_FFI_ERR_PANIC 5

typedef struct LedPulseOptionsC {
  double roi_x_start;
  double roi_x_end;
  double roi_y_start;
  double roi_y_end;
  int32_t decode_mode;
  int32_t pulse_polarity;
  uintptr_t scan_step_size;
  uintptr_t threshold_calibration_step_size;
  uintptr_t baseline_frame_start;
  uintptr_t baseline_frame_end;
  double std_threshold;
  double std_noise_floor;
  double baseline_percentile;
  double absolute_dff_threshold;
} LedPulseOptionsC;

typedef struct LedEventC {
  uintptr_t on_frame;
  uintptr_t off_frame;
  double on_time;
  double off_time;
} LedEventC;

typedef struct LedEventsBuffer {
  struct LedEventC *events;
  uintptr_t len;
  char *error_message;
} LedEventsBuffer;

typedef struct LedEventsResultC {
  int32_t status_code;
  struct LedEventC *events;
  uintptr_t len;
  char *error_message;
} LedEventsResultC;

int32_t led_pulses_get_default_options(struct LedPulseOptionsC *out_options);

int32_t led_pulses_extract_to_buffer(const char *video_file_path,
                                     const struct LedPulseOptionsC *options,
                                     struct LedEventsBuffer *out_result);

struct LedEventsResultC *led_pulses_extract(const char *video_file_path,
                                            double roi_x_start,
                                            double roi_x_end,
                                            double roi_y_start,
                                            double roi_y_end,
                                            int32_t decode_mode,
                                            int32_t pulse_polarity,
                                            uintptr_t scan_step_size,
                                            uintptr_t threshold_calibration_step_size,
                                            uintptr_t baseline_frame_start,
                                            uintptr_t baseline_frame_end,
                                            double std_threshold,
                                            double std_noise_floor,
                                            double baseline_percentile,
                                            double absolute_dff_threshold);

void led_pulses_free_result(struct LedEventsBuffer *result);

void led_pulses_free_owned_result(struct LedEventsResultC *result);
