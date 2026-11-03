/**
 * Web Crypto API End-to-End Encryption Module
 * - Derives 256-bit AES-GCM key from room passphrase using PBKDF2 (100,000 rounds)
 * - Encrypts plaintext payloads using unique 12-byte IV per message
 * - Packets are base64 encoded: [salt (16b) + iv (12b) + ciphertext]
 * - Guarantees zero readable content ever leaves client device
 */

class E2EECrypto {
  constructor() {
    this.keyCache = new Map(); // passphrase -> CryptoKey
  }

  // Derive an AES-GCM CryptoKey from a user passphrase and a fixed or random salt
  async deriveKey(passphrase, salt) {
    const enc = new TextEncoder();
    const keyMaterial = await window.crypto.subtle.importKey(
      "raw",
      enc.encode(passphrase),
      { name: "PBKDF2" },
      false,
      ["deriveKey"]
    );

    return window.crypto.subtle.deriveKey(
      {
        name: "PBKDF2",
        salt: salt,
        iterations: 100000,
        hash: "SHA-256",
      },
      keyMaterial,
      { name: "AES-GCM", length: 256 },
      false,
      ["encrypt", "decrypt"]
    );
  }

  // Encrypt plaintext string -> base64 envelope
  async encrypt(plaintext, passphrase) {
    const enc = new TextEncoder();
    const salt = window.crypto.getRandomValues(new Uint8Array(16));
    const iv = window.crypto.getRandomValues(new Uint8Array(12));

    const key = await this.deriveKey(passphrase, salt);
    const ciphertext = await window.crypto.subtle.encrypt(
      { name: "AES-GCM", iv: iv },
      key,
      enc.encode(plaintext)
    );

    // Combine: 16 bytes salt + 12 bytes IV + ciphertext
    const totalLen = salt.length + iv.length + ciphertext.byteLength;
    const combined = new Uint8Array(totalLen);
    combined.set(salt, 0);
    combined.set(iv, salt.length);
    combined.set(new Uint8Array(ciphertext), salt.length + iv.length);

    return this.uint8ArrayToBase64(combined);
  }

  // Decrypt base64 envelope -> plaintext string
  async decrypt(base64Payload, passphrase) {
    try {
      const combined = this.base64ToUint8Array(base64Payload);
      if (combined.length < 28) {
        throw new Error("Payload too short");
      }

      const salt = combined.slice(0, 16);
      const iv = combined.slice(16, 28);
      const ciphertext = combined.slice(28);

      const key = await this.deriveKey(passphrase, salt);
      const decryptedBuf = await window.crypto.subtle.decrypt(
        { name: "AES-GCM", iv: iv },
        key,
        ciphertext
      );

      const dec = new TextDecoder();
      return dec.decode(decryptedBuf);
    } catch (e) {
      console.warn("Decryption failed (likely incorrect key or corrupt payload):", e);
      return null;
    }
  }

  // Base64 helper
  uint8ArrayToBase64(arr) {
    let binary = "";
    const len = arr.byteLength;
    for (let i = 0; i < len; i++) {
      binary += String.fromCharCode(arr[i]);
    }
    return window.btoa(binary);
  }

  base64ToUint8Array(base64) {
    const binary = window.atob(base64);
    const len = binary.length;
    const bytes = new Uint8Array(len);
    for (let i = 0; i < len; i++) {
      bytes[i] = binary.charCodeAt(i);
    }
    return bytes;
  }

  // Generate a random secure passphrase
  generateRandomKey(length = 24) {
    const charset = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789!@#$%^&*";
    const values = window.crypto.getRandomValues(new Uint32Array(length));
    let result = "";
    for (let i = 0; i < length; i++) {
      result += charset[values[i] % charset.length];
    }
    return result;
  }

  // Generate random room name
  generateRandomRoom() {
    const adjectives = ["neon", "shadow", "cyber", "phantom", "stealth", "matrix", "vector", "binary", "zero", "crypto"];
    const nouns = ["vault", "nexus", "bunker", "hub", "node", "relay", "sector", "zone", "cipher", "pulse"];
    const adj = adjectives[Math.floor(Math.random() * adjectives.length)];
    const noun = nouns[Math.floor(Math.random() * nouns.length)];
    const num = Math.floor(100 + Math.random() * 900);
    return `${adj}-${noun}-${num}`;
  }
}

window.e2eeCrypto = new E2EECrypto();
