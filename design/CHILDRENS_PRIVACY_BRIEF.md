# Children's privacy and Scoranger: a brief for counsel

**Prepared for:** IRL Labs LLC, ahead of the public App Store submission of
Scoranger (`com.irllabs.scoranger`), against `rel/0.11.0` (marketing version
0.11.0, build 200).

**What this is.** Facts, rule text and questions assembled so a lawyer can
dispose of this in twenty minutes rather than three hours. Every factual claim
about the app was read out of this repository and is cited to a file and line.
Every rule is quoted from its current text with a URL. **All web sources
checked 2026-09-21**; this area moves.

**What this is not.** Legal advice. Its author is not this company's lawyer.
Where the rule text settles a question this brief says so and cites it; where
the answer turns on a judgement only counsel can make, it asks the question
instead of guessing. Nothing here is a legal conclusion.

**Companion documents:** `design/APP_STORE_PRIVACY.md` (the full data
inventory; its §9 is this brief's predecessor) and `design/privacy-policy.md`
(the draft policy, whose children's section is a placeholder §9 below
replaces). Both live on branch `feat/app-store-privacy`, which is `rel/0.11.0`
plus those three files. This brief is on `feat/childrens-privacy-brief`, also
cut from `rel/0.11.0`. The two branches need to land together.

---

## 1. Bottom line

Scoranger is a professional arranging tool for composers and musicians. It is
not directed to children under 13 on any of the factors the FTC's rule
enumerates, and that prong of COPPA closes (§2). The only live question is the
narrow second prong — actual knowledge — and it exists for one reason: the
developer's own son, under 13, uses the app with an account, and the developer
knows it (§3).

That fact resolves more simply than it first appears, for two reasons. **The
FTC locates actual knowledge in an information channel** — a registration field
that asks and receives an age, or someone telling the operator. Scoranger asks
nothing and receives nothing; the developer knows his son's age because he is
his father. And **the parent whose consent the Rule contemplates and the
operator of the service are the same person**, present while the app is used,
so the consent COPPA exists to procure is not in doubt. What counsel must
decide is whether either of those propositions holds as a matter of law, since
no FTC source addresses either (§3, and Q1).

Three engineering defects need fixing regardless of how any of this comes out,
because each is a plain gap between what the app does and what the privacy
policy will say (§7). One of them — an email address in server logs that
account deletion does not reach — is the sharpest edge in the whole inventory,
and it is sharp for every user, not only for a child.

For the App Store: an ordinary general-audience rating, no Kids Category. The
language-model chat is the only feature that plausibly moves the rating, and
the reason is Apple's questionnaire, not children's privacy law (§8).

---

## 2. Scoranger is not directed to children

COPPA's first trigger is whether the service is "directed to children."
16 CFR § 312.2 defines the term and lists the factors the Commission weighs:

> **Website or online service directed to children** means a commercial website
> or online service, or portion thereof, that is targeted to children.
>
> (1) In determining whether a website or online service, or a portion thereof,
> is directed to children, the Commission will consider its subject matter,
> visual content, use of animated characters or child-oriented activities and
> incentives, music or other audio content, age of models, presence of child
> celebrities or celebrities who appeal to children, language or other
> characteristics of the website or online service, as well as whether
> advertising promoting or appearing on the website or online service is
> directed to children. The Commission will also consider competent and
> reliable empirical evidence regarding audience composition and evidence
> regarding the intended audience, including marketing or promotional materials
> or plans, representations to consumers or to third parties, reviews by users
> or third parties, and the age of users on similar websites or services.
>
> (2) A website or online service shall be deemed directed to children when it
> has actual knowledge that it is collecting personal information directly from
> users of another website or online service directed to children.
>
> (3) A mixed audience website or online service shall not be deemed directed to
> children with regard to any visitor not identified as under 13.
>
> (4) A website or online service shall not be deemed directed to children
> solely because it refers or links to a commercial website or online service
> directed to children by using information location tools…

— 16 CFR § 312.2, as amended 90 FR 16977 (22 Apr 2025).
<https://www.ecfr.gov/current/title-16/part-312>. Checked 2026-09-21.

How Scoranger scores, factor by factor:

| Factor | Scoranger |
|---|---|
| Subject matter | Score arrangement, transposition, part extraction, clef and instrument changes, chord-symbol analysis. Conservatory vocabulary throughout. |
| Visual content | Engraved Western staff notation. No illustration, no characters, no mascot. |
| Animated characters, child-oriented activities or incentives | None. No games, no rewards, no streaks, no points, no stickers. |
| Music or audio content | MIDI playback of the user's own score through a General MIDI sound bank. No songs, no jingles, no child-oriented audio. |
| Age of models | No models. No people appear anywhere in the app. |
| Child celebrities | None. |
| Language and other characteristics | "Consolidate ties", "split bass", "absorb part", "alto clef", "octave shift", "harmony candidates per bar". The CLI vocabulary in `CLAUDE.md` is the app's vocabulary. |
| Advertising directed to children | No advertising of any kind. No ad SDK, no IDFA, no ad network (`design/APP_STORE_PRIVACY.md` §4). |
| Empirical evidence of audience composition | None gathered. The intended audience is composers, arrangers and working musicians. |
| Intended audience | Same. |

Apple's own guideline reinforces the point from the other direction:

> As a reminder, Guideline 2.3.8 requires that use of terms like "For Kids" and
> "For Children" in app metadata is reserved for the Kids Category. Apps not in
> the Kids Category cannot include any terms in app name, subtitle, icon,
> screenshots or description that imply the main audience for the app is
> children.

— App Review Guidelines § 5.1.4(b), revised 8 June 2026.
<https://developer.apple.com/app-store/review/guidelines/>. Checked 2026-09-21.

Scoranger's name, subtitle, icon and description carry nothing of the sort.

**The "mixed audience" category does not catch this either**, and the FTC says
so directly. Mixed audience is a *subset* of child-directed, not a halfway
house for general-audience services with some young users:

> Importantly, "mixed audience" sites or services are a subcategory of
> "directed to children." In other words, **a website or online service that is
> appealing to all ages and not specifically directed at children is not deemed
> "mixed audience" simply because some children may use the site or service.**

— FTC, *Complying with COPPA: Frequently Asked Questions*, FAQ H.5. Emphasis
added.
<https://www.ftc.gov/business-guidance/resources/complying-coppa-frequently-asked-questions>.
Checked 2026-09-21. (These FAQs are staff views, "not binding on the
Commission," and parts of the page have not been updated for the 2025 Rule.
Where the FAQ and the Rule text diverge, the Rule controls.)

**This prong is closed.** Counsel need only confirm it, and the confirmation
should take one reading. Nothing else in this brief depends on re-opening it.

---

## 3. The one known child user

### The trigger

> It shall be unlawful for any operator of a Web site or online service
> directed to children, or **any operator that has actual knowledge that it is
> collecting or maintaining personal information from a child**, to collect
> personal information from a child in a manner that violates the regulations
> prescribed under this part.

— 16 CFR § 312.3 (emphasis added).
<https://www.govinfo.gov/content/pkg/CFR-2024-title16-vol1/xml/CFR-2024-title16-vol1-part312.xml>.
Checked 2026-09-21.

COPPA has no small-business, revenue or user-count exemption. Neither
15 U.S.C. § 6502 nor § 312.2's definition of "operator" carries a size
qualifier; the only entity-level carve-out in that definition is *"any
nonprofit entity that would otherwise be exempt from coverage under Section 5
of the Federal Trade Commission Act."* The FTC accommodates small operators by
scaling duties, not by exempting them — § 312.8(b) expressly ties the required
safeguards to *"the operator's size, complexity, and nature and scope of
activities."* A one-person LLC is an operator on the same terms as a platform.

### The fact

The developer's son, under 13, uses Scoranger, with an account, and the
developer knows it. This is not inferred: it is written into the repository.
`ios/Scoranger/Scoranger.entitlements:5-11` carries this comment justifying the
Sign in with Apple entitlement:

> Sign in with Apple. Ali's son has an Apple account and no Google one, so this
> is not a nice-to-have: without it he cannot join a shared set list at all.

**Flag for the record:** that comment contradicts what the developer now
states, which is that Sign in with Apple is *unavailable* to his son because
Apple does not offer it below the age threshold, and that Google sign-in is
what works. One of the two is stale. It does not change the analysis — either
way the child has an account — but the comment should be corrected so the
repository stops asserting a fact the developer disputes.

### What is collected from that child, if he signs in

Verified in code:

| Item | Where it lives | Citation |
|---|---|---|
| Firebase uid | Firebase Auth | `ios/Scoranger/Account/SignIn.swift:337-346` |
| Email address (retained even if an Apple private-relay address) | Firebase Auth | `SignIn.swift:40-53, 339-341` |
| Display name from the provider | Firebase Auth | `SignIn.swift:343` |
| Set-list membership records keyed by uid | Firestore `setlists/{id}`, `memberships/{uid}_{setlistId}` | written by Cloud Function, `firebase/functions/index.js:76-95` |
| His pencil ink on shared pages, keyed by uid | Firestore `setlists/{id}/entries/{id}/ink/{uid}` | `Account/SharedSetlists.swift:573-579` |
| Sheet music he adds to a shared set list | Cloud Storage `shared/{setlistId}/…` | `SharedSetlists.swift:461-482` |
| **His email address, written to Google Cloud Logging on every scan conversion** | Cloud Logging, retention not configured in the repo | `omr-service/identity.py:187-197`, emitted `omr-service/server.py:168-171` |

Signed **out** — which is the app's full-function default — nothing reaches
Firebase at all, and that is enforced by a release gate
(`engine/scripts/check_signed_out.py`, wired into `engine/scripts/run_checks.sh`).
Two things still leave the device signed out: the chat text and score structure
to OpenRouter (`ios/Scoranger/LocalChat.swift:262`), and dictation audio to
Apple's speech servers (`ios/Scoranger/SpeechDictation.swift:51-76`). Neither
carries any identifier.

### Why this resolves quickly

Two things in the FTC's staff guidance do most of the work. First, there is no
duty to go looking:

> **The Rule does not require operators of general audience sites to investigate
> the ages of visitors to their sites or services.** However, operators will be
> held to have acquired actual knowledge of having collected personal
> information from a child where, for example, they later learn of a child's
> age or grade from a concerned parent who has learned that his child is
> participating on the site or service.

— FAQ H.1. Emphasis added.

Second, the obligation that arrives with actual knowledge is **scoped to the
identified child and is a binary**:

> **Where an operator knows that a particular visitor is a child, the operator
> must either meet COPPA's notice and parental consent requirements or delete
> the child's information.**

— FAQ H.6. Emphasis added. Note the singular throughout: "a particular
visitor", "the child's information". Nothing in that sentence reaches the
service as a whole.

Here the parent *is* the operator. He is not a concerned parent putting the
operator on notice — the notice and the noticed are one person, present while
the app is used. The consent the Rule exists to procure is not in doubt, is not
being sought from a stranger, and is not being inferred from a checkbox.

**And the FTC's current formulation of the trigger is narrower than "the
operator happens to know."** Its business guidance for general-audience
operators, page-dated May 2026 — newer and more on-point than the FAQ page —
locates actual knowledge in an *information channel*:

> The Rule doesn't require operators of sites or services directed to general
> audiences to investigate the ages of its users. **However, asking for or
> otherwise collecting information that establishes that a visitor is under 13
> triggers COPPA compliance.**
>
> Although the Rule doesn't define the term, the FTC has said that **an operator
> has actual knowledge of a user's age if the site or service asks for – and
> receives – information from the user that allows it to determine the person's
> age.** For example, an operator who asks for a date of birth on a site's
> registration page has actual knowledge as defined by COPPA if a user responds
> with a year that suggests they're under 13.

— FTC, *Children's Online Privacy Protection Rule: Not Just for Kids' Sites*,
May 2026. Emphasis added.
<https://www.ftc.gov/business-guidance/resources/childrens-online-privacy-protection-rule-not-just-kids-sites>.
Checked 2026-09-21.

Scoranger asks nothing and receives nothing. The developer's knowledge of his
son's age comes from being his father, not from the service. The FTC's
enforcement complaints track the same shape: in *NGL Labs* the knowledge came
from inbound parent and child complaints referencing the child's age; in
*Sendit* from 116,000 users entering an under-13 date of birth in a profile
field. Both are channels into the service. **No source located addresses
whether a developer's off-platform personal knowledge of his own child's age is
"actual knowledge" within the meaning of the Rule.**

**Separately, the Rule's test for consent is about mechanism, not certainty.**
§ 312.5(b)(1): *"Any method to obtain verifiable parental consent must be
reasonably calculated, in light of available technology, to ensure that the
person providing consent is the child's parent."* Every enumerated method in
§ 312.5(b)(2) — signed form, card transaction, telephone, video call,
government ID, knowledge-based challenge, facial match, and the lighter "email
plus" route available to operators that do not disclose information to third
parties — exists to reach a parent the operator cannot otherwise identify. None
of them contemplates the operator *being* the parent.

**No FTC rule text, FAQ or guidance located addresses whether an
operator-parent can satisfy § 312.5 for his own child.** That gap, together
with the off-platform-knowledge gap above, is the whole of the live question.
Hence Q1 for counsel rather than a conclusion declared here.

---

## 4. What is settled

Counsel need only confirm these.

1. **Scoranger is not "directed to children" under 16 CFR § 312.2.** §2, factor
   by factor.
2. **COPPA has no small-business exemption.** Size does not take IRL Labs out
   of § 312.2's definition of "operator."
3. **No Kids Category.** Guideline 1.3 bars links out, purchasing
   opportunities, and third-party analytics or advertising outside narrow
   documented cases; routing chat to a third-party model gateway does not sit
   inside that regime. It is also simply not a children's app.
4. **In-app account deletion is mandatory and is currently missing from the
   release branch.** Guideline 5.1.1(v): *"If your app supports account
   creation, you must also offer account deletion within the app."* The
   implementation exists on `feat/account-deletion`; `git merge-base
   --is-ancestor` confirms it is **not** an ancestor of `rel/0.11.0`. Shipping
   0.11.0 as it stands means sign-in with no deletion path, which is a
   guaranteed rejection. Nothing to do with children.
5. **Age rating questionnaire responses are now mandatory**, not optional:
   *"beginning in September 2026, responses will be required when submitting
   new apps or updates to the App Store"*
   (<https://developer.apple.com/news/?id=tlur8uvi>, 9 July 2026).
6. **The state age-appropriate-design and minors'-privacy laws do not reach IRL
   Labs**, on their own applicability text. Each has a size threshold this
   developer falls far below: California AADC via the CCPA "business"
   definition, Civ. Code § 1798.140(d)(1) (>$25M revenue **or** 100,000+
   consumers **or** ≥50% of revenue from selling or sharing personal
   information — and partly enjoined besides, *NetChoice v. Bonta*, No. 25-2366,
   9th Cir., 12 Mar 2026); Maryland AADC, Com. Law § 14-4601(H)(1)(V) (>$25M
   **or** 50,000+ **or** ≥50%); Nebraska LB 504 § 3(5)(a) (all five conditions
   **conjunctively**); Connecticut CTDPA § 42-516(a) (100,000+ consumers, or
   25,000+ with >25% of revenue from data sales — amended thresholds effective
   1 July 2026 not verified). Scoranger sells no data, carries no advertising
   and has users in the low thousands. **Counsel can close this whole family of
   laws.** The app-store age-assurance laws are the opposite case — no
   threshold at all — and are in Q6.
7. **GDPR Article 8, if EU distribution is intended, is engaged only where the
   lawful basis is consent** — *"Where point (a) of Article 6(1) applies…"*
   (Art. 8(1)). Scoranger's account processing rests on contract necessity for
   the sharing features. Recital 38's general "children merit specific
   protection" still applies.
   (<https://gdpr-info.eu/art-8-gdpr/>, <https://gdpr-info.eu/recitals/no-38/>.)

---

## 5. What turns on judgement

Each of these is answerable yes or no with the facts attached. They are ordered
by how much turns on them.

**Q1(a). Is a developer's off-platform personal knowledge that his own son is
under 13 "actual knowledge that it is collecting or maintaining personal
information from a child" within 16 CFR § 312.3 — when the service itself asks
for no age, receives no age, and has no channel through which the fact
arrives?**
*Facts:* no age gate, no birthdate field, no age-identifying question anywhere
(verified by grep across `ios/`, `engine/`, `omr-service/`, `firebase/`); the
FTC's May 2026 formulation is that an operator has actual knowledge *"if the
site or service asks for – and receives – information from the user that allows
it to determine the person's age"*; the enforcement complaints locate the
trigger in a registration field (*Sendit*) or an inbound complaint (*NGL*).

**Q1(b). If yes, is the obligation discharged by the operator-parent recording
his own consent and the § 312.4(d) notice, rather than by one of the
§ 312.5(b)(2) mechanisms — all of which exist to reach a parent the operator
cannot otherwise identify?**
*Facts:* the child has a Firebase account; the data collected is the list in §3;
the operator is the parent and is present in use; § 312.5(b)(1) requires a
method *"reasonably calculated… to ensure that the person providing consent is
the child's parent"*; no FTC source addresses operator-parent self-consent.

**Q2. If Q1 is yes, does the obligation attach only to that child's data, or
does it pull the whole service into the amended Rule's service-wide duties — in
particular the written data-retention policy in § 312.10 and the written
information-security programme in § 312.8(b)?**
*Facts:* FAQ H.6's phrasing is singular ("a particular visitor", "the child's
information"), which reads as per-child. But § 312.10 is drafted at the level
of the operator: *"At a minimum, the operator must establish, implement, and
maintain a written data retention policy that sets forth the purposes for which
children's personal information is collected, the business need for retaining
such information, and a timeframe for deletion of such information,"* and
§ 312.4(d)(2) requires that policy to appear in the posted notice. The amended
Rule was published 22 April 2025, took effect 23 June 2025 and its compliance
date, 22 April 2026, has passed. § 312.8(b) expressly scales to *"the
operator's size, complexity, and nature and scope of activities."*
Sources: <https://www.ecfr.gov/current/title-16/part-312>;
<https://www.federalregister.gov/documents/2025/04/22/2025-05904/childrens-online-privacy-protection-rule>.
*Practical note:* if the answer is yes, the fix is small — a written retention
policy naming the Cloud Logging records and a deletion timeframe, which is
needed anyway (see 7.2 and Q5).

**Q3. Should IRL Labs adopt an age gate at all?**
*Facts:* the FTC permits blocking under-13s outright and does not require
general-audience services to screen — *"COPPA does not require you to permit
children under age 13 to participate in your general audience website or online
service, and you may block children from participating if you so choose"*
(FAQ H.3). But the same FAQ warns about the half-measure: *"if you ask
participants to enter age information, and then you fail either to screen out
children under age 13 or to obtain their parents' consent to collecting these
children's personal information, you may be liable for violating COPPA."* A
gate that collects a birthdate and then admits the developer's son is precisely
that half-measure.
The FTC removed one objection to gating in February 2026: a policy statement
says the Commission *"will not bring an enforcement action under the COPPA Rule
against operators of general audience sites and services and mixed audience
sites and services that collect, use, or disclose personal information for the
sole purpose of determining a user's age without first obtaining verifiable
parental consent"* — subject to six conditions (no other use, prompt deletion,
vetted third parties, notice, security, accuracy). It is forbearance, not a
rule, is revocable, and lapses when the Commission publishes rule amendments on
the subject.
(<https://www.ftc.gov/news-events/news/press-releases/2026/02/ftc-issues-coppa-policy-statement-incentivize-use-age-verification-technologies-protect-children>,
25 Feb 2026.)
**But a gate is a one-way door.** Per the May 2026 guidance quoted in §3,
asking for and receiving an under-13 answer is itself what "triggers COPPA
compliance." Today the service asks nothing. A gate would convert a question
that currently has no channel into a documented, recurring one. **Counsel
should consider whether adding a gate increases rather than reduces
exposure.**

**Q4. Does routing a child's typed or dictated words through the developer's
OpenRouter account breach OpenRouter's terms, and does that matter?** See §6.

**Q5. Is the email address in the OMR Cloud Logging records, which account
deletion does not reach, a deletion-right problem independent of children's
law?**
*Facts:* `omr-service/identity.py:187-197` writes `{"actor": "uid:<sub>",
"email": <address>, …}` on every attributed conversion, on all four exit paths
(`server.py:199, 208, 212, 215`). `deleteAccount`
(`feat/account-deletion:firebase/functions/index.js:417-540`) makes no Logging
API call of any kind. Retention is **not configured anywhere in this
repository** — no log router, no bucket, no sink, no exclusion. The developer
states it is 30 days, which matches the Google Cloud Logging `_Default` bucket
default; that figure should be confirmed in the console before the privacy
policy states it. This bites under CCPA/CPRA deletion rights and under
Apple's account-deletion guideline regardless of any child's involvement.

**Q6. Do the state app-store age-assurance laws impose anything on this
developer today?** These are not children's-app laws; they reach every
developer distributing in the state. Current status:

| Law | Developer duties begin | Status 2026-09-21 | Threshold |
|---|---|---|---|
| **Texas** App Store Accountability Act, Tex. Bus. & Com. Code ch. 121 subch. C (S.B. 2420) | **1 Jan 2026 — in force now** | Preliminary injunction (W.D. Tex. 1:25-cv-01660) lifted by a Fifth Circuit stay 28 May 2026; enforceable from 4 June 2026; Supreme Court declined to vacate the stay 6 July 2026 (*Students Engaged in Advancing Texas v. Paxton*, 25A1389; *CCIA v. Paxton*, 25A1390). Merits appeal pending. | **None.** § 121.051 applies to "the developer of a software application that the developer makes available to users in this state through an app store." |
| **Utah** App Store Accountability Act, Utah Code tit. 13 ch. 76 (S.B. 142) | **6 May 2027** | In force, not enjoined. Apple began sharing age categories for new Utah accounts 6 May 2026, ahead of the duties. | **None.** § 13-76-101(9). |
| **Louisiana**, La. R.S. 51:1771–1775 (Act 185 of 2026, H.B. 977, superseding 2025 Act 481) | **1 July 2027** | Not yet effective. Apple began sharing age categories 1 July 2026. | **None.** |
| **Alabama**, Act 2026-59 (H.B. 161) | **1 Jan 2027** | Not yet effective. Details not verified. | Not verified. |

The Texas duties that actually bind a developer today, verbatim:

> **Sec. 121.052. DESIGNATION OF AGE RATING.** (a) The developer of a software
> application shall assign to each software application and to each purchase
> that can be made through the software application an age rating… (b) The
> developer… shall provide to each app store through which the developer makes
> the software application available: (1) each rating assigned under Subsection
> (a); and (2) the specific content or other elements that led to each rating…

> **Sec. 121.054. AGE VERIFICATION.** (a) The developer… shall create and
> implement a system to use information received under Section 121.024 to
> verify: (1) for each user…, the age category assigned to that user…; and (2)
> for each minor user…, whether consent has been obtained…

> **Sec. 121.055. USE OF PERSONAL DATA.** (a) The developer… may use personal
> data provided… only to: (1) enforce restrictions and protections on the
> software application related to age; (2) ensure compliance with applicable
> laws and regulations; and (3) implement safety-related features and default
> settings. (b) The developer… shall delete personal data provided by the owner
> of an app store… on completion of the verification required by Section
> 121.054.

Sources: <https://capitol.texas.gov/tlodocs/89R/billtext/html/SB02420F.HTM>;
<https://le.utah.gov/xcode/Title13/Chapter76/>;
<https://www.legis.la.gov/legis/ViewDocument.aspx?d=1475238>;
Apple: <https://developer.apple.com/news/?id=sg176nne> (3 Jun 2026),
<https://developer.apple.com/news/?id=f5zj08ey> (24 Feb 2026),
<https://developer.apple.com/news/?id=2ezb6jhj> (4 Nov 2025);
<https://www.scotusblog.com/2026/07/supreme-court-allows-texas-to-enforce-law-requiring-age-verification-and-parental-consent-on-app/>.
Checked 2026-09-21.

*Fact for counsel:* Scoranger calls none of Apple's age APIs. Verified — the
`DeclaredAgeRange` framework is not imported, not linked and not entitled
anywhere in the repository; nor is PermissionKit's Significant Change API.
§ 121.052's age-rating disclosure is satisfied by answering Apple's
questionnaire (§8). **The question is whether § 121.054's "create and implement
a system to use" the age signal binds a general-audience app that has no
age-restricted content and no in-app purchases to enforce — such that not
calling the API is compliant inaction rather than a gap.**

---

## 6. Third-party terms: a minor's words through an adult-attested key

Every chat request goes from the device directly to `openrouter.ai`
(`ios/Scoranger/LocalChat.swift:262`) using a **single API key shared by every
install**, baked into the bundle at build time from a gitignored `.env`
(`ios/project.yml:131-138`). No user identifier of any kind accompanies it: the
body has exactly three keys, `model`, `messages` and `tools`
(`LocalChat.swift:268-272`), and the four headers are `Content-Type`,
`HTTP-Referer`, `X-Title` and the bearer key. So every user's words — including
a child's — are attributed at OpenRouter's end to the developer's adult
account.

OpenRouter's Terms of Service (last updated 31 August 2026,
<https://openrouter.ai/terms>, checked 2026-09-21):

> **2. Eligibility.** You must be at least 18 years of age to use the Service.
> By agreeing to these Terms, you represent and warrant to us that: (a) you are
> at least 18 years of age; (b) you have not previously been suspended or
> removed from the Service; and (c) your registration and your use of the
> Service is in compliance with all applicable laws and regulations.

> **5.2 Flow-Down to Authorized Users.** You will require that all of your
> Authorized Users and customers access and use the Service and Models only in
> accordance with this Agreement, any documentation provided by OpenRouter on
> the Site and Service, and the applicable Model Terms. You will be responsible
> for all acts and omissions of your Authorized Users, including any violation
> of applicable Model Terms.

Two things are worth counsel's attention and neither is resolved by the text.

First, **"Authorized Users" is defined narrowly** — individuals from the admin
user's organisation invited to an organisational account. It does not obviously
reach the end users of an application built on the key. Section 5.2 also says
"and customers", which is not a defined term. So whether Scoranger's users are
within §5.2 at all is a construction question.

Second, **§5.2 flows down "the applicable Model Terms"** — the terms of
whichever upstream provider serves the request. Scoranger sends no `provider`
routing block (verified: no `provider`, `transforms`, `data_collection` or
`user` key anywhere in the Swift), so **which provider serves a given request is
OpenRouter's choice at call time**. The default model is
`google/gemini-3.7-flash`; the catalogue also includes Anthropic, Moonshot,
Alibaba and DeepSeek models (`LocalChat.swift:10-18`). Each of those providers
sets its own minimum age. Those terms have not been checked and should be.

**Q4, restated precisely:** does §2's 18-plus representation bind only the
account holder, or does routing an under-18 end user's text through the
account put the account holder in breach — and separately, does §5.2's
flow-down obligation extend to end users of an application, such that IRL Labs
must impose a minimum age in its own terms? The developer states that the data
policy on the account is now set to zero data retention with training and
data-sharing disabled; that is an account-dashboard setting, is not requested
per-request in code, and should be screenshotted for the file.

---

## 7. Three engineering defects to fix regardless

These stand independent of every legal question above. Each is a gap between
what the app does and what the privacy policy will have to say.

**7.1 Dictation is not on-device.** `requiresOnDeviceRecognition` is never set
anywhere in the repository — zero matches across all Swift — so it defaults to
`false` and `SFSpeechAudioBufferRecognitionRequest` streams microphone audio to
Apple's servers even on devices that support on-device recognition
(`ios/Scoranger/SpeechDictation.swift:51-76`). The Info.plist strings say
nothing about a server: `NSSpeechRecognitionUsageDescription: "Dictate
arrangement requests"`, `NSMicrophoneUsageDescription: "Dictation input for
chat"` (`ios/Scoranger/Info.plist:133-136`).
*Fix:* set `requiresOnDeviceRecognition = true` with a
`supportsOnDeviceRecognition` fallback. One line plus a guard.
*Cost:* on-device recognition is less accurate and needs the language model
downloaded. *Gain:* the Audio Data row in the App Privacy questionnaire becomes
a clean "No", and no user's voice — child or adult — leaves the device.
*Why the rule text makes this more than housekeeping:* the amended § 312.2
defines personal information to include *"(8) A photograph, video, or audio
file where such file contains a child's image or voice"* and, new in 2025,
*"(10) A biometric identifier… such as… voiceprints."* The 2025 Rule also added
§ 312.5(c)(9), an exception for collecting *"an audio file containing a child's
voice, and no other personal information, for use in responding to a child's
specific request"* — but only where the operator *"deletes it immediately after
responding"* and gives the § 312.4(d)(4) notice. On-device recognition removes
the question entirely rather than requiring the app to fit inside that
exception.

**7.2 The email address in scan logs, which account deletion does not reach.**
`omr-service/identity.py:187-197` writes the signed-in user's email address
into Cloud Logging on every conversion, on all four exit paths. `deleteAccount`
makes no Logging call. This is the sharpest edge in the inventory and it is
sharp for every user.
*Fix, in ascending order of effort:*
 (a) **Stop logging the email.** The `actor` field already carries
 `uid:<sub>`, which is sufficient for per-user cost accounting; the address
 adds nothing the uid does not. Delete `"email": detail` from `usage_line` and
 the `email` plumbing in `server.py`. This is the cheapest fix and it costs the
 product nothing — verified: the address is used for no other purpose in the
 service.
 (b) Set an explicit retention on the log bucket, so the policy can state a
 number honestly.
 (c) Have `deleteAccount` issue a Cloud Logging deletion or redaction for the
 departing uid. This is the most work and is unnecessary if (a) is done.
*Recommendation:* do (a). It is a three-line change and it removes the problem
rather than managing it.
*Why this one is the sharpest:* in *United States v. Cognosphere* (C.D. Cal.
No. 2:25-cv-00447, complaint and stipulated order 17 Jan 2025, $20M), the FTC
alleged that partial remediation was not enough — the operator removed the
child's post and muted the account *"but without deleting or seeking verifiable
parental consent for the use or disclosure of, other personal information of
the child already collected."* If IRL Labs ever has to remediate for any user,
child or not, the Cloud Logging records are exactly the "other personal
information already collected" that the deletion path does not reach.

**7.3 The chat sends excerpts of previous prompts.** The `list_versions` tool
returns the iOS bridge's unfiltered `load_meta`, which carries artifact
filenames, document uids, and **the first 200 characters of each earlier user
prompt** (`engine/scoranger_engine/workspace.py:54`, reached via
`ios/PythonApp/app/bridge.py:310-311`). The Python agent's own implementation
projects version documents down to `{id, op, args}`
(`engine/scoranger_engine/chat.py:143-145`), so the two paths disagree and the
iOS one leaks more. This looks unintended.
*Fix:* make the bridge apply the same projection as `chat.py`.
*Cost:* none identified — the model does not need old prompt text to reason
about version history.

---

## 8. App Store: age rating and the Kids Category

**The Kids Category: no.** Settled, §4 item 3.

**The age rating: an ordinary general-audience rating.** Apple replaced the old
scheme in July 2025:

> The updated age rating system adds 13+, 16+, and 18+ to the existing 4+ and
> 9+ ratings. […] We've introduced a new set of required questions to the
> ratings questionnaire for all apps. These new questions cover: In-app
> controls. Capabilities. Medical or wellness topics. Violent themes in your
> app or game.

— <https://developer.apple.com/news/?id=ks775ehf>, 24 July 2025. Checked
2026-09-21.

Responses became mandatory for every submission and update in September 2026
(<https://developer.apple.com/news/?id=tlur8uvi>, 9 July 2026), so this
questionnaire will be answered as part of this submission, not optionally.

**What the facts support.** The questionnaire is filled in by hand in App Store
Connect and Apple does not publish the question text, so the headings below are
Apple's published category names, not verbatim questions. Confirm against the
live form.

- **Content descriptors** (violence, sexual content, profanity, horror, drugs,
  alcohol, tobacco, mature themes, gambling, contests): **None** on every one.
  The app renders notation and plays MIDI.
- **Chance-based activities** (simulated gambling, contests, gambling, loot
  boxes): **None**. No in-app purchase, no StoreKit.
- **Medical or wellness topics:** **None**.
- **In-app controls:** the app has no parental controls and no age-restriction
  mechanism. Answer honestly: none.
- **Capabilities:** this is the section that matters. It asks about chat or
  messaging, user-generated content, and web access.
  - *Unrestricted web access:* **No.** There is no in-app browser and no
    `UIApplication.shared.open` anywhere; sharing goes out through the system
    share sheet.
  - *Chat or messaging between users:* **No.** The chat is a user-to-model
    interface, not user-to-user. There is no messaging surface.
  - *User-generated content:* **Yes, in a limited sense.** Set list members see
    each other's entry titles, composers and pencil ink
    (`SharedSetlists.swift:461-482, 573-587`), capped at twelve members per set
    list and invisible outside it.
- **Social media capabilities:** **No.** Apple's definition is *"the ability to
  redistribute, amplify, or interact with user-generated content through a
  social feed or similar discovery method"*
  (<https://developer.apple.com/news/?id=tlur8uvi>). Scoranger has no feed, no
  discovery, no followers, no amplification — a closed twelve-person set list
  is the opposite of a discovery method. Answering No avoids the Social Media
  content descriptor and the Time Allowance category that comes with it.

**Does the language-model chat move the rating?** It is the one feature that
could, and the reason is Apple's expectation that a developer account for what
an open-ended model can produce, not children's privacy law. Two guidelines
bear on it, both revised 8 June 2026
(<https://developer.apple.com/app-store/review/guidelines/>):

> **1.2.1(a) Creator Content.** Creator apps must provide a way for users to
> identify content that exceeds the app's age rating, and use an age
> restriction mechanism based on verified or declared age to limit access by
> underage users.

> **4.7.5** Your app must provide a way for users to identify software that
> exceeds the app's age rating, and use an age restriction mechanism based on
> verified or declared age to limit access by underage users.

Scoranger is not a creator-content app and hosts no mini-apps or
chatbots-as-content in 4.7.5's sense: the chat is one scoped assistant whose
job is to call deterministic music21 operations on the user's own score. But
the model behind it is a general-purpose frontier model reachable through a
free-text field, and that is where this submission is most likely to draw a
question.

*Recommendation:* answer honestly for 4+, and keep a one-paragraph explanation
ready of why the chat is bounded — the system prompt, the tool-only action
surface, and the fact that the model never writes notation directly. If App
Review pushes back, 13+ costs a tool for musicians nothing.

---

## 9. The privacy policy's children's section, drafted

This replaces the placeholder in `design/privacy-policy.md`. It is drafted for
the expected answer — a general-audience app that does not knowingly collect
personal information from children under 13 — and is ready to publish once
counsel confirms §2 and Q1. Two variants follow for the cases where counsel
answers differently.

### 9.1 Primary draft — publish this if counsel confirms §2 and Q1

> ## Children
>
> Scoranger is a tool for composers, arrangers and working musicians. It is not
> designed for children, it is not marketed to children, and it is not in the
> App Store's Kids category.
>
> We do not knowingly collect personal information from children under 13. You
> never need an account to use Scoranger: the library, the engine, the
> arranging tools and playback all work with no sign-in and nothing leaves the
> iPad. An account exists only so that you can share a set list with other
> people.
>
> If you believe a child under 13 has created a Scoranger account, write to us
> at [EMAIL ADDRESS] and we will delete the account and everything associated
> with it. You can also do this yourself at any time from Settings → Account →
> Delete my account.
>
> Two features send what you say to another company, and parents should know
> about them. The **chat** sends what you type or dictate, together with a
> description of your score, to a language model run by another company — see
> "The chat, and the part people are surprised by" above. **Dictation** uses
> Apple's speech recognition, which may send what you say to Apple's servers.
> Neither carries your name, your email address or any account identifier.
> Neither is available to anyone who has not chosen to use it.

*Notes for whoever publishes this.* The last paragraph presumes defect 7.1 has
not been fixed. **If `requiresOnDeviceRecognition` is set before launch, replace
the dictation sentence with:** "Dictation uses Apple's speech recognition on
the device itself; what you say does not leave the iPad."

### 9.2 If counsel answers Q1 yes and wants the obligation stated

Add, after the second paragraph:

> Where we become aware that a user is under 13, we collect personal
> information from that user only with the verifiable consent of their parent
> or guardian, and a parent or guardian may at any time review what we hold,
> refuse further collection, and require its deletion by writing to
> [EMAIL ADDRESS].

### 9.3 If counsel requires an age gate (Q3 answered yes)

Replace the second paragraph with:

> Scoranger asks for your date of birth when you create an account, for the
> sole purpose of complying with children's privacy law. We do not create
> accounts for people under 13. We keep the date only long enough to make that
> decision.

That wording tracks Guideline 5.1.4(a), which permits asking for a birthdate
*"only for the purpose of complying with these statutes"* and requires the app
to *"include some useful functionality or entertainment value regardless of a
person's age"* — which Scoranger does, since the whole app works signed out.

---

## 10. Options, and what each costs

Not a list to adopt. An evaluation.

| Option | Cost | What it gives up | Verdict |
|---|---|---|---|
| **Remove the email from the OMR logs** (7.2a) | Three lines | Nothing — the uid already carries the cost signal | **Do it.** Most exposure removed per unit of work in the whole inventory. |
| **Set on-device dictation** (7.1) | One line plus a capability guard | Some recognition accuracy | **Do it.** Converts a questionnaire "Yes" to a "No". |
| **Fix the chat's prompt-excerpt leak** (7.3) | Apply `chat.py`'s projection in the iOS bridge | Nothing identified | **Do it.** |
| **Merge `feat/account-deletion`** | A merge and a regression pass | Nothing | **Mandatory**, and not currently done. |
| **Add an age gate** | A screen, a stored birthdate, a refusal path, and a new category of collected data | Friction at sign-in; and see Q3 — it may *increase* exposure by creating age knowledge where none existed | **Ask counsel first.** Do not add reflexively. |
| **Refuse accounts below 13** | The above, plus locking the developer's son out of shared set lists | The one feature he uses | **Damages the product for no gain** while the operator and the parent are the same person. |
| **Disable chat and dictation for known-child accounts** | Presupposes the gate | The two features a young musician would most want | **Disproportionate.** |
| **Adopt the Declared Age Range API** | Framework adoption plus PermissionKit | Nothing functional | **Ask counsel (Q6).** Probably unnecessary with nothing age-restricted to gate, but Texas is in force. |

**Most exposure removed for the least product damage:** the first four rows.
None of them changes a single user-visible behaviour, and together they close
every gap between what the app does and what its privacy policy will say.
**Most product damage:** an age gate plus a refusal below 13 plus feature
lockouts — which would lock out the app's own most-cited user to solve a
problem the facts do not support.

---

## 11. What could not be established

| # | Unknown | Who resolves it |
|---|---|---|
| 1 | Cloud Logging retention for the OMR usage records. **No log router, bucket, sink, exclusion or retention setting exists anywhere in this repository.** The developer states 30 days, which matches Google's `_Default` bucket default, but it is console state, not code. | Ali, in the GCP console. The privacy policy needs the number. |
| 2 | Whether the OpenRouter account's zero-data-retention and training settings are actually off. The developer states they are now set; nothing in code requests them per-request. | Ali. Screenshot for the file. |
| 3 | Minimum-age terms of the upstream model providers whose Model Terms flow down under OpenRouter §5.2. | Counsel, with §6. |
| 4 | Scoranger's App Store category and age rating. Nothing in this repository declares either — no `LSApplicationCategoryType`, no fastlane metadata, no App Store Connect metadata directory. | Ali, in App Store Connect. |
| 5 | Whether the Sign in with Apple comment at `Scoranger.entitlements:5-11` or the developer's current account is correct about whether his son can use Sign in with Apple. | Ali. Correct the comment either way. |
| 6 | Whether EU or UK distribution is intended. Determines whether §4 item 7 needs any work at all. | Ali. |

---

## Appendix: sources, all checked 2026-09-21

| Source | Document date | URL |
|---|---|---|
| 16 CFR part 312 (COPPA Rule): §§ 312.2, 312.3, 312.4, 312.5, 312.8, 312.10 | as amended 90 FR 16977, 22 Apr 2025 | <https://www.ecfr.gov/current/title-16/part-312> |
| 15 U.S.C. § 6502 (COPPA statute) | — | <https://uscode.house.gov/view.xhtml?req=granuleid:USC-prelim-title15-section6502> |
| COPPA Rule final amendments, 90 FR 16918 | published 22 Apr 2025; effective 23 Jun 2025; compliance 22 Apr 2026 | <https://www.federalregister.gov/documents/2025/04/22/2025-05904/childrens-online-privacy-protection-rule> |
| FTC, *COPPA Rule: Not Just for Kids' Sites* — the current general-audience guidance | page-dated May 2026 | <https://www.ftc.gov/business-guidance/resources/childrens-online-privacy-protection-rule-not-just-kids-sites> |
| FTC, *Complying with COPPA: FAQs*, §§ A, H, I — staff views, partly stale | timestamped 2026 but tracks the 2013 Rule in places | <https://www.ftc.gov/business-guidance/resources/complying-coppa-frequently-asked-questions> |
| FTC COPPA policy statement on age-verification technologies (forbearance, 2-0) | 25 Feb 2026 | <https://www.ftc.gov/news-events/news/press-releases/2026/02/ftc-issues-coppa-policy-statement-incentivize-use-age-verification-technologies-protect-children> |
| *U.S. v. NGL Labs*, C.D. Cal. 2:24-cv-05753 — actual knowledge from inbound complaints | complaint 9 Jul 2024; order 14 Jul 2024 | ftc.gov case file |
| *U.S. v. Cognosphere*, C.D. Cal. 2:25-cv-00447 — partial remediation insufficient | 17 Jan 2025 | ftc.gov case file |
| *U.S. v. Iconic Hearts (Sendit)*, C.D. Cal. 2:25-cv-09310 — **pending; allegations only** | complaint 29 Sep 2025 | ftc.gov case file |
| Texas S.B. 2420, Tex. Bus. & Com. Code ch. 121 | eff. 1 Jan 2026 | <https://capitol.texas.gov/tlodocs/89R/billtext/html/SB02420F.HTM> |
| Utah App Store Accountability Act, Utah Code tit. 13 ch. 76 | duties from 6 May 2027 | <https://le.utah.gov/xcode/Title13/Chapter76/> |
| Louisiana Act 185 (2026), H.B. 977 | eff. 1 Jul 2027 | <https://www.legis.la.gov/legis/ViewDocument.aspx?d=1475238> |
| *NetChoice v. Bonta*, No. 25-2366 (9th Cir.) — CA AADC partly enjoined | 12 Mar 2026 | <https://cdn.ca9.uscourts.gov/datastore/opinions/2026/03/12/25-2366.pdf> |
| App Review Guidelines (1.2.1(a), 1.3, 2.3.6, 4.7.5, 5.1.1(v), 5.1.4) | revised 8 Jun 2026 | <https://developer.apple.com/app-store/review/guidelines/> |
| Updated age ratings in App Store Connect | 24 Jul 2025 | <https://developer.apple.com/news/?id=ks775ehf> |
| Age rating questionnaire: social media questions | 9 Jul 2026 | <https://developer.apple.com/news/?id=tlur8uvi> |
| Next steps for apps distributed in Texas | 4 Nov 2025 | <https://developer.apple.com/news/?id=2ezb6jhj> |
| Age requirements: Brazil, Australia, Singapore, Utah, Louisiana | 24 Feb 2026 | <https://developer.apple.com/news/?id=f5zj08ey> |
| Update for apps distributed in Texas (SB 2420 in force 4 Jun 2026) | 3 Jun 2026 | <https://developer.apple.com/news/?id=sg176nne> |
| SCOTUS declines to block Texas SB 2420 | 6 Jul 2026 | <https://www.scotusblog.com/2026/07/supreme-court-allows-texas-to-enforce-law-requiring-age-verification-and-parental-consent-on-app/> |
| OpenRouter Terms of Service (§2 Eligibility, §5.2 Flow-Down) | last updated 31 Aug 2026 | <https://openrouter.ai/terms> |
| GDPR Article 8; Recital 38 | — | <https://gdpr-info.eu/art-8-gdpr/> · <https://gdpr-info.eu/recitals/no-38/> |
