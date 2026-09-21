# texts

A course textbook turned into something an agent can read: one markdown file
per chapter, searchable, with every passage citable to the page printed in the
book.

## What is here

| Path                | What it holds                                                    |
| ------------------- | ---------------------------------------------------------------- |
| `bin/textbook`      | Search a corpus. Never loads a whole chapter into context.        |
| `ingest/ingest.py`  | PDF to corpus. `scan` prints the plan, `apply` writes it.         |

The corpora themselves live in `$COURSEWORK_DIR/texts/<slug>/` (default
`~/coursework/texts`), next to the syllabi they are assigned by. Nothing here
holds book text, because a textbook is somebody else's copyright even when the
licence is open.

## Ingesting

```bash
ingest/ingest.py scan  ~/Downloads/book.pdf
ingest/ingest.py apply ~/Downloads/book.pdf --out ~/coursework/texts/<slug> --keep-pdf
```

`scan` reads the PDF's bookmark outline and prints the chapter plan. It writes
nothing, and `apply` writes exactly that plan, because an outline can be absent
or wrong and 500 pages filed under the wrong headings is expensive to notice.

Chapter numbers come from the outline's nesting, not from its order. Flattening
the tree numbers Contents and Preface as chapters 1 and 2 and pushes the book's
own chapter 1 to 3, which points every assigned reading at the wrong text.

Extraction is pdfminer by way of markitdown, not `pdftotext`. On a Pressbooks
PDF with figures in the margin, `pdftotext` interleaves caption lines into the
body mid-word: "the emerging anthropological prac-", then the caption, then
"tices of this time". pdfminer keeps reading order and pushes captions to the
end of the page.

Three artifacts the cleaner handles, all found in Perspectives 2e:

- **Running heads.** Matching the book's title missed every one of them,
  because the PDF metadata title ends ", 2nd Edition" and the running head does
  not. The cleaner counts instead: a string sitting beside a page number three
  or more times is a running head whatever it says.
- **A doubled text layer.** Prince draws chapter openers twice, so a two-line
  heading arrives as A, A, B, B and reflows into "INTRODUCTION TO INTRODUCTION
  TO ANTHROPOLOGY ANTHROPOLOGY". Consecutive identical lines collapse.
- **Words broken across lines.** "prac-" plus "tices" is one word and the
  hyphen goes; "non-" plus "European" is a compound and it stays. The capital
  on the second half is what tells them apart.

Four words in 253,000 still end in a dangling hyphen in the Perspectives
corpus, where the continuation landed after an intervening figure caption
rather than in the next block. Three of the four are in bibliographies. Healing
those needs lookahead past unrelated blocks, which is a good way to join two
sentences that were never one.

## Checking

```bash
ingest/ingest.py verify ~/Downloads/book.pdf --out ~/coursework/texts/<slug>
```

Every defect it checks for shipped at least once during the first ingest: front
matter numbered as chapters, running heads left in as headings, the doubled
text layer, glossary entries fused into one paragraph. Re-reading the output by
hand caught each of them once and none of them twice, which is what the script
is for.

## Reading

```bash
textbook books                              # what is ingested
textbook toc                                # chapters, page spans, lengths
textbook search "participant observation"   # ranked passages
textbook search "kula" --chapter 6          # one chapter
textbook show 06-economics --at 48210       # a window around an offset
textbook glossary reciprocity               # defined terms only
```

Every hit carries `p. N`, the page printed in the book, taken from `<!-- p. N -->`
markers laid down during ingest. Cite that rather than the PDF page: a claim
the reader cannot look up is a claim they have to take on faith.

## Which corpora exist

Run `textbook books`. The index of a corpus is its own `INDEX.md`, and
`GLOSSARY.md` collects every term the book defines, in chapter order.

Built with Chewbacca
