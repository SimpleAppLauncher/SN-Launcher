// Prints the Rust verdict for each line of a licence corpus, so it can be
// diffed against the Dart implementation's. A divergence here is a licensing
// bug, not a performance one, so this is checked rather than assumed.
use std::io::BufRead;

fn main() {
    let stdin = std::io::stdin();
    for line in stdin.lock().lines() {
        let l = line.unwrap();
        if l.trim().is_empty() {
            continue;
        }
        println!("{}\t{}", licence_filter::allows(&l), l);
    }
}
