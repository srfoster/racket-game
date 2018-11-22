#lang racket

;Stuff for start-game
(provide physics-start
         uniqify-ids
         final-state
         lux-start)

(provide new-component
         new-game-function
         (struct-out entity)
         (struct-out entity-name)
         
         (struct-out hidden)
         (struct-out disabled)

         (struct-out layer)
         
         (struct-out game) 
         (struct-out bb)

         draw-entities
         draw-entity

         set-layer
         get-layer

         entity-eq?
         entity-animation
         sprite->entity
         sprite->bb
         update-entity 
         get-component
         get-components
         add-component 
         remove-component
         add-components
         get-name
         get-id
         change-name
         basic-entity
         dead
         die
         get-entity

         colliding-with
         is-colliding-with?
         is-colliding-by-name?

         
         image->bb

         displayln-if

         draw
         game-width
         game-height
         width
         height
         set-posn
         get-posn
         x y

         component-is?
         set-velocity
         ;chipmunkify
         uniqify-id

         has-component?
         is-component?

         id
         id?

         new-game-function-f

         and/r
         or/r
         not/r

         entity-with-name
         replace-entity-in-list
         entity-in-list?
         union-entities
         die-if-member-of
         handler
         f-handler
         simple-handler
         )

(require posn)
(require 2htdp/image)
;(require 2htdp/universe)
(require "../components/animated-sprite.rkt")

(require threading)

(require (for-syntax racket/syntax))
(require (prefix-in phys: racket-chipmunk))



;This is what a game is...
(struct game ([entities #:mutable]
              [self-killed-entities #:mutable]
              [input #:mutable]
              [prev-input #:mutable]
              [collisions #:mutable]) #:transparent)

(define-syntax-rule (handler g e body)
  (lambda (g e)
    body ))

(define-syntax-rule (f-handler g e f)
  (lambda (g e)
    (f e)))

(define-syntax-rule (simple-handler body)
  (lambda (g e)
    body
    e))

(struct bb [w h])

(define (width e)
  (bb-w (get-component e bb?)))

(define (height e)
  (bb-h (get-component e bb?)))

(define w width)
(define h height)



(define (set-posn e p)
  (update-entity e posn? p))

(define (get-posn e)
  (get-component e posn?))



(define (x e)
  (posn-x (get-posn e)))

(define (y e)
  (posn-y (get-posn e)))


(struct id [id] #:transparent)



(struct entity [components] #:transparent)

(struct entity-name (string) #:transparent)


(define (entity-eq? e1 e2)
  (and
   (entity? e1)
   (entity? e2)
   (get-id e1)
   (get-id e2)
   (= (get-id e1)
      (get-id e2))))

(define component-handlers (hash))

(define (new-component struct? update)
  (set! component-handlers
        (hash-set component-handlers struct? update)))

(define (get-handler-for-component c)
  (define types    (hash-keys component-handlers))
  (define has-type (lambda (c t) (t c)))
  (define type     (findf (curry has-type c) types))
  (hash-ref component-handlers type #f))


(define (component? x)
  (get-handler-for-component x))

(define (and/r . rs)
  (λ(g e)
    (define bs (map (λ(r) (r g e)) rs))
    (define b (not (member #f bs)))
    b))

(define (or/r . rs)
  (λ(g e)
    (define bs (map (λ(r) (r g e)) rs))
    (define b (member #t bs))
    b))

(define (not/r r)
  (λ(g e)
    (not (r g e))))

(define game-functions (list))

(require (for-syntax racket))
(define-syntax (new-game-function stx)
  
  (define update (second (syntax->datum stx)))
  (displayln (~a "Registering game extension " update))
  (datum->syntax stx
   `(new-game-function-f ,(~a update) ,update)))

(define (new-game-function-f f-name update)
  (set! game-functions
        (append game-functions (list (list f-name update)))))


;Animated sprites are components, but we'll handle them specially
; at least until we can untangle them bettter...
(define (update-animated-sprite g e c)
  (update-entity e animated-sprite? next-frame))

(new-component animated-sprite?
               update-animated-sprite)

(define (get-name e)
  (define n (get-component e entity-name?))
  (if n
      (entity-name-string n)
      #f))


(define (entity-with-name n g)
  (findf (λ(x) (string=? n (get-name x))) (game-entities g)))

(define (get-id e)
  (id-id (get-component e id?)))

(define (entity-animation e)
  (findf animated-sprite? (entity-components e)))

(define (entity-bb e)
  (findf bb? (entity-components e)))

(define (component-is? c)
  (λ(x)
    (eq? x c)))

(define (add-or-update-component e pred? val)
  (add-component (remove-component e pred?)
                 val))

(define (update-component components component-pred f)
  (define ci (index-where components component-pred))
  (if ci
      (let [(old-component (list-ref components ci))]
        (if old-component
            (if (procedure? f)
                (list-set components ci (f old-component))
                (list-set components ci f))
            components))
      components))


;Only remove this contract if you want to spend a bunch of
; time tracking down bugs caused by forgetting to put at ? at
; the end of your predicate.
(define/contract (update-entity e component-pred f)
  (-> entity? (-> any/c boolean?) any/c entity?)
  (match-define (entity components) e)

  (and
   (eq? component-pred posn?)
   (has-chipmunk-body? e)
   (update-chipmunk-posn! e f))

  (entity (update-component components component-pred f)))


(define (update-chipmunk-posn! e p)
  (define c (entity->chipmunk e))
  (and (not (phys:destroyed-chipmunk? c))
       (phys:set-chipmunk-posn! c
                                (posn-x p)
                                (posn-y p))))

;You can pass in a predicate or an actual component
(define/contract (get-component e maybe-pred)
  (-> entity? any/c any/c)
  (define component-pred
    (if (procedure? maybe-pred)
        maybe-pred
        (lambda (c)
          (eq? c maybe-pred))))
  (findf component-pred (entity-components e)))

(define #;/contract (get-components e component-pred)
  #;(-> entity? any/c any/c)

  (filter component-pred (entity-components e)))

(define (add-component e c)
  (match-define (entity components) e)
  (entity (cons c components)))

(define (remove-component e c?)
  (match-define (entity components) e)

  ;Just a quick little side-effect here,
  ;  Nobody will notice...
  (maybe-clean-up-physical-collider! e c?)
  
  (entity (filter (lambda (c) (not (c? c))) components)))

  
(define (replace-entity-in-list updated-entity current-entities)
  (define (f entity)
    (if (entity-eq? entity updated-entity)
        updated-entity
        entity))
  (map f current-entities))

(define (entity-in-list? e l)
  (not (member e l entity-eq?)))

(define (union-entities a b) ;Versions of entities in a take presidence 
  (define in-a-not-b (filter (λ (o) (not (member o b entity-eq?))) a))
  (define in-a-and-b (filter (λ (o)      (member o b entity-eq?)) a))
  (define in-b-not-a (filter (λ (o) (not (member o a entity-eq?))) b))
  (append in-a-not-b
          in-a-and-b
          in-b-not-a))


(define (maybe-clean-up-physical-collider! e c?)
  (and (or (physical-collider? c?)
           (eq? physical-collider? c?))
       (get-component e physical-collider?)
       (already-chipmunkified? (get-component e physical-collider?))
       (phys:destroy-chipmunk (physical-collider-chipmunk (get-component e physical-collider?)))))

(define (add-components e . cs)
  (define flattened (flatten cs))
  (if (empty? flattened)
      e
      (apply (curry add-components (add-component e (first flattened)))
             (rest flattened))))

(define (basic-entity p s)
  (entity (list (id #f)
                p
                (image->bb (render s))
                s)))

(define (get-entity name g)
  (define (has-name n e)
    (string=? n (get-name e)))
  (findf (curry has-name name) (game-entities g)))

(define (sprite->entity sprite-or-image #:position p
                        #:name     n
                        #:components (c #f)
                        . cs)
  (define all-cs (flatten (filter identity (cons
                                            (entity-name n)
                                            (cons c cs)))))
  (define sprite (if (animated-sprite? sprite-or-image)
                     sprite-or-image
                     (new-sprite sprite-or-image)))
  (apply (curry add-components (basic-entity p sprite) )
         all-cs))

(define (sprite->bb s)
  (image->bb (render s)))

(define (image->bb i)
  (bb
   (image-width i)
   (image-height i)))



(provide (struct-out on-collide))

(struct on-collide (name func))

(define (displayln-if pred? . s)
  (and pred?
       (displayln (apply ~a s))))

(define (update-on-collide g e c)
  (add-physical-collider-if-necessary
   (if (is-colliding-with? (on-collide-name c) g e)
       ((on-collide-func c) g e)       
       e
       )))

(define (add-physical-collider-if-necessary e)
  (if (get-component e physical-collider?)
      e
      (chipmunkify (add-component e (make-physical-collider)))))

(new-component on-collide?
               update-on-collide)




;Input


(define-syntax (define-all-buttons stx)
  (syntax-case stx ()
    [(_ (button-states up-f down-f button-down? button-up? button-change-down? button-change-up?)
        (keys ...))
     (with-syntax [(test 42)]
       #`(begin
           (provide button-states)
           
           (define button-states
             (make-hash (list
                         (cons (format "~a" 'keys) #f)
                         ...)))
           
           (define (button-state-set key val)
             (hash-set! button-states (format "~a" key) val)
             button-states)

           (provide button-down?)
           (define (button-down? key g)
             (define h (game-input g))
             (hash-ref h (format "~a" key) #f))

           (provide button-up?)
           (define (button-up? key g)
             (not (button-down? key g)))
           
           (provide button-change-down?)
           (define (button-change-down? key g)
             (define prev-h (game-prev-input g))
             (and
              (button-down? key g)
              (not (hash-ref prev-h (format "~a" key) #f))))

           (provide button-change-up?)
           (define (button-change-up? key g)
             (define prev-h (game-prev-input g))
             (and
              (button-up? key g)
              (hash-ref prev-h (format "~a" key) #f)))

           (define (convert-special a-key)
             (cond [(string=? a-key "\b") "backspace"]
                   [(string=? a-key "\n") "enter"]
                   [(string=? a-key "\r") "enter"]
                   [(string=? a-key " ") "space"]
                   [else a-key]))
           
           ;Consumes a world, handles a single key PRESS by setting button state to true and returning the world
           (define (down-f larger-state a-key)

             (define key-name
               (convert-special a-key))

             (define btn-states (game-input larger-state))
             
             (set-game-input! larger-state
                              (cond                       
                                [(string=? key-name (format "~a" 'keys))  (button-state-set 'keys #t)]
                                ...
                                [else btn-states]))
             larger-state)

           ;Consumes a world, handles a single key RELEASE by setting button state to false and returning the world
           (define (up-f larger-state a-key)

             (define key-name
               (convert-special a-key))

             (define btn-states (game-input larger-state))
             
             (set-game-input! larger-state
                              (cond
                                [(string=? key-name (format "~a" 'keys))  (button-state-set 'keys #f)]
                                ...
                                [else btn-states]))
             larger-state)))]))


(define-all-buttons
  (button-states handle-key-up handle-key-down button-down? button-up? button-change-down? button-change-up?)
  (left right up down wheel-up wheel-down
        rshift lshift
        backspace
        enter
        space
        a b c d e f g h i j k l m n o p q r s t u v w x y z
        A B C D E F G H I J K L M N O P Q R S T U V W X Y Z
        0 1 2 3 4 5 6 7 8 9
        * - / + = < >
        |#| : |,| |.| | |
        |"| |'|
        |]| |[|
        ))





(define (draw-entity e)
  (define s (get-component e animated-sprite?))
  (if s
      (render s)
      empty-image))

(define (draw-entities es)
  (if (= 1 (length es))
      (draw-entity (first es))
      (let* ([p (get-component (first es) posn?)]
             [x (posn-x p)]
             [y (posn-y p)])
        (place-image (draw-entity (first es))
                     x y
                     (draw-entities (rest es))))))

(define (ui? e)
    (and ((has-component? layer?) e)
         (eq? (get-layer e) "ui")))

  (define (not-ui? e)
    (not (ui? e)))

(define #;/contract (draw g)
  #;(-> game? image?)
  (define (not-hidden e) (and (not (get-component e hidden?))
                              (not (get-component e disabled?))))
  (define not-hidden-entities (filter not-hidden (game-entities g)))
  (define regular-entities (filter not-ui? not-hidden-entities))
  (define ui-entities (filter ui? not-hidden-entities))
  (define entities (append ui-entities regular-entities))
  ;(define entities (filter not-hidden (game-entities g)))
  (draw-entities entities))



 
(define (is-colliding? e g)
  (findf (curry member e entity-eq?) (game-collisions g)))

(define (is-colliding-with? name g me)
  (define names (map get-name (colliding-with me g)))
  (member name names))

(define (is-colliding-by-name? name1 name2 g)
  (define names (map (curry map get-name) (game-collisions g)))
  (or (member (list name1 name2) names)
      (member (list name2 name1) names)))


(define (extract-out e l)
  (define (not-eq? e o)
    (not (entity-eq? e o)))
  (filter (curry not-eq? e) l))

(define (colliding-with e g)
  (filter identity
          (flatten
           (map (curry extract-out e)
                (filter (λ(other) (member e other entity-eq?))
                        (game-collisions g))))))

(define #;/contract (main-tick-component g e c)
  #;(-> any/c any/c any/c entity?)

  (define handler (get-handler-for-component c))
  (if handler
      (handler g e c)
      e))


(define #;/contract (tick-component g e c)
  #;(-> any/c any/c any/c entity?)
  (define next-entity-state (main-tick-component g e c))
  next-entity-state)

(define #;/contract (main-tick-entity g e)
  #;(-> any/c any/c entity?)

  (foldl
   (lambda (c e2)
     (tick-component g e2 c))
   e
   (entity-components e)))



(define (tick-entity g e)
  (main-tick-entity g (chipmunkify e)))

(define (tick-entities g)
  (define es (game-entities g))
  (struct-copy game g
               [entities (map (curry tick-entity g) es)]))


(define (do-game-functions g)
  (define pipeline (lambda (a-fun a-game)
                     (with-handlers ([exn:fail?
                                      (λ (e)
                                        (displayln e)
                                        (error (~a "Error running " (first a-fun) ": " e)))])
                       ((second a-fun) a-game))))
  (foldl pipeline g game-functions))




(define (store-prev-input g)
  (set-game-prev-input! g (hash-copy (game-input g))) 
  g)



(define (find-entity-by-id i g)
  (findf (λ(e) (eq? i (get-id e)))
         (game-entities g)))

(define (current-version-of e g)
  (find-entity-by-id (get-id e) g))

(define last-game-snapshot #f)

(define (uniqify-id g e)
  (if (or (not (get-id e))
          (member (get-id e)
                  (map get-id (remove e (game-entities g) entity-eq?))))
      (begin
       ;(displayln (~a "Setting new id"))
       (update-entity e id? (id (random 1000000))))
      e))

(define (uniqify-ids g)
  (struct-copy game g
               [entities (map (curry uniqify-id g)
                              (game-entities g))]))

(define tick
  (lambda (g)
    (define new-g (uniqify-ids g))
    
    (set! last-game-snapshot new-g)
    
    (define new-game (~> new-g
                         ;Just a note for the future.  This is not slow.  Do not move to a different thread in a misguided effort to optimize...
                         ;  However, maybe we should consider moving this to its own physics module...?
                         physics-tick 
                         tick-entities
                         handle-self-killed-entities
                         do-game-functions
                         handle-killed-entities
                         store-prev-input
                         cleanup-physics))
    ;(displayln (~a (map get-name (flatten (game-collisions g)))))

    (set-game-self-killed-entities! new-game '())
  
    new-game))

(define (handle-self-killed-entities g)
  (handle-dead g #t))

(define (handle-killed-entities g)
  (handle-dead g #f))


(define (die-if-member-of e doomed)
  (if (member e doomed entity-eq?)
      (add-component e (dead))
      e))

(define (handle-dead g self-killed?)
  (define is-alive? (lambda (e) (not (get-component e dead?))))

  (define doomed (filter (not/c is-alive?) (game-entities g)))

  (define doomed-chipmunks (filter identity
                                   (map entity->chipmunk doomed)))

  (for ([d doomed-chipmunks])
    (or (phys:destroyed-chipmunk? d)
        (phys:destroy-chipmunk d)))
  
  (set-game-entities! g (filter is-alive? (game-entities g)))
  
  (and self-killed?
       (set-game-self-killed-entities! g doomed))
  g)


(define (game-replace-entity g e)
  (define (replace-entity e1)
    (lambda (e2)
      (if (equal? (get-name e1)
                  (get-name e2))
          e1
          e2)))
  (struct-copy game g
               [entities (map (replace-entity e) (game-entities g))]))


(define (is-static? e)
  (get-component e static?))

(define (is-disabled? e)
  (get-component e disabled?))

(define (is-physical? e)
  (get-component e physical-collider?))

(define (is-static-and-not-disabled? e)
  (and (is-static? e)
       (not (is-disabled? e))))

(define (non-static? e)
  (not (is-static? e)))

(define (not-static-and-not-disabled? e)
  (and (not (is-static? e))
       (not (is-disabled? e))))

(define (not-both-static e-pair)
  (not (and (is-static? (first e-pair))
            (is-static? (second e-pair)))))





;DEAD ENTITIES

(struct dead ())

(define (die g e)
  (add-component e (dead)))

;END DEAD ENTITIES

;HIDDEN

(struct hidden ())

;END HIDDEN

;HIDDEN

(struct disabled ())


(struct layer (name))

(define (set-layer name)
 (lambda (g e)
     (update-entity e layer? (layer name))))

(define (get-layer e)
  (layer-name (get-component e layer?)))

;END HIDDEN



; END ACTIVE

(define (game-width g)
  (image-width (draw g)))


(define (game-height g)
  (image-height (draw g)))

(define (has-component? pred?)
  (lambda(e)
    (get-component e pred?)))


(define (is-component? c)
  (lambda(o)
    (or
     (eq? o c)
     (and (list? c)
          (member o c)))))






(define (final-state d)
  (demo-state d))


(require racket/match
         racket/fixnum
         racket/flonum
         lux
         lux/chaos/gui
         lux/chaos/gui/val
         (prefix-in lux: lux/chaos/gui/key)
         (prefix-in lux: lux/chaos/gui/mouse)

         (prefix-in ml: mode-lambda)
         (prefix-in ml: mode-lambda/static)
         (prefix-in gl: mode-lambda/backend/gl))



(struct demo
  ( state render-tick)
  #:methods gen:word
  [(define (word-fps w)
     60.0)  ;Changed from 60 to 30, which makes it more smooth on the Chromebooks we use in class.
            ;   Not sure why we were seeing such dramatic framerate drops
   
   (define (word-label s ft)
     (lux-standard-label "Values" ft))
   
   (define (word-output w)
     (match-define (demo  state render-tick) w)
     #;(g/v (draw state)) ;Old, slower drawing method.  For reference...
     (render-tick)
     )
   
   (define (word-event w e)
     (match-define (demo  state render-tick) w)
     (define closed? #f)
     (cond
       [(eq? e 'close)  #f]
       [(lux:key-event? e)

       
        (if (not (eq? 'release (send e get-key-code)))
            (demo  (handle-key-down state (format "~a" (send e get-key-code))) render-tick)
            (demo  (handle-key-up state (format "~a" (send e get-key-release-code))) render-tick))
         
        ]
       [else w]))
   
   (define (word-tick w)
     (match-define (demo  state render-tick) w)
     (demo  (tick state) render-tick)
     )])

(define (lux-start larger-state)
  (define render-tick (get-mode-lambda-render-tick (game-entities larger-state)))

  
  (call-with-chaos
   (make-gui #:start-fullscreen? #f #:mode gl:gui-mode)
   (λ () (fiat-lux (demo larger-state render-tick)))))

(define (id->symbol #:prefix (prefix "") n)
  (string->symbol (~a prefix "id" n)))

(define (sprite-eq? e1 e2)
  (animated-sprite-image-eq? (get-component e1 animated-sprite?)
                             (get-component e2 animated-sprite?)))
 
(define (get-mode-lambda-render-tick original-entities)
  (define sprite-entities
    (filter (has-component? animated-sprite?) original-entities))
  
  (define W (w (last original-entities)))
  (define H (h (last original-entities)))
  (define W/2 (/ W 2.0))
  (define H/2 (/ W 2.0))

  (define sd (ml:make-sprite-db))

  (define (add-entity! db e)
    (define frames (animated-sprite-frames (get-component e animated-sprite?)))
    (for ([i (in-range (vector-length frames))])
      (define id-sym (id->symbol #:prefix (~a "sprite" i) (get-id e)))
      (ml:add-sprite!/value db
                            id-sym
                            (vector-ref frames i))

      (displayln (~a "Compiling sprite " (get-name e) " id: " id-sym ))
      
      ))
  

  (for ([sprite-entity (in-list sprite-entities)])
    (add-entity! sd sprite-entity))
  
  (define csd (ml:compile-sprite-db sd))

  (displayln (ml:compiled-sprite-db-spr->idx csd))
 ; (ml:save-csd! csd (build-path "/Users/thoughtstem/Desktop/sprite-db") #:debug? #t)

  

  (define start (current-milliseconds))

  (define (time-since-start)
    (- start (current-milliseconds)))

  (define layers
    (vector
     (ml:layer (* W 1.0) (* H 1.0))))

  (define compiled original-entities)

  (define ml:render (gl:stage-draw/dc csd W H 8))
  
  (define (ticky-tick)
    
    ;Find uncompiled entities...
    (define uncompiled (if (not last-game-snapshot)
                           '()
                           (filter-not (curryr member compiled entity-eq? #;sprite-eq?)
                                       (game-entities last-game-snapshot))))


    ;Recompile the database if we added anything:
    (and (not (empty? uncompiled))
         (let ([sd2 (ml:make-sprite-db)])
           (for ([sprite-entity (in-list (append compiled uncompiled))])
             (and (get-component sprite-entity animated-sprite?)
                  (add-entity! sd2 sprite-entity)))
           (set! csd (ml:compile-sprite-db sd2))
           ;(ml:save-csd! csd (build-path "/Users/thoughtstem/Desktop/sprite-db") #:debug? #t)
           (set! compiled (append compiled uncompiled))
           (displayln (ml:compiled-sprite-db-spr->idx csd))
           (set! ml:render (gl:stage-draw/dc csd W H 8))))



    (define (sprites-to-render)
      (if (not last-game-snapshot)
          '()
          (flatten
           (filter identity
                   (for/list ([e (in-list (reverse (game-entities last-game-snapshot)))])
                     (define frame-i   (animated-sprite-current-frame (get-component e animated-sprite?)))
                     (define id-sym    (id->symbol #:prefix (~a "sprite" frame-i) (get-id e)))
                     (define sprite-id (ml:sprite-idx csd id-sym))

                    ; (displayln (~a (get-name e) " id: " id-sym " sprite-id: " sprite-id))

                     (if (not sprite-id)
                           #f
                           (ml:sprite #:layer 0
                                      (real->double-flonum (- (x e) W/2)) (real->double-flonum (- (y e) H/2))
                                      sprite-id)))))))

    
    
    (ml:render layers
               (sprites-to-render)
               '()))

  ticky-tick)





 
(define (change-name name)
  (lambda (g e)
    (update-entity e entity-name? (entity-name name))))










;Physics module.....

(require (prefix-in h:   lang/posn))



(provide (rename-out [make-physical-collider physical-collider])
         physical-collider?)

(struct physical-collider (chipmunk force) #:transparent)


(define (entity->chipmunk e)
  (define pc (get-component e physical-collider?))
  (if pc
      (physical-collider-chipmunk pc)
      #f))

(define (make-physical-collider)
  (physical-collider #f (posn 0 0)))


(define (set-velocity e p)
  (update-entity e physical-collider?
                 (struct-copy physical-collider (get-component e physical-collider?)
                              [force p])))


(provide (struct-out static))

(struct static ())

(define (handler-identity g e c)
  e)

(new-component static?
               handler-identity) 





(define *tick-rate* (/ 1 120.0))


(define (physics-tick g)  
  (phys:step-chipmunk *tick-rate*)


  

  (define (physics-tick-entity e)
    (define pc (get-component e physical-collider?))
    
    (if (or (not pc)
            (not (already-chipmunkified? pc)))
        e
        (let ([f (physical-collider-force pc)]
              [c (physical-collider-chipmunk pc)])

          (define new-pos (posn (phys:x c)
                                (phys:y c)))

          
          (update-entity e
                         ;This looks weird.  it's there to trick update-entity into not
                         ;  propagating position data into chipmunk world,
                         ;  since this posn information just came from there
                         (and/c posn? posn?)
                         new-pos))))

  (define new-es (map physics-tick-entity (game-entities g)))
  
  (struct-copy game g
               [entities new-es]))




(define (already-chipmunkified? pc)
  (and (physical-collider-chipmunk pc)
       (not (phys:destroyed-chipmunk? (physical-collider-chipmunk pc)))))


(define (chipmunkify e)
  (define pc (get-component e physical-collider?))
 
  (if (or (not pc)
          (already-chipmunkified? pc))
      e
      (let ([chipmunk ((if (get-component e static?) phys:box-kinematic phys:box)
                       (x e)
                       (y e)
                       (w e)
                       (h e)
                       #:group (if (get-component e static?) 2 1) ;Is this what we want???
                       #:meta (get-id e)
                       )])


        (chipmunkify-step2
         (update-entity e physical-collider?
                        (physical-collider chipmunk (posn 0 0)))))))




(define (vel-func chipmunk gravity damping dt)

  (define e (find-entity-by-id (phys:chipmunk-meta chipmunk) last-game-snapshot))

  ;(displayln (~a "Find by id " (phys:chipmunk-meta chipmunk)))
  ;(displayln e)


  #;(phys:cpBodyUpdateVelocity body gravity damping dt)

  (and e
       (get-component e physical-collider?) ;Shouldn't it always have one at this point??  
       (phys:set-velocity! (entity->chipmunk e) ;chipmunk
                           (posn-x (physical-collider-force (get-component e physical-collider?)))
                           (posn-y (physical-collider-force (get-component e physical-collider?))))))



(define (chipmunkify-step2 e)

  (define (set-vel-func-for-sure e)

    (define chipmunk (physical-collider-chipmunk
                      (get-component e physical-collider?)))
    
    (define body (phys:chipmunk-body chipmunk))

    (phys:set-velocity-function! chipmunk vel-func))


  (define (set-vel-func e)
    (if (is-static? e)
        e
        (set-vel-func-for-sure e)))

  (set-vel-func e)
  e)


(define (physics-start g)
  (displayln "Physics start")

  (phys:set-presolve!
   (λ(c1 c2)
     (define e1 (find-entity-by-id (phys:chipmunk-meta c1) last-game-snapshot))
     (define e2 (find-entity-by-id (phys:chipmunk-meta c2) last-game-snapshot))

     #;(displayln (~a "Colliding " (get-name e1) " " (get-name e2)))

     (set-game-collisions! last-game-snapshot
                           (cons (list e1 e2)
                                 (game-collisions last-game-snapshot)))))

  (define new-es (map chipmunkify (game-entities g)))

  
  (struct-copy game g

               ;Filtering here is weird.  It assumes that physical, static, disabled components
               ;  should not be added to the game.  Optimizes away things like hidden walls.
               ;  But it's a potential bug if you actually want that thing to become enabled at some point...
               ;Maybe safe though.  Why not just use hidden?
               ;   Can initially disabled components actually be woken up
               ;  anyway?

               ;NOTE: Rolled back that filtering optimization.  It loses track of entities, which makes it harder
               ;  to clean up chipmunks later.
               [entities new-es #;(filter (or/c
                                           (not/c is-static?)
                                           (not/c is-physical?)
                                           (not/c is-disabled?)) new-es)]))



(define (cleanup-physics g)
  (set-game-collisions! g '())
  g)

(define (has-chipmunk-body? e)
  (and
   (get-component e physical-collider?)
   (entity->chipmunk e)
   (phys:chipmunk-body (entity->chipmunk e))))








