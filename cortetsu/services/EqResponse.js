.pragma library

// Magnitude response of the Cortetsu equalizer graph, to size the preamp.
//
// The coefficients follow PipeWire's builtin biquads
// (spa/plugins/audioconvert/biquad.c at tag 1.6.11): RBJ shelves and peaking
// filters with A = 10^(dB/40) and the frequency normalised to Nyquist. The
// graph is band 1 a low shelf, bands 2-9 peaking filters and band 10 a high
// shelf, in series, so their responses multiply.
//
// Why not "minus the largest band": neighbouring peaking bands one octave
// apart overlap, so +6 dB on 64 Hz and +6 dB on 125 Hz rise above 6 dB
// between them. The preamp has to cover the cascade, not one band.

var sampleRate = 48000; // ponytail: PipeWire's default clock rate; at 44.1 kHz the 16 kHz shelf moves by a fraction of a dB. Read the graph's rate from the node if that ever matters.
var types = ["lowshelf", "peaking", "peaking", "peaking", "peaking", "peaking", "peaking", "peaking", "peaking", "highshelf"];
var qs = [0.7, 1, 1, 1, 1, 1, 1, 1, 1, 0.7];

function coefficients(type, frequency, q, db) {
    var nyquistFraction = Math.max(0, Math.min(1, frequency * 2 / sampleRate));
    var A = Math.pow(10, db / 40);
    if (nyquistFraction <= 0 || nyquistFraction >= 1)
        return [1, 0, 0, 1, 0, 0];
    var w0 = Math.PI * nyquistFraction;
    var alpha = Math.sin(w0) / (2 * q);
    var k = Math.cos(w0);
    if (type === "peaking")
        return [1 + alpha * A, -2 * k, 1 - alpha * A, 1 + alpha / A, -2 * k, 1 - alpha / A];
    var k2 = 2 * Math.sqrt(A) * alpha;
    var ap = A + 1;
    var am = A - 1;
    if (type === "lowshelf")
        return [A * (ap - am * k + k2), 2 * A * (am - ap * k), A * (ap - am * k - k2),
                ap + am * k + k2, -2 * (am + ap * k), ap + am * k - k2];
    return [A * (ap + am * k + k2), -2 * A * (am + ap * k), A * (ap + am * k - k2),
            ap - am * k + k2, 2 * (am - ap * k), ap - am * k - k2];
}

// |H(e^jw)| in dB for one biquad at `hz`.
function biquadDb(c, hz) {
    var w = 2 * Math.PI * hz / sampleRate;
    var c1 = Math.cos(w), s1 = Math.sin(w), c2 = Math.cos(2 * w), s2 = Math.sin(2 * w);
    var nr = c[0] + c[1] * c1 + c[2] * c2, ni = -(c[1] * s1 + c[2] * s2);
    var dr = c[3] + c[4] * c1 + c[5] * c2, di = -(c[4] * s1 + c[5] * s2);
    var num = nr * nr + ni * ni, den = dr * dr + di * di;
    return den > 0 ? 10 * Math.log10(num / den) : 0;
}

// Response of the whole cascade at `hz`, in dB.
function cascadeDb(frequencies, gains, hz) {
    var total = 0;
    for (var i = 0; i < frequencies.length; i++) {
        var db = Number(gains[i]) || 0;
        if (db !== 0)
            total += biquadDb(coefficients(types[i], frequencies[i], qs[i], db), hz);
    }
    return total;
}

// The highest point of the curve between 20 Hz and 20 kHz, in dB. Probed on
// 241 log-spaced points plus every band centre, where peaks sit.
function peakDb(frequencies, gains) {
    if (!gains.some(function (db) { return Number(db) > 0; }))
        return 0;
    var points = frequencies.slice();
    for (var i = 0; i <= 240; i++)
        points.push(20 * Math.pow(1000, i / 240));
    var peak = 0;
    for (var j = 0; j < points.length; j++)
        peak = Math.max(peak, cascadeDb(frequencies, gains, points[j]));
    return peak;
}

// Preamp in dB (zero or negative) that keeps the boosted curve at or under
// 0 dBFS, rounded up to the next tenth so it never undershoots.
function preampDb(frequencies, gains) {
    return -Math.ceil(peakDb(frequencies, gains) * 10) / 10;
}

// Linear gain for PipeWire's builtin `mixer` ("Gain 1" is a multiplier).
function linear(db) {
    return Math.pow(10, db / 20);
}
