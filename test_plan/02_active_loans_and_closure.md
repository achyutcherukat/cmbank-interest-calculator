# 02 — Active Loans View and Full Closure

**Pre-condition:** Doc 01 complete. 10 open loans (#3200–#3209). Device date = T.
**Reference:** `dataset_reference.md §5`, §5a

L2 (#3201) and L3 (#3202) are used in this doc as **preview-only** edge-case checks — the closure screen is opened to observe values, then cancelled. This keeps both pledges open for Admin Reports tests in Doc 09.

---

## TC-02-01: View Active Loans List

| Step | Action | Expected Result | P/F |
|------|--------|-----------------|-----|
| 1 | Navigate to the Open / Active Loans list | 10 loans displayed | |
| 2 | Verify default sort order | Newest pledge number first (#3209 at top, #3200 at bottom) | |
| 3 | Confirm #3201 (L2) shows "No Customer" or an empty customer field | No customer name shown | |
| 4 | Confirm #3202 (L3) also shows no customer | — | |
| 5 | Tap pledge #3200 (L1) to open its detail | Loan detail screen opens | |
| 6 | Verify displayed information | Pledge #3200, Customer: Rajan Kumar, Principal: ₹50,000, Gold: Necklace 22K 20g, Status: Open | |

---

## TC-02-02: Interest Preview — L1

| Step | Action | Expected Result | P/F |
|------|--------|-----------------|-----|
| 1 | On L1 detail, find or open the interest preview / close loan screen | — | |
| 2 | Observe interest for today T | rawDays = 0 → effectiveDays = 7 → rawInterest = 175.0 → roundUp5 = **175** → interest = **₹175** | |
| 3 | Observe note text | **"Minimum 7 days applied"** | |
| 4 | Observe total | **₹50,175** | |

---

## TC-02-03: Close L1 — Standard Full Closure (Cash)

Pledge #3200 · ₹50,000 principal · same-day closure on T

| Step | Action | Expected Result | P/F |
|------|--------|-----------------|-----|
| 1 | On L1 closure screen, verify interest | **₹175** | |
| 2 | Verify note | "Minimum 7 days applied" | |
| 3 | Verify total to collect | **₹50,175** | |
| 4 | Select payment mode **Cash** | Cash = ₹50,175 | |
| 5 | Confirm / complete the closure | Closure saved | |
| 6 | Verify L1 no longer appears in Open Loans list | Pledge #3200 absent | |
| 7 | Verify L1 appears in Closed Loans | Status shows "Closed", closure date = T | |
| 8 | Open L1 detail from closed list | total_interest_paid = ₹175, total_amount_collected = ₹50,175 | |

---

## TC-02-04: Edge Case — Minimum ₹50 Interest Branch (L2, Preview Only, DO NOT Close)

Pledge #3201 · ₹10,000 principal

Expected calculation:
- rawDays = 0, effectiveDays = 7
- rawInterest = 10,000 × 0.0035 = 35.0 → roundUp5 = **35** → 35 < 50 → **minimum branch fires**
- interest = **₹50**, note = **"Minimum ₹50 interest applied"**
- total = **₹10,050**

| Step | Action | Expected Result | P/F |
|------|--------|-----------------|-----|
| 1 | Open the close/interest screen for pledge #3201 (L2) | Closure preview screen shown | |
| 2 | Verify interest displayed | **₹50** | |
| 3 | Verify the note shown | **"Minimum ₹50 interest applied"** | |
| 4 | Verify total | **₹10,050** | |
| 5 | **Cancel / go back — do NOT complete the closure** | L2 remains open | |

---

## TC-02-05: Edge Case — Rounds to Exactly ₹50, Minimum Branch Does NOT Fire (L3, Preview Only)

Pledge #3202 · ₹13,000 principal

Expected calculation:
- rawDays = 0, effectiveDays = 7
- rawInterest = 13,000 × 0.0035 = 45.5 → roundUp5 = ceil(9.1)×5 = **50** → 50 is NOT < 50 → **minimum branch skipped**
- interest = **₹50**, note = **"Minimum 7 days applied"** (NOT "Minimum ₹50 interest applied")
- total = **₹13,050**

| Step | Action | Expected Result | P/F |
|------|--------|-----------------|-----|
| 1 | Open the close/interest screen for pledge #3202 (L3) | Closure preview screen shown | |
| 2 | Verify interest displayed | **₹50** | |
| 3 | Verify the note shown | **"Minimum 7 days applied"** — must NOT say "Minimum ₹50 interest applied" | |
| 4 | Verify total | **₹13,050** | |
| 5 | **Cancel / go back — do NOT complete the closure** | L3 remains open | |

> **Boundary check:** L2 (₹10,000) and L3 (₹13,000) both produce ₹50 interest. The observable difference is the note text. If the app shows the same note for both, the minimum-₹50 floor and the rounding-to-50 paths are not distinguished — that is a bug.

---

## TC-02-06: Loan Detail — Payment History (L1)

| Step | Action | Expected Result | P/F |
|------|--------|-----------------|-----|
| 1 | Open closed pledge #3200 (L1) detail | — | |
| 2 | Find the payment / transaction history section | 2 entries shown | |
| 3 | Entry 1 | Type: LOAN_DISBURSED, direction: out, amount: ₹50,000 | |
| 4 | Entry 2 | Type: LOAN_FULL_CLOSURE, direction: in, amount: ₹50,175 | |

---

## TC-02-07: Verify Open Loan Count After This Doc

| Step | Action | Expected Result | P/F |
|------|--------|-----------------|-----|
| 1 | Navigate to Open Loans list | **9 open loans**: #3201–#3209 | |
| 2 | Confirm #3200 is absent | Absent ✓ | |
| 3 | Confirm #3201 and #3202 are still open | Present ✓ (closures were cancelled) | |

---

## Running Totals After Doc 02

Gold Stock (T):
- Gold OUT added: L1 (#3200) closed → +20g, +1 item
- Gold IN: 163g, 10 items (unchanged from doc 01)
- Gold OUT so far: 20g, 1 item
- Closing stock after doc 02: **143g, 9 items**

Cash Book (T):
- Cash IN added: ₹50,175 (L1 LOAN_FULL_CLOSURE)
- Running Cash IN: ₹50,175
- Running Cash OUT: ₹2,43,000 (loans) — unchanged from doc 01
- Opening: ₹5,00,000 (backdated entries not yet done)
- Balance so far: 5,00,000 + 50,175 − 2,43,000 = **₹3,07,175** (partial; more follows)
