use std::ffi::{c_char, CStr, CString};
use std::path::Path;
use std::ptr;

use crate::video::led_pulses;

#[repr(C)]
pub struct LedPulseOptionsC {
	pub roi_x_start: f64,
	pub roi_x_end: f64,
	pub roi_y_start: f64,
	pub roi_y_end: f64,
	pub decode_mode: i32,
	pub pulse_polarity: i32,
	pub scan_step_size: usize,
	pub threshold_calibration_step_size: usize,
	pub baseline_frame_start: usize,
	pub baseline_frame_end: usize,
	pub std_threshold: f64,
	pub std_noise_floor: f64,
	pub baseline_percentile: f64,
	pub absolute_dff_threshold: f64,
}

#[repr(C)]
pub struct LedEventC {
	pub on_frame: usize,
	pub off_frame: usize,
	pub on_time: f64,
	pub off_time: f64,
}

#[repr(C)]
pub struct LedEventsBuffer {
	pub events: *mut LedEventC,
	pub len: usize,
	pub error_message: *mut c_char,
}

#[repr(C)]
pub struct LedEventsResultC {
	pub status_code: i32,
	pub events: *mut LedEventC,
	pub len: usize,
	pub error_message: *mut c_char,
}

pub const LED_FFI_OK: i32 = 0;
pub const LED_FFI_ERR_NULL_POINTER: i32 = 1;
pub const LED_FFI_ERR_INVALID_UTF8: i32 = 2;
pub const LED_FFI_ERR_INVALID_OPTION: i32 = 3;
pub const LED_FFI_ERR_RUNTIME: i32 = 4;
pub const LED_FFI_ERR_PANIC: i32 = 5;

fn clear_result(result: &mut LedEventsBuffer) {
	result.events = ptr::null_mut();
	result.len = 0;
	result.error_message = ptr::null_mut();
}

fn set_result_error(result: &mut LedEventsBuffer, message: String) {
	if let Ok(cmsg) = CString::new(message) {
		result.error_message = cmsg.into_raw();
	}
}

fn clear_owned_result(result: &mut LedEventsResultC) {
	result.status_code = LED_FFI_OK;
	result.events = ptr::null_mut();
	result.len = 0;
	result.error_message = ptr::null_mut();
}

fn set_owned_result_error(result: &mut LedEventsResultC, message: String) {
	if let Ok(cmsg) = CString::new(message) {
		result.error_message = cmsg.into_raw();
	}
}

fn decode_mode_from_i32(value: i32) -> Option<led_pulses::DecodeMode> {
	match value {
		0 => Some(led_pulses::DecodeMode::SparseSeek),
		1 => Some(led_pulses::DecodeMode::StreamingRing),
		_ => None,
	}
}

fn pulse_polarity_from_i32(value: i32) -> Option<led_pulses::PulsePolarity> {
	match value {
		0 => Some(led_pulses::PulsePolarity::OnPulses),
		1 => Some(led_pulses::PulsePolarity::OffPulses),
		_ => None,
	}
}

fn decode_mode_to_i32(value: led_pulses::DecodeMode) -> i32 {
	match value {
		led_pulses::DecodeMode::SparseSeek => 0,
		led_pulses::DecodeMode::StreamingRing => 1,
	}
}

fn pulse_polarity_to_i32(value: led_pulses::PulsePolarity) -> i32 {
	match value {
		led_pulses::PulsePolarity::OnPulses => 0,
		led_pulses::PulsePolarity::OffPulses => 1,
	}
}

fn validate_c_options(c_options: &LedPulseOptionsC) -> Result<(), String> {
	if !(0.0..=1.0).contains(&c_options.roi_x_start)
		|| !(0.0..=1.0).contains(&c_options.roi_x_end)
		|| c_options.roi_x_start >= c_options.roi_x_end
	{
		return Err("ROI X range must satisfy 0 <= start < end <= 1".to_string());
	}

	if !(0.0..=1.0).contains(&c_options.roi_y_start)
		|| !(0.0..=1.0).contains(&c_options.roi_y_end)
		|| c_options.roi_y_start >= c_options.roi_y_end
	{
		return Err("ROI Y range must satisfy 0 <= start < end <= 1".to_string());
	}

	if c_options.scan_step_size == 0 {
		return Err("scan_step_size must be > 0".to_string());
	}

	if c_options.threshold_calibration_step_size == 0 {
		return Err("threshold_calibration_step_size must be > 0".to_string());
	}

	if c_options.baseline_frame_end < c_options.baseline_frame_start {
		return Err("baseline_frame_end must be >= baseline_frame_start".to_string());
	}

	if c_options.std_threshold <= 0.0 {
		return Err("std_threshold must be > 0".to_string());
	}

	if c_options.std_noise_floor <= 0.0 {
		return Err("std_noise_floor must be > 0".to_string());
	}

	if !(0.0..=100.0).contains(&c_options.baseline_percentile) {
		return Err("baseline_percentile must be between 0 and 100".to_string());
	}

	if c_options.absolute_dff_threshold < 0.0 {
		return Err("absolute_dff_threshold must be >= 0".to_string());
	}

	if decode_mode_from_i32(c_options.decode_mode).is_none() {
		return Err(format!("unsupported decode_mode code: {}", c_options.decode_mode));
	}

	if pulse_polarity_from_i32(c_options.pulse_polarity).is_none() {
		return Err(format!(
			"unsupported pulse_polarity code: {}",
			c_options.pulse_polarity
		));
	}

	Ok(())
}

fn convert_c_options(c_options: &LedPulseOptionsC) -> Result<led_pulses::Options, String> {
	validate_c_options(c_options)?;

	Ok(led_pulses::Options {
		roi_x_range: (c_options.roi_x_start, c_options.roi_x_end),
		roi_y_range: (c_options.roi_y_start, c_options.roi_y_end),
		decode_mode: decode_mode_from_i32(c_options.decode_mode)
			.ok_or_else(|| format!("unsupported decode_mode code: {}", c_options.decode_mode))?,
		pulse_polarity: pulse_polarity_from_i32(c_options.pulse_polarity).ok_or_else(|| {
			format!("unsupported pulse_polarity code: {}", c_options.pulse_polarity)
		})?,
		scan_step_size: c_options.scan_step_size,
		threshold_calibration_step_size: c_options.threshold_calibration_step_size,
		baseline_frames_range: (c_options.baseline_frame_start, c_options.baseline_frame_end),
		std_threshold: c_options.std_threshold,
		std_noise_floor: c_options.std_noise_floor,
		baseline_percentile: c_options.baseline_percentile,
		absolute_dff_threshold: c_options.absolute_dff_threshold,
	})
}

fn build_default_c_options(options: &led_pulses::Options) -> LedPulseOptionsC {
	LedPulseOptionsC {
		roi_x_start: options.roi_x_range.0,
		roi_x_end: options.roi_x_range.1,
		roi_y_start: options.roi_y_range.0,
		roi_y_end: options.roi_y_range.1,
		decode_mode: decode_mode_to_i32(options.decode_mode),
		pulse_polarity: pulse_polarity_to_i32(options.pulse_polarity),
		scan_step_size: options.scan_step_size,
		threshold_calibration_step_size: options.threshold_calibration_step_size,
		baseline_frame_start: options.baseline_frames_range.0,
		baseline_frame_end: options.baseline_frames_range.1,
		std_threshold: options.std_threshold,
		std_noise_floor: options.std_noise_floor,
		baseline_percentile: options.baseline_percentile,
		absolute_dff_threshold: options.absolute_dff_threshold,
	}
}

fn copy_events_to_c_buffer(events: Vec<led_pulses::LedEvent>, output_buffer: &mut LedEventsBuffer) {
	let mut c_events: Vec<LedEventC> = events
		.into_iter()
		.map(|event| LedEventC {
			on_frame: event.on_frame,
			off_frame: event.off_frame,
			on_time: event.on_time,
			off_time: event.off_time,
		})
		.collect();

	output_buffer.len = c_events.len();
	output_buffer.events = if c_events.is_empty() {
		ptr::null_mut()
	} else {
		let events_ptr = c_events.as_mut_ptr();
		std::mem::forget(c_events);
		events_ptr
	};
}

fn free_event_buffer(events_ptr: *mut LedEventC, event_count: usize) {
	if !events_ptr.is_null() {
		unsafe {
			drop(Vec::from_raw_parts(events_ptr, event_count, event_count));
		}
	}
}

fn free_c_string(message_ptr: *mut c_char) {
	if !message_ptr.is_null() {
		unsafe {
			drop(CString::from_raw(message_ptr));
		}
	}
}

fn extract_events_into_buffer(
	video_file_path: *const c_char,
	c_options: &LedPulseOptionsC,
	output_buffer: &mut LedEventsBuffer,
) -> i32 {
	let video_path = match unsafe { CStr::from_ptr(video_file_path) }.to_str() {
		Ok(s) => s,
		Err(_) => return LED_FFI_ERR_INVALID_UTF8,
	};

	let normalized_path = Path::new(video_path);
	let normalized_video_path = match normalized_path.to_str() {
		Some(s) => s,
		None => return LED_FFI_ERR_INVALID_UTF8,
	};

	let extraction_options = match convert_c_options(c_options) {
		Ok(opts) => opts,
		Err(err) => {
			set_result_error(output_buffer, err);
			return LED_FFI_ERR_INVALID_OPTION;
		}
	};

	let extracted_events = match led_pulses::extract_led_timings(normalized_video_path, extraction_options) {
		Ok(v) => v,
		Err(err) => {
			set_result_error(output_buffer, format!("{}", err));
			return LED_FFI_ERR_RUNTIME;
		}
	};

	copy_events_to_c_buffer(extracted_events, output_buffer);

	LED_FFI_OK
}

#[unsafe(no_mangle)]
pub extern "C" fn led_pulses_get_default_options(out_options: *mut LedPulseOptionsC) -> i32 {
	if out_options.is_null() {
		return LED_FFI_ERR_NULL_POINTER;
	}

	let default_c_options = build_default_c_options(&led_pulses::Options::default());
	unsafe {
		*out_options = default_c_options;
	}

	LED_FFI_OK
}

#[unsafe(no_mangle)]
pub extern "C" fn led_pulses_extract_to_buffer(
	video_file_path: *const c_char,
	options: *const LedPulseOptionsC,
	out_result: *mut LedEventsBuffer,
) -> i32 {
	if video_file_path.is_null() || options.is_null() || out_result.is_null() {
		return LED_FFI_ERR_NULL_POINTER;
	}

	let output_buffer = unsafe { &mut *out_result };
	clear_result(output_buffer);

	let c_options = unsafe { &*options };
	let run = || -> i32 { extract_events_into_buffer(video_file_path, c_options, output_buffer) };

	match std::panic::catch_unwind(std::panic::AssertUnwindSafe(run)) {
		Ok(code) => code,
		Err(_) => {
			set_result_error(output_buffer, "panic in led_pulses_extract_to_buffer".to_string());
			LED_FFI_ERR_PANIC
		}
	}
}

#[unsafe(no_mangle)]
pub extern "C" fn led_pulses_extract(
	video_file_path: *const c_char,
	roi_x_start: f64,
	roi_x_end: f64,
	roi_y_start: f64,
	roi_y_end: f64,
	decode_mode: i32,
	pulse_polarity: i32,
	scan_step_size: usize,
	threshold_calibration_step_size: usize,
	baseline_frame_start: usize,
	baseline_frame_end: usize,
	std_threshold: f64,
	std_noise_floor: f64,
	baseline_percentile: f64,
	absolute_dff_threshold: f64,
) -> *mut LedEventsResultC {
	let mut owned_result_box = Box::new(LedEventsResultC {
		status_code: LED_FFI_OK,
		events: ptr::null_mut(),
		len: 0,
		error_message: ptr::null_mut(),
	});
	clear_owned_result(&mut owned_result_box);

	if video_file_path.is_null() {
		owned_result_box.status_code = LED_FFI_ERR_NULL_POINTER;
		set_owned_result_error(&mut owned_result_box, "video_file_path must not be null".to_string());
		return Box::into_raw(owned_result_box);
	}

	let c_options = LedPulseOptionsC {
		roi_x_start,
		roi_x_end,
		roi_y_start,
		roi_y_end,
		decode_mode,
		pulse_polarity,
		scan_step_size,
		threshold_calibration_step_size,
		baseline_frame_start,
		baseline_frame_end,
		std_threshold,
		std_noise_floor,
		baseline_percentile,
		absolute_dff_threshold,
	};

	let run = || -> i32 {
		let mut output_buffer = LedEventsBuffer {
			events: ptr::null_mut(),
			len: 0,
			error_message: ptr::null_mut(),
		};
		let status = extract_events_into_buffer(video_file_path, &c_options, &mut output_buffer);
		owned_result_box.status_code = status;
		owned_result_box.events = output_buffer.events;
		owned_result_box.len = output_buffer.len;
		owned_result_box.error_message = output_buffer.error_message;
		status
	};

	match std::panic::catch_unwind(std::panic::AssertUnwindSafe(run)) {
		Ok(_) => Box::into_raw(owned_result_box),
		Err(_) => {
			owned_result_box.status_code = LED_FFI_ERR_PANIC;
			set_owned_result_error(&mut owned_result_box, "panic in led_pulses_extract".to_string());
			Box::into_raw(owned_result_box)
		}
	}
}

#[unsafe(no_mangle)]
pub extern "C" fn led_pulses_free_result(result: *mut LedEventsBuffer) {
	if result.is_null() {
		return;
	}

	let output_buffer = unsafe { &mut *result };

	free_event_buffer(output_buffer.events, output_buffer.len);
	free_c_string(output_buffer.error_message);

	clear_result(output_buffer);
}

#[unsafe(no_mangle)]
pub extern "C" fn led_pulses_free_owned_result(result: *mut LedEventsResultC) {
	if result.is_null() {
		return;
	}

	let mut owned_result_box = unsafe { Box::from_raw(result) };

	free_event_buffer(owned_result_box.events, owned_result_box.len);
	free_c_string(owned_result_box.error_message);

	clear_owned_result(&mut owned_result_box);
}