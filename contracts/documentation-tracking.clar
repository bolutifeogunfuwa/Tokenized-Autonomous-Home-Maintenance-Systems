;; Documentation Tracking Contract
;; Maintains home maintenance history and warranties

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-OWNER-ONLY (err u500))
(define-constant ERR-NOT-FOUND (err u501))
(define-constant ERR-INVALID-INPUT (err u502))
(define-constant ERR-ALREADY-EXISTS (err u503))
(define-constant ERR-EXPIRED-WARRANTY (err u504))
(define-constant ERR-INVALID-DOCUMENT (err u505))

;; Document Types
(define-constant DOC-TYPE-RECEIPT u1)
(define-constant DOC-TYPE-WARRANTY u2)
(define-constant DOC-TYPE-MANUAL u3)
(define-constant DOC-TYPE-INSPECTION u4)
(define-constant DOC-TYPE-CERTIFICATE u5)

;; Data Variables
(define-data-var next-record-id uint u1)
(define-data-var next-warranty-id uint u1)
(define-data-var next-document-id uint u1)
(define-data-var total-records uint u0)
(define-data-var total-warranties uint u0)

;; Data Maps
(define-map maintenance-records
  { record-id: uint }
  {
    home-id: uint,
    service-type: (string-ascii 100),
    description: (string-ascii 500),
    service-date: uint,
    service-provider: (string-ascii 200),
    cost: uint,
    parts-replaced: (string-ascii 300),
    labor-hours: uint,
    quality-rating: uint,
    follow-up-required: bool,
    follow-up-date: uint,
    created-by: principal,
    created-at: uint,
    tags: (string-ascii 200)
  }
)

(define-map warranty-information
  { warranty-id: uint }
  {
    home-id: uint,
    item-name: (string-ascii 100),
    manufacturer: (string-ascii 100),
    model-number: (string-ascii 100),
    serial-number: (string-ascii 100),
    purchase-date: uint,
    warranty-start: uint,
    warranty-end: uint,
    warranty-type: (string-ascii 100),
    coverage-details: (string-ascii 500),
    purchase-price: uint,
    vendor: (string-ascii 200),
    is-active: bool,
    claim-count: uint
  }
)

(define-map service-documents
  { document-id: uint }
  {
    record-id: uint,
    document-type: uint,
    document-name: (string-ascii 200),
    document-hash: (string-ascii 64),
    file-size: uint,
    upload-date: uint,
    uploaded-by: principal,
    description: (string-ascii 300),
    is-verified: bool,
    access-level: uint
  }
)

(define-map warranty-claims
  { warranty-id: uint, claim-id: uint }
  {
    claim-date: uint,
    claim-amount: uint,
    claim-status: (string-ascii 50),
    claim-description: (string-ascii 500),
    resolution-date: uint,
    resolution-notes: (string-ascii 500),
    claimed-by: principal
  }
)

(define-map home-maintenance-summary
  { home-id: uint }
  {
    total-records: uint,
    total-spent: uint,
    last-service-date: uint,
    active-warranties: uint,
    upcoming-expirations: uint,
    average-service-cost: uint,
    most-common-service: (string-ascii 100)
  }
)

(define-map maintenance-schedules
  { home-id: uint, item-type: (string-ascii 100) }
  {
    last-serviced: uint,
    next-service-due: uint,
    service-frequency: uint,
    service-provider: (string-ascii 200),
    estimated-cost: uint,
    priority: uint
  }
)

;; Private Functions
(define-private (is-contract-owner)
  (is-eq tx-sender CONTRACT-OWNER)
)

(define-private (is-valid-document-type (doc-type uint))
  (and (>= doc-type DOC-TYPE-RECEIPT) (<= doc-type DOC-TYPE-CERTIFICATE))
)

(define-private (is-warranty-active (warranty-end uint))
  (let
    (
      (current-time (unwrap-panic (get-block-info? time (- block-height u1))))
    )
    (> warranty-end current-time)
  )
)

(define-private (calculate-warranty-days-remaining (warranty-end uint))
  (let
    (
      (current-time (unwrap-panic (get-block-info? time (- block-height u1))))
    )
    (if (> warranty-end current-time)
      (/ (- warranty-end current-time) u86400)
      u0
    )
  )
)

;; Public Functions

;; Create a maintenance record
(define-public (create-maintenance-record
  (home-id uint)
  (service-type (string-ascii 100))
  (description (string-ascii 500))
  (service-date uint)
  (service-provider (string-ascii 200))
  (cost uint)
  (parts-replaced (string-ascii 300))
  (labor-hours uint)
  (quality-rating uint)
  (tags (string-ascii 200)))
  (let
    (
      (record-id (var-get next-record-id))
      (current-time (unwrap-panic (get-block-info? time (- block-height u1))))
    )
    (begin
      (map-set maintenance-records
        { record-id: record-id }
        {
          home-id: home-id,
          service-type: service-type,
          description: description,
          service-date: service-date,
          service-provider: service-provider,
          cost: cost,
          parts-replaced: parts-replaced,
          labor-hours: labor-hours,
          quality-rating: quality-rating,
          follow-up-required: false,
          follow-up-date: u0,
          created-by: tx-sender,
          created-at: current-time,
          tags: tags
        }
      )
      (var-set next-record-id (+ record-id u1))
      (var-set total-records (+ (var-get total-records) u1))
      ;; Update home maintenance summary
      (let
        (
          (current-summary (default-to
            { total-records: u0, total-spent: u0, last-service-date: u0, active-warranties: u0,
              upcoming-expirations: u0, average-service-cost: u0, most-common-service: "" }
            (map-get? home-maintenance-summary { home-id: home-id })))
          (new-total-records (+ (get total-records current-summary) u1))
          (new-total-spent (+ (get total-spent current-summary) cost))
          (new-average-cost (/ new-total-spent new-total-records))
        )
        (map-set home-maintenance-summary
          { home-id: home-id }
          (merge current-summary {
            total-records: new-total-records,
            total-spent: new-total-spent,
            last-service-date: service-date,
            average-service-cost: new-average-cost,
            most-common-service: service-type
          })
        )
      )
      (ok record-id)
    )
  )
)

;; Add warranty information
(define-public (add-warranty
  (home-id uint)
  (item-name (string-ascii 100))
  (manufacturer (string-ascii 100))
  (model-number (string-ascii 100))
  (serial-number (string-ascii 100))
  (purchase-date uint)
  (warranty-duration-days uint)
  (warranty-type (string-ascii 100))
  (coverage-details (string-ascii 500))
  (purchase-price uint)
  (vendor (string-ascii 200)))
  (let
    (
      (warranty-id (var-get next-warranty-id))
      (warranty-start purchase-date)
      (warranty-end (+ purchase-date (* warranty-duration-days u86400)))
    )
    (begin
      (map-set warranty-information
        { warranty-id: warranty-id }
        {
          home-id: home-id,
          item-name: item-name,
          manufacturer: manufacturer,
          model-number: model-number,
          serial-number: serial-number,
          purchase-date: purchase-date,
          warranty-start: warranty-start,
          warranty-end: warranty-end,
          warranty-type: warranty-type,
          coverage-details: coverage-details,
          purchase-price: purchase-price,
          vendor: vendor,
          is-active: true,
          claim-count: u0
        }
      )
      (var-set next-warranty-id (+ warranty-id u1))
      (var-set total-warranties (+ (var-get total-warranties) u1))
      (ok warranty-id)
    )
  )
)

;; Upload service document
(define-public (upload-document
  (record-id uint)
  (document-type uint)
  (document-name (string-ascii 200))
  (document-hash (string-ascii 64))
  (file-size uint)
  (description (string-ascii 300)))
  (let
    (
      (document-id (var-get next-document-id))
      (current-time (unwrap-panic (get-block-info? time (- block-height u1))))
      (record (unwrap! (map-get? maintenance-records { record-id: record-id }) ERR-NOT-FOUND))
    )
    (if (is-valid-document-type document-type)
      (begin
        (map-set service-documents
          { document-id: document-id }
          {
            record-id: record-id,
            document-type: document-type,
            document-name: document-name,
            document-hash: document-hash,
            file-size: file-size,
            upload-date: current-time,
            uploaded-by: tx-sender,
            description: description,
            is-verified: false,
            access-level: u1
          }
        )
        (var-set next-document-id (+ document-id u1))
        (ok document-id)
      )
      ERR-INVALID-DOCUMENT
    )
  )
)

;; File warranty claim
(define-public (file-warranty-claim
  (warranty-id uint)
  (claim-amount uint)
  (claim-description (string-ascii 500)))
  (let
    (
      (warranty (unwrap! (map-get? warranty-information { warranty-id: warranty-id }) ERR-NOT-FOUND))
      (current-time (unwrap-panic (get-block-info? time (- block-height u1))))
      (claim-count (get claim-count warranty))
    )
    (if (and (get is-active warranty) (is-warranty-active (get warranty-end warranty)))
      (begin
        (map-set warranty-claims
          { warranty-id: warranty-id, claim-id: (+ claim-count u1) }
          {
            claim-date: current-time,
            claim-amount: claim-amount,
            claim-status: "filed",
            claim-description: claim-description,
            resolution-date: u0,
            resolution-notes: "",
            claimed-by: tx-sender
          }
        )
        (map-set warranty-information
          { warranty-id: warranty-id }
          (merge warranty { claim-count: (+ claim-count u1) })
        )
        (ok true)
      )
      ERR-EXPIRED-WARRANTY
    )
  )
)

;; Update warranty claim status
(define-public (update-claim-status
  (warranty-id uint)
  (claim-id uint)
  (new-status (string-ascii 50))
  (resolution-notes (string-ascii 500)))
  (let
    (
      (claim (unwrap! (map-get? warranty-claims { warranty-id: warranty-id, claim-id: claim-id }) ERR-NOT-FOUND))
      (current-time (unwrap-panic (get-block-info? time (- block-height u1))))
    )
    (begin
      (map-set warranty-claims
        { warranty-id: warranty-id, claim-id: claim-id }
        (merge claim {
          claim-status: new-status,
          resolution-date: current-time,
          resolution-notes: resolution-notes
        })
      )
      (ok true)
    )
  )
)

;; Update maintenance schedule
(define-public (update-maintenance-schedule
  (home-id uint)
  (item-type (string-ascii 100))
  (service-frequency uint)
  (service-provider (string-ascii 200))
  (estimated-cost uint)
  (priority uint))
  (let
    (
      (current-time (unwrap-panic (get-block-info? time (- block-height u1))))
      (next-service (+ current-time (* service-frequency u86400)))
    )
    (begin
      (map-set maintenance-schedules
        { home-id: home-id, item-type: item-type }
        {
          last-serviced: current-time,
          next-service-due: next-service,
          service-frequency: service-frequency,
          service-provider: service-provider,
          estimated-cost: estimated-cost,
          priority: priority
        }
      )
      (ok true)
    )
  )
)

;; Verify document
(define-public (verify-document (document-id uint))
  (let
    (
      (document (unwrap! (map-get? service-documents { document-id: document-id }) ERR-NOT-FOUND))
    )
    (if (is-contract-owner)
      (begin
        (map-set service-documents
          { document-id: document-id }
          (merge document { is-verified: true })
        )
        (ok true)
      )
      ERR-OWNER-ONLY
    )
  )
)

;; Read-only Functions

;; Get maintenance record
(define-read-only (get-maintenance-record (record-id uint))
  (map-get? maintenance-records { record-id: record-id })
)

;; Get warranty information
(define-read-only (get-warranty (warranty-id uint))
  (map-get? warranty-information { warranty-id: warranty-id })
)

;; Get service document
(define-read-only (get-document (document-id uint))
  (map-get? service-documents { document-id: document-id })
)

;; Get warranty claim
(define-read-only (get-warranty-claim (warranty-id uint) (claim-id uint))
  (map-get? warranty-claims { warranty-id: warranty-id, claim-id: claim-id })
)

;; Get home maintenance summary
(define-read-only (get-home-summary (home-id uint))
  (map-get? home-maintenance-summary { home-id: home-id })
)

;; Get maintenance schedule
(define-read-only (get-maintenance-schedule (home-id uint) (item-type (string-ascii 100)))
  (map-get? maintenance-schedules { home-id: home-id, item-type: item-type })
)

;; Check warranty status
(define-read-only (check-warranty-status (warranty-id uint))
  (match (map-get? warranty-information { warranty-id: warranty-id })
    some-warranty (let
      (
        (days-remaining (calculate-warranty-days-remaining (get warranty-end some-warranty)))
      )
      {
        is-active: (get is-active some-warranty),
        days-remaining: days-remaining,
        expires-soon: (and (> days-remaining u0) (<= days-remaining u30))
      }
    )
    { is-active: false, days-remaining: u0, expires-soon: false }
  )
)

;; Get total records
(define-read-only (get-total-records)
  (var-get total-records)
)

;; Get total warranties
(define-read-only (get-total-warranties)
  (var-get total-warranties)
)

;; Get next record ID
(define-read-only (get-next-record-id)
  (var-get next-record-id)
)

;; Get next warranty ID
(define-read-only (get-next-warranty-id)
  (var-get next-warranty-id)
)

;; Get next document ID
(define-read-only (get-next-document-id)
  (var-get next-document-id)
)
