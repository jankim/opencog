;; This is the GHOST action selector for finding and deciding
;; which action should be executed at a particular point in time.

(define (rank-and-eval RULES)
"
  Partition RULES into different categories based on their type,
  and evaluate each of them. The satisfied one(s) will be returned.
"
  (define curr-topic (ghost-get-curr-topic))
  (define topic-rejoinders '())
  (define topic-responders '())
  (define topic-random-gambits '())
  (define topic-gambits '())
  (define responders '())
  (define random-gambits '())
  (define gambits '())
  (define rules-evaluated '())

  ; To evaluate a list of rules using "psi-satisfiable?"
  (define (eval-rules R)
    (set! rules-evaluated
      (append-map
        (lambda (r)
          (if (equal? (stv 1 1) (psi-satisfiable? r)) (list r) '()))
        R))
    rules-evaluated)

  ; To pick one of the selected rules either randomly or based on their weights
  (define (pick-rule F)
    ; Either randomly pick one of the rules, or pick based on their TV strength
    (cond ((equal? 'RANDOM F)
           (list-ref rules-evaluated
             (random (length rules-evaluated) (random-state-from-platform))))
          ((equal? 'RANK F)
           (let ((highest-strength 0)
                 (selected-rule '()))
             (for-each (lambda (r)
               (let ((strength (cog-stv-strength r)))
                    (if (> strength highest-strength)
                        (begin (set! highest-strength strength)
                               (set! selected-rule r)))))
               rules-evaluated)
             selected-rule))))

  ; Go through the rules and put them into different categories
  (for-each (lambda (r)
    (define rule-topic (get-rule-topic r))
    (if (any (lambda (t) (equal? curr-topic t)) rule-topic)
        (cond ((equal? strval-rejoinder (cog-value r ghost-rule-type))
               (set! topic-rejoinders (append topic-rejoinders (list r))))
              ((equal? strval-responder (cog-value r ghost-rule-type))
               (set! topic-responders (append topic-responders (list r))))
              ((equal? strval-random-gambit (cog-value r ghost-rule-type))
               (set! topic-random-gambits (append topic-random-gambits (list r))))
              ((equal? strval-gambit (cog-value r ghost-rule-type))
               (set! topic-gambits (append topic-gambits (list r)))))
        (cond ; Skip the rule if it's in a topic that should be explicitly triggered
              ; A rule may (rarely) be in multiple topics, so check them all
              ((every (lambda (t) (topic-has-feature? t "noaccess")) rule-topic))
              ((equal? strval-responder (cog-value r ghost-rule-type))
               (set! responders (append responders (list r))))
              ((equal? strval-random-gambit (cog-value r ghost-rule-type))
               (set! random-gambits (append random-gambits (list r))))
              ((equal? strval-gambit (cog-value r ghost-rule-type))
               (set! gambits (append gambits (list r)))))))
    RULES)

  (cog-logger-debug ghost-logger "topic-rejoinders = ~a\n" (length topic-rejoinders))
  (cog-logger-debug ghost-logger "topic-responders = ~a\n" (length topic-responders))
  (cog-logger-debug ghost-logger "topic-random-gambits = ~a\n" (length topic-random-gambits))
  (cog-logger-debug ghost-logger "topic-gambits = ~a\n" (length topic-gambits))
  (cog-logger-debug ghost-logger "responders = ~a\n" (length responders))
  (cog-logger-debug ghost-logger "random-gambits = ~a\n" (length random-gambits))
  (cog-logger-debug ghost-logger "gambits = ~a\n" (length gambits))

  ; And finally, evaluate the rules in this order:
  ; 1) topic-rejoinders
  ; 2) topic-responders
  ; 3) topic-random-gambits
  ; 4) topic-gambits
  ; 5) responders
  ; 6) random-gambits
  ; 7) gambits
  (cond ((not (null? (eval-rules topic-rejoinders))) (pick-rule 'RANK))
        ((not (null? (eval-rules topic-responders))) (pick-rule 'RANK))
        ((not (null? (eval-rules topic-random-gambits))) (pick-rule 'RANDOM))
        ((not (null? (eval-rules topic-gambits))) (pick-rule 'RANK))
        ((not (null? (eval-rules responders))) (pick-rule 'RANK))
        ((not (null? (eval-rules random-gambits))) (pick-rule 'RANDOM))
        ((not (null? (eval-rules gambits))) (pick-rule 'RANK))
        ; If we are here, there is no match
        (else (list))))

; ----------
(define-public (ghost-find-rules SENT)
"
  The action selector. It first searches for the rules using DualLink,
  and then does the filtering by evaluating the context of the rules.
  Eventually returns a list of weighted rules that can satisfy the demand.
"
  (let* ((input-lseq (gddr (car (filter (lambda (e)
           (equal? ghost-lemma-seq (gar e)))
             (cog-get-pred SENT 'PredicateNode)))))
         ; The ones that contains no variables/globs
         (exact-match (filter psi-rule? (cog-get-trunk input-lseq)))
         ; The ones that contains no constant terms
         (no-const (filter psi-rule? (append-map cog-get-trunk
           (cog-chase-link 'MemberLink 'ListLink ghost-no-constant))))
         ; The ones found by the recognizer
         (dual-match (filter psi-rule? (append-map cog-get-trunk
           (cog-outgoing-set (cog-execute! (Dual input-lseq))))))
         ; Get the psi-rules associate with them with duplicates removed
         (rules-matched
           (fold (lambda (rule prev)
                   ; Since a psi-rule can satisfy multiple goals and an
                   ; ImplicationLink will be generated for each of them,
                   ; we are comparing the implicant of the rules instead
                   ; of the rules themselves, and create a list of rules
                   ; with unique implicants
                   (if (any (lambda (r) (equal? (gar r) (gar rule))) prev)
                       prev (append prev (list rule))))
                 (list) (append exact-match no-const dual-match)))
         ; Evaluate the matched rules one by one and see which of them satisfy
         ; the current context
         (rules-satisfied (rank-and-eval rules-matched)))
        (cog-logger-debug ghost-logger "For input:\n~a" input-lseq)
        (cog-logger-debug ghost-logger "Rules with no constant:\n~a" no-const)
        (cog-logger-debug ghost-logger "Exact match:\n~a" exact-match)
        (cog-logger-debug ghost-logger "Dual match:\n~a" dual-match)
        (cog-logger-debug ghost-logger "Rules matched:\n~a" rules-matched)
        (cog-logger-debug ghost-logger "Rules satisfied:\n~a" rules-satisfied)
        (List rules-satisfied)))

(Define
  (DefinedSchema (ghost-prefix "Get Current Input"))
  (Get (State ghost-curr-proc (Variable "$x"))))

(Define
  (DefinedSchema (ghost-prefix "Find Rules"))
  (Lambda (VariableList (TypedVariable (Variable "$sentence")
                                       (Type "SentenceNode")))
          (ExecutionOutput (GroundedSchema "scm: ghost-find-rules")
                           (List (Variable "$sentence")))))

; The action selector for OpenPsi
(psi-set-action-selector!
  (Concept "GHOST")
  (Put (DefinedSchema (ghost-prefix "Find Rules"))
       (DefinedSchema (ghost-prefix "Get Current Input"))))
