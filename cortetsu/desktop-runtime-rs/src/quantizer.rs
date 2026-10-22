// Copyright 2022 Google LLC
// Copyright 2026 Cortetsu contributors
// SPDX-License-Identifier: Apache-2.0
//
// Rust adaptation of materialyoucolor's C++ Celebi/WSMeans algorithm. Keeping its
// initialization, convergence threshold and Lab matrix preserves existing user
// palettes. material-colors' WSMeans uses a different initialization/iteration
// count and therefore cannot substitute for this part of the old pipeline.
// Reference: T-Dynamos/materialyoucolor-python, materialyoucolor/quantize.

use material_colors::{
    color::Argb,
    quantize::{Quantizer, QuantizerResult, QuantizerWu},
};
use std::collections::{BTreeMap, HashMap};

/// The deterministic glibc random sequence used by the legacy Linux helper.
/// Private state avoids libc's process-global generator and requires no unsafe
/// FFI. This is color clustering, never a source of security randomness.
struct ClusterRandom(Vec<u32>);
impl ClusterRandom {
    fn new() -> Self {
        let mut r = vec![42688_u32];
        for i in 1..31 {
            r.push((16807 * i64::from(r[i - 1]) % 2147483647) as u32);
        }
        for i in 31..34 {
            r.push(r[i - 31]);
        }
        for i in 34..344 {
            r.push(r[i - 31].wrapping_add(r[i - 3]));
        }
        Self(r)
    }
    fn next(&mut self) -> usize {
        let i = self.0.len();
        let value = self.0[i - 31].wrapping_add(self.0[i - 3]);
        self.0.push(value);
        (value >> 1) as usize
    }
}

#[derive(Clone, Copy, Default)]
struct Lab([f64; 3]);
impl Lab {
    fn from_argb(p: Argb) -> Self {
        fn linear(c: u8) -> f64 {
            let c = f64::from(c) / 255.0;
            if c <= 0.040449936 {
                c / 12.92 * 100.0
            } else {
                ((c + 0.055) / 1.055).powf(2.4) * 100.0
            }
        }
        fn lab_f(c: f64) -> f64 {
            if c > 216.0 / 24389.0 {
                c.powf(1.0 / 3.0)
            } else {
                ((24389.0 / 27.0) * c + 16.0) / 116.0
            }
        }
        let (r, g, b) = (linear(p.red), linear(p.green), linear(p.blue));
        let x = lab_f((0.41233895 * r + 0.35762064 * g + 0.18051042 * b) / 95.047);
        let y = lab_f((0.2126 * r + 0.7152 * g + 0.0722 * b) / 100.0);
        let z = lab_f((0.01932141 * r + 0.11916382 * g + 0.95034478 * b) / 108.883);
        Self([116.0 * y - 16.0, 500.0 * (x - y), 200.0 * (y - z)])
    }
    fn argb(self) -> Argb {
        let [l, a, b] = self.0;
        let fy = (l + 16.0) / 116.0;
        let fx = a / 500.0 + fy;
        let fz = fy - b / 200.0;
        fn inv(f: f64) -> f64 {
            let cube = f * f * f;
            if cube > 216.0 / 24389.0 {
                cube
            } else {
                (116.0 * f - 16.0) / (24389.0 / 27.0)
            }
        }
        fn delinear(c: f64) -> u8 {
            let c = c / 100.0;
            let v = if c <= 0.0031308 {
                c * 12.92
            } else {
                1.055 * c.powf(1.0 / 2.4) - 0.055
            };
            (v * 255.0).round().clamp(0.0, 255.0) as u8
        }
        let x = inv(fx) * 95.047;
        let y = if l > 8.0 {
            fy * fy * fy
        } else {
            l / (24389.0 / 27.0)
        } * 100.0;
        let z = inv(fz) * 108.883;
        Argb::new(
            255,
            delinear(3.2406 * x - 1.5372 * y - 0.4986 * z),
            delinear(-0.9689 * x + 1.8758 * y + 0.0415 * z),
            delinear(0.0557 * x - 0.2040 * y + 1.0570 * z),
        )
    }
    fn distance(self, other: Self) -> f64 {
        let d = [
            self.0[0] - other.0[0],
            self.0[1] - other.0[1],
            self.0[2] - other.0[2],
        ];
        d[0] * d[0] + d[1] * d[1] + d[2] * d[2]
    }
}

pub fn quantize(pixels: &[Argb], max_colours: usize) -> QuantizerResult {
    let mut output = QuantizerResult {
        color_to_count: Default::default(),
        input_pixel_to_cluster_pixel: Default::default(),
    };
    if pixels.is_empty() || max_colours == 0 {
        return output;
    }
    let max_colours = max_colours.min(256);
    let starting = QuantizerWu::quantize(pixels, max_colours).color_to_count;
    let mut counts = HashMap::<Argb, usize>::new();
    let mut points = Vec::<(Lab, u32)>::new();
    for p in pixels {
        match counts.get(p) {
            Some(i) => points[*i].1 += 1,
            None => {
                counts.insert(*p, points.len());
                points.push((Lab::from_argb(*p), 1));
            }
        }
    }
    let mut clusters: Vec<_> = starting.keys().copied().map(Lab::from_argb).collect();
    let n = clusters.len();
    let mut random = ClusterRandom::new();
    let mut membership: Vec<_> = points.iter().map(|_| random.next() % n).collect();
    let mut populations = vec![0u32; n];
    let mut distances = vec![vec![0.0; n]; n];
    for iteration in 0..100 {
        for i in 0..n {
            for j in i + 1..n {
                let distance = clusters[i].distance(clusters[j]);
                distances[i][j] = distance;
                distances[j][i] = distance;
            }
        }
        let mut moved = false;
        for (i, (point, _)) in points.iter().enumerate() {
            let previous = membership[i];
            let previous_distance = point.distance(clusters[previous]);
            let mut minimum = previous_distance;
            let mut nearest = previous;
            for j in 0..n {
                if distances[previous][j] >= 4.0 * previous_distance {
                    continue;
                }
                let distance = point.distance(clusters[j]);
                if distance < minimum {
                    minimum = distance;
                    nearest = j;
                }
            }
            // The original Linux C++ extension resolves unqualified abs to
            // abs(int), truncating delta-E before comparing it to 3. Preserve
            // that boundary as well as the seed to avoid changing palettes.
            if nearest != previous
                && (minimum.sqrt() - previous_distance.sqrt()).abs().trunc() > 3.0
            {
                membership[i] = nearest;
                moved = true;
            }
        }
        if !moved && iteration != 0 {
            break;
        }
        let mut sums = vec![[0.0; 3]; n];
        populations.fill(0);
        for (i, (point, count)) in points.iter().enumerate() {
            let c = membership[i];
            populations[c] += count;
            for (sum, component) in sums[c].iter_mut().zip(point.0) {
                *sum += component * f64::from(*count);
            }
        }
        for i in 0..n {
            clusters[i] = if populations[i] == 0 {
                Lab::default()
            } else {
                Lab(sums[i].map(|v| v / f64::from(populations[i])))
            };
        }
    }
    // The binding used std::map; preserving ascending ARGB also preserves Score
    // tie ordering. Clusters which converge on the same color sum populations.
    let mut result = BTreeMap::<Argb, u32>::new();
    for (cluster, count) in clusters.into_iter().zip(populations) {
        if count != 0 {
            *result.entry(cluster.argb()).or_default() += count;
        }
    }
    output.color_to_count = result.into_iter().collect();
    output
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn legacy_cluster_initialization() {
        let mut random = ClusterRandom::new();
        assert_eq!(
            (0..8).map(|_| random.next()).collect::<Vec<_>>(),
            vec![
                1057348992, 762201445, 1956717003, 540228760, 637815880, 1149054967, 495305702,
                2085833226
            ]
        );
    }
}
