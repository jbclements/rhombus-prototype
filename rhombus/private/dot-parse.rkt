#lang racket/base
(require (for-syntax racket/base
                     syntax/parse/pre
                     "statically-str.rkt"
                     "srcloc.rkt")
         "parse.rkt"
         "parens.rkt"
         "static-info.rkt"
         (submod "assign.rkt" for-assign))

(provide (for-syntax dot-parse-dispatch
                     set-parse-function-call!))

(define-for-syntax (dot-parse-dispatch k)
  (lambda (lhs dot-stx field-stx tail more-static? success-k fail-k)
    (define (ary mask n-k no-k)
      (define (bad msg)
        (raise-syntax-error #f msg field-stx))
      (syntax-parse tail
        #:datum-literals ()
        [((~and args (p-tag::parens g ...)) . new-tail)
         (define gs (syntax->list #'(g ...)))
         (define n (length gs))
         (cond
           [(bitwise-bit-set? mask n)
            (success-k (n-k #'(p-tag g ...)
                            n
                            (lambda (e)
                              (relocate (respan #`(#,lhs args)) e)))
                       #'new-tail)]
           [else
            (if more-static?
                (bad (string-append "wrong number of arguments in method call" statically-str))
                (success-k (no-k (lambda (e)
                                   (relocate (respan #`(#,lhs #,field-stx)) e)))
                           tail))])]
        [_
         (if more-static?
             (bad "expected parentheses afterward")
             (success-k (no-k (lambda (e)
                                (relocate (respan #`(#,lhs #,field-stx)) e)))
                        tail))]))

    (define (nary mask direct-id id [static-infos #f])
      (define (wrap n stx)
        (define maybe-static-infos
          (if (procedure? static-infos)
              (static-infos n)
              static-infos))
        (if maybe-static-infos
            (wrap-static-info* stx maybe-static-infos)
            stx))
      (ary mask
           (if (eqv? mask 1)
               ;; fast path given no args
               (lambda (no-args n reloc)
                 (wrap 0
                       (relocate
                        (respan #`(#,lhs #,field-stx))
                        #`(#,direct-id #,lhs))))
               (lambda (args n reloc)
                 (wrap n
                       (let ()
                         (define-values (proc tail)
                           (parse-function-call direct-id (list lhs) #`(#,direct-id #,args)
                                                #:srcloc (reloc #'#false)
                                                #:static? more-static?))
                         proc))))
           ;; return partially applied method
           (lambda (reloc)
             (reloc #`(#,id #,lhs)))))

    (define field
      (let ([just-access
             (lambda (mk)
               (success-k (mk lhs
                              (lambda (e)
                                (relocate (respan #`(#,lhs #,field-stx)) e)))
                          tail))])
        (case-lambda
          [(mk) (just-access mk)]
          [(mk mk-set)
           (syntax-parse tail
             [assign::assign-op-seq
              (call-with-values
               success-k
               (lambda ()
                 (build-assign
                  (attribute assign.op)
                  #'assign.name
                  #`(lambda ()
                      #,(mk lhs (lambda (e)
                                  (relocate (respan #`(#,lhs #,field-stx)) e))))
                  #`(lambda (v)
                      #,(mk-set lhs #'v
                                (lambda (e)
                                  (relocate (respan #`(#,lhs #,field-stx)) e))))
                  #'value
                  #'assign.tail)))]
             [_ (just-access mk)])])))

    (k (syntax-e field-stx) field ary nary fail-k)))

(define-for-syntax parse-function-call #f)
(define-for-syntax (set-parse-function-call! proc)
  (set! parse-function-call proc))
