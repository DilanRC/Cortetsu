//! The `capabilities/key` bitmap of an input device.
//!
//! The kernel prints the bitmap as hexadecimal words, most significant word
//! first, each one an unsigned long without padding. A word is 64 bits on a
//! 64-bit kernel and 32 bits on a 32-bit one; the file itself does not say
//! which, so the width is a parameter. `word_bits_for` picks it from the text
//! when a word is too long for 32 bits and from the build target otherwise.

/// Codes whose bit is set, ascending.
pub fn parse(text: &str, word_bits: u32) -> Result<Vec<u16>, String> {
    let mut codes = Vec::new();
    for (index, word) in text.split_whitespace().rev().enumerate() {
        let value = u64::from_str_radix(word, 16).map_err(|_| format!("palabra no hexadecimal: {word}"))?;
        if word_bits < 64 && value >> word_bits != 0 {
            return Err(format!("{word} no cabe en {word_bits} bits"));
        }
        for bit in 0..word_bits {
            if value & (1u64 << bit) != 0 {
                let code = index as u64 * u64::from(word_bits) + u64::from(bit);
                codes.push(u16::try_from(code).map_err(|_| format!("código fuera de rango: {code}"))?);
            }
        }
    }
    codes.sort_unstable();
    Ok(codes)
}

pub fn word_bits_for(text: &str) -> u32 {
    let long_word = text.split_whitespace().any(|word| word.trim_start_matches('0').len() > 8);
    if long_word || cfg!(target_pointer_width = "64") { 64 } else { 32 }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn empty_and_zero_bitmaps_declare_nothing() {
        assert_eq!(parse("", 64).unwrap(), Vec::<u16>::new());
        assert_eq!(parse("0", 64).unwrap(), Vec::<u16>::new());
    }

    #[test]
    fn the_rightmost_word_is_word_zero() {
        // Power Button on the HP Victus: KEY_POWER (116) and KEY_WAKEUP (143).
        assert_eq!(parse("8000 10000000000000 0", 64).unwrap(), vec![116, 143]);
    }

    #[test]
    fn word_boundaries_at_64_bits() {
        assert_eq!(parse("1 8000000000000000", 64).unwrap(), vec![63, 64]);
        assert_eq!(parse("1 0 1", 64).unwrap(), vec![0, 128]);
    }

    #[test]
    fn word_boundaries_at_32_bits() {
        assert_eq!(parse("1 80000000", 32).unwrap(), vec![31, 32]);
        // The same text read as 64-bit words means other codes.
        assert_eq!(parse("1 80000000", 64).unwrap(), vec![31, 64]);
        assert!(parse("100000000", 32).is_err());
    }

    #[test]
    fn high_codes_such_as_key_fn_esc() {
        // KEY_FN_ESC = 465 = word 7, bit 17.
        let text = format!("20000{}", " 0".repeat(7));
        assert_eq!(parse(&text, 64).unwrap(), vec![465]);
    }

    #[test]
    fn width_is_detected_from_long_words() {
        assert_eq!(word_bits_for("10000000000000 0"), 64);
    }

    #[test]
    fn garbage_is_an_error_not_an_empty_device() {
        assert!(parse("zz 0", 64).is_err());
    }
}
