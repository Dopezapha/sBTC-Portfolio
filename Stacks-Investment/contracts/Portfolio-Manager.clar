;; sBTC Portfolio Manager
;; A smart contract to manage sBTC investments across multiple strategies

;; Error codes
(define-constant ERR-UNAUTHORIZED u1)
(define-constant ERR-INVALID-AMOUNT u2)
(define-constant ERR-INSUFFICIENT-BALANCE u3)
(define-constant ERR-STRATEGY-EXISTS u4)
(define-constant ERR-STRATEGY-NOT-FOUND u5)
(define-constant ERR-ALLOCATION-EXCEEDED u6)
(define-constant ERR-TRANSFER-FAILED u7)
(define-constant ERR-PAUSED u8)

;; Define a trait for token contracts (SIP-010 compatible)
(define-trait sip-010-trait
  (
    ;; Transfer from the caller to a new principal
    (transfer (uint principal principal (optional (buff 34))) (response bool uint))
    
    ;; Get the token balance of the specified principal
    (get-balance (principal) (response uint uint))
    
    ;; Get the total supply of the token
    (get-total-supply () (response uint uint))
    
    ;; Get the token decimals
    (get-decimals () (response uint uint))
    
    ;; Get the token name
    (get-name () (response (string-ascii 32) uint))
    
    ;; Get the token symbol
    (get-symbol () (response (string-ascii 32) uint))
  )
)

;; Contract states
(define-data-var contract-owner principal tx-sender)
(define-data-var contract-paused bool false)
(define-data-var total-managed-amount uint u0)
(define-data-var performance-fee-percent uint u200) ;; 2.00% (scaled by 100)
(define-data-var platform-fee-percent uint u50)     ;; 0.50% (scaled by 100)
(define-data-var fee-collector principal tx-sender)
(define-data-var sbtc-contract principal 'ST000000000000000000002AMW42H.sbtc-token) ;; Replace with actual contract when deployed
(define-data-var max-strategies uint u20) ;; Strategy count limit for direct access - avoids recursion

;; Strategy structure
(define-map strategies
  { strategy-id: uint }
  {
    name: (string-ascii 64),
    description: (string-utf8 256),
    manager: principal,
    active: bool,
    risk-level: uint,
    performance-multiplier: uint,
    total-allocated: uint,
    allocation-cap: uint,
    creation-height: uint
  }
)

;; User portfolio balances
(define-map user-balances
  { user: principal }
  { total-balance: uint }
)

;; User strategy allocations
(define-map user-strategy-allocations
  { user: principal, strategy-id: uint }
  { allocated-amount: uint, entry-height: uint }
)

;; Strategy performance data
(define-map strategy-performance
  { strategy-id: uint, period: uint }
  {
    start-value: uint,
    end-value: uint,
    yield-percent: int,
    calculated-at-height: uint
  }
)

;; Strategy count for IDs
(define-data-var strategy-counter uint u0)

;; Events
(define-private (emit-deposit-event (user principal) (amount uint))
  (print { type: "deposit", user: user, amount: amount })
)

(define-private (emit-withdrawal-event (user principal) (amount uint))
  (print { type: "withdrawal", user: user, amount: amount })
)

(define-private (emit-strategy-allocation-event (user principal) (strategy-id uint) (amount uint))
  (print { type: "allocation", user: user, strategy-id: strategy-id, amount: amount })
)

(define-private (emit-strategy-created-event (strategy-id uint) (manager principal))
  (print { type: "strategy-created", strategy-id: strategy-id, manager: manager })
)

;; Authorization checks
(define-private (is-contract-owner)
  (is-eq tx-sender (var-get contract-owner))
)

(define-private (is-strategy-manager (strategy-id uint))
  (match (map-get? strategies { strategy-id: strategy-id })
    strategy (is-eq tx-sender (get manager strategy))
    false
  )
)

(define-private (assert-not-paused)
  (if (var-get contract-paused)
    (err ERR-PAUSED)
    (ok true))
)

;; Admin functions
(define-public (set-contract-owner (new-owner principal))
  (begin
    (asserts! (is-contract-owner) (err ERR-UNAUTHORIZED))
    (var-set contract-owner new-owner)
    (ok true)
  )
)

(define-public (set-fee-collector (new-collector principal))
  (begin
    (asserts! (is-contract-owner) (err ERR-UNAUTHORIZED))
    (var-set fee-collector new-collector)
    (ok true)
  )
)

(define-public (set-performance-fee (new-fee uint))
  (begin
    (asserts! (is-contract-owner) (err ERR-UNAUTHORIZED))
    (asserts! (<= new-fee u1000) (err ERR-INVALID-AMOUNT)) ;; Max 10%
    (var-set performance-fee-percent new-fee)
    (ok true)
  )
)

(define-public (set-platform-fee (new-fee uint))
  (begin
    (asserts! (is-contract-owner) (err ERR-UNAUTHORIZED))
    (asserts! (<= new-fee u500) (err ERR-INVALID-AMOUNT)) ;; Max 5%
    (var-set platform-fee-percent new-fee)
    (ok true)
  )
)

(define-public (toggle-contract-pause)
  (begin
    (asserts! (is-contract-owner) (err ERR-UNAUTHORIZED))
    (var-set contract-paused (not (var-get contract-paused)))
    (ok true)
  )
)

(define-public (set-sbtc-contract (new-contract principal))
  (begin
    (asserts! (is-contract-owner) (err ERR-UNAUTHORIZED))
    (var-set sbtc-contract new-contract)
    (ok true)
  )
)

;; Strategy management
(define-public (create-strategy 
                (name (string-ascii 64))
                (description (string-utf8 256))
                (risk-level uint)
                (performance-multiplier uint) 
                (allocation-cap uint))
  (let ((new-id (+ (var-get strategy-counter) u1)))
    (begin
      (try! (assert-not-paused))
      (asserts! (>= performance-multiplier u50) (err ERR-INVALID-AMOUNT)) ;; Minimum 0.5x
      (asserts! (<= performance-multiplier u500) (err ERR-INVALID-AMOUNT)) ;; Maximum 5x
      (asserts! (<= risk-level u10) (err ERR-INVALID-AMOUNT)) ;; Risk scale 0-10
      
      (map-set strategies 
        { strategy-id: new-id }
        {
          name: name,
          description: description,
          manager: tx-sender,
          active: true,
          risk-level: risk-level,
          performance-multiplier: performance-multiplier,
          total-allocated: u0,
          allocation-cap: allocation-cap,
          creation-height: block-height
        }
      )
      
      (var-set strategy-counter new-id)
      (emit-strategy-created-event new-id tx-sender)
      (ok new-id)
    )
  )
)

(define-public (update-strategy 
                (strategy-id uint)
                (name (optional (string-ascii 64)))
                (description (optional (string-utf8 256)))
                (active (optional bool))
                (risk-level (optional uint))
                (performance-multiplier (optional uint)))
  (begin
    (try! (assert-not-paused))
    (match (map-get? strategies { strategy-id: strategy-id })
      strategy 
        (begin
          (asserts! (is-strategy-manager strategy-id) (err ERR-UNAUTHORIZED))
          
          ;; Validate optional parameters
          (asserts! (match risk-level
                    r-level (and (>= r-level u0) (<= r-level u10))
                    true) (err ERR-INVALID-AMOUNT))
          
          (asserts! (match performance-multiplier
                    p-mult (and (>= p-mult u50) (<= p-mult u500))
                    true) (err ERR-INVALID-AMOUNT))
    
          (map-set strategies 
            { strategy-id: strategy-id }
            {
              name: (default-to (get name strategy) name),
              description: (default-to (get description strategy) description),
              manager: (get manager strategy),
              active: (default-to (get active strategy) active),
              risk-level: (default-to (get risk-level strategy) risk-level),
              performance-multiplier: (default-to (get performance-multiplier strategy) performance-multiplier),
              total-allocated: (get total-allocated strategy),
              allocation-cap: (get allocation-cap strategy),
              creation-height: (get creation-height strategy)
            }
          )
          (ok true)
        )
      (err ERR-STRATEGY-NOT-FOUND)
    )
  )
)

(define-public (update-strategy-allocation-cap (strategy-id uint) (new-cap uint))
  (begin
    (try! (assert-not-paused))
    (match (map-get? strategies { strategy-id: strategy-id })
      strategy 
        (begin
          (asserts! (is-strategy-manager strategy-id) (err ERR-UNAUTHORIZED))
          
          (map-set strategies 
            { strategy-id: strategy-id }
            (merge strategy { allocation-cap: new-cap })
          )
          (ok true)
        )
      (err ERR-STRATEGY-NOT-FOUND)
    )
  )
)

(define-public (set-strategy-performance 
                (strategy-id uint)
                (period uint)
                (start-value uint)
                (end-value uint))
  (begin
    (try! (assert-not-paused))
    (match (map-get? strategies { strategy-id: strategy-id })
      strategy 
        (begin
          (asserts! (is-strategy-manager strategy-id) (err ERR-UNAUTHORIZED))
          (asserts! (> start-value u0) (err ERR-INVALID-AMOUNT))
          
          (let ((yield-percent (if (> end-value start-value)
                                 (to-int (* (/ (* (- end-value start-value) u10000) start-value) u1))
                                 (to-int (* (/ (* (- end-value start-value) u10000) start-value) u1)))))
            (map-set strategy-performance
              { strategy-id: strategy-id, period: period }
              {
                start-value: start-value,
                end-value: end-value,
                yield-percent: yield-percent,
                calculated-at-height: block-height
              }
            )
            (ok yield-percent)
          )
        )
      (err ERR-STRATEGY-NOT-FOUND)
    )
  )
)

;; User functions
(define-public (deposit (token-contract <sip-010-trait>) (amount uint))
  (begin
    (try! (assert-not-paused))
    (asserts! (> amount u0) (err ERR-INVALID-AMOUNT))
    
    ;; Transfer sBTC to the contract
    (match (contract-call? token-contract transfer amount tx-sender (as-contract tx-sender) none)
      success
        (begin
          ;; Update user balance
          (map-set user-balances
            { user: tx-sender }
            { 
              total-balance: (+ (get-user-balance tx-sender) amount)
            }
          )
          
          ;; Update total managed amount
          (var-set total-managed-amount (+ (var-get total-managed-amount) amount))
          
          (emit-deposit-event tx-sender amount)
          (ok amount)
        )
      error (err ERR-TRANSFER-FAILED)
    )
  )
)

(define-public (withdraw (token-contract <sip-010-trait>) (amount uint))
  (begin
    (try! (assert-not-paused))
    (asserts! (> amount u0) (err ERR-INVALID-AMOUNT))
    (asserts! (>= (get-user-unallocated-balance tx-sender) amount) (err ERR-INSUFFICIENT-BALANCE))
    
    ;; Update user balance
    (map-set user-balances
      { user: tx-sender }
      { 
        total-balance: (- (get-user-balance tx-sender) amount)
      }
    )
    
    ;; Update total managed amount
    (var-set total-managed-amount (- (var-get total-managed-amount) amount))
    
    ;; Transfer sBTC back to the user
    (as-contract 
      (match (contract-call? token-contract transfer amount (as-contract tx-sender) tx-sender none)
        success (begin 
                  (emit-withdrawal-event tx-sender amount) 
                  (ok amount)
                )
        error (err ERR-TRANSFER-FAILED)
      )
    )
  )
)

(define-public (allocate-to-strategy (strategy-id uint) (amount uint))
  (begin
    (try! (assert-not-paused))
    (match (map-get? strategies { strategy-id: strategy-id })
      strategy 
        (begin
          (asserts! (get active strategy) (err ERR-STRATEGY-NOT-FOUND))
          (asserts! (> amount u0) (err ERR-INVALID-AMOUNT))
          
          (let ((unallocated-balance (get-user-unallocated-balance tx-sender))
                (current-allocated (match (map-get? user-strategy-allocations { user: tx-sender, strategy-id: strategy-id })
                                     allocation (get allocated-amount allocation)
                                     u0)))
            
            (asserts! (>= unallocated-balance amount) (err ERR-INSUFFICIENT-BALANCE))
            ;; Check strategy allocation cap
            (asserts! (<= (+ (get total-allocated strategy) amount) (get allocation-cap strategy)) (err ERR-ALLOCATION-EXCEEDED))
            
            ;; Update user strategy allocation
            (map-set user-strategy-allocations
              { user: tx-sender, strategy-id: strategy-id }
              { 
                allocated-amount: (+ current-allocated amount),
                entry-height: block-height
              }
            )
            
            ;; Update strategy total allocation
            (map-set strategies
              { strategy-id: strategy-id }
              (merge strategy { total-allocated: (+ (get total-allocated strategy) amount) })
            )
            
            (emit-strategy-allocation-event tx-sender strategy-id amount)
            (ok amount)
          )
        )
      (err ERR-STRATEGY-NOT-FOUND)
    )
  )
)

(define-public (deallocate-from-strategy (strategy-id uint) (amount uint))
  (begin
    (try! (assert-not-paused))
    (match (map-get? strategies { strategy-id: strategy-id })
      strategy 
        (begin
          (match (map-get? user-strategy-allocations { user: tx-sender, strategy-id: strategy-id })
            user-allocation
              (begin
                (asserts! (> amount u0) (err ERR-INVALID-AMOUNT))
                (asserts! (>= (get allocated-amount user-allocation) amount) (err ERR-INSUFFICIENT-BALANCE))
                
                ;; Update user allocation
                (if (is-eq amount (get allocated-amount user-allocation))
                  (map-delete user-strategy-allocations { user: tx-sender, strategy-id: strategy-id })
                  (map-set user-strategy-allocations
                    { user: tx-sender, strategy-id: strategy-id }
                    { 
                      allocated-amount: (- (get allocated-amount user-allocation) amount),
                      entry-height: (get entry-height user-allocation)
                    }
                  )
                )
                
                ;; Update strategy total allocation
                (map-set strategies
                  { strategy-id: strategy-id }
                  (merge strategy { total-allocated: (- (get total-allocated strategy) amount) })
                )
                
                (ok amount)
              )
            (err ERR-STRATEGY-NOT-FOUND)
          )
        )
      (err ERR-STRATEGY-NOT-FOUND)
    )
  )
)

;; Read-only functions for user balances
(define-read-only (get-user-balance (user principal))
  (default-to u0 (get total-balance (map-get? user-balances { user: user })))
)

(define-read-only (get-user-strategy-allocation (user principal) (strategy-id uint))
  (match (map-get? user-strategy-allocations { user: user, strategy-id: strategy-id })
    allocation (get allocated-amount allocation)
    u0)
)

(define-read-only (get-user-allocated-balance-for-strategy (user principal) (strategy-id uint))
  (get-user-strategy-allocation user strategy-id)
)

;; Calculate total allocated balance manually without using get-user-strategies
(define-read-only (get-user-allocated-balance (user principal))
  (+ 
    (get-user-strategy-allocation user u1)
    (get-user-strategy-allocation user u2)
    (get-user-strategy-allocation user u3)
    (get-user-strategy-allocation user u4)
    (get-user-strategy-allocation user u5)
    (get-user-strategy-allocation user u6)
    (get-user-strategy-allocation user u7)
    (get-user-strategy-allocation user u8)
    (get-user-strategy-allocation user u9)
    (get-user-strategy-allocation user u10)
    (get-user-strategy-allocation user u11)
    (get-user-strategy-allocation user u12)
    (get-user-strategy-allocation user u13)
    (get-user-strategy-allocation user u14)
    (get-user-strategy-allocation user u15)
    (get-user-strategy-allocation user u16)
    (get-user-strategy-allocation user u17)
    (get-user-strategy-allocation user u18)
    (get-user-strategy-allocation user u19)
    (get-user-strategy-allocation user u20)
  )
)

(define-read-only (get-user-unallocated-balance (user principal))
  (- (get-user-balance user) (get-user-allocated-balance user))
)

;; Get one strategy that the user has allocated to
(define-read-only (get-user-strategy (user principal) (strategy-id uint))
  (if (and 
       (<= strategy-id (var-get strategy-counter))
       (> (get-user-strategy-allocation user strategy-id) u0))
    (some strategy-id)
    none)
)

;; Check if user has allocated to specific strategy
(define-read-only (has-user-allocated-to-strategy (user principal) (strategy-id uint))
  (is-some (get-user-strategy user strategy-id))
)

;; Check if user has allocated to at least one strategy
(define-read-only (has-user-allocated-to-any-strategy (user principal))
  (or 
    (> (get-user-strategy-allocation user u1) u0)
    (> (get-user-strategy-allocation user u2) u0)
    (> (get-user-strategy-allocation user u3) u0)
    (> (get-user-strategy-allocation user u4) u0)
    (> (get-user-strategy-allocation user u5) u0)
    (> (get-user-strategy-allocation user u6) u0)
    (> (get-user-strategy-allocation user u7) u0)
    (> (get-user-strategy-allocation user u8) u0)
    (> (get-user-strategy-allocation user u9) u0)
    (> (get-user-strategy-allocation user u10) u0)
    (> (get-user-strategy-allocation user u11) u0)
    (> (get-user-strategy-allocation user u12) u0)
    (> (get-user-strategy-allocation user u13) u0)
    (> (get-user-strategy-allocation user u14) u0)
    (> (get-user-strategy-allocation user u15) u0)
    (> (get-user-strategy-allocation user u16) u0)
    (> (get-user-strategy-allocation user u17) u0)
    (> (get-user-strategy-allocation user u18) u0)
    (> (get-user-strategy-allocation user u19) u0)
    (> (get-user-strategy-allocation user u20) u0)
  )
)

(define-read-only (get-strategy (strategy-id uint))
  (map-get? strategies { strategy-id: strategy-id })
)

(define-read-only (get-strategy-performance-data (strategy-id uint) (period uint))
  (map-get? strategy-performance { strategy-id: strategy-id, period: period })
)

(define-read-only (get-total-managed-amount)
  (var-get total-managed-amount)
)

(define-read-only (get-contract-owner)
  (var-get contract-owner)
)

(define-read-only (is-contract-paused)
  (var-get contract-paused)
)

(define-read-only (get-performance-fee)
  (var-get performance-fee-percent)
)

(define-read-only (get-platform-fee)
  (var-get platform-fee-percent)
)

(define-read-only (get-sbtc-contract)
  (var-get sbtc-contract)
)

;; Helper function to check if a trait implements SIP-010
(define-read-only (is-sip-010-trait (token-trait <sip-010-trait>))
  true
)

;; Helper function
(define-private (unwrap-uint (x uint))
  x)