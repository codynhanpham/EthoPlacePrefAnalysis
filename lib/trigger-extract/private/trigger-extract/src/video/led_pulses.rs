use opencv::{
    core::{self, Rect, Scalar},
    prelude::*,
    videoio::{
        self, VideoCapture, CAP_PROP_FPS, CAP_PROP_FRAME_COUNT, CAP_PROP_FRAME_HEIGHT,
        CAP_PROP_FRAME_WIDTH, CAP_PROP_POS_FRAMES,
    },
    Result,
};
use std::collections::VecDeque;

fn configure_hardware_acceleration() -> i32 {
    let num_threads = if let Ok(count) = std::thread::available_parallelism() {
        let count = count.get();
        if count > 1 { count - 1 } else { 1 }
    } else {
        1
    };

    // Apply OpenCV global thread count. Note this helps OpenCV kernels, but decode can still be backend-limited....
    if let Err(err) = core::set_num_threads(num_threads as i32) {
        eprintln!("[WARN] Failed to set OpenCV thread count: {}", err);
    }
    if let Err(err) = core::set_use_optimized(true) {
        eprintln!("[WARN] Failed to enable OpenCV optimized kernels: {}", err);
    }

    eprintln!("[INFO] Using CPU multithreading with {} thread(s).", num_threads);
    num_threads as i32
}


#[derive(Debug)]
pub struct LedEvent {
    pub on_frame: usize,
    pub off_frame: usize,
    pub on_time: f64,
    pub off_time: f64,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DecodeMode {
    SparseSeek,
    StreamingRing,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PulsePolarity {
    // Baseline is OFF, pulses go ON (default behavior).
    OnPulses,
    // Baseline is ON, pulses go OFF.
    OffPulses,
}

pub struct Options {
    pub roi_x_range: (f64, f64),
    pub roi_y_range: (f64, f64),
    pub decode_mode: DecodeMode,
    pub pulse_polarity: PulsePolarity,
    pub scan_step_size: usize,
    pub threshold_calibration_step_size: usize,
    pub baseline_frames_range: (usize, usize),
    pub std_threshold: f64,
    pub std_noise_floor: f64,
    pub baseline_percentile: f64,
    pub absolute_dff_threshold: f64,
}

impl Default for Options {
    fn default() -> Self {
        Options {
            roi_x_range: (0.4375, 0.5625), // [0.5-1/16, 0.5+1/16]
            roi_y_range: (0.08, 0.215),
            decode_mode: DecodeMode::SparseSeek,
            pulse_polarity: PulsePolarity::OnPulses,
            scan_step_size: 60 * 30,
            threshold_calibration_step_size: 2 * 30,
            baseline_frames_range: (30*60*1/2-1, 30*60*2-1), // 0-indexed
            std_threshold: 6.5,
            std_noise_floor: 5.0,
            baseline_percentile: 10.0,
            absolute_dff_threshold: 0.001,
        }
    }
}

// Helper function to calculate percentile
fn calculate_percentile(data: &[f64], percentile: f64) -> f64 {
    let mut sorted = data.to_vec();
    sorted.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));
    let idx = ((percentile / 100.0) * (sorted.len() - 1) as f64).round() as usize;
    sorted[idx]
}

// Helper to calculate standard deviation
fn calculate_std(data: &[f64]) -> f64 {
    let mean = data.iter().sum::<f64>() / data.len() as f64;
    let variance = data.iter().map(|value| {
        let diff = mean - *value;
        diff * diff
    }).sum::<f64>() / data.len() as f64;
    variance.sqrt()
}

fn mean_roi_intensity(frame: &Mat, rect: Rect) -> Result<f64> {
    let roi = Mat::roi(frame, rect)?;
    let mean_scalar: Scalar = core::mean(&roi, &core::no_array())?;
    Ok((mean_scalar[0] + mean_scalar[1] + mean_scalar[2]) / 3.0)
}

fn read_intensities_range(
    cap: &mut VideoCapture,
    rect: Rect,
    start_frame: usize,
    end_frame: usize,
) -> Result<Vec<f64>> {
    if end_frame < start_frame {
        return Ok(Vec::new());
    }

    cap.set(CAP_PROP_POS_FRAMES, start_frame as f64)?;

    let mut frame = Mat::default();
    let mut intensities = Vec::with_capacity(end_frame - start_frame + 1);

    for _ in start_frame..=end_frame {
        if !cap.read(&mut frame)? || frame.empty() {
            break;
        }
        intensities.push(mean_roi_intensity(&frame, rect)?);
    }

    Ok(intensities)
}

pub fn extract_led_timings(video_file_path: &str, options: Options) -> Result<Vec<LedEvent>> {
    // Configure hardware acceleration once per call
    let num_threads = configure_hardware_acceleration();
    
    let mut cap = VideoCapture::from_file(video_file_path, videoio::CAP_ANY)?;

    // Best-effort request to decoder backend to use more threads.
    // Some backends ignore this property; that's expected.
    #[allow(non_upper_case_globals)]
    {
        #[allow(unused_must_use)]
        {
            cap.set(videoio::CAP_PROP_N_THREADS, num_threads as f64);
        }
    }
    
    let w = cap.get(CAP_PROP_FRAME_WIDTH)?;
    let h = cap.get(CAP_PROP_FRAME_HEIGHT)?;
    let fps = cap.get(CAP_PROP_FPS)?;
    let frame_count = cap.get(CAP_PROP_FRAME_COUNT)? as usize;

    if frame_count == 0 {
        return Ok(Vec::new());
    }

    // ROI Conversion
    let x1 = (options.roi_x_range.0 * w).round() as i32;
    let x2 = (options.roi_x_range.1 * w).round() as i32;
    let y1 = (options.roi_y_range.0 * h).round() as i32;
    let y2 = (options.roi_y_range.1 * h).round() as i32;
    
    let rect = Rect::new(x1, y1, x2 - x1, y2 - y1);

    // ============================================================== 
    // PASS 1: Sparse decode (MATLAB-style)
    // ============================================================== 
    let base_start = options.baseline_frames_range.0.min(frame_count - 1);
    let base_end = options.baseline_frames_range.1.min(frame_count - 1);
    let base_intensities = read_intensities_range(&mut cap, rect, base_start, base_end)?;

    if base_intensities.is_empty() {
        return Ok(Vec::new());
    }

    let rough_f0 = base_intensities.iter().sum::<f64>() / base_intensities.len() as f64;
    let dff_denom = rough_f0.max(f64::EPSILON);

    let polarity_sign = match options.pulse_polarity {
        PulsePolarity::OnPulses => 1.0,
        PulsePolarity::OffPulses => -1.0,
    };

    // Detection macro-scan: controls how often we probe for ON/OFF state transitions.
    let start_macro = (base_end + 1).min(frame_count);
    let scan_step_size = options.scan_step_size.max(1);
    let micro_scan_window_size = scan_step_size;
    let threshold_calibration_step_size = options.threshold_calibration_step_size.max(1);
    let frame_trace: Vec<usize> = (start_macro..frame_count)
        .step_by(scan_step_size)
        .collect();

    if frame_trace.is_empty() {
        return Ok(Vec::new());
    }

    let mut sampled_frames = Vec::with_capacity(frame_trace.len());
    let mut dff_trace = Vec::with_capacity(frame_trace.len());
    for &k in &frame_trace {
        let current = read_intensities_range(&mut cap, rect, k, k)?;
        if let Some(&mean_intensity) = current.first() {
            sampled_frames.push(k);
            dff_trace.push(polarity_sign * ((mean_intensity - rough_f0) / dff_denom));
        }
    }

    if dff_trace.is_empty() {
        return Ok(Vec::new());
    }

    // Threshold calibration trace: keep threshold statistics stable even when macro step changes.
    let threshold_frames: Vec<usize> = (start_macro..frame_count)
        .step_by(threshold_calibration_step_size)
        .collect();
    let mut threshold_trace = Vec::with_capacity(threshold_frames.len());
    for &k in &threshold_frames {
        let current = read_intensities_range(&mut cap, rect, k, k)?;
        if let Some(&mean_intensity) = current.first() {
            threshold_trace.push(polarity_sign * ((mean_intensity - rough_f0) / dff_denom));
        }
    }

    if threshold_trace.is_empty() {
        threshold_trace = dff_trace.clone();
    }

    // Compute robust baseline from a dedicated threshold calibration trace.
    let baseline_f0_percentile = calculate_percentile(&threshold_trace, options.baseline_percentile);

    // Re-center dF/F0 traces
    for val in &mut dff_trace {
        *val -= baseline_f0_percentile;
    }
    for val in &mut threshold_trace {
        *val -= baseline_f0_percentile;
    }

    // Compute thresholds from calibration trace (recompute percentile AFTER re-centering, matching MATLAB)
    let baseline_cut = calculate_percentile(&threshold_trace, options.baseline_percentile);
    let baseline_samples: Vec<f64> = threshold_trace.iter().filter(|&&x| x <= baseline_cut).cloned().collect();
    
    let baseline_sigma = if baseline_samples.len() < 2 {
        calculate_std(&threshold_trace)
    } else {
        calculate_std(&baseline_samples)
    };

    let t_trigger = (options.std_threshold * baseline_sigma).max(options.absolute_dff_threshold);
    let t_rise_noise = options.std_noise_floor * baseline_sigma;

    // ============================================================== 
    // PASS 3: Event detection
    // ============================================================== 
    let mut events = Vec::new();
    let mut is_searching_on = true;
    let mut current_on_frame = 0;
    let mut on_level_mu = std::f64::NAN;

    match options.decode_mode {
        DecodeMode::SparseSeek => {
            for (idx, &current_dff) in dff_trace.iter().enumerate() {
                let k = sampled_frames[idx];

                if is_searching_on {
                    if current_dff > t_trigger {
                        // Micro-scan for exact start of rise in [k-scan_step, k].
                        let chunk_start = k.saturating_sub(micro_scan_window_size);
                        let chunk_intensities = read_intensities_range(&mut cap, rect, chunk_start, k)?;
                        let last_off_idx = chunk_intensities
                            .iter()
                            .enumerate()
                            .rev()
                            .find(|(_, val)| ((polarity_sign * ((**val - rough_f0) / dff_denom)) - baseline_f0_percentile) <= t_rise_noise)
                            .map(|(i, _)| i);

                        current_on_frame = match last_off_idx {
                            Some(off_idx) => chunk_start + off_idx + 1,
                            None => chunk_start,
                        };

                        if current_on_frame >= frame_count {
                            current_on_frame = frame_count - 1;
                        }

                        on_level_mu = current_dff;
                        is_searching_on = false;
                    }
                } else {
                    // SEARCHING_OFF
                    on_level_mu = 0.9 * on_level_mu + 0.1 * current_dff;
                    let t_fall_noise = on_level_mu - (options.std_noise_floor * baseline_sigma);

                    if current_dff < t_trigger {
                        // Micro-scan for exact start of fall in [chunk_start, k].
                        let chunk_start = current_on_frame.max(k.saturating_sub(micro_scan_window_size));
                        let chunk_intensities = read_intensities_range(&mut cap, rect, chunk_start, k)?;
                        let first_drop_idx = chunk_intensities
                            .iter()
                            .enumerate()
                            .find(|(_, val)| ((polarity_sign * ((**val - rough_f0) / dff_denom)) - baseline_f0_percentile) < t_fall_noise)
                            .map(|(i, _)| i);

                        let mut current_off_frame = match first_drop_idx {
                            Some(drop_idx) => chunk_start + drop_idx.saturating_sub(1),
                            None => chunk_start,
                        };

                        if current_off_frame >= frame_count {
                            current_off_frame = frame_count - 1;
                        }

                        events.push(LedEvent {
                            on_frame: current_on_frame + 1, // +1 for MATLAB 1-based indexing parity if desired
                            off_frame: current_off_frame + 1,
                            on_time: current_on_frame as f64 / fps,
                            off_time: current_off_frame as f64 / fps,
                        });

                        is_searching_on = true;
                    }
                }
            }
        }
        DecodeMode::StreamingRing => {
            let ring_start = start_macro.saturating_sub(micro_scan_window_size);
            cap.set(CAP_PROP_POS_FRAMES, ring_start as f64)?;

            let mut frame = Mat::default();
            let mut frame_idx = ring_start;
            let mut sample_idx = 0usize;
            let mut ring: VecDeque<(usize, f64)> = VecDeque::with_capacity(micro_scan_window_size + 2);

            while frame_idx < frame_count && sample_idx < sampled_frames.len() {
                if !cap.read(&mut frame)? || frame.empty() {
                    break;
                }

                let intensity = mean_roi_intensity(&frame, rect)?;
                ring.push_back((frame_idx, intensity));
                if ring.len() > micro_scan_window_size + 1 {
                    ring.pop_front();
                }

                // Advance sample pointer if decode skipped frames unexpectedly.
                while sample_idx < sampled_frames.len() && sampled_frames[sample_idx] < frame_idx {
                    sample_idx += 1;
                }

                if sample_idx < sampled_frames.len() && sampled_frames[sample_idx] == frame_idx {
                    let current_dff = dff_trace[sample_idx];
                    let k = frame_idx;

                    if is_searching_on {
                        if current_dff > t_trigger {
                            let chunk_start = k.saturating_sub(micro_scan_window_size);
                            let mut last_off_frame = None;
                            for (f, val) in ring.iter().rev() {
                                if *f < chunk_start {
                                    break;
                                }
                                let dff = (polarity_sign * ((*val - rough_f0) / dff_denom)) - baseline_f0_percentile;
                                if dff <= t_rise_noise {
                                    last_off_frame = Some(*f);
                                    break;
                                }
                            }

                            current_on_frame = match last_off_frame {
                                Some(f) => (f + 1).min(frame_count - 1),
                                None => chunk_start,
                            };

                            on_level_mu = current_dff;
                            is_searching_on = false;
                        }
                    } else {
                        on_level_mu = 0.9 * on_level_mu + 0.1 * current_dff;
                        let t_fall_noise = on_level_mu - (options.std_noise_floor * baseline_sigma);

                        if current_dff < t_trigger {
                            let chunk_start = current_on_frame.max(k.saturating_sub(micro_scan_window_size));
                            let mut first_drop_frame = None;
                            for (f, val) in ring.iter() {
                                if *f < chunk_start {
                                    continue;
                                }
                                let dff = (polarity_sign * ((*val - rough_f0) / dff_denom)) - baseline_f0_percentile;
                                if dff < t_fall_noise {
                                    first_drop_frame = Some(*f);
                                    break;
                                }
                            }

                            let current_off_frame = match first_drop_frame {
                                Some(f) => f.saturating_sub(1).max(chunk_start).min(frame_count - 1),
                                None => chunk_start,
                            };

                            events.push(LedEvent {
                                on_frame: current_on_frame + 1,
                                off_frame: current_off_frame + 1,
                                on_time: current_on_frame as f64 / fps,
                                off_time: current_off_frame as f64 / fps,
                            });

                            is_searching_on = true;
                        }
                    }

                    sample_idx += 1;
                }

                frame_idx += 1;
            }
        }
    }

    // If LED stays ON until the end, close the event at the last frame.
    if !is_searching_on {
        let current_off_frame = frame_count - 1;
        events.push(LedEvent {
            on_frame: current_on_frame + 1,
            off_frame: current_off_frame + 1,
            on_time: current_on_frame as f64 / fps,
            off_time: current_off_frame as f64 / fps,
        });
    }

    Ok(events)
}


#[cfg(test)]
mod tests {
    use super::*;

    // Use the ./led_pulses_test.bat file to quickly test this function with a known video

    #[test]
    #[ignore = "Set LED_TEST_VIDEO to an absolute video path before running this test"]
    fn test_extract_led_timings() -> Result<()> {
        let video_path = std::env::var("LED_TEST_VIDEO")
            .expect("Missing LED_TEST_VIDEO env var (absolute path to test video)");

        let mut options = Options::default();
        if let Ok(mode) = std::env::var("LED_DECODE_MODE") {
            if mode.eq_ignore_ascii_case("streaming") || mode.eq_ignore_ascii_case("ring") {
                options.decode_mode = DecodeMode::StreamingRing;
            }
        }
        if let Ok(polarity) = std::env::var("LED_PULSE_POLARITY") {
            if polarity.eq_ignore_ascii_case("off") || polarity.eq_ignore_ascii_case("off-pulses") {
                options.pulse_polarity = PulsePolarity::OffPulses;
            }
        }

        let events = extract_led_timings(&video_path, options)?;

        assert!(
            !events.is_empty(),
            "No LED events detected for video: {}",
            video_path
        );
        println!("{:#?}", events);
        Ok(())
    }
}