# Dataset Reference — CM Bank Manual Regression Test Plan

This file is the single source of truth for every expected value used across all 13 numbered test documents. All arithmetic was computed from the live source code before this file was written.

---

## 1. Substitute These Dates Before Starting

| Label | Meaning | Example |
|-------|---------|---------|
| **T** | The actual date testing begins | 2026-06-21 |
| **T-1** | The calendar day before T | 2026-06-20 |
| **T-2** | Two calendar days before T | 2026-06-19 |

---

## 2. First Launch Wizard Settings

| Field | Value |
|-------|-------|
| Business Name | CM Bank |
| Staff PIN | 111111 |
| Admin PIN | 999999 |
| Biometric Login | OFF |
| Interest Rate | 18.00 % p.a. |
| Pledge Rate | ₹2,500 per gram |
| Starting Pledge Number | 3200 |
| Opening Cash | ₹5,00,000 |
| Opening UPI | ₹0 |
| Opening Stock Weight | 0 g |
| Opening Stock Count | 0 items |

---

## 3. Interest Calculation Rules (confirmed from source code)

```
rawDays       = toDate.difference(fromDate).inDays
effectiveDays = max(rawDays, 7)           ← minimum 7 days
rawInterest   = principal × effectiveDays / 360 × rate / 100
interest      = ceil(rawInterest / 5) × 5  ← round UP to nearest ₹5
if interest < 50 → interest = 50, note = "Minimum ₹50 interest applied"
```

Factor used throughout (18 % rate, 7-day minimum): **P × 0.0035**

Rounding check for ₹50 minimum:
- If `ceil(rawInterest/5)×5 < 50` → minimum branch triggers, note says "₹50 minimum"
- If `ceil(rawInterest/5)×5 == 50` → no minimum branch (result is exactly ₹50 from rounding), note says "Minimum 7 days applied"
- If `ceil(rawInterest/5)×5 > 50` → normal result

---

## 4. Customers

| ID | Name | Phone |
|----|------|-------|
| C1 | Rajan Kumar | 9876543210 |
| C2 | Meena Devi | 9123456789 |
| C3 | Suresh Pillai | 9988776655 |

C1 is created inline when opening L1. C2 inline with L4. C3 inline with L6.
All three customers are reused by later loans (tests "existing customer" path).

---

## 5. Primary Loans (created in Doc 01, all dated T)

All loans disbursed in **cash**. Interest rate 18 % throughout.

| Label | Pledge # | Customer | Principal | Item Type | Purity | Gross Wt | Net Wt | Qty |
|-------|----------|----------|-----------|-----------|--------|----------|--------|-----|
| L1 | 3200 | C1 (new) | ₹50,000 | Necklace | 22K | 22 g | 20 g | 1 |
| L2 | 3201 | (none) | ₹10,000 | Ring | 22K | 6 g | 5 g | 1 |
| L3 | 3202 | (none) | ₹13,000 | Bangle | 22K | 14 g | 12 g | 1 |
| L4 | 3203 | C2 (new) | ₹30,000 | Chain | 22K | 26 g | 24 g | 1 |
| L5 | 3204 | C2 (existing) | ₹20,000 | Bracelet | 22K | 22 g | 20 g | 1 |
| L6 | 3205 | C3 (new) | ₹25,000 | Anklet | 22K | 22 g | 20 g | 1 |
| L7 | 3206 | C3 (existing) | ₹15,000 | Coin | 916 | 14 g | 12 g | 1 |
| L8 | 3207 | C1 (existing) | ₹18,000 | Ring | 916 | 10 g | 9 g | 1 |
| L9 | 3208 | C2 (existing) | ₹40,000 | Earring | 916 | 11 g | 10 g | 1 |
| L10 | 3209 | C3 (existing) | ₹22,000 | Pendant | 22K | 17 g | 15 g | 1 |

**Pledge number sequence start:** `new_pledge_last_number` = 0 → `starting_pledge_number` = 3200 → first pledge = 3200. Each creation advances the counter by 1.

**Auto-fill note:** With pledge rate ₹2,500/g, auto-fill = net weight × 2,500. Only L1 matches auto-fill exactly (20 g × 2,500 = ₹50,000). All others require the tester to clear the auto-filled amount and enter the principal from this table.

### 5a. 7-Day Same-Day Interest (all loans closed on T = 0 raw days → 7 effective days)

| Label | Principal | rawInterest (P×0.0035) | roundUp5 | < ₹50? | Interest | Note shown |
|-------|-----------|------------------------|----------|--------|----------|------------|
| L1 | ₹50,000 | 175.00 | **175** | No | **₹175** | "Minimum 7 days applied" |
| L2 | ₹10,000 | 35.00 | 35 | **Yes** | **₹50** | "Minimum ₹50 interest applied" |
| L3 | ₹13,000 | 45.50 | ceil(9.1)×5 = **50** | **No** | **₹50** | "Minimum 7 days applied" |
| L4 | ₹30,000 | 105.00 | **105** | No | **₹105** | "Minimum 7 days applied" |
| L5 | ₹20,000 | 70.00 | **70** | No | **₹70** | "Minimum 7 days applied" |
| L6 | ₹25,000 | 87.50 | ceil(17.5)×5 = **90** | No | **₹90** | "Minimum 7 days applied" |
| L7 | ₹15,000 | 52.50 | ceil(10.5)×5 = **55** | No | **₹55** | "Minimum 7 days applied" |
| L8 | ₹18,000 | 63.00 | ceil(12.6)×5 = **65** | No | **₹65** | "Minimum 7 days applied" |
| L9 | ₹40,000 | 140.00 | **140** | No | **₹140** | "Minimum 7 days applied" |
| L10 | ₹22,000 | 77.00 | ceil(15.4)×5 = **80** | No | **₹80** | "Minimum 7 days applied" |

**Boundary distinction between L2 and L3:**
- L2 (₹10,000): rawInterest 35.0 → roundUp5 = 35 < 50 → minimum branch fires → note = "Minimum ₹50 interest applied"
- L3 (₹13,000): rawInterest 45.5 → roundUp5 = ceil(9.1)×5 = 50 → 50 is NOT < 50 → minimum branch does NOT fire → note = "Minimum 7 days applied"

Both show ₹50 interest. The NOTE TEXT is the observable difference. This tests the exact threshold where rounding brings the value to ₹50 without the minimum-₹50 branch activating.

---

## 6. Renewal, Part-Payment, and Top-Up Pledges (created in Doc 03, all dated T)

All renewals happen same-day as opening (T), so effectiveDays = 7 and interest values from §5a apply.

New pledge numbers continue the counter after L1–L10 (last used = 3209):

| Old Label | New Label | New Pledge # | Flow | Interest on Old Pledge | Payment Collected (Cash IN) | New Principal |
|-----------|-----------|-------------|------|------------------------|----------------------------|---------------|
| L4 | L4R | 3210 | Renew → Pay Interest | ₹105 | ₹105 (RENEWAL_INTEREST_PAID) | ₹30,000 |
| L5 | L5R | 3211 | Renew → Capitalise | ₹70 | **₹0** (no payment) | ₹20,070 |
| L6 | L6R | 3212 | Part Pay: Principal + Interest | ₹90 | ₹5,090 (PART_PAYMENT_RECEIVED) | ₹20,000 |
| L7 | L7R | 3213 | Part Pay: Fixed ≤ Interest | ₹55 | ₹30 (PART_PAYMENT_RECEIVED) | ₹15,025 |
| L8 | L8R | 3214 | Part Pay: Fixed > Interest | ₹65 | ₹3,065 (PART_PAYMENT_RECEIVED) | ₹15,000 |
| L9 | L9R | 3215 | Top-Up: Pay Interest Now | ₹140 | ₹0 (disbursal, see below) | ₹50,000 |
| L10 | L10R | 3216 | Top-Up: Add to Pledge | ₹80 | ₹0 (disbursal, see below) | ₹30,080 |

### 6a. Renewal Detail — Pay Interest (L4 → L4R)

- User confirms: renew type = "Renew", subtype = "Pay Interest Now"
- Interest on L4: ₹105 (cash collected from customer)
- New pledge L4R: same gold (Chain 24g), principal = ₹30,000
- Ledger entry on old pledge: RENEWAL_INTEREST_PAID, direction=IN, cash=₹105

### 6b. Renewal Detail — Capitalise Interest (L5 → L5R)

- User confirms: renew type = "Renew", subtype = "Add Interest to Pledge"
- No cash payment
- New pledge L5R: same gold (Bracelet 20g), principal = ₹20,000 + ₹70 = ₹20,070
- No ledger entry (onPayment = null)

### 6c. Part Payment — Principal + Interest (L6 → L6R)

Screen logic: user enters **principal portion** to pay off = ₹5,000
```
principalPaid = 5,000
totalPaid     = 5,000 + 90 = 5,090   ← displayed as "Total to Collect"
newPrincipal  = 25,000 - 5,000 = 20,000
```
- Cash collected: ₹5,090
- Ledger: PART_PAYMENT_RECEIVED, sub=PRINCIPAL_AND_INTEREST, cash=₹5,090

### 6d. Part Payment — Fixed Amount LESS than interest (L7 → L7R)

Screen logic: user enters **fixed total amount** = ₹30 (less than interest ₹55)
```
intPaid      = min(30, 55) = 30
unpaidInt    = 55 - 30 = 25
newPrincipal = 15,000 + 25 = 15,025
totalPay     = 30
```
- Cash collected: ₹30
- Ledger: PART_PAYMENT_RECEIVED, sub=FIXED_AMOUNT_INCLUSIVE, cash=₹30

### 6e. Part Payment — Fixed Amount MORE than interest (L8 → L8R)

Screen logic: user enters **fixed total amount** = ₹3,065 (more than interest ₹65)
```
intPaid       = min(3065, 65) = 65
principalPaid = 3,065 - 65  = 3,000
newPrincipal  = 18,000 - 3,000 = 15,000
totalPay      = 3,065
```
- Cash collected: ₹3,065
- Ledger: PART_PAYMENT_RECEIVED, sub=FIXED_AMOUNT_INCLUSIVE, cash=₹3,065

### 6f. Top-Up — Pay Interest Now, not capitalised (L9 → L9R)

User enters new pledge amount = ₹50,000 (must be > L9 principal + interest = 40,140)
```
ilFinalAmt  = 50,000    (intSub='pay': ilFinalAmt = ilNewAmt)
netDisburse = 50,000 - 40,000 - 140 = 9,860   ← Cash OUT to customer
```
- New pledge L9R: principal = ₹50,000
- Ledger on new pledge: LOAN_INCREASE_DISBURSED, direction=OUT, cash=₹9,860

### 6g. Top-Up — Add Interest to Pledge, capitalised (L10 → L10R)

User enters new pledge amount = ₹30,000 (before capitalisation)
```
ilFinalAmt  = 30,000 + 80 = 30,080   (intSub='add': adds interest to new amount)
netDisburse = 30,080 - 22,000 - 80  = 8,000   ← Cash OUT to customer
```
- New pledge L10R: principal = ₹30,080
- Ledger on new pledge: LOAN_INCREASE_DISBURSED, direction=OUT, cash=₹8,000

---

## 7. Migrated Pledge (Doc 04 — Add Existing Loan)

| Label | Pledge # | Customer | Start Date | Principal | Item | Net Wt |
|-------|----------|----------|------------|-----------|------|--------|
| LM1 | 1500 | C1 (existing) | T-30 | ₹35,000 | Necklace, 22K | 18 g |

LM1 interest when closed on T (30 calendar days):
```
rawDays = 30 ≥ 7 → effectiveDays = 30
rawInterest = 35,000 × 30/360 × 0.18 = 35,000 × 0.015 = 525.0
roundUp5(525) = 525   ← already multiple of 5, and 525 ≥ 50
interest = ₹525, total = ₹35,525
```

**Gold Stock behaviour:** LM1 source='migrated' → does NOT appear in Gold IN when loaded.
LM1 closure → DOES appear in Gold OUT (it has pledge_items, inner JOIN picks it up).
Net effect on stock register: closing count is 1 lower than physical count for T.

The pledge counter is NOT advanced when loading a migrated pledge (manually entered number 1500).
Next pledge after all renewals L4R–L10R = **3217**.

---

## 8. Backdated Pledge (Doc 05 — Cash Book)

| Label | Pledge # | Customer | Date Opened | Principal | Item | Net Wt | Date Closed |
|-------|----------|----------|-------------|-----------|------|--------|-------------|
| L11 | 3217 | C3 (existing) | T-2 | ₹20,000 | Necklace, 22K | 15 g | T-1 |

L11 interest (opened T-2, closed T-1, rawDays=1 → effectiveDays=7):
```
rawInterest = 20,000 × 0.0035 = 70.0
roundUp5(70) = 70 ≥ 50
interest = ₹70, note = "Minimum 7 days applied", total = ₹20,070
```

---

## 9. Calculator-Only Manual Closure (Doc 08)

| Pledge # | Principal | Opened | Closed | Days | Interest | Total |
|----------|-----------|--------|--------|------|----------|-------|
| 999 | ₹20,000 | T-30 | T | 30 | ₹300 | ₹20,300 |

Calculation:
```
rawDays = 30 ≥ 7 → effectiveDays = 30
rawInterest = 20,000 × 30/360 × 0.18 = 300.0
roundUp5(300) = 300, total = ₹20,300
```
`createManualClosedPledge` is called (no pledge_items inserted, no gold stock impact).
Ledger: LOAN_FULL_CLOSURE, direction=IN, cash=₹20,300 on T.

---

## 10. Running Cash Balances

### T-2 (from Doc 05 backdated entries)
| | Cash | UPI |
|-|------|-----|
| Opening | ₹5,00,000 | ₹0 |
| Cash OUT | ₹20,000 (L11 disbursed, LOAN_DISBURSED) | — |
| Cash IN | ₹0 | — |
| **Closing** | **₹4,80,000** | **₹0** |

### T-1 (from Doc 05 backdated entries)
| | Cash | UPI |
|-|------|-----|
| Opening | ₹4,80,000 (from T-2 closing) | ₹0 |
| Cash IN | ₹20,070 (L11 closure, LOAN_FULL_CLOSURE) | — |
| Cash OUT | ₹0 | — |
| **Closing** | **₹5,00,070** | **₹0** |

### T (after all docs 01–08 complete, before locking)

The Cash Book for T shows these ledger totals (all amounts cash; UPI = ₹0 throughout):

**Cash OUT breakdown:**
| Entry | Amount | Type |
|-------|--------|------|
| L1 disbursed | ₹50,000 | LOAN_DISBURSED |
| L2 disbursed | ₹10,000 | LOAN_DISBURSED |
| L3 disbursed | ₹13,000 | LOAN_DISBURSED |
| L4 disbursed | ₹30,000 | LOAN_DISBURSED |
| L5 disbursed | ₹20,000 | LOAN_DISBURSED |
| L6 disbursed | ₹25,000 | LOAN_DISBURSED |
| L7 disbursed | ₹15,000 | LOAN_DISBURSED |
| L8 disbursed | ₹18,000 | LOAN_DISBURSED |
| L9 disbursed | ₹40,000 | LOAN_DISBURSED |
| L10 disbursed | ₹22,000 | LOAN_DISBURSED |
| L9R top-up extra | ₹9,860 | LOAN_INCREASE_DISBURSED |
| L10R top-up extra | ₹8,000 | LOAN_INCREASE_DISBURSED |
| Rent expense | ₹5,000 | EXPENSE |
| **Total Cash OUT** | **₹2,65,860** | |

**Cash IN breakdown:**
| Entry | Amount | Type |
|-------|--------|------|
| L1 closure | ₹50,175 | LOAN_FULL_CLOSURE |
| LM1 closure | ₹35,525 | LOAN_FULL_CLOSURE |
| #999 calculator closure | ₹20,300 | LOAN_FULL_CLOSURE |
| L4R renewal interest | ₹105 | RENEWAL_INTEREST_PAID |
| L6R part payment | ₹5,090 | PART_PAYMENT_RECEIVED |
| L7R part payment | ₹30 | PART_PAYMENT_RECEIVED |
| L8R part payment | ₹3,065 | PART_PAYMENT_RECEIVED |
| **Total Cash IN** | **₹1,14,290** | |

**T summary:**
| | Cash | UPI |
|-|------|-----|
| Opening | ₹5,00,070 (from T-1 closing) | ₹0 |
| Cash IN | ₹1,14,290 | ₹0 |
| Cash OUT | ₹2,65,860 | ₹0 |
| **Closing** | **₹3,48,500** | **₹0** |

> **Note — cascade timing:** Before doc 05 backdated entries are created, T's opening shows ₹5,00,000 (from settings). After L11 is created on T-2 and closed on T-1, the cascade updates T's opening to ₹5,00,070. The tester must navigate away from T and return to see the updated figure. Before doc 08's calculator closure is recorded, T closing shows ₹3,28,200 (= 5,00,070 + 93,990 − 2,65,860). After recording pledge #999's closure (₹20,300 Cash IN), T closing becomes ₹3,48,500. After rounding check: 5,00,070 + 1,14,290 − 2,65,860 = **₹3,48,500**.

> **Note — renewal pledges do NOT generate a LOAN_DISBURSED entry.** `createRenewalPledge` does not write a payment row. Only the specific payment for each renewal type is recorded (RENEWAL_INTEREST_PAID, PART_PAYMENT_RECEIVED, or LOAN_INCREASE_DISBURSED for top-ups).

---

## 11. Gold Stock

### T-2
| | Weight | Item count (pledge_items rows) |
|-|--------|-------------------------------|
| Opening | 0 g | 0 |
| Gold IN | 15 g | 1 (L11 Necklace) |
| Gold OUT | 0 g | 0 |
| **Closing** | **15 g** | **1** |

### T-1
| | Weight | Item count |
|-|--------|-----------|
| Opening | 15 g | 1 |
| Gold IN | 0 g | 0 |
| Gold OUT | 15 g | 1 (L11 closed) |
| **Closing** | **0 g** | **0** |

### T
| | Weight | Item count |
|-|--------|-----------|
| Opening | 0 g | 0 (from T-1 closing) |
| Gold IN | 273 g | 17 |
| Gold OUT | 148 g | 9 |
| **Closing** | **125 g** | **8** |

**Gold IN (T) — source='new' pledges with start_date=T:**
L1(20g) + L2(5g) + L3(12g) + L4(24g) + L5(20g) + L6(20g) + L7(12g) + L8(9g) + L9(10g) + L10(15g) = **163 g, 10 items**
PLUS renewal new pledges L4R(24g) + L5R(20g) + L6R(20g) + L7R(12g) + L8R(9g) + L9R(10g) + L10R(15g) = **110 g, 7 items**
Total IN: **273 g, 17 items**

**Gold OUT (T) — closed pledges with closed_at on T, with pledge_items rows:**
L1(20g) + L4(24g) + L5(20g) + L6(20g) + L7(12g) + L8(9g) + L9(10g) + L10(15g) + LM1(18g) = **148 g, 9 items**

LM1 (source='migrated') never appeared in Gold IN but DOES appear in Gold OUT (query filters only by closed_at, not by source).

**Items remaining open at end of T:**
L2 (5g Ring) + L3 (12g Bangle) + L4R (24g Chain) + L5R (20g Bracelet) + L6R (20g Anklet) + L7R (12g Coin) + L8R (9g Ring) + L9R (10g Earring) + L10R (15g Pendant) = **9 pledges, 143 g physical gold**

System closing shows **8 items, 125 g** because LM1 reduced the count on Gold OUT without ever being added to Gold IN (pre-existing pledge). This is expected behaviour.

---

## 12. Open Pledges at End of Test Session

| Pledge # | Label | Customer | Principal | Gold |
|----------|-------|----------|-----------|------|
| 3201 | L2 | (none) | ₹10,000 | Ring 22K 5g |
| 3202 | L3 | (none) | ₹12,857 | Bangle 22K 12g |
| 3210 | L4R | C2 Meena Devi | ₹30,000 | Chain 22K 24g |
| 3211 | L5R | C2 Meena Devi | ₹20,070 | Bracelet 22K 20g |
| 3212 | L6R | C3 Suresh Pillai | ₹20,000 | Anklet 22K 20g |
| 3213 | L7R | C3 Suresh Pillai | ₹15,025 | Coin 916 12g |
| 3214 | L8R | C1 Rajan Kumar | ₹15,000 | Ring 916 9g |
| 3215 | L9R | C2 Meena Devi | ₹50,000 | Earring 916 10g |
| 3216 | L10R | C3 Suresh Pillai | ₹30,080 | Pendant 22K 15g |

---

## 13. Pledge Counter at Each Phase

| After | Last Used | Next Pledge # |
|-------|-----------|---------------|
| Doc 01 (L1–L10 created) | 3209 | 3210 |
| Doc 03 (L4R–L10R created) | 3216 | 3217 |
| Doc 04 (LM1 migrated — counter NOT advanced) | 3216 | 3217 |
| Doc 05 (L11 created via backdated Cash Book) | 3217 | 3218 |

---

## 14. Expense Categories (from seed data)

Rent · Electricity · Staff Salary · Office Supplies · Other

Used in Doc 05: **Rent, ₹5,000 cash**

---

## 15. Lock Sequence (Cash Book)

| Day | Locked in | Expected closing (cash) |
|-----|-----------|------------------------|
| T-2 | Doc 05 | ₹4,80,000 |
| T-1 | Doc 05 | ₹5,00,070 |
| T | After all docs complete | ₹3,48,500 |

Sequential lock guard rule: previous calendar day must be locked before current day can be locked, EXCEPT when locking the very first record date (which has no earlier daily_balance rows).

---

## 16. Purity Types (from seed data)

916 · 22K · Other
