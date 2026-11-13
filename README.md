> **WARNING:** Once again adding, this is an early prototype. Please do not use
> it to custody any real funds. It is not safe for that purpose.

# Zigner

Zigner is a testnet-only, Android-first air-gapped signer prototype for Zcash.
It pairs with a watch-only desktop wallet over animated QR codes: the desktop
constructs a PCZT, the offline phone reviews and signs it, and the desktop
finalizes and broadcasts the transaction.

The interface is Flutter; PCZT parsing, validation, key derivation, and signing
are implemented in Rust and exposed through `flutter_rust_bridge`.

> **Warning**
>
> This is unaudited prototype software. It has no mainnet mode and must not be
> used to protect real funds. Review the limitations below before testing it.

## What works

- Create or import a BIP-39 recovery phrase.
- Create a 24-word signer with a mandatory written-backup check, or import an
  English BIP-39 phrase (12/15/18/21/24 words), with an optional BIP-39 passphrase.
- Encrypt the recovery entropy and optional passphrase with a non-exportable
  Android Keystore AES-256-GCM key. Prefer StrongBox, otherwise verify TEE-backed
  protection; refuse software-only keys. Require system authentication for each
  encryption and decryption operation.
- Follow the Quiet Vault onboarding: safety check, hidden recovery words,
  three native-validated backup questions, and Android authentication to save.
  Debug builds offer a quiz skip for development; release and profile builds
  reject this bypass in the native vault. Skipping leaves backup status unchecked.
- Unlock the app without releasing seed material to Flutter. Lock the session
  when it backgrounds; signing and account export still require fresh authentication.
- Practice a three-word paper-backup check without displaying the stored phrase.
  Imported signers show backup unchecked until this succeeds.
- Erase a signer only after a backup acknowledgement, typing `erase`, and
  authenticated vault decryption. Erasure destroys the Keystore key and local ciphertext.
- Export account 0's testnet UFVK as an animated `zcash-accounts` UR.
- Import that watch-only account into the compatible Vizor desktop prototype.
- Scan animated `zcash-sign-batch` requests containing compact PCZTs.
- Display transaction details for user approval.
- Sign account 0 Orchard and Ironwood spends.
- Return signatures as an animated `zcash-batch-sig-result` UR.
- Reject mainnet requests, transparent spends, and Sapling spends.

Release and profile Android manifests do not request `INTERNET`. The debug
manifest requests it only so Flutter's development VM service and hot reload
can operate while the phone is connected for development.

## Requirements

- Linux, macOS, or Windows development host
- Flutter SDK compatible with Dart `^3.13.5`
- Rust stable toolchain with Android targets
- Android SDK, platform tools, NDK, and an Android 11+ device with a secure
  screen lock and authenticated hardware-backed Android Keystore
- USB debugging enabled while developing

Confirm the local toolchain with:

```sh
flutter doctor -v
rustup show
adb devices
```

The first build compiles the Rust dependency graph and can take several
minutes.

## Run on an Android phone

1. Clone the repository and fetch dependencies:

   ```sh
   git clone https://github.com/zcashlabs/zigner.git
   cd zigner
   flutter pub get
   ```

2. Connect the phone over USB, unlock it, accept the debugging prompt, and
   check that Flutter can see it:

   ```sh
   flutter devices
   ```

3. Start a debug session (replace the ID with the value shown above):

   ```sh
   flutter run -d <device-id>
   ```

Press `r` in that terminal for hot reload and `R` for a full hot restart.
Changes to Rust code require a rebuild, not just hot reload.

## End-to-end demo

1. In Zigner, create or import a testnet signer wallet.
2. Open **Show account QR** and display the animated account QR.
3. In the compatible Vizor desktop build, add an air-gapped signer and scan
   the account QR. Vizor imports viewing data only.
4. Fund the resulting address with testnet ZEC.
5. Create a send in Vizor and display its animated signing request.
6. In Zigner, choose **Scan a request**, scan the animation, and verify
   the amount and destination on the phone.
7. Continue to signing and unlock with Android. Zigner displays an animated signature response.
8. Scan that response with Vizor to finalize and broadcast the transaction.

For an air-gap demonstration, disconnect USB after installing the app and put
the phone in airplane mode with Wi-Fi, Bluetooth, and NFC disabled. Do not
claim a production air gap while a development/debug connection is active.

## Build and test

```sh
flutter analyze
flutter test
(cd android && ./gradlew :app:testDebugUnitTest)
cargo test --manifest-path rust/Cargo.toml
flutter build apk --debug
```

The debug APK is written beneath `build/app/outputs/flutter-apk/`.
Release signing must be configured separately; release builds do not use the debug key.

For a real authenticated vault round-trip on a connected Android phone:

```sh
ORG_GRADLE_PROJECT_zignerVaultSelfTest=true flutter test --no-pub integration_test/vault_auth_test.dart -d <device-id>
```

This installs **Zigner vault self-test** under the separate `.vault_test` app ID.
It drives import and protection using a published BIP-39 test vector, then checks
authenticated decryption against the expected seed. Approve the two Android
authentication prompts on the phone; the test cannot replace physical authentication.
Start with a fresh self-test installation and uninstall that test app afterward.
The test refuses to run against the normal Zigner app and never replaces its vault.

## Architecture

```text
lib/                         Flutter UI and workflow
lib/src/security/            Vault routing, privacy shield, native vault client
android/app/src/main/kotlin/ Native BIP-39 and authenticated hardware-backed vault
lib/src/rust/                Generated Flutter/Rust bindings
rust/src/api/vizor.rs        Account export and PCZT signing API
rust/src/frb_generated.rs    Generated native bindings
rust_builder/                Cargokit native build integration
android/                     Android manifests and application wrapper
```

The QR protocol uses multipart URs so larger PCZTs and signature responses can
be transferred without a network connection. Requests are resolved and parsed
before signing; the phone derives account 0 keys for Zcash testnet and returns
spend-authorization signatures rather than a complete transaction.

## Security limitations

- The encryption key stays in StrongBox or the TEE; the encrypted recovery
  material stays in an atomic, versioned file in Android's no-backup directory.
  GCM authenticates the ciphertext and vault version. Cloud backup and device
  transfer are excluded. Screen capture and non-system overlays are blocked.
- Android's system biometric/credential prompt is bound to the actual cipher
  operation, with no authentication reuse window. A secure screen lock is
  required. Removing the lock can permanently invalidate the encryption key;
  recovery requires the paper phrase and, if used, the extra BIP-39 passphrase.
- The recovery phrase is shown only during creation. New setup is kept in
  memory until the backup check and authentication succeed. Leaving setup or
  backgrounding the app discards an idle, unsaved draft. Inputs disable
  autofill, suggestions, personalized keyboard learning, and copy actions.
- Existing prototype storage is upgraded explicitly. Its old copy is retained
  until the new vault is saved and successfully unlocked with authentication.
  Upgrades do not replace an existing native vault or silently create a new seed.
- Zcash signing and seed derivation still occur in application memory. Android
  secure elements do not expose the Zcash signing primitives. Native, Dart, and
  Rust byte buffers are cleared where owned; managed strings, channel/FFI copies,
  keyboard software, and garbage collectors prevent guaranteed memory erasure.
  Screenshot blocking also does not stop an external camera or a compromised OS.
- The project has not received an independent cryptographic or application
  security audit.
- Device compromise, debug builds, screen capture, malicious firmware, and
  supply-chain attacks are outside this prototype's protection boundary.
- Recovery phrase backup and secure device provisioning remain the user's
  responsibility.
- Only the prototype's account-0 testnet flow is supported.

Before production use, the project needs a documented threat model,
independent review of PCZT policy and display binding, reproducible release
builds, hardened device guidance, and audited key-management behavior.

The vault follows Android's [Keystore](https://developer.android.com/privacy-and-security/keystore)
and [auth-per-use key](https://developer.android.com/identity/sign-in/biometric-auth#auth-per-use-keys)
guidance. The bundled English word list comes from
[BIP-39](https://github.com/bitcoin/bips/blob/master/bip-0039/english.txt);
derivation tests use the public
[python-mnemonic vectors](https://github.com/trezor/python-mnemonic/blob/master/vectors.json).

## Interface reference

The Flutter interface follows the [shared Quiet Vault design and flow](https://claude.ai/artifact/K6FLFF44bMGzaUTnB2xMXL#page-dcb81aee8d83):
green-black surfaces, sage actions, Manrope headings, Inter body text, and
JetBrains Mono for recovery words and request identifiers. Fonts are bundled
for offline use; their OFL licenses are included in the app’s licenses screen.

Status labels reflect native capability checks, including the debug build’s
network permission. No sample amounts, fees, signer fingerprints, or QR payloads
from the reference are used. The current PCZT review cannot reliably distinguish
all change or reconstruct the full fee; it labels the visible-output total and
shows request warnings before signing. The app remains testnet-only.
