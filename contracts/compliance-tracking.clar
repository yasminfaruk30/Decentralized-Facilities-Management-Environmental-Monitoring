;; Compliance Tracking Contract
;; Tracks environmental compliance and violations

;; Constants
(define-constant ERR_UNAUTHORIZED (err u300))
(define-constant ERR_INVALID_DATA (err u301))
(define-constant ERR_NOT_FOUND (err u302))
(define-constant ERR_ALREADY_EXISTS (err u303))

;; Data Variables
(define-data-var next-violation-id uint u1)
(define-data-var next-standard-id uint u1)

;; Data Maps
(define-map compliance-standards
  { standard-id: uint }
  {
    name: (string-ascii 50),
    parameter-type: (string-ascii 30),
    min-value: uint,
    max-value: uint,
    severity: (string-ascii 10),
    active: bool,
    created-block: uint
  }
)

(define-map compliance-violations
  { violation-id: uint }
  {
    facility-id: (string-ascii 20),
    standard-id: uint,
    reading-id: uint,
    violation-type: (string-ascii 20),
    severity: (string-ascii 10),
    detected-block: uint,
    resolved: bool,
    resolution-block: (optional uint)
  }
)

(define-map facility-compliance-status
  { facility-id: (string-ascii 20) }
  {
    compliant: bool,
    last-check: uint,
    violation-count: uint,
    last-violation: (optional uint)
  }
)

;; Internal coordinator verification
(define-map verified-coordinators
  { coordinator: principal }
  { verified: bool, last-activity: uint }
)

;; Internal reading storage for validation
(define-map environmental-readings
  { reading-id: uint }
  {
    parameter-type: (string-ascii 30),
    value: uint,
    facility-id: (string-ascii 20),
    recorded-by: principal,
    block-height: uint
  }
)

;; Public Functions

;; Register as coordinator
(define-public (register-as-coordinator)
  (begin
    (map-set verified-coordinators
      { coordinator: tx-sender }
      { verified: true, last-activity: block-height }
    )
    (ok true)
  )
)

;; Add reading for validation (simplified)
(define-public (add-reading
  (reading-id uint)
  (parameter-type (string-ascii 30))
  (value uint)
  (facility-id (string-ascii 20))
)
  (let
    (
      (coordinator-data (map-get? verified-coordinators { coordinator: tx-sender }))
    )
    (asserts! (is-some coordinator-data) ERR_UNAUTHORIZED)

    (map-set environmental-readings
      { reading-id: reading-id }
      {
        parameter-type: parameter-type,
        value: value,
        facility-id: facility-id,
        recorded-by: tx-sender,
        block-height: block-height
      }
    )
    (ok true)
  )
)

;; Create compliance standard
(define-public (create-compliance-standard
  (name (string-ascii 50))
  (parameter-type (string-ascii 30))
  (min-value uint)
  (max-value uint)
  (severity (string-ascii 10))
)
  (let
    (
      (standard-id (var-get next-standard-id))
      (coordinator-data (map-get? verified-coordinators { coordinator: tx-sender }))
    )
    (asserts! (is-some coordinator-data) ERR_UNAUTHORIZED)
    (asserts! (> (len name) u0) ERR_INVALID_DATA)
    (asserts! (< min-value max-value) ERR_INVALID_DATA)

    (map-set compliance-standards
      { standard-id: standard-id }
      {
        name: name,
        parameter-type: parameter-type,
        min-value: min-value,
        max-value: max-value,
        severity: severity,
        active: true,
        created-block: block-height
      }
    )

    (var-set next-standard-id (+ standard-id u1))
    (ok standard-id)
  )
)

;; Record compliance violation
(define-public (record-violation
  (facility-id (string-ascii 20))
  (standard-id uint)
  (reading-id uint)
  (violation-type (string-ascii 20))
)
  (let
    (
      (violation-id (var-get next-violation-id))
      (coordinator-data (map-get? verified-coordinators { coordinator: tx-sender }))
      (standard (unwrap! (map-get? compliance-standards { standard-id: standard-id }) ERR_NOT_FOUND))
      (reading (unwrap! (map-get? environmental-readings { reading-id: reading-id }) ERR_NOT_FOUND))
    )
    (asserts! (is-some coordinator-data) ERR_UNAUTHORIZED)
    (asserts! (get active standard) ERR_INVALID_DATA)

    (map-set compliance-violations
      { violation-id: violation-id }
      {
        facility-id: facility-id,
        standard-id: standard-id,
        reading-id: reading-id,
        violation-type: violation-type,
        severity: (get severity standard),
        detected-block: block-height,
        resolved: false,
        resolution-block: none
      }
    )

    ;; Update facility compliance status
    (let
      (
        (current-status (default-to
          { compliant: true, last-check: u0, violation-count: u0, last-violation: none }
          (map-get? facility-compliance-status { facility-id: facility-id })
        ))
      )
      (map-set facility-compliance-status
        { facility-id: facility-id }
        {
          compliant: false,
          last-check: block-height,
          violation-count: (+ (get violation-count current-status) u1),
          last-violation: (some violation-id)
        }
      )
    )

    (var-set next-violation-id (+ violation-id u1))
    (ok violation-id)
  )
)

;; Resolve violation
(define-public (resolve-violation (violation-id uint))
  (let
    (
      (violation (unwrap! (map-get? compliance-violations { violation-id: violation-id }) ERR_NOT_FOUND))
      (coordinator-data (map-get? verified-coordinators { coordinator: tx-sender }))
    )
    (asserts! (is-some coordinator-data) ERR_UNAUTHORIZED)
    (asserts! (not (get resolved violation)) ERR_INVALID_DATA)

    (map-set compliance-violations
      { violation-id: violation-id }
      (merge violation { resolved: true, resolution-block: (some block-height) })
    )
    (ok true)
  )
)

;; Check facility compliance
(define-public (check-facility-compliance (facility-id (string-ascii 20)))
  (let
    (
      (coordinator-data (map-get? verified-coordinators { coordinator: tx-sender }))
    )
    (asserts! (is-some coordinator-data) ERR_UNAUTHORIZED)

    ;; Update compliance status based on current conditions
    (let
      (
        (current-status (default-to
          { compliant: true, last-check: u0, violation-count: u0, last-violation: none }
          (map-get? facility-compliance-status { facility-id: facility-id })
        ))
      )
      (map-set facility-compliance-status
        { facility-id: facility-id }
        (merge current-status { last-check: block-height })
      )
      (ok (get compliant current-status))
    )
  )
)

;; Read-only Functions

;; Get compliance standard
(define-read-only (get-compliance-standard (standard-id uint))
  (map-get? compliance-standards { standard-id: standard-id })
)

;; Get violation details
(define-read-only (get-violation (violation-id uint))
  (map-get? compliance-violations { violation-id: violation-id })
)

;; Get facility compliance status
(define-read-only (get-facility-compliance-status (facility-id (string-ascii 20)))
  (map-get? facility-compliance-status { facility-id: facility-id })
)

;; Check if facility is compliant
(define-read-only (is-facility-compliant (facility-id (string-ascii 20)))
  (match (map-get? facility-compliance-status { facility-id: facility-id })
    status (get compliant status)
    true
  )
)

;; Get total standards count
(define-read-only (get-total-standards)
  (- (var-get next-standard-id) u1)
)

;; Get total violations count
(define-read-only (get-total-violations)
  (- (var-get next-violation-id) u1)
)

;; Check if coordinator is verified
(define-read-only (is-coordinator-verified (coordinator principal))
  (match (map-get? verified-coordinators { coordinator: coordinator })
    data (get verified data)
    false
  )
)
