# 01 — New Loans

**Pre-condition:** Doc 00 complete. Logged in as Staff. Device date = T.
**Reference:** `dataset_reference.md §5`, §13

This document creates loans L1–L10 (pledge numbers 3200–3209). They must be created in the order shown; the pledge counter advances automatically.

---

## TC-01-01: L1 — Standard New Loan With New Customer (Auto-fill Test)

Pledge #3200 · Customer C1 (Rajan Kumar) · 22K Necklace · ₹50,000 cash

| Step | Action | Expected Result | P/F |
|------|--------|-----------------|-----|
| 1 | Navigate to New Loan screen | New Loan form opens | |
| 2 | Observe the pledge number field | Shows **3200** (auto-generated) | |
| 3 | Enter gross weight **22** g | Field accepts the value | |
| 4 | Enter net weight **20** g | Field accepts the value | |
| 5 | Select purity **22K** | Purity selected | |
| 6 | Select item type **Necklace** | Item type selected | |
| 7 | Observe the loan amount field | Auto-fills to **₹50,000** (20 g × ₹2,500) | |
| 8 | Leave loan amount at ₹50,000 | — | |
| 9 | Select payment mode **Cash** | Cash selected; cash field shows ₹50,000 | |
| 10 | Tap "Add Customer" or the customer field | Customer entry form / search opens | |
| 11 | Enter name **Rajan Kumar**, phone **9876543210** | Customer form accepts values | |
| 12 | Save the new customer | Customer attached to the loan | |
| 13 | Optionally add a photo (skip if slow; not required for core test) | — | |
| 14 | Tap Save / Create Loan | Loan created, confirmation shown | |
| 15 | Verify pledge number on confirmation | Shows **3200** | |
| 16 | Verify loan amount | Shows **₹50,000** | |

---

## TC-01-02: L2 — No Customer, Minimum Interest Edge Case

Pledge #3201 · No customer · 22K Ring · ₹10,000 cash

This loan is designed to trigger the **₹50 minimum interest** rule when closed same-day.
rawInterest = 10,000 × 0.0035 = **35.00 → rounds to 35 < 50 → minimum ₹50 applied**.

| Step | Action | Expected Result | P/F |
|------|--------|-----------------|-----|
| 1 | Open New Loan screen | Pledge number shows **3201** | |
| 2 | Enter gross weight **6** g, net weight **5** g | — | |
| 3 | Select purity **22K**, item type **Ring** | — | |
| 4 | Clear auto-filled loan amount, enter **10000** | Loan amount = ₹10,000 | |
| 5 | Select payment mode **Cash** | — | |
| 6 | Leave customer blank (no customer) | No customer attached | |
| 7 | Tap Save | Loan created as **₹10,000** with no customer | |
| 8 | Verify pledge #3201 | Confirmed | |

---

## TC-01-03: L3 — Minimum Interest Boundary (rounds to exactly ₹50, minimum branch does NOT fire)

Pledge #3202 · No customer · 22K Bangle · ₹13,000 cash

rawInterest = 13,000 × 0.0035 = 45.50 → ceil(45.5/5)×5 = ceil(9.1)×5 = **50** → 50 is NOT < 50 → minimum branch skipped.
Result: ₹50 interest with note **"Minimum 7 days applied"** (not "Minimum ₹50 interest applied").
Compare with L2 (₹10,000) which shows the same ₹50 but with a different note.

| Step | Action | Expected Result | P/F |
|------|--------|-----------------|-----|
| 1 | Open New Loan screen | Pledge number shows **3202** | |
| 2 | Gross weight **14** g, net weight **12** g, purity **22K**, type **Bangle** | — | |
| 3 | Enter loan amount **13000** | ₹13,000 | |
| 4 | Payment mode **Cash**, no customer | — | |
| 5 | Save | Pledge #3202 created | |

---

## TC-01-04: L4 — For Renewal (Renew → Pay Interest)

Pledge #3203 · Customer C2 (Meena Devi, new) · 22K Chain · ₹30,000 cash

| Step | Action | Expected Result | P/F |
|------|--------|-----------------|-----|
| 1 | Open New Loan screen | Pledge number shows **3203** | |
| 2 | Gross **26** g, net **24** g, purity **22K**, type **Chain** | — | |
| 3 | Clear auto-fill, enter loan amount **30000** | — | |
| 4 | Payment mode **Cash** | — | |
| 5 | Add new customer: name **Meena Devi**, phone **9123456789** | Customer attached | |
| 6 | Save | Pledge #3203 created | |

---

## TC-01-05: L5 — Same Customer (C2), For Renewal (Capitalise)

Pledge #3204 · Customer C2 (Meena Devi, existing) · 22K Bracelet · ₹20,000 cash

| Step | Action | Expected Result | P/F |
|------|--------|-----------------|-----|
| 1 | Open New Loan screen | Pledge number shows **3204** | |
| 2 | Gross **22** g, net **20** g, purity **22K**, type **Bracelet** | — | |
| 3 | Enter loan amount **20000** | — | |
| 4 | Payment mode **Cash** | — | |
| 5 | Add customer: search for **9123456789** or "Meena Devi" | **Existing customer C2 found and attached** (tests existing-customer path) | |
| 6 | Save | Pledge #3204 created with same customer as L4 | |

---

## TC-01-06: L6 — New Customer C3, For Part Payment P+I

Pledge #3205 · Customer C3 (Suresh Pillai, new) · 22K Anklet · ₹25,000 cash

| Step | Action | Expected Result | P/F |
|------|--------|-----------------|-----|
| 1 | Open New Loan screen | Pledge number shows **3205** | |
| 2 | Gross **22** g, net **20** g, purity **22K**, type **Anklet** | — | |
| 3 | Enter loan amount **25000** | — | |
| 4 | Payment mode **Cash** | — | |
| 5 | Add new customer: **Suresh Pillai**, phone **9988776655** | Customer C3 created and attached | |
| 6 | Save | Pledge #3205 created | |

---

## TC-01-07: L7 — Same Customer C3, For Part Payment Fixed ≤ Interest

Pledge #3206 · Customer C3 (existing) · 916 Coin · ₹15,000 cash

| Step | Action | Expected Result | P/F |
|------|--------|-----------------|-----|
| 1 | Open New Loan screen | Pledge number shows **3206** | |
| 2 | Gross **14** g, net **12** g, purity **916**, type **Coin** | — | |
| 3 | Enter loan amount **15000** | — | |
| 4 | Payment mode **Cash** | — | |
| 5 | Attach existing customer C3 (search "9988776655" or "Suresh Pillai") | C3 found and attached | |
| 6 | Save | Pledge #3206 created | |

---

## TC-01-08: L8 — Same Customer C1, For Part Payment Fixed > Interest

Pledge #3207 · Customer C1 (existing) · 916 Ring · ₹18,000 cash

| Step | Action | Expected Result | P/F |
|------|--------|-----------------|-----|
| 1 | Open New Loan screen | Pledge number shows **3207** | |
| 2 | Gross **10** g, net **9** g, purity **916**, type **Ring** | — | |
| 3 | Enter loan amount **18000** | — | |
| 4 | Payment mode **Cash** | — | |
| 5 | Attach existing customer C1 (search "9876543210") | C1 found | |
| 6 | Save | Pledge #3207 created | |

---

## TC-01-09: L9 — For Top-Up (Pay Interest Now)

Pledge #3208 · Customer C2 (existing) · 916 Earring · ₹40,000 cash

| Step | Action | Expected Result | P/F |
|------|--------|-----------------|-----|
| 1 | Open New Loan screen | Pledge number shows **3208** | |
| 2 | Gross **11** g, net **10** g, purity **916**, type **Earring** | — | |
| 3 | Enter loan amount **40000** | — | |
| 4 | Payment mode **Cash** | — | |
| 5 | Attach existing customer C2 (Meena Devi) | Attached | |
| 6 | Save | Pledge #3208 created | |

---

## TC-01-10: L10 — For Top-Up (Capitalise Interest)

Pledge #3209 · Customer C3 (existing) · 22K Pendant · ₹22,000 cash

| Step | Action | Expected Result | P/F |
|------|--------|-----------------|-----|
| 1 | Open New Loan screen | Pledge number shows **3209** | |
| 2 | Gross **17** g, net **15** g, purity **22K**, type **Pendant** | — | |
| 3 | Enter loan amount **22000** | — | |
| 4 | Payment mode **Cash** | — | |
| 5 | Attach existing customer C3 (Suresh Pillai) | Attached | |
| 6 | Save | Pledge #3209 created | |

---

## TC-01-11: Verify Open Loans List

| Step | Action | Expected Result | P/F |
|------|--------|-----------------|-----|
| 1 | Navigate to Active / Open Loans list | List displayed, newest first | |
| 2 | Verify pledge #3209 appears at the top | ✓ | |
| 3 | Verify pledge #3200 appears in list | ✓ | |
| 4 | Count open pledges | **10 open pledges** (3200–3209) | |
| 5 | Verify pledge #3201 shows "(No Customer)" or similar | Customer field blank for L2, L3 | |

---

## TC-01-12: Multiple Loans for Same Customer

| Step | Action | Expected Result | P/F |
|------|--------|-----------------|-----|
| 1 | Find any way to view C2's (Meena Devi) loans from the loan list or customer detail | Loans #3203 (L4), #3204 (L5), and #3208 (L9) are all associated with C2 | |
| 2 | Find C3's (Suresh Pillai) loans | Loans #3205 (L6), #3206 (L7), and #3209 (L10) are all associated with C3 | |

---

## Running Totals After Doc 01

Gold Stock (T):
- Gold IN: **163 g, 10 items** (L1–L10, all source='new')
- Gold OUT: 0 (no closures yet)
- Closing stock: **163 g, 10 items**

Cash Book (T):
- Cash OUT (loans): ₹2,65,000
  - L1–L10 combined: 50,000+10,000+12,857+30,000+20,000+25,000+15,000+18,000+40,000+22,000
  - **= ₹2,42,857**

Wait — note that L3 principal is ₹12,857, so total is:
50,000 + 10,000 + 12,857 + 30,000 + 20,000 + 25,000 + 15,000 + 18,000 + 40,000 + 22,000 = **₹2,42,857**

Opening: ₹5,00,000 → after disbursals: ₹5,00,000 − ₹2,43,000 = **₹2,57,000** (partial running total; more transactions follow in docs 02–08)
