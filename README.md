# CryptoRiskEngine

**Dynamic Risk Modeling for Cryptocurrency-Backed Loans on Stacks**

---

## 🚀 Overview

The `CryptoRiskEngine` is a robust Clarity smart contract designed to implement a **dynamic risk assessment system** for overcollateralized cryptocurrency loans. It moves beyond static collateral ratios by integrating several key risk vectors: **collateral health**, **borrower credit history (reputation)**, and **market volatility**.

This contract dynamically calculates an interest rate and a comprehensive risk score for each active loan. Crucially, it includes a `perform-dynamic-risk-assessment` public function that, when called (likely by an external oracle or keeper bot), recalculates the loan's health, accrues interest, adjusts the debt principal, and is capable of automatically **liquidating** loans that fall below a critical collateralization threshold, thus securing the protocol's solvency.

### Key Features

* **Multi-Factor Risk Scoring:** Combines collateral ratio, global market volatility, and borrower default history into a single risk score.
* **Dynamic Interest Rates:** Interest rates are adjusted based on the calculated collateralization health and the borrower's on-chain reputation.
* **Automated Liquidation:** Loans are flagged and closed if the health ratio drops below the `liquidation-threshold` (105%).
* **On-Chain Reputation System:** Tracks successful repayments and defaults, dynamically adjusting a borrower's `reputation-score` to offer better rates to reliable users.
* **Time-Based Accrual:** Interest is accrued based on the number of blocks elapsed since the last update.

---

## 🛠️ Contract Constants & Error Codes

The contract defines several fixed constants for risk tiers, interest rates, and operational boundaries, along with standardized error codes.

### Risk & Rate Constants (in Basis Points - bp)

| Constant | Value (bp) | Equivalent % | Description |
| :--- | :--- | :--- | :--- |
| `low-risk-threshold` | `u15000` | 150% | Minimum collateral for the lowest risk tier. |
| `medium-risk-threshold`| `u12500` | 125% | Minimum collateral for the medium risk tier. |
| `high-risk-threshold` | `u11000` | 110% | Minimum collateral required to open a loan. |
| `liquidation-threshold`| `u10500` | 105% | Health ratio at or below which liquidation is triggered. |
| `low-risk-rate` | `u500` | 5% APR | Base interest rate for low-risk loans. |
| `medium-risk-rate` | `u1000` | 10% APR | Base interest rate for medium-risk loans. |
| `high-risk-rate` | `u1500` | 15% APR | Base interest rate for high-risk loans. |

### Error Codes

| Code | Description |
| :--- | :--- |
| `u100` | `err-owner-only`: Restricted to the contract owner. |
| `u101` | `err-not-found`: Loan or profile does not exist. |
| `u102` | `err-insufficient-collateral`: Collateral ratio is too low for loan creation. |
| `u103` | `err-loan-already-exists`: Borrower already has an active loan. |
| `u104` | `err-unauthorized`: Action not permitted for `tx-sender`. |
| `u105` | `err-invalid-amount`: Input amount is zero or otherwise invalid. |
| `u106` | `err-loan-underwater`: Loan is in a critical state (though liquidation is handled internally). |
| `u107` | `err-invalid-risk-params`: Invalid parameters provided for risk updates. |

---

## 🗄️ Data Structure

### `loans` Map

Stores the current state of an active or inactive loan, keyed by the borrower's principal.

```clarity
{
    collateral-amount: uint,
    loan-amount: uint,       ;; The current principal + accrued interest
    interest-rate: uint,     ;; Current APR (in basis points)
    risk-score: uint,        ;; Current risk score (0-10000)
    last-update-block: uint,
    is-active: bool
}

```

### `borrower-profiles` Map

Stores the long-term credit and behavior history of a borrower, keyed by principal.

Code snippet

```
{
    total-loans-taken: uint,
    loans-repaid: uint,
    defaults: uint,
    reputation-score: uint   ;; (0-10000), higher is better
}

```

### Data Variables

| **Variable** | **Type** | **Initial Value** | **Description** |
| --- | --- | --- | --- |
| `global-volatility-index` | `uint` | `u5000` (50%) | System-wide market volatility factor (updated by owner/oracle). |
| `liquidation-penalty` | `uint` | `u1000` (10%) | Penalty applied to the collateral upon liquidation. |
| `risk-adjustment-factor` | `uint` | `u10000` (100%) | Global multiplier for dynamic risk adjustments. |

* * * * *

🧠 Core Logic: Private Functions
--------------------------------

These helper functions encapsulate the critical risk calculation logic.

### `(calculate-health-ratio (collateral uint) (loan uint))`

Calculates the collateralization ratio in basis points:

$$ \text{Health Ratio} = \frac{\text{Collateral Value}}{\text{Loan Value}} \times 10000 $$

### `(get-risk-tier (health-ratio uint))`

Assigns a text-based risk tier (`"low"`, `"medium"`, `"high"`, or `"critical"`) based on where the `health-ratio` falls relative to the defined thresholds.

### `(calculate-interest-rate (health-ratio uint) (reputation uint))`

Determines the final interest rate:

1.  Sets a **base rate** based on the collateralization risk tier.

2.  Applies a **reputation discount**: $\text{Discount} = \frac{\text{Base Rate} \times \text{Reputation Score}}{10000}$.

3.  The final rate is $\text{Base Rate} - \text{Discount}$ (min 0).

### `(calculate-risk-score (health-ratio uint) (volatility uint) (defaults uint))`

Generates a holistic Risk Score (0-10000, higher is riskier):

$$ \text{Risk Score} = \text{Collateral Risk} + \text{Volatility Risk} + \text{Default Risk} $$

-   **Collateral Risk:** Adds `u5000` if the ratio is below `high-risk-threshold` (110%).

-   **Volatility Risk:** $\frac{\text{Global Volatility Index}}{2}$.

-   **Default Risk:** $\text{Defaults Count} \times 1000$.

### `(update-reputation (borrower principal) (action (string-ascii 10)))`

Modifies the borrower's `reputation-score` and updates loan statistics:

-   **"repay"**: Increases `loans-repaid` and boosts `reputation-score` by `u100` (up to `u9500`).

-   **"default"**: Increases `defaults` and reduces `reputation-score` by `u1000` (down to `u0`).

* * * * *

🌐 Public Functions (API)
-------------------------

### `(create-loan (collateral-amount uint) (loan-amount uint))`

-   **Pre-conditions:**

    -   No existing active loan for `tx-sender`.

    -   `collateral-amount` and `loan-amount` must be greater than zero.

    -   Initial `health-ratio` must be $\ge \text{u11000}$ (110%).

-   **Action:**

    -   Calculates initial `health-ratio`, `interest-rate`, and `risk-score`.

    -   Creates a new entry in the `loans` map and updates `borrower-profiles`.

-   **Returns:** `(ok {loan-amount: uint, interest-rate: uint, risk-score: uint})`

### `(repay-loan)`

-   **Pre-conditions:** `tx-sender` must have an active loan.

-   **Action:**

    -   Marks the loan as `is-active: false` in the `loans` map.

    -   Calls `update-reputation` with "repay".

-   **Returns:** `(ok collateral-amount)` (the collateral to be returned to the borrower).

### `(add-collateral (amount uint))`

-   **Pre-conditions:** `tx-sender` must have an active loan; `amount` must be $> u0$.

-   **Action:** Increases the `collateral-amount` in the loan record.

-   **Returns:** `(ok true)`

### `(update-global-volatility (new-volatility uint))`

-   **Pre-conditions:** `tx-sender` must be the `contract-owner`. `new-volatility` must be $\le \text{u10000}$ (100%).

-   **Action:** Updates the `global-volatility-index` data variable.

-   **Returns:** `(ok true)`

### `(perform-dynamic-risk-assessment (borrower principal) (current-collateral-value uint))`

**The core function for dynamic risk management.**

-   **Pre-conditions:** A valid, active loan must exist for the `borrower`.

-   **Action:**

    1.  Calculate Accrued Interest: The total debt is updated by adding interest accrued since last-update-block.

        $$ \text{Interest Accrued} = \frac{\text{Principal} \times \text{Interest Rate} \times \text{Blocks Elapsed}}{\text{Blocks Per Year} \times 10000} $$

    2.  **Recalculate Health:** A `new-health-ratio` is calculated using `current-collateral-value` and `total-debt`.

    3.  **Adjust Risk/Rate:** `risk-score` is re-calculated (including a penalty for time elapsed), and a `new-interest-rate` is determined and globally adjusted by `risk-adjustment-factor`.

    4.  **Liquidation Check:**

        -   If $\text{new-health-ratio} < \text{liquidation-threshold}$ (105%): The loan is set to `is-active: false`, `update-reputation` is called with "default", and a **liquidation action** is returned.

        -   Otherwise: The loan record is updated with the `total-debt`, `adjusted-interest-rate`, and `adjusted-risk-score`.

-   **Returns:** `(ok {action: string, health-ratio: uint, risk-score: uint, new-interest-rate: uint, liquidation-penalty: uint})`

* * * * *

👓 Read-Only Functions
----------------------

### `(get-loan-details (borrower principal))`

Retrieves the raw data for a loan from the `loans` map.

### `(get-borrower-profile (borrower principal))`

Retrieves the raw data for a borrower from the `borrower-profiles` map.

* * * * *

🤝 Contribution
---------------

We welcome contributions to enhance the robustness and feature set of `CryptoRiskEngine`. Before submitting a pull request, please ensure your code adheres to the following guidelines:

1.  **Clarity Best Practices:** Ensure all new functions and variables are clearly documented with comments.

2.  **Security Audit:** All logic must be rigorously tested for potential attack vectors, especially around arithmetic overflows, reentrancy (where applicable in other contracts), and denial-of-service risks.

3.  **Error Handling:** Use the defined error codes and `asserts!` for all critical pre-conditions.

4.  **Testing:** Provide comprehensive unit tests covering all edge cases, including liquidation events, maximum/minimum collateralization, and reputation score boundaries.

### Reporting Issues

Please use the GitHub Issue Tracker to report any bugs or propose new features.

* * * * *

⚖️ License
----------

### MIT License

Copyright (c) 2025 CryptoRiskEngine Contributors

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
