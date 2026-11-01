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
- Store the phrase using Android Keystore-backed encrypted storage.
- Export account 0's testnet UFVK as an animated `zcash-accounts` UR.
- Import that watch-only account into the compatible Vizor desktop prototype.
- Scan animated `zcash-sign-batch` requests containing compact PCZTs.
- Verify output commitments and recipient addresses before user approval.
- Sign account 0 Orchard and Ironwood spends.
- Return signatures as an animated `zcash-batch-sig-result` UR.
- Reject unverifiable outputs, wrong-network addresses, and unsupported pools.

Release and profile Android manifests do not request `INTERNET`. The debug
manifest requests it only so Flutter's development VM service and hot reload
can operate while the phone is connected for development.

## Requirements

- Linux, macOS, or Windows development host
- Flutter SDK compatible with Dart `^3.13.5`
- Rust stable toolchain with Android targets
- Android SDK, platform tools, NDK, and a USB-connected Android device
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
2. Open **Connect to Vizor** and display the animated account QR.
3. In the compatible Vizor desktop build, add an air-gapped signer and scan
   the account QR. Vizor imports viewing data only.
4. Fund the resulting address with testnet ZEC.
5. Create a send in Vizor and display its animated signing request.
6. In Zigner, choose **Scan signing request**, scan the animation, and verify
   the amount and destination on the phone.
7. Approve the request. Zigner displays an animated signature response.
8. Scan that response with Vizor to finalize and broadcast the transaction.

For an air-gap demonstration, disconnect USB after installing the app and put
the phone in airplane mode with Wi-Fi, Bluetooth, and NFC disabled. Do not
claim a production air gap while a development/debug connection is active.

## Build and test

```sh
flutter analyze
flutter test
cargo test --manifest-path rust/Cargo.toml
flutter build apk --debug
```

The debug APK is written beneath `build/app/outputs/flutter-apk/`.

### CI

Pushes and pull requests run Rust/Flutter checks and an Android signing flow:
wallet setup, account export, QR assembly, rejection, approval, signing, and
response display. The host verifies the emulator's returned signatures and
viewing key against the original PCZTs. CI also checks the ARM64 APK's packaged
permissions, debug flag, and native library.

Use a disposable emulator; the test clears its wallet. With the pinned toolchains:

```sh
RUSTUP_TOOLCHAIN=1.97.0 bash integration_test/run_android.sh emulator-5554
```

The fixture uses a public test mnemonic. Regenerate it with:

```sh
RUSTUP_TOOLCHAIN=1.97.0 cargo test --locked --manifest-path rust/Cargo.toml --lib \
  vizor_flow_tests::regenerate_signer_flow_fixture -- --ignored --exact
```

CI injects QR frames; optical scanning, proofs, broadcasting, and real-device
security remain separate checks. The release-mode APK retains prototype debug
signing. Toolchain versions are pinned in `.github/workflows/ci.yml`.

## Architecture

```text
lib/                         Flutter UI and workflow
lib/src/security/            Android-backed seed storage wrapper
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

- The seed is encrypted through Android Keystore-backed storage, but Zcash
  signing occurs in application memory. This is not equivalent to performing
  Zcash cryptography entirely inside StrongBox or a secure element.
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
