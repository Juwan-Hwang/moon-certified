///|
test "make_image_and_get_pixel" {
  let img = make_image(3, 2, 0.5)
  assert_eq(img.width, 3)
  assert_eq(img.height, 2)
  assert_true((get_pixel(img, 0, 0) - 0.5).abs() < 1.0e-12)
  assert_true((get_pixel(img, 2, 1) - 0.5).abs() < 1.0e-12)
  // Out of bounds returns 0
  assert_true(get_pixel(img, -1, 0) == 0.0)
  assert_true(get_pixel(img, 0, -1) == 0.0)
  assert_true(get_pixel(img, 3, 0) == 0.0)
}

///|
test "set_pixel" {
  let img = make_image(3, 3, 0.0)
  set_pixel(img, 1, 1, 0.8)
  assert_true((get_pixel(img, 1, 1) - 0.8).abs() < 1.0e-12)
  // Out of bounds is no-op
  set_pixel(img, -1, 0, 1.0)
  set_pixel(img, 3, 0, 1.0)
  assert_true(get_pixel(img, 0, 0) == 0.0)
}

///|
test "clone_image" {
  let img = from_array([1.0, 2.0, 3.0, 4.0], 2, 2)
  let c = clone_image(img)
  // Modify original
  set_pixel(img, 0, 0, 99.0)
  // Clone should be unaffected
  assert_true((get_pixel(c, 0, 0) - 1.0).abs() < 1.0e-12)
}

///|
test "convolve2d_identity" {
  let img = from_array([1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0], 3, 3)
  // Identity kernel: [0 0 0; 0 1 0; 0 0 0]
  let kernel = [0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0]
  let result = convolve2d(img, kernel, 3, 3, Clamp)
  for i = 0; i < 9; i = i + 1 {
    assert_true((result.data[i] - img.data[i]).abs() < 1.0e-10)
  }
}

///|
test "convolve2d_box_blur" {
  let img = from_array([0.0, 0.0, 0.0, 0.0, 9.0, 0.0, 0.0, 0.0, 0.0], 3, 3)
  // Box blur with Clamp border
  let kernel = [
    1.0 / 9.0,
    1.0 / 9.0,
    1.0 / 9.0,
    1.0 / 9.0,
    1.0 / 9.0,
    1.0 / 9.0,
    1.0 / 9.0,
    1.0 / 9.0,
    1.0 / 9.0,
  ]
  let result = convolve2d(img, kernel, 3, 3, Clamp)
  // Center pixel: sum of all 9 pixels / 9 = 9/9 = 1.0
  assert_true((result.data[4] - 1.0).abs() < 1.0e-10)
}

///|
test "convolve_separable_matches_2d" {
  // A separable kernel [1,1,1]/3 applied both H and V = 3x3 box blur
  let img = from_array(
    [
      1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0, 11.0, 12.0, 13.0, 14.0,
      15.0, 16.0,
    ],
    4,
    4,
  )
  let sep_kernel = [1.0 / 3.0, 1.0 / 3.0, 1.0 / 3.0]
  let sep_result = convolve_separable(img, sep_kernel, Clamp)
  // 2D equivalent kernel is outer product
  let kernel2d = Array::make(9, 0.0)
  for i = 0; i < 3; i = i + 1 {
    for j = 0; j < 3; j = j + 1 {
      kernel2d[i * 3 + j] = sep_kernel[i] * sep_kernel[j]
    }
  }
  let result2d = convolve2d(img, kernel2d, 3, 3, Clamp)
  for i = 0; i < 16; i = i + 1 {
    assert_true((sep_result.data[i] - result2d.data[i]).abs() < 1.0e-10)
  }
}

///|
test "gaussian_kernel_normalized" {
  let kernel = gaussian_kernel(1.5)
  // Sum should be 1.0
  let mut sum = 0.0
  for i = 0; i < kernel.length(); i = i + 1 {
    sum = sum + kernel[i]
  }
  assert_true((sum - 1.0).abs() < 1.0e-10)
  // Symmetric
  let n = kernel.length()
  for i = 0; i < n / 2; i = i + 1 {
    assert_true((kernel[i] - kernel[n - 1 - i]).abs() < 1.0e-10)
  }
}

///|
test "gaussian_blur_preserves_constant" {
  let img = make_image(5, 5, 0.7)
  let blurred = gaussian_blur(img, 1.0, Clamp)
  for i = 0; i < 25; i = i + 1 {
    assert_true((blurred.data[i] - 0.7).abs() < 1.0e-10)
  }
}

///|
test "sobel_edges_uniform_image" {
  let img = make_image(5, 5, 1.0)
  let (mag, _) = sobel_edges(img, Clamp)
  // Uniform image: gradient should be zero
  for i = 0; i < 25; i = i + 1 {
    assert_true(mag.data[i] < 1.0e-10)
  }
}

///|
test "sobel_edges_vertical_boundary" {
  // Left half 0, right half 1 — vertical edge in the middle
  let data : Array[Double] = []
  for y = 0; y < 5; y = y + 1 {
    for x = 0; x < 5; x = x + 1 {
      data.push(if x < 2 { 0.0 } else { 1.0 })
    }
  }
  let img = from_array(data, 5, 5)
  let (mag, _) = sobel_edges(img, Clamp)
  // Middle column should have high gradient
  assert_true(mag.data[2 * 5 + 2] > 0.5)
}

///|
test "prewitt_edges_uniform" {
  let img = make_image(4, 4, 0.5)
  let (mag, _) = prewitt_edges(img, Clamp)
  for i = 0; i < 16; i = i + 1 {
    assert_true(mag.data[i] < 1.0e-10)
  }
}

///|
test "scharr_edges_uniform" {
  let img = make_image(4, 4, 0.5)
  let (mag, _) = scharr_edges(img, Clamp)
  for i = 0; i < 16; i = i + 1 {
    assert_true(mag.data[i] < 1.0e-10)
  }
}

///|
test "laplacian_edges_uniform" {
  let img = make_image(4, 4, 1.0)
  let result = laplacian_edges(img, Clamp)
  for i = 0; i < 16; i = i + 1 {
    assert_true(result.data[i].abs() < 1.0e-10)
  }
}

///|
test "log_edges_uniform" {
  let img = make_image(5, 5, 1.0)
  let result = log_edges(img, 1.0, Clamp)
  // LoG of constant should be near zero (after Gaussian blur which preserves constant)
  for i = 0; i < 25; i = i + 1 {
    assert_true(result.data[i].abs() < 1.0e-6)
  }
}

///|
test "canny_edges_empty" {
  let img = make_image(0, 0, 0.0)
  let result = canny_edges(img, 1.0, 0.1, 0.2, Clamp)
  assert_eq(result.data.length(), 0)
}

///|
test "canny_edges_uniform" {
  let img = make_image(5, 5, 0.5)
  let result = canny_edges(img, 1.0, 0.1, 0.2, Clamp)
  // No edges in uniform image
  for i = 0; i < 25; i = i + 1 {
    assert_true(result.data[i] == 0.0)
  }
}

///|
test "canny_edges_detects_boundary" {
  // Sharp vertical boundary
  let data : Array[Double] = []
  for y = 0; y < 8; y = y + 1 {
    for x = 0; x < 8; x = x + 1 {
      data.push(if x < 4 { 0.0 } else { 1.0 })
    }
  }
  let img = from_array(data, 8, 8)
  let result = canny_edges(img, 0.5, 0.05, 0.15, Clamp)
  // Should detect some edges near the boundary
  let mut has_edge = false
  for i = 0; i < 64; i = i + 1 {
    if result.data[i] > 0.5 {
      has_edge = true
    }
  }
  assert_true(has_edge)
}

///|
test "morphology_erode" {
  // Binary image with a solid square in center
  let img = from_array(
    [
      0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 0.0, 0.0, 1.0, 1.0, 1.0, 0.0,
      0.0, 1.0, 1.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
    ],
    5,
    5,
  )
  let se = rect_struct(3, 3)
  let eroded = erode(img, se, Zero)
  // Center should survive (all neighbors are 1)
  assert_true((eroded.data[2 * 5 + 2] - 1.0).abs() < 1.0e-10)
  // Edges of the square should be eroded (at least one neighbor is 0)
  assert_true(eroded.data[1 * 5 + 1] == 0.0)
  assert_true(eroded.data[1 * 5 + 3] == 0.0)
}

///|
test "morphology_dilate" {
  // Single point in center
  let img = from_array(
    [
      0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0,
      0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
    ],
    5,
    5,
  )
  let se = rect_struct(3, 3)
  let dilated = dilate(img, se, Zero)
  // 3x3 block around center should be 1
  for dy = -1; dy <= 1; dy = dy + 1 {
    for dx = -1; dx <= 1; dx = dx + 1 {
      let idx = (2 + dy) * 5 + (2 + dx)
      assert_true((dilated.data[idx] - 1.0).abs() < 1.0e-10)
    }
  }
  // Corners should still be 0
  assert_true(dilated.data[0] == 0.0)
  assert_true(dilated.data[24] == 0.0)
}

///|
test "morphology_opening_removes_noise" {
  // Single pixel "noise" should be removed by opening
  let img = from_array(
    [
      0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0,
      0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
    ],
    5,
    5,
  )
  let se = rect_struct(3, 3)
  let opened = morphological_open(img, se, Zero)
  // All pixels should be 0 (noise removed)
  for i = 0; i < 25; i = i + 1 {
    assert_true(opened.data[i] == 0.0)
  }
}

///|
test "morphology_closing_fills_hole" {
  // Solid square with a hole
  let img = from_array(
    [
      0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 0.0, 0.0, 1.0, 0.0, 1.0, 0.0,
      0.0, 1.0, 1.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
    ],
    5,
    5,
  )
  let se = rect_struct(3, 3)
  let closed = morphological_close(img, se, Zero)
  // Hole should be filled
  assert_true((closed.data[2 * 5 + 2] - 1.0).abs() < 1.0e-10)
}

///|
test "morphological_gradient" {
  let img = from_array(
    [
      0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 0.0, 0.0, 1.0, 1.0, 1.0, 0.0,
      0.0, 1.0, 1.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
    ],
    5,
    5,
  )
  let se = rect_struct(3, 3)
  let grad = morphological_gradient(img, se, Zero)
  // Interior pixel: dilation=1, erosion=1, gradient=0
  assert_true(grad.data[2 * 5 + 2].abs() < 1.0e-10)
  // Edge pixel: dilation=1, erosion=0, gradient=1
  assert_true((grad.data[1 * 5 + 1] - 1.0).abs() < 1.0e-10)
}

///|
test "struct_elements" {
  let rs = rect_struct(3, 3)
  assert_eq(rs.width, 3)
  assert_eq(rs.height, 3)
  assert_eq(rs.data.length(), 9)
  // All ones
  for i = 0; i < 9; i = i + 1 {
    assert_true(rs.data[i] == 1.0)
  }
  let cs = cross_struct(5)
  assert_eq(cs.width, 5)
  assert_eq(cs.height, 5)
  // Center should be 1
  assert_true(cs.data[2 * 5 + 2] == 1.0)
  // Corner should be 0
  assert_true(cs.data[0] == 0.0)
  let ds = disk_struct(2)
  assert_eq(ds.width, 5)
  assert_eq(ds.height, 5)
  // Center should be 1
  assert_true(ds.data[2 * 5 + 2] == 1.0)
  // Corner should be 0 (distance > 2)
  assert_true(ds.data[0] == 0.0)
}

///|
test "histogram" {
  let img = from_array([0.0, 0.25, 0.5, 0.75, 1.0, 0.0], 3, 2)
  let hist = histogram(img, 4)
  assert_eq(hist.length(), 4)
  let total = hist[0] + hist[1] + hist[2] + hist[3]
  assert_eq(total, 6)
}

///|
test "otsu_threshold_bimodal" {
  // Bimodal: half 0.0, half 1.0
  let data : Array[Double] = []
  for i = 0; i < 50; i = i + 1 {
    data.push(0.0)
  }
  for i = 0; i < 50; i = i + 1 {
    data.push(1.0)
  }
  let img = from_array(data, 10, 10)
  let t = otsu_threshold(img)
  // Threshold should be between 0 and 1
  assert_true(t >= 0.0 && t < 1.0)
  // For perfectly bimodal with values at 0 and 1,
  // Otsu finds the first separating threshold
  assert_true(t <= 0.5)
}

///|
test "threshold_binary" {
  let img = from_array([0.1, 0.5, 0.9, 0.3], 2, 2)
  let result = threshold(img, 0.4)
  assert_true(result.data[0] == 0.0)
  assert_true(result.data[1] == 1.0)
  assert_true(result.data[2] == 1.0)
  assert_true(result.data[3] == 0.0)
}

///|
test "normalize" {
  let img = from_array([2.0, 4.0, 6.0, 8.0], 2, 2)
  let n = normalize(img)
  // Min=2, Max=8, range=6 -> (v-2)/6
  assert_true((n.data[0] - 0.0).abs() < 1.0e-10)
  assert_true((n.data[1] - 1.0 / 3.0).abs() < 1.0e-10)
  assert_true((n.data[2] - 2.0 / 3.0).abs() < 1.0e-10)
  assert_true((n.data[3] - 1.0).abs() < 1.0e-10)
}

///|
test "abs_diff" {
  let a = from_array([1.0, 3.0, 5.0, 7.0], 2, 2)
  let b = from_array([2.0, 1.0, 5.0, 10.0], 2, 2)
  let d = abs_diff(a, b)
  assert_true((d.data[0] - 1.0).abs() < 1.0e-10)
  assert_true((d.data[1] - 2.0).abs() < 1.0e-10)
  assert_true((d.data[2] - 0.0).abs() < 1.0e-10)
  assert_true((d.data[3] - 3.0).abs() < 1.0e-10)
}

///|
test "add_and_subtract_images" {
  let a = from_array([1.0, 2.0, 3.0, 4.0], 2, 2)
  let b = from_array([5.0, 6.0, 7.0, 8.0], 2, 2)
  let s = add_images(a, b)
  assert_true((s.data[0] - 6.0).abs() < 1.0e-10)
  assert_true((s.data[3] - 12.0).abs() < 1.0e-10)
  let d = subtract_images(a, b)
  assert_true((d.data[0] - -4.0).abs() < 1.0e-10)
  assert_true((d.data[3] - -4.0).abs() < 1.0e-10)
}

///|
test "scale_image" {
  let img = from_array([1.0, 2.0, 3.0, 4.0], 2, 2)
  let s = scale_image(img, 2.5)
  for i = 0; i < 4; i = i + 1 {
    assert_true((s.data[i] - img.data[i] * 2.5).abs() < 1.0e-10)
  }
}

///|
test "box_blur" {
  let img = from_array([9.0, 9.0, 9.0, 9.0, 9.0, 9.0, 9.0, 9.0, 9.0], 3, 3)
  let blurred = box_blur(img, 3, Clamp)
  // All 9s with clamp border: average should be 9.0
  for i = 0; i < 9; i = i + 1 {
    assert_true((blurred.data[i] - 9.0).abs() < 1.0e-6)
  }
}

///|
test "median_filter_removes_impulse" {
  let img = from_array(
    [
      1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 99.0, 1.0, 1.0,
      1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0,
    ],
    5,
    5,
  )
  let filtered = median_filter(img, 3, Clamp)
  // The impulse at (2,2) should be removed
  assert_true((filtered.data[2 * 5 + 2] - 1.0).abs() < 1.0e-10)
}

///|
test "border_types" {
  let img = from_array([1.0, 2.0, 3.0, 4.0], 2, 2)
  // Zero border: out of bounds = 0
  let k = [1.0] // 1x1 kernel, just reads center
  let r_zero = convolve2d(img, k, 1, 1, Zero)
  for i = 0; i < 4; i = i + 1 {
    assert_true((r_zero.data[i] - img.data[i]).abs() < 1.0e-10)
  }
  // Test Clamp: read from (-1,-1) should return (0,0)
  let k2 = [1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0] // reads top-left neighbor
  let r_clamp = convolve2d(img, k2, 3, 3, Clamp)
  // Pixel (0,0) should read from (-1,-1) clamped to (0,0) = 1.0
  assert_true((r_clamp.data[0] - 1.0).abs() < 1.0e-10)
}

///|
test "top_hat_and_bottom_hat" {
  let img = from_array(
    [
      0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 0.0, 0.0, 1.0, 1.0, 1.0, 0.0,
      0.0, 1.0, 1.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
    ],
    5,
    5,
  )
  let se = rect_struct(3, 3)
  let th = top_hat(img, se, Zero)
  let bh = bottom_hat(img, se, Zero)
  assert_eq(th.width, 5)
  assert_eq(th.height, 5)
  assert_eq(bh.width, 5)
  assert_eq(bh.height, 5)
  // Top-hat at corners should be 0 (no features)
  assert_true(th.data[0].abs() < 1.0e-10)
  // Bottom-hat at interior should be 0
  assert_true(bh.data[2 * 5 + 2].abs() < 1.0e-10)
}

///|
test "from_array_validation" {
  // Mismatched dimensions returns empty
  let img = from_array([1.0, 2.0, 3.0], 2, 2)
  assert_eq(img.width, 0)
  assert_eq(img.height, 0)
  assert_eq(img.data.length(), 0)
}
