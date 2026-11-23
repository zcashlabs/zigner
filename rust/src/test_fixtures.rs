//! Test-only builders for Vizor `zcash-sign-batch` requests.
//!
//! The PCZTs are built with the same transaction builder and PCZT roles that
//! wallets use, so the tests exercise real Orchard actions rather than
//! hand-assembled bytes.

use std::convert::Infallible;

use orchard::{
    keys::{FullViewingKey, Scope, SpendingKey},
    note::{ExtractedNoteCommitment, NoteVersion, RandomSeed, Rho},
    tree::{MerkleHashOrchard, MerklePath},
    value::NoteValue,
};
use pczt::{
    roles::{creator::Creator, io_finalizer::IoFinalizer, signer::batch::BatchSignRequest},
    Pczt,
};
use rand::{rand_core::UnwrapErr, rngs::SysRng};
use transparent::address::TransparentAddress;
use ur_registry::zcash::zcash_sign_batch::ZcashSignBatch;
use zcash_keys::keys::UnifiedSpendingKey;
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
const EXTRA_OUTPUT_VALUE: u64 = 50_000;
const FEE: u64 = 10_000;

/// A pool that a coordinator could attach an output to without Zigner showing it.
#[derive(Clone, Copy)]
pub(crate) enum ExtraOutput {
    None,
    Transparent,
    Sapling,
}

fn account_fvk() -> FullViewingKey {
    let usk = UnifiedSpendingKey::from_seed(&Network::TestNetwork, &SEED, AccountId::ZERO)
        .expect("test seed derives a USK");
    FullViewingKey::from(usk.orchard())
}

pub(crate) fn payee_address() -> orchard::Address {
    let sk = SpendingKey::from_bytes([1; 32]).expect("valid Orchard spending key");
    FullViewingKey::from(&sk).address_at(0u32, Scope::External)
}

/// Builds an IO-finalized PCZT that spends one account-0 note in the Ironwood
/// pool to an Ironwood payee and change, plus an optional output in another pool.
///
/// Ironwood is used because NU6.3 disables cross-address transfers in the
/// Orchard pool; Zigner reviews and signs both pools identically.
pub(crate) fn build_pczt(extra: ExtraOutput) -> Pczt {
    let fvk = account_fvk();
    let own_address = fvk.address_at(0u32, Scope::External);
    let rho = Rho::from_bytes(&[0; 32]).unwrap();
    let rseed = RandomSeed::from_bytes([42; 32], &rho).unwrap();
    let note = orchard::Note::from_parts(
        own_address,
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
            sapling_anchor: Some(sapling::Anchor::empty_tree()),
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
    let extra_value = match extra {
        ExtraOutput::None => 0,
        ExtraOutput::Transparent => {
            builder
                .add_transparent_output(
                    &TransparentAddress::PublicKeyHash([0x42; 20]),
                    Zatoshis::const_from_u64(EXTRA_OUTPUT_VALUE),
                )
                .unwrap();
            EXTRA_OUTPUT_VALUE
        }
        ExtraOutput::Sapling => {
            let (_, address) = sapling::zip32::ExtendedSpendingKey::master(&[9; 32])
                .to_diversifiable_full_viewing_key()
                .default_address();
            builder
                .add_sapling_output::<Infallible>(
                    None,
                    address,
                    Zatoshis::const_from_u64(EXTRA_OUTPUT_VALUE),
                    MemoBytes::empty(),
                )
                .unwrap();
            EXTRA_OUTPUT_VALUE
        }
    };
    builder
        .add_ironwood_output::<Infallible>(
            None,
            fvk.address_at(0u32, Scope::Internal),
            Zatoshis::const_from_u64(NOTE_VALUE - PAYMENT_VALUE - extra_value - FEE),
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
    IoFinalizer::new(pczt).finalize_io().unwrap()
}

/// Wraps PCZTs in the `zcash-sign-batch` CBOR envelope that Vizor displays.
pub(crate) fn sign_batch_cbor(pczts: Vec<Pczt>) -> Vec<u8> {
    let data = BatchSignRequest::new(pczts).serialize().unwrap();
    ZcashSignBatch::new(vec![0xab; 16], data)
        .try_into()
        .unwrap()
}
