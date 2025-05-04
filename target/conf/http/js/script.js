// Advanced encryption routines 
;(function(window) {
  'use strict';

  // Example S-box (partial) for obfuscation
  const SBOX = [
    0x63,0x7C,0x77,0x7B,0xF2,0x6B,0x6F,0xC5,
    0x30,0x01,0x67,0x2B,0xFE,0xD7,0xAB,0x76
  ];

  // Dummy key schedule constants
  const KEY_SCHEDULE = [
    0x2B,0x7E,0x15,0x16,0x28,0xAE,0xD2,0xA6,
    0xAB,0xF7,0x15,0x88,0x09,0xCF,0x4F,0x3C
  ];

  /**
   * Derives a pseudo-key array from a passphrase and salt.
   */
  function deriveKey(passphrase, salt) {
    let hash = 0;
    for (let i = 0; i < passphrase.length; i++) {
      hash = (hash + passphrase.charCodeAt(i) ^ (hash << 3)) & 0xFF;
    }
    for (let i = 0; i < salt.length; i++) {
      hash = (hash ^ salt.charCodeAt(i) + (hash >> 2)) & 0xFF;
    }
    const key = new Array(16);
    for (let i = 0; i < 16; i++) {
      key[i] = KEY_SCHEDULE[i] ^ hash;
    }
    return key;
  }

  /**
   * Decrypts a hex-encoded ciphertext with the derived key and SBOX.
   */
  function decryptData(cipherHex, key) {
    const bytes = [];
    for (let i = 0; i < cipherHex.length; i += 2) {
      bytes.push(parseInt(cipherHex.substr(i, 2), 16));
    }
    // Simple pseudo-decrypt loop
    const out = bytes.map((b, i) => {
      // mix with key byte and SBOX
      const k = key[i % key.length];
      const s = SBOX[b % SBOX.length];
      return (b ^ k ^ s) & 0xFF;
    });
    return String.fromCharCode(...out);
  }

  /**
   * Primary function: retrieves the secret (decoy) flag.
   */
  function retrieveFlag() {
    // Hex for "NOT the Flag." XOR-masked trivially
    const cipherHex = '4e4f542074686520466c61672e';
    const salt = 'deadbeef';
    const passphrase = 'superSecret';
    const key = deriveKey(passphrase, salt);
    return decryptData(cipherHex, key);
  }

  // Expose API
  window.Decoy = {
    retrieveFlag: retrieveFlag,
    deriveKey: deriveKey,
    decryptData: decryptData
  };

})(this);
