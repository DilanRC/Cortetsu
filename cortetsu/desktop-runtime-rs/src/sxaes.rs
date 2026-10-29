//! The prompter side of gcr's `sx-aes-1` secret exchange (gcr 3.41,
//! gcr/gcr-secret-exchange.c): Diffie-Hellman over the RFC 3526 1536-bit group,
//! HKDF-SHA256 with an all-zero salt and no info down to a 16-byte key, then
//! AES-128-CBC with PKCS#7 padding and a random IV. Messages are GKeyFile text
//! with base64 values under a `[sx-aes-1]` group.
use aes::{
    Aes128,
    cipher::{BlockEncrypt, KeyInit, generic_array::GenericArray},
};
use base64::{Engine, engine::general_purpose::STANDARD as B64};
use hmac::{Hmac, Mac};
use num_bigint::BigUint;
use sha2::Sha256;
use std::{fs::File, io::Read};
use zeroize::Zeroizing;

const GROUP: &str = "sx-aes-1";
const PRIME: &str = "FFFFFFFFFFFFFFFFC90FDAA22168C234C4C6628B80DC1CD129024E088A67CC74020BBEA63B139B22514A08798E3404DDEF9519B3CD3A431B302B0A6DF25F14374FE1356D6D51C245E485B576625E7EC6F44C42E9A637ED6B0BFF5CB6F406B7EDEE386BFB5A899FA5AE9F24117C4B1FE649286651ECE45B3DC2007CB8A163BF0598DA48361C55D39A69163FA8FD24CF5F83655D23DCA3AD961C62F356208552BB9ED529077096966D670C354E4ABC9804F1746C08CA237327FFFFFFFFFFFFFFFF";

fn prime() -> BigUint {
    BigUint::parse_bytes(PRIME.as_bytes(), 16).expect("constant prime")
}

pub fn random(n: usize) -> std::io::Result<Vec<u8>> {
    let mut bytes = vec![0u8; n];
    File::open("/dev/urandom")?.read_exact(&mut bytes)?;
    Ok(bytes)
}

/// Reads one base64 field from the `[sx-aes-1]` group of a GKeyFile message.
fn field(message: &str, key: &str) -> Option<Vec<u8>> {
    let mut in_group = false;
    for line in message.lines().map(str::trim) {
        if line.starts_with('[') {
            in_group = line == format!("[{GROUP}]");
        } else if in_group
            && let Some((k, v)) = line.split_once('=')
            && k.trim() == key
        {
            return B64.decode(v.trim()).ok();
        }
    }
    None
}

/// HKDF-SHA256 (RFC 5869) with gcr's parameters; 16 bytes fit in one block.
fn transport_key(shared: &[u8]) -> Zeroizing<[u8; 16]> {
    let mut extract = <Hmac<Sha256> as Mac>::new_from_slice(&[0u8; 32]).expect("any key length");
    extract.update(shared);
    let prk: Zeroizing<[u8; 32]> = Zeroizing::new(extract.finalize().into_bytes().into());
    let mut expand = <Hmac<Sha256> as Mac>::new_from_slice(&prk[..]).expect("any key length");
    expand.update(&[1u8]);
    let okm: Zeroizing<[u8; 32]> = Zeroizing::new(expand.finalize().into_bytes().into());
    let mut key = Zeroizing::new([0u8; 16]);
    key.copy_from_slice(&okm[..16]);
    key
}

pub struct Exchange {
    // ponytail: BigUint cannot be zeroized, so the DH private value stays in
    // freed memory until reused. It only protects this one exchange; a
    // zeroizing bignum (crypto-bigint) is the upgrade if that ever matters.
    private: BigUint,
    public: Vec<u8>,
    key: Option<Zeroizing<[u8; 16]>>,
}

impl Exchange {
    pub fn new() -> std::io::Result<Self> {
        let p = prime();
        // As egg_dh_gen_pair: random, non-zero, below p/2.
        let mut bytes = Zeroizing::new(random(192)?);
        bytes[0] &= 0x7f;
        let mut private = BigUint::from_bytes_be(&bytes);
        if private == BigUint::ZERO {
            private = BigUint::from(2u8);
        }
        let public = BigUint::from(2u8).modpow(&private, &p).to_bytes_be();
        Ok(Self {
            private,
            public,
            key: None,
        })
    }

    fn message(&self, extra: &[(&str, &[u8])]) -> String {
        let mut out = format!("[{GROUP}]\npublic={}\n", B64.encode(&self.public));
        for (k, v) in extra {
            out.push_str(&format!("{k}={}\n", B64.encode(v)));
        }
        out
    }

    /// What the prompter sends before the client has spoken.
    pub fn begin(&self) -> String {
        self.message(&[])
    }

    /// Takes the client's message and derives the transport key from its
    /// public value. False for a malformed message or an out-of-range value.
    pub fn receive(&mut self, message: &str) -> bool {
        let Some(peer) = field(message, "public") else {
            return false;
        };
        let p = prime();
        let peer = BigUint::from_bytes_be(&peer);
        if peer <= BigUint::from(1u8) || peer >= &p - 1u8 {
            return false;
        }
        let shared = Zeroizing::new(peer.modpow(&self.private, &p).to_bytes_be());
        let key = transport_key(&shared);
        self.key = Some(key);
        true
    }

    /// The reply for a finished prompt: always our public value, plus the
    /// encrypted secret when there is one. None before `receive`.
    pub fn send(&self, secret: Option<&str>) -> Option<String> {
        let key = self.key.as_ref()?;
        let Some(secret) = secret else {
            return Some(self.message(&[]));
        };
        let iv = random(16).ok()?;
        let cipher = Aes128::new(GenericArray::from_slice(&key[..]));
        let pad = 16 - secret.len() % 16;
        let mut data = Zeroizing::new(secret.as_bytes().to_vec());
        data.extend(std::iter::repeat_n(pad as u8, pad));
        let mut previous: [u8; 16] = iv.clone().try_into().ok()?;
        for block in data.chunks_mut(16) {
            for (b, p) in block.iter_mut().zip(previous) {
                *b ^= p;
            }
            cipher.encrypt_block(GenericArray::from_mut_slice(block));
            previous.copy_from_slice(block);
        }
        Some(self.message(&[("secret", &data), ("iv", &iv)]))
    }
}

/// The client half, enough to decrypt what `send` produced. Tests only.
#[cfg(test)]
pub fn client_decrypt(client_private: &BigUint, reply: &str) -> Option<String> {
    let p = prime();
    let peer = BigUint::from_bytes_be(&field(reply, "public")?);
    let key = transport_key(&peer.modpow(client_private, &p).to_bytes_be());
    use aes::cipher::BlockDecrypt;
    let cipher = Aes128::new(GenericArray::from_slice(&key[..]));
    let iv = field(reply, "iv")?;
    let mut data = field(reply, "secret")?;
    let mut previous: [u8; 16] = iv.try_into().ok()?;
    for block in data.chunks_mut(16) {
        let current: [u8; 16] = block.to_vec().try_into().ok()?;
        cipher.decrypt_block(GenericArray::from_mut_slice(block));
        for (b, p) in block.iter_mut().zip(previous) {
            *b ^= p;
        }
        previous = current;
    }
    let pad = *data.last()? as usize;
    data.truncate(data.len().checked_sub(pad)?);
    String::from_utf8(data).ok()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn client() -> (BigUint, String) {
        let private = BigUint::from_bytes_be(&random(100).unwrap());
        let public = BigUint::from(2u8).modpow(&private, &prime()).to_bytes_be();
        (
            private,
            format!("[{GROUP}]\npublic={}\n", B64.encode(public)),
        )
    }

    #[test]
    fn round_trips_a_secret_through_the_client_half() {
        let mut ours = Exchange::new().unwrap();
        assert!(ours.begin().starts_with("[sx-aes-1]\npublic="));
        assert_eq!(ours.send(Some("x")), None, "no key before receive");
        let (private, hello) = client();
        assert!(ours.receive(&hello));
        for secret in ["", "contraseña", "exactly16bytes!!", &"x".repeat(300)] {
            let reply = ours.send(Some(secret)).unwrap();
            assert_eq!(client_decrypt(&private, &reply).as_deref(), Some(secret));
        }
        let cancel = ours.send(None).unwrap();
        assert!(!cancel.contains("secret="));
    }

    #[test]
    fn refuses_bad_peer_values() {
        let mut ours = Exchange::new().unwrap();
        assert!(!ours.receive("no group"));
        assert!(!ours.receive("[other]\npublic=AQ==\n"));
        assert!(
            !ours.receive("[sx-aes-1]\npublic=AQ==\n"),
            "1 is a weak public value"
        );
        let p_minus_1 = B64.encode((prime() - 1u8).to_bytes_be());
        assert!(!ours.receive(&format!("[sx-aes-1]\npublic={p_minus_1}\n")));
    }
}
