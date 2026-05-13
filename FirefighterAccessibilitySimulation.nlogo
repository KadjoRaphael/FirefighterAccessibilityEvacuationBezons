; ============================================================
; FIRE SERVICE ACCESS AND EVACUATION IN THE EVENT OF FLOODING – NETLOGO SIMULATION
; Full script with all comments translated into English
; ============================================================

extensions [ gis csv table ]

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;; BREEDS ;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; Agent type definitions — each breed represents a category of actors in the simulation
breed [ residents    resident    ]   ; Stationary civilians waiting or deciding to evacuate
breed [ pedestrians  pedestrian  ]   ; Civilians actively moving on foot toward a shelter
breed [ parents      parent      ]   ; Parents heading to pick up children at schools
breed [ workers      worker      ]   ; Workers evacuating from workplaces to shelters
breed [ relatives    relative    ]   ; Relatives heading to workplaces to retrieve someone
breed [ car-drivers  car-driver  ]   ; Civilians trying to evacuate by car
breed [ intersections intersection ] ; Road network nodes
directed-link-breed [ roads road ]   ; Directed road segments between intersections
breed [ firestations firestation ]   ; Fire station locations (fixed)
breed [ firetrucks   firetruck   ]   ; Fire rescue vehicles dispatched from stations
breed [ buses        bus-vehicle ]   ; Buses used for mass evacuation

firestations-own [ id ] ; Unique identifier for each fire station

; Properties shared by ALL agent types (turtles)
turtles-own [
  evacuated?                ; Boolean: has the agent safely evacuated?
  rescued-by-firefighters?  ; Boolean: was the agent rescued by a firetruck?
  alert-received?           ; Boolean: has the agent received an alert?
  alert-channel             ; Channel through which the alert was received (radio, app, etc.)
]

; Patch (cell) properties for the flood model
patches-own [
  depth max_depth waterDepth floodClass  ; Current depth, historical max, original raster depth, flood class (0–4)
  water-rise-rate                        ; Rate at which water is rising (m/tick)
  predicted-depth                        ; Anticipated future water depth (lookahead)
  prev-depth                             ; Depth at previous tick (for rise-rate calculation)
  shared-congestion-signal               ; Traffic congestion signal broadcast by firetrucks (Improvement A4)
  civilian-flood-signal                  ; Flood signal broadcast by civilians in distress (Improvement A1)
]

; Properties specific to resident agents
residents-own [
  init_dest reached? current_int moving?  ; Initial destination, reached flag, current intersection, movement flag
  speed decision miltime time_in_water    ; Walking speed, evacuation decision (1=evacuate,2=wait), decision time, time spent in water
  max_depth_agent                         ; Maximum flood depth the agent has been exposed to
  wait-start-tick                         ; Tick at which the agent started waiting (decision=2)
  prev-flood-class                        ; Flood class at previous tick (used for re-decision)
]

; Properties specific to directed road links
roads-own [ crowd traffic mid-x mid-y road-capacity-factor crowd-density ]
; crowd: number of agents on this road segment
; traffic: traffic level
; mid-x/mid-y: midpoint coordinates of the segment
; road-capacity-factor: reduction factor (1.0 = free, 0.0 = fully blocked)
; crowd-density: weighted density of nearby agents

; Properties specific to intersection nodes
intersections-own [
  shelter? shelter_type id previous fscore gscore  ; Shelter flag, type (Hor/Ver), ID, A* parent, A* scores
  hor-path evacuee_count                           ; Pre-computed horizontal shelter path, count of evacuees arrived
  school?                                          ; True if this intersection is a school
  workplace?                                       ; True if this intersection is a workplace
]

; Properties specific to pedestrian agents
pedestrians-own [
  current_int shelter next_int moving?  ; Current intersection, target shelter ID, next intersection, movement flag
  speed path decision time_in_water     ; Speed, planned route, decision, time in water
  max_depth_agent                       ; Maximum water depth encountered
]

; Properties specific to parent agents
parents-own [
  current_int dest_int next_int moving?  ; Current/destination/next intersection, movement flag
  speed path time_in_water max_depth_agent  ; Speed, route, time in water, max depth
  mission-done?                          ; True when the parent has reached the school
]

; Properties specific to worker agents
workers-own [
  current_int dest_int next_int moving?
  speed path time_in_water max_depth_agent
  mission-done?
]

; Properties specific to relative agents
relatives-own [
  current_int dest_int next_int moving?
  speed path time_in_water max_depth_agent
  mission-done?
]

; Properties specific to car-driver agents
car-drivers-own [
  current_int next_int dest_int moving?
  speed path time_in_water max_depth_agent
  can-drive?   ; False if flood depth forces the driver to abandon the car
  decision     ; Evacuation decision
]

; Properties specific to bus agents
buses-own [
  current_int next_int dest_int home_post  ; Navigation state and home collection point
  path phase capacity                      ; Planned route, current phase (collecting/to-shelter), max passengers
  passengers-cargo moving? speed          ; List of passengers on board, movement flag, speed
]

; Properties specific to firetruck agents
firetrucks-own [
  current_int next_int path                  ; Navigation: current/next intersection, route
  target-resident target_int                 ; Assigned victim and their nearest intersection
  moving? speed                              ; Movement flag and speed
  rescue_time                                ; Remaining ticks for the rescue operation
  home_post                                  ; Starting intersection (station or reinforcement post)
  drop_post                                  ; Target shelter for drop-off
  phase                                      ; Current phase: to-victim / rescuing / to-drop / returning
  capacity                                   ; Maximum number of victims the truck can carry
  cargo                                      ; List of victims currently on board
  dispatch-tick                              ; Tick at which this truck was dispatched
  firetruck-station-id                       ; ID of the originating fire station
  alt-paths                                  ; List of k alternative routes
  current-route-idx                          ; Index of the currently used route in alt-paths
  reroute-cooldown                           ; Cooldown ticks before a new rerouting is allowed
  priority-mode?                             ; True if the truck is in priority mode (clears traffic)
  prev-path                                  ; Previous route (used for congestion signal broadcast)
]

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;; GLOBALS ;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

globals [
  ev_times                  ; List of evacuation times (in minutes) for all evacuated agents
  mouse-was-down?           ; Tracks previous mouse state for click detection
  road_network              ; GIS dataset: road network shapefile
  population_distribution   ; GIS dataset: initial population locations
  shelter_locations         ; GIS dataset: shelter locations
  tsunami_sample            ; GIS raster: flood depth data (ASC file)
  cis_dataset               ; GIS dataset: fire station locations
  ecoles_dataset            ; GIS dataset: school locations
  entreprises_dataset       ; GIS dataset: workplace/business locations

  zip100-raster             ; Reference to the flood raster for progressive flooding

  cum_rescued               ; Cumulative count of victims rescued by firetrucks
  cum_self_evacuated        ; Cumulative count of agents who self-evacuated

  reinforcement_posts           ; Agentset of reinforcement post intersections
  reinforcement_start_min       ; Minute at which reinforcement dispatching begins
  reinforcement_interval_sec    ; Seconds between reinforcement dispatch waves
  reinforcement_batch_size      ; Number of reinforcement trucks per wave

  cached-shelters           ; Pre-cached agentset of all shelter intersections
  cached-schools            ; Pre-cached agentset of all school intersections
  cached-workplaces         ; Pre-cached agentset of all workplace intersections
  flood-patches-cache       ; Pre-cached agentset of all flooded patches

  N_Foot                    ; Number of residents who decided to evacuate on foot
  N_Wait                    ; Number of residents who decided to wait

  patch_to_meter            ; Scale factor: size of one patch in meters
  tick_to_sec               ; Duration of one tick in seconds (60 s)

  fd_to_mps                 ; Conversion: patches/tick to meters/second
  fd_to_kph                 ; Conversion: patches/tick to km/h

  min_lon                   ; Minimum longitude of the GIS envelope
  min_lat                   ; Minimum latitude of the GIS envelope

  access-times              ; List of firetruck access times (minutes) recorded per rescue
  cum-reroutes              ; Cumulative number of firetruck rerouting events

  record-video?             ; Boolean: whether video recording is active

  cum-parents-arrived       ; Cumulative parents who completed their mission
  cum-workers-arrived       ; Cumulative workers who reached their destination
  cum-relatives-arrived     ; Cumulative relatives who completed their mission

  nb-camions-bloques        ; Number of firetrucks that could not find a route
  pct-routes-inondees       ; Percentage of roads that are flooded
  pct-routes-saturees       ; Percentage of roads that are congested

  temps-acces-caserne-1     ; Last recorded access time for station 1
  temps-acces-caserne-2     ; Last recorded access time for station 2
  temps-acces-caserne-3     ; Last recorded access time for station 3

  saturation-threshold      ; Crowd count above which a road is considered saturated
  crowd-weight              ; Weight applied to crowd penalty in A* pathfinding
  road-block-rate           ; Base probability rate for random road blockage
  num-parents               ; Number of parent agents to create
  num-workers               ; Number of worker agents to create
  num-relatives             ; Number of relative agents to create

  immediate_evacuation      ; Boolean: forces all residents to evacuate immediately at t=0
  wait-time-min             ; Maximum wait time (minutes) before a waiting resident is forced to evacuate

  accessibility-index       ; Composite accessibility index (0–100), updated each cycle
  mean-rescue-delay         ; Mean rescue delay computed from recorded access times
  isolated-victims-count    ; Count of victims unreachable from any fire station
  pct-network-accessible    ; Percentage of road network still accessible

  reinforcement-activated   ; Boolean: whether reinforcements have been activated
  reinforcement-trigger-min ; Minute threshold that triggers a reinforcement activation prompt
  reinforcement-alert-shown ; Boolean: whether the reinforcement alert has already been shown
  simulation-paused?        ; Boolean: whether the simulation is currently paused

  cum-congestion-events     ; Cumulative count of ticks where at least one road was saturated
  cum-trucks-delivered      ; Cumulative number of victims successfully delivered to shelters

  alert-delay-min           ; Alert delay in minutes (used in what-if late-alert scenario)
  shelter-capacity-pct      ; Capacity percentage used in shelter overflow scenario

  num-buses                 ; Number of bus agents to create
  num-car-drivers           ; Number of car-driver agents to create

  flood-lookahead           ; Number of ticks ahead used to predict future flood depth
  flood-rise-threshold      ; Minimum rise rate (m/tick) considered significant
  flood-update-interval     ; Frequency (ticks) for updating water rise rates

  road-usage-counts         ; Table: key=(from,to), value=number of trucks using that segment

  claimed-victims           ; List of victim WHO IDs already assigned to a firetruck
  reroute-refresh-interval  ; Frequency (ticks) for periodic route refresh in firetrucks
  alert-propagation-radius  ; Radius within which alerts and rerouting signals propagate
  cum-civilian-reroutes     ; Cumulative count of civilian rerouting events

  cum-truck-congestion-events  ; Congestion events caused mainly by trucks
  cum-civil-congestion-events  ; Congestion events caused mainly by civilians

  shelter-max-capacity          ; Maximum allowed evacuees per shelter before it's considered saturated
  shelter-saturation-reroutes   ; Count of firetrucks rerouted due to shelter saturation

  cum-civil-reactions-to-truck-reroute  ; Count of civilians who rerouted following a truck rerouting
  congestion-signal-decay               ; Exponential decay factor for the congestion signal (A4)

  comm-channel              ; Active communication channel: "radio", "app", "word-of-mouth", or "combined"
  radio-alert-radius        ; Radius of the radio alert coverage (effectively infinite)
  radio-alert-delay-ticks   ; Ticks before the radio alert is broadcast
  radio-alert-fired?        ; Boolean: whether the radio alert has already been sent
  app-alert-radius          ; Radius of the app-based alert
  app-alert-delay-ticks     ; Ticks before the app alert is triggered
  app-alert-fired?          ; Boolean: whether the app alert has already been sent
  word-of-mouth-radius      ; Radius for word-of-mouth alert propagation
  cum-radio-alerts          ; Cumulative count of residents alerted via radio
  cum-app-alerts            ; Cumulative count of residents alerted via app
  cum-wom-alerts            ; Cumulative count of residents alerted via word of mouth
  cum-firetruck-alerts      ; Cumulative count of residents alerted by firetruck proximity

  firetruck-priority-enabled?   ; Boolean: enables firetruck priority mode in traffic (A4)
  priority-crowd-reduction      ; Crowd reduction factor when a priority truck is present
  cum-priority-passages         ; Cumulative number of priority passages recorded

  base-truck-speed          ; Reference speed for firetrucks (in patches/tick)
  cum-speed-reductions      ; Cumulative count of ticks where truck speed was reduced by flood

  access-time-reinforce-threshold     ; Mean access time threshold (minutes) that auto-triggers reinforcements
  access-time-check-interval          ; Frequency (ticks) for checking the access time threshold
  cum-access-triggered-reinforcements ; Count of automatic reinforcement activations triggered by access time

  cum-civilian-flood-signals               ; Cumulative signals emitted by distressed civilians (A1)
  cum-shelter-saturation-civilian-reroutes ; Civilians rerouted due to shelter saturation (A2)
  cum-index-driven-prioritizations         ; Prioritization decisions driven by the accessibility index (A3)
  cum-traffic-saturation-managed           ; Ticks where traffic saturation was actively managed (A4)
]


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; REPORTER: EVACUATION AGENT SET
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; Returns all agents that are part of the evacuation population (residents + pedestrians)
to-report evac-agents
  report (turtle-set residents pedestrians)
end

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; RESET IMPROVEMENT CONFIGURATION
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; Resets all improvement toggles (A1–A4) and the scenario type to their default off/none state
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

; Returns true if the mouse was clicked (button released this tick)
to-report mouse-clicked?
  report (mouse-was-down? = true and not mouse-down?)
end

; Finds all unique intersections that have at least one resident on them
to-report find-origins
  let origins []
  ask residents [
    set origins lput min-one-of intersections [ distance myself ] origins
  ]
  set origins remove-duplicates origins
  report origins
end

; Assigns the initial evacuation decision (decision=0) and a reaction time using the Rayleigh model
to make-decision
  set decision 0
  set miltime (Rtau1 / tick_to_sec)  ; Convert global reaction time parameter to ticks
end

; Rayleigh distribution sampler — models alert reaction delay (based on Douvinet 2018).
; sigma varies by flood exposure level:
;   - High exposure (floodClass >= 3): short sigma (~2–5 min) — fast reaction
;   - Medium exposure (fc = 2)       : medium sigma (~6–10 min)
;   - Low exposure (fc <= 1)         : long sigma (~7–15 min) — slower reaction
; The alert channel (radio, app, word-of-mouth, truck proximity)
; modulates both the trigger probability AND the sigma used.
to-report rayleigh-sample [ sigma ]
  let u random-float 0.9999
  if u <= 0 [ set u 0.0001 ]   ; Avoid log(0)
  report sigma * sqrt (-2 * ln (1 - u))
end

; Computes the flood penalty for a road segment (used in A* for vehicles)
; Returns 99999 (impassable) if water depth exceeds 1.2 m
to-report flood-penalty-for-patch [ mid-p ]
  if mid-p = nobody [ report 0 ]
  let pen  0
  let fc   [floodClass]       of mid-p   ; Flood class (0–4)
  let wd   [depth]            of mid-p   ; Current water depth (m)
  let pred [predicted-depth]  of mid-p   ; Predicted depth (lookahead)
  let rise [water-rise-rate]  of mid-p   ; Water rise rate (m/tick)

  set pen pen + fc * 10                        ; Base penalty proportional to flood class
  if fc >= 3 [ set pen pen + fc * 10 ]         ; Extra penalty for severe flood classes
  if wd > 0.3 [ set pen pen + wd * 15 ]        ; Penalty increases with depth
  if wd > 0.6 [ set pen pen + wd * 10 ]
  if wd > 1.0 [ set pen pen + 40 ]
  if wd > 1.2 [ report 99999 ]                 ; Road impassable above 1.2 m
  if pred > 0.3 [ set pen pen + pred * 18 ]    ; Predictive penalty for anticipated rise
  if pred > 0.6 [ set pen pen + pred * 12 ]
  if pred > 1.0 [ set pen pen + 45 ]
  if pred > 1.2 [ report 99999 ]               ; Future depth also makes road impassable
  if rise > flood-rise-threshold [ set pen pen + rise * 65 ] ; Fast-rising water increases penalty

  ; Improvement A4: add congestion signal penalty if traffic management is active
  if a4-traffic-management? [
    let sig [shared-congestion-signal] of mid-p
    if sig > 0 [ set pen pen + sig * 20 ]
  ]
  ; Improvement A1: add civilian flood signal penalty if civilian signaling is active
  if a1-civilian-signal? [
    let csig [civilian-flood-signal] of mid-p
    if csig > 0.5 [ set pen pen + csig * 15 ]
    if csig > 2.0 [ set pen pen + csig * 10 ]
  ]
  report pen
end


; Reduced flood penalty for pedestrian movement — never returns 99999 (no hard cutoff on foot)
to-report flood-penalty-foot [ mid-p ]
  if mid-p = nobody [ report 0 ]
  let pen 0
  let fc   [floodClass]      of mid-p
  let wd   [depth]           of mid-p
  let pred [predicted-depth] of mid-p
  let rise [water-rise-rate] of mid-p
  set pen pen + fc * 5                         ; Lower base penalty than vehicle mode
  if wd > 0.3 [ set pen pen + wd * 10 ]
  if wd > 0.6 [ set pen pen + wd * 15 ]
  if wd > 1.0 [ set pen pen + 20 ]
  if wd > 1.5 [ set pen pen + 35 ]
  if pred > 0.6 [ set pen pen + pred * 10 ]
  if rise > flood-rise-threshold [ set pen pen + rise * 30 ]
  report pen
end


; Flood penalty specific to heavy rescue trucks — tolerates higher water but is still penalized
to-report flood-penalty-truck [ mid-p ]
  if mid-p = nobody [ report 0 ]
  let pen  0
  let wd   [depth]           of mid-p
  let pred [predicted-depth] of mid-p
  let rise [water-rise-rate] of mid-p
  if wd > 0.3 [ set pen pen + wd * 8  ]
  if wd > 0.6 [ set pen pen + wd * 12 ]
  if wd > 1.0 [ set pen pen + 25      ]
  if wd > 1.5 [ set pen pen + 40      ]
  if pred > 0.6 [ set pen pen + pred * 8  ]
  if pred > 1.2 [ set pen pen + pred * 12 ]
  if rise > flood-rise-threshold [ set pen pen + rise * 20 ]
  report pen
end


; Assigns evacuation decisions to all residents using a behavioral probability model.
; Evacuation probability increases with flood class and alert reception.
; Uses a Rayleigh distribution to model reaction time:
;   floodClass >= 3 → sigma = 5 min  (high exposure, fast reaction)
;   floodClass  = 2 → sigma = 10 min (medium exposure)
;   floodClass <= 1 → sigma = 15 min (low exposure, slower reaction)
to assign-decisions-behavioral
  ask residents [
    let fc [floodClass] of patch-here
    let p-evacuate 0.50              ; Base evacuation probability
    if fc = 1 [ set p-evacuate 0.65 ]
    if fc = 2 [ set p-evacuate 0.80 ]
    if fc = 3 [ set p-evacuate 0.90 ]
    if fc = 4 [ set p-evacuate 0.97 ]
    if alert-received? [ set p-evacuate min list 1.0 (p-evacuate + 0.15) ] ; Alert increases probability
    ifelse random-float 1 < p-evacuate [
      set decision 1   ; Resident decides to evacuate
      let sigma-sec ifelse-value (fc >= 3) [ 5 * 60 ]
        [ ifelse-value (fc = 2) [ 10 * 60 ] [ 15 * 60 ] ]
      let raw-time (rayleigh-sample sigma-sec) / tick_to_sec   ; Reaction delay in ticks
      set miltime max list 1 raw-time                          ; At least 1 tick before moving
    ] [
      set decision 2   ; Resident decides to wait (shelter-in-place)
      set color gray
      set miltime 0
    ]
    set prev-flood-class fc   ; Store flood class for change detection next tick
  ]
  set N_Foot count residents with [ decision = 1 ]   ; Count of foot evacuees
  set N_Wait count residents with [ decision = 2 ]   ; Count of waiting residents
end

; Risk-based decision assignment — currently delegates to the behavioral model
to assign-decisions-risk-based
  assign-decisions-behavioral
end

; Placeholder for water rise rate updates (logic handled inline in the go loop)
to update-water-rise-rates
end

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; A* PATHFINDING ALGORITHM
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; Standard A* for civilian vehicles.
; Finds the shortest path from intersection 'source' to goal set 'gls' (closest to 'gl').
; Incorporates: road length, crowd penalty, road-capacity-factor block penalty, and flood penalty.
to-report Astar [ source gl gls ]
  let rchd? false
  let dstn nobody
  let closedset []
  let openset []
  ask intersections [ set previous -1 ]    ; Reset pathfinding state on all nodes
  set openset lput [who] of source openset
  ask source [
    set gscore 0
    set fscore (gscore + distance gl)      ; f = g + h (heuristic = Euclidean distance to goal)
  ]
  while [ not empty? openset and (not rchd?) ] [
    let current Astar-smallest openset     ; Expand node with lowest f-score
    if member? current [who] of gls [
      set dstn intersection current
      set rchd? true
    ]
    set openset remove current openset
    set closedset lput current closedset
    ask intersection current [
      ask out-road-neighbors [
        let this-road road [who] of myself who
        let road-cost   [link-length] of this-road              ; Geometric road length
        let cap-factor  [road-capacity-factor] of this-road     ; Capacity reduction factor
        let crowd-pen   crowd-weight * [crowd] of this-road     ; Crowd-based congestion penalty
        if cap-factor <= 0 [ stop ]                             ; Road fully blocked — skip
        let block-pen ifelse-value (cap-factor < 1.0)
          [ (1.0 - cap-factor) * 30 ] [ 0 ]                    ; Additional penalty for partial blockage
        let mid-p patch [mid-x] of this-road [mid-y] of this-road
        let flood-pen flood-penalty-for-patch mid-p             ; Flood-based penalty
        let tent_gscore [gscore] of myself + road-cost + crowd-pen + block-pen + flood-pen
        let tent_fscore tent_gscore + distance gl
        if ( member? who closedset and ( tent_fscore >= fscore ) ) [ stop ]
        if ( not member? who closedset ) [
          set previous current
          set gscore tent_gscore
          set fscore tent_fscore
          if not member? who openset [ set openset lput who openset ]
        ]
      ]
    ]
  ]
  ; Reconstruct path by backtracking through 'previous' pointers
  let route []
  ifelse dstn != nobody [
    while [ [previous] of dstn != -1 ] [
      set route fput [who] of dstn route
      set dstn intersection ([previous] of dstn)
    ]
  ] [ set route [] ]
  report route
end


; A* variant for pedestrians on foot.
; Road-capacity-factor is ignored (a blocked road can still be crossed on foot).
; Uses flood-penalty-foot which never returns 99999.
to-report Astar-foot [ source gl gls ]
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
        let road-cost  [link-length] of this-road
        let crowd-pen  crowd-weight * [crowd] of this-road
        ; Pedestrian mode: capacity factor ignored, lighter flood penalty
        let mid-p patch [mid-x] of this-road [mid-y] of this-road
        let flood-pen flood-penalty-foot mid-p
        let tent_gscore [gscore] of myself + road-cost + crowd-pen + flood-pen
        let tent_fscore tent_gscore + distance gl
        if ( member? who closedset and ( tent_fscore >= fscore ) ) [ stop ]
        if ( not member? who closedset ) [
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


; A* variant for heavy rescue trucks.
; Uses flood-penalty-truck (no crowd or capacity penalties — trucks override traffic).
to-report Astar-truck [ source gl gls ]
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
        let road-cost [link-length] of this-road
        let mid-p patch [mid-x] of this-road [mid-y] of this-road
        let flood-pen flood-penalty-truck mid-p   ; Truck-specific flood penalty
        let tent_gscore [gscore] of myself + road-cost + flood-pen
        let tent_fscore tent_gscore + distance gl
        if ( member? who closedset and ( tent_fscore >= fscore ) ) [ stop ]
        if ( not member? who closedset ) [
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


; Returns the WHO of the intersection with the lowest f-score in the open set
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
;; K-BEST PATHS COMPUTATION
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; Computes up to k alternative routes between src and tgt.
; Uses a penalty-multiplier strategy: progressively degrades previously found routes
; to force A* to explore different paths.
; use-truck? switches between Astar (civilian) and Astar-truck.
to-report k-best-paths-generic [ src tgt k use-truck? ]
  let routes []
  let penalty-multipliers [ 0.10 0.20 0.35 0.50 ]   ; Increasing penalty to diverge from base route
  let base-route ifelse-value use-truck?
    [ Astar-truck src tgt (turtle-set tgt) ]
    [ Astar       src tgt (turtle-set tgt) ]
  if not empty? base-route [ set routes lput base-route routes ]
  let iter 0
  while [ iter < (k - 1) and length routes < k ] [
    let pmul item (min list iter (length penalty-multipliers - 1)) penalty-multipliers
    ; Save and degrade capacity factors of all known-route segments
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
    ; Find a new alternative route with degraded original paths
    let alt-route ifelse-value use-truck?
      [ Astar-truck src tgt (turtle-set tgt) ]
      [ Astar       src tgt (turtle-set tgt) ]
    ; Restore original capacity factors
    ask roads [
      let lkey (list ([who] of end1) ([who] of end2))
      if table:has-key? saved-caps lkey [
        set road-capacity-factor table:get saved-caps lkey ]
    ]
    ; Only add if not a duplicate
    if not empty? alt-route [
      let is-duplicate? false
      foreach routes [ r -> if r = alt-route [ set is-duplicate? true ] ]
      if not is-duplicate? [ set routes lput alt-route routes ]
    ]
    set iter iter + 1
  ]
  report routes
end

; k-best paths for civilian vehicles
to-report k-best-paths [ src tgt k ]
  report k-best-paths-generic src tgt k false
end

; k-best paths for firetrucks
to-report k-best-paths-truck [ src tgt k ]
  report k-best-paths-generic src tgt k true
end


; Returns the number of firetrucks currently routed through a given road segment
to-report trucks-on-road [ from-who to-who ]
  let key (list from-who to-who)
  ifelse table:has-key? road-usage-counts key
    [ report table:get road-usage-counts key ]
    [ report 0 ]
end


; Scores a given route based on multiple criteria:
; travel time (accounting for flood depth), congestion, blockage, flood penalty,
; and coordination penalty for multiple trucks on the same segment.
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
          if cap <= 0 [ report 99999 ]           ; Segment fully blocked
          let dist      [link-length] of r
          let cong-pen  [crowd-density] of r * crowd-weight
          let block-pen ifelse-value (cap < 0.5) [ (1 - cap) * 50 ] [ 0 ]
          let mid-p patch [mid-x] of r [mid-y] of r
          let flood-pen flood-penalty-for-patch mid-p
          let truck-count trucks-on-road ([who] of from-int) ([who] of to-int)
          let coordination-pen truck-count * 15  ; Penalty when multiple trucks share a segment
          let seg-depth ifelse-value (mid-p != nobody) [ [depth] of mid-p ] [ 0 ]
          let effective-speed max list 0.1 (1.0 - (seg-depth / 1.5)) ; Speed decreases with depth
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


; Returns the route with the lowest score from a list of candidate routes
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
;; CONGESTION MANAGEMENT
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; Updates crowd and crowd-density values for all road segments each tick.
; Accounts for priority truck presence to reduce effective civil crowd count (A4).
to update-crowd
  ask roads [
    ; Count civilian agents within proximity radius 3
    let civil-count count
      (turtle-set residents pedestrians parents workers relatives car-drivers) with [
        distancexy [mid-x] of myself [mid-y] of myself < 3
      ]
    let truck-count count firetrucks with [
      distancexy [mid-x] of myself [mid-y] of myself < 3
    ]
    ; Count trucks in priority mode near this road
    let priority-trucks-here count firetrucks with [
      priority-mode? = true and
      distancexy [mid-x] of myself [mid-y] of myself < 3
    ]
    ; A4: reduce effective civil crowd when priority trucks are present
    let effective-civil-count ifelse-value
      (a4-traffic-management? and firetruck-priority-enabled? and priority-trucks-here > 0)
      [ max list 0 (civil-count - (priority-trucks-here * 2)) ]
      [ civil-count ]
    let truck-equiv truck-count * 3   ; 1 truck = 3 equivalent civilian agents for crowd purposes
    let priority-reduction ifelse-value
      (a4-traffic-management? and firetruck-priority-enabled? and priority-trucks-here > 0)
      [ priority-trucks-here * 2 ] [ 0 ]
    set crowd max list 0 (effective-civil-count + truck-equiv - priority-reduction)

    ; Compute weighted density: agents closer to midpoint contribute more
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
      if d > 0.01 [ set weighted-density weighted-density + (3 / d) ]   ; Trucks weighted x3
    ]
    set crowd-density precision weighted-density 3

    ; Color the road based on saturation state
    if road-capacity-factor >= 0.7 [
      ifelse crowd >= saturation-threshold [
        set color red   ; Road is saturated
        ifelse truck-equiv > effective-civil-count
          [ set cum-truck-congestion-events cum-truck-congestion-events + 1 ]   ; Congestion caused by trucks
          [ set cum-civil-congestion-events cum-civil-congestion-events + 1 ]   ; Congestion caused by civilians
      ] [
        ; Flood priority coloring: orange if water is present, otherwise black
        let mid-p-c patch mid-x mid-y
        ifelse (mid-p-c != nobody and [depth] of mid-p-c > 0)
          [ set color orange ]
          [ set color black ]
      ]
    ]
  ]
end


; Updates the road-capacity-factor for each road based on current and predicted flood depth.
; Also applies stochastic road blockage based on flood class.
to update-road-obstructions
  ask roads [
    let mid-patch patch mid-x mid-y
    if mid-patch != nobody [
      let fc [floodClass] of mid-patch
      let wd max list ([depth] of mid-patch) ([waterDepth] of mid-patch)
      ; Progressively reduce capacity with increasing depth
      if wd > 0.1 and wd <= 0.3 [ set road-capacity-factor max list 0.6 (road-capacity-factor - 0.03) ]
      if wd > 0.3 and wd <= 0.6 [ set road-capacity-factor max list 0.3 (road-capacity-factor - 0.08) ]
      if wd > 0.6 and wd <= 1.0 [ set road-capacity-factor max list 0.1 (road-capacity-factor - 0.12) ]
      if wd > 1.0               [ set road-capacity-factor max list 0.0 (road-capacity-factor - 0.20) ]
      ; Fast-rising water accelerates capacity reduction
      let rise [water-rise-rate] of mid-patch
      if rise > flood-rise-threshold and wd > 0 [
        set road-capacity-factor max list 0.05 (road-capacity-factor - rise * 0.5) ]
      ; Predictive capacity reduction based on forecast depth
      let pred [predicted-depth] of mid-patch
      if pred > 0.6 and road-capacity-factor > 0.3 [
        set road-capacity-factor max list 0.3 (road-capacity-factor - 0.05) ]
      if pred > 1.0 [ set road-capacity-factor max list 0.1 (road-capacity-factor - 0.10) ]
      ; Slowly recover capacity on dry, uncrowded roads
      if wd <= 0 and crowd = 0 [
        set road-capacity-factor min list 1.0 (road-capacity-factor + 0.02) ]
      ; Stochastic partial blockage for roads in flooded areas (debris, vehicles)
      if fc >= 2 [
        let prob-block (road-block-rate / 100) * (fc - 1) * 0.04
        if random-float 1 < prob-block [
          set road-capacity-factor max list 0.1 (road-capacity-factor - 0.10) ]
      ]
      ; Update road color based on capacity level
      if road-capacity-factor <= 0                              [ set color red     ]
      if road-capacity-factor > 0 and road-capacity-factor < 0.3  [ set color red + 1 ]
      if road-capacity-factor >= 0.3 and road-capacity-factor < 0.7 [ set color orange ]
      if road-capacity-factor >= 0.7 [
        ifelse crowd >= saturation-threshold [ set color red ] [ set color black ] ]

      ; Flood priority: flooded roads are always shown in orange regardless of capacity
      if [depth] of mid-patch > 0 [ set color orange ]
    ]
  ]
end


; Applies flood-priority coloring each tick: orange for flooded roads, black otherwise
to update-road-flood-colors
  ask roads [
    let mid-p patch mid-x mid-y
    if mid-p != nobody [
      ifelse [depth] of mid-p > 0
        [ set color orange ]
        [ if road-capacity-factor >= 0.7 and crowd < saturation-threshold
          [ set color black ] ]
    ]
  ]
end


; Updates the global statistics on flooded and saturated roads
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


; Rebuilds the road-usage-counts table based on active firetruck routes
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


; Detects whether congestion or flooding lies ahead on a firetruck's planned route.
; Uses proximity-based sensitivity: closer segments are checked with full threshold,
; further segments with progressively relaxed thresholds.
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
          ; Proximity factor: nearby segments have full sensitivity
          let proximity-factor ifelse-value (i < 3) [ 1.0 ]
            [ ifelse-value (i < 8) [ 0.8 ] [ 0.6 ] ]
          if [crowd] of r >= (saturation-threshold * proximity-factor) [ set detected? true ]
          if [road-capacity-factor] of r < (0.35 * proximity-factor)   [ set detected? true ]
          let mid-p patch [mid-x] of r [mid-y] of r
          if mid-p != nobody [
            if [waterDepth] of mid-p > (0.4 * proximity-factor)        [ set detected? true ]
            if [water-rise-rate] of mid-p > flood-rise-threshold        [ set detected? true ]
            if [predicted-depth] of mid-p > (0.5 * proximity-factor)   [ set detected? true ]
            ; A1: also detect based on civilian flood signal
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
;; IMPROVEMENT A1 — CIVILIAN FLOOD SIGNALS TO FIRETRUCKS
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; Civilians in flood-affected areas emit a flood signal on their patch.
; This signal is then read by firetrucks and A* as an additional cost penalty.
to civilians-broadcast-flood-signals
  if not a1-civilian-signal? [ stop ]
  ; Stationary residents in water broadcast a signal on their current patch
  ask residents with [ not evacuated? and [waterDepth] of patch-here > 0.3 ] [
    ask patch-here [
      set civilian-flood-signal min list 5.0 (civilian-flood-signal + 0.35)
    ]
    set cum-civilian-flood-signals cum-civilian-flood-signals + 1
  ]
  ; Pedestrians also broadcast on their current patch and along their upcoming path
  ask pedestrians with [ not evacuated? ] [
    if [waterDepth] of patch-here > 0.3 [
      ask patch-here [
        set civilian-flood-signal min list 5.0 (civilian-flood-signal + 0.40)
      ]
      set cum-civilian-flood-signals cum-civilian-flood-signals + 1
    ]
    ; Broadcast on the next 2 road segments of their current path
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

; Exponential decay of civilian flood signals — signals fade over time if not reinforced
to decay-civilian-flood-signals
  ask patches with [ civilian-flood-signal > 0 ] [
    set civilian-flood-signal max list 0 (civilian-flood-signal * 0.80)
  ]
end

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; SHARED CONGESTION SIGNAL (A4)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; Broadcasts a congestion signal along a route.
; congested? = true → signal increases (warns of congestion)
; congested? = false → signal decreases (congestion cleared on new route)
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

; Decays the shared congestion signal over time (A4 active) or resets it to zero (A4 off)
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

; Pedestrians near a truck's old (congested) route reroute to a less saturated shelter.
; Used to model the ripple effect of firetruck rerouting on civilian behavior.
to civilian-react-to-truck-reroute [ old-route ]
  if empty? old-route [ stop ]
  ; Compute the centroid of the old route to define a reaction zone
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
  ; Pedestrians within the reaction radius reroute toward an available shelter
  ask pedestrians with [
    evacuated? = false and not empty? path and current_int != nobody and
    distancexy cx cy < alert-propagation-radius
  ] [
    let goals nobody
    ifelse a2-shelter-saturation? [
      ; A2 active: prefer unsaturated horizontal shelters
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
;; IMPROVEMENT A2 — SHELTER SATURATION REROUTING
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; Checks each active pedestrian's upcoming path for congestion or flood blockage.
; Also reroutes if their target shelter is over capacity (A2).
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
            let prox-factor ifelse-value (j = 0) [ 1.0 ] [ 0.75 ]  ; Next segment checked with full sensitivity
            if [crowd] of r >= (saturation-threshold * prox-factor) [ set need-reroute? true ]
            if [road-capacity-factor] of r < (0.25 * prox-factor)   [ set need-reroute? true ]
            let mid-p patch [mid-x] of r [mid-y] of r
            if mid-p != nobody [
              if [depth] of mid-p > (Hc * prox-factor)              [ set need-reroute? true ]  ; Depth exceeds pedestrian threshold
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
    ; A2: also reroute if target shelter is saturated
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
    ; Perform rerouting if needed
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


; Switches a waiting resident (decision=2) to active evacuation (decision=1).
; Called within the context of a specific resident agent (ask residents [...]).
; sigma-sec: Rayleigh standard deviation in seconds for reaction delay.
to switch-to-evacuation [ sigma-sec ]
  set decision 1  set color brown
  let raw-time (rayleigh-sample sigma-sec) / tick_to_sec
  set miltime max list 1 (ticks + raw-time)    ; Schedule start of movement
  set wait-start-tick -1                        ; Reset wait counter
  set claimed-victims remove who claimed-victims  ; Release any prior firetruck claim
end

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; ALERT CHANNELS
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; Propagates evacuation alerts to residents through one or more channels.
; Supported channels: "radio", "app", "word-of-mouth", "combined"
; Each channel has distinct reach, delay, and behavioral effectiveness.
to propagate-alert-differentiated

  ; --- RADIO ALERT ---
  ; Broadcast to all residents at once after radio-alert-delay-ticks
  ; Reception rate: 85% of all non-evacuated residents
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
              ; Rayleigh sigma for radio: shorter in high-risk zones
              let sigma-sec ifelse-value (fc >= 3) [ 4 * 60 ] [ 9 * 60 ]
              switch-to-evacuation sigma-sec ]
          ]
          ; Accelerate departure for residents already planning to evacuate
          if decision = 1 and miltime > ticks [
            set miltime max list ticks (miltime * 0.6) ]
        ]
      ]
      output-print (word "RADIO broadcast at " precision time-min 1
        " min - " cum-radio-alerts " residents alerted")
    ]
  ]

  ; --- APP ALERT ---
  ; Targeted mobile app notification — more precise but less accessible in deep flood zones
  ; Reception inversely proportional to flood class (phones/connectivity more impaired)
  if (comm-channel = "app" or comm-channel = "combined") [
    if ticks >= app-alert-delay-ticks and not app-alert-fired? [
      set app-alert-fired? true
      ask residents with [ alert-received? = false and evacuated? = false ] [
        let fc-local [floodClass] of patch-here
        let p-receive ifelse-value (fc-local <= 1) [ 0.90 ]
          [ ifelse-value (fc-local = 2) [ 0.70 ] [ 0.45 ] ]  ; Lower reception in flooded areas
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
              ; App Rayleigh sigma: very short (immediate, targeted alert)
              let sigma-sec ifelse-value (fc-local >= 3) [ 2 * 60 ] [ 6 * 60 ]
              let raw-time (rayleigh-sample sigma-sec) / tick_to_sec
              set miltime max list 1 (ticks + raw-time)
              set wait-start-tick -1
              set claimed-victims remove who claimed-victims
            ]
          ]
          if decision = 1 and miltime > ticks [
            set miltime max list ticks (miltime * 0.4) ]  ; App accelerates departure strongly
        ]
      ]
      output-print (word "APP broadcast at " precision time-min 1
        " min - " cum-app-alerts " residents alerted")
    ]
  ]

  ; --- WORD-OF-MOUTH ALERT ---
  ; Residents alerted by nearby evacuees, firetrucks, or previously alerted neighbors
  ; Two rounds: 1) direct proximity to alert sources, 2) peer-to-peer propagation
  if (comm-channel = "word-of-mouth" or comm-channel = "combined") [
    ask residents with [ alert-received? = false and evacuated? = false ] [
      let me self
      let found? false
      ; Check proximity to active firetrucks
      if not found? [
        if any? firetrucks with [
          (phase = "to-victim" or phase = "rescuing") and distance me < word-of-mouth-radius
        ] [ set found? true ]
      ]
      ; Check proximity to already-evacuated residents
      if not found? [
        if any? residents with [ evacuated? = true and distance me < word-of-mouth-radius ]
        [ set found? true ]
      ]
      ; Check proximity to already-evacuated pedestrians
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
            ; Word-of-mouth Rayleigh sigma: intermediate (less reliable than radio/app)
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
    ; Peer-to-peer propagation: alerted residents spread alert to close neighbors
    ask residents with [ alert-received? = true and evacuated? = false ] [
      let me self
      ask residents with [
        alert-received? = false and evacuated? = false and
        distance me < (word-of-mouth-radius * 0.5)  ; Reduced radius for peer-to-peer
      ] [
        if random-float 1 < 0.40 [   ; 40% chance of successful transmission
          set alert-received? true
          set alert-channel "word-of-mouth"
          set cum-wom-alerts cum-wom-alerts + 1
          if decision = 2 [
            let fc [floodClass] of patch-here
            if random-float 1 < 0.50 [
              set decision 1  set color brown
              let sigma-sec 10 * 60   ; Longer sigma for secondary propagation
              let raw-time (rayleigh-sample sigma-sec) / tick_to_sec
              set miltime max list 1 (ticks + raw-time)
              set wait-start-tick -1
            ]
          ]
        ]
      ]
    ]
  ]

  ; --- FIRETRUCK PROXIMITY ALERT ---
  ; Residents automatically alerted when a firetruck passes nearby
  ; High switch-to-evacuation probability (visual urgency cue)
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
            ; Firetruck proximity Rayleigh sigma: very short (urgency perceived directly)
            let sigma-sec ifelse-value (fc >= 3) [ 2 * 60 ] [ 5 * 60 ]
            let raw-time (rayleigh-sample sigma-sec) / tick_to_sec
            set miltime max list 1 (ticks + raw-time)
            set wait-start-tick -1
            set claimed-victims remove who claimed-victims
          ]
        ]
        if decision = 1 and miltime > ticks [
          set miltime max list ticks (miltime * 0.45) ]  ; Strong time compression
      ]
    ]
  ]
end

; Dynamically updates decisions of waiting residents (decision=2) based on:
; - Observed increase in local flood class
; - Proximity to evacuated neighbors
to update-resident-decisions
  ask residents with [ decision = 2 and evacuated? = false ] [
    let fc-now [floodClass] of patch-here
    let trigger? false
    ; Flood class has increased since last tick → potential trigger
    if fc-now > prev-flood-class [ set trigger? true ]
    ; Nearby evacuated residents → social influence trigger
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

; Checks whether the shelter assigned to a firetruck's drop-off is over capacity.
; If so, reroutes the truck to the nearest available unsaturated shelter.
to check-shelter-saturation-reroute
  ask firetrucks with [
    phase = "to-drop" and drop_post != nobody and current_int != nobody
  ] [
    let current-load [evacuee_count] of drop_post
    if current-load > shelter-max-capacity [
      ; Find an unsaturated, flood-free shelter
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
            output-print (word "Truck " who " -> shelter saturated (" current-load
              ") redirected to shelter " [who] of new-shelter)
          ]
        ]
      ]
    ]
  ]
end

; Checks whether the mean access time has exceeded the trigger threshold.
; If so, automatically activates reinforcements (A3-related logic).
to check-access-time-trigger-reinforcements
  if reinforcement-activated [ stop ]
  if empty? access-times [ stop ]
  let current-mean mean access-times
  if current-mean > access-time-reinforce-threshold [
    set reinforcement-activated true
    set cum-access-triggered-reinforcements cum-access-triggered-reinforcements + 1
    output-print "========================================="
    output-print "AUTO REINFORCEMENT (ACCESS TIME THRESHOLD)"
    output-print (word "Mean access time : " precision current-mean 1 " min")
    output-print (word "Threshold        : " access-time-reinforce-threshold " min")
    output-print (word "Triggered at     : " precision time-min 1 " min")
    output-print "========================================="
  ]
end

; Updates all accessibility and network metrics used by the A3 priority index:
; - pct-network-accessible: share of roads still operational
; - isolated-victims-count: victims unreachable from any fire station
; - mean-rescue-delay: mean of recorded access times
; - accessibility-index: composite indicator (0–100)
to update-accessibility-metrics
  if count roads = 0 [ stop ]
  ; Accessible roads: capacity >= 30% and not saturated
  let accessible-roads roads with [
    road-capacity-factor >= 0.3 and crowd < saturation-threshold ]
  set pct-network-accessible precision (100 * count accessible-roads / count roads) 1

  ; Count victims unreachable by any fire station
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
      set color magenta ]   ; Highlight isolated victims in magenta
  ]

  ; Mean rescue delay from recorded access times
  ifelse not empty? access-times
    [ set mean-rescue-delay precision mean access-times 2 ]
    [ set mean-rescue-delay 0 ]

  ; Composite accessibility index — penalized by isolated victims, network state,
  ; rescue delay, shelter saturation; boosted by alert coverage
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
  let comm-bonus min list 5 (pct-alerted * 0.05)   ; Communication coverage boosts index
  set accessibility-index precision
    (max list 0 (100 - penalty-isolated - penalty-network
                     - penalty-delay   - penalty-shelters + comm-bonus)) 1
end

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; STATE MARKERS (EVACUATION & RESCUE)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; Marks an agent as self-evacuated (no firetruck involvement).
; Updates cumulative counters, records evacuation time, and updates shelter count.
to mark-evacuated
  if evacuated? = false [
    if is-pedestrian? self [ set cum_self_evacuated cum_self_evacuated + 1 ]
    if is-resident? self [
      if rescued-by-firefighters? = false [ set cum_self_evacuated cum_self_evacuated + 1 ] ]
    if is-car-driver? self [ set cum_self_evacuated cum_self_evacuated + 1 ]
    set evacuated? true  set moving? false  set color turquoise
    set ev_times lput ((ticks * tick_to_sec) / 60) ev_times   ; Record time in minutes
    if is-turtle? current_int [ ask current_int [ set evacuee_count evacuee_count + 1 ] ]
  ]
end

; Marks an agent as rescued by a firetruck.
; Updates cumulative rescue counters, releases claimed status, and reduces local crowd.
to mark-rescued
  if evacuated? = false [
    set cum_rescued cum_rescued + 1
    set cum-trucks-delivered cum-trucks-delivered + 1
    set evacuated? true  set moving? false
    set rescued-by-firefighters? true  set color turquoise
    set ev_times lput ((ticks * tick_to_sec) / 60) ev_times
    if is-turtle? current_int [ ask current_int [ set evacuee_count evacuee_count + 1 ] ]
    set claimed-victims remove who claimed-victims
    ; Release crowd contribution from nearby roads
    let mx xcor  let my ycor
    ask roads with [
      sqrt ((mid-x - mx) ^ 2 + (mid-y - my) ^ 2) < 3 and crowd > 0
    ] [ set crowd max list 0 (crowd - 1) ]
  ]
end

; Initializes metric globals to their safe default values at setup
to setup-init-val
  set accessibility-index 100
  set mean-rescue-delay 0
  set isolated-victims-count 0
  set pct-network-accessible 100
end


; Updates visual display of all evacuation agents each tick.
; Evacuated agents are hidden; active agents show red square in flood, brown dot otherwise.
to update-agent-colors
  ask residents with [ evacuated? = true ] [
    set color turquoise
    hide-turtle   ; Evacuated agents are removed from view
  ]
  ask pedestrians with [ evacuated? = true ] [
    set color turquoise
    hide-turtle
  ]
  ask residents with [ evacuated? = false ] [
    ifelse [depth] of patch-here > 0 [
      set color red
      set shape "square"
      set size 1.4   ; Compact size for flood zone residents
    ] [
      set color brown
      set shape "dot"
      set size 2
    ]
    show-turtle
  ]
  ask pedestrians with [ evacuated? = false ] [
    ifelse [depth] of patch-here > 0 [
      set color red
      set shape "square"
      set size 1.4
    ] [
      set color brown
      set shape "dot"
      set size 2
    ]
    show-turtle
  ]
end


; Final display pass at simulation end (t = 60 min):
; - Non-evacuated agents in flood zones shown as red squares
; - Flooded roads shown as orange
; - Parent agents hidden
to finalize-display
  ask (turtle-set
    residents   with [ evacuated? = false and [floodClass] of patch-here >= 1 ]
    pedestrians with [ evacuated? = false and [floodClass] of patch-here >= 1 ]) [
    set color red  set shape "square"  set size 1.4  show-turtle ]
  ask roads [
    let mid-p patch mid-x mid-y
    if mid-p != nobody [
      if [depth] of mid-p > 0 [ set color orange ]
    ]
  ]
  ask parents [ hide-turtle ]
end


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; GIS DATA LOADING
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; Loads all GIS datasets and sets up the coordinate transformation from world to NetLogo space.
; Also computes the patch_to_meter, tick_to_sec, fd_to_mps, and fd_to_kph conversion factors.
to read-gis-files
  set shelter_locations       gis:load-dataset "shelter_locations.shp"
  set road_network            gis:load-dataset "road_network.shp"
  set population_distribution gis:load-dataset "population_distribution.shp"
  set cis_dataset             gis:load-dataset "cis_bezons.shp"
  set tsunami_sample          gis:load-dataset "flood.asc"
  set ecoles_dataset          gis:load-dataset "Ecole_ZIP.shp"
  set entreprises_dataset     gis:load-dataset "Entreprises_ZIP.shp"

  ; Compute bounding box as the union of all dataset envelopes
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

  ; patch_to_meter: real-world size of one patch (~5 m based on GIS extent)
  ; tick_to_sec   : one tick = 60 seconds
  ; fd_to_mps     : patches/tick → m/s  = patch_to_meter / tick_to_sec
  ;   Example: pedestrian at 1.2 m/s → speed = 1.2 / fd_to_mps = 1.2 × 60 / patch_to_meter
  ;   If patch_to_meter = 5 m → speed = 14.4 patches/tick
  ; fd_to_kph     : patches/tick → km/h = fd_to_mps × 3.6
  ;   Example: firetruck at 30 km/h (degraded urban crisis speed)
  ;   → speed = 30 / fd_to_kph
  ;   If patch_to_meter = 5 m → speed ≈ 6.94 patches/tick
  set patch_to_meter max (list (world_width / netlogo_width) (world_height / netlogo_height))
  set tick_to_sec 60.0
  set fd_to_mps patch_to_meter / tick_to_sec
  set fd_to_kph fd_to_mps * 3.6
end

; Loads the road network from the GIS shapefile.
; Creates intersection nodes and directed road links based on the DIRECTION attribute.
to load-network
  ask intersections [ die ]
  ask roads [ die ]
  foreach gis:feature-list-of road_network [ i ->
    let direction gis:property-value i "DIRECTION"   ; Road directionality attribute
    foreach gis:vertex-lists-of i [ j ->
      let prev -1
      foreach j [ k ->
        if length (gis:location-of k) = 2 [
          let x item 0 gis:location-of k
          let y item 1 gis:location-of k
          let curr 0
          ; Reuse existing intersection at this location, or create a new one
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
          ; Create directed road link(s) between consecutive vertices
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
  ; Initialize road properties
  ask roads [
    set color black  set thickness 0.05
    set mid-x mean [xcor] of both-ends
    set mid-y mean [ycor] of both-ends
    set traffic 0  set crowd 0  set crowd-density 0
    set road-capacity-factor 1.0
  ]
  output-print "Network Loaded"
end

; Returns true if the given heading is consistent with the specified direction constraint
to-report is-heading-right? [link_heading direction]
  if direction = "north"   [ if abs(subtract-headings   0 link_heading) <= 90 [ report true ] ]
  if direction = "east"    [ if abs(subtract-headings  90 link_heading) <= 90 [ report true ] ]
  if direction = "south"   [ if abs(subtract-headings 180 link_heading) <= 90 [ report true ] ]
  if direction = "west"    [ if abs(subtract-headings 270 link_heading) <= 90 [ report true ] ]
  if direction = "two-way" [ report true ]
  report false
end

; Loads shelter locations from GIS and marks the nearest intersections.
; TYPE attribute determines shelter type: "ver" → vertical, otherwise → horizontal.
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
  set cached-shelters intersections with [ shelter? ]   ; Cache for performance
end


; Loads schools and workplaces from GIS datasets.
; Assigns unique intersections to each, avoiding duplicates.
; Falls back to default random assignment if datasets are empty.
to load-schools-workplaces
  ask intersections [ set school? false  set workplace? false ]
  let nb-schools-loaded 0
  let used-nodes-school []
  foreach gis:feature-list-of ecoles_dataset [ i ->
    let loc gis:location-of gis:centroid-of i
    if not empty? loc [
      let x item 0 loc  let y item 1 loc
      let candidate min-one-of intersections with [
        not member? self used-nodes-school ] [ distancexy x y ]
      if candidate != nobody [
        ask candidate [
          set school? true
          set shape "circle"   ; Initial display: yellow circle (same as shelter)
          set color yellow
          set size 3
        ]
        set used-nodes-school lput candidate used-nodes-school
        set nb-schools-loaded nb-schools-loaded + 1
      ]
    ]
  ]
  ; Fallback: assign 5 random non-shelter intersections if no schools were loaded
  if nb-schools-loaded = 0 [
    let all-ints intersections with [ not shelter? ]
    if any? all-ints [
      ask n-of (min list 5 count all-ints) all-ints [
        set school? true  set shape "circle"  set color yellow  set size 3 ]
    ]
  ]

  let nb-workplaces-loaded 0
  let used-nodes-wp []
  foreach gis:feature-list-of entreprises_dataset [ i ->
    let loc gis:location-of gis:centroid-of i
    if not empty? loc [
      let x item 0 loc  let y item 1 loc
      let candidate min-one-of intersections with [
        not member? self used-nodes-wp ] [ distancexy x y ]
      if candidate != nobody [
        ask candidate [
          set workplace? true
          set shape "square"
          set color orange    ; Initial display: orange square
          set size 1.5
        ]
        set used-nodes-wp lput candidate used-nodes-wp
        set nb-workplaces-loaded nb-workplaces-loaded + 1
      ]
    ]
  ]
  ; Fallback: assign 8 random non-shelter/non-school intersections
  if nb-workplaces-loaded = 0 [
    let all-ints intersections with [ not shelter? and not school? ]
    if any? all-ints [
      ask n-of (min list 8 count all-ints) all-ints [
        set workplace? true  set shape "square"  set color orange  set size 1.5 ]
    ]
  ]
  set cached-schools    intersections with [ school?    ]
  set cached-workplaces intersections with [ workplace? ]
  output-print (word "Schools: " count cached-schools
    " | Workplaces: " count cached-workplaces)
end


; Loads fire station locations from GIS.
; If fewer than 3 stations are found, creates supplementary stations near flood zones.
; Supplementary stations are shown in orange and hidden until reinforcements are activated.
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
  ; Ensure at least 3 fire stations exist — create orange supplementary posts if needed
  if count firestations < 3 [
    let candidate-shelters intersections with [
      shelter? = true and [waterDepth] of patch-here = 0 and
      not any? firestations with [ distance myself < 5 ]
    ]
    if any? candidate-shelters [
      let n-needed 3 - count firestations
      let flood-p patches with [ waterDepth > 0 ]
      let chosen nobody
      ; Prefer shelter nodes closest to the flood zone
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
  ; Initialize access time monitors for the first 3 stations
  set temps-acces-caserne-1 0
  set temps-acces-caserne-2 0
  set temps-acces-caserne-3 0
  ; Supplementary (orange) stations start hidden until reinforcements are activated
  ask firestations with [ color = orange ] [ hide-turtle ]
  output-print (word "Fire stations: " count firestations)
end


; Updates the visual display of schools and workplaces based on flood presence:
; - Workplaces: orange square → green square when flooded
; - Schools: yellow circle → yellow triangle when flooded
to update-schools-workplaces-display
  ask cached-workplaces [
    ifelse depth > 0
      [ set color green  ]
      [ set color orange ]
  ]
  ask cached-schools [
    ifelse depth > 0
      [ set shape "triangle" ]
      [ set shape "circle"   ]
  ]
end


; Selects the highest-priority victim from a pool based on the accessibility index (A3).
; If A3 is active and the index is low, isolated (magenta) or high-risk (floodClass >= 3) victims
; are prioritized over the nearest victim.
to-report pick-priority-victim [ pool src ]
  if not any? pool [ report nobody ]
  ifelse a3-priority-index? [
    ifelse accessibility-index < 50 and any? pool with [ color = magenta ] [
      ; Critical state: prioritize isolated victims
      set cum-index-driven-prioritizations cum-index-driven-prioritizations + 1
      report min-one-of (pool with [ color = magenta ]) [ distance src ]
    ] [
      ifelse accessibility-index < 70
             and any? pool with [ [floodClass] of patch-here >= 3 ] [
        ; Degraded state: prioritize severely flooded areas
        set cum-index-driven-prioritizations cum-index-driven-prioritizations + 1
        report min-one-of (pool with [ [floodClass] of patch-here >= 3 ]) [ distance src ]
      ] [
        ; Normal state: nearest victim first
        report min-one-of pool [ distance src ]
      ]
    ]
  ] [
    report min-one-of pool [ distance src ]   ; A3 off: always nearest victim
  ]
end


; Dispatches new firetrucks from each active fire station to uncovered victims.
; Uses coverage-radius logic to avoid sending multiple trucks to the same area.
; Applies k-best-paths for robust routing and records claimed victims.
to dispatch-firetrucks
  let dispatch-orders []
  let coverage-radius 25   ; Spatial coverage radius — adjust based on map scale

  ask firestations [
    let station self
    if any? firetrucks with [ distance station < 0.5 ] [ stop ]   ; Station already has idle trucks

    ; Candidate victims: waiting residents and pedestrians not yet claimed
    let res-v residents   with [ decision = 2 and evacuated? = false
                                 and not member? who claimed-victims ]
    let ped-v pedestrians with [ decision = 2 and evacuated? = false
                                 and not member? who claimed-victims ]
    let victims (turtle-set res-v ped-v)
    if not any? victims [ stop ]

    ; Prioritize victims not already covered by a nearby truck
    let uncovered victims with [
      not any? firetrucks with [
        (phase = "to-victim" or phase = "rescuing") and
        target-resident != nobody and
        distance myself < coverage-radius
      ]
    ]
    ; If all victims are covered, still dispatch to the nearest one
    let target-pool ifelse-value (any? uncovered) [ uncovered ] [ victims ]

    let victim pick-priority-victim target-pool station
    if victim != nobody and a3-priority-index? and ticks mod 30 = 0 [
      output-print (word "INDEX-DRIVEN dispatch: index=" accessibility-index
        " -> victim #" [who] of victim) ]
    if victim = nobody [ stop ]

    let src min-one-of intersections [ distance station ]
    let tgt min-one-of intersections [ distance victim  ]
    if (src = nobody) or (tgt = nobody) [ stop ]

    ; Compute up to 5 alternative routes for robust dispatching
    let alternatives k-best-paths-truck src tgt 5
    if empty? alternatives [
      let foot-route Astar-truck src tgt (turtle-set tgt)
      if not empty? foot-route [ set alternatives (list foot-route) ]
    ]
    ; Emergency fallback: route to nearest dry intersection near victim
    if empty? alternatives [
      let near-dry min-one-of intersections with [
        [floodClass] of patch-here <= 1 ] [ distance tgt ]
      if near-dry != nobody and near-dry != src [
        let relay-route Astar-truck src near-dry (turtle-set near-dry)
        if not empty? relay-route [ set alternatives (list relay-route) ]
      ]
    ]

    let chosen ifelse-value (not empty? alternatives)
               [ best-of-k-routes alternatives ] [ [] ]

    set dispatch-orders lput (list src tgt victim alternatives chosen [id] of station)
                             dispatch-orders
    set claimed-victims lput ([who] of victim) claimed-victims
  ]

  ; Dispatch from reinforcement posts covering remote flooded areas
  if reinforcement-activated and any? reinforcement_posts [
    ask reinforcement_posts [
      let post self
      let res-r residents   with [ decision = 2 and evacuated? = false
                                   and not member? who claimed-victims ]
      let ped-r pedestrians with [ decision = 2 and evacuated? = false
                                   and not member? who claimed-victims ]
      let rv (turtle-set res-r ped-r)
      if any? rv [
        let local-uncovered rv with [
          not any? firetrucks with [
            (phase = "to-victim" or phase = "rescuing") and
            target-resident != nobody and
            distance myself < coverage-radius
          ]
        ]
        if any? local-uncovered [
          let v min-one-of local-uncovered [ distance post ]
          let src min-one-of intersections [ distance post ]
          let tgt min-one-of intersections [ distance v ]
          if (src != nobody) and (tgt != nobody) [
            let alts k-best-paths-truck src tgt 5
            if empty? alts [
              let fr Astar-truck src tgt (turtle-set tgt)
              if not empty? fr [ set alts (list fr) ]
            ]
            if not empty? alts [
              let chosen best-of-k-routes alts
              if not empty? chosen [
                set claimed-victims lput ([who] of v) claimed-victims
                set dispatch-orders lput (list src tgt v alts chosen 0)
                                         dispatch-orders
              ]
            ]
          ]
        ]
      ]
    ]
  ]

  ; Create firetruck agents from dispatch orders (observer context)
  foreach dispatch-orders [ order ->
    let src    item 0 order
    let tgt    item 1 order
    let victim item 2 order
    let alts   item 3 order
    let chosen item 4 order
    let sid    item 5 order

    create-firetrucks 1 [
      set color red  set shape "car"  set size 2.5
      set moving? false
      set speed (max_speed_firefighters / fd_to_kph)   ; Convert km/h to patches/tick
      set capacity 3  set cargo []
      set current_int src  move-to src
      set home_post src  set firetruck-station-id sid
      set alt-paths alts  set current-route-idx 0
      set reroute-cooldown 0  set priority-mode? false
      set prev-path []  set alert-received? false  set alert-channel "none"
      ; Find nearest unsaturated shelter for drop-off
      let shelters cached-shelters with [ evacuee_count < shelter-max-capacity ]
      if not any? shelters [ set shelters cached-shelters ]
      if any? shelters [ set drop_post min-one-of shelters [ distance src ] ]
      if drop_post = nobody [ set drop_post src ]
      set phase "to-victim"  set rescue_time 45
      set target-resident victim  set target_int tgt
      set path chosen  set dispatch-tick ticks
    ]
  ]
end



; Records the access time for a specific fire station after a truck reaches its victim.
; sid: station ID (1, 2, or 3); elapsed-min: time in minutes since dispatch.
to record-access-time [ sid elapsed-min ]
  set access-times lput elapsed-min access-times
  if sid = 1 [ set temps-acces-caserne-1 precision elapsed-min 2 ]
  if sid = 2 [ set temps-acces-caserne-2 precision elapsed-min 2 ]
  if sid = 3 [ set temps-acces-caserne-3 precision elapsed-min 2 ]
end

; ================================================================
; FIRETRUCK SPEED FACTOR BASED ON FLOOD DEPTH
; ================================================================
; Calibrated on operational flood-response practices:
;   depth = 0 m    → factor 1.00 — normal speed
;   depth ≤ 0.3 m  → factor 1.00 — minimal disruption
;   depth ≤ 0.5 m  → factor 0.50 — progressive loss of control (~50% speed)
;   depth ≤ 0.6 m  → factor 0.20 — very difficult movement (~20% speed)
;   depth > 0.6 m  → factor 0.05 — vehicle effectively immobilized;
;                                   crews continue on foot with water-rescue equipment
;                                   (residual factor = mission continuity)
to-report firetruck-depth-factor [ local-depth ]
  report ifelse-value (local-depth > 0.6) [ 0.05 ]
    [ ifelse-value (local-depth > 0.5) [ 0.20 ]
      [ ifelse-value (local-depth > 0.3) [ 0.50 ]
        [ 1.0 ] ] ]
end


; Handles a single movement step for a firetruck (shared by to-victim and to-drop phases).
; If the road ahead is fully blocked (cap=0), the truck continues at a forced minimum speed.
; Speed is scaled by the depth factor at the current patch.
to firetruck-move-step
  if next_int = nobody [ stop ]
  let nxt next_int
  if [out-road-neighbor? nxt] of current_int [
    let r road [who] of current_int [who] of nxt
    if r != nobody [
      let cap [road-capacity-factor] of r
      if cap <= 0 [
        ; Road is fully blocked: truck forces through at minimum speed (on-foot mode)
        let local-depth [depth] of patch-here
        let depth-factor firetruck-depth-factor local-depth
        let forced-step max list 0.005 (speed * depth-factor)
        if forced-step > distance next_int [ set forced-step distance next_int ]
        fd forced-step
        set color blue  set size 3.5  show-turtle   ; Visual indicator: truck forcing through
        if a4-traffic-management? and firetruck-priority-enabled? and priority-mode? [
          set cum-priority-passages cum-priority-passages + 1 ]
        if distance next_int < 0.05 [
          move-to next_int  set current_int next_int
          set moving? false  set color red  set size 2.5 ]
        stop
      ]
    ]
  ]
  ; Normal movement with depth-based speed reduction
  let local-depth [depth] of patch-here
  let depth-factor firetruck-depth-factor local-depth
  if local-depth > 0.3 [ set cum-speed-reductions cum-speed-reductions + 1 ]
  let real-step max list 0.01 (speed * depth-factor)
  if real-step > distance next_int [ set real-step distance next_int ]
  fd real-step
  if distance next_int < 0.05 [
    move-to next_int  set current_int next_int
    set moving? false  set color red  set size 2.5 ]
end



; Main firetruck movement procedure — handles all phases:
; "to-victim": navigating to the assigned victim
; "rescuing": performing the rescue operation
; "to-drop": transporting victims to a shelter
; "returning": returning to the home post after drop-off
to move-firetrucks
  ask firetrucks [
    ; Defensive initialization of list/numeric properties
    if not is-list? cargo     [ set cargo [] ]
    if not is-list? alt-paths [ set alt-paths [] ]
    if (not is-number? capacity) or (capacity <= 0) [ set capacity 3 ]

    ; Assign a new target if none is set
    if target-resident = nobody [
      firetruck-assign-new-target
      if target-resident = nobody [ stop ]
    ]
    ; Release target if victim has already been evacuated
    if [evacuated?] of target-resident = true [
      if target-resident != nobody [
        set claimed-victims remove ([who] of target-resident) claimed-victims ]
      set target-resident nobody
      firetruck-assign-new-target
      stop
    ]

    ; --- PHASE: TO-VICTIM ---
    if phase = "to-victim" [
      if empty? path [
        ; Path is empty: try foot-mode A* as a fallback
        if target-resident != nobody [
          let my-target target-resident
          let tgt min-one-of intersections [ distance my-target ]
          if tgt != nobody [
            let foot-route Astar-foot current_int tgt (turtle-set tgt)
            if not empty? foot-route [
              set path foot-route
              set color blue
              stop
            ]
          ]
        ]
        if target-resident = nobody [ firetruck-assign-new-target  stop ]
        ; Direct movement as last resort if no path found
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
        ; Truck has reached victim: record access time and begin rescue
        let elapsed precision (((ticks - dispatch-tick) * tick_to_sec) / 60) 2
        record-access-time firetruck-station-id elapsed
        set phase "rescuing"  set moving? false
        stop
      ]
      ; Skip intersections already passed
      while [ (not empty? path) and (intersection item 0 path = current_int) ] [
        set path remove-item 0 path ]
      if empty? path [ stop ]
      ; Set heading toward next intersection
      if not moving? [
        set next_int intersection item 0 path
        set path remove-item 0 path
        if next_int != nobody [
          ifelse distance next_int > 0 [
            set heading towards next_int  set moving? true
          ] [ move-to next_int  set current_int next_int  set moving? false ]
        ]
      ]
      if moving? [ firetruck-move-step ]
      stop
    ]


    ; --- PHASE: RESCUING ---
    if phase = "rescuing" [
      if rescue_time > 0 [ set rescue_time rescue_time - tick_to_sec  stop ]  ; Wait for rescue to complete
      let v target-resident
      if v != nobody [
        if [evacuated?] of v = false [
          if not is-list? cargo [ set cargo [] ]
          set cargo lput v cargo          ; Load victim onto truck
          ask v [
            set rescued-by-firefighters? true  set evacuated? true
            set moving? false  hide-turtle
            set claimed-victims remove who claimed-victims
          ]
        ]
      ]
      set rescue_time 45  set target-resident nobody
      ; If cargo is full, head to drop-off shelter
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
          ; No route found: drop victims at current location
          foreach cargo [ vv ->
            if is-turtle? vv [ ask vv [ show-turtle  mark-rescued ] ] ]
          set cargo []  firetruck-assign-new-target  stop
        ]
        set path return-route  set alt-paths return-routes
        set phase "to-drop"  set moving? false
        stop
      ]
      ; Cargo not full: look for another victim
      firetruck-assign-new-target
      stop
    ]

    ; --- PHASE: TO-DROP ---
    if phase = "to-drop" [
      if empty? path [
        ; Arrived at shelter: unload all passengers
        let drop drop_post
        foreach cargo [ vv ->
          if is-turtle? vv [
            if [evacuated?] of vv = false [
              ask vv [
                show-turtle
                if drop != nobody [ move-to drop  set current_int drop  set color turquoise ]
                mark-rescued
              ]
            ]
          ]
        ]
        set cargo []  set rescue_time 45  set target-resident nobody
        ; After drop-off, return to home post if needed
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
      if moving? [ firetruck-move-step ]
      stop
    ]


    ; --- PHASE: RETURNING ---
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
          ; Check if the road ahead is blocked — stop and reset path if so
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
            ; Arrived at home post: ready for next dispatch
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



; Assigns a new rescue target to a firetruck that has completed its current mission.
; Tries to find a reachable victim using k-best-paths-truck.
; Falls back to foot-mode routing and relay routing if no direct path is found.
; Records the truck as "blocked" if no route is available.
to firetruck-assign-new-target
  if target-resident != nobody [
    set claimed-victims remove ([who] of target-resident) claimed-victims ]

  ; Candidate victims: unclaimed waiting agents
  let res-base residents   with [ decision = 2 and evacuated? = false and not member? who claimed-victims ]
  let ped-base pedestrians with [ decision = 2 and evacuated? = false and not member? who claimed-victims ]
  let base-victims (turtle-set res-base ped-base)

  ; Fallback: all waiting agents (ignore claims) if no unclaimed victims
  if not any? base-victims [
    let res-all residents   with [ decision = 2 and evacuated? = false ]
    let ped-all pedestrians with [ decision = 2 and evacuated? = false ]
    set base-victims (turtle-set res-all ped-all)
  ]
  if not any? base-victims [
    ; No victims left: truck is idle
    set target-resident nobody  set target_int nobody
    set path []  set alt-paths []  set moving? false  stop
  ]
  ; Ensure the truck has a valid current intersection
  if current_int = nobody [
    set current_int min-one-of intersections [ distance myself ]
    if current_int = nobody [ stop ]
    move-to current_int
  ]

  ; Build a small pool of 3 candidate victims and try each one
  let src current_int
  let n min (list 3 count base-victims)
  let pool nobody
  let best-v pick-priority-victim base-victims self
  set pool ifelse-value (best-v != nobody)
    [ min-n-of n base-victims [ distance myself ] ]
  [ no-turtles ]

  let pool-list shuffle sort pool
  set target-resident nobody  set target_int nobody
  set path []  set alt-paths []  set moving? false

  foreach pool-list [ v ->
    if target-resident = nobody [
      let tgt min-one-of intersections [ distance v ]
      if tgt != nobody [
        let alternatives k-best-paths-truck src tgt 5
        if empty? alternatives [
          let foot-route Astar-truck src tgt (turtle-set tgt)
          if not empty? foot-route [ set alternatives (list foot-route) ]
        ]
        ; Relay via nearest dry intersection if still no path found
        if empty? alternatives [
          let near-dry min-one-of intersections with [
            [floodClass] of patch-here <= 1 ] [ distance tgt ]
          if near-dry != nobody and near-dry != src [
            let foot-route2 Astar-truck src near-dry (turtle-set near-dry)
            if not empty? foot-route2 [ set alternatives (list foot-route2) ]
          ]
        ]
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
  ; Truck is blocked if no valid path could be computed
  if target-resident = nobody [
    set nb-camions-bloques nb-camions-bloques + 1
    set color red + 3   ; Darker red to signal blocked truck
  ]
end



; Continuously monitors all active firetrucks (to-victim and to-drop phases).
; If congestion is detected ahead, computes alternative routes and reroutes if a
; significant improvement is found. Also performs periodic route refreshes.
to continuous-reroute-firetrucks
  ask firetrucks with [
    (phase = "to-victim" or phase = "to-drop") and
    length path >= 2 and current_int != nobody and reroute-cooldown <= 0
  ] [
    if firetruck-detects-congestion? path [
      let dest ifelse-value (phase = "to-victim") [ target_int ] [ drop_post ]
      if dest != nobody [
        let new-alts k-best-paths-truck current_int dest 5
        if not empty? new-alts [
          let new-best best-of-k-routes new-alts
          if not empty? new-best and new-best != path [
            let old-score route-score path
            let new-score route-score new-best
            ; Urgency level: 0–3 based on congestion + victim flood depth
            let urgency-level 0
            if firetruck-detects-congestion? path [ set urgency-level urgency-level + 1 ]
            if target-resident != nobody [
              let victim-depth [depth] of patch
                (int [xcor] of target-resident)
                (int [ycor] of target-resident)
              if victim-depth > 0.5 [ set urgency-level urgency-level + 1 ]
              if victim-depth > 1.0 [ set urgency-level urgency-level + 1 ]
            ]
            ; A3: lower the gain threshold when accessibility index is degraded
            let index-factor ifelse-value a3-priority-index? [
              ifelse-value (accessibility-index < 40) [ 0.80 ]
                [ ifelse-value (accessibility-index < 70) [ 0.90 ] [ 0.95 ] ]
            ] [ 0.95 ]
            let gain-threshold ifelse-value (urgency-level >= 2)
              [ index-factor * 0.90 ] [ index-factor ]
            if new-score < old-score * gain-threshold [
              set prev-path path
              broadcast-congestion-signal prev-path true     ; Warn other agents of old route
              civilian-react-to-truck-reroute prev-path      ; Trigger civilian reaction
              broadcast-congestion-signal new-best false     ; Signal improvement on new route
              set path      new-best
              set alt-paths new-alts
              set cum-reroutes cum-reroutes + 1
              set color pink   ; Visual indicator: truck is rerouting
              ; Activate priority mode for high-urgency reroutes (A4)
              if a4-traffic-management? and firetruck-priority-enabled? and urgency-level >= 2 [
                set priority-mode? true
                set cum-priority-passages cum-priority-passages + 1
              ]
              ; Cooldown duration depends on urgency
              let new-cooldown ifelse-value (urgency-level >= 3) [ 1 ]
                [ ifelse-value (urgency-level = 2) [ 2 ]
                  [ ifelse-value (urgency-level = 1) [ 4 ] [ 6 ] ] ]
              set reroute-cooldown new-cooldown
            ]
          ]
        ]
      ]
    ]
    ; Periodic fresh route refresh regardless of congestion detection
    if ticks mod reroute-refresh-interval = 0 [
      let dest ifelse-value (phase = "to-victim") [ target_int ] [ drop_post ]
      if dest != nobody [
        let fresh-alts k-best-paths-truck current_int dest 5
        if not empty? fresh-alts [
          set alt-paths fresh-alts
          let current-score route-score path
          let best-fresh    best-of-k-routes fresh-alts
          let fresh-score   route-score best-fresh
          if fresh-score < current-score * 0.90 [   ; Only reroute if at least 10% improvement
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
  ; Decrement reroute cooldown and restore color when cooldown expires
  ask firetrucks with [ reroute-cooldown > 0 ] [
    set reroute-cooldown reroute-cooldown - 1
    if reroute-cooldown = 0 [ set color red  set priority-mode? false ]
  ]
end



; Sets up the list of reinforcement dispatch posts.
; Priority: orange supplementary fire stations → shelters near flood zone → random shelters.
to setup-reinforcement-posts
  let temp-stations firestations with [ color = orange ]
  ifelse any? temp-stations [
    ; Use supplementary station locations as reinforcement posts
    let renfort-posts []
    ask temp-stations [
      let nearest min-one-of intersections [ distance myself ]
      if nearest != nobody [ set renfort-posts lput nearest renfort-posts ]
    ]
    set reinforcement_posts turtle-set renfort-posts
  ] [
    ; No orange stations: place posts at shelters closest to flood zone
    let flood-patches patches with [ waterDepth > 0 ]
    if not any? flood-patches [
      ; No flood data yet: use up to 24 shelter intersections
      set reinforcement_posts (turtle-set n-of
        (min list 24 count intersections with [ shelter? ])
        intersections with [ shelter? ])
      stop
    ]
    let shelters intersections with [ shelter? ]
    if count shelters <= 24 [ set reinforcement_posts shelters  stop ]
    ; Rank shelters by proximity to flood zone and take the 24 closest
    ask shelters [
      let d min [ distance myself ] of flood-patches
      set fscore d
    ]
    set reinforcement_posts (turtle-set min-n-of 24 shelters [ fscore ])
  ]
end


; Dispatches reinforcement firetrucks from reinforcement posts.
; Activates automatically if main station trucks are overwhelmed and time threshold is reached.
; Sends one truck per available post (up to reinforcement_batch_size) every interval.
to dispatch-reinforcements
  ; Auto-activate if main station is busy and time threshold is met
  if not reinforcement-activated [
    let main-trucks count firetrucks with [
      firetruck-station-id = 1 and phase = "to-victim" ]
    if time-min >= reinforcement-trigger-min and main-trucks >= 2 [
      set reinforcement-activated true
      output-print (word "REINFORCEMENTS AUTO-ACTIVATED at " precision time-min 1 " min")
    ]
  ]
  if not reinforcement-activated [ stop ]
  if time-min < reinforcement_start_min [ stop ]
  if (ticks * tick_to_sec) mod reinforcement_interval_sec != 0 [ stop ]
  if reinforcement_posts = nobody or not any? reinforcement_posts [ stop ]

  ; Candidate victims for reinforcements
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
          ; Identify which supplementary station ID to assign
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

; Checks if car-drivers can still drive. If flood depth > 0.3 m,
; they are converted to pedestrian agents and continue on foot.
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
        ; Pedestrian speed: Ped_Speed [m/s] / fd_to_mps
        ; Example: 1.2 m/s × 60 s / 5 m = 14.4 patches/tick (normal conditions)
        set speed (Ped_Speed / fd_to_mps)
        set evacuated? false
        set rescued-by-firefighters? false
        set time_in_water my-tin  set max_depth_agent my-mdp
        set moving? false  set decision 1
        set alert-received? my-alert  set alert-channel my-channel
        ifelse empty? path [ set shelter -1 ] [ set shelter last path ]
      ]
      die   ; Car-driver agent is replaced by pedestrian
    ]
  ]
end

; Moves car-driver agents toward their destination.
; Stops if water depth exceeds 0.3 m (driver should have converted to pedestrian already).
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

; Creates bus agents assigned to collection points in flooded zones.
; Each bus follows a round-trip route: collect residents → drop at shelter → return.
to setup-bus-routes
  ask buses [ die ]
  if num-buses <= 0 [ stop ]
  if not any? cached-shelters [ stop ]
  ; Find candidate collection intersections in flood zones with nearby waiting residents
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
      set passengers-cargo []  set speed (30 / fd_to_kph)   ; 30 km/h bus speed
      set color green  set shape "car"  set size 3
      set moving? false  set next_int nobody
      set alert-received? false  set alert-channel "none"
    ]
  ]
  output-print (word "Buses created: " count buses)
end

; Manages bus movement and passenger collection/drop-off.
; Phase "collecting": boards nearby waiting residents until full or no more to pick up.
; Phase "to-shelter": drives to destination shelter, unloads passengers, returns.
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
      ; Transition to driving phase when full or no more local victims
      if length passengers-cargo >= capacity or
      not any? residents with [ decision = 2 and not evacuated? and distance myself < 10 ] [
        set phase "to-shelter"
        set path best-of-k-routes (k-best-paths current_int dest_int 3)
      ]
    ]
    if phase = "to-shelter" [
      if empty? path [
        ; At shelter: unload all passengers
        foreach passengers-cargo [ p ->
          if is-turtle? p [
            ask p [ show-turtle  move-to [current_int] of myself  mark-rescued ] ]
        ]
        set passengers-cargo []
        ; Return to home collection point
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

; Triggers a selected what-if scenario by modifying simulation state.
; Scenarios: late-alert, road-closure, shelter-overflow, comm-failure, fast-flood
to trigger-what-if-scenario
  if scenario-type = "late-alert" [
    ; Delay all resident reaction times by alert-delay-min
    let delay-ticks (alert-delay-min * 60 / tick_to_sec)
    ask residents [ set miltime miltime + delay-ticks ]
    output-print (word "WHAT-IF: alert delayed by " alert-delay-min " min.")
  ]
  if scenario-type = "road-closure" [
    ; Block the 3 most congested roads
    let main-roads max-n-of 3 roads [ crowd ]
    ask main-roads [ set road-capacity-factor 0.0  set color red ]
    output-print "WHAT-IF: 3 main roads blocked."
  ]
  if scenario-type = "shelter-overflow" [
    ; Close shelters that exceed the capacity percentage threshold
    ask cached-shelters [
      if evacuee_count > shelter-capacity-pct [
        set shelter? false  set color gray  set shape "x"
        output-print (word "Shelter " who " saturated - closed.")
      ]
    ]
    set cached-shelters intersections with [ shelter? ]
  ]
  if scenario-type = "comm-failure" [
    ; Disable all alert channels and clear routes for firetrucks
    ask firetrucks [ set alt-paths [] ]
    ask residents   [ set alert-received? false ]
    ask pedestrians [ set alert-received? false ]
    set alert-propagation-radius 0
    set radio-alert-fired? false  set app-alert-fired? false
    output-print "WHAT-IF: communication failure - all channels disabled."
  ]
  if scenario-type = "fast-flood" [
    ; Accelerate flood depth by 50% and reclassify all flood patches
    ask patches with [ floodClass >= 1 ] [
      set waterDepth waterDepth * 1.5
      ifelse waterDepth < 0.5 [ set floodClass 1 ] [
      ifelse waterDepth < 1.0 [ set floodClass 2 ] [
      ifelse waterDepth < 2.0 [ set floodClass 3 ] [ set floodClass 4 ]]]
    ]
    recolor-flood-classes-singleband
    output-print "WHAT-IF: accelerated flooding (+50%)."
  ]
end

; Runs a simple how-to optimization: randomly samples 10 candidate station configurations
; and selects the one minimizing mean distance from all waiting victims.
to run-how-to-optimization
  output-print "HOW-TO: searching for optimal configuration..."
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
        ask candidate-stations [ set color cyan  set size 4 ]   ; Highlight best config
      ]
    ]
  ]
  output-print (word "HOW-TO score: " precision best-score 2 " | Stations: " best-config)
end

; Activates reinforcement trucks and reveals supplementary fire stations on the map.
; Can be triggered manually via the interface button or automatically by the simulation.
to activate-reinforcements
  ifelse reinforcement-activated [ output-print "Reinforcements already active." ] [
    set reinforcement-activated true  set simulation-paused? false
    ask firestations with [ color = orange ] [ show-turtle ]   ; Show supplementary stations
    output-print (word "REINFORCEMENTS ACTIVATED at " precision time-min 1 " min.")
  ]
end


; Initializes flood data from the raster file.
; Sets all patch flood properties to zero — the flood is simulated progressively in 'go'.
to setup-flood-zip100
  set zip100-raster tsunami_sample
  ask patches [ set waterDepth 0  set floodClass 0  set depth 0  set prev-depth 0 ]
  gis:apply-raster zip100-raster waterDepth   ; Load maximum (final) flood depths
  ask patches [
    if not ((waterDepth <= 0) or (waterDepth >= 0)) [ set waterDepth 0 ] ]  ; Clean NaN values
  ; Flood class starts at 0 and water rises progressively over 60 minutes
  ask patches [ set floodClass 0  set pcolor white ]
  set flood-patches-cache patches with [ waterDepth > 0 ]
end

; Colors patches according to their flood class using a single-band blue palette
to recolor-flood-classes-singleband
  ask patches with [ floodClass = 0 ] [ set pcolor white ]
  ask patches with [ floodClass = 1 ] [ set pcolor rgb 195 232 251 ]   ; Light blue
  ask patches with [ floodClass = 2 ] [ set pcolor rgb  82 167 237 ]   ; Medium blue
  ask patches with [ floodClass = 3 ] [ set pcolor rgb  19 140 206 ]   ; Deep blue
  ask patches with [ floodClass = 4 ] [ set pcolor rgb   8  48 107 ]   ; Very deep blue
end

; Loads population from the GIS shapefile.
; Creates one resident agent per location point, assigns speed, decision flag, and initial destination.
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
            ; Walking speed: Ped_Speed [m/s] / fd_to_mps
            ; Recommended value: Ped_Speed = 1.2 m/s (normal walking pace)
            ; Example: if patch_to_meter = 5 m → speed = 1.2 × 60 / 5 = 14.4 patches/tick
            set speed (Ped_Speed / fd_to_mps)
            if speed < 0.001 [ set speed 0.001 ]
            set evacuated? false
            set rescued-by-firefighters? false
            set time_in_water 0  set max_depth_agent 0  set miltime 0
            set alert-received? false  set alert-channel "none"
            set prev-flood-class [floodClass] of patch-here
            make-decision
            if immediate_evacuation [ set miltime 0 ]   ; Force immediate start if enabled
          ]
        ]
      ]
    ]
  ]
  ; Defensive initialization: fix any incorrectly typed boolean/channel values
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

; Creates parent, worker, and relative agents to simulate civilian flows
; (e.g., parents going to pick up children, workers evacuating from offices).
to load-civilian-flows
  let dry-ints intersections with [ [floodClass] of patch-here = 0 and not shelter? ]
  ; Parent agents: from dry zone to school
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
  ; Worker agents: from workplace to nearest shelter
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
  ; Relative agents: from dry zone to workplace (to retrieve someone)
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
  output-print (word "Parents: " count parents " | Workers: " count workers
    " | Relatives: " count relatives)
end

; Moves a parent/worker/relative agent toward its destination.
; Immobilization probability when depth > 1.5 × Hc (pedestrian threshold).
; Marks mission-done? and dies when destination is reached.
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
    ; Hc = pedestrian discomfort threshold (default: 0.5 m)
    ; Above 1.5 × Hc: 5% chance of immobilization per tick
    ; Represents difficulties caused by flood water (stress, obstacles, loss of balance)
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

; Pre-computes horizontal shelter paths for all resident origin intersections.
; These paths are stored in hor-path and used when residents convert to pedestrians.
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
;; SETUP PHASES: LOAD 1 / 2 / 3
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; Phase 1: Initializes all globals, loads GIS data, network, shelters, and flood raster.
; Must be called first before load2 and load3.
to load1
  ca  clear-all-plots
  ask patches [ set pcolor white ]
  ; Reset all counters and state variables
  set ev_times []
  set cum_rescued 0  set cum_self_evacuated 0
  set reinforcement_start_min 1
  set reinforcement_interval_sec 20
  set reinforcement_batch_size 24
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
  set record-video? false

  ; Print active improvement configuration to output
  output-print "============================================"
  output-print (word "CONFIG: "
    ifelse-value a1-civilian-signal?    ["A1-ON "]["A1-OFF "]
    ifelse-value a2-shelter-saturation? ["A2-ON "]["A2-OFF "]
    ifelse-value a3-priority-index?     ["A3-ON "]["A3-OFF "]
    ifelse-value a4-traffic-management? ["A4-ON "]["A4-OFF "])
  output-print (word "SCENARIO: " scenario-type)
  output-print "============================================"

  setup-init-val
  read-gis-files
  load-network  load-shelters
  setup-flood-zip100
  ; Note: setup-reinforcement-posts is called in load3, after fire stations are loaded,
  ; ensuring waterDepth and orange station data are available.
  reset-timer  reset-ticks
end


; Phase 2: Loads population, assigns decisions, creates civilian flow agents,
; pre-computes shelter routes, sets up buses, and resets road state.
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


; Phase 3: Loads fire stations, sets up reinforcement posts, and triggers the what-if scenario.
; Must be called after load1 and load2.
to load3
  ask firestations [ die ]  ask firetrucks [ die ]
  load-firestations
  setup-reinforcement-posts
  trigger-what-if-scenario
  output-print "SETUP COMPLETE (3/3)!"
  ;Automatically starts video recording
  start-recording
  beep
end


; Initializes the "Firefighter Accessibility" plot axes and starting values
to init-accessibility-plot
  set-current-plot "Firefighter Accessibility"
  clear-plot
  set-plot-y-range 0 10
  set-current-plot-pen "Trucks Arrived"  plotxy 0 0
  set-current-plot-pen "Firefighter Rerouting"  plotxy 0 0
end

; Updates the accessibility plot with current cumulative delivery and rerouting counts
to update-accessibility-plot
  set-current-plot "Firefighter Accessibility"
  set-plot-y-range 0 (max list 1 (max list cum-trucks-delivered cum-reroutes))
  set-current-plot-pen "Trucks Arrived"
  set-plot-pen-mode 0  plotxy time-min cum-trucks-delivered
  set-current-plot-pen "Firefighter Rerouting"
  set-plot-pen-mode 0  plotxy time-min cum-reroutes
end

; Initializes the "Evacuation Progress" plot with y-range set to total population
to init-evacuation-plot
  set-current-plot "Evacuation Progress"
  clear-plot
  set-plot-y-range 0 (max list 1 total-population)
  set-current-plot-pen "Safe"  plotxy 0 0
  set-current-plot-pen "Still Exposed"  plotxy 0 0
end

; Updates the evacuation progress plot with current safe and exposed agent counts
to update-evacuation-plot
  set-current-plot "Evacuation Progress"
  set-plot-y-range 0 (max list 1 total-population)
  set-current-plot-pen "Safe"
  set-plot-pen-mode 0  plotxy time-min safe-count
  set-current-plot-pen "Still Exposed"
  set-plot-pen-mode 0  plotxy time-min exposed-count
end

; Forces waiting residents (decision=2) who have exceeded the configured wait-time-min
; to begin evacuating. Constrained between 5 and 10 minutes.
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

; Dynamically adjusts the crowd-weight parameter based on current road saturation level.
; Only applies when A4 (traffic management) is active.
to auto-adjust-parameters
  if time-min < 5 [ set crowd-weight 1.0  stop ]   ; No adjustment in first 5 minutes
  ifelse a4-traffic-management? [
    let pct-sat (100 * count roads with [ crowd >= saturation-threshold ] / max list 1 count roads)
    ifelse pct-sat < 20 [ set crowd-weight 0.5 ]         ; Low saturation: reduce crowd weight
    [ ifelse pct-sat < 50 [ set crowd-weight 2.0 ] [ set crowd-weight 5.0 ] ]  ; High saturation: increase weight
    set cum-traffic-saturation-managed cum-traffic-saturation-managed + 1
  ] [
    set crowd-weight 1.0   ; A4 off: constant crowd weight
  ]
end

; Starts frame-by-frame capture mode for video recording.
; Sets the record-video? flag to true so that export-view is called each tick in the go loop.
to start-recording
  set record-video? true
  output-print "Recording started automatically..."
end


; Stops frame capture by setting the record-video? flag to false.
; Frames saved in the frames/ folder can then be assembled into a video using ffmpeg.
to stop-recording
  set record-video? false
  output-print "Recording stopped. Frames saved in frames/ folder."
end


; Cleans up the claimed-victims list by removing WHO IDs for agents that are already evacuated.
; Prevents stale claims from blocking firetruck dispatching.
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
;;;;;;;;;;;;;;;; GO (MAIN LOOP) ;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; Main simulation loop — executed once per tick.
; Each tick represents 60 seconds of simulated time.
; Runs until time-min >= 60 (1 hour), then exports results and stops.
to go
  if simulation-paused? [ stop ]   ; Pause guard (reinforcement prompt)
  if time-min >= 60 [
    export-results
    finalize-display
    stop-recording 
    stop
  ]

  ; Active agents at this tick
  let res-active  residents   with [ evacuated? = false ]
  let ped-active  pedestrians with [ evacuated? = false ]
  let active-agents (turtle-set res-active ped-active)
  let active-peds   ped-active

  ; Linear flood progression factor: 0.0 at t=0, 1.0 at t=60 min
  let progress min list 1.0 (time-min / 60)

  ; --- FLOOD PROGRESSION ---
  ; Each patch increases its flood depth proportionally to the raster maximum (waterDepth)
  ask flood-patches-cache [
    let new-depth waterDepth * progress
    let raw-rise max list 0 (new-depth - depth)         ; Raw rise since last tick
    set water-rise-rate 0.7 * water-rise-rate + 0.3 * raw-rise  ; Exponential smoothing
    set depth new-depth
    set predicted-depth min list waterDepth (depth + water-rise-rate * flood-lookahead)  ; Lookahead forecast
    if depth > max_depth [ set max_depth depth ]

    ; Classify flood depth into 5 classes (0 = dry, 4 = very deep)
    ifelse depth <= 0   [ set floodClass 0 ] [
    ifelse depth < 0.5  [ set floodClass 1 ] [
    ifelse depth < 1.0  [ set floodClass 2 ] [
    ifelse depth < 2.0  [ set floodClass 3 ] [ set floodClass 4 ]]]]

    ; Fine-grained coloring within each flood class based on sub-ranges
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

  ; Accumulate time-in-water for agents currently standing in water (depth >= Hc)
  let wet-agents active-agents with [ [waterDepth] of patch-here >= Hc ]
  ask wet-agents [ set time_in_water time_in_water + tick_to_sec ]

  ; --- RESIDENT MOVEMENT PHASE 1: Move toward initial intersection ---
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

  ; --- RESIDENT MOVEMENT PHASE 2: Spawn pedestrian or enter waiting state ---
  ask residents with [ reached? = true and evacuated? = false ] [
    let spd speed  let dcsn decision
    let tinw time_in_water  let tmax max_depth_agent
    let alrt alert-received?  let chan alert-channel
    if dcsn = 1 [
      ; Decision = evacuate: hatch a pedestrian and transfer properties
      ask current_int [
        hatch-pedestrians 1 [
          set size 2  set shape "dot"  set color orange
          set current_int myself  set speed spd
          set evacuated? false  set rescued-by-firefighters? false
          set moving? false  set decision 1
          set time_in_water tinw  set max_depth_agent tmax
          set alert-received? alrt  set alert-channel chan
          set path [hor-path] of myself      ; Use precomputed shelter path
          ifelse empty? path [ set shelter -1 ] [ set shelter last path ]
          if shelter = -1 and [shelter_type] of current_int = "Hor" [ set shelter -99 ]
          if shelter = -99 [ mark-evacuated ]  ; Already at shelter
        ]
      ]
      die   ; Remove the resident agent (now replaced by pedestrian)
    ]
    if dcsn = 2 [
      ; Decision = wait: stay put and record wait start tick
      ifelse [floodClass] of patch-here >= 1
          [ set color red  set shape "square"  set size 1.4 ]
      [ set color gray ]
      set moving? false
      if wait-start-tick = -1 [ set wait-start-tick ticks ]
    ]
  ]

  ; --- PEDESTRIAN MOVEMENT ---
  ; Check if pedestrian has reached their shelter
  ask active-peds [
    if [who] of current_int = shelter or shelter = -99 [ mark-evacuated ] ]
  ; Set next intersection for idle pedestrians with a remaining path
  ask active-peds with [ moving? = false and not empty? path ] [
    set next_int intersection item 0 path
    set path remove-item 0 path
    ifelse next_int != nobody and distance next_int > 0 [
      set heading towards next_int  set moving? true
    ] [ set moving? false ]
  ]
  ask active-peds with [ moving? = true ] [
    ; Hc = pedestrian discomfort threshold (default: 0.5 m)
    ; Above 1.5 × Hc: 5% chance of stopping and reverting to decision=2
    if [depth] of patch-here > (Hc * 1.5) [
      if random-float 1 < 0.05 [ set moving? false  set decision 2  stop ] ]
    ifelse speed > distance next_int [ fd distance next_int ] [ fd speed ]
    if distance next_int < 0.005 [
      set moving? false  set current_int next_int
      if [who] of current_int = shelter [ mark-evacuated ]
    ]
  ]

  ; Residents moving in dry zone → auto-evacuated (reached safety)
  ask residents with [
    evacuated? = false and decision = 1 and moving? = true
    and [floodClass] of patch-here = 0
  ] [ mark-evacuated ]

  ; Pedestrians in dry zone → auto-evacuated
  ask active-peds with [
    [floodClass] of patch-here = 0
  ] [ mark-evacuated ]

  ; Move civilian flow agents (parents, workers, relatives)
  ask parents   [ move-civilian-flow ]
  ask workers   [ move-civilian-flow ]
  ask relatives [ move-civilian-flow ]

  ; Periodic updates at varying intervals for performance balance
  if ticks mod 5 = 0 [ update-modal-choice ]         ; Check car → pedestrian conversion
  if ticks mod 5 = 0 [ update-road-usage-counts ]    ; Refresh firetruck route usage table
  move-car-drivers
  if count buses > 0 [ move-buses ]

  if ticks mod 60 = 0 [ force-waiters-to-evacuate ]   ; Force evacuation of long-waiting residents
  if ticks mod 10 = 0 [ update-resident-decisions ]   ; Re-evaluate waiting residents' decisions
  if ticks mod 5  = 0 [ propagate-alert-differentiated ]  ; Broadcast alerts via active channels
  if ticks mod 5  = 0 [ civilians-broadcast-flood-signals ]  ; A1: civilians emit flood signals
  if ticks mod 3  = 0 [ decay-civilian-flood-signals ]       ; A1: decay flood signals

  update-crowd   ; Update crowd counts on all road segments every tick

  if ticks mod 30 = 0 [ update-road-obstructions ]    ; Update road capacity based on flood depth
  update-road-flood-colors   ; Every tick: apply flood color priority to roads
  update-agent-colors        ; Every tick: update agent shapes/colors
  if ticks mod 6 = 0 [ update-schools-workplaces-display ]  ; Update school/workplace icons
  if ticks mod 20 = 0 [ update-road-status ]          ; Update % flooded and saturated roads
  if ticks mod 10 = 0 [ reroute-pedestrians ]         ; A2: reroute pedestrians if needed
  if ticks mod 3  = 0 [ decay-congestion-signals ]    ; A4: decay congestion signals

  ; Record a congestion event if any road is saturated this tick
  if ticks mod 12 = 0 [
    if count roads with [
      crowd >= saturation-threshold and road-capacity-factor >= 0.3 ] > 0 [
      set cum-congestion-events cum-congestion-events + 1 ]
  ]
  if ticks mod 60 = 0 [ auto-adjust-parameters ]      ; A4: adjust crowd-weight dynamically

  if count firetrucks > 0 [ continuous-reroute-firetrucks ]    ; Reroute trucks detecting congestion
  if ticks mod 15 = 0 [ check-shelter-saturation-reroute ]     ; Reroute trucks to unsaturated shelters
  if ticks mod access-time-check-interval = 0 [ check-access-time-trigger-reinforcements ]  ; Auto-reinforcement check
  if ticks mod 30 = 0 [ cleanup-claimed-victims ]     ; Remove stale victim claims

  ; --- REINFORCEMENT TRIGGER ALERT ---
  ; Pause simulation and alert user that main station is overwhelmed
  if not reinforcement-activated and not reinforcement-alert-shown [
    if time-min >= reinforcement-trigger-min [
      set reinforcement-alert-shown true  set simulation-paused? true
      output-print "========================================="
      output-print "ALERT: Main fire station overwhelmed!"
      output-print (word "Time: " precision time-min 1 " min")
      output-print ">>> Click 'Activate Reinforcements' then GO."
      output-print "========================================="
      stop
    ]
  ]

  if ticks mod 30 = 0 [ dispatch-reinforcements ]    ; Dispatch reinforcement trucks
  if ticks mod 15 = 0 [ dispatch-firetrucks ]        ; Dispatch new firetrucks from stations
  if count firetrucks > 0 [ move-firetrucks ]        ; Execute firetruck movement

  if ticks mod 12 = 0 [ update-accessibility-metrics ]  ; Update A3 accessibility index
  if ticks mod 12 = 0 [ update-evacuation-plot ]         ; Update evacuation progress chart
  if ticks mod 60 = 0 [ update-accessibility-plot ]      ; Update accessibility chart
  
  tick
  ; If frame capture is active, export the current view as a PNG file.
  ; The output path is built automatically from the base directory and the
  ; config-folder-name reporter, which resolves to the correct subfolder
  ; based on the active improvement flags (A1–A4) and scenario type.
  ; Files are numbered from frame_10001.png onward to guarantee correct
  ; chronological ordering when assembling the video with ffmpeg.
  ; NOTE FOR USERS: NetLogo saves frames relative to the .nlogo file location.
  ; The folder "simulation_images_for_videos" must exist in the same directory
  ; as the .nlogo file. Create it manually before running the simulation.
  ; If you prefer an absolute path, replace the folder name below with your
  ; local path, e.g: "C:/Users/YourName/YourProject/simulation_images_for_videos/"
  if record-video? [
    let frame-name (word "simulation_images_for_videos/frame_"
      (word (10000 + ticks)) ".png")
    carefully [ export-view frame-name ]
    [ output-print "WARNING: folder missing - check simulation_images_for_videos/ exists next to the .nlogo file" ]
  ]
end


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;; REPORTERS ;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; Total active population (residents + pedestrians still in the simulation)
to-report total-population
  report count residents + count pedestrians
end

; Current simulation time in minutes
to-report time-min
  report (ticks * tick_to_sec) / 60
end

; Count of agents rescued by firetrucks
to-report rescued-count
  report count residents  with [ rescued-by-firefighters? = true ] +
         count pedestrians with [ rescued-by-firefighters? = true ]
end

; Count of agents who self-evacuated (not by firetruck)
to-report self-evacuated-count
  report count residents  with [ evacuated? = true and rescued-by-firefighters? = false ] +
         count pedestrians with [ evacuated? = true and rescued-by-firefighters? = false ]
end

; Count of non-evacuated agents currently in flooded zones
to-report non-evacuated-count
  report count residents  with [ evacuated? = false and [floodClass] of patch-here >= 1 ] +
         count pedestrians with [ evacuated? = false and [floodClass] of patch-here >= 1 ]
end

; Percentage of total population rescued by firetrucks
to-report per-rescued
  if total-population = 0 [ report 0 ]
  report 100 * rescued-count / total-population
end

; Percentage of total population still in flooded zones and not evacuated
to-report per-non-evacuated
  if total-population = 0 [ report 0 ]
  report 100 * non-evacuated-count / total-population
end

; Mean evacuation time in minutes (over all evacuated agents)
to-report mean-ev-time
  if empty? ev_times [ report 0 ]
  report mean ev_times
end

; Median evacuation time in minutes
to-report median-ev-time
  if empty? ev_times [ report 0 ]
  let s sort ev_times
  let n length s
  if n mod 2 = 1 [ report item (n / 2) s ]
  report (item (n / 2 - 1) s + item (n / 2) s) / 2
end

; Mean firetruck access time in minutes
to-report mean-access-time
  if empty? access-times [ report 0 ]
  report precision (mean access-times) 2
end

; Percentage of roads with crowd count exceeding the saturation threshold
to-report pct-saturated-roads
  if count roads = 0 [ report 0 ]
  report precision
    (100 * count roads with [ crowd >= saturation-threshold ] / count roads) 1
end

; Count of active civilian flow agents (parents + workers + relatives) still on mission
to-report active-flow-agents
  report count parents   with [ not mission-done? ] +
         count workers   with [ not mission-done? ] +
         count relatives with [ not mission-done? ]
end

; Count of flow agents currently in flooded zones (contributing to congestion)
to-report blocking-residents-count
  report count turtles with [
    (is-parent? self or is-worker? self or is-relative? self) and
    not mission-done? and [floodClass] of patch-here >= 1
  ]
end

; Percentage of total population classified as isolated (unreachable by firetrucks)
to-report pct-isolated-victims
  if total-population = 0 [ report 0 ]
  report precision (100 * isolated-victims-count / total-population) 1
end

; Mean number of reroutes per active firetruck
to-report firetruck-reroute-rate
  if count firetrucks = 0 [ report 0 ]
  report precision (cum-reroutes / max list 1 count firetrucks) 2
end

; Count of agents currently in flooded zones and not yet evacuated
to-report exposed-count
  report count residents  with [ evacuated? = false and [floodClass] of patch-here >= 1 ] +
         count pedestrians with [ evacuated? = false and [floodClass] of patch-here >= 1 ]
end

; Percentage of total population currently exposed to flooding
to-report pct-exposed
  if total-population = 0 [ report 0 ]
  report precision (100 * exposed-count / total-population) 1
end

; Count of agents who have successfully evacuated
to-report safe-count
  report count residents  with [ evacuated? = true ] +
         count pedestrians with [ evacuated? = true ]
end

; Percentage of total population that has evacuated
to-report pct-safe
  if total-population = 0 [ report 0 ]
  report precision (100 * safe-count / total-population) 1
end

; Count of agents who have not yet evacuated (all zones)
to-report still-in-danger-count
  report count residents  with [ evacuated? = false ] +
         count pedestrians with [ evacuated? = false ]
end

; Percentage of flood patches where water is rising faster than the threshold
to-report pct-rising-patches
  if not is-agentset? flood-patches-cache [ report 0 ]
  if count flood-patches-cache = 0 [ report 0 ]
  report precision
    (100 * count flood-patches-cache with [
      water-rise-rate > flood-rise-threshold ] / count flood-patches-cache) 1
end

; Maximum water rise rate observed across all flooded patches
to-report max-rise-rate
  if not is-agentset? flood-patches-cache [ report 0 ]
  if count flood-patches-cache = 0 [ report 0 ]
  let rates [water-rise-rate] of flood-patches-cache
  if empty? rates [ report 0 ]
  report precision (max rates) 4
end

; Number of victims currently assigned to (claimed by) a firetruck
to-report claimed-victims-count
  report length claimed-victims
end

; Number of residents who have received any form of alert
to-report alerted-residents-count
  report count residents with [ alert-received? = true ]
end

; Cumulative count of civilian path rerouting events
to-report civilian-reroute-count
  report cum-civilian-reroutes
end

; Percentage of congestion events attributable to truck traffic
to-report pct-truck-congestion
  let total max list 1 (cum-truck-congestion-events + cum-civil-congestion-events)
  report precision (100 * cum-truck-congestion-events / total) 1
end

; Percentage of congestion events attributable to civilian traffic
to-report pct-civil-congestion
  let total max list 1 (cum-truck-congestion-events + cum-civil-congestion-events)
  report precision (100 * cum-civil-congestion-events / total) 1
end

; Number of shelters currently exceeding their maximum capacity
to-report shelter-saturation-count
  report count cached-shelters with [ evacuee_count > shelter-max-capacity ]
end

; Count of firetrucks rerouted because their assigned shelter was saturated
to-report shelter-saturation-reroute-count
  report shelter-saturation-reroutes
end

; Count of civilians who rerouted in response to a firetruck rerouting event
to-report civil-reactions-to-reroute-count
  report cum-civil-reactions-to-truck-reroute
end

; Percentage of patches with an active shared congestion signal (> 0.5)
to-report pct-congestion-signal-active
  if count patches = 0 [ report 0 ]
  report precision
    (100 * count patches with [ shared-congestion-signal > 0.5 ] / count patches) 1
end

; Share of alerted residents reached via radio
to-report pct-alerted-by-radio
  let total max list 1 (cum-radio-alerts + cum-app-alerts + cum-wom-alerts + cum-firetruck-alerts)
  report precision (100 * cum-radio-alerts / total) 1
end

; Share of alerted residents reached via mobile app
to-report pct-alerted-by-app
  let total max list 1 (cum-radio-alerts + cum-app-alerts + cum-wom-alerts + cum-firetruck-alerts)
  report precision (100 * cum-app-alerts / total) 1
end

; Share of alerted residents reached via word of mouth
to-report pct-alerted-by-wom
  let total max list 1 (cum-radio-alerts + cum-app-alerts + cum-wom-alerts + cum-firetruck-alerts)
  report precision (100 * cum-wom-alerts / total) 1
end

; Share of alerted residents reached via firetruck proximity
to-report pct-alerted-by-firetruck
  let total max list 1 (cum-radio-alerts + cum-app-alerts + cum-wom-alerts + cum-firetruck-alerts)
  report precision (100 * cum-firetruck-alerts / total) 1
end

; Total number of alert events across all channels
to-report total-alerted-count
  report cum-radio-alerts + cum-app-alerts + cum-wom-alerts + cum-firetruck-alerts
end

; Cumulative count of priority passage events (A4 firetruck priority mode)
to-report priority-passage-count
  report cum-priority-passages
end

; Percentage of firetrucks currently in priority mode
to-report pct-trucks-in-priority-mode
  if count firetrucks = 0 [ report 0 ]
  report precision
    (100 * count firetrucks with [ priority-mode? = true ] / count firetrucks) 1
end

; Cumulative count of ticks where at least one truck had its speed reduced by flood depth
to-report speed-reduction-count
  report cum-speed-reductions
end

; Mean flood depth at patches currently occupied by firetrucks
to-report mean-truck-depth
  if count firetrucks = 0 [ report 0 ]
  let depths-list [depth] of patches with [ any? firetrucks-here ]
  if empty? depths-list [ report 0 ]
  report precision mean depths-list 3
end

; Count of automatic reinforcement activations triggered by access-time threshold
to-report access-triggered-reinforcements-count
  report cum-access-triggered-reinforcements
end

; Difference between mean access time and the activation threshold
to-report access-time-vs-threshold
  report precision (mean-access-time - access-time-reinforce-threshold) 2
end

; Percentage of patches with an active civilian flood signal (> 0.5)
to-report pct-civilian-signal-active
  if count patches = 0 [ report 0 ]
  report precision
    (100 * count patches with [ civilian-flood-signal > 0.5 ] / count patches) 1
end

; Cumulative count of civilian flood signal broadcasts (A1)
to-report civilian-flood-signal-count
  report cum-civilian-flood-signals
end

; Civilians rerouted specifically because their target shelter was saturated (A2)
to-report shelter-saturation-civilian-reroute-count
  report cum-shelter-saturation-civilian-reroutes
end

; Percentage of shelters currently exceeding their maximum capacity
to-report pct-shelters-saturated
  let nb max list 1 count cached-shelters
  report precision
    (100 * count cached-shelters with [ evacuee_count > shelter-max-capacity ] / nb) 1
end

; Count of dispatching decisions influenced by the accessibility index (A3)
to-report index-driven-prioritization-count
  report cum-index-driven-prioritizations
end

; Current accessibility index value (0 = fully blocked, 100 = fully accessible)
to-report current-accessibility-index
  report accessibility-index
end

; Cumulative count of ticks where traffic saturation was actively managed (A4)
to-report traffic-saturation-managed-count
  report cum-traffic-saturation-managed
end

; Short label summarizing active improvements and scenario type (used in plots and CSV)
to-report active-config-label
  report (word
    ifelse-value a1-civilian-signal?    ["A1 "][""]
    ifelse-value a2-shelter-saturation? ["A2 "][""]
    ifelse-value a3-priority-index?     ["A3 "][""]
    ifelse-value a4-traffic-management? ["A4 "][""]
    "| " scenario-type)
end

; Mean time in water (seconds) across all non-evacuated agents
to-report mean-exposure-time
  let exposed (turtle-set
    residents   with [ evacuated? = false ]
    pedestrians with [ evacuated? = false ])
  if not any? exposed [ report 0 ]
  report precision (mean [time_in_water] of exposed) 1
end

; Maximum time in water (seconds) across all non-evacuated agents
to-report max-exposure-time
  let exposed (turtle-set
    residents   with [ evacuated? = false ]
    pedestrians with [ evacuated? = false ])
  if not any? exposed [ report 0 ]
  report precision (max [time_in_water] of exposed) 1
end

; Count of non-evacuated agents whose time in water has exceeded the critical threshold Tc
to-report count-agents-over-Tc
  report count residents  with [ evacuated? = false and time_in_water > Tc ] +
         count pedestrians with [ evacuated? = false and time_in_water > Tc ]
end

; Percentage of exposed agents exceeding the critical water exposure threshold Tc
to-report pct-agents-over-Tc
  let exposed exposed-count
  if exposed = 0 [ report 0 ]
  report precision (100 * count-agents-over-Tc / exposed) 1
end

; Total cumulative water exposure in minutes across all agents (residents + pedestrians)
to-report total-cumulative-exposure-min
  let all-agents (turtle-set residents pedestrians)
  if not any? all-agents [ report 0 ]
  report precision (sum [time_in_water] of all-agents / 60) 1
end

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; PARETO MULTI-OBJECTIVE SCORES
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; Rescue score (0–100): composite indicator of firetruck effectiveness.
; Weighted combination of:
;   - access time score (50%)
;   - isolation score (30%)
;   - blocked truck score (20%)
to-report rescue-score
  let score-delay ifelse-value (mean-access-time > 0)
    [ max list 0 (100 - (mean-access-time * 10)) ] [ 100 ]
  let score-isolated ifelse-value (total-population > 0)
    [ max list 0 (100 - (100 * isolated-victims-count / total-population)) ] [ 100 ]
  let score-blocked ifelse-value (count firetrucks > 0)
    [ max list 0 (100 - (nb-camions-bloques * 10)) ] [ 100 ]
  report precision ((score-delay * 0.50) + (score-isolated * 0.30) + (score-blocked * 0.20)) 1
end

; Civil score (0–100): composite indicator of civilian evacuation efficiency.
; Weighted combination of:
;   - safe evacuation rate (50%)
;   - mean evacuation time (25%)
;   - network accessibility (25%)
to-report civil-score
  let score-evac pct-safe
  let score-time ifelse-value (mean-ev-time > 0)
    [ max list 0 (100 - (mean-ev-time * 2)) ] [ 100 ]
  let score-network pct-network-accessible
  report precision ((score-evac * 0.50) + (score-time * 0.25) + (score-network * 0.25)) 1
end



;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; RESULTS EXPORT (CSV)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; Exports all key simulation results to a CSV file at the end of the run.
; Each row is an Indicator,Value pair for easy analysis.
to export-results
  let filename "simulation_outputs.csv"
  file-open filename

  ; Header
  file-print "Indicator,Value"

  ; Configuration
  file-print (word "Configuration," active-config-label)
  file-print (word "Scenario," scenario-type)
  file-print (word "Simulation time (min)," precision time-min 1)

  ; Population
  file-print (word "Total population," total-population)
  file-print (word "Evacuated (%)," pct-safe)
  file-print (word "Non-evacuated (%)," per-non-evacuated)
  file-print (word "Rescued by firetrucks (%)," per-rescued)
  file-print (word "Exposed (%)," pct-exposed)

  ; Timing
  file-print (word "Mean evacuation time (min)," precision mean-ev-time 2)
  file-print (word "Median evacuation time (min)," precision median-ev-time 2)
  file-print (word "Mean firetruck access time (min)," mean-access-time)

  ; Network
  file-print (word "Flooded roads (%)," pct-routes-inondees)
  file-print (word "Saturated roads (%)," pct-routes-saturees)
  file-print (word "Accessible network (%)," pct-network-accessible)

  ; Firetrucks
  file-print (word "Firetruck reroutes," cum-reroutes)
  file-print (word "Blocked trucks," nb-camions-bloques)
  file-print (word "Deliveries completed," cum-trucks-delivered)

  ; Alerts
  file-print (word "Radio alerts," cum-radio-alerts)
  file-print (word "App alerts," cum-app-alerts)
  file-print (word "Word-of-mouth alerts," cum-wom-alerts)
  file-print (word "Firetruck proximity alerts," cum-firetruck-alerts)

  ; Indices
  file-print (word "Accessibility index," accessibility-index)
  file-print (word "Mean rescue delay," mean-rescue-delay)
  file-print (word "Isolated victims," isolated-victims-count)

  ; Scores
  file-print (word "Rescue score," rescue-score)
  file-print (word "Civil score," civil-score)

  file-close
  output-print (word "Results exported: " filename)
  export-video-script
end


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; VIDEO CONVERSION SCRIPT EXPORT
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; Generates a Windows batch (.bat) file that converts the exported PNG frames
; into an MP4 video using ffmpeg. The script is created automatically at the
; end of each simulation run, named after the current configuration folder
; (e.g. convert_07_comm_failure.bat).
;
; The generated .bat file can be double-clicked to produce the final video.
; ffmpeg settings used:
;   -framerate 3        : 3 frames per second (slow playback for analysis)
;   -start_number 10001 : matches the frame numbering used during export
;   format=yuv420p      : ensures broad video player compatibility
;   pad=ceil(iw/2)*2    : forces even width/height required by H.264 encoder
;   -c:v libx264        : H.264 compression for small file size
;
; Note: ffmpeg must be installed and accessible from the command line.
to export-video-script
  let base-path ""
  let bat-file "conversion_of_simulation_images_to_video.bat"
  file-open bat-file
  file-print "@echo off"
  ; Convert frames to video
  file-print (word "ffmpeg -y -framerate 3 -start_number 10001 -i \""
    "simulation_images_for_videos/frame_%%05d.png\" "
    "-vf \"format=yuv420p,pad=ceil(iw/2)*2:ceil(ih/2)*2\" "
    "-c:v libx264 \""
    "simulation_images_for_videos.mp4\"")
  ; Delete all PNG files after video is created
  file-print "del /Q \"simulation_images_for_videos\\*.png\""
  file-print "echo Video created and PNG files deleted."
  file-print "pause"
  file-close
  output-print "BAT script generated: conversion_of_simulation_images_to_video.bat"
end
