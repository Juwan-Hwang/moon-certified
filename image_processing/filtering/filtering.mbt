///|
/// Image Processing — 2-D convolution, edge detection, morphological operations.
///
/// This package provides production-grade image processing primitives:
///
/// - **2-D convolution**: Separable and general kernel convolution with
///   multiple border-handling strategies (zero, clamp, reflect, wrap).
/// - **Gaussian blur**: Separable Gaussian kernel for O(n·k) blurring.
/// - **Edge detection**: Sobel, Prewitt, Laplacian, Scharr, and Canny edge
///   detectors.
/// - **Morphological operations**: Erosion, dilation, opening, closing,
///   gradient, top-hat, and bottom-hat with arbitrary structuring elements.
/// - **Thresholding**: Otsu's method for automatic threshold selection.
/// - **Image utilities**: Grayscale conversion, normalization, histogram.
///
/// ## Representation
///
/// Images are stored as flat `Array[Double]` in row-major order with
/// `width` × `height` dimensions. Pixel `(x, y)` is at index `y * width + x`.
///
/// ## Complexity
///
/// | Operation              | Time              |
/// |------------------------|-------------------|
/// | `convolve2d`           | O(W·H·k₁·k₂)     |
/// | `gaussian_blur`        | O(W·H·k)          |
/// | `sobel_edges`          | O(W·H)            |
/// | `canny_edges`          | O(W·H)            |
/// | `erode` / `dilate`     | O(W·H·k₁·k₂)     |
///
/// ## References
///
/// - Gonzalez, R. C. & Woods, R. E. (2018). *Digital Image Processing*,
///   4th ed. Pearson.
/// - Canny, J. (1986). "A computational approach to edge detection."
///   *IEEE Trans. Pattern Anal. Mach. Intell.*, PAMI-8, 679–698.
/// - Otsu, N. (1979). "A threshold selection method from gray-level
///   histograms." *IEEE Trans. Syst. Man Cybern.*, SMC-9, 62–66.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.
const PI : Double = 3.14159265358979323846

// ---------------------------------------------------------------------------
// Image type and helpers
// ---------------------------------------------------------------------------

///|
/// A grayscale image stored as a flat row-major `Double` array.
pub struct Image {
  /// Pixel data in row-major order: `data[y * width + x]`.
  data : Array[Double]
  /// Image width (number of columns).
  width : Int
  /// Image height (number of rows).
  height : Int
}

///|
/// Create an image from a flat data array and dimensions.
pub fn make_image(width : Int, height : Int, fill : Double) -> Image {
  if width <= 0 || height <= 0 {
    return { data: [], width: 0, height: 0 }
  }
  { data: Array::make(width * height, fill), width, height }
}

///|
/// Create an image from an existing data array.
pub fn from_array(data : Array[Double], width : Int, height : Int) -> Image {
  if width <= 0 || height <= 0 || data.length() != width * height {
    return { data: [], width: 0, height: 0 }
  }
  { data, width, height }
}

///|
/// Get pixel at `(x, y)`. Returns 0.0 for out-of-bounds.
pub fn get_pixel(img : Image, x : Int, y : Int) -> Double {
  if x < 0 || x >= img.width || y < 0 || y >= img.height {
    return 0.0
  }
  img.data[y * img.width + x]
}

///|
/// Set pixel at `(x, y)`. No-op for out-of-bounds.
pub fn set_pixel(img : Image, x : Int, y : Int, val : Double) -> Unit {
  if x >= 0 && x < img.width && y >= 0 && y < img.height {
    img.data[y * img.width + x] = val
  }
}

///|
/// Clone an image.
pub fn clone_image(img : Image) -> Image {
  let data = Array::make(img.data.length(), 0.0)
  for i = 0; i < data.length(); i = i + 1 {
    data[i] = img.data[i]
  }
  { data, width: img.width, height: img.height }
}

// ---------------------------------------------------------------------------
// Border handling
// ---------------------------------------------------------------------------

///|
/// Border handling strategy for convolution and filtering.
pub(all) enum BorderType {
  /// Fill outside pixels with zero.
  Zero
  /// Clamp to the nearest edge pixel.
  Clamp
  /// Reflect about the edge: `abcde -> edcba|abcde|edcba`.
  Reflect
  /// Wrap around: `abcde -> ...eabcd|abcde|abcde...`.
  Wrap
}

///|
/// Sample pixel with border handling.
fn sample(img : Image, x : Int, y : Int, border : BorderType) -> Double {
  let w = img.width
  let h = img.height
  match border {
    Zero =>
      if x < 0 || x >= w || y < 0 || y >= h {
        0.0
      } else {
        img.data[y * w + x]
      }
    Clamp => {
      let cx = if x < 0 { 0 } else if x >= w { w - 1 } else { x }
      let cy = if y < 0 { 0 } else if y >= h { h - 1 } else { y }
      img.data[cy * w + cx]
    }
    Reflect => {
      let mut rx = x
      let mut ry = y
      if rx < 0 {
        rx = -rx - 1
      }
      if rx >= w {
        rx = 2 * w - rx - 1
      }
      if ry < 0 {
        ry = -ry - 1
      }
      if ry >= h {
        ry = 2 * h - ry - 1
      }
      // Final clamp (safety for very small images)
      if rx < 0 {
        rx = 0
      }
      if rx >= w {
        rx = w - 1
      }
      if ry < 0 {
        ry = 0
      }
      if ry >= h {
        ry = h - 1
      }
      img.data[ry * w + rx]
    }
    Wrap => {
      let mut rx = x % w
      if rx < 0 {
        rx = rx + w
      }
      let mut ry = y % h
      if ry < 0 {
        ry = ry + h
      }
      img.data[ry * w + rx]
    }
  }
}

// ---------------------------------------------------------------------------
// 2-D Convolution
// ---------------------------------------------------------------------------

///|
/// Apply a 2-D convolution kernel to an image.
///
/// `kernel` is a flat array in row-major order with dimensions
/// `kw` × `kh`. The kernel is centered on each pixel. For even dimensions,
/// the center is biased toward the top-left.
///
/// **Time**: O(W·H·kw·kh).
pub fn convolve2d(
  img : Image,
  kernel : Array[Double],
  kw : Int,
  kh : Int,
  border : BorderType,
) -> Image {
  let w = img.width
  let h = img.height
  if w == 0 || h == 0 || kw <= 0 || kh <= 0 {
    return clone_image(img)
  }
  let result = Array::make(w * h, 0.0)
  let half_kw = kw / 2
  let half_kh = kh / 2
  for y = 0; y < h; y = y + 1 {
    for x = 0; x < w; x = x + 1 {
      let mut acc = 0.0
      for ky = 0; ky < kh; ky = ky + 1 {
        for kx = 0; kx < kw; kx = kx + 1 {
          let px = x + kx - half_kw
          let py = y + ky - half_kh
          let coeff = kernel[ky * kw + kx]
          acc = acc + coeff * sample(img, px, py, border)
        }
      }
      result[y * w + x] = acc
    }
  }
  { data: result, width: w, height: h }
}

///|
/// Apply a separable 1-D kernel horizontally then vertically.
///
/// For a kernel of length `k`, this is O(W·H·k) instead of O(W·H·k²).
pub fn convolve_separable(
  img : Image,
  kernel : Array[Double],
  border : BorderType,
) -> Image {
  let k = kernel.length()
  if k == 0 {
    return clone_image(img)
  }
  let w = img.width
  let h = img.height
  let half_k = k / 2
  // Horizontal pass
  let temp = Array::make(w * h, 0.0)
  for y = 0; y < h; y = y + 1 {
    for x = 0; x < w; x = x + 1 {
      let mut acc = 0.0
      for ki = 0; ki < k; ki = ki + 1 {
        let px = x + ki - half_k
        acc = acc + kernel[ki] * sample(img, px, y, border)
      }
      temp[y * w + x] = acc
    }
  }
  // Vertical pass
  let result = Array::make(w * h, 0.0)
  let temp_img : Image = { data: temp, width: w, height: h }
  for y = 0; y < h; y = y + 1 {
    for x = 0; x < w; x = x + 1 {
      let mut acc = 0.0
      for ki = 0; ki < k; ki = ki + 1 {
        let py = y + ki - half_k
        acc = acc + kernel[ki] * sample(temp_img, x, py, border)
      }
      result[y * w + x] = acc
    }
  }
  { data: result, width: w, height: h }
}

// ---------------------------------------------------------------------------
// Gaussian Blur
// ---------------------------------------------------------------------------

///|
/// Generate a 1-D Gaussian kernel.
///
/// `sigma` is the standard deviation. The kernel length is
/// `2 * ceil(3 * sigma) + 1` to capture >99.7% of the distribution.
pub fn gaussian_kernel(sigma : Double) -> Array[Double] {
  if sigma <= 0.0 {
    return [1.0]
  }
  let radius = (3.0 * sigma).ceil().to_int()
  let k = 2 * radius + 1
  let kernel = Array::make(k, 0.0)
  let two_sigma_sq = 2.0 * sigma * sigma
  let mut sum = 0.0
  for i = 0; i < k; i = i + 1 {
    let x = (i - radius).to_double()
    let val = @math.exp(-(x * x) / two_sigma_sq)
    kernel[i] = val
    sum = sum + val
  }
  // Normalize
  for i = 0; i < k; i = i + 1 {
    kernel[i] = kernel[i] / sum
  }
  kernel
}

///|
/// Apply Gaussian blur using separable convolution.
///
/// **Time**: O(W·H·k) where k ≈ 6·sigma.
pub fn gaussian_blur(img : Image, sigma : Double, border : BorderType) -> Image {
  let kernel = gaussian_kernel(sigma)
  convolve_separable(img, kernel, border)
}

// ---------------------------------------------------------------------------
// Edge Detection
// ---------------------------------------------------------------------------

///|
/// Sobel edge detection — computes gradient magnitude and direction.
///
/// Returns `(magnitude, direction)` images. The direction is in radians,
/// measured from the positive x-axis.
pub fn sobel_edges(img : Image, border : BorderType) -> (Image, Image) {
  let w = img.width
  let h = img.height
  let gx_kernel : Array[Double] = [
    -1.0, 0.0, 1.0, -2.0, 0.0, 2.0, -1.0, 0.0, 1.0,
  ]
  let gy_kernel : Array[Double] = [
    -1.0, -2.0, -1.0, 0.0, 0.0, 0.0, 1.0, 2.0, 1.0,
  ]
  let gx = convolve2d(img, gx_kernel, 3, 3, border)
  let gy = convolve2d(img, gy_kernel, 3, 3, border)
  let mag = Array::make(w * h, 0.0)
  let dir = Array::make(w * h, 0.0)
  for i = 0; i < w * h; i = i + 1 {
    let dx = gx.data[i]
    let dy = gy.data[i]
    mag[i] = (dx * dx + dy * dy).sqrt()
    dir[i] = @math.atan2(dy, dx)
  }
  ({ data: mag, width: w, height: h }, { data: dir, width: w, height: h })
}

///|
/// Prewitt edge detection — similar to Sobel but with uniform weights.
pub fn prewitt_edges(img : Image, border : BorderType) -> (Image, Image) {
  let w = img.width
  let h = img.height
  let gx_kernel : Array[Double] = [
    -1.0, 0.0, 1.0, -1.0, 0.0, 1.0, -1.0, 0.0, 1.0,
  ]
  let gy_kernel : Array[Double] = [
    -1.0, -1.0, -1.0, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0,
  ]
  let gx = convolve2d(img, gx_kernel, 3, 3, border)
  let gy = convolve2d(img, gy_kernel, 3, 3, border)
  let mag = Array::make(w * h, 0.0)
  let dir = Array::make(w * h, 0.0)
  for i = 0; i < w * h; i = i + 1 {
    let dx = gx.data[i]
    let dy = gy.data[i]
    mag[i] = (dx * dx + dy * dy).sqrt()
    dir[i] = @math.atan2(dy, dx)
  }
  ({ data: mag, width: w, height: h }, { data: dir, width: w, height: h })
}

///|
/// Scharr edge detection — optimized rotational symmetry kernel.
pub fn scharr_edges(img : Image, border : BorderType) -> (Image, Image) {
  let w = img.width
  let h = img.height
  let gx_kernel : Array[Double] = [
    -3.0, 0.0, 3.0, -10.0, 0.0, 10.0, -3.0, 0.0, 3.0,
  ]
  let gy_kernel : Array[Double] = [
    -3.0, -10.0, -3.0, 0.0, 0.0, 0.0, 3.0, 10.0, 3.0,
  ]
  let gx = convolve2d(img, gx_kernel, 3, 3, border)
  let gy = convolve2d(img, gy_kernel, 3, 3, border)
  let mag = Array::make(w * h, 0.0)
  let dir = Array::make(w * h, 0.0)
  for i = 0; i < w * h; i = i + 1 {
    let dx = gx.data[i]
    let dy = gy.data[i]
    mag[i] = (dx * dx + dy * dy).sqrt()
    dir[i] = @math.atan2(dy, dx)
  }
  ({ data: mag, width: w, height: h }, { data: dir, width: w, height: h })
}

///|
/// Laplacian edge detection — second derivative based.
///
/// Uses the standard 4-connected Laplacian kernel:
/// ```text
///  0  1  0
///  1 -4  1
///  0  1  0
/// ```
pub fn laplacian_edges(img : Image, border : BorderType) -> Image {
  let kernel : Array[Double] = [0.0, 1.0, 0.0, 1.0, -4.0, 1.0, 0.0, 1.0, 0.0]
  convolve2d(img, kernel, 3, 3, border)
}

///|
/// Laplacian of Gaussian (LoG) edge detection.
///
/// First applies Gaussian blur, then Laplacian.
pub fn log_edges(img : Image, sigma : Double, border : BorderType) -> Image {
  let blurred = gaussian_blur(img, sigma, border)
  laplacian_edges(blurred, border)
}

///|
/// Canny edge detection — multi-stage edge detector.
///
/// Steps: (1) Gaussian blur, (2) Sobel gradient, (3) non-maximum suppression,
/// (4) double threshold, (5) hysteresis edge tracking.
///
/// `low_thresh` and `high_thresh` are relative to the maximum gradient
/// magnitude (0.0 to 1.0).
pub fn canny_edges(
  img : Image,
  sigma : Double,
  low_thresh : Double,
  high_thresh : Double,
  border : BorderType,
) -> Image {
  let w = img.width
  let h = img.height
  if w == 0 || h == 0 {
    return clone_image(img)
  }
  // Step 1: Gaussian blur
  let blurred = gaussian_blur(img, sigma, border)
  // Step 2: Sobel gradient
  let (mag, dir) = sobel_edges(blurred, border)
  // Find max magnitude for threshold normalization
  let mut max_mag = 0.0
  for i = 0; i < w * h; i = i + 1 {
    if mag.data[i] > max_mag {
      max_mag = mag.data[i]
    }
  }
  if max_mag < 1.0e-12 {
    return make_image(w, h, 0.0)
  }
  let t_high = high_thresh * max_mag
  let t_low = low_thresh * max_mag
  // Step 3: Non-maximum suppression
  let nms = Array::make(w * h, 0.0)
  for y = 1; y < h - 1; y = y + 1 {
    for x = 1; x < w - 1; x = x + 1 {
      let idx = y * w + x
      let m = mag.data[idx]
      if m < 1.0e-12 {
        continue
      }
      let angle = dir.data[idx]
      // Quantize angle to 4 directions (0, 45, 90, 135 degrees)
      let deg = (angle * 180.0 / PI).abs()
      let mut n1 = 0.0
      let mut n2 = 0.0
      if deg < 22.5 || deg >= 157.5 {
        // Horizontal: compare left and right
        n1 = mag.data[idx - 1]
        n2 = mag.data[idx + 1]
      } else if deg < 67.5 {
        // 45 degrees: compare diagonal
        if angle > 0.0 {
          n1 = mag.data[idx - w + 1]
          n2 = mag.data[idx + w - 1]
        } else {
          n1 = mag.data[idx - w - 1]
          n2 = mag.data[idx + w + 1]
        }
      } else if deg < 112.5 {
        // Vertical: compare up and down
        n1 = mag.data[idx - w]
        n2 = mag.data[idx + w]
        // 135 degrees: compare other diagonal
      } else if angle > 0.0 {
        n1 = mag.data[idx - w - 1]
        n2 = mag.data[idx + w + 1]
      } else {
        n1 = mag.data[idx - w + 1]
        n2 = mag.data[idx + w - 1]
      }
      if m >= n1 && m >= n2 {
        nms[idx] = m
      } else {
        nms[idx] = 0.0
      }
    }
  }
  // Step 4 & 5: Double threshold + hysteresis
  let result = Array::make(w * h, 0.0)
  // Use a simple stack-based flood fill for hysteresis
  let stack : Array[Int] = []
  // Mark strong edges and push to stack
  for i = 0; i < w * h; i = i + 1 {
    if nms[i] >= t_high {
      result[i] = 1.0
      stack.push(i)
    }
  }
  // Hysteresis: trace weak edges connected to strong edges
  while stack.length() > 0 {
    let idx = stack.pop().unwrap()
    let x = idx % w
    let y = idx / w
    // Check 8-connected neighbors
    for dy = -1; dy <= 1; dy = dy + 1 {
      for dx = -1; dx <= 1; dx = dx + 1 {
        if dx == 0 && dy == 0 {
          continue
        }
        let nx = x + dx
        let ny = y + dy
        if nx >= 0 && nx < w && ny >= 0 && ny < h {
          let nidx = ny * w + nx
          if result[nidx] == 0.0 && nms[nidx] >= t_low {
            result[nidx] = 1.0
            stack.push(nidx)
          }
        }
      }
    }
  }
  { data: result, width: w, height: h }
}

// ---------------------------------------------------------------------------
// Morphological Operations
// ---------------------------------------------------------------------------

///|
/// A structuring element for morphological operations.
pub struct StructElement {
  /// Flat array in row-major order. Non-zero values are part of the element.
  data : Array[Double]
  width : Int
  height : Int
}

///|
/// Create a rectangular structuring element of the given size.
pub fn rect_struct(w : Int, h : Int) -> StructElement {
  { data: Array::make(w * h, 1.0), width: w, height: h }
}

///|
/// Create a cross (+) shaped structuring element.
pub fn cross_struct(size : Int) -> StructElement {
  let s = if size < 3 { 3 } else if size % 2 == 0 { size + 1 } else { size }
  let data = Array::make(s * s, 0.0)
  let mid = s / 2
  for i = 0; i < s; i = i + 1 {
    data[mid * s + i] = 1.0 // horizontal
    data[i * s + mid] = 1.0 // vertical
  }
  { data, width: s, height: s }
}

///|
/// Create a disk-shaped structuring element.
pub fn disk_struct(radius : Int) -> StructElement {
  let r = if radius < 1 { 1 } else { radius }
  let s = 2 * r + 1
  let data = Array::make(s * s, 0.0)
  let r_sq = r.to_double() * r.to_double()
  for y = 0; y < s; y = y + 1 {
    for x = 0; x < s; x = x + 1 {
      let dx = (x - r).to_double()
      let dy = (y - r).to_double()
      if dx * dx + dy * dy <= r_sq {
        data[y * s + x] = 1.0
      }
    }
  }
  { data, width: s, height: s }
}

///|
/// Morphological erosion.
///
/// Each output pixel is the minimum of pixels under the structuring element
/// (where the element is non-zero).
pub fn erode(img : Image, se : StructElement, border : BorderType) -> Image {
  let w = img.width
  let h = img.height
  let sw = se.width
  let sh = se.height
  let half_sw = sw / 2
  let half_sh = sh / 2
  let result = Array::make(w * h, 0.0)
  for y = 0; y < h; y = y + 1 {
    for x = 0; x < w; x = x + 1 {
      let mut min_val = 1.0e308
      for sy = 0; sy < sh; sy = sy + 1 {
        for sx = 0; sx < sw; sx = sx + 1 {
          if se.data[sy * sw + sx] != 0.0 {
            let px = x + sx - half_sw
            let py = y + sy - half_sh
            let val = sample(img, px, py, border)
            if val < min_val {
              min_val = val
            }
          }
        }
      }
      result[y * w + x] = min_val
    }
  }
  { data: result, width: w, height: h }
}

///|
/// Morphological dilation.
///
/// Each output pixel is the maximum of pixels under the structuring element
/// (where the element is non-zero).
pub fn dilate(img : Image, se : StructElement, border : BorderType) -> Image {
  let w = img.width
  let h = img.height
  let sw = se.width
  let sh = se.height
  let half_sw = sw / 2
  let half_sh = sh / 2
  let result = Array::make(w * h, 0.0)
  for y = 0; y < h; y = y + 1 {
    for x = 0; x < w; x = x + 1 {
      let mut max_val = -1.0e308
      for sy = 0; sy < sh; sy = sy + 1 {
        for sx = 0; sx < sw; sx = sx + 1 {
          if se.data[sy * sw + sx] != 0.0 {
            let px = x + sx - half_sw
            let py = y + sy - half_sh
            let val = sample(img, px, py, border)
            if val > max_val {
              max_val = val
            }
          }
        }
      }
      result[y * w + x] = max_val
    }
  }
  { data: result, width: w, height: h }
}

///|
/// Morphological opening = erosion followed by dilation.
pub fn morphological_open(
  img : Image,
  se : StructElement,
  border : BorderType,
) -> Image {
  let eroded = erode(img, se, border)
  dilate(eroded, se, border)
}

///|
/// Morphological closing = dilation followed by erosion.
pub fn morphological_close(
  img : Image,
  se : StructElement,
  border : BorderType,
) -> Image {
  let dilated = dilate(img, se, border)
  erode(dilated, se, border)
}

///|
/// Morphological gradient = dilation − erosion.
pub fn morphological_gradient(
  img : Image,
  se : StructElement,
  border : BorderType,
) -> Image {
  let w = img.width
  let h = img.height
  let d = dilate(img, se, border)
  let e = erode(img, se, border)
  let result = Array::make(w * h, 0.0)
  for i = 0; i < w * h; i = i + 1 {
    result[i] = d.data[i] - e.data[i]
  }
  { data: result, width: w, height: h }
}

///|
/// Top-hat transform = image − opening.
pub fn top_hat(img : Image, se : StructElement, border : BorderType) -> Image {
  let w = img.width
  let h = img.height
  let opened = morphological_open(img, se, border)
  let result = Array::make(w * h, 0.0)
  for i = 0; i < w * h; i = i + 1 {
    result[i] = img.data[i] - opened.data[i]
  }
  { data: result, width: w, height: h }
}

///|
/// Bottom-hat transform = closing − image.
pub fn bottom_hat(
  img : Image,
  se : StructElement,
  border : BorderType,
) -> Image {
  let w = img.width
  let h = img.height
  let closed = morphological_close(img, se, border)
  let result = Array::make(w * h, 0.0)
  for i = 0; i < w * h; i = i + 1 {
    result[i] = closed.data[i] - img.data[i]
  }
  { data: result, width: w, height: h }
}

// ---------------------------------------------------------------------------
// Thresholding
// ---------------------------------------------------------------------------

///|
/// Compute the histogram of an image with `n_bins` bins.
///
/// Values are expected in [0, 1]. Values outside this range are clamped.
pub fn histogram(img : Image, n_bins : Int) -> Array[Int] {
  let bins = Array::make(n_bins, 0)
  for i = 0; i < img.data.length(); i = i + 1 {
    let val = img.data[i]
    let clamped = if val < 0.0 { 0.0 } else if val > 1.0 { 1.0 } else { val }
    let bin = (clamped * (n_bins - 1).to_double()).round().to_int()
    bins[bin] = bins[bin] + 1
  }
  bins
}

///|
/// Otsu's method for automatic threshold selection.
///
/// Finds the threshold that maximizes inter-class variance between
/// foreground and background. Returns a threshold in [0, 1].
pub fn otsu_threshold(img : Image) -> Double {
  let n_bins = 256
  let hist = histogram(img, n_bins)
  let total = img.data.length()
  if total == 0 {
    return 0.0
  }
  // Compute cumulative sums
  let mut sum_total = 0.0
  for i = 0; i < n_bins; i = i + 1 {
    sum_total = sum_total + i.to_double() * hist[i].to_double()
  }
  let mut sum_bg = 0.0
  let mut weight_bg = 0
  let mut max_var = -1.0
  let mut best_thresh = 0
  for t = 0; t < n_bins; t = t + 1 {
    weight_bg = weight_bg + hist[t]
    if weight_bg == 0 {
      continue
    }
    let weight_fg = total - weight_bg
    if weight_fg == 0 {
      break
    }
    sum_bg = sum_bg + t.to_double() * hist[t].to_double()
    let mean_bg = sum_bg / weight_bg.to_double()
    let mean_fg = (sum_total - sum_bg) / weight_fg.to_double()
    // Inter-class variance
    let w_bg = weight_bg.to_double() / total.to_double()
    let w_fg = weight_fg.to_double() / total.to_double()
    let var_between = w_bg * w_fg * (mean_bg - mean_fg) * (mean_bg - mean_fg)
    if var_between > max_var {
      max_var = var_between
      best_thresh = t
    }
  }
  best_thresh.to_double() / (n_bins - 1).to_double()
}

///|
/// Apply a binary threshold to an image.
///
/// Pixels >= `threshold` become `1.0`, others become `0.0`.
pub fn threshold(img : Image, threshold : Double) -> Image {
  let w = img.width
  let h = img.height
  let result = Array::make(w * h, 0.0)
  for i = 0; i < w * h; i = i + 1 {
    result[i] = if img.data[i] >= threshold { 1.0 } else { 0.0 }
  }
  { data: result, width: w, height: h }
}

// ---------------------------------------------------------------------------
// Image Utilities
// ---------------------------------------------------------------------------

///|
/// Normalize image values to [0, 1].
pub fn normalize(img : Image) -> Image {
  let w = img.width
  let h = img.height
  let mut min_val = 1.0e308
  let mut max_val = -1.0e308
  for i = 0; i < w * h; i = i + 1 {
    let v = img.data[i]
    if v < min_val {
      min_val = v
    }
    if v > max_val {
      max_val = v
    }
  }
  let range = max_val - min_val
  let result = Array::make(w * h, 0.0)
  if range < 1.0e-12 {
    // Constant image: set everything to 0
    return { data: result, width: w, height: h }
  }
  for i = 0; i < w * h; i = i + 1 {
    result[i] = (img.data[i] - min_val) / range
  }
  { data: result, width: w, height: h }
}

///|
/// Compute the absolute difference between two images.
pub fn abs_diff(a : Image, b : Image) -> Image {
  let w = a.width
  let h = a.height
  let result = Array::make(w * h, 0.0)
  for i = 0; i < w * h; i = i + 1 {
    let diff = a.data[i] - b.data[i]
    result[i] = if diff < 0.0 { -diff } else { diff }
  }
  { data: result, width: w, height: h }
}

///|
/// Add two images element-wise.
pub fn add_images(a : Image, b : Image) -> Image {
  let w = a.width
  let h = a.height
  let result = Array::make(w * h, 0.0)
  for i = 0; i < w * h; i = i + 1 {
    result[i] = a.data[i] + b.data[i]
  }
  { data: result, width: w, height: h }
}

///|
/// Subtract image `b` from image `a` element-wise.
pub fn subtract_images(a : Image, b : Image) -> Image {
  let w = a.width
  let h = a.height
  let result = Array::make(w * h, 0.0)
  for i = 0; i < w * h; i = i + 1 {
    result[i] = a.data[i] - b.data[i]
  }
  { data: result, width: w, height: h }
}

///|
/// Scale all pixel values by a scalar.
pub fn scale_image(img : Image, scalar : Double) -> Image {
  let w = img.width
  let h = img.height
  let result = Array::make(w * h, 0.0)
  for i = 0; i < w * h; i = i + 1 {
    result[i] = img.data[i] * scalar
  }
  { data: result, width: w, height: h }
}

///|
/// Box blur (average filter) using a square kernel of size `k`.
pub fn box_blur(img : Image, k : Int, border : BorderType) -> Image {
  if k <= 0 {
    return clone_image(img)
  }
  let kernel = Array::make(k, 1.0 / k.to_double())
  convolve_separable(img, kernel, border)
}

///|
/// Median filter — replaces each pixel with the median of its neighborhood.
///
/// **Time**: O(W·H·k²·log(k²)).
pub fn median_filter(img : Image, k : Int, border : BorderType) -> Image {
  let w = img.width
  let h = img.height
  if k <= 0 {
    return clone_image(img)
  }
  let half_k = k / 2
  let result = Array::make(w * h, 0.0)
  let buf : Array[Double] = Array::make(k * k, 0.0)
  for y = 0; y < h; y = y + 1 {
    for x = 0; x < w; x = x + 1 {
      let mut count = 0
      for ky = 0; ky < k; ky = ky + 1 {
        for kx = 0; kx < k; kx = kx + 1 {
          let px = x + kx - half_k
          let py = y + ky - half_k
          buf[count] = sample(img, px, py, border)
          count = count + 1
        }
      }
      // Sort and take median
      buf.sort()
      result[y * w + x] = buf[count / 2]
    }
  }
  { data: result, width: w, height: h }
}
