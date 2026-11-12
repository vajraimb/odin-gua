# 经文来源与校勘 / Sources and collation

`zhouyi.txt`（中文）与 `legge.txt`（英文）共 450 条：64 卦辞 + 384 爻辞 + 用九、用六。只收经文，不收彖、象、文言、十翼。

The two files hold 450 entries: 64 judgments, 384 line texts, and the two extra texts for hexagrams 1 and 2 (用九 / 用六). Only the classic itself is included; no commentaries (Ten Wings).

逐条来源见 `provenance.tsv`（hex, line, zh_source, en_source, note）。Per-entry provenance is in `provenance.tsv`.

## 中文 / Chinese

- 底本：[中國哲學書電子化計劃 ctext](https://ctext.org/book-of-changes)（武英殿本《周易正義》），保留其标点；繁体。432 条直接取自底本。
- 校本：[維基文庫《周易》](https://zh.wikisource.org/wiki/周易)、[《周易》四部叢刊本](https://zh.wikisource.org/wiki/周易_(四部叢刊本))、[Project Gutenberg #25501](https://www.gutenberg.org/cache/epub/25501/pg25501.txt)。
- 改字规则：仅当三个校本**一致**且与底本不同时才改（4 处）：
  - 35 九四「鼫」（底本「碩」）
  - 36 六四「于出門庭」（底本「出于門庭」）
  - 37 九五「勿恤，吉」（底本「勿恤，往吉」）
  - 41 上九「利有攸往」（底本脫「利」）
- 31 卦辭：底本冠卦名「咸，」，已去，与其余各卦体例一致。
- 38 睽、40 解：底本缺，取自維基文庫；38 六三從 PG+四部叢刊作「掣」，上九作「塗」；40 六五從 PG 作「維」。
- 底本特有用字保留并在 note 里注明：14「祐」、20/55「闚」、24「祗」、26「曰」、41/49「巳」、47「享」。異文（維基文庫「一作」）一并记在 note，不进正文。

## English

- James Legge, *The Yî King*, Sacred Books of the East vol. 16 (Oxford, 1882). Public domain ([Wikipedia](https://en.wikipedia.org/wiki/Sacred_Books_of_the_East)).
- 194 entries (hexagrams 1–32) come from the proofread transcription on [English Wikisource](https://en.wikisource.org/wiki/Sacred_Books_of_the_East/Volume_16), used only where it agrees ≥ 90% with the OCR vote below.
- 256 entries come from a word-level majority vote across three independent archive.org scans: [IGNCA 20915](https://archive.org/download/in.gov.ignca.20915/20915_djvu.txt), [wg916](https://archive.org/details/wg916), and the Motilal Banarsidass reprint (`sacredbooksofeas0000fmax`, vol. 16).
- Hexagram names keep Legge's romanisation with diacritics (Khien, Khwăn, Kî Ȝî …), checked against the [sacred-texts.com index](https://sacred-texts.com/ich/index.htm) used as a spelling reference only.
- Normalisation: italics dropped; ASCII quotes; em dash written as `--`; yogh written as `Ȝ`. Legge's bracketed glosses are kept verbatim.
- Known residual risk: Wikisource proofreading stops at hexagram 33, so 33–64 rest on the OCR vote; rare diacritics inside line texts were restored by hand from the name table.

## 一致性保证 / Integrity checks

`tools/gen_texts.py` 生成 `src/gua/texts_gen.odin`，每次编译都由约 1800 条 `#assert` 校验：

- `#load_hash(file, "fnv64a")` 封印：改了 `data/*.txt` 不重跑生成器，编译失败。
- 每卦标题序号与卦名、每段标签（卦辭/初九…/用九；J/1–6/U）在偏移处吻合。
- 每条爻辞前的「九/六」与英文 “undivided/divided” 都必须与卦画比特一致（两种语言互证）。

Run `python3 tools/gen_texts.py` after editing either text file.
