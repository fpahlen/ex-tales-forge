# Social-act classification: sources for labelling player lines (Jev)

Purpose: give us citable taxonomies, datasets, and research for classifying the social act of a player's spoken line in the tavern RPG, so NPCs react sensibly. Every URL below was checked on 2026-10-19 and resolved (HTTP 200; APA's DOI blocks bots, so Kruger et al. is linked via PubMed). Licences marked "verify" were not confirmed. Check them before using any data beyond internal testing.

Relevance: **H** = directly useful for the label set or test lines; **M** = useful background or a partial fit; **L** = context only.

## 1. Speech-act and dialogue-act taxonomies and corpora
| Source | URL | Offers | Licence | Rel. |
|---|---|---|---|---|
| Searle (1976), "A classification of illocutionary acts", *Language in Society* | https://doi.org/10.1017/S0047404500006837 | The five classes: assertives, directives, commissives, expressives, declarations. The theory behind request/offer/threat/apology/compliment. | n/a (paper) | M |
| Stolcke et al. (2000), "Dialogue act modeling for automatic tagging and recognition of conversational speech" | https://aclanthology.org/J00-3003/ | SWBD-DAMSL: 42 dialogue acts on Switchboard. Includes question types, agree/accept, apology, thanking, and greeting-style conventional acts. | paper | H |
| Switchboard Dialog Act Corpus (C. Potts tools) | https://github.com/cgpotts/swda | The SWDA data in usable form. | CC BY-NC-SA 3.0 (per repo; verify) | M |
| Shriberg et al. (2004), "The ICSI Meeting Recorder Dialog Act (MRDA) Corpus" | https://aclanthology.org/W04-2319/ ; tools: https://github.com/NathanDuran/MRDA-Corpus | Meeting dialogue acts. | verify | L |
| Li et al. (2017), "DailyDialog: A Manually Labelled Multi-turn Dialogue Dataset" | https://aclanthology.org/I17-1099/ ; https://huggingface.co/datasets/li2017dailydialog/daily_dialog | About 13k everyday dialogues. Each turn has one of four acts (inform, question, directive, commissive) and one of seven emotions. | CC BY-NC-SA 4.0 (per HF card; verify) | H |

## 2. Datasets for humour, sarcasm, offence, and politeness
| Source | URL | Offers | Licence | Rel. |
|---|---|---|---|---|
| Danescu-Niculescu-Mizil et al. (2013), "A computational approach to politeness…" (Stanford Politeness Corpus) | https://aclanthology.org/P13-1025/ ; https://convokit.cornell.edu/documentation/wiki_politeness.html | Wikipedia and StackExchange requests rated for politeness, plus politeness strategies such as gratitude, apologising, hedging, and deference. | verify (ConvoKit) | H |
| Van Hee et al. (2018), SemEval-2018 Task 3: Irony Detection in English Tweets | https://aclanthology.org/S18-1005/ | Binary irony labels, plus a 4-way type label. | verify | H |
| Ghosh et al. (2020), "A Report on the 2020 Sarcasm Detection Shared Task" | https://aclanthology.org/2020.figlang-1.1/ | Sarcasm in Reddit and Twitter replies, with context. | verify | M |
| Khodak et al. (2017), "A Large Self-Annotated Corpus for Sarcasm" (SARC) | https://arxiv.org/abs/1704.05579 | About 1.3M Reddit comments self-labelled with /s. Noisy. | verify | M |
| Misra, News Headlines Dataset for Sarcasm Detection | https://www.kaggle.com/datasets/rmisra/news-headlines-dataset-for-sarcasm-detection | Onion headlines vs. real headlines. Short lines. | see Kaggle page | L |
| Meaney et al. (2021), SemEval-2021 Task 7: HaHackathon | https://aclanthology.org/2021.semeval-1.9/ | Text rated for whether it is humorous and how funny, plus offence ratings. | verify | H |
| Zampieri et al. (2019), "Predicting the Type and Target of Offensive Posts…" (OLID) | https://aclanthology.org/N19-1144/ | Offensive vs. not, targeted vs. untargeted, and target type (individual/group). Maps to insult vs. general rudeness. | verify | H |
| Davidson et al. (2017), "Automated Hate Speech Detection and the Problem of Offensive Language" | https://arxiv.org/abs/1703.04009 ; https://github.com/t-davidson/hate-speech-and-offensive-language | Tweets labelled hate / offensive / neither. | verify (repo) | M |
| Waseem et al. (2017), "Understanding Abuse: A Typology…" | https://aclanthology.org/W17-3012/ | A typology of abuse: directed vs. generalised, explicit vs. implicit. | paper | M |

**Gaps:** we found no well-established standalone public dataset for **apologies**, **threats**, **gossip**, or **offers**. Apologies show up as a SWBD-DAMSL tag and a politeness strategy, and offers/threats fall under Searle's commissives. We will probably need to write our own lines for these.

## 3. LLMs classifying sarcasm, humour, or speech acts zero-shot
| Source | URL | Offers | Rel. |
|---|---|---|---|
| Zhang et al. (2024), "SarcasmBench: Towards Evaluating LLMs on Sarcasm Understanding" | https://arxiv.org/abs/2408.11319 | Tests 11 LLMs and 8 PLMs on 6 benchmarks. LLMs **underperform supervised PLMs**; GPT-4 is best among LLMs; few-shot beats zero-shot and CoT. Exact per-dataset numbers are in the paper and not copied here. | H |
| Zhang et al. (2023), "Sentiment Analysis in the Era of LLMs: A Reality Check" | https://arxiv.org/abs/2305.15005 | Zero/few-shot LLM evaluation across sentiment tasks, including irony and offensive-language style tasks. Numbers not reproduced here. | M |

## 4. Social reasoning and theory of mind in agents and NPCs; fast/slow reasoning
| Source | URL | Offers | Rel. |
|---|---|---|---|
| Park et al. (2023), "Generative Agents: Interactive Simulacra of Human Behavior" | https://arxiv.org/abs/2304.03442 | LLM NPCs with memory, reflection, and planning in a sandbox town. | M |
| Kosinski (2023), "Evaluating LLMs in Theory of Mind Tasks" | https://arxiv.org/abs/2302.02083 | False-belief tests on LLMs. Its claims are contested. | L |
| Gandhi et al. (2023), "Understanding Social Reasoning in LMs with LMs" (BigToM) | https://arxiv.org/abs/2306.15448 | A procedurally generated ToM benchmark. | M |
| Lin et al. (2023), "SwiftSage: … Fast and Slow Thinking…" | https://arxiv.org/abs/2305.17390 | A fast small model plus a slow LLM planner. A precedent for a cheap first-pass classifier that escalates hard lines. | M |
| Sumers et al. (2023), "Cognitive Architectures for Language Agents" (CoALA) | https://arxiv.org/abs/2309.02427 | A framework for agent memory, action, and decision loops. | L |

## 5. Humans misreading tone in text
| Source | URL | Offers | Rel. |
|---|---|---|---|
| Kruger, Epley, Parker & Ng (2005), "Egocentrism over e-mail: Can we communicate as well as we think?", *JPSP* 89(6) | https://pubmed.ncbi.nlm.nih.gov/16393025/ | Email senders overestimate how well readers will detect their sarcasm or humour. This justifies letting Jev ask for clarification or hedge on ambiguous lines, and expecting less than perfect human agreement. | H |

## Sources of scripted test lines for the founder labelling survey
- **DailyDialog**: questions, requests (directive), offers/accept (commissive), and greetings.
- **Stanford Politeness**: polite vs. rude requests.
- **SemEval-2018 irony / FigLang 2020**: sarcasm.
- **HaHackathon**: jokes, with offence ratings.
- **OLID**: insults (targeted offence). Rewrite these into tavern register and remove slurs.
- **SWBD-DAMSL**: apology, thanks, and accept/reject examples.
- Licences: most of these are research or NC licences. Paraphrase them into fantasy register for internal testing, and do not ship raw text in the product.
- Threats, gossip, flattery, and offers: write these by hand.

## Recommended label set (14)
`greeting`, `question`, `request`, `offer`, `accept`, `decline`, `compliment` (incl. flattery), `apology`, `thanks`, `joke`, `sarcasm`, `insult`, `threat`, `gossip`, plus `other/statement` as a fallback.

Add a separate politeness axis instead of more acts: `polite | neutral | rude`, following the Stanford Politeness Corpus.

Allow one primary act and an optional secondary act, because sarcasm and jokes often wrap another act, e.g. a sarcastic compliment that is really an insult. The set maps to Searle's classes (directive: request/question; commissive: offer/threat/accept; expressive: apology/thanks/compliment/greeting) and to DailyDialog's 4 acts, so we can test against existing data.

## Caveats
- Licences marked "verify" were not confirmed.
- We did not copy any accuracy figures. Read the papers before quoting numbers.
- Social-media data (tweets, Reddit) is a different register from tavern speech.
- Human agreement on sarcasm and humour is itself limited (Kruger et al.), so do not expect Jev to score 100% against founder labels.
