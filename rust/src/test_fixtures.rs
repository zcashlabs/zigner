//! Test-only builders for Vizor `zcash-sign-batch` requests.
//!
//! The PCZTs are built with the same transaction builder and PCZT roles that
//! wallets use, so the tests exercise real Orchard-protocol actions rather than
//! hand-assembled bytes.

use std::convert::Infallible;

use orchard::{
    keys::{FullViewingKey, Scope, SpendingKey},
    note::{ExtractedNoteCommitment, NoteVersion, RandomSeed, Rho},
    tree::{MerkleHashOrchard, MerklePath},
    value::NoteValue,
};
use pczt::{
    roles::{
        creator::Creator, io_finalizer::IoFinalizer, redactor::Redactor,
        signer::batch::BatchSignRequest, updater::Updater,
    },
    Pczt,
};
use rand::{rand_core::UnwrapErr, rngs::SysRng};
use ur_registry::zcash::zcash_sign_batch::ZcashSignBatch;
use zcash_keys::{address::UnifiedAddress, keys::UnifiedSpendingKey};
use zcash_primitives::transaction::{
    builder::{BuildConfig, Builder, BundlePadding, PcztResult},
    fees::fixed,
};
use zcash_protocol::{consensus::Network, memo::MemoBytes, value::Zatoshis};
use zip32::AccountId;

/// The seed whose account-0 Orchard key owns the spent note.
pub(crate) const SEED: [u8; 64] = [7; 64];
/// A testnet height at which NU6.3 (v6 transactions) is active.
const TARGET_HEIGHT: u32 = 4_200_000;
const NOTE_VALUE: u64 = 1_000_000;
pub(crate) const PAYMENT_VALUE: u64 = 250_000;
pub(crate) const CHANGE_VALUE: u64 = NOTE_VALUE - PAYMENT_VALUE - FEE;
const FEE: u64 = 10_000;

fn account_fvk() -> FullViewingKey {
    let usk = UnifiedSpendingKey::from_seed(&Network::TestNetwork, &SEED, AccountId::ZERO)
        .expect("test seed derives a USK");
    FullViewingKey::from(usk.orchard())
}

fn encode_testnet(address: orchard::Address) -> String {
    UnifiedAddress::from_receivers(Some(address), None)
        .expect("an Orchard receiver forms a unified address")
        .encode(&Network::TestNetwork)
}

fn payee_address() -> orchard::Address {
    let sk = SpendingKey::from_bytes([1; 32]).expect("valid Orchard spending key");
    FullViewingKey::from(&sk).address_at(0u32, Scope::External)
}

/// The testnet unified address the wallet shows for the payee.
pub(crate) fn payee_user_address() -> String {
    encode_testnet(payee_address())
}

/// The victim's own external address, which an attacker could claim to pay.
pub(crate) fn own_user_address() -> String {
    encode_testnet(account_fvk().address_at(0u32, Scope::External))
}

/// The testnet unified address for the account's internal (change) receiver.
pub(crate) fn change_address() -> String {
    encode_testnet(account_fvk().address_at(0u32, Scope::Internal))
}

/// Builds an IO-finalized PCZT that spends one account-0 note in the Ironwood
/// pool to an Ironwood payee and change. The payee output carries a
/// `user_address`, as wallets set for external recipients; change does not.
///
/// Ironwood is used because NU6.3 disables cross-address transfers in the
/// Orchard pool; Zigner reviews and signs both pools identically.
pub(crate) fn build_pczt() -> Pczt {
    let fvk = account_fvk();
    let rho = Rho::from_bytes(&[0; 32]).unwrap();
    let rseed = RandomSeed::from_bytes([42; 32], &rho).unwrap();
    let note = orchard::Note::from_parts(
        fvk.address_at(0u32, Scope::External),
        NoteValue::from_raw(NOTE_VALUE),
        rho,
        rseed,
        NoteVersion::V3,
    )
    .unwrap();
    let cmx = ExtractedNoteCommitment::from(note.commitment());
    let merkle_path = MerklePath::from_parts(0, [MerkleHashOrchard::from_cmx(&cmx); 32]);
    let anchor = merkle_path.root(cmx);

    let mut builder = Builder::new(
        Network::TestNetwork,
        TARGET_HEIGHT.into(),
        BuildConfig::Standard {
            sapling_anchor: None,
            orchard_anchor: None,
            ironwood_anchor: Some(anchor),
            orchard_padding: BundlePadding::DEFAULT,
            ironwood_padding: BundlePadding::DEFAULT,
        },
    );
    builder
        .add_ironwood_spend::<Infallible>(fvk.clone(), note, merkle_path)
        .unwrap();
    builder
        .add_ironwood_output::<Infallible>(
            None,
            payee_address(),
            Zatoshis::const_from_u64(PAYMENT_VALUE),
            MemoBytes::empty(),
        )
        .unwrap();
    builder
        .add_ironwood_output::<Infallible>(
            None,
            fvk.address_at(0u32, Scope::Internal),
            Zatoshis::const_from_u64(CHANGE_VALUE),
            MemoBytes::empty(),
        )
        .unwrap();

    let PcztResult { pczt_parts, .. } = builder
        .build_for_pczt(
            UnwrapErr(SysRng),
            &fixed::FeeRule::non_standard(Zatoshis::const_from_u64(FEE)),
        )
        .unwrap();
    let pczt = Creator::build_from_parts(pczt_parts).expect("v6 PCZT");
    let pczt = IoFinalizer::new(pczt).finalize_io().unwrap();
    let payee = payee_action_index(&pczt);
    set_user_address(pczt, payee, payee_user_address())
}

/// Returns the index of the Ironwood action that pays the payee.
pub(crate) fn payee_action_index(pczt: &Pczt) -> usize {
    action_paying(pczt, PAYMENT_VALUE)
}

fn action_paying(pczt: &Pczt, value: u64) -> usize {
    pczt.ironwood()
        .actions()
        .iter()
        .position(|action| *action.output().value() == Some(value))
        .expect("an Ironwood action pays this value")
}

/// Sets an Ironwood action's `user_address`, as any Updater may.
pub(crate) fn set_user_address(pczt: Pczt, index: usize, user_address: String) -> Pczt {
    Updater::new(pczt)
        .update_ironwood_with(|mut updater| {
            updater.update_action_with(index, |mut action| {
                action.set_output_user_address(user_address);
                Ok(())
            })
        })
        .unwrap()
        .finish()
}

/// Applies the compact batch-signer view that Vizor sends (librustzcash's
/// `redact_pczt_for_batch_signer`): spend FVKs, witnesses, proof, binding key
/// and anchor are removed, and `cv_net` / `cmx` are compacted so the receiver
/// must recompute them from `recipient`, `value`, `rseed` and `rcv`.
///
/// Unlike Vizor, the IO finalizer's padding-spend signature is kept, because
/// these fixtures pad with a random dummy key rather than a wallet-owned note.
pub(crate) fn vizor_compact_view(pczt: Pczt) -> Pczt {
    Redactor::new(pczt)
        .redact_ironwood_with(|mut bundle| {
            bundle.clear_zkproof();
            bundle.clear_bsk();
            bundle.redact_actions(|mut action| {
                action.clear_spend_witness();
                action.clear_spend_fvk();
            });
            bundle.compact_resolvable_fields();
            bundle.clear_anchor();
        })
        .finish()
}

/// Rewrites the payee output's `value` field in the serialized PCZT while
/// keeping its `cmx` and `cv_net`, which is what a malicious coordinator would
/// send. The PCZT role APIs deliberately offer no setter for this field.
pub(crate) fn spoof_payee_value(pczt: Pczt, spoofed: u64) -> Pczt {
    let original = postcard_option_u64(PAYMENT_VALUE);
    let replacement = postcard_option_u64(spoofed);
    assert_eq!(
        original.len(),
        replacement.len(),
        "keep the encoding length"
    );

    let mut bytes = pczt.serialize().unwrap();
    let positions = bytes
        .windows(original.len())
        .enumerate()
        .filter(|(_, window)| *window == original.as_slice())
        .map(|(position, _)| position)
        .collect::<Vec<_>>();
    assert_eq!(positions.len(), 1, "the payee value must be unambiguous");
    bytes[positions[0]..positions[0] + original.len()].copy_from_slice(&replacement);
    let spoofed_pczt = Pczt::parse(&bytes).unwrap();
    let payee = &spoofed_pczt.ironwood().actions()[action_paying(&spoofed_pczt, spoofed)];
    assert!(payee.output().cmx().is_some(), "cmx must stay committed");
    spoofed_pczt
}

/// Postcard encodes `Some(u64)` as a 0x01 tag followed by a LEB128 varint.
fn postcard_option_u64(mut value: u64) -> Vec<u8> {
    let mut bytes = vec![0x01];
    loop {
        let byte = (value & 0x7f) as u8;
        value >>= 7;
        if value == 0 {
            bytes.push(byte);
            return bytes;
        }
        bytes.push(byte | 0x80);
    }
}

/// Wraps PCZTs in the `zcash-sign-batch` CBOR envelope that Vizor displays.
pub(crate) fn sign_batch_cbor(pczts: Vec<Pczt>) -> Vec<u8> {
    let data = BatchSignRequest::new(pczts).serialize().unwrap();
    ZcashSignBatch::new(vec![0xab; 16], data)
        .try_into()
        .unwrap()
}
