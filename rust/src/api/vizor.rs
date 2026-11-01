use std::sync::{LazyLock, Mutex};

use pczt::roles::signer::{
    batch::{BatchSignRequest, BatchSignResponse},
    extract_orchard_spend_auth_signatures, Signer,
};
use rand::{rand_core::UnwrapErr, rngs::SysRng};
use sha2::Digest;
use ur_registry::{
    traits::RegistryItem,
    zcash::{
        zcash_accounts::ZcashAccounts, zcash_batch_sig_result::ZcashBatchSigResult,
        zcash_sign_batch::ZcashSignBatch,
        zcash_unified_full_viewing_key::ZcashUnifiedFullViewingKey,
    },
};
use zcash_keys::keys::UnifiedSpendingKey;
use zcash_protocol::consensus::Network;
use zip32::{fingerprint::SeedFingerprint, AccountId};

#[derive(Debug)]
enum CompactSignError {
    Parse(pczt::roles::low_level_signer::OrchardParseError),
    Sign(String),
}

impl From<pczt::roles::low_level_signer::OrchardParseError> for CompactSignError {
    fn from(error: pczt::roles::low_level_signer::OrchardParseError) -> Self {
        Self::Parse(error)
    }
}

const MAX_BATCH_CBOR_BYTES: usize = 80 * 1024;
const MAX_BATCH_MESSAGES: usize = 40;
const MAX_BATCH_SIGNATURES: usize = 96;
// Smaller fountain fragments produce materially lower-density QR symbols that
// desktop webcams can focus on reliably. The extra frames are preferable to a
// single dense response that cannot be recognized.
const QR_FRAGMENT_LENGTH: usize = 120;

struct ScanSession {
    decoder: ur::Decoder,
}

static SCAN_SESSION: LazyLock<Mutex<Option<ScanSession>>> = LazyLock::new(|| Mutex::new(None));

#[derive(Debug, Clone)]
pub struct UrScanProgress {
    pub complete: bool,
    pub progress: u32,
    pub cbor: Option<Vec<u8>>,
}

#[derive(Debug, Clone)]
pub struct BatchReview {
    pub request_id_hex: String,
    pub transaction_count: u32,
    pub orchard_spend_count: u32,
    pub ironwood_spend_count: u32,
    pub visible_output_total_zat: u64,
    pub outputs: Vec<String>,
    pub request_digest: String,
    pub warnings: Vec<String>,
}

#[derive(Debug, Clone)]
pub struct SignedBatch {
    pub request_id_hex: String,
    pub signature_count: u32,
    pub ur_parts: Vec<String>,
}

fn encode_ur_parts(cbor: &[u8], ur_type: &str) -> Result<Vec<String>, String> {
    let mut encoder = ur::Encoder::new(cbor, QR_FRAGMENT_LENGTH, ur_type)
        .map_err(|e| format!("UR encoder initialization failed: {e}"))?;
    let count = encoder.fragment_count();
    (0..count)
        .map(|_| {
            encoder
                .next_part()
                .map(|part| part.to_uppercase())
                .map_err(|e| format!("UR part encoding failed: {e}"))
        })
        .collect()
}

#[flutter_rust_bridge::frb(sync)]
pub fn reset_vizor_scan() {
    if let Ok(mut session) = SCAN_SESSION.lock() {
        *session = None;
    }
}

#[flutter_rust_bridge::frb(sync)]
pub fn receive_vizor_ur_part(part: String) -> Result<UrScanProgress, String> {
    let normalized = part.trim().to_lowercase();
    if !normalized.starts_with("ur:zcash-sign-batch/") {
        return Err("Expected a zcash-sign-batch QR from Vizor.".to_owned());
    }
    if let Ok((ur::ur::Kind::SinglePart, message)) = ur::decode(&normalized) {
        if message.len() > MAX_BATCH_CBOR_BYTES {
            return Err("Vizor signing request exceeds the 80 KiB safety limit.".to_owned());
        }
        return Ok(UrScanProgress {
            complete: true,
            progress: 100,
            cbor: Some(message),
        });
    }
    let mut guard = SCAN_SESSION
        .lock()
        .map_err(|_| "QR decoder state is unavailable".to_owned())?;
    let session = guard.get_or_insert_with(|| ScanSession {
        decoder: ur::Decoder::default(),
    });
    session
        .decoder
        .receive(&normalized)
        .map_err(|e| format!("Invalid animated QR part: {e}"))?;
    let progress = u32::from(session.decoder.progress());
    if !session.decoder.complete() {
        return Ok(UrScanProgress {
            complete: false,
            progress,
            cbor: None,
        });
    }
    let message = session
        .decoder
        .message()
        .map_err(|e| format!("Animated QR assembly failed: {e}"))?
        .ok_or_else(|| "Animated QR completed without a payload".to_owned())?;
    *guard = None;
    if message.len() > MAX_BATCH_CBOR_BYTES {
        return Err("Vizor signing request exceeds the 80 KiB safety limit.".to_owned());
    }
    Ok(UrScanProgress {
        complete: true,
        progress: 100,
        cbor: Some(message),
    })
}

fn decode_batch(cbor: Vec<u8>) -> Result<(ZcashSignBatch, BatchSignRequest), String> {
    if cbor.len() > MAX_BATCH_CBOR_BYTES {
        return Err("Vizor signing request exceeds the 80 KiB safety limit.".to_owned());
    }
    let envelope: ZcashSignBatch = cbor
        .try_into()
        .map_err(|e| format!("Invalid zcash-sign-batch envelope: {e:?}"))?;
    if envelope.get_request_id().is_empty() {
        return Err("Vizor signing request has no request id.".to_owned());
    }
    let request = BatchSignRequest::parse(envelope.get_data())
        .map_err(|e| format!("Invalid PCZT signing batch: {e:?}"))?;
    if request.pczts().is_empty() || request.pczts().len() > MAX_BATCH_MESSAGES {
        return Err("Vizor signing batch has an unsupported transaction count.".to_owned());
    }
    Ok((envelope, request))
}

#[flutter_rust_bridge::frb(sync)]
pub fn inspect_vizor_batch(cbor: Vec<u8>) -> Result<BatchReview, String> {
    let (envelope, request) = decode_batch(cbor.clone())?;
    let mut orchard_spends = 0usize;
    let mut ironwood_spends = 0usize;
    let mut visible_output_total = 0u64;
    let mut hidden_values = false;
    let mut outputs = Vec::new();
    for pczt in request.pczts() {
        if !pczt.transparent().inputs().is_empty() || !pczt.sapling().spends().is_empty() {
            return Err(
                "This signer currently accepts Orchard and Ironwood spends only.".to_owned(),
            );
        }
        orchard_spends += pczt
            .orchard()
            .actions()
            .iter()
            .filter(|action| action.spend().spend_auth_sig().is_none())
            .count();
        ironwood_spends += pczt
            .ironwood()
            .actions()
            .iter()
            .filter(|action| action.spend().spend_auth_sig().is_none())
            .count();
        for action in pczt
            .orchard()
            .actions()
            .iter()
            .chain(pczt.ironwood().actions().iter())
        {
            let value_label = action
                .output()
                .value()
                .map(|value| format!("{value} zat"))
                .unwrap_or_else(|| "redacted value".to_owned());
            let address = action
                .output()
                .user_address()
                .as_deref()
                .unwrap_or("redacted recipient");
            outputs.push(format!("{value_label} → {address}"));
            match action.output().value() {
                Some(value) => {
                    visible_output_total = visible_output_total
                        .checked_add(*value)
                        .ok_or_else(|| "Visible output total overflowed u64".to_owned())?;
                }
                None => hidden_values = true,
            }
        }
    }
    let signature_count = orchard_spends + ironwood_spends;
    if signature_count == 0 || signature_count > MAX_BATCH_SIGNATURES {
        return Err("Vizor signing batch has an unsupported signature count.".to_owned());
    }
    let mut warnings = vec![
        "Testnet only. Confirm the transaction details shown in Vizor before signing.".to_owned(),
    ];
    if hidden_values {
        warnings.push(
            "Some output values are redacted in the compact PCZT; the displayed total is incomplete."
                .to_owned(),
        );
    }
    Ok(BatchReview {
        request_id_hex: hex::encode(envelope.get_request_id()),
        transaction_count: request.pczts().len() as u32,
        orchard_spend_count: orchard_spends as u32,
        ironwood_spend_count: ironwood_spends as u32,
        visible_output_total_zat: visible_output_total,
        outputs,
        request_digest: hex::encode(sha2::Sha256::digest(&cbor)),
        warnings,
    })
}

#[flutter_rust_bridge::frb(sync)]
pub fn sign_vizor_batch(
    cbor: Vec<u8>,
    seed: Vec<u8>,
    account_index: u32,
) -> Result<SignedBatch, String> {
    if !(32..=252).contains(&seed.len()) {
        return Err("The wallet seed length is invalid.".to_owned());
    }
    // Re-run every policy check immediately before signing.
    inspect_vizor_batch(cbor.clone())?;
    let (envelope, request) = decode_batch(cbor)?;
    let account = AccountId::try_from(account_index)
        .map_err(|_| "The ZIP-32 account index is invalid.".to_owned())?;
    let usk = UnifiedSpendingKey::from_seed(&Network::TestNetwork, &seed, account)
        .map_err(|e| format!("Could not derive the testnet account key: {e}"))?;
    let ask = orchard::keys::SpendAuthorizingKey::from(usk.orchard());

    let mut all_signatures = Vec::with_capacity(request.pczts().len());
    for pczt in request.pczts().iter().cloned() {
        let orchard_indices = pczt
            .orchard()
            .actions()
            .iter()
            .enumerate()
            .filter_map(|(index, action)| {
                action.spend().spend_auth_sig().is_none().then_some(index)
            })
            .collect::<Vec<_>>();
        let ironwood_indices = pczt
            .ironwood()
            .actions()
            .iter()
            .enumerate()
            .filter_map(|(index, action)| {
                action.spend().spend_auth_sig().is_none().then_some(index)
            })
            .collect::<Vec<_>>();
        // The transported batch is intentionally compact and can omit spend FVKs.
        // Constructing the high-level signer still validates the PCZT structure and
        // gives us the canonical shielded sighash, but its Ironwood signing method
        // requires an FVK that the signature itself does not depend on. The crate's
        // low-level external-signer role is designed for this exact wire format.
        let sighash = Signer::new(pczt.clone())
            .map_err(|e| format!("PCZT failed signer validation: {e:?}"))?
            .shielded_sighash();
        let signed = pczt::roles::low_level_signer::Signer::new(pczt)
            .sign_orchard_with::<CompactSignError, _>(|_, bundle, _| {
                for &index in &orchard_indices {
                    bundle.actions_mut()[index]
                        .sign(sighash, &ask, UnwrapErr(SysRng))
                        .map_err(|e| {
                            CompactSignError::Sign(format!(
                                "Orchard spend {index} could not be signed: {e:?}"
                            ))
                        })?;
                }
                Ok(())
            })
            .and_then(|signer| {
                signer.sign_ironwood_with::<CompactSignError, _>(|_, bundle, _| {
                    for &index in &ironwood_indices {
                        bundle.actions_mut()[index]
                            .sign(sighash, &ask, UnwrapErr(SysRng))
                            .map_err(|e| {
                                CompactSignError::Sign(format!(
                                    "Ironwood spend {index} could not be signed: {e:?}"
                                ))
                            })?;
                    }
                    Ok(())
                })
            })
            .map_err(|e| match e {
                CompactSignError::Parse(error) => {
                    format!("Compact PCZT could not be parsed for signing: {error:?}")
                }
                CompactSignError::Sign(error) => error,
            })?
            .finish();
        all_signatures.push(extract_orchard_spend_auth_signatures(&signed));
    }
    let signature_count = all_signatures.iter().map(Vec::len).sum::<usize>();
    let response = BatchSignResponse::new(all_signatures)
        .serialize()
        .map_err(|e| format!("Could not encode PCZT signatures: {e:?}"))?;
    let result = ZcashBatchSigResult::new(envelope.get_request_id().to_vec(), response, [0, 1, 0]);
    let result_cbor: Vec<u8> = result
        .try_into()
        .map_err(|e| format!("Could not encode signature result CBOR: {e:?}"))?;
    Ok(SignedBatch {
        request_id_hex: hex::encode(envelope.get_request_id()),
        signature_count: signature_count as u32,
        ur_parts: encode_ur_parts(
            &result_cbor,
            &ZcashBatchSigResult::get_registry_type().get_type(),
        )?,
    })
}

#[flutter_rust_bridge::frb(sync)]
pub fn export_testnet_account(
    seed: Vec<u8>,
    account_index: u32,
    name: String,
) -> Result<Vec<String>, String> {
    let account = AccountId::try_from(account_index)
        .map_err(|_| "The ZIP-32 account index is invalid.".to_owned())?;
    let usk = UnifiedSpendingKey::from_seed(&Network::TestNetwork, &seed, account)
        .map_err(|e| format!("Could not derive the testnet account key: {e}"))?;
    let ufvk = usk
        .to_unified_full_viewing_key()
        .encode(&Network::TestNetwork);
    let fingerprint = SeedFingerprint::from_seed(&seed)
        .ok_or_else(|| "The wallet seed length is invalid for ZIP-32.".to_owned())?;
    let account =
        ZcashUnifiedFullViewingKey::new(ufvk, account_index, Some(name.trim().to_owned()));
    let accounts = ZcashAccounts::new(fingerprint.to_bytes().to_vec(), vec![account]);
    let cbor: Vec<u8> = accounts
        .try_into()
        .map_err(|e| format!("Could not encode account export CBOR: {e:?}"))?;
    encode_ur_parts(&cbor, &ZcashAccounts::get_registry_type().get_type())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn decode_parts(parts: &[String]) -> Vec<u8> {
        if parts.len() == 1 {
            return ur::decode(&parts[0]).unwrap().1;
        }
        let mut decoder = ur::Decoder::default();
        for part in parts {
            decoder.receive(&part.to_lowercase()).unwrap();
        }
        decoder.message().unwrap().unwrap()
    }

    #[test]
    fn exported_account_is_a_valid_testnet_zcash_accounts_ur() {
        let parts = export_testnet_account(vec![7; 64], 0, "Airgap phone".to_owned()).unwrap();
        let cbor = decode_parts(&parts);
        let accounts: ZcashAccounts = cbor.try_into().unwrap();
        assert_eq!(accounts.get_accounts().len(), 1);
        let account = &accounts.get_accounts()[0];
        assert_eq!(account.get_index(), 0);
        assert_eq!(account.get_name().as_deref(), Some("Airgap phone"));
        assert!(account.get_ufvk().starts_with("uviewtest"));
    }

    #[test]
    fn scanner_rejects_unrelated_ur_types() {
        let _scanner = crate::vizor_flow_tests::SCANNER_TEST.lock().unwrap();
        reset_vizor_scan();
        assert_eq!(
            receive_vizor_ur_part("ur:bytes/abcd".to_owned()).unwrap_err(),
            "Expected a zcash-sign-batch QR from Vizor."
        );
    }
}
