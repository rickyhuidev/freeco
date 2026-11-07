import Foundation
import CoreGraphics

// Exercises the app's real ChineseDictionary (segmentation + lookup) and
// TextLayout (line joining + sentence splitting) against the bundled TSV.
// Run from the repo root; see README for the swiftc command.

var failures = 0
func check<T: Equatable>(_ label: String, _ got: T, _ expected: T) {
    let ok = got == expected
    if !ok { failures += 1 }
    print("\(ok ? "PASS" : "FAIL")  \(label)\(ok ? "" : "\n      got:      \(got)\n      expected: \(expected)")")
}

let tsvPath = "ChineseOCR/Assets.xcassets/cedict.dataset/cedict.tsv"
guard let tsv = try? String(contentsOfFile: tsvPath, encoding: .utf8) else {
    print("cannot read \(tsvPath) (run from the repo root)")
    exit(1)
}
let dictionary = ChineseDictionary.shared
dictionary.load(tsv: tsv)

// MARK: Segmentation

func words(_ s: String) -> [String] { dictionary.segment(s).map(\.text) }
check("segment simplified", words("我是中国人。"), ["我", "是", "中国人", "。"])
check("segment traditional", words("這是傳統中文的句子。"), ["這", "是", "傳統", "中文", "的", "句子", "。"])
check("segment sentence", words("我们今天去北京看长城。"), ["我们", "今天", "去", "北京", "看", "长城", "。"])
check("non-Chinese run is one segment", words("iPhone 18很漂亮"), ["iPhone 18", "很", "漂亮"])

// MARK: Lookup

check("lookup by traditional", dictionary.entries(for: "傳統").first?.pinyin, "chuán tǒng")
check("lookup by simplified", dictionary.entries(for: "长城").first?.pinyin, "Cháng chéng")

// MARK: Line joining (normalized boxes, origin bottom-left, portrait 3:4 photo)

let aspect: CGFloat = 0.75
func line(_ text: String, x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat = 0.04) -> RecognizedLine {
    RecognizedLine(text: text, box: CGRect(x: x, y: y, width: w, height: h))
}

check("wrapped paragraph joins",
      TextLayout.paragraphs(from: [
          line("今天天气很好，我们一起去", x: 0.10, y: 0.80, w: 0.80),
          line("公园散步吧。", x: 0.10, y: 0.75, w: 0.40),
      ], imageAspect: aspect),
      ["今天天气很好，我们一起去公园散步吧。"])

check("indented first line joins",
      TextLayout.paragraphs(from: [
          line("今天天气很好我们去", x: 0.16, y: 0.80, w: 0.60),
          line("公园。", x: 0.10, y: 0.75, w: 0.20),
      ], imageAspect: aspect),
      ["今天天气很好我们去公园。"])

check("menu items stay separate",
      TextLayout.paragraphs(from: [
          line("宫保鸡丁", x: 0.10, y: 0.60, w: 0.25),
          line("红烧肉", x: 0.10, y: 0.54, w: 0.20),
          line("麻婆豆腐", x: 0.10, y: 0.48, w: 0.25),
      ], imageAspect: aspect),
      ["宫保鸡丁", "红烧肉", "麻婆豆腐"])

check("sentence end breaks paragraph",
      TextLayout.paragraphs(from: [
          line("这是第一段的最后一句。", x: 0.10, y: 0.80, w: 0.80),
          line("这是第二段的第一句话", x: 0.10, y: 0.75, w: 0.80),
      ], imageAspect: aspect),
      ["这是第一段的最后一句。", "这是第二段的第一句话"])

check("heading stays separate from body",
      TextLayout.paragraphs(from: [
          line("欢迎来到北京动物园", x: 0.10, y: 0.85, w: 0.80, h: 0.08),
          line("开放时间为早上八点到下午五点", x: 0.10, y: 0.79, w: 0.80),
      ], imageAspect: aspect),
      ["欢迎来到北京动物园", "开放时间为早上八点到下午五点"])

check("far-apart lines stay separate",
      TextLayout.paragraphs(from: [
          line("出口在左边请注意安全", x: 0.10, y: 0.80, w: 0.80),
          line("小心地滑请慢慢走", x: 0.10, y: 0.40, w: 0.70),
      ], imageAspect: aspect),
      ["出口在左边请注意安全", "小心地滑请慢慢走"])

// MARK: Sentences

check("closing quote stays with its sentence",
      TextLayout.sentences(in: "他说：“你好。”我们走吧！"), ["他说：“你好。”", "我们走吧！"])
check("stacked terminators stay together",
      TextLayout.sentences(in: "真的吗？！是的。"), ["真的吗？！", "是的。"])
check("no punctuation is one sentence",
      TextLayout.sentences(in: "没有标点"), ["没有标点"])

print(failures == 0 ? "\nALL TEXT CHECKS PASS" : "\n\(failures) TEXT CHECK FAILURES")
exit(failures == 0 ? 0 : 1)
