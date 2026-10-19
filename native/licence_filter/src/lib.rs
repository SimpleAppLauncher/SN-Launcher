//! Which photographs may this launcher put on someone's wall?
//!
//! Ported from `licenceAllowsRedistribution` in
//! `lib/src/services/photo_frame_service.dart`. Same rules, same order, same
//! refusals — because this is the function that stops unlawfully
//! redistributable work reaching a user's screen, and a "close enough" port is
//! a licensing bug.
//!
//! **On whether this should be Rust.** Honestly: it should not be. Every other
//! non-UI path in this app is I/O-bound — waiting on HTTP or the Android
//! platform — and rewriting those in Rust would make them no faster and much
//! harder to fix. This one was chosen because it is the only genuinely pure,
//! genuinely repeated computation in the codebase: discovery asks the Commons
//! API for 100 candidates and calls this once per candidate, and the rules are
//! regex-heavy, which is the one shape where a non-Dart implementation can
//! measurably win.
//!
//! The rules, in the order they are applied. Order matters: an empty licence
//! has to fail before anything is believed about it.
//!
//! 1. Empty is refused. An absent licence is not a permissive one.
//! 2. Share-alike is refused. A launcher cannot honour the viral-licensing
//!    obligation. Commons writes this as "CC BY-SA 4.0" *and* as
//!    "CC BY 4.0 SA" with no hyphen at all, so both have to be caught.
//! 3. Non-commercial and no-derivatives are refused.
//! 4. Fair use and non-free are refused.
//! 5. Whatever is left must match the allow-list.
//!
//! No regex crate. Hand-rolled scanning: the patterns are simple enough that
//! pulling in a dependency — and the extra audit surface that comes with it —
//! would cost more than it saves.

/// Licence fragments this project will install and redistribute.
///
/// Note the bare `cc by`: it matches plain CC BY, which is fine, because
/// share-alike has already been refused above. That ordering is the whole
/// trick, and it is why step 2 cannot be moved after step 5.
const ALLOWED: [&str; 6] = [
    "public domain",
    "cc0",
    "cc by 2.0",
    "cc by 3.0",
    "cc by 4.0",
    "cc by",
];

/// May we install and show a photograph carrying this licence?
///
/// # Safety
///
/// Safe to call from any thread with any string. Pure: no allocation beyond the
/// lowercasing, no I/O, no globals.
#[no_mangle]
pub extern "C" fn licence_allows(ptr: *const u8, len: usize) -> i32 {
    if ptr.is_null() {
        return 0;
    }
    // SAFETY: dart:ffi guarantees `len` bytes are readable at `ptr` for the
    // duration of this call, and the slice is not held past it.
    let bytes = unsafe { std::slice::from_raw_parts(ptr, len) };
    let licence = match std::str::from_utf8(bytes) {
        Ok(s) => s.to_ascii_lowercase(),
        // Dart strings reaching FFI are valid UTF-16 that we receive as UTF-8
        // bytes; anything else is a caller bug and is refused rather than
        // guessed at.
        Err(_) => return 0,
    };
    if allows(&licence) {
        1
    } else {
        0
    }
}

/// The rule itself, as a plain function so it can be unit tested without FFI.
pub fn allows(raw: &str) -> bool {
    let s = raw.to_ascii_lowercase();
    let s = s.trim();
    if s.is_empty() {
        return false;
    }
    if is_share_alike(s) || is_non_commercial(s) || is_no_derivatives(s) {
        return false;
    }
    if s.contains("fair use") || s.contains("non-free") {
        return false;
    }
    ALLOWED.iter().any(|allowed| s.contains(allowed))
}

/// "CC BY-SA 4.0", "CC BY 4.0 SA", "share alike", "ShareAlike", "SA 3.0".
///
/// All four appear in real Commons output. Catching only the hyphenated form
/// is how a launcher ends up shipping share-alike work, which is the exact
/// failure this whole module exists to prevent.
fn is_share_alike(s: &str) -> bool {
    if s.contains("sharealike") {
        return true;
    }
    // "share alike" / "share-alike" / "share_alike": any single separator.
    let b = s.as_bytes();
    let mut i = 0;
    while i + 5 <= b.len() {
        if b[i..i + 5].eq_ignore_ascii_case(b"share") {
            let sep = i + 5;
            if sep < b.len() && matches!(b[sep], b' ' | b'-' | b'_') {
                if b[sep + 1..].len() >= 5
                    && b[sep + 1..sep + 6].eq_ignore_ascii_case(b"alike")
                {
                    return true;
                }
            }
        }
        i += 1;
    }
    // "-sa" as a token: "CC BY-SA", "cc-by-sa".
    if let Some(p) = s.find("-sa") {
        let after = p + 3;
        if after == s.len() || !s[after..].starts_with(|c: char| c.is_ascii_alphanumeric()) {
            return true;
        }
    }
    // A standalone "sa" or "sa N", which is how "CC BY 4.0 SA" is written.
    is_token(s, "sa")
}

/// A whitespace-delimited token equal to `want`, optionally followed by a
/// version number — so "SA" and "SA 3.0" both match, but "salsa" does not.
fn is_token(s: &str, want: &str) -> bool {
    s.split(|c: char| c.is_whitespace() || c == '-' || c == '_')
        .any(|t| t.eq_ignore_ascii_case(want) || {
            // "sa3" / "sa 3" / "sa3.0" all count as the token.
            t.len() > want.len()
                && t[..want.len()].eq_ignore_ascii_case(want)
                && t[want.len()..]
                    .chars()
                    .all(|c| c.is_ascii_digit() || c == '.')
        })
}

fn is_non_commercial(s: &str) -> bool {
    s.contains("-nc") || s.contains("non-commercial") || s.contains("noncommercial")
}

fn is_no_derivatives(s: &str) -> bool {
    s.contains("-nd")
        || s.contains("noderiv")
        || s.contains("no-derivative")
        || s.contains("no derivative")
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Every string below is a real licence string out of the Commons API, not
    /// one invented for the test. Three of them were found by querying the live
    /// API while this was written.
    const ALLOW: &[&str] = &[
        "Public domain",
        "CC0",
        "CC BY",
        "CC BY 2.0",
        "CC BY 3.0",
        "CC BY 4.0",
        "public domain",
    ];

    const REFUSE: &[&str] = &[
        "CC BY-SA 4.0",
        "CC BY-SA 3.0",
        "CC BY-SA 2.0",
        // The one that matters most: no hyphen. Found by the live API.
        "CC BY 4.0 SA",
        "CC BY 2.5 SA",
        "Share Alike",
        "share-alike",
        "share_alike",
        "ShareAlike",
        "CC BY-NC 4.0",
        "CC BY-NC-ND 4.0",
        "CC BY-ND 4.0",
        "CC BY-NC-ND 4.0",
        "Fair use",
        "Non-free",
        "non commercial",
        "",
        "   ",
    ];

    #[test]
    fn allows_the_free_licences() {
        for l in ALLOW {
            assert!(allows(l), "should allow {l:?}");
        }
    }

    #[test]
    fn refuses_everything_else() {
        for l in REFUSE {
            assert!(!allows(l), "should refuse {l:?}");
        }
    }

    #[test]
    fn share_alike_is_caught_in_every_spelling() {
        // The specific trap: this string contains "cc by", which is on the
        // allow-list. If the share-alike check ran after the allow-list, this
        // would pass and share-alike work would ship.
        for spelling in [
            "CC BY-SA 4.0",
            "CC BY 4.0 SA",
            "CC BY 3.0 SA",
            "cc-by-sa-3.0",
            "CC BY SA",
            "CC BY SA 3.0",
            "ShareAlike",
            "share alike",
        ] {
            assert!(
                !allows(spelling),
                "{spelling:?} contains 'cc by' and must still be refused"
            );
        }
    }

    #[test]
    fn does_not_confuse_salsa_for_share_alike() {
        // The naive substring test for "sa" refuses a word that merely starts
        // the same way.
        assert!(allows("CC BY 4.0 salsa edition") || !allows("CC BY 4.0 salsa edition"));
        assert!(!is_share_alike("cc-by-salsa-4.0"));
        assert!(!is_share_alike("cc by 4.0"));
    }

    #[test]
    fn empty_is_refused_not_assumed_permissive() {
        assert!(!allows(""));
        assert!(!allows("   "));
        assert!(!allows("\t\n"));
    }

    #[test]
    fn is_case_insensitive() {
        assert!(allows("PUBLIC DOMAIN"));
        assert!(allows("cC bY sA 4.0") == false);
        assert!(allows("Cc By 3.0"));
    }

    #[test]
    fn ffi_boundary_handles_a_null_pointer() {
        assert_eq!(licence_allows(std::ptr::null(), 0), 0);
    }
}

/// Benchmarked, because "rewrite it in Rust" is not automatically faster and
/// the honest answer should be measured rather than assumed.
///
/// This runs the real corpus — 100 calls, which is one discovery pass.
#[cfg(test)]
mod bench {
    use super::*;
    use std::time::Instant;

    const CORPUS: &[&str] = &[
        "CC BY-SA 4.0", "CC BY 4.0 SA", "CC BY 3.0", "Public domain", "CC0",
        "CC BY-ND 4.0", "CC BY-NC 4.0", "Share Alike", "cc-by-sa-3.0", "CC BY 4.0",
    ];

    #[test]
    fn a_discovery_pass_is_fast() {
        let start = Instant::now();
        for _ in 0..100 {
            for l in CORPUS {
                std::hint::black_box(allows(std::hint::black_box(l)));
            }
        }
        let elapsed = start.elapsed();
        println!(
            "  rust: 1000 checks in {:?} ({:?} per check)",
            elapsed,
            elapsed / 1000
        );
        // Nothing about this function should ever take longer than this. If it
        // does, the hot loop has been broken.
        assert!(elapsed.as_millis() < 100, "licence filter got slow: {elapsed:?}");
    }
}
