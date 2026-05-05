extensions [ gis csv table vid ]

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;; BREEDS ;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

breed [ residents    resident    ]
breed [ pedestrians  pedestrian  ]
breed [ parents      parent      ]
breed [ workers      worker      ]
breed [ relatives    relative    ]
breed [ car-drivers  car-driver  ]
breed [ intersections intersection ]
directed-link-breed [ roads road ]
breed [ firestations firestation ]
breed [ firetrucks   firetruck   ]
breed [ buses        bus-vehicle ]

firestations-own [ id ]

turtles-own [
  evacuated?
  rescued-by-firefighters?
  alert-received?
  alert-channel
]

patches-own [
  depth depths max_depth waterDepth floodClass
  water-rise-rate
  predicted-depth
  prev-depth
  shared-congestion-signal
  civilian-flood-signal
]

residents-own [
  init_dest reached? current_int moving?
  speed decision miltime time_in_water
  max_depth_agent
  wait-start-tick
  prev-flood-class
]

roads-own [ crowd traffic mid-x mid-y road-capacity-factor crowd-density ]

intersections-own [
  shelter? shelter_type id previous fscore gscore
  hor-path evacuee_count
  school?
  workplace?
]

pedestrians-own [
  current_int shelter next_int moving?
  speed path decision time_in_water
  max_depth_agent
]

parents-own [
  current_int dest_int next_int moving?
  speed path time_in_water max_depth_agent
  mission-done?
]

workers-own [
  current_int dest_int next_int moving?
  speed path time_in_water max_depth_agent
  mission-done?
]

relatives-own [
  current_int dest_int next_int moving?
  speed path time_in_water max_depth_agent
  mission-done?
]

car-drivers-own [
  current_int next_int dest_int moving?
  speed path time_in_water max_depth_agent
  can-drive?
  decision
]

buses-own [
  current_int next_int dest_int home_post
  path phase capacity
  passengers-cargo moving? speed
]

firetrucks-own [
  current_int next_int path
  target-resident target_int
  moving? speed
  rescue_time
  home_post
  drop_post
  phase
  capacity
  cargo
  dispatch-tick
  firetruck-station-id
  alt-paths
  current-route-idx
  reroute-cooldown
  priority-mode?
  prev-path
]

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;; GLOBALS ;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

globals [
  ev_times
  mouse-was-down?
  road_network
  population_distribution
  shelter_locations
  tsunami_sample
  cis_dataset
  ecoles_dataset
  entreprises_dataset

  zip100-raster
  tsunami_data_inc
  tsunami_data_start
  tsunami_data_count
  last-tsunami-idx

  tsunami_max_depth
  tsunami_min_depth

  cum_rescued
  cum_self_evacuated

  reinforcement_posts
  reinforcement_start_min
  reinforcement_interval_sec
  reinforcement_batch_size

  cached-shelters
  cached-schools
  cached-workplaces
  flood-patches-cache

  N_Foot
  N_Wait

  patch_to_meter
  tick_to_sec

  fd_to_mps
  fd_to_kph

  min_lon
  min_lat

  access-times
  cum-reroutes

  record-video?
  video-filename

  cum-parents-arrived
  cum-workers-arrived
  cum-relatives-arrived

  nb-camions-bloques
  pct-routes-inondees
  pct-routes-saturees

  temps-acces-caserne-1
  temps-acces-caserne-2
  temps-acces-caserne-3

  saturation-threshold
  crowd-weight
  road-block-rate
  num-parents
  num-workers
  num-relatives

  immediate_evacuation
  wait-time-min

  accessibility-index
  mean-rescue-delay
  isolated-victims-count
  pct-network-accessible

  reinforcement-activated
  reinforcement-trigger-min
  reinforcement-alert-shown
  simulation-paused?

  cum-congestion-events
  cum-trucks-delivered

  alert-delay-min
  shelter-capacity-pct

  num-buses
  num-car-drivers

  flood-lookahead
  flood-rise-threshold
  flood-update-interval

  road-usage-counts

  claimed-victims
  reroute-refresh-interval
  alert-propagation-radius
  cum-civilian-reroutes

  cum-truck-congestion-events
  cum-civil-congestion-events

  shelter-max-capacity
  shelter-saturation-reroutes

  cum-civil-reactions-to-truck-reroute
  congestion-signal-decay

  comm-channel
  radio-alert-radius
  radio-alert-delay-ticks
  radio-alert-fired?
  app-alert-radius
  app-alert-delay-ticks
  app-alert-fired?
  word-of-mouth-radius
  cum-radio-alerts
  cum-app-alerts
  cum-wom-alerts
  cum-firetruck-alerts

  firetruck-priority-enabled?
  priority-crowd-reduction
  cum-priority-passages

  base-truck-speed
  cum-speed-reductions

  access-time-reinforce-threshold
  access-time-check-interval
  cum-access-triggered-reinforcements

  cum-civilian-flood-signals
  cum-shelter-saturation-civilian-reroutes
  cum-index-driven-prioritizations
  cum-traffic-saturation-managed
]

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; REPORTER CENTRAL
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

to-report evac-agents
  report (turtle-set residents pedestrians)
end

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; RESET CONFIG
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

to reset-config
  set a1-civilian-signal?    false
  set a2-shelter-saturation? false
  set a3-priority-index?     false
  set a4-traffic-management? false
  set scenario-type "none"
end

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;; HELPERS ;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

to-report mouse-clicked?
  report (mouse-was-down? = true and not mouse-down?)
end

to-report find-origins
  let origins []
  ask residents [
    set origins lput min-one-of intersections [ distance myself ] origins
  ]
  set origins remove-duplicates origins
  report origins
end

to make-decision
  set decision 0
  set miltime (Rtau1 / tick_to_sec)
end

;; Rayleigh-sample — modélise le délai de réaction à l'alerte (Douvinet 2018).
;; sigma varie selon le niveau d'exposition à l'inondation :
;;   - zone très exposée (floodClass >= 3) : sigma court  (~2–5 min)
;;   - zone moyennement exposée (fc = 2)   : sigma moyen  (~6–10 min)
;;   - zone peu exposée (fc <= 1)           : sigma long   (~7–15 min)
;; Le canal d'alerte (radio, appli, bouche-à-oreille, proximité camion)
;; module la probabilité de déclenchement ET le sigma utilisé.
to-report rayleigh-sample [ sigma ]
  let u random-float 0.9999
  if u <= 0 [ set u 0.0001 ]
  report sigma * sqrt (-2 * ln (1 - u))
end

to-report flood-penalty-for-patch [ mid-p ]
  if mid-p = nobody [ report 0 ]
  let pen  0
  let fc   [floodClass]       of mid-p
  let wd   [depth]            of mid-p
  let pred [predicted-depth]  of mid-p
  let rise [water-rise-rate]  of mid-p

  set pen pen + fc * 10
  if fc >= 3 [ set pen pen + fc * 10 ]
  if wd > 0.3 [ set pen pen + wd * 15 ]
  if wd > 0.6 [ set pen pen + wd * 10 ]
  if wd > 1.0 [ set pen pen + 40 ]
  if wd > 1.2 [ report 99999 ]
  if pred > 0.3 [ set pen pen + pred * 18 ]
  if pred > 0.6 [ set pen pen + pred * 12 ]
  if pred > 1.0 [ set pen pen + 45 ]
  if pred > 1.2 [ report 99999 ]
  if rise > flood-rise-threshold [ set pen pen + rise * 65 ]

  if a4-traffic-management? [
    let sig [shared-congestion-signal] of mid-p
    if sig > 0 [ set pen pen + sig * 20 ]
  ]
  if a1-civilian-signal? [
    let csig [civilian-flood-signal] of mid-p
    if csig > 0.5 [ set pen pen + csig * 15 ]
    if csig > 2.0 [ set pen pen + csig * 10 ]
  ]
  report pen
end

to assign-decisions-behavioral
  ask residents [
    let fc [floodClass] of patch-here
    let p-evacuate 0.50
    if fc = 1 [ set p-evacuate 0.65 ]
    if fc = 2 [ set p-evacuate 0.80 ]
    if fc = 3 [ set p-evacuate 0.90 ]
    if fc = 4 [ set p-evacuate 0.97 ]
    if alert-received? [ set p-evacuate min list 1.0 (p-evacuate + 0.15) ]
    ifelse random-float 1 < p-evacuate [
      set decision 1
      ;; Sigma Rayleigh (en secondes) selon le niveau d'exposition :
      ;;   floodClass >= 3 → sigma = 5 min  (zone très exposée, réaction rapide)
      ;;   floodClass  = 2 → sigma = 10 min (zone moyennement exposée)
      ;;   floodClass <= 1 → sigma = 15 min (zone peu exposée, réaction plus lente)
      let sigma-sec ifelse-value (fc >= 3) [ 5 * 60 ]
        [ ifelse-value (fc = 2) [ 10 * 60 ] [ 15 * 60 ] ]
      let raw-time (rayleigh-sample sigma-sec) / tick_to_sec
      set miltime max list 1 raw-time
    ] [
      set decision 2
      set color gray
      set miltime 0
    ]
    set prev-flood-class fc
  ]
  set N_Foot count residents with [ decision = 1 ]
  set N_Wait count residents with [ decision = 2 ]
end

to assign-decisions-risk-based
  assign-decisions-behavioral
end

to update-water-rise-rates
end

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; A*
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

to-report Astar [ source gl gls ]
  let rchd? false
  let dstn nobody
  let closedset []
  let openset []
  ask intersections [ set previous -1 ]
  set openset lput [who] of source openset
  ask source [
    set gscore 0
    set fscore (gscore + distance gl)
  ]
  while [ not empty? openset and (not rchd?) ] [
    let current Astar-smallest openset
    if member? current [who] of gls [
      set dstn intersection current
      set rchd? true
    ]
    set openset remove current openset
    set closedset lput current closedset
    ask intersection current [
      ask out-road-neighbors [
        let this-road road [who] of myself who
        let road-cost   [link-length] of this-road
        let cap-factor  [road-capacity-factor] of this-road
        let crowd-pen   crowd-weight * [crowd] of this-road
        if cap-factor <= 0 [ stop ]
        let block-pen ifelse-value (cap-factor < 1.0)
          [ (1.0 - cap-factor) * 30 ] [ 0 ]
        let mid-p patch [mid-x] of this-road [mid-y] of this-road
        let flood-pen flood-penalty-for-patch mid-p
        let tent_gscore [gscore] of myself + road-cost + crowd-pen + block-pen + flood-pen
        let tent_fscore tent_gscore + distance gl
        if ( member? who closedset and ( tent_fscore >= fscore ) ) [ stop ]
        if ( not member? who closedset or ( tent_fscore >= fscore )) [
          set previous current
          set gscore tent_gscore
          set fscore tent_fscore
          if not member? who openset [ set openset lput who openset ]
        ]
      ]
    ]
  ]
  let route []
  ifelse dstn != nobody [
    while [ [previous] of dstn != -1 ] [
      set route fput [who] of dstn route
      set dstn intersection ([previous] of dstn)
    ]
  ] [ set route [] ]
  report route
end

to-report Astar-smallest [ who_list ]
  let min_who 0
  let min_fscr 100000000
  foreach who_list [ [?1] ->
    let fscr [fscore] of intersection ?1
    if fscr < min_fscr [ set min_fscr fscr  set min_who ?1 ]
  ]
  report min_who
end

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; K-BEST PATHS
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

to-report k-best-paths [ src tgt k ]
  let routes []
  let penalty-multipliers [ 0.10 0.20 0.35 0.50 ]
  let base-route Astar src tgt (turtle-set tgt)
  if not empty? base-route [ set routes lput base-route routes ]
  let iter 0
  while [ iter < (k - 1) and length routes < k ] [
    let pmul item (min list iter (length penalty-multipliers - 1)) penalty-multipliers
    let saved-caps table:make
    ask roads [
      let lkey (list ([who] of end1) ([who] of end2))
      table:put saved-caps lkey road-capacity-factor
    ]
    foreach routes [ r ->
      let i 0
      while [ i < length r - 1 ] [
        let from-who item i r
        let to-who   item (i + 1) r
        if intersection from-who != nobody and intersection to-who != nobody [
          if [out-road-neighbor? intersection to-who] of intersection from-who [
            let rd road from-who to-who
            if rd != nobody [
              ask rd [ set road-capacity-factor max list 0.05 (road-capacity-factor * pmul) ]
            ]
          ]
        ]
        set i i + 1
      ]
    ]
    let alt-route Astar src tgt (turtle-set tgt)
    ask roads [
      let lkey (list ([who] of end1) ([who] of end2))
      if table:has-key? saved-caps lkey [
        set road-capacity-factor table:get saved-caps lkey
      ]
    ]
    if not empty? alt-route [
      let is-duplicate? false
      foreach routes [ r -> if r = alt-route [ set is-duplicate? true ] ]
      if not is-duplicate? [ set routes lput alt-route routes ]
    ]
    set iter iter + 1
  ]
  report routes
end

to-report trucks-on-road [ from-who to-who ]
  let key (list from-who to-who)
  ifelse table:has-key? road-usage-counts key
    [ report table:get road-usage-counts key ]
    [ report 0 ]
end

to-report route-score [ route ]
  if empty? route [ report 99999 ]
  let total-score 0
  let i 0
  while [ i < length route - 1 ] [
    let from-int intersection item i route
    let to-int   intersection item (i + 1) route
    if from-int != nobody and to-int != nobody [
      if [out-road-neighbor? to-int] of from-int [
        let r road [who] of from-int [who] of to-int
        if r != nobody [
          let cap [road-capacity-factor] of r
          if cap <= 0 [ report 99999 ]
          let dist      [link-length] of r
          let cong-pen  [crowd-density] of r * crowd-weight
          let block-pen ifelse-value (cap < 0.5) [ (1 - cap) * 50 ] [ 0 ]
          let mid-p patch [mid-x] of r [mid-y] of r
          let flood-pen flood-penalty-for-patch mid-p
          let truck-count trucks-on-road ([who] of from-int) ([who] of to-int)
          let coordination-pen truck-count * 15
          let seg-depth ifelse-value (mid-p != nobody) [ [depth] of mid-p ] [ 0 ]
          let effective-speed max list 0.1 (1.0 - (seg-depth / 1.5))
          let travel-time (dist / effective-speed)
          set total-score total-score + travel-time + cong-pen + block-pen
            + flood-pen + coordination-pen
        ]
      ]
    ]
    set i i + 1
  ]
  report total-score
end

to-report best-of-k-routes [ routes ]
  if empty? routes [ report [] ]
  let best-route first routes
  let best-score route-score best-route
  foreach routes [ r ->
    let s route-score r
    if s < best-score [ set best-score s  set best-route r ]
  ]
  report best-route
end

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; CONGESTION
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

to update-crowd
  ask roads [
    let civil-count count
      (turtle-set residents pedestrians parents workers relatives car-drivers) with [
        distancexy [mid-x] of myself [mid-y] of myself < 3
      ]
    let truck-count count firetrucks with [
      distancexy [mid-x] of myself [mid-y] of myself < 3
    ]
    let priority-trucks-here count firetrucks with [
      priority-mode? = true and
      distancexy [mid-x] of myself [mid-y] of myself < 3
    ]
    let effective-civil-count ifelse-value
      (a4-traffic-management? and firetruck-priority-enabled? and priority-trucks-here > 0)
      [ max list 0 (civil-count - (priority-trucks-here * 2)) ]
      [ civil-count ]
    let truck-equiv truck-count * 3
    let priority-reduction ifelse-value
      (a4-traffic-management? and firetruck-priority-enabled? and priority-trucks-here > 0)
      [ priority-trucks-here * 2 ] [ 0 ]
    set crowd max list 0 (effective-civil-count + truck-equiv - priority-reduction)

    let agents-nearby (turtle-set residents pedestrians parents workers relatives car-drivers) with [
      distancexy [mid-x] of myself [mid-y] of myself < 5
    ]
    let weighted-density 0
    ask agents-nearby [
      let d distancexy [mid-x] of myself [mid-y] of myself
      if d > 0.01 [ set weighted-density weighted-density + (1 / d) ]
    ]
    ask firetrucks with [ distancexy [mid-x] of myself [mid-y] of myself < 5 ] [
      let d distancexy [mid-x] of myself [mid-y] of myself
      if d > 0.01 [ set weighted-density weighted-density + (3 / d) ]
    ]
    set crowd-density precision weighted-density 3

    if road-capacity-factor >= 0.7 [
      ifelse crowd >= saturation-threshold [
        set color red
        ifelse truck-equiv > effective-civil-count
          [ set cum-truck-congestion-events cum-truck-congestion-events + 1 ]
          [ set cum-civil-congestion-events cum-civil-congestion-events + 1 ]
      ] [ set color black ]
    ]
  ]
end

to update-road-obstructions
  ask roads [
    let mid-patch patch mid-x mid-y
    if mid-patch != nobody [
      let fc [floodClass] of mid-patch
      let wd max list ([depth] of mid-patch) ([waterDepth] of mid-patch)
      if wd > 0.1 and wd <= 0.3 [ set road-capacity-factor max list 0.6 (road-capacity-factor - 0.03) ]
      if wd > 0.3 and wd <= 0.6 [ set road-capacity-factor max list 0.3 (road-capacity-factor - 0.08) ]
      if wd > 0.6 and wd <= 1.0 [ set road-capacity-factor max list 0.1 (road-capacity-factor - 0.12) ]
      if wd > 1.0               [ set road-capacity-factor max list 0.0 (road-capacity-factor - 0.20) ]
      let rise [water-rise-rate] of mid-patch
      if rise > flood-rise-threshold and wd > 0 [
        set road-capacity-factor max list 0.05 (road-capacity-factor - rise * 0.5) ]
      let pred [predicted-depth] of mid-patch
      if pred > 0.6 and road-capacity-factor > 0.3 [
        set road-capacity-factor max list 0.3 (road-capacity-factor - 0.05) ]
      if pred > 1.0 [ set road-capacity-factor max list 0.1 (road-capacity-factor - 0.10) ]
      if wd <= 0 and crowd = 0 [
        set road-capacity-factor min list 1.0 (road-capacity-factor + 0.02) ]
      if fc >= 2 [
        let prob-block (road-block-rate / 100) * (fc - 1) * 0.04
        if random-float 1 < prob-block [
          set road-capacity-factor max list 0.1 (road-capacity-factor - 0.10) ]
      ]
      if road-capacity-factor <= 0 [ set color red ]
      if road-capacity-factor > 0 and road-capacity-factor < 0.3 [ set color red + 1 ]
      if road-capacity-factor >= 0.3 and road-capacity-factor < 0.7 [ set color orange ]
      if road-capacity-factor >= 0.7 [
        ifelse crowd >= saturation-threshold [ set color red ] [ set color black ] ]
    ]
  ]
end

to update-road-status
  if count roads = 0 [ stop ]
  let nb-inondees 0
  ask roads [
    let p patch mid-x mid-y
    if p != nobody [
      let water-level max list ([depth] of p) ([waterDepth] of p)
      if water-level > 0.2 and [floodClass] of p >= 2 [ set nb-inondees nb-inondees + 1 ]
    ]
  ]
  set pct-routes-inondees precision (100 * nb-inondees / count roads) 1
  let nb-saturees count roads with [ crowd >= saturation-threshold and road-capacity-factor >= 0.2 ]
  set pct-routes-saturees precision (100 * nb-saturees / count roads) 1
end

to update-road-usage-counts
  set road-usage-counts table:make
  ask firetrucks with [
    (phase = "to-victim" or phase = "to-drop") and length path >= 2
  ] [
    let i 0
    while [ i < length path - 1 ] [
      let key (list item i path  item (i + 1) path)
      let current-count ifelse-value (table:has-key? road-usage-counts key)
        [ table:get road-usage-counts key ] [ 0 ]
      table:put road-usage-counts key (current-count + 1)
      set i i + 1
    ]
  ]
end

to-report firetruck-detects-congestion? [ truck-path ]
  let look-ahead max list 0 (length truck-path - 1)
  let i 0
  let detected? false
  while [i < look-ahead and not detected?] [
    let from-int intersection item i truck-path
    let to-int   intersection item (i + 1) truck-path
    if from-int != nobody and to-int != nobody [
      if [out-road-neighbor? to-int] of from-int [
        let r road [who] of from-int [who] of to-int
        if r != nobody [
          let proximity-factor ifelse-value (i < 3) [ 1.0 ]
            [ ifelse-value (i < 8) [ 0.8 ] [ 0.6 ] ]
          if [crowd] of r >= (saturation-threshold * proximity-factor) [ set detected? true ]
          if [road-capacity-factor] of r < (0.35 * proximity-factor)   [ set detected? true ]
          let mid-p patch [mid-x] of r [mid-y] of r
          if mid-p != nobody [
            if [waterDepth] of mid-p > (0.4 * proximity-factor)        [ set detected? true ]
            if [water-rise-rate] of mid-p > flood-rise-threshold        [ set detected? true ]
            if [predicted-depth] of mid-p > (0.5 * proximity-factor)   [ set detected? true ]
            if a1-civilian-signal? [
              if [civilian-flood-signal] of mid-p > 2.5                [ set detected? true ]
            ]
          ]
        ]
      ]
    ]
    set i i + 1
  ]
  report detected?
end

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; AMELIORATION 1 — SIGNAL CIVIL → POMPIERS
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

to civilians-broadcast-flood-signals
  if not a1-civilian-signal? [ stop ]
  ask residents with [ not evacuated? and [waterDepth] of patch-here > 0.3 ] [
    ask patch-here [
      set civilian-flood-signal min list 5.0 (civilian-flood-signal + 0.35)
    ]
    set cum-civilian-flood-signals cum-civilian-flood-signals + 1
  ]
  ask pedestrians with [ not evacuated? ] [
    if [waterDepth] of patch-here > 0.3 [
      ask patch-here [
        set civilian-flood-signal min list 5.0 (civilian-flood-signal + 0.40)
      ]
      set cum-civilian-flood-signals cum-civilian-flood-signals + 1
    ]
    if not empty? path [
      let check-steps min list 2 (length path)
      let j 0
      while [ j < check-steps - 1 ] [
        let from-int-who item j path
        let to-int-who   item (j + 1) path
        let from-int intersection from-int-who
        let to-int   intersection to-int-who
        if from-int != nobody and to-int != nobody [
          if [out-road-neighbor? to-int] of from-int [
            let r road from-int-who to-int-who
            if r != nobody [
              let mid-p patch [mid-x] of r [mid-y] of r
              if mid-p != nobody [
                if [waterDepth] of mid-p > 0.4 [
                  ask mid-p [
                    set civilian-flood-signal min list 5.0 (civilian-flood-signal + 0.25)
                  ]
                ]
              ]
            ]
          ]
        ]
        set j j + 1
      ]
    ]
  ]
end

to decay-civilian-flood-signals
  ask patches with [ civilian-flood-signal > 0 ] [
    set civilian-flood-signal max list 0 (civilian-flood-signal * 0.80)
  ]
end

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; SIGNAL DE CONGESTION PARTAGE
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

to broadcast-congestion-signal [ old-route congested? ]
  if empty? old-route [ stop ]
  if not a4-traffic-management? [ stop ]
  let signal-value ifelse-value congested? [ 1.0 ] [ -0.3 ]
  let i 0
  while [ i < length old-route - 1 ] [
    let from-int intersection item i old-route
    let to-int   intersection item (i + 1) old-route
    if from-int != nobody and to-int != nobody [
      if [out-road-neighbor? to-int] of from-int [
        let r road [who] of from-int [who] of to-int
        if r != nobody [
          let mid-p patch [mid-x] of r [mid-y] of r
          if mid-p != nobody [
            ask mid-p [
              set shared-congestion-signal
                min list 5.0 (max list 0 (shared-congestion-signal + signal-value))
            ]
          ]
        ]
      ]
    ]
    set i i + 1
  ]
end

to decay-congestion-signals
  ifelse a4-traffic-management? [
    ask patches with [ shared-congestion-signal > 0 ] [
      set shared-congestion-signal
        max list 0 (shared-congestion-signal * congestion-signal-decay)
    ]
  ] [
    ask patches [ set shared-congestion-signal 0 ]
  ]
end

to civilian-react-to-truck-reroute [ old-route ]
  if empty? old-route [ stop ]
  let sum-x 0  let sum-y 0  let count-pts 0
  foreach old-route [ int-who ->
    let int-node intersection int-who
    if int-node != nobody [
      set sum-x sum-x + [xcor] of int-node
      set sum-y sum-y + [ycor] of int-node
      set count-pts count-pts + 1
    ]
  ]
  if count-pts = 0 [ stop ]
  let cx sum-x / count-pts
  let cy sum-y / count-pts
  ask pedestrians with [
    evacuated? = false and not empty? path and current_int != nobody and
    distancexy cx cy < alert-propagation-radius
  ] [
    let goals nobody
    ifelse a2-shelter-saturation? [
      set goals cached-shelters with [ shelter_type = "Hor" and evacuee_count < shelter-max-capacity ]
      if not any? goals [ set goals cached-shelters with [ shelter_type = "Hor" ] ]
      if not any? goals [ set goals cached-shelters with [ evacuee_count < shelter-max-capacity ] ]
      if not any? goals [ set goals cached-shelters ]
    ] [
      set goals cached-shelters with [ shelter_type = "Hor" ]
      if not any? goals [ set goals cached-shelters ]
    ]
    if any? goals [
      let best-goal min-one-of goals [ distance myself ]
      if best-goal != nobody [
        let new-path Astar current_int best-goal (turtle-set best-goal)
        if not empty? new-path and new-path != path [
          set path new-path
          set shelter [who] of best-goal
          set moving? false
          set cum-civilian-reroutes cum-civilian-reroutes + 1
          set cum-civil-reactions-to-truck-reroute cum-civil-reactions-to-truck-reroute + 1
        ]
      ]
    ]
  ]
end

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; AMELIORATION 2 — SATURATION ABRIS
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

to reroute-pedestrians
  ask pedestrians with [ evacuated? = false and not empty? path and current_int != nobody ] [
    let need-reroute? false
    let check-ahead min list 3 (length path)
    let j 0
    while [ j < check-ahead - 1 and not need-reroute? ] [
      let from-int-who item j path
      let to-int-who   item (j + 1) path
      let from-int intersection from-int-who
      let to-int   intersection to-int-who
      if from-int != nobody and to-int != nobody [
        if [out-road-neighbor? to-int] of from-int [
          let r road from-int-who to-int-who
          if r != nobody [
            let prox-factor ifelse-value (j = 0) [ 1.0 ] [ 0.75 ]
            if [crowd] of r >= (saturation-threshold * prox-factor) [ set need-reroute? true ]
            if [road-capacity-factor] of r < (0.25 * prox-factor)   [ set need-reroute? true ]
            let mid-p patch [mid-x] of r [mid-y] of r
            if mid-p != nobody [
              if [depth] of mid-p > (Hc * prox-factor)              [ set need-reroute? true ]
              if a4-traffic-management? [
                if [shared-congestion-signal] of mid-p > 2.0         [ set need-reroute? true ]
              ]
              if a1-civilian-signal? [
                if [civilian-flood-signal] of mid-p > 2.5            [ set need-reroute? true ]
              ]
            ]
          ]
        ]
      ]
      set j j + 1
    ]
    if a2-shelter-saturation? [
      if not need-reroute? [
        if shelter != -1 and shelter != -99 and shelter != nobody [
          let target-shelter intersection shelter
          if target-shelter != nobody [
            if [evacuee_count] of target-shelter > shelter-max-capacity [
              set need-reroute? true
            ]
          ]
        ]
      ]
    ]
    if need-reroute? [
      let goals nobody
      ifelse a2-shelter-saturation? [
        set goals cached-shelters with [ shelter_type = "Hor" and evacuee_count < shelter-max-capacity ]
        if not any? goals [ set goals cached-shelters with [ shelter_type = "Hor" ] ]
        if not any? goals [ set goals cached-shelters with [ evacuee_count < shelter-max-capacity ] ]
        if not any? goals [ set goals cached-shelters ]
      ] [
        set goals cached-shelters with [ shelter_type = "Hor" ]
        if not any? goals [ set goals cached-shelters ]
      ]
      if any? goals [
        let best-goal min-one-of goals [ distance myself ]
        if best-goal != nobody [
          let new-path Astar current_int best-goal (turtle-set best-goal)
          if not empty? new-path and new-path != path [
            set path new-path
            set shelter [who] of best-goal
            set cum-civilian-reroutes cum-civilian-reroutes + 1
            if a2-shelter-saturation? [
              if [evacuee_count] of best-goal > 0 [
                set cum-shelter-saturation-civilian-reroutes
                  cum-shelter-saturation-civilian-reroutes + 1 ] ]
            set moving? false
          ]
        ]
      ]
    ]
  ]
end

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; CANAUX D'ALERTE
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

to propagate-alert-differentiated

  if (comm-channel = "radio" or comm-channel = "combined") [
    if ticks >= radio-alert-delay-ticks and not radio-alert-fired? [
      set radio-alert-fired? true
      ask residents with [ alert-received? = false and evacuated? = false ] [
        if random-float 1 < 0.85 [
          set alert-received? true
          set alert-channel "radio"
          set cum-radio-alerts cum-radio-alerts + 1
          if decision = 2 [
            let fc [floodClass] of patch-here
            let p-switch 0.65
            if fc >= 2 [ set p-switch 0.80 ]
            if fc >= 3 [ set p-switch 0.92 ]
            if random-float 1 < p-switch [
              set decision 1  set color brown
              ;; Rayleigh radio : sigma réduit (réaction plus rapide qu'à l'état naturel)
              let sigma-sec ifelse-value (fc >= 3) [ 4 * 60 ] [ 9 * 60 ]
              let raw-time (rayleigh-sample sigma-sec) / tick_to_sec
              set miltime max list 1 (ticks + raw-time)
              set wait-start-tick -1
              set claimed-victims remove who claimed-victims
            ]
          ]
          if decision = 1 and miltime > ticks [
            set miltime max list ticks (miltime * 0.6) ]
        ]
      ]
      output-print (word "RADIO diffusee a " precision time-min 1
        " min - " cum-radio-alerts " residents alertes")
    ]
  ]

  if (comm-channel = "app" or comm-channel = "combined") [
    if ticks >= app-alert-delay-ticks and not app-alert-fired? [
      set app-alert-fired? true
      ask residents with [ alert-received? = false and evacuated? = false ] [
        let fc-local [floodClass] of patch-here
        let p-receive ifelse-value (fc-local <= 1) [ 0.90 ]
          [ ifelse-value (fc-local = 2) [ 0.70 ] [ 0.45 ] ]
        if random-float 1 < p-receive [
          set alert-received? true
          set alert-channel "app"
          set cum-app-alerts cum-app-alerts + 1
          if decision = 2 [
            let p-switch 0.80
            if fc-local >= 2 [ set p-switch 0.88 ]
            if fc-local >= 3 [ set p-switch 0.95 ]
            if random-float 1 < p-switch [
              set decision 1  set color brown
              ;; Rayleigh appli : sigma très court (alerte ciblée et immédiate)
              let sigma-sec ifelse-value (fc-local >= 3) [ 2 * 60 ] [ 6 * 60 ]
              let raw-time (rayleigh-sample sigma-sec) / tick_to_sec
              set miltime max list 1 (ticks + raw-time)
              set wait-start-tick -1
              set claimed-victims remove who claimed-victims
            ]
          ]
          if decision = 1 and miltime > ticks [
            set miltime max list ticks (miltime * 0.4) ]
        ]
      ]
      output-print (word "APP diffusee a " precision time-min 1
        " min - " cum-app-alerts " residents alertes")
    ]
  ]

  if (comm-channel = "word-of-mouth" or comm-channel = "combined") [
    ask residents with [ alert-received? = false and evacuated? = false ] [
      let me self
      let found? false
      if not found? [
        if any? firetrucks with [
          (phase = "to-victim" or phase = "rescuing") and distance me < word-of-mouth-radius
        ] [ set found? true ]
      ]
      if not found? [
        if any? residents with [ evacuated? = true and distance me < word-of-mouth-radius ]
        [ set found? true ]
      ]
      if not found? [
        if any? pedestrians with [ evacuated? = true and distance me < word-of-mouth-radius ]
        [ set found? true ]
      ]
      if found? [
        set alert-received? true
        set alert-channel "word-of-mouth"
        set cum-wom-alerts cum-wom-alerts + 1
        if decision = 2 [
          let fc [floodClass] of patch-here
          let p-evacuate 0.50
          if fc = 1 [ set p-evacuate 0.65 ]
          if fc = 2 [ set p-evacuate 0.80 ]
          if fc = 3 [ set p-evacuate 0.90 ]
          if fc = 4 [ set p-evacuate 0.97 ]
          set p-evacuate min list 1.0 (p-evacuate + 0.15)
          if random-float 1 < p-evacuate [
            set decision 1  set color brown
            ;; Rayleigh bouche-à-oreille : sigma intermédiaire (moins fiable que radio/appli)
            let sigma-sec ifelse-value (fc >= 3) [ 3 * 60 ] [ 7 * 60 ]
            let raw-time (rayleigh-sample sigma-sec) / tick_to_sec
            set miltime max list 1 (ticks + raw-time)
            set wait-start-tick -1
            set claimed-victims remove who claimed-victims
          ]
        ]
        if decision = 1 and miltime > ticks [
          set miltime max list ticks (miltime * 0.5) ]
      ]
    ]
    ask residents with [ alert-received? = true and evacuated? = false ] [
      let me self
      ask residents with [
        alert-received? = false and evacuated? = false and
        distance me < (word-of-mouth-radius * 0.5)
      ] [
        if random-float 1 < 0.40 [
          set alert-received? true
          set alert-channel "word-of-mouth"
          set cum-wom-alerts cum-wom-alerts + 1
          if decision = 2 [
            let fc [floodClass] of patch-here
            if random-float 1 < 0.50 [
              set decision 1  set color brown
              let sigma-sec 10 * 60
              let raw-time (rayleigh-sample sigma-sec) / tick_to_sec
              set miltime max list 1 (ticks + raw-time)
              set wait-start-tick -1
            ]
          ]
        ]
      ]
    ]
  ]

  let firetruck-sources firetrucks with [ phase = "to-victim" or phase = "rescuing" ]
  if any? firetruck-sources [
    ask residents with [ alert-received? = false and evacuated? = false ] [
      let me self
      let nearby-truck one-of firetruck-sources with [ distance me < alert-propagation-radius ]
      if nearby-truck != nobody [
        set alert-received? true
        set alert-channel "firetruck-proximity"
        set cum-firetruck-alerts cum-firetruck-alerts + 1
        if decision = 2 [
          let fc [floodClass] of patch-here
          let p-evacuate 0.75
          if fc >= 2 [ set p-evacuate 0.88 ]
          if fc >= 3 [ set p-evacuate 0.96 ]
          if random-float 1 < p-evacuate [
            set decision 1  set color brown
            ;; Rayleigh proximité camion : sigma très court (urgence perçue directement)
            let sigma-sec ifelse-value (fc >= 3) [ 2 * 60 ] [ 5 * 60 ]
            let raw-time (rayleigh-sample sigma-sec) / tick_to_sec
            set miltime max list 1 (ticks + raw-time)
            set wait-start-tick -1
            set claimed-victims remove who claimed-victims
          ]
        ]
        if decision = 1 and miltime > ticks [
          set miltime max list ticks (miltime * 0.45) ]
      ]
    ]
  ]
end

to update-resident-decisions
  ask residents with [ decision = 2 and evacuated? = false ] [
    let fc-now [floodClass] of patch-here
    let trigger? false
    if fc-now > prev-flood-class [ set trigger? true ]
    if not trigger? [
      if any? residents with [ evacuated? = true and distance myself < 3 ] [
        if random-float 1 < 0.30 [ set trigger? true ] ]
    ]
    if not trigger? [
      if any? pedestrians with [ evacuated? = true and distance myself < 3 ] [
        if random-float 1 < 0.30 [ set trigger? true ] ]
    ]
    if trigger? [
      let p-switch 0.60
      if fc-now = 2 [ set p-switch 0.75 ]
      if fc-now = 3 [ set p-switch 0.90 ]
      if fc-now = 4 [ set p-switch 0.98 ]
      if alert-received? [ set p-switch min list 1.0 (p-switch + 0.10) ]
      if random-float 1 < p-switch [
        set decision 1  set color brown
        set moving? false  set wait-start-tick -1
        let sigma-sec ifelse-value (fc-now >= 3) [ 2 * 60 ] [ 5 * 60 ]
        let raw-time (rayleigh-sample sigma-sec) / tick_to_sec
        set miltime max list 1 (ticks + raw-time)
        set claimed-victims remove who claimed-victims
      ]
    ]
    set prev-flood-class fc-now
  ]
end

to check-shelter-saturation-reroute
  ask firetrucks with [
    phase = "to-drop" and drop_post != nobody and current_int != nobody
  ] [
    let current-load [evacuee_count] of drop_post
    if current-load > shelter-max-capacity [
      let available-shelters cached-shelters with [
        [floodClass] of patch-here = 0 and evacuee_count < shelter-max-capacity ]
      if not any? available-shelters [
        set available-shelters cached-shelters with [ evacuee_count < shelter-max-capacity ] ]
      if any? available-shelters [
        let new-shelter min-one-of available-shelters [ distance myself ]
        if new-shelter != nobody and new-shelter != drop_post [
          let return-routes k-best-paths current_int new-shelter 5
          let return-route best-of-k-routes return-routes
          if not empty? return-route [
            set drop_post  new-shelter
            set path       return-route
            set alt-paths  return-routes
            set moving?    false
            set color      orange
            set shelter-saturation-reroutes shelter-saturation-reroutes + 1
            output-print (word "Camion " who " -> abri sature (" current-load
              ") redirige vers abri " [who] of new-shelter)
          ]
        ]
      ]
    ]
  ]
end

to check-access-time-trigger-reinforcements
  if reinforcement-activated [ stop ]
  if empty? access-times [ stop ]
  let current-mean mean access-times
  if current-mean > access-time-reinforce-threshold [
    set reinforcement-activated true
    set cum-access-triggered-reinforcements cum-access-triggered-reinforcements + 1
    output-print "========================================="
    output-print "RENFORTS AUTO (SEUIL TEMPS D ACCES)"
    output-print (word "Temps acces moyen : " precision current-mean 1 " min")
    output-print (word "Seuil            : " access-time-reinforce-threshold " min")
    output-print (word "Declenchement a  : " precision time-min 1 " min")
    output-print "========================================="
  ]
end

to update-accessibility-metrics
  if count roads = 0 [ stop ]
  let accessible-roads roads with [
    road-capacity-factor >= 0.3 and crowd < saturation-threshold ]
  set pct-network-accessible precision (100 * count accessible-roads / count roads) 1

  set isolated-victims-count 0
  ask residents with [ decision = 2 and not evacuated? ] [
    let my-pos self
    let reachable? false
    ask firestations [
      if not reachable? [
        let src min-one-of intersections [ distance myself ]
        let tgt min-one-of intersections [ distance my-pos ]
        if src != nobody and tgt != nobody [
          let route Astar src tgt (turtle-set tgt)
          if not empty? route [ set reachable? true ]
        ]
      ]
    ]
    if not reachable? [
      set isolated-victims-count isolated-victims-count + 1
      set color magenta ]
  ]

  ifelse not empty? access-times
    [ set mean-rescue-delay precision mean access-times 2 ]
    [ set mean-rescue-delay 0 ]

  let penalty-isolated ifelse-value (total-population > 0)
    [ 30 * isolated-victims-count / max list 1 total-population ] [ 0 ]
  let penalty-network  (100 - pct-network-accessible) * 0.3
  let penalty-delay    min list 30 (mean-rescue-delay * 1.5)
  let nb-shelters max list 1 count cached-shelters
  let nb-satures  count cached-shelters with [ evacuee_count > shelter-max-capacity ]
  let pct-satures 100 * nb-satures / nb-shelters
  let penalty-shelters pct-satures * 0.25
  let total-residents count residents
  let pct-alerted ifelse-value (total-residents > 0)
    [ 100 * count residents with [ alert-received? = true ] / total-residents ] [ 0 ]
  let comm-bonus min list 5 (pct-alerted * 0.05)
  set accessibility-index precision
    (max list 0 (100 - penalty-isolated - penalty-network
                     - penalty-delay   - penalty-shelters + comm-bonus)) 1
end

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; STATE MARKERS
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

to mark-evacuated
  if evacuated? = false [
    if is-pedestrian? self [ set cum_self_evacuated cum_self_evacuated + 1 ]
    if is-resident? self [
      if rescued-by-firefighters? = false [ set cum_self_evacuated cum_self_evacuated + 1 ] ]
    if is-car-driver? self [ set cum_self_evacuated cum_self_evacuated + 1 ]
    set evacuated? true  set moving? false  set color blue
    set ev_times lput ((ticks * tick_to_sec) / 60) ev_times
    if is-turtle? current_int [ ask current_int [ set evacuee_count evacuee_count + 1 ] ]
  ]
end

to mark-rescued
  if evacuated? = false [
    set cum_rescued cum_rescued + 1
    set cum-trucks-delivered cum-trucks-delivered + 1
    set evacuated? true  set moving? false
    set rescued-by-firefighters? true  set color blue
    set ev_times lput ((ticks * tick_to_sec) / 60) ev_times
    if is-turtle? current_int [ ask current_int [ set evacuee_count evacuee_count + 1 ] ]
    set claimed-victims remove who claimed-victims
    let mx xcor  let my ycor
    ask roads with [
      sqrt ((mid-x - mx) ^ 2 + (mid-y - my) ^ 2) < 3 and crowd > 0
    ] [ set crowd max list 0 (crowd - 1) ]
  ]
end

to setup-init-val
  set accessibility-index 100
  set mean-rescue-delay 0
  set isolated-victims-count 0
  set pct-network-accessible 100
end

to update-agent-colors
  ask residents  with [ evacuated? = true ] [
    set color blue
    ifelse [floodClass] of patch-here >= 1 [ hide-turtle ] [ show-turtle ]
  ]
  ask pedestrians with [ evacuated? = true ] [
    set color blue
    ifelse [floodClass] of patch-here >= 1 [ hide-turtle ] [ show-turtle ]
  ]
  ask residents with [ evacuated? = false and [floodClass] of patch-here >= 1 ] [
    ifelse alert-received? [
      if alert-channel = "radio"               [ set color cyan - 1  ]
      if alert-channel = "app"                 [ set color green - 1 ]
      if alert-channel = "word-of-mouth"       [ set color brown + 2 ]
      if alert-channel = "firetruck-proximity" [ set color orange    ]
      if alert-channel = "none" or alert-channel = 0 [ set color brown ]
    ] [ set color brown ]
    show-turtle
  ]
  ask pedestrians with [ evacuated? = false and [floodClass] of patch-here >= 1 ] [
    ifelse alert-received? [
      if alert-channel = "radio"               [ set color cyan - 1  ]
      if alert-channel = "app"                 [ set color green - 1 ]
      if alert-channel = "word-of-mouth"       [ set color brown + 2 ]
      if alert-channel = "firetruck-proximity" [ set color orange    ]
      if alert-channel = "none" or alert-channel = 0 [ set color brown ]
    ] [ set color brown ]
    show-turtle
  ]
  ask residents  with [ evacuated? = false and [floodClass] of patch-here = 0 ] [
    set color magenta  show-turtle ]
  ask pedestrians with [ evacuated? = false and [floodClass] of patch-here = 0 ] [
    set color magenta  show-turtle ]
end

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; GIS
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

to read-gis-files
  set shelter_locations       gis:load-dataset "shelter_locations.shp"
  set road_network            gis:load-dataset "road_network_2.shp"
  set population_distribution gis:load-dataset "population_distribution.shp"
  set cis_dataset             gis:load-dataset "cis_bezons.shp"
  set tsunami_sample          gis:load-dataset "sample.asc"
  set ecoles_dataset          gis:load-dataset "Ecole_ZIP.shp"
  set entreprises_dataset     gis:load-dataset "Entreprises_ZIP.shp"

  let world_envelope (gis:envelope-union-of
    (gis:envelope-of road_network)
    (gis:envelope-of shelter_locations)
    (gis:envelope-of population_distribution)
    (gis:envelope-of cis_dataset)
    (gis:envelope-of tsunami_sample))

  let netlogo_envelope (list (min-pxcor + 1) (max-pxcor - 1) (min-pycor + 1) (max-pycor - 1))
  gis:set-transformation world_envelope netlogo_envelope

  let world_width   item 1 world_envelope - item 0 world_envelope
  let world_height  item 3 world_envelope - item 2 world_envelope
  let netlogo_width  (max-pxcor - 1) - (min-pxcor + 1)
  let netlogo_height (max-pycor - 1) - (min-pycor + 1)
  set patch_to_meter max (list (world_width / netlogo_width) (world_height / netlogo_height))
  set tick_to_sec 60.0
  set fd_to_mps patch_to_meter / tick_to_sec
  set fd_to_kph fd_to_mps * 3.6


  ;; patch_to_meter : taille réelle d'une case (≈ 5 m selon l'emprise GIS)
  ;; tick_to_sec    : durée d'un tick = 60 s
  ;; fd_to_mps      : cases/tick → m/s  = patch_to_meter / tick_to_sec
  ;;   Ex. piéton à 1,2 m/s → speed = 1,2 / fd_to_mps = 1,2 × 60 / patch_to_meter
  ;;       Si patch_to_meter = 5 m → speed = 14,4 cases/tick
  ;; fd_to_kph      : cases/tick → km/h = fd_to_mps × 3,6
  ;;   Ex. camion à 30 km/h (vitesse dégradée, contexte de crise urbaine)
  ;;       → speed = 30 / fd_to_kph
  ;;       Si patch_to_meter = 5 m → speed ≈ 6,94 cases/tick
  set patch_to_meter max (list (world_width / netlogo_width) (world_height / netlogo_height))
  set tick_to_sec 60.0
  set fd_to_mps patch_to_meter / tick_to_sec
  set fd_to_kph fd_to_mps * 3.6
end

to load-network
  ask intersections [ die ]
  ask roads [ die ]
  foreach gis:feature-list-of road_network [ i ->
    let direction gis:property-value i "DIRECTION"
    foreach gis:vertex-lists-of i [ j ->
      let prev -1
      foreach j [ k ->
        if length (gis:location-of k) = 2 [
          let x item 0 gis:location-of k
          let y item 1 gis:location-of k
          let curr 0
          ifelse any? intersections with [xcor = x and ycor = y] [
            set curr [who] of one-of intersections with [xcor = x and ycor = y]
          ] [
            create-intersections 1 [
              set xcor x  set ycor y
              set shelter? false  set school? false  set workplace? false
              set shelter_type "None"  set size 0.1  set shape "square"
              set color white  set evacuee_count 0  set curr who
            ]
          ]
          if prev != -1 and prev != curr [
            ifelse direction = "two-way" [
              ask intersection prev [ create-road-to intersection curr ]
              ask intersection curr [ create-road-to intersection prev ]
            ] [
              if is-heading-right? ([towards intersection curr] of intersection prev) direction [
                ask intersection prev [ create-road-to intersection curr ]
              ]
              if is-heading-right? ([towards intersection prev] of intersection curr) direction [
                ask intersection curr [ create-road-to intersection prev ]
              ]
            ]
          ]
          set prev curr
        ]
      ]
    ]
  ]
  ask roads [
    set color black  set thickness 0.05
    set mid-x mean [xcor] of both-ends
    set mid-y mean [ycor] of both-ends
    set traffic 0  set crowd 0  set crowd-density 0
    set road-capacity-factor 1.0
  ]
  output-print "Network Loaded"
end

to-report is-heading-right? [link_heading direction]
  if direction = "north"   [ if abs(subtract-headings   0 link_heading) <= 90 [ report true ] ]
  if direction = "east"    [ if abs(subtract-headings  90 link_heading) <= 90 [ report true ] ]
  if direction = "south"   [ if abs(subtract-headings 180 link_heading) <= 90 [ report true ] ]
  if direction = "west"    [ if abs(subtract-headings 270 link_heading) <= 90 [ report true ] ]
  if direction = "two-way" [ report true ]
  report false
end

to load-shelters
  ask intersections [
    set shelter? false  set shelter_type "None"
    set color white  set size 0.1  set shape "square"  set evacuee_count 0
  ]
  foreach gis:feature-list-of shelter_locations [ i ->
    let curr_shelter_type gis:property-value i "TYPE"
    foreach gis:vertex-lists-of i [ j ->
      foreach j [ k ->
        if length (gis:location-of k) = 2 [
          let x item 0 gis:location-of k
          let y item 1 gis:location-of k
          ask min-one-of intersections [ distancexy x y ] [
            set shelter? true  set shape "circle"  set size 3  set color yellow
            ifelse curr_shelter_type = "ver"
              [ set shelter_type "Ver" ] [ set shelter_type "Hor" ]
          ]
        ]
      ]
    ]
  ]
  output-print "Shelters Loaded"
  set cached-shelters intersections with [ shelter? ]
end

to load-schools-workplaces
  ask intersections [ set school? false  set workplace? false ]
  let nb-ecoles-chargees 0
  let used-nodes-school []
  foreach gis:feature-list-of ecoles_dataset [ i ->
    let loc gis:location-of gis:centroid-of i
    if not empty? loc [
      let x item 0 loc  let y item 1 loc
      let candidate min-one-of intersections with [
        not member? self used-nodes-school ] [ distancexy x y ]
      if candidate != nobody [
        ask candidate [ set school? true  set shape "triangle"  set color yellow  set size 3 ]
        set used-nodes-school lput candidate used-nodes-school
        set nb-ecoles-chargees nb-ecoles-chargees + 1
      ]
    ]
  ]
  if nb-ecoles-chargees = 0 [
    let flood-ints intersections with [ [floodClass] of patch-here >= 1 and not shelter? ]
    if any? flood-ints [
      ask n-of (min list 5 count flood-ints) flood-ints [
        set school? true  set shape "triangle"  set color yellow  set size 3 ]
    ]
  ]
  let nb-entreprises-chargees 0
  let used-nodes-wp []
  foreach gis:feature-list-of entreprises_dataset [ i ->
    let loc gis:location-of gis:centroid-of i
    if not empty? loc [
      let x item 0 loc  let y item 1 loc
      let candidate min-one-of intersections with [
        not member? self used-nodes-wp ] [ distancexy x y ]
      if candidate != nobody [
        ask candidate [ set workplace? true  set shape "square"  set color orange  set size 1.5 ]
        set used-nodes-wp lput candidate used-nodes-wp
        set nb-entreprises-chargees nb-entreprises-chargees + 1
      ]
    ]
  ]
  if nb-entreprises-chargees = 0 [
    let flood-ints intersections with [
      [floodClass] of patch-here >= 1 and not shelter? and not school? ]
    if any? flood-ints [
      ask n-of (min list 8 count flood-ints) flood-ints [
        set workplace? true  set shape "square"  set color orange  set size 1.5 ]
    ]
  ]
  set cached-schools    intersections with [ school?    ]
  set cached-workplaces intersections with [ workplace? ]
  output-print (word "Ecoles : " count cached-schools " | Entreprises : " count cached-workplaces)
end

to load-firestations
  ask firestations [ die ]
  let station-counter 1
  foreach gis:feature-list-of cis_dataset [ i ->
    foreach gis:vertex-lists-of i [ j ->
      foreach j [ k ->
        if length (gis:location-of k) = 2 [
          let x item 0 gis:location-of k
          let y item 1 gis:location-of k
          let sid station-counter
          create-firestations 1 [
            set xcor x  set ycor y
            set shape "house"  set color red  set size 4  set id sid
          ]
          set station-counter station-counter + 1
        ]
      ]
    ]
  ]
  if count firestations < 3 [
    let candidate-shelters intersections with [
      shelter? = true and [floodClass] of patch-here = 0 and
      not any? firestations with [ distance myself < 5 ]
    ]
    if any? candidate-shelters [
      let n-needed 3 - count firestations
      let flood-p patches with [ floodClass > 0 ]
      let chosen nobody
      ifelse any? flood-p [
        set chosen min-n-of (min list n-needed count candidate-shelters)
          candidate-shelters [ min [distance myself] of flood-p ]
      ] [
        set chosen n-of (min list n-needed count candidate-shelters) candidate-shelters
      ]
      let station-data []
      ask chosen [
        set station-data lput (list xcor ycor station-counter) station-data
        set station-counter station-counter + 1
      ]
      foreach station-data [ entry ->
        let cx item 0 entry  let cy item 1 entry  let sid item 2 entry
        create-firestations 1 [
          set xcor cx  set ycor cy  set shape "house"
          set color orange  set size 4  set id sid
          set label (word "PT" (sid - 1))  set label-color black
        ]
      ]
    ]
  ]
  set temps-acces-caserne-1 0
  set temps-acces-caserne-2 0
  set temps-acces-caserne-3 0
  ;; Les casernes de renfort sont cachées jusqu'à l'activation
  ask firestations with [ color = orange ] [ hide-turtle ]
  output-print (word "Casernes : " count firestations)
end

to dispatch-firetrucks
  let available-stations firestations with [
    not any? firetrucks with [ distance myself < 0.2 ]
  ]
  if not any? available-stations [ stop ]
  let res-v residents   with [ decision = 2 and evacuated? = false and not member? who claimed-victims ]
  let ped-v pedestrians with [ decision = 2 and evacuated? = false and not member? who claimed-victims ]
  let victims (turtle-set res-v ped-v)
  if not any? victims [ stop ]
  let station one-of available-stations

  let victim nobody
  ifelse a3-priority-index? [
    ifelse accessibility-index < 50 and any? victims with [ color = magenta ] [
      set victim min-one-of (victims with [ color = magenta ]) [ distance station ]
      set cum-index-driven-prioritizations cum-index-driven-prioritizations + 1
      if ticks mod 30 = 0 [
        output-print (word "INDEX-DRIVEN dispatch : index=" accessibility-index
          " -> victime isolee #" [who] of victim) ]
    ] [
      ifelse accessibility-index < 70 and any? victims with [ [floodClass] of patch-here >= 3 ] [
        set victim min-one-of (victims with [ [floodClass] of patch-here >= 3 ]) [ distance station ]
        set cum-index-driven-prioritizations cum-index-driven-prioritizations + 1
      ] [
        set victim min-one-of victims [ distance station ]
      ]
    ]
  ] [
    set victim min-one-of victims [ distance station ]
  ]

  let src min-one-of intersections [ distance station ]
  let tgt min-one-of intersections [ distance victim ]
  if (src = nobody) or (tgt = nobody) [ stop ]
  let alternatives k-best-paths src tgt 5
  if empty? alternatives [ stop ]
  let chosen-route best-of-k-routes alternatives
  let sid [id] of station
  set claimed-victims lput ([who] of victim) claimed-victims
  create-firetrucks 1 [
    set color red  set shape "car"  set size 2.5
    set moving? false
    ;; Vitesse camion : max_speed_firefighters [km/h] / fd_to_kph [km/h par case/tick]
    ;; Valeur recommandée : 30 km/h (circulation dégradée en crise urbaine)
    ;; Cette vitesse de base est modulée à chaque tick par firetruck-depth-factor
    set speed (max_speed_firefighters / fd_to_kph)
    set capacity 3  set cargo []
    set current_int src  move-to src
    set home_post src  set firetruck-station-id sid
    set alt-paths alternatives  set current-route-idx 0
    set reroute-cooldown 0  set priority-mode? false
    set prev-path []  set alert-received? false  set alert-channel "none"
    let shelters cached-shelters with [ evacuee_count < shelter-max-capacity ]
    if not any? shelters [ set shelters cached-shelters ]
    if any? shelters [ set drop_post min-one-of shelters [ distance src ] ]
    if drop_post = nobody [ set drop_post src ]
    set phase "to-victim"  set rescue_time 45
    set target-resident victim  set target_int tgt
    set path chosen-route  set dispatch-tick ticks
  ]
end

to record-access-time [ sid elapsed-min ]
  set access-times lput elapsed-min access-times
  if sid = 1 [ set temps-acces-caserne-1 precision elapsed-min 2 ]
  if sid = 2 [ set temps-acces-caserne-2 precision elapsed-min 2 ]
  if sid = 3 [ set temps-acces-caserne-3 precision elapsed-min 2 ]
end

;; ================================================================
;; FACTEUR DE VITESSE DES CAMIONS SELON LA PROFONDEUR D'EAU
;; ================================================================
;; Seuils calibrés sur les pratiques opérationnelles en inondation :
;;   depth = 0 m    → facteur 1,00 — circulation normale à pleine vitesse
;;   depth ≤ 0,3 m  → facteur 1,00 — légère perturbation, pas d'impact significatif
;;   depth ≤ 0,5 m  → facteur 0,50 — perte de contrôle progressive (~50 % de la vitesse)
;;   depth ≤ 0,6 m  → facteur 0,20 — déplacement très difficile (~20 % de la vitesse)
;;   depth > 0,6 m  → facteur 0,05 — véhicule immobilisé ; les équipes poursuivent
;;                                    à pied avec équipements de sauvetage aquatique
;;                                    (facteur résiduel = continuité de mission)
to-report firetruck-depth-factor [ local-depth ]
  report ifelse-value (local-depth > 0.6) [ 0.05 ]
    [ ifelse-value (local-depth > 0.5) [ 0.20 ]
      [ ifelse-value (local-depth > 0.3) [ 0.50 ]
        [ 1.0 ] ] ]
end

to move-firetrucks
  ask firetrucks [
    if not is-list? cargo     [ set cargo [] ]
    if not is-list? alt-paths [ set alt-paths [] ]
    if (not is-number? capacity) or (capacity <= 0) [ set capacity 3 ]

    if target-resident = nobody [
      firetruck-assign-new-target
      if target-resident = nobody [ stop ]
    ]
    if [evacuated?] of target-resident = true [
      if target-resident != nobody [
        set claimed-victims remove ([who] of target-resident) claimed-victims ]
      set target-resident nobody
      firetruck-assign-new-target
      stop
    ]

    if phase = "to-victim" [
      if empty? path [
        if target-resident = nobody [ firetruck-assign-new-target  stop ]
        if distance target-resident > 0.6 [
          set heading towards target-resident
          let local-depth [depth] of patch-here
          let depth-factor firetruck-depth-factor local-depth
          let real-step (speed * depth-factor)
          if real-step < 0.01 [ set real-step 0.01 ]
          if real-step > distance target-resident [ set real-step distance target-resident ]
          fd real-step
          stop
        ]
        let elapsed precision (((ticks - dispatch-tick) * tick_to_sec) / 60) 2
        record-access-time firetruck-station-id elapsed
        set phase "rescuing"  set moving? false
        stop
      ]
      while [ (not empty? path) and (intersection item 0 path = current_int) ] [
        set path remove-item 0 path ]
      if empty? path [ stop ]
      if not moving? [
        set next_int intersection item 0 path
        set path remove-item 0 path
        if next_int != nobody [
          ifelse distance next_int > 0 [
            set heading towards next_int  set moving? true
          ] [ move-to next_int  set current_int next_int  set moving? false ]
        ]
      ]
      if moving? [
        if next_int != nobody [
          let nxt next_int
          let src-who [who] of current_int
          if [out-road-neighbor? nxt] of current_int [
            let r road src-who [who] of nxt
            if r != nobody [
              let cap [road-capacity-factor] of r
              if cap <= 0 [
                ifelse (a4-traffic-management? and firetruck-priority-enabled? and priority-mode?) [
                  let local-depth [depth] of patch-here
                  let depth-factor firetruck-depth-factor local-depth
                  let forced-step (speed * 0.20 * depth-factor)
                  if forced-step < 0.005 [ set forced-step 0.005 ]
                  if forced-step > distance next_int [ set forced-step distance next_int ]
                  fd forced-step
                  set cum-priority-passages cum-priority-passages + 1
                ] [ set moving? false  set reroute-cooldown 0  set path []  stop ]
              ]
            ]
          ]
        ]
        let local-depth [depth] of patch-here
        let depth-factor firetruck-depth-factor local-depth
        ;; Comptabilisation des réductions dès Hc = 0,3 m (seuil de gêne)
        if local-depth > 0.3 [ set cum-speed-reductions cum-speed-reductions + 1 ]
        let real-step (speed * depth-factor)
        if real-step < 0.01 [ set real-step 0.01 ]
        if next_int != nobody [
          if real-step > distance next_int [ set real-step distance next_int ]
          fd real-step
          if distance next_int < 0.05 [
            move-to next_int  set current_int next_int
            set moving? false  set color red ]
        ]
      ]
      stop
    ]

    if phase = "rescuing" [
      if rescue_time > 0 [ set rescue_time rescue_time - tick_to_sec  stop ]
      let v target-resident
      if v != nobody [
        if [evacuated?] of v = false [
          if not is-list? cargo [ set cargo [] ]
          set cargo lput v cargo
          ask v [
            set rescued-by-firefighters? true  set evacuated? true
            set moving? false  hide-turtle
            set claimed-victims remove who claimed-victims
          ]
        ]
      ]
      set rescue_time 45  set target-resident nobody
      if length cargo >= capacity [
        let src current_int
        let available-shelters cached-shelters with [
          [floodClass] of patch-here = 0 and evacuee_count < shelter-max-capacity ]
        if not any? available-shelters [
          set available-shelters cached-shelters with [ evacuee_count < shelter-max-capacity ] ]
        if not any? available-shelters [
          set available-shelters cached-shelters with [ [floodClass] of patch-here = 0 ] ]
        if not any? available-shelters [ set available-shelters cached-shelters ]
        let best-shelter ifelse-value (any? available-shelters)
          [ min-one-of available-shelters [ distance src ] ] [ drop_post ]
        if best-shelter != nobody [ set drop_post best-shelter ]
        let tgt drop_post
        if (src = nobody) or (tgt = nobody) [ stop ]
        let return-routes k-best-paths src tgt 5
        let return-route best-of-k-routes return-routes
        if empty? return-route [
          foreach cargo [ vv ->
            if is-turtle? vv [ ask vv [ show-turtle  mark-rescued ] ] ]
          set cargo []  firetruck-assign-new-target  stop
        ]
        set path return-route  set alt-paths return-routes
        set phase "to-drop"  set moving? false
        stop
      ]
      firetruck-assign-new-target
      stop
    ]

    if phase = "to-drop" [
      if empty? path [
        let drop drop_post
        foreach cargo [ vv ->
          if is-turtle? vv [
            if [evacuated?] of vv = false [
              ask vv [
                show-turtle
                if drop != nobody [ move-to drop  set current_int drop  set color blue ]
                mark-rescued
              ]
            ]
          ]
        ]
        set cargo []  set rescue_time 45  set target-resident nobody
        if home_post != nobody and home_post != current_int [
          let src current_int
          let return-routes k-best-paths src home_post 5
          let return-route best-of-k-routes return-routes
          if not empty? return-route [
            set path return-route  set alt-paths return-routes
            set phase "returning"  set color red  set moving? false
            stop
          ]
        ]
        firetruck-assign-new-target  stop
      ]
      while [ (not empty? path) and (intersection item 0 path = current_int) ] [
        set path remove-item 0 path ]
      if empty? path [ stop ]
      if not moving? [
        set next_int intersection item 0 path
        set path remove-item 0 path
        if next_int != nobody [
          ifelse distance next_int > 0 [
            set heading towards next_int  set moving? true
          ] [ move-to next_int  set current_int next_int  set moving? false ]
        ]
      ]
      if moving? [
        if next_int != nobody [
          let nxt next_int
          let src-who [who] of current_int
          if [out-road-neighbor? nxt] of current_int [
            let r road src-who [who] of nxt
            if r != nobody [
              let cap [road-capacity-factor] of r
              if cap <= 0 [
                ifelse (a4-traffic-management? and firetruck-priority-enabled? and priority-mode?) [
                  let local-depth [depth] of patch-here
                  let depth-factor firetruck-depth-factor local-depth
                  let forced-step (speed * 0.20 * depth-factor)
                  if forced-step < 0.005 [ set forced-step 0.005 ]
                  if forced-step > distance next_int [ set forced-step distance next_int ]
                  fd forced-step
                  set cum-priority-passages cum-priority-passages + 1
                ] [ set moving? false  set reroute-cooldown 0  set path []  stop ]
              ]
            ]
          ]
        ]
        let local-depth [depth] of patch-here
        let depth-factor firetruck-depth-factor local-depth
        let real-step (speed * depth-factor)
        if real-step < 0.01 [ set real-step 0.01 ]
        if next_int != nobody [
          if real-step > distance next_int [ set real-step distance next_int ]
          fd real-step
          if distance next_int < 0.05 [
            move-to next_int  set current_int next_int
            set moving? false  set color red ]
        ]
      ]
      stop
    ]

    if phase = "returning" [
      if empty? path [
        set phase "to-victim"  set color red
        set moving? false  set priority-mode? false
        firetruck-assign-new-target  stop
      ]
      while [ (not empty? path) and (intersection item 0 path = current_int) ] [
        set path remove-item 0 path ]
      if empty? path [
        set phase "to-victim"  set color red  set priority-mode? false
        firetruck-assign-new-target  stop
      ]
      if not moving? [
        set next_int intersection item 0 path
        set path remove-item 0 path
        if next_int != nobody [
          ifelse distance next_int > 0 [
            set heading towards next_int  set moving? true
          ] [ move-to next_int  set current_int next_int  set moving? false ]
        ]
      ]
      if moving? [
        if next_int != nobody [
          let nxt next_int
          let src-who [who] of current_int
          if [out-road-neighbor? nxt] of current_int [
            let r road src-who [who] of nxt
            if r != nobody [
              let cap [road-capacity-factor] of r
              if cap <= 0 [
                set moving? false  set reroute-cooldown 0  set path []  stop ]
            ]
          ]
        ]
        let local-depth [depth] of patch-here
        let depth-factor firetruck-depth-factor local-depth
        let real-step (speed * depth-factor)
        if real-step < 0.01 [ set real-step 0.01 ]
        if real-step > distance next_int [ set real-step distance next_int ]
        fd real-step
        if distance next_int < 0.05 [
          move-to next_int  set current_int next_int
          set moving? false
          if current_int = home_post [
            set phase "to-victim"  set color red
            set priority-mode? false
            firetruck-assign-new-target
          ]
        ]
      ]
      stop
    ]
  ]
end

to firetruck-assign-new-target
  if target-resident != nobody [
    set claimed-victims remove ([who] of target-resident) claimed-victims ]

  let res-base residents   with [ decision = 2 and evacuated? = false and not member? who claimed-victims ]
  let ped-base pedestrians with [ decision = 2 and evacuated? = false and not member? who claimed-victims ]
  let base-victims (turtle-set res-base ped-base)

  if not any? base-victims [
    let res-all residents   with [ decision = 2 and evacuated? = false ]
    let ped-all pedestrians with [ decision = 2 and evacuated? = false ]
    set base-victims (turtle-set res-all ped-all)
  ]
  if not any? base-victims [
    set target-resident nobody  set target_int nobody
    set path []  set alt-paths []  set moving? false  stop
  ]
  if current_int = nobody [
    set current_int min-one-of intersections [ distance myself ]
    if current_int = nobody [ stop ]
    move-to current_int
  ]

  let src current_int
  let n min (list 3 count base-victims)
  let pool nobody
  ifelse a3-priority-index? [
    ifelse accessibility-index < 50 and any? base-victims with [ color = magenta ] [
      let isolated-pool base-victims with [ color = magenta ]
      let n-isolated min list n count isolated-pool
      let n-other    max list 0 (n - n-isolated)
      let other-pool base-victims with [ color != magenta ]
      set pool (turtle-set
        (min-n-of n-isolated isolated-pool [ distance myself ])
        (ifelse-value (n-other > 0 and any? other-pool)
          [ min-n-of n-other other-pool [ distance myself ] ]
          [ no-turtles ]))
      set cum-index-driven-prioritizations cum-index-driven-prioritizations + 1
    ] [
      ifelse accessibility-index < 70 and
      any? base-victims with [ [floodClass] of patch-here >= 3 ] [
        let critical-pool base-victims with [ [floodClass] of patch-here >= 3 ]
        let n-crit min list n count critical-pool
        let n-norm max list 0 (n - n-crit)
        let normal-pool base-victims with [ [floodClass] of patch-here < 3 ]
        set pool (turtle-set
          (min-n-of n-crit critical-pool [ distance myself ])
          (ifelse-value (n-norm > 0 and any? normal-pool)
            [ min-n-of n-norm normal-pool [ distance myself ] ]
            [ no-turtles ]))
      ] [
        set pool min-n-of n base-victims [ distance myself ]
      ]
    ]
  ] [
    set pool min-n-of n base-victims [ distance myself ]
  ]

  let pool-list shuffle sort pool
  set target-resident nobody  set target_int nobody
  set path []  set alt-paths []  set moving? false

  foreach pool-list [ v ->
    if target-resident = nobody [
      let tgt min-one-of intersections [ distance v ]
      if tgt != nobody [
        let alternatives k-best-paths src tgt 5
        if not empty? alternatives [
          let chosen best-of-k-routes alternatives
          if not empty? chosen [
            set claimed-victims lput ([who] of v) claimed-victims
            set target-resident v  set target_int tgt
            set path chosen  set alt-paths alternatives
            set phase "to-victim"  set moving? false
            set dispatch-tick ticks
          ]
        ]
      ]
    ]
  ]
  if target-resident = nobody [
    set nb-camions-bloques nb-camions-bloques + 1
    set color red + 3
  ]
end

to continuous-reroute-firetrucks
  ask firetrucks with [
    (phase = "to-victim" or phase = "to-drop") and
    length path >= 2 and current_int != nobody and reroute-cooldown <= 0
  ] [
    if firetruck-detects-congestion? path [
      let dest ifelse-value (phase = "to-victim") [ target_int ] [ drop_post ]
      if dest != nobody [
        let new-alts k-best-paths current_int dest 5
        if not empty? new-alts [
          let new-best best-of-k-routes new-alts
          if not empty? new-best and new-best != path [
            let old-score route-score path
            let new-score route-score new-best
            let urgency-level 0
            if firetruck-detects-congestion? path [ set urgency-level urgency-level + 1 ]
            if target-resident != nobody [
              let victim-depth [depth] of patch
                (int [xcor] of target-resident)
                (int [ycor] of target-resident)
              if victim-depth > 0.5 [ set urgency-level urgency-level + 1 ]
              if victim-depth > 1.0 [ set urgency-level urgency-level + 1 ]
            ]
            let index-factor ifelse-value a3-priority-index? [
              ifelse-value (accessibility-index < 40) [ 0.80 ]
                [ ifelse-value (accessibility-index < 70) [ 0.90 ] [ 0.95 ] ]
            ] [ 0.95 ]
            let gain-threshold ifelse-value (urgency-level >= 2)
              [ index-factor * 0.90 ] [ index-factor ]
            if new-score < old-score * gain-threshold [
              set prev-path path
              broadcast-congestion-signal prev-path true
              civilian-react-to-truck-reroute prev-path
              broadcast-congestion-signal new-best false
              set path      new-best
              set alt-paths new-alts
              set cum-reroutes cum-reroutes + 1
              set color pink
              if a4-traffic-management? and firetruck-priority-enabled? and urgency-level >= 2 [
                set priority-mode? true
                set cum-priority-passages cum-priority-passages + 1
              ]
              let new-cooldown ifelse-value (urgency-level >= 3) [ 1 ]
                [ ifelse-value (urgency-level = 2) [ 2 ]
                  [ ifelse-value (urgency-level = 1) [ 4 ] [ 6 ] ] ]
              set reroute-cooldown new-cooldown
            ]
          ]
        ]
      ]
    ]
    if ticks mod reroute-refresh-interval = 0 [
      let dest ifelse-value (phase = "to-victim") [ target_int ] [ drop_post ]
      if dest != nobody [
        let fresh-alts k-best-paths current_int dest 5
        if not empty? fresh-alts [
          set alt-paths fresh-alts
          let current-score route-score path
          let best-fresh    best-of-k-routes fresh-alts
          let fresh-score   route-score best-fresh
          if fresh-score < current-score * 0.90 [
            set prev-path path
            broadcast-congestion-signal prev-path true
            civilian-react-to-truck-reroute prev-path
            set path best-fresh
            set cum-reroutes cum-reroutes + 1
            set color pink
            set reroute-cooldown 6
          ]
        ]
      ]
    ]
  ]
  ask firetrucks with [ reroute-cooldown > 0 ] [
    set reroute-cooldown reroute-cooldown - 1
    if reroute-cooldown = 0 [ set color red  set priority-mode? false ]
  ]
end

to setup-reinforcement-posts
  let temp-stations firestations with [ color = orange ]
  ifelse any? temp-stations [
    let renfort-posts []
    ask temp-stations [
      let nearest min-one-of intersections [ distance myself ]
      if nearest != nobody [ set renfort-posts lput nearest renfort-posts ]
    ]
    set reinforcement_posts turtle-set renfort-posts
  ] [
    let flood-patches patches with [ floodClass > 0 ]
    if not any? flood-patches [
      set reinforcement_posts (turtle-set n-of
        (min list 24 count intersections with [ shelter? ])
        intersections with [ shelter? ])
      stop
    ]
    let shelters intersections with [ shelter? ]
    if count shelters <= 24 [ set reinforcement_posts shelters  stop ]
    ask shelters [
      let d min [ distance myself ] of flood-patches
      set fscore d
    ]
    set reinforcement_posts (turtle-set min-n-of 24 shelters [ fscore ])
  ]
end

to dispatch-reinforcements
  if not reinforcement-activated [
    let main-trucks count firetrucks with [
      firetruck-station-id = 1 and phase = "to-victim" ]
    if time-min >= reinforcement-trigger-min and main-trucks >= 2 [
      set reinforcement-activated true
      output-print (word "RENFORTS AUTO-ACTIVES a " precision time-min 1 " min")
    ]
  ]
  if not reinforcement-activated [ stop ]
  if time-min < reinforcement_start_min [ stop ]
  if (ticks * tick_to_sec) mod reinforcement_interval_sec != 0 [ stop ]
  if reinforcement_posts = nobody or not any? reinforcement_posts [ stop ]

  let res-rv residents   with [ decision = 2 and evacuated? = false and not member? who claimed-victims ]
  let ped-rv pedestrians with [ decision = 2 and evacuated? = false and not member? who claimed-victims ]
  let victims (turtle-set res-rv ped-rv)
  if not any? victims [ stop ]

  let origins sort reinforcement_posts
  let k min list reinforcement_batch_size length origins
  (foreach (sublist origins 0 k) n-values k [ i -> i ] [ [orig i] ->
    if any? victims [
      let victim min-one-of victims [ distance orig ]
      let src orig
      let tgt min-one-of intersections [ distance victim ]
      if (src != nobody) and (tgt != nobody) [
        let alternatives k-best-paths src tgt 5
        let chosen best-of-k-routes alternatives
        if not empty? chosen [
          set claimed-victims lput ([who] of victim) claimed-victims
          let nearest-temp min-one-of firestations with [ color = orange ] [ distance src ]
          let renfort-sid ifelse-value (nearest-temp != nobody) [ [id] of nearest-temp ] [ 0 ]
          create-firetrucks 1 [
            set color red  set shape "car"  set size 2.5
            set moving? false
            set speed (max_speed_firefighters / fd_to_kph)
            set current_int src  move-to src
            set phase "to-victim"  set home_post src
            set firetruck-station-id renfort-sid
            set alt-paths alternatives  set current-route-idx 0
            set reroute-cooldown 0  set priority-mode? false
            set prev-path []  set alert-received? false  set alert-channel "none"
            let renfort-shelters cached-shelters with [ evacuee_count < shelter-max-capacity ]
            if not any? renfort-shelters [ set renfort-shelters cached-shelters ]
            if any? renfort-shelters [ set drop_post min-one-of renfort-shelters [ distance src ] ]
            if drop_post = nobody [ set drop_post src ]
            set rescue_time 45  set target-resident victim  set target_int tgt
            set path chosen  set capacity 3  set cargo []  set dispatch-tick ticks
          ]
        ]
      ]
      set victims victims with [ self != victim ]
    ]
  ])
end

to update-modal-choice
  ask car-drivers with [ not evacuated? ] [
    let local-depth [waterDepth] of patch-here
    if local-depth > 0.3 [
      set can-drive? false
      let my-path path  let my-int current_int
      let my-tin time_in_water  let my-mdp max_depth_agent
      let my-alert alert-received?  let my-channel alert-channel
      hatch-pedestrians 1 [
        set current_int my-int  set path my-path
        ;; Vitesse piéton : Ped_Speed [m/s] / fd_to_mps
        ;; Ex. : 1,2 m/s × 60 s / 5 m = 14,4 cases/tick (conditions normales)
        set speed (Ped_Speed / fd_to_mps)
        set evacuated? false
        set rescued-by-firefighters? false
        set time_in_water my-tin  set max_depth_agent my-mdp
        set moving? false  set decision 1
        set alert-received? my-alert  set alert-channel my-channel
        ifelse empty? path [ set shelter -1 ] [ set shelter last path ]
      ]
      die
    ]
  ]
end

to move-car-drivers
  ask car-drivers with [ not evacuated? ] [
    if [waterDepth] of patch-here > 0.3 [ stop ]
    if dest_int = nobody [ stop ]
    if current_int = dest_int [ mark-evacuated  stop ]
    if moving? = false and not empty? path [
      set next_int intersection item 0 path
      set path remove-item 0 path
      if next_int != nobody [
        ifelse distance next_int > 0 [
          set heading towards next_int  set moving? true
        ] [ set current_int next_int ]
      ]
    ]
    if moving? [
      let step speed
      if step < 0.01 [ set step 0.01 ]
      if next_int != nobody [
        if step > distance next_int [ set step distance next_int ]
        fd step
        if distance next_int < 0.005 [
          move-to next_int  set current_int next_int
          set moving? false  set time_in_water time_in_water + tick_to_sec
          if current_int = dest_int [ mark-evacuated ]
        ]
      ]
    ]
  ]
end

to setup-bus-routes
  ask buses [ die ]
  if num-buses <= 0 [ stop ]
  if not any? cached-shelters [ stop ]
  let collection-candidates intersections with [
    [floodClass] of patch-here >= 1 and not shelter?
    and any? residents with [ distance myself < 5 and decision = 2 ]
  ]
  if not any? collection-candidates [
    set collection-candidates intersections with [
      [floodClass] of patch-here >= 1 and not shelter? ] ]
  if not any? collection-candidates [ stop ]
  let n-bus min list num-buses count collection-candidates
  let chosen-starts n-of n-bus collection-candidates
  let bus-data []
  ask chosen-starts [
    let src self
    let nearest-shelter min-one-of cached-shelters [ distance src ]
    if nearest-shelter != nobody [
      let bus-path Astar src nearest-shelter (turtle-set nearest-shelter)
      if not empty? bus-path [
        set bus-data lput (list src nearest-shelter bus-path) bus-data ]
    ]
  ]
  foreach bus-data [ entry ->
    let src  item 0 entry  let tgt  item 1 entry  let bpath item 2 entry
    create-buses 1 [
      set current_int src  set dest_int tgt  set home_post src
      move-to src
      set path bpath  set phase "collecting"  set capacity 15
      set passengers-cargo []  set speed (30 / fd_to_kph)
      set color green  set shape "car"  set size 3
      set moving? false  set next_int nobody
      set alert-received? false  set alert-channel "none"
    ]
  ]
  output-print (word "Bus crees : " count buses)
end

to move-buses
  ask buses [
    if phase = "collecting" [
      if length passengers-cargo < capacity [
        let this-bus self
        ask residents with [ decision = 2 and not evacuated? and distance myself < 3 ] [
          if length ([passengers-cargo] of this-bus) < ([capacity] of this-bus) [
            ask this-bus [ set passengers-cargo lput myself passengers-cargo ]
            set evacuated? true  set moving? false  hide-turtle
          ]
        ]
      ]
      if length passengers-cargo >= capacity or
      not any? residents with [ decision = 2 and not evacuated? and distance myself < 10 ] [
        set phase "to-shelter"
        set path best-of-k-routes (k-best-paths current_int dest_int 3)
      ]
    ]
    if phase = "to-shelter" [
      if empty? path [
        foreach passengers-cargo [ p ->
          if is-turtle? p [
            ask p [ show-turtle  move-to [current_int] of myself  mark-rescued ] ]
        ]
        set passengers-cargo []
        let tgt home_post
        if tgt = nobody [ set tgt current_int ]
        set path best-of-k-routes (k-best-paths current_int tgt 3)
        set phase "collecting"  stop
      ]
      while [ (not empty? path) and (intersection item 0 path = current_int) ] [
        set path remove-item 0 path ]
      if empty? path [ stop ]
      if not moving? [
        set next_int intersection item 0 path
        set path remove-item 0 path
        if next_int != nobody [
          ifelse distance next_int > 0 [
            set heading towards next_int  set moving? true
          ] [ set current_int next_int  set moving? false ]
        ]
      ]
      if moving? [
        let step speed
        if step < 0.01 [ set step 0.01 ]
        if next_int != nobody [
          if step > distance next_int [ set step distance next_int ]
          fd step
          if distance next_int < 0.05 [
            move-to next_int  set current_int next_int  set moving? false ]
        ]
      ]
    ]
  ]
end

to trigger-what-if-scenario
  if scenario-type = "late-alert" [
    let delay-ticks (alert-delay-min * 60 / tick_to_sec)
    ask residents [ set miltime miltime + delay-ticks ]
    output-print (word "WHAT-IF : alerte retardee de " alert-delay-min " min.")
  ]
  if scenario-type = "road-closure" [
    let main-roads max-n-of 3 roads [ crowd ]
    ask main-roads [ set road-capacity-factor 0.0  set color red ]
    output-print "WHAT-IF : 3 routes principales bloquees."
  ]
  if scenario-type = "shelter-overflow" [
    ask cached-shelters [
      if evacuee_count > shelter-capacity-pct [
        set shelter? false  set color gray  set shape "x"
        output-print (word "Abri " who " sature - ferme.")
      ]
    ]
    set cached-shelters intersections with [ shelter? ]
  ]
  if scenario-type = "comm-failure" [
    ask firetrucks [ set alt-paths [] ]
    ask residents   [ set alert-received? false ]
    ask pedestrians [ set alert-received? false ]
    set alert-propagation-radius 0
    set radio-alert-fired? false  set app-alert-fired? false
    output-print "WHAT-IF : panne comm - tous canaux desactives."
  ]
  if scenario-type = "fast-flood" [
    ask patches with [ floodClass >= 1 ] [
      set waterDepth waterDepth * 1.5
      ifelse waterDepth < 0.5 [ set floodClass 1 ] [
      ifelse waterDepth < 1.0 [ set floodClass 2 ] [
      ifelse waterDepth < 2.0 [ set floodClass 3 ] [ set floodClass 4 ]]]
    ]
    recolor-flood-classes-singleband
    output-print "WHAT-IF : montee des eaux acceleree (+50%)."
  ]
end

to run-how-to-optimization
  output-print "HOW-TO : recherche configuration optimale..."
  let best-score 9999  let best-config []
  let dry-intersections intersections with [ [floodClass] of patch-here = 0 ]
  if not any? dry-intersections [ stop ]
  repeat 10 [
    let n-stations min list 3 count dry-intersections
    let candidate-stations n-of n-stations dry-intersections
    let victim-pool residents with [ decision = 2 ]
    if any? victim-pool [
      let score mean [ min [distance myself] of candidate-stations ] of victim-pool
      if score < best-score [
        set best-score score  set best-config sort candidate-stations
        ask candidate-stations [ set color cyan  set size 4 ]
      ]
    ]
  ]
  output-print (word "HOW-TO score : " precision best-score 2 " | Casernes : " best-config)
end

to activate-reinforcements
  ifelse reinforcement-activated [ output-print "Reinforcements already active." ] [
    set reinforcement-activated true  set simulation-paused? false
    ;; Affichage des casernes de renfort au moment de leur activation
    ask firestations with [ color = orange ] [ show-turtle ]
    output-print (word "REINFORCEMENTS ACTIVATED at " precision time-min 1 " min.")
  ]
end

to load-tsunami
  ask patches [
    set depths []  set depth 0  set max_depth 0
    set water-rise-rate 0  set predicted-depth 0
    set shared-congestion-signal 0  set civilian-flood-signal 0
  ]
  file-close-all

  ifelse file-exists? "details.txt" [
    file-open "details.txt"
    set tsunami_data_start file-read
    set tsunami_data_inc   file-read
    set tsunami_data_count file-read
    file-close
    let files n-values tsunami_data_count [ i -> i * tsunami_data_inc + tsunami_data_start ]
    set tsunami_max_depth 0  set tsunami_min_depth 9999
    foreach files [ t ->
      let asc-path (word t ".asc")
      ifelse file-exists? asc-path [
        let tsunami gis:load-dataset asc-path
        gis:apply-raster tsunami depth
        ask patches [
          if not ((depth <= 0) or (depth >= 0)) [ set depth 0 ]
          if depth > tsunami_max_depth [ set tsunami_max_depth depth ]
          if depth < tsunami_min_depth [ set tsunami_min_depth depth ]
          set depths lput depth depths
        ]
      ] [ output-print (word "Fichier manquant : " asc-path) ]
      ask patches [ set depth 0 ]
    ]
    output-print "Tsunami Data Loaded"
  ] [ output-print "details.txt introuvable dans le dossier du modele" ]
end


to setup-flood-zip100
  set zip100-raster tsunami_sample
  ask patches [ set waterDepth 0  set floodClass 0  set depth 0  set prev-depth 0 ]
  gis:apply-raster zip100-raster waterDepth
  ask patches [
    if not ((waterDepth <= 0) or (waterDepth >= 0)) [ set waterDepth 0 ] ]
  ;; floodClass reste à 0 et tout reste blanc au démarrage
  ;; L'inondation sera simulée progressivement dans go sur 60 minutes
  ask patches [ set floodClass 0  set pcolor white ]
  set flood-patches-cache patches with [ waterDepth > 0 ]
end

to recolor-flood-classes-singleband
  ask patches with [ floodClass = 0 ] [ set pcolor white ]
  ask patches with [ floodClass = 1 ] [ set pcolor rgb 195 232 251 ]
  ask patches with [ floodClass = 2 ] [ set pcolor rgb  82 167 237 ]
  ask patches with [ floodClass = 3 ] [ set pcolor rgb  19 140 206 ]
  ask patches with [ floodClass = 4 ] [ set pcolor rgb   8  48 107 ]
end

to load-population
  ask residents [ die ]  ask pedestrians [ die ]  ask parents [ die ]
  ask workers   [ die ]  ask relatives   [ die ]  ask car-drivers [ die ]
  foreach gis:feature-list-of population_distribution [ i ->
    foreach gis:vertex-lists-of i [ j ->
      foreach j [ k ->
        if length (gis:location-of k) = 2 [
          let x item 0 gis:location-of k
          let y item 1 gis:location-of k
          create-residents 1 [
            set xcor x  set ycor y
            set color brown  set shape "dot"  set size 2
            set moving? false  set reached? false
            set current_int nobody  set wait-start-tick -1
            set init_dest min-one-of intersections [ distance myself ]
            ;; Vitesse piéton : Ped_Speed [m/s] / fd_to_mps
            ;; Valeur recommandée : Ped_Speed = 1,2 m/s (marche normale)
            ;; Ex. si patch_to_meter = 5 m → speed = 1,2 × 60 / 5 = 14,4 cases/tick
            set speed (Ped_Speed / fd_to_mps)
            if speed < 0.001 [ set speed 0.001 ]
            set evacuated? false
            set rescued-by-firefighters? false
            set time_in_water 0  set max_depth_agent 0  set miltime 0
            set alert-received? false  set alert-channel "none"
            set prev-flood-class [floodClass] of patch-here
            make-decision
            if immediate_evacuation [ set miltime 0 ]
          ]
        ]
      ]
    ]
  ]
  ask residents [
    if not is-boolean? evacuated?               [ set evacuated? false ]
    if not is-boolean? rescued-by-firefighters? [ set rescued-by-firefighters? false ]
    if not is-boolean? alert-received?          [ set alert-received? false ]
    if alert-channel = 0                        [ set alert-channel "none" ]
  ]
  ask pedestrians [
    if not is-boolean? evacuated?               [ set evacuated? false ]
    if not is-boolean? rescued-by-firefighters? [ set rescued-by-firefighters? false ]
    if not is-boolean? alert-received?          [ set alert-received? false ]
    if alert-channel = 0                        [ set alert-channel "none" ]
  ]
  output-print "Population Loaded"
end

to load-civilian-flows
  let dry-ints intersections with [ [floodClass] of patch-here = 0 and not shelter? ]
  if any? cached-schools and any? dry-ints [
    repeat num-parents [
      let src one-of dry-ints  let dest one-of cached-schools
      if src != nobody and dest != nobody and src != dest [
        create-parents 1 [
          set color yellow  set shape "dot"  set size 3
          set speed (Ped_Speed / fd_to_mps)
          if speed < 0.001 [ set speed 0.001 ]
          set evacuated? false  set rescued-by-firefighters? false
          set alert-received? false  set alert-channel "none"
          set time_in_water 0  set max_depth_agent 0  set mission-done? false
          set current_int src  set dest_int dest  move-to src
          set path Astar src dest (turtle-set dest)
          set moving? false  set next_int nobody
        ]
      ]
    ]
  ]
  if any? cached-workplaces and any? cached-shelters [
    repeat num-workers [
      let src one-of cached-workplaces
      let dest min-one-of cached-shelters [ distance src ]
      if src != nobody and dest != nobody and src != dest [
        create-workers 1 [
          set color orange  set shape "dot"  set size 2
          set speed (Ped_Speed / fd_to_mps)
          if speed < 0.001 [ set speed 0.001 ]
          set evacuated? false  set rescued-by-firefighters? false
          set alert-received? false  set alert-channel "none"
          set time_in_water 0  set max_depth_agent 0  set mission-done? false
          set current_int src  set dest_int dest  move-to src
          set path Astar src dest (turtle-set dest)
          set moving? false  set next_int nobody
        ]
      ]
    ]
  ]
  if any? cached-workplaces and any? dry-ints [
    repeat num-relatives [
      let src one-of dry-ints  let dest one-of cached-workplaces
      if src != nobody and dest != nobody and src != dest [
        create-relatives 1 [
          set color pink  set shape "dot"  set size 2
          set speed (Ped_Speed / fd_to_mps)
          if speed < 0.001 [ set speed 0.001 ]
          set evacuated? false  set rescued-by-firefighters? false
          set alert-received? false  set alert-channel "none"
          set time_in_water 0  set max_depth_agent 0  set mission-done? false
          set current_int src  set dest_int dest  move-to src
          set path Astar src dest (turtle-set dest)
          set moving? false  set next_int nobody
        ]
      ]
    ]
  ]
  output-print (word "Parents: " count parents " | Travailleurs: " count workers
    " | Proches: " count relatives)
end

to move-civilian-flow
  if mission-done? [ stop ]
  if evacuated? [ stop ]
  if current_int = dest_int [
    set mission-done? true  set evacuated? true
    if is-parent?   self [ set cum-parents-arrived   cum-parents-arrived   + 1 ]
    if is-worker?   self [ set cum-workers-arrived   cum-workers-arrived   + 1 ]
    if is-relative? self [ set cum-relatives-arrived cum-relatives-arrived + 1 ]
    die  stop
  ]
  if moving? = false and not empty? path [
    set next_int intersection item 0 path
    set path remove-item 0 path
    if next_int != nobody [
      ifelse distance next_int > 0 [
        set heading towards next_int  set moving? true
      ] [ set current_int next_int ]
    ]
  ]
  if moving? [
    ;; Hc = seuil de gêne piéton (0,3 m par défaut)
    ;; Au-delà de 1,5 × Hc, risque d'immobilisation (5 %) représentant les difficultés
    ;; de déplacement liées à la présence d'eau (stress, obstacles, perte d'équilibre)
    if [depth] of patch-here > (Hc * 1.5) [
      if random-float 1 < 0.05 [ set moving? false  stop ] ]
    let step speed
    if step < 0.01 [ set step 0.01 ]
    if next_int != nobody [
      if step > distance next_int [ set step distance next_int ]
      fd step
      if distance next_int < 0.005 [
        move-to next_int  set current_int next_int
        set moving? false  set time_in_water time_in_water + tick_to_sec
      ]
    ]
  ]
end

to load-routes
  let origins find-origins
  ask turtles with [ member? self origins ] [
    let goals intersections with [ shelter? and shelter_type = "Hor" ]
    ifelse any? goals [
      set hor-path Astar self (min-one-of goals [ distance myself ]) goals
    ] [ set hor-path [] ]
  ]
  output-print "Routes Calculated"
end

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; LOAD 1/2/3
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

to load1
  ca  clear-all-plots
  ask patches [ set pcolor white ]
  set ev_times []
  set cum_rescued 0  set cum_self_evacuated 0
  set reinforcement_start_min 1
  set reinforcement_interval_sec 20
  set reinforcement_batch_size 24
  set last-tsunami-idx -1
  set access-times []
  set cum-reroutes 0  set cum-civilian-reroutes 0
  set cum-parents-arrived 0  set cum-workers-arrived 0  set cum-relatives-arrived 0
  set nb-camions-bloques 0  set pct-routes-inondees 0  set pct-routes-saturees 0
  set temps-acces-caserne-1 0  set temps-acces-caserne-2 0  set temps-acces-caserne-3 0
  set cum-congestion-events 0  set cum-trucks-delivered 0
  set saturation-threshold 3  set crowd-weight 1.0  set road-block-rate 10
  set num-parents 20  set num-workers 30  set num-relatives 15
  set num-buses 3  set num-car-drivers 50
  set immediate_evacuation false  set wait-time-min 5
  set alert-delay-min 0  set shelter-capacity-pct 50
  set accessibility-index 100  set mean-rescue-delay 0
  set isolated-victims-count 0  set pct-network-accessible 100
  set reinforcement-activated false  set reinforcement-trigger-min 5
  set reinforcement-alert-shown false  set simulation-paused? false
  set flood-lookahead 5  set flood-rise-threshold 0.05  set flood-update-interval 6
  set claimed-victims []  set road-usage-counts table:make
  set reroute-refresh-interval 12  set alert-propagation-radius 5
  set cum-truck-congestion-events 0  set cum-civil-congestion-events 0
  set shelter-max-capacity 50  set shelter-saturation-reroutes 0
  set cum-civil-reactions-to-truck-reroute 0
  set congestion-signal-decay 0.85
  set comm-channel "combined"
  set radio-alert-radius 99999  set radio-alert-delay-ticks 10  set radio-alert-fired? false
  set app-alert-radius 15  set app-alert-delay-ticks 5  set app-alert-fired? false
  set word-of-mouth-radius alert-propagation-radius
  set cum-radio-alerts 0  set cum-app-alerts 0  set cum-wom-alerts 0  set cum-firetruck-alerts 0
  set firetruck-priority-enabled? a4-traffic-management?
  set priority-crowd-reduction 0.6  set cum-priority-passages 0
  set base-truck-speed 0  set cum-speed-reductions 0
  set access-time-reinforce-threshold 8.0
  set access-time-check-interval 30
  set cum-access-triggered-reinforcements 0
  set cum-civilian-flood-signals 0
  set cum-shelter-saturation-civilian-reroutes 0
  set cum-index-driven-prioritizations 0
  set cum-traffic-saturation-managed 0

  set record-video?   false
  set video-filename  "simulation.mp4"

  output-print "============================================"
  output-print (word "CONFIG : "
    ifelse-value a1-civilian-signal?    ["A1-ON "]["A1-OFF "]
    ifelse-value a2-shelter-saturation? ["A2-ON "]["A2-OFF "]
    ifelse-value a3-priority-index?     ["A3-ON "]["A3-OFF "]
    ifelse-value a4-traffic-management? ["A4-ON "]["A4-OFF "])
  output-print (word "SCENARIO : " scenario-type)
  output-print "============================================"

  setup-init-val
  read-gis-files
  load-network  load-shelters  load-tsunami
  setup-flood-zip100  setup-reinforcement-posts
  reset-timer  reset-ticks
end

to load2
  load-population
  assign-decisions-behavioral
  load-schools-workplaces
  load-civilian-flows
  load-routes
  setup-bus-routes
  ask roads [ set crowd 0  set crowd-density 0 ]
  reset-ticks
  init-accessibility-plot
  init-evacuation-plot
end

to load3
  ask firestations [ die ]  ask firetrucks [ die ]
  load-firestations
  trigger-what-if-scenario
  output-print "READ (3/3) DONE!"
  beep
end

to init-accessibility-plot
  set-current-plot "Firefighter Accessibility"
  clear-plot
  set-plot-y-range 0 10
  set-current-plot-pen "Trucks Arrived"  plotxy 0 0
  set-current-plot-pen "Firefighter Rerouting"  plotxy 0 0
end

to update-accessibility-plot
  set-current-plot "Firefighter Accessibility"
  set-plot-y-range 0 (max list 1 (max list cum-trucks-delivered cum-reroutes))
  set-current-plot-pen "Trucks Arrived"
  set-plot-pen-mode 0  plotxy time-min cum-trucks-delivered
  set-current-plot-pen "Firefighter Rerouting"
  set-plot-pen-mode 0  plotxy time-min cum-reroutes
end

to init-evacuation-plot
  set-current-plot "Evacuation Progress"
  clear-plot
  set-plot-y-range 0 (max list 1 total-population)
  set-current-plot-pen "Safe"  plotxy 0 0
  set-current-plot-pen "Still Exposed"  plotxy 0 0
end

to update-evacuation-plot
  set-current-plot "Evacuation Progress"
  set-plot-y-range 0 (max list 1 total-population)
  set-current-plot-pen "Safe"
  set-plot-pen-mode 0  plotxy time-min safe-count
  set-current-plot-pen "Still Exposed"
  set-plot-pen-mode 0  plotxy time-min exposed-count
end

to force-waiters-to-evacuate
  let local-wait wait-time-min
  if local-wait < 5  [ set local-wait 5  ]
  if local-wait > 10 [ set local-wait 10 ]
  let wait-ticks (local-wait * 60 / tick_to_sec)
  ask residents with [
    decision = 2 and evacuated? = false and
    wait-start-tick >= 0 and (ticks - wait-start-tick) >= wait-ticks
  ] [
    set decision 1  set color brown  set reached? false
    set moving? false  set wait-start-tick -1
    set claimed-victims remove who claimed-victims
    if init_dest != nobody [
      ifelse distance init_dest > 0 [
        set heading towards init_dest  set moving? true
      ] [ set reached? true  set current_int init_dest  move-to init_dest ]
    ]
  ]
end

to auto-adjust-parameters
  if time-min < 5 [ set crowd-weight 1.0  stop ]
  ifelse a4-traffic-management? [
    let pct-sat (100 * count roads with [ crowd >= saturation-threshold ] / max list 1 count roads)
    ifelse pct-sat < 20 [ set crowd-weight 0.5 ]
    [ ifelse pct-sat < 50 [ set crowd-weight 2.0 ] [ set crowd-weight 5.0 ] ]
    set cum-traffic-saturation-managed cum-traffic-saturation-managed + 1
  ] [
    set crowd-weight 1.0
  ]
end

to start-recording
  set record-video? true
  vid:start-recorder
  output-print "Enregistrement demarre..."
end

to stop-recording
  vid:save-recording video-filename
  set record-video? false
  output-print (word "Video sauvegardee : " video-filename)
end


to cleanup-claimed-victims
  let clean-list []
  foreach claimed-victims [ v ->
    let agent turtle v
    if agent != nobody [
      if [evacuated?] of agent = false [
        set clean-list lput v clean-list ]
    ]
  ]
  set claimed-victims clean-list
end

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;; GO ;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

to go
  if simulation-paused? [ stop ]
  if time-min >= 60 [ stop ]

  let res-active  residents   with [ evacuated? = false ]
  let ped-active  pedestrians with [ evacuated? = false ]
  let active-agents (turtle-set res-active ped-active)
  let active-peds   ped-active

  let idx int(((ticks * tick_to_sec) - tsunami_data_start) / tsunami_data_inc)
  if idx < 0 [ set idx 0 ]
  if tsunami_data_count > 0 and idx >= tsunami_data_count [
    set idx tsunami_data_count - 1 ]
  let do-visual? (ticks mod 30 = 0)
  let progress min list 1.0 (time-min / 60)

  ;; Progression de l'inondation à chaque tick indépendamment des fichiers tsunami
  ask flood-patches-cache [
    let new-depth waterDepth * progress
    let raw-rise max list 0 (new-depth - depth)
    set water-rise-rate 0.7 * water-rise-rate + 0.3 * raw-rise
    set depth new-depth
    set predicted-depth min list waterDepth (depth + water-rise-rate * flood-lookahead)
    if depth > max_depth [ set max_depth depth ]

    ;; floodClass selon profondeur courante
    ifelse depth <= 0   [ set floodClass 0 ] [
    ifelse depth < 0.5  [ set floodClass 1 ] [
    ifelse depth < 1.0  [ set floodClass 2 ] [
    ifelse depth < 2.0  [ set floodClass 3 ] [ set floodClass 4 ]]]]

    ;; Coloration nuancée
    ifelse floodClass = 0 [ set pcolor white ] [
    ifelse depth >= 2.0 [
      if floodClass = 1 [ set pcolor rgb 155 192 211 ]
      if floodClass = 2 [ set pcolor rgb  42 127 197 ]
      if floodClass = 3 [ set pcolor rgb   0 100 166 ]
      if floodClass = 4 [ set pcolor rgb   0   8  67 ]
    ] [ ifelse depth >= 1.5 [
      if floodClass = 1 [ set pcolor rgb 165 202 221 ]
      if floodClass = 2 [ set pcolor rgb  52 137 207 ]
      if floodClass = 3 [ set pcolor rgb   5 110 176 ]
      if floodClass = 4 [ set pcolor rgb   2  18  77 ]
    ] [ ifelse depth >= 1.0 [
      if floodClass = 1 [ set pcolor rgb 175 212 231 ]
      if floodClass = 2 [ set pcolor rgb  62 147 217 ]
      if floodClass = 3 [ set pcolor rgb  10 120 186 ]
      if floodClass = 4 [ set pcolor rgb   4  28  87 ]
    ] [ ifelse depth >= 0.5 [
      if floodClass = 1 [ set pcolor rgb 185 222 241 ]
      if floodClass = 2 [ set pcolor rgb  72 157 227 ]
      if floodClass = 3 [ set pcolor rgb  14 130 196 ]
      if floodClass = 4 [ set pcolor rgb   6  38  97 ]
    ] [
      if floodClass = 1 [ set pcolor rgb 195 232 251 ]
      if floodClass = 2 [ set pcolor rgb  82 167 237 ]
      if floodClass = 3 [ set pcolor rgb  19 140 206 ]
      if floodClass = 4 [ set pcolor rgb   8  48 107 ]
    ]]]]]
  ]

  if ticks mod flood-update-interval = 0 [ update-water-rise-rates ]

  let wet-agents active-agents with [ [waterDepth] of patch-here >= Hc ]
  ask wet-agents [ set time_in_water time_in_water + tick_to_sec ]

  ask residents with [ moving? = false and evacuated? = false and miltime <= ticks ] [
    ifelse init_dest != nobody and distance init_dest > 0 [
      set heading towards init_dest  set moving? true
    ] [
      set moving? false  set reached? true
      set current_int init_dest
      if init_dest != nobody [ move-to init_dest ]
    ]
  ]
  ask residents with [ moving? = true ] [
    ifelse (distance init_dest < speed) [ fd distance init_dest ] [ fd speed ]
    if distance init_dest < 0.005 [
      move-to init_dest  set moving? false  set reached? true
      set current_int init_dest
    ]
  ]
  ask residents with [ reached? = true and evacuated? = false ] [
    let spd speed  let dcsn decision
    let tinw time_in_water  let tmax max_depth_agent
    let alrt alert-received?  let chan alert-channel
    if dcsn = 1 [
      ask current_int [
        hatch-pedestrians 1 [
          set size 2  set shape "dot"  set color orange
          set current_int myself  set speed spd
          set evacuated? false  set rescued-by-firefighters? false
          set moving? false  set decision 1
          set time_in_water tinw  set max_depth_agent tmax
          set alert-received? alrt  set alert-channel chan
          set path [hor-path] of myself
          ifelse empty? path [ set shelter -1 ] [ set shelter last path ]
          if shelter = -1 and [shelter_type] of current_int = "Hor" [ set shelter -99 ]
          if shelter = -99 [ mark-evacuated ]
        ]
      ]
      die
    ]
    if dcsn = 2 [
      set color gray  set moving? false
      if wait-start-tick = -1 [ set wait-start-tick ticks ]
    ]
  ]

  ask active-peds [
    if [who] of current_int = shelter or shelter = -99 [ mark-evacuated ] ]
  ask active-peds with [ moving? = false and not empty? path ] [
    set next_int intersection item 0 path
    set path remove-item 0 path
    ifelse next_int != nobody and distance next_int > 0 [
      set heading towards next_int  set moving? true
    ] [ set moving? false ]
  ]
  ask active-peds with [ moving? = true ] [
    ;; Hc = seuil de gêne piéton (0,3 m par défaut)
    ;; Au-delà de 1,5 × Hc : risque d'immobilisation et refus d'évacuation
    if [depth] of patch-here > (Hc * 1.5) [
      if random-float 1 < 0.05 [ set moving? false  set decision 2  stop ] ]
    ifelse speed > distance next_int [ fd distance next_int ] [ fd speed ]
    if distance next_int < 0.005 [
      set moving? false  set current_int next_int
      if [who] of current_int = shelter [ mark-evacuated ]
    ]
  ]

  ask parents   [ move-civilian-flow ]
  ask workers   [ move-civilian-flow ]
  ask relatives [ move-civilian-flow ]

  if ticks mod 5 = 0 [ update-modal-choice ]
  if ticks mod 5 = 0 [ update-road-usage-counts ]
  move-car-drivers
  if count buses > 0 [ move-buses ]

  if ticks mod 60 = 0 [ force-waiters-to-evacuate ]
  if ticks mod 10 = 0 [ update-resident-decisions ]
  if ticks mod 5  = 0 [ propagate-alert-differentiated ]
  if ticks mod 5  = 0 [ civilians-broadcast-flood-signals ]
  if ticks mod 3  = 0 [ decay-civilian-flood-signals ]

  update-crowd

  if ticks mod 30 = 0 [ update-road-obstructions ]
  if ticks mod 6  = 0 [ update-agent-colors ]
  if ticks mod 20 = 0 [ update-road-status ]
  if ticks mod 10 = 0 [ reroute-pedestrians ]
  if ticks mod 3  = 0 [ decay-congestion-signals ]

  if ticks mod 12 = 0 [
    if count roads with [
      crowd >= saturation-threshold and road-capacity-factor >= 0.3 ] > 0 [
      set cum-congestion-events cum-congestion-events + 1 ]
  ]
  if ticks mod 60 = 0 [ auto-adjust-parameters ]

  if count firetrucks > 0 [ continuous-reroute-firetrucks ]
  if ticks mod 15 = 0 [ check-shelter-saturation-reroute ]
  if ticks mod access-time-check-interval = 0 [ check-access-time-trigger-reinforcements ]
  if ticks mod 30 = 0 [ cleanup-claimed-victims ]

  if not reinforcement-activated and not reinforcement-alert-shown [
    if time-min >= reinforcement-trigger-min [
      set reinforcement-alert-shown true  set simulation-paused? true
      output-print "========================================="
      output-print "ALERT : Main fire station overwhelmed !"
      output-print (word "Time : " precision time-min 1 " min")
      output-print ">>> Click Activate Reinforcements then GO."
      output-print "========================================="
      stop
    ]
  ]

  if ticks mod 30 = 0 [ dispatch-reinforcements ]
  if ticks mod 15 = 0 [ dispatch-firetrucks ]
  if count firetrucks > 0 [ move-firetrucks ]
  if ticks mod 12 = 0 [ update-accessibility-metrics ]
  if ticks mod 12 = 0 [ update-evacuation-plot ]
  if ticks mod 60 = 0 [ update-accessibility-plot ]

  if record-video? [ vid:record-view ]
  tick
end

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;; REPORTERS ;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

to-report total-population
  report count residents + count pedestrians
end

to-report time-min
  report (ticks * tick_to_sec) / 60
end

to-report rescued-count
  report count residents  with [ rescued-by-firefighters? = true ] +
         count pedestrians with [ rescued-by-firefighters? = true ]
end

to-report self-evacuated-count
  report count residents  with [ evacuated? = true and rescued-by-firefighters? = false ] +
         count pedestrians with [ evacuated? = true and rescued-by-firefighters? = false ]
end

to-report non-evacuated-count
  report count residents  with [ evacuated? = false ] +
         count pedestrians with [ evacuated? = false ]
end

to-report per-rescued
  if total-population = 0 [ report 0 ]
  report 100 * rescued-count / total-population
end

to-report per-non-evacuated
  if total-population = 0 [ report 0 ]
  report 100 * non-evacuated-count / total-population
end

to-report mean-ev-time
  if empty? ev_times [ report 0 ]
  report mean ev_times
end

to-report median-ev-time
  if empty? ev_times [ report 0 ]
  let s sort ev_times
  let n length s
  if n mod 2 = 1 [ report item (n / 2) s ]
  report (item (n / 2 - 1) s + item (n / 2) s) / 2
end

to-report mean-access-time
  if empty? access-times [ report 0 ]
  report precision (mean access-times) 2
end

to-report pct-saturated-roads
  if count roads = 0 [ report 0 ]
  report precision
    (100 * count roads with [ crowd >= saturation-threshold ] / count roads) 1
end

to-report active-flow-agents
  report count parents   with [ not mission-done? ] +
         count workers   with [ not mission-done? ] +
         count relatives with [ not mission-done? ]
end

to-report blocking-residents-count
  report count turtles with [
    (is-parent? self or is-worker? self or is-relative? self) and
    not mission-done? and [floodClass] of patch-here >= 1
  ]
end

to-report pct-isolated-victims
  if total-population = 0 [ report 0 ]
  report precision (100 * isolated-victims-count / total-population) 1
end

to-report firetruck-reroute-rate
  if count firetrucks = 0 [ report 0 ]
  report precision (cum-reroutes / max list 1 count firetrucks) 2
end

to-report exposed-count
  report count residents  with [ evacuated? = false and [floodClass] of patch-here >= 1 ] +
         count pedestrians with [ evacuated? = false and [floodClass] of patch-here >= 1 ]
end

to-report pct-exposed
  if total-population = 0 [ report 0 ]
  report precision (100 * exposed-count / total-population) 1
end

to-report safe-count
  report count residents  with [ evacuated? = true ] +
         count pedestrians with [ evacuated? = true ]
end

to-report pct-safe
  if total-population = 0 [ report 0 ]
  report precision (100 * safe-count / total-population) 1
end

to-report still-in-danger-count
  report count residents  with [ evacuated? = false ] +
         count pedestrians with [ evacuated? = false ]
end

to-report pct-rising-patches
  if not is-agentset? flood-patches-cache [ report 0 ]
  if count flood-patches-cache = 0 [ report 0 ]
  report precision
    (100 * count flood-patches-cache with [
      water-rise-rate > flood-rise-threshold ] / count flood-patches-cache) 1
end

to-report max-rise-rate
  if not is-agentset? flood-patches-cache [ report 0 ]
  if count flood-patches-cache = 0 [ report 0 ]
  let rates [water-rise-rate] of flood-patches-cache
  if empty? rates [ report 0 ]
  report precision (max rates) 4
end

to-report claimed-victims-count
  report length claimed-victims
end

to-report alerted-residents-count
  report count residents with [ alert-received? = true ]
end

to-report civilian-reroute-count
  report cum-civilian-reroutes
end

to-report pct-truck-congestion
  let total max list 1 (cum-truck-congestion-events + cum-civil-congestion-events)
  report precision (100 * cum-truck-congestion-events / total) 1
end

to-report pct-civil-congestion
  let total max list 1 (cum-truck-congestion-events + cum-civil-congestion-events)
  report precision (100 * cum-civil-congestion-events / total) 1
end

to-report shelter-saturation-count
  report count cached-shelters with [ evacuee_count > shelter-max-capacity ]
end

to-report shelter-saturation-reroute-count
  report shelter-saturation-reroutes
end

to-report civil-reactions-to-reroute-count
  report cum-civil-reactions-to-truck-reroute
end

to-report pct-congestion-signal-active
  if count patches = 0 [ report 0 ]
  report precision
    (100 * count patches with [ shared-congestion-signal > 0.5 ] / count patches) 1
end

to-report pct-alerted-by-radio
  let total max list 1 (cum-radio-alerts + cum-app-alerts + cum-wom-alerts + cum-firetruck-alerts)
  report precision (100 * cum-radio-alerts / total) 1
end

to-report pct-alerted-by-app
  let total max list 1 (cum-radio-alerts + cum-app-alerts + cum-wom-alerts + cum-firetruck-alerts)
  report precision (100 * cum-app-alerts / total) 1
end

to-report pct-alerted-by-wom
  let total max list 1 (cum-radio-alerts + cum-app-alerts + cum-wom-alerts + cum-firetruck-alerts)
  report precision (100 * cum-wom-alerts / total) 1
end

to-report pct-alerted-by-firetruck
  let total max list 1 (cum-radio-alerts + cum-app-alerts + cum-wom-alerts + cum-firetruck-alerts)
  report precision (100 * cum-firetruck-alerts / total) 1
end

to-report total-alerted-count
  report cum-radio-alerts + cum-app-alerts + cum-wom-alerts + cum-firetruck-alerts
end

to-report priority-passage-count
  report cum-priority-passages
end

to-report pct-trucks-in-priority-mode
  if count firetrucks = 0 [ report 0 ]
  report precision
    (100 * count firetrucks with [ priority-mode? = true ] / count firetrucks) 1
end

to-report speed-reduction-count
  report cum-speed-reductions
end

to-report mean-truck-depth
  if count firetrucks = 0 [ report 0 ]
  let depths-list [depth] of patches with [ any? firetrucks-here ]
  if empty? depths-list [ report 0 ]
  report precision mean depths-list 3
end

to-report access-triggered-reinforcements-count
  report cum-access-triggered-reinforcements
end

to-report access-time-vs-threshold
  report precision (mean-access-time - access-time-reinforce-threshold) 2
end

to-report pct-civilian-signal-active
  if count patches = 0 [ report 0 ]
  report precision
    (100 * count patches with [ civilian-flood-signal > 0.5 ] / count patches) 1
end

to-report civilian-flood-signal-count
  report cum-civilian-flood-signals
end

to-report shelter-saturation-civilian-reroute-count
  report cum-shelter-saturation-civilian-reroutes
end

to-report pct-shelters-saturated
  let nb max list 1 count cached-shelters
  report precision
    (100 * count cached-shelters with [ evacuee_count > shelter-max-capacity ] / nb) 1
end

to-report index-driven-prioritization-count
  report cum-index-driven-prioritizations
end

to-report current-accessibility-index
  report accessibility-index
end

to-report traffic-saturation-managed-count
  report cum-traffic-saturation-managed
end

to-report active-config-label
  report (word
    ifelse-value a1-civilian-signal?    ["A1 "][""]
    ifelse-value a2-shelter-saturation? ["A2 "][""]
    ifelse-value a3-priority-index?     ["A3 "][""]
    ifelse-value a4-traffic-management? ["A4 "][""]
    "| " scenario-type)
end

to-report mean-exposure-time
  let exposed (turtle-set
    residents   with [ evacuated? = false ]
    pedestrians with [ evacuated? = false ])
  if not any? exposed [ report 0 ]
  report precision (mean [time_in_water] of exposed) 1
end

to-report max-exposure-time
  let exposed (turtle-set
    residents   with [ evacuated? = false ]
    pedestrians with [ evacuated? = false ])
  if not any? exposed [ report 0 ]
  report precision (max [time_in_water] of exposed) 1
end

to-report count-agents-over-Tc
  report count residents  with [ evacuated? = false and time_in_water > Tc ] +
         count pedestrians with [ evacuated? = false and time_in_water > Tc ]
end

to-report pct-agents-over-Tc
  let exposed exposed-count
  if exposed = 0 [ report 0 ]
  report precision (100 * count-agents-over-Tc / exposed) 1
end

to-report total-cumulative-exposure-min
  let all-agents (turtle-set residents pedestrians)
  if not any? all-agents [ report 0 ]
  report precision (sum [time_in_water] of all-agents / 60) 1
end

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; PARETO MULTI-OBJECTIVE SCORES
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

to-report rescue-score
  let score-delay ifelse-value (mean-access-time > 0)
    [ max list 0 (100 - (mean-access-time * 10)) ] [ 100 ]
  let score-isolated ifelse-value (total-population > 0)
    [ max list 0 (100 - (100 * isolated-victims-count / total-population)) ] [ 100 ]
  let score-blocked ifelse-value (count firetrucks > 0)
    [ max list 0 (100 - (nb-camions-bloques * 10)) ] [ 100 ]
  report precision ((score-delay * 0.50) + (score-isolated * 0.30) + (score-blocked * 0.20)) 1
end

to-report civil-score
  let score-evac pct-safe
  let score-time ifelse-value (mean-ev-time > 0)
    [ max list 0 (100 - (mean-ev-time * 2)) ] [ 100 ]
  let score-network pct-network-accessible
  report precision ((score-evac * 0.50) + (score-time * 0.25) + (score-network * 0.25)) 1
end
@#$#@#$#@
GRAPHICS-WINDOW
245
26
856
758
-1
-1
3.0
1
10
1
1
1
0
0
0
1
-100
100
-120
120
0
0
1
ticks
30.0

BUTTON
1129
30
1200
63
GO
go
T
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

MONITOR
865
72
933
117
Time (min)
time-min
2
1
11

INPUTBOX
13
137
70
197
Hc
2.5
1
0
Number

BUTTON
886
29
952
62
READ (1/2)
load1\noutput-print \"READ (1/2) DONE!\"\nbeep
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

TEXTBOX
12
114
229
142
Water depth and exposure duration (m&s)
10
0.0
1

TEXTBOX
15
320
195
338
Evacuation decision-making delay
11
0.0
1

TEXTBOX
14
208
111
238
Pedestrian walking speed (m/s)
10
0.0
1

INPUTBOX
12
246
82
306
Ped_Speed
1.22
1
0
Number

BUTTON
965
30
1035
63
READ (2/3)
load2\noutput-print \"READ (2/3) DONE!\"\nbeep
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

INPUTBOX
111
247
229
307
max_speed_firefighters
30.0
1
0
Number

BUTTON
1047
30
1117
63
READ (3/3)
load3\noutput-print \"READ (3/3) DONE!\"\nbeep
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

TEXTBOX
122
209
231
232
Vehicle speed (km/h)
10
0.0
1

INPUTBOX
43
342
114
402
Rtau1
10.0
1
0
Number

BUTTON
9
23
110
56
Trigger What-If
trigger-what-if-scenario
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
0

BUTTON
118
24
233
57
Run How-To
run-how-to-optimization
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

MONITOR
1183
74
1317
119
Saturated Roads (%)
pct-routes-saturees
2
1
11

MONITOR
1062
182
1177
227
Mean Access Time
mean-access-time
17
1
11

PLOT
866
391
1316
565
Firefighter Accessibility
Time (min)
Cumul
0.0
70.0
0.0
10.0
true
true
"" ""
PENS
"Trucks Arrived" 1.0 0 -14439633 true "" "plotxy time-min count evac-agents with [ rescued-by-firefighters? = true ]"
"Firefighter Rerouting" 1.0 0 -2064490 true "" "plotxy time-min cum-reroutes"

MONITOR
947
73
1062
118
Firetrucks Rerouting
cum-reroutes
0
1
11

MONITOR
948
128
1063
173
Flooded Roads (%)
pct-routes-inondees
2
1
11

MONITOR
1156
130
1216
175
Safe
safe-count
17
1
11

MONITOR
1072
129
1148
174
Still Exposed
total-population - safe-count
17
1
11

MONITOR
1184
183
1317
228
Accessibility Index
accessibility-index
17
1
11

MONITOR
1224
130
1317
175
Isolated Victims
isolated-victims-count
17
1
11

PLOT
865
573
1315
757
Evacuation Progress
Time (min)
Value
0.0
70.0
0.0
10.0
true
true
"" ""
PENS
"Safe" 1.0 0 -14835848 true "" "plotxy time-min safe-count"
"Still Exposed" 1.0 0 -6459832 true "" "plotxy time-min exposed-count"

CHOOSER
14
416
106
461
Scenario-type
Scenario-type
"none" "fast-flood" "comm-failure"
0

BUTTON
10
67
102
100
Activer Renforts
activate-reinforcements
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

MONITOR
110
66
234
111
Reinforcement Status
reinforcement-activated
17
1
11

MONITOR
1071
238
1189
279
% active rising zones
pct-rising-patches
2
1
10

MONITOR
1186
288
1316
329
Max rise rate (m/tick)
max-rise-rate
4
1
10

SWITCH
13
471
167
504
a1-civilian-signal?
a1-civilian-signal?
1
1
-1000

SWITCH
12
515
167
548
a2-shelter-saturation?
a2-shelter-saturation?
1
1
-1000

SWITCH
11
559
167
592
a3-priority-index?
a3-priority-index?
1
1
-1000

SWITCH
10
604
167
637
a4-traffic-management?
a4-traffic-management?
1
1
-1000

MONITOR
10
650
168
695
Active Config
(word \n  ifelse-value a1-civilian-signal? [\"A1 \"][\"\"] \n  ifelse-value a2-shelter-saturation? [\"A2 \"][\"\"]\n  ifelse-value a3-priority-index? [\"A3 \"][\"\"]\n  ifelse-value a4-traffic-management? [\"A4 \"][\"\"]\n  \"| \" scenario-type)
17
1
11

BUTTON
1208
30
1295
63
 Reset Config
reset-config
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

MONITOR
947
181
1052
226
Rescued by FF
rescued-count
17
1
11

MONITOR
947
237
1067
278
Network Access (%)
pct-network-accessible
2
1
10

MONITOR
1071
73
1173
118
Civilian Reroutes
civilian-reroute-count
17
1
11

SLIDER
81
136
233
169
Tc
Tc
60
3600
1800.0
60
1
NIL
HORIZONTAL

MONITOR
1192
238
1317
279
Exposition moy. (sec)
mean-exposure-time
1
1
10

MONITOR
949
287
1066
332
Exposition max (sec)
max-exposure-time
1
1
11

MONITOR
1075
287
1180
332
% agents > Tc
pct-agents-over-Tc
2
1
11

MONITOR
948
340
1071
381
Exposition cum. (min)
total-cumulative-exposure-min
1
1
10

MONITOR
1194
338
1316
383
Rescue Score (%)
rescue-score
2
1
11

MONITOR
1078
340
1182
381
Civil Score (%)
civil-score
2
1
10

BUTTON
1324
74
1397
107
Record
start-recording
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
1325
119
1397
152
Stop & Save
stop-recording
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

@#$#@#$#@
@#$#@#$#@
default
true
0
Polygon -7500403 true true 150 5 40 250 150 205 260 250

airplane
true
0
Polygon -7500403 true true 150 0 135 15 120 60 120 105 15 165 15 195 120 180 135 240 105 270 120 285 150 270 180 285 210 270 165 240 180 180 285 195 285 165 180 105 180 60 165 15

arrow
true
0
Polygon -7500403 true true 150 0 0 150 105 150 105 293 195 293 195 150 300 150

box
false
0
Polygon -7500403 true true 150 285 285 225 285 75 150 135
Polygon -7500403 true true 150 135 15 75 150 15 285 75
Polygon -7500403 true true 15 75 15 225 150 285 150 135
Line -16777216 false 150 285 150 135
Line -16777216 false 150 135 15 75
Line -16777216 false 150 135 285 75

bug
true
0
Circle -7500403 true true 96 182 108
Circle -7500403 true true 110 127 80
Circle -7500403 true true 110 75 80
Line -7500403 true 150 100 80 30
Line -7500403 true 150 100 220 30

butterfly
true
0
Polygon -7500403 true true 150 165 209 199 225 225 225 255 195 270 165 255 150 240
Polygon -7500403 true true 150 165 89 198 75 225 75 255 105 270 135 255 150 240
Polygon -7500403 true true 139 148 100 105 55 90 25 90 10 105 10 135 25 180 40 195 85 194 139 163
Polygon -7500403 true true 162 150 200 105 245 90 275 90 290 105 290 135 275 180 260 195 215 195 162 165
Polygon -16777216 true false 150 255 135 225 120 150 135 120 150 105 165 120 180 150 165 225
Circle -16777216 true false 135 90 30
Line -16777216 false 150 105 195 60
Line -16777216 false 150 105 105 60

car
false
0
Polygon -7500403 true true 300 180 279 164 261 144 240 135 226 132 213 106 203 84 185 63 159 50 135 50 75 60 0 150 0 165 0 225 300 225 300 180
Circle -16777216 true false 180 180 90
Circle -16777216 true false 30 180 90
Polygon -16777216 true false 162 80 132 78 134 135 209 135 194 105 189 96 180 89
Circle -7500403 true true 47 195 58
Circle -7500403 true true 195 195 58

circle
false
0
Circle -7500403 true true 0 0 300

circle 2
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240

cow
false
0
Polygon -7500403 true true 200 193 197 249 179 249 177 196 166 187 140 189 93 191 78 179 72 211 49 209 48 181 37 149 25 120 25 89 45 72 103 84 179 75 198 76 252 64 272 81 293 103 285 121 255 121 242 118 224 167
Polygon -7500403 true true 73 210 86 251 62 249 48 208
Polygon -7500403 true true 25 114 16 195 9 204 23 213 25 200 39 123

cylinder
false
0
Circle -7500403 true true 0 0 300

dot
false
0
Circle -7500403 true true 90 90 120

face happy
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 255 90 239 62 213 47 191 67 179 90 203 109 218 150 225 192 218 210 203 227 181 251 194 236 217 212 240

face neutral
false
0
Circle -7500403 true true 8 7 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Rectangle -16777216 true false 60 195 240 225

face sad
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 168 90 184 62 210 47 232 67 244 90 220 109 205 150 198 192 205 210 220 227 242 251 229 236 206 212 183

fish
false
0
Polygon -1 true false 44 131 21 87 15 86 0 120 15 150 0 180 13 214 20 212 45 166
Polygon -1 true false 135 195 119 235 95 218 76 210 46 204 60 165
Polygon -1 true false 75 45 83 77 71 103 86 114 166 78 135 60
Polygon -7500403 true true 30 136 151 77 226 81 280 119 292 146 292 160 287 170 270 195 195 210 151 212 30 166
Circle -16777216 true false 215 106 30

flag
false
0
Rectangle -7500403 true true 60 15 75 300
Polygon -7500403 true true 90 150 270 90 90 30
Line -7500403 true 75 135 90 135
Line -7500403 true 75 45 90 45

flower
false
0
Polygon -10899396 true false 135 120 165 165 180 210 180 240 150 300 165 300 195 240 195 195 165 135
Circle -7500403 true true 85 132 38
Circle -7500403 true true 130 147 38
Circle -7500403 true true 192 85 38
Circle -7500403 true true 85 40 38
Circle -7500403 true true 177 40 38
Circle -7500403 true true 177 132 38
Circle -7500403 true true 70 85 38
Circle -7500403 true true 130 25 38
Circle -7500403 true true 96 51 108
Circle -16777216 true false 113 68 74
Polygon -10899396 true false 189 233 219 188 249 173 279 188 234 218
Polygon -10899396 true false 180 255 150 210 105 210 75 240 135 240

house
false
0
Rectangle -7500403 true true 45 120 255 285
Rectangle -16777216 true false 120 210 180 285
Polygon -7500403 true true 15 120 150 15 285 120
Line -16777216 false 30 120 270 120

leaf
false
0
Polygon -7500403 true true 150 210 135 195 120 210 60 210 30 195 60 180 60 165 15 135 30 120 15 105 40 104 45 90 60 90 90 105 105 120 120 120 105 60 120 60 135 30 150 15 165 30 180 60 195 60 180 120 195 120 210 105 240 90 255 90 263 104 285 105 270 120 285 135 240 165 240 180 270 195 240 210 180 210 165 195
Polygon -7500403 true true 135 195 135 240 120 255 105 255 105 285 135 285 165 240 165 195

line
true
0
Line -7500403 true 150 0 150 300

line half
true
0
Line -7500403 true 150 0 150 150

pentagon
false
0
Polygon -7500403 true true 150 15 15 120 60 285 240 285 285 120

person
false
0
Circle -7500403 true true 110 5 80
Polygon -7500403 true true 105 90 120 195 90 285 105 300 135 300 150 225 165 300 195 300 210 285 180 195 195 90
Rectangle -7500403 true true 127 79 172 94
Polygon -7500403 true true 195 90 240 150 225 180 165 105
Polygon -7500403 true true 105 90 60 150 75 180 135 105

plant
false
0
Rectangle -7500403 true true 135 90 165 300
Polygon -7500403 true true 135 255 90 210 45 195 75 255 135 285
Polygon -7500403 true true 165 255 210 210 255 195 225 255 165 285
Polygon -7500403 true true 135 180 90 135 45 120 75 180 135 210
Polygon -7500403 true true 165 180 165 210 225 180 255 120 210 135
Polygon -7500403 true true 135 105 90 60 45 45 75 105 135 135
Polygon -7500403 true true 165 105 165 135 225 105 255 45 210 60
Polygon -7500403 true true 135 90 120 45 150 15 180 45 165 90

square
false
0
Rectangle -7500403 true true 30 30 270 270

square 2
false
0
Rectangle -7500403 true true 30 30 270 270
Rectangle -16777216 true false 60 60 240 240

star
false
0
Polygon -7500403 true true 151 1 185 108 298 108 207 175 242 282 151 216 59 282 94 175 3 108 116 108

target
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240
Circle -7500403 true true 60 60 180
Circle -16777216 true false 90 90 120
Circle -7500403 true true 120 120 60

tree
false
0
Circle -7500403 true true 118 3 94
Rectangle -6459832 true false 120 195 180 300
Circle -7500403 true true 65 21 108
Circle -7500403 true true 116 41 127
Circle -7500403 true true 45 90 120
Circle -7500403 true true 104 74 152

triangle
false
0
Polygon -7500403 true true 150 30 15 255 285 255

triangle 2
false
0
Polygon -7500403 true true 150 30 15 255 285 255
Polygon -16777216 true false 151 99 225 223 75 224

truck
false
0
Rectangle -7500403 true true 4 45 195 187
Polygon -7500403 true true 296 193 296 150 259 134 244 104 208 104 207 194
Rectangle -1 true false 195 60 195 105
Polygon -16777216 true false 238 112 252 141 219 141 218 112
Circle -16777216 true false 234 174 42
Rectangle -7500403 true true 181 185 214 194
Circle -16777216 true false 144 174 42
Circle -16777216 true false 24 174 42
Circle -7500403 false true 24 174 42
Circle -7500403 false true 144 174 42
Circle -7500403 false true 234 174 42

turtle
true
0
Polygon -10899396 true false 215 204 240 233 246 254 228 266 215 252 193 210
Polygon -10899396 true false 195 90 225 75 245 75 260 89 269 108 261 124 240 105 225 105 210 105
Polygon -10899396 true false 105 90 75 75 55 75 40 89 31 108 39 124 60 105 75 105 90 105
Polygon -10899396 true false 132 85 134 64 107 51 108 17 150 2 192 18 192 52 169 65 172 87
Polygon -10899396 true false 85 204 60 233 54 254 72 266 85 252 107 210
Polygon -7500403 true true 119 75 179 75 209 101 224 135 220 225 175 261 128 261 81 224 74 135 88 99

wheel
false
0
Circle -7500403 true true 3 3 294
Circle -16777216 true false 30 30 240
Line -7500403 true 150 285 150 15
Line -7500403 true 15 150 285 150
Circle -7500403 true true 120 120 60
Line -7500403 true 216 40 79 269
Line -7500403 true 40 84 269 221
Line -7500403 true 40 216 269 79
Line -7500403 true 84 40 221 269

x
false
0
Polygon -7500403 true true 270 75 225 30 30 225 75 270
Polygon -7500403 true true 30 75 75 30 270 225 225 270
@#$#@#$#@
NetLogo 6.4.0
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
<experiments>
  <experiment name="Pareto_Analysis" repetitions="3" runMetricsEveryStep="true">
    <setup>load1 load2 load3 set reinforcement-activated true</setup>
    <go>go</go>
    <exitCondition>time-min &gt;= 60</exitCondition>
    <metric>rescue-score</metric>
    <metric>civil-score</metric>
    <metric>pct-safe</metric>
    <metric>mean-access-time</metric>
    <metric>active-config-label</metric>
    <enumeratedValueSet variable="a1-civilian-signal?">
      <value value="false"/>
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="a2-shelter-saturation?">
      <value value="false"/>
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="a3-priority-index?">
      <value value="false"/>
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="a4-traffic-management?">
      <value value="false"/>
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="scenario-type">
      <value value="&quot;none&quot;"/>
      <value value="&quot;fast-flood&quot;"/>
    </enumeratedValueSet>
  </experiment>
</experiments>
@#$#@#$#@
@#$#@#$#@
default
0.0
-0.2 0 0.0 1.0
0.0 1 1.0 0.0
0.2 0 0.0 1.0
link direction
true
0
Line -7500403 true 150 150 90 180
Line -7500403 true 150 150 210 180
@#$#@#$#@
0
@#$#@#$#@
