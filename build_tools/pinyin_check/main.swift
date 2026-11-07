import Foundation

// Exercises the real PinyinFormatter from the app target.
let pinyinCases: [(String, String)] = [
    ("chuan2 tong3", "chuán tǒng"),
    ("zhong1 guo2", "zhōng guó"),
    ("ni3 hao3", "nǐ hǎo"),
    ("lv4", "lǜ"),
    ("nu:3", "nǚ"),
    ("xie4 xie5", "xiè xie"),
    ("Beijing", "Beijing"),
    ("hao3", "hǎo"),
    ("liu2", "liú"),
    ("gui4", "guì"),
]

var failures = 0
for (input, expected) in pinyinCases {
    let got = PinyinFormatter.diacritic(for: input)
    let ok = got == expected
    if !ok { failures += 1 }
    print("\(ok ? "PASS" : "FAIL")  \(input) -> \(got)  (expected \(expected))")
}

print(failures == 0 ? "\nALL PINYIN PASS" : "\n\(failures) PINYIN FAILURES")
exit(failures == 0 ? 0 : 1)
