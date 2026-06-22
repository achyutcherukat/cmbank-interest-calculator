# 00 — First Launch Setup

**Pre-condition:** Fresh app install (no prior database). Device date = T.
**Reference:** See `dataset_reference.md §2` for all wizard values.

---

## TC-00-01: App First Launch — Setup Wizard Appears

| Step | Action | Expected Result | P/F |
|------|--------|-----------------|-----|
| 1 | Launch the CM Bank app for the first time | "First Setup" screen opens — NOT the login screen | |
| 2 | Observe the form layout | Sections visible: Business, Login PINs, Defaults, Starting Pledge Number, Opening Balances, Opening Stock | |

---

## TC-00-02: Business Name

| Step | Action | Expected Result | P/F |
|------|--------|-----------------|-----|
| 1 | Clear the Business Name field (default is "CM Bank") | Field is blank | |
| 2 | Attempt to tap Save with blank Business Name | Validation error shown on field | |
| 3 | Enter **CM Bank** | Field contains "CM Bank" | |

---

## TC-00-03: Staff PIN Setup and Validation

| Step | Action | Expected Result | P/F |
|------|--------|-----------------|-----|
| 1 | Tap the "Common Staff PIN" field | Numeric keyboard appears | |
| 2 | Enter **111111** | 6 dots / masked characters shown | |
| 3 | Enter **222222** in Confirm Staff PIN | Field shows 6 masked characters | |
| 4 | Attempt to Save | Validation error: PINs do not match | |
| 5 | Clear Confirm Staff PIN, enter **111111** | Confirm field shows 6 masked characters | |

---

## TC-00-04: Admin PIN Setup

| Step | Action | Expected Result | P/F |
|------|--------|-----------------|-----|
| 1 | Enter **999999** in Admin PIN field | 6 masked characters shown | |
| 2 | Enter **999999** in Confirm Admin PIN | Confirm matches | |
| 3 | Leave Biometric toggle OFF | Toggle is in off position | |

---

## TC-00-05: Financial Defaults

| Step | Action | Expected Result | P/F |
|------|--------|-----------------|-----|
| 1 | Verify Interest Rate field shows **18.00** | Default pre-filled | |
| 2 | Enter **0** in Interest Rate, attempt Save | Validation error (must be positive) | |
| 3 | Restore to **18.00** | Field shows 18.00 | |
| 4 | Enter **2500** in Pledge Rate field | Field shows 2500 | |
| 5 | Verify Starting Pledge Number shows **3200** | Default pre-filled | |

---

## TC-00-06: Opening Balances

| Step | Action | Expected Result | P/F |
|------|--------|-----------------|-----|
| 1 | Enter **500000** in Opening Cash | Field shows 500000 | |
| 2 | Leave Opening UPI at **0** | Field shows 0 | |
| 3 | Leave Opening Stock Weight at **0** | — | |
| 4 | Leave Opening Stock Count at **0** | — | |

---

## TC-00-07: Save Setup

| Step | Action | Expected Result | P/F |
|------|--------|-----------------|-----|
| 1 | Tap Save / Complete Setup | Progress indicator shown briefly | |
| 2 | Observe navigation | App transitions to the Login screen or Home screen | |
| 3 | If Login screen appears, enter Staff PIN **111111** | Home screen is shown | |

---

## TC-00-08: Post-Setup State Verification

| Step | Action | Expected Result | P/F |
|------|--------|-----------------|-----|
| 1 | Kill and relaunch the app | Login screen appears (NOT the First Setup wizard) | |
| 2 | Enter Staff PIN **111111** | Home screen opens | |
| 3 | Enter wrong PIN (e.g., **000000**) | Error shown, login rejected | |
| 4 | Enter correct PIN **111111** | Home screen opens | |

---

## TC-00-09: Admin Login

| Step | Action | Expected Result | P/F |
|------|--------|-----------------|-----|
| 1 | Find the Admin login option (separate button or screen) | Admin PIN prompt shown | |
| 2 | Enter Admin PIN **999999** | Admin home or admin-level home screen appears | |
| 3 | Return to Staff view | Staff home screen accessible | |

---

## Notes for Following Docs

- All subsequent tests assume the app is logged in as Staff (PIN 111111) unless a step explicitly says "log in as Admin."
- Device date remains T throughout docs 01–12 unless a step navigates to a backdated date inside the app's date pickers.
