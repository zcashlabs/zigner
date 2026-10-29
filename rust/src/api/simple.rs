use serde::Deserialize;
use sha2::{Digest, Sha256};

const MAX_REQUEST_BYTES: usize = 16 * 1024;
const MAX_MEMO_BYTES: usize = 512;

#[derive(Debug, Clone)]
pub struct TransactionReview {
    pub network: String,
    pub transaction_kind: String,
    pub recipient: String,
    pub amount_zat: u64,
    pub fee_zat: u64,
    pub memo: Option<String>,
    pub change_zat: u64,
    pub request_digest: String,
    pub warnings: Vec<String>,
}

#[derive(Debug, Clone)]
pub struct DemoSignature {
    pub request_digest: String,
    pub signature_payload: String,
    pub warning: String,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct DemoRequest {
    network: String,
    transaction_kind: String,
    recipient: String,
    amount_zat: u64,
    fee_zat: u64,
    #[serde(default)]
    memo: Option<String>,
    #[serde(default)]
    change_zat: u64,
}

#[flutter_rust_bridge::frb(sync)]
pub fn inspect_demo_request(payload: String) -> Result<TransactionReview, String> {
    if payload.is_empty() {
        return Err("The signing request is empty.".to_owned());
    }
    if payload.len() > MAX_REQUEST_BYTES {
        return Err(format!(
            "The signing request exceeds the {MAX_REQUEST_BYTES}-byte prototype limit."
        ));
    }

    let request: DemoRequest = serde_json::from_str(&payload)
        .map_err(|error| format!("Invalid prototype signing request: {error}"))?;

    if request.network != "testnet" {
        return Err("This prototype signs testnet requests only.".to_owned());
    }
    if !matches!(
        request.transaction_kind.as_str(),
        "shielded" | "transparent" | "shielding" | "deshielding"
    ) {
        return Err("Unsupported transaction kind.".to_owned());
    }
    if request.recipient.len() < 16 || request.recipient.len() > 512 {
        return Err("Recipient length is outside the accepted range.".to_owned());
    }
    if request.amount_zat == 0 {
        return Err("Transaction amount must be greater than zero.".to_owned());
    }
    if request.fee_zat > request.amount_zat {
        return Err("The fee cannot exceed the payment amount in this prototype.".to_owned());
    }
    if request
        .memo
        .as_ref()
        .is_some_and(|memo| memo.len() > MAX_MEMO_BYTES)
    {
        return Err(format!(
            "Memo exceeds the {MAX_MEMO_BYTES}-byte Zcash memo limit."
        ));
    }

    let mut warnings =
        vec!["Prototype envelope: this is not a real PCZT and cannot move funds.".to_owned()];
    if request.transaction_kind == "transparent" {
        warnings.push("Transparent transactions reveal sender and recipient activity.".to_owned());
    }
    if request.fee_zat > 100_000 {
        warnings.push("The requested fee is unusually high for this demo.".to_owned());
    }

    let request_digest = hex::encode(Sha256::digest(payload.as_bytes()));

    Ok(TransactionReview {
        network: request.network,
        transaction_kind: request.transaction_kind,
        recipient: request.recipient,
        amount_zat: request.amount_zat,
        fee_zat: request.fee_zat,
        memo: request.memo,
        change_zat: request.change_zat,
        request_digest,
        warnings,
    })
}

#[flutter_rust_bridge::frb(sync)]
pub fn create_demo_signature(request_digest: String) -> Result<DemoSignature, String> {
    if request_digest.len() != 64 || !request_digest.bytes().all(|byte| byte.is_ascii_hexdigit()) {
        return Err("Invalid request digest.".to_owned());
    }

    let signature = Sha256::digest(format!("ZCASH_SIGNER_DEMO:{request_digest}").as_bytes());
    Ok(DemoSignature {
        request_digest,
        signature_payload: format!("ur:zcash-demo-signature/{}", hex::encode(signature)),
        warning: "DEMO ONLY — this is not a cryptographic Zcash signature.".to_owned(),
    })
}

#[flutter_rust_bridge::frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();
}

#[cfg(test)]
mod tests {
    use super::*;

    const VALID_REQUEST: &str = r#"{
        "network":"testnet",
        "transaction_kind":"shielded",
        "recipient":"utest1prototypeaddress0000000000000000000000000000000000",
        "amount_zat":12340000,
        "fee_zat":10000,
        "memo":"Hello from the offline signer",
        "change_zat":42000000
    }"#;

    #[test]
    fn reviews_valid_request() {
        let review = inspect_demo_request(VALID_REQUEST.to_owned()).unwrap();
        assert_eq!(review.network, "testnet");
        assert_eq!(review.amount_zat, 12_340_000);
        assert_eq!(review.request_digest.len(), 64);
    }

    #[test]
    fn rejects_mainnet_request() {
        let payload = VALID_REQUEST.replace("testnet", "mainnet");
        assert_eq!(
            inspect_demo_request(payload).unwrap_err(),
            "This prototype signs testnet requests only."
        );
    }

    #[test]
    fn demo_signature_is_bound_to_digest() {
        let review = inspect_demo_request(VALID_REQUEST.to_owned()).unwrap();
        let signature = create_demo_signature(review.request_digest.clone()).unwrap();
        assert_eq!(signature.request_digest, review.request_digest);
        assert!(signature
            .signature_payload
            .starts_with("ur:zcash-demo-signature/"));
    }
}
