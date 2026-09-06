# AI PROCESS — How ALTAURI Is Developed

> "A human being cannot process text at such speed and in such
> volumes — that is the vocation of AI: a tool that helps humans."
>
> — **Albert Lapinskyi**, author of ALTAURI

> One page of honesty: what generative AI does in this codebase, what it is
> never allowed to do, and how human direction stays auditable.

## Declaration

ALTAURI is developed by a human author working with large language models
(LLMs) as everyday instruments. This use is disclosed openly — in this file,
in the README, and in the grant application. Nothing in this repository is
presented as purely human work — and nothing is purely machine work either.

## The three-voice practice

Every change to this codebase passes through three voices:

| Voice | Who | What it contributes |
|---|---|---|
| 1. Draft & analysis | AI (LLM) | proposes implementations, finds inconsistencies, critiques designs, explains unfamiliar platform corners |
| 2. Judgment | the author | accepts, rejects, reworks; owns architecture, naming, semantics and priorities; compiles, tests on real hardware and real targets |
| 3. Frozen record | the repository | accepted decisions land as code + comments + a Task ledger entry; rejected proposals vanish |

The frozen record is the point: a decision that is not recorded did not
happen. Voice 3 is what makes Voice 2 auditable.

## The Task ledger — the decision record

Comments across `src/` reference a continuous internal task numbering
(`Task 86` … `Task 165`) and project stages (`Stage 3`, `Stage 4a-4`, …).
These numbers are the author's project journal, not generated decoration:

- a task id in a comment means: "this behavior was decided there, for this reason";
- fix families are named and grouped (e.g. `FIX B..G`, Tasks 140–141 — the
  file I/O correctness pass);
- when a comment and the code disagree, the task trail shows which voice won.

Examples a reviewer can trace today:

- **FileReaderAtom / FileWriterAtom v1.3** — the binary byte pipeline exists
  because a PNG (`fft.png`) was mangled by the text pipe; the lesson is
  recorded in the comments themselves ("the field lesson fft.png");
- **RelayAtom v1.5** — a one-line fix whose changelog explains the
  dead-scheduler cause and why the fix restores the base-class contract;
- **MiniAudioAtom** — zero-GC audio thread design; the constraints
  (no allocations in the audio callback) are written next to the code
  that obeys them.

## What AI is never allowed to do

- commit or push — every merge into the public branch is a human action;
- decide architecture, naming, semantics or priorities;
- modify code silently: accepted changes are compiled and tested by the
  author on real targets (html5, Windows/cpp) before they enter history.

## Comment language history

Comments were authored in Russian during development and translated to
English (September 2026) before the public release. The translation was
comment-only: executable code semantics are untouched and diff-verified.
Meaningful idioms were preserved rather than flattened ("anti-matryoshka"
tail truncation, "ROCK-SOLID" re-read guarantees).

## Compatibility with the NLnet GenAI policy

NLnet funds human creative work; purely AI-generated contributions are not
eligible for payment. ALTAURI's practice — human direction with AI
instrumentation, disclosed, with a frozen decision record — is designed to
sit exactly on the fundable side of that line. This file exists so that a
reviewer does not have to take our word for it: the ledger, the per-file
changelogs and the git history are open for inspection.
