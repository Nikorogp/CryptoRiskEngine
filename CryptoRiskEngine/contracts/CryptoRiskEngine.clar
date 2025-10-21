;; Dynamic Risk Modeling for Crypto Loans
;; This contract implements a dynamic risk assessment system for cryptocurrency-backed loans
;; It evaluates collateral health, borrower history, and market volatility to determine loan terms
;; and trigger liquidations when necessary.

;; constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-insufficient-collateral (err u102))
(define-constant err-loan-already-exists (err u103))
(define-constant err-unauthorized (err u104))
(define-constant err-invalid-amount (err u105))
(define-constant err-loan-underwater (err u106))
(define-constant err-invalid-risk-params (err u107))

;; Risk tier thresholds (in basis points, 10000 = 100%)
(define-constant low-risk-threshold u15000)    ;; 150% collateralization
(define-constant medium-risk-threshold u12500) ;; 125% collateralization
(define-constant high-risk-threshold u11000)   ;; 110% collateralization
(define-constant liquidation-threshold u10500) ;; 105% collateralization

;; Interest rates in basis points per year
(define-constant low-risk-rate u500)      ;; 5% APR
(define-constant medium-risk-rate u1000)  ;; 10% APR
(define-constant high-risk-rate u1500)    ;; 15% APR

;; data maps and vars
;; Stores loan information for each borrower
(define-map loans
    principal
    {
        collateral-amount: uint,
        loan-amount: uint,
        interest-rate: uint,
        risk-score: uint,
        last-update-block: uint,
        is-active: bool
    }
)

;; Tracks borrower credit history and behavior
(define-map borrower-profiles
    principal
    {
        total-loans-taken: uint,
        loans-repaid: uint,
        defaults: uint,
        reputation-score: uint
    }
)

;; Dynamic risk parameters updated by oracle or governance
(define-data-var global-volatility-index uint u5000) ;; 50% baseline volatility
(define-data-var liquidation-penalty uint u1000)     ;; 10% penalty
(define-data-var risk-adjustment-factor uint u10000) ;; 100% baseline

;; private functions
;; Calculate the health ratio of a loan (collateral value / loan value)
(define-private (calculate-health-ratio (collateral uint) (loan uint))
    (if (is-eq loan u0)
        u0
        (/ (* collateral u10000) loan)
    )
)

;; Determine risk tier based on collateralization ratio
(define-private (get-risk-tier (health-ratio uint))
    (if (>= health-ratio low-risk-threshold)
        "low"
        (if (>= health-ratio medium-risk-threshold)
            "medium"
            (if (>= health-ratio high-risk-threshold)
                "high"
                "critical"
            )
        )
    )
)

;; Calculate interest rate based on risk tier and borrower reputation
(define-private (calculate-interest-rate (health-ratio uint) (reputation uint))
    (let
        (
            (base-rate (if (>= health-ratio low-risk-threshold)
                          low-risk-rate
                          (if (>= health-ratio medium-risk-threshold)
                              medium-risk-rate
                              high-risk-rate
                          )
                       ))
            (reputation-discount (/ (* base-rate reputation) u10000))
        )
        (if (> base-rate reputation-discount)
            (- base-rate reputation-discount)
            u0
        )
    )
)

;; Calculate risk score (0-10000, higher is riskier)
(define-private (calculate-risk-score 
    (health-ratio uint) 
    (volatility uint) 
    (defaults uint))
    (let
        (
            (collateral-risk (if (< health-ratio high-risk-threshold) u5000 u0))
            (volatility-risk (/ volatility u2))
            (default-risk (* defaults u1000))
        )
        (if (> (+ (+ collateral-risk volatility-risk) default-risk) u10000)
            u10000
            (+ (+ collateral-risk volatility-risk) default-risk)
        )
    )
)

;; Update borrower reputation based on action
(define-private (update-reputation (borrower principal) (action (string-ascii 10)))
    (let
        (
            (profile (default-to 
                {total-loans-taken: u0, loans-repaid: u0, defaults: u0, reputation-score: u7500}
                (map-get? borrower-profiles borrower)))
        )
        (if (is-eq action "repay")
            (map-set borrower-profiles borrower
                (merge profile {
                    loans-repaid: (+ (get loans-repaid profile) u1),
                    reputation-score: (if (< (get reputation-score profile) u9500)
                                        (+ (get reputation-score profile) u100)
                                        u10000)
                })
            )
            (if (is-eq action "default")
                (map-set borrower-profiles borrower
                    (merge profile {
                        defaults: (+ (get defaults profile) u1),
                        reputation-score: (if (> (get reputation-score profile) u1000)
                                            (- (get reputation-score profile) u1000)
                                            u0)
                    })
                )
                true
            )
        )
    )
)

;; public functions
;; Create a new loan with collateral
(define-public (create-loan (collateral-amount uint) (loan-amount uint))
    (let
        (
            (existing-loan (map-get? loans tx-sender))
            (health-ratio (calculate-health-ratio collateral-amount loan-amount))
            (profile (default-to 
                {total-loans-taken: u0, loans-repaid: u0, defaults: u0, reputation-score: u7500}
                (map-get? borrower-profiles tx-sender)))
            (interest-rate (calculate-interest-rate health-ratio (get reputation-score profile)))
            (risk-score (calculate-risk-score health-ratio (var-get global-volatility-index) (get defaults profile)))
        )
        (asserts! (is-none existing-loan) err-loan-already-exists)
        (asserts! (> collateral-amount u0) err-invalid-amount)
        (asserts! (> loan-amount u0) err-invalid-amount)
        (asserts! (>= health-ratio high-risk-threshold) err-insufficient-collateral)
        
        (map-set loans tx-sender {
            collateral-amount: collateral-amount,
            loan-amount: loan-amount,
            interest-rate: interest-rate,
            risk-score: risk-score,
            last-update-block: block-height,
            is-active: true
        })
        
        (map-set borrower-profiles tx-sender
            (merge profile {total-loans-taken: (+ (get total-loans-taken profile) u1)})
        )
        
        (ok {loan-amount: loan-amount, interest-rate: interest-rate, risk-score: risk-score})
    )
)

;; Repay loan and close position
(define-public (repay-loan)
    (let
        (
            (loan (unwrap! (map-get? loans tx-sender) err-not-found))
        )
        (asserts! (get is-active loan) err-not-found)
        
        (map-set loans tx-sender (merge loan {is-active: false}))
        (update-reputation tx-sender "repay")
        
        (ok (get collateral-amount loan))
    )
)

;; Add collateral to existing loan
(define-public (add-collateral (amount uint))
    (let
        (
            (loan (unwrap! (map-get? loans tx-sender) err-not-found))
        )
        (asserts! (get is-active loan) err-not-found)
        (asserts! (> amount u0) err-invalid-amount)
        
        (map-set loans tx-sender 
            (merge loan {collateral-amount: (+ (get collateral-amount loan) amount)})
        )
        
        (ok true)
    )
)

;; Update global risk parameters (owner only)
(define-public (update-global-volatility (new-volatility uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (<= new-volatility u10000) err-invalid-risk-params)
        (var-set global-volatility-index new-volatility)
        (ok true)
    )
)

;; Read-only function to get loan details
(define-read-only (get-loan-details (borrower principal))
    (map-get? loans borrower)
)

;; Read-only function to get borrower profile
(define-read-only (get-borrower-profile (borrower principal))
    (map-get? borrower-profiles borrower)
)

;; NEW FEATURE: Comprehensive dynamic risk recalculation and loan management
;; This function performs a complete risk reassessment of an active loan
;; considering current market conditions, collateral value changes, and borrower behavior
;; It automatically adjusts interest rates, triggers warnings, or initiates liquidations
(define-public (perform-dynamic-risk-assessment 
    (borrower principal) 
    (current-collateral-value uint))
    (let
        (
            (loan (unwrap! (map-get? loans borrower) err-not-found))
            (profile (unwrap! (map-get? borrower-profiles borrower) err-not-found))
            (blocks-elapsed (- block-height (get last-update-block loan)))
            
            ;; Calculate accrued interest based on blocks elapsed
            ;; Assuming ~144 blocks per day, ~52560 blocks per year
            (interest-accrued (/ (* (* (get loan-amount loan) (get interest-rate loan)) blocks-elapsed) 
                                 (* u52560 u10000)))
            (total-debt (+ (get loan-amount loan) interest-accrued))
            
            ;; Calculate new health metrics
            (new-health-ratio (calculate-health-ratio current-collateral-value total-debt))
            (volatility (var-get global-volatility-index))
            (adjustment-factor (var-get risk-adjustment-factor))
            
            ;; Adjust risk score based on market volatility and time
            (time-risk-increase (/ blocks-elapsed u1000))
            (base-risk-score (calculate-risk-score new-health-ratio volatility (get defaults profile)))
            (adjusted-risk-score (+ base-risk-score time-risk-increase))
            
            ;; Calculate new interest rate based on updated risk
            (new-interest-rate (calculate-interest-rate new-health-ratio (get reputation-score profile)))
            (adjusted-interest-rate (/ (* new-interest-rate adjustment-factor) u10000))
        )
        ;; Ensure loan is active
        (asserts! (get is-active loan) err-not-found)
        
        ;; Check if loan should be liquidated
        (if (< new-health-ratio liquidation-threshold)
            (begin
                (map-set loans borrower (merge loan {is-active: false}))
                (update-reputation borrower "default")
                (ok {
                    action: "liquidated",
                    health-ratio: new-health-ratio,
                    risk-score: adjusted-risk-score,
                    new-interest-rate: u0,
                    liquidation-penalty: (var-get liquidation-penalty)
                })
            )
            ;; Update loan with new parameters
            (begin
                (map-set loans borrower {
                    collateral-amount: (get collateral-amount loan),
                    loan-amount: total-debt,
                    interest-rate: adjusted-interest-rate,
                    risk-score: (if (> adjusted-risk-score u10000) u10000 adjusted-risk-score),
                    last-update-block: block-height,
                    is-active: true
                })
                (ok {
                    action: "updated",
                    health-ratio: new-health-ratio,
                    risk-score: (if (> adjusted-risk-score u10000) u10000 adjusted-risk-score),
                    new-interest-rate: adjusted-interest-rate,
                    liquidation-penalty: u0
                })
            )
        )
    )
)



