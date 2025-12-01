extensions [csv nw]
directed-link-breed [connections connection]

turtles-own [
  node-id               ; Node ID
  node-type             ; Node type (community/external)
  response-probability  ; Node response probability (converted from 1-5 scale to 0.2-1)
  response-duration     ; Duration of node's response
  is-recovered          ; Whether the community is fully recovered
  post-flood-value      ; Functionality value after flood (Fa)
  pre-flood-value       ; Functionality value before flood (F0)
  resistance            ; Resistance capacity (Community property)
  recovery              ; Recovery capacity (Community property)
  has-responded         ; Flag marking if node has responded in current tick during loss sharing (to avoid repeated queries)
  has-responded1        ; Flag marking if node has responded in current tick during recovery participation
  has-responded2        ; Flag marking if node has responded in current tick when applying flood resilience measures
  response-count        ; Count of responses during loss sharing
  response-count1       ; Count of responses during recovery
  response-count2       ; Count of responses during flood resilience measures application
  time-since-activation ; Remaining active ticks during loss sharing
  time-since-activation1 ; Remaining active ticks during recovery
  is-active             ; Whether node is active during loss sharing
  is-active1            ; Whether node is active during recovery
  is-active2            ; Whether node is active during flood resilience measures execution
  resource              ; Total budget of each node
  theoretical-post-flood-value ; F_t: Theoretical worst-case functionality (no assistance) (Fw)
]

links-own [
  connection-type   ; Link type
  strength          ; Link strength
  trust             ; Dynamic trust value
]

globals [
  flood-loss-rate           ; Dynamic flood loss rate
  robustness                ; Robustness (R)
  adaptivity                ; Adaptivity (A)
  resilience-score          ; Resilience (Ω)
  recovery-end-time         ; Time when community recovery completes
  MaxCR                     ; Maximum Trust Increment (for diminishing returns formula)
  disaster-phase            ; Disaster phase (pre-disaster, during-disaster, post-disaster)
  flood-start-tick          ; Tick when flood begins
  rainfall-now
  rainfall-past
  theoretical-loss
  actual-loss
  actual-recovery
  flood-mitigation-pathways ; Paths for the five flood resilience measures
  early-warning-pathways
  community-education-pathways
  emergency-support-pathways
  funds-pathways
  flood-mitigation-pre-done?    ; Flag controlling activation status of pre-flood Flood Mitigation Infrastructure
  flood-mitigation-during-done? ; Flag controlling activation status of during-flood Flood Mitigation Infrastructure
  community-education-pre-done? ; Flag controlling activation status of pre-flood Community-Based Disaster Education
  early-warning-pre-done?       ; Flag controlling pre-flood Early Warning System activation
  early-warning-during-done?    ; Flag controlling during-flood Early Warning System activation
  emergency-support-during-done? ; Flag controlling during-flood Emergency Support activation
  emergency-support-post-done?  ; Flag controlling post-flood Emergency Support activation
  funds-pre-done?               ; Flag controlling pre-flood Funds activation
  funds-during-done?            ; Flag controlling during-flood Funds activation
  funds-post-done?              ; Flag controlling post-flood Funds activation
  reported?
  incf       ; Government agencies' resource increment
  tf         ; Interval for government resource replenishment
  incif      ; Non-government agencies' resource increment
  tif        ; Interval for non-government resource replenishment
  rf_l       ; Random factor in share loss phase
  rf_r       ; Random factor in recovery phase
  total-responses ; Total responses
  total-resource ; Total resources used
  resource-rest   ; Remaining resources
  total-theoretical-loss  ; Accumulated theoretical loss over entire flood period (Legacy, replaced by AUC)
  total-actual-loss       ; Accumulated actual loss over entire flood period (Legacy, replaced by AUC)
  total-area-F0   ; Total area under F0 (Ideal) curve
  total-area-Fa  ; Total area under Fa (Actual) curve
  total-area-Fw   ; Total area under Fw (Worst-case) curve
  stop-tick
  accumulative-loss-share ; Temporary global to sum loss sharing potential per tick
]




;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;【Part 1】Import data, initialize model, set flood scenario ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

to setup
  clear-all
  import-network-data "network_data.csv"  ; Import network data
  import-node-data "node_data.csv"        ; Import node attribute data
  ask turtles [set is-active false set has-responded false
    set is-active1 false set has-responded1 false]
  initialize-community
  ;setup-flood-scenario
  repeat 30 [layout-spring turtles links 0.5 10 3]

  ; Initialize node colors and ensure all is-active flags are false
  ask turtles [
    if node-type = "community" [
      set color blue
    ]
    if node-type != "community" [
      set color gray
    ]
    set is-active false  ; Ensure all nodes start as inactive
  ]
   ; Initialize global state variables
  set MaxCR maximum-trust-increment   ; Trust increase rate (from interface slider)
  set rainfall-past []
  set disaster-phase "pre-disaster"
  set flood-start-tick 2     ; Set the tick when the flood starts
  set incf G-resource-increment  ; Government resource increment (from interface)
  set tf G-replenishment-interval ; Government resource replenishment interval (from interface)
  set incif NG-resource-increment  ; Non-government resource increment (from interface)
  set tif NG-replenishment-interval ; Non-government resource replenishment interval (from interface)
  set rf_l 0.01 ; Random factor for loss sharing phase
  set rf_r 0.01 ; Random factor for recovery phase
  set accumulative-loss-share 0

  ; Reset all flood measure activation flags
  set flood-mitigation-pre-done? false
  set flood-mitigation-during-done? false
  set community-education-pre-done? false
  set early-warning-pre-done? false
  set early-warning-during-done? false
  set emergency-support-during-done? false
  set emergency-support-post-done? false
  set funds-pre-done? false
  set funds-during-done? false
  set funds-post-done? false
  set reported? false
  set stop-tick flood-start-tick
  set total-area-F0 0
  set total-area-Fa 0
  set total-area-Fw 0
  reset-ticks
end


; Import network data, set link thickness and color. These are directed links.
to import-network-data [file-name]
  file-open file-name
  let header file-read-line  ; Skip the header line

  while [not file-at-end?] [
    let line csv:from-row file-read-line
    let source-name item 0 line
    let target-name item 1 line
    let link-strength  item 2 line
    let link-type item 3 line

    let source find-or-create-node source-name
    let target find-or-create-node target-name

    if (source != nobody and target != nobody) [
      ask source [
          create-connection-to target [
            set strength link-strength  ; Need to be normalized
            set connection-type link-type

            if connection-type = "formal" [
              set trust trust-in-nongovernment-actors ; Set initial trust (from interface)
              set color red
            ]
            if connection-type = "informal" [
              set trust trust-in-nongovernment-actors ; Set initial trust (from interface)
              set color green
            ]

            set thickness strength / 2
          ]
      ]
    ]
  ]
  file-close
end

;; =====================================================
;; To simulate multiple types of governance network structures,
;; researchers can refer to the following code block.
;; You only need to set a global variable `network-id` on the Interface tab.
;; The rest of the code remains unchanged.
;; =====================================================
;
;; Compute indices: each type includes 10 variants; `index` selects the specific network file
;let index network-id mod 10
;
;; Compute type index: divides by 10 and takes the integer part to determine network category
;let type-index floor (network-id / 10)
;
;; Define the four governance network types
;let network-types ["high-density-formal" "high-density-informal" "low-density-formal" "low-density-informal"]
;
;; Check for out-of-range input
;if type-index >= length network-types [
;  print (word "Error: network-id out of range! Given: " network-id)
;  stop
;]
;
;; Retrieve the name of the selected network type for this simulation run
;let network-type item type-index network-types
;
;; Construct the file path to the network CSV based on type and index
;set network-name (word "generated_networks/network_data_" network-type "_" index ".csv")
;
;; Import network and node attributes from external CSV files
;import-network-data network-name
;import-node-data "file name of the node data"


; Import node attribute data
to import-node-data [file-name]
  file-open file-name
  while [not file-at-end?] [
    let line csv:from-row file-read-line
    let node-name item 0 line
    show node-name
    let raw-response-probability item 1 line
    let raw-response-duration item 2 line
    let ntype item 4 line
    ask turtles with [label = node-name] [
      set response-probability raw-response-probability / 5.0  ; Convert 1-5 scale to 0.2-1 probability
      set response-duration raw-response-duration  ; Response duration from expert scoring
      set node-type ntype
      set response-count 0  ; Initialize response counts
      set response-count1 0
      set is-active false  ; Initialize as inactive
      set is-active1 false
      set is-active2 false
      set time-since-activation 0  ; Initialize active time
      set time-since-activation1 0
      set resource initial-resources ; Set initial resource (from interface)
    ]
  ]
  file-close
end


; Find or create a node
to-report find-or-create-node [name]
  if any? turtles with [label = name] [
    report one-of turtles with [label = name]
  ]
  create-turtles 1 [
    set label name
    set shape "circle"
    if name = "Zengbu_Community" [set node-type "community"]
  ]
  report one-of turtles with [label = name]
end


; Initialize community node properties
to initialize-community
  ask turtles with [node-type = "community"] [
    set is-recovered false
    set post-flood-value 100
    set pre-flood-value 100
    set theoretical-post-flood-value 100
    set resistance 0.5 ; Set initial resistance capacity to 0.5
    set recovery 0.5   ; Set initial recovery capacity 0.5
  ]
end


to rain
  ; Parameters for Chicago rainfall model based on intensity
  let a 0 let b 0 let c 0
  if flood-intensity = "10-year flood" [
    set a 16971.541 set b 34.941 set c 0.916
  ]
  if flood-intensity = "50-year flood" [
    set a 24556.014 set b 46.25 set c 0.913
  ]
  if flood-intensity = "100-year flood" [
    set a 27212.984 set b 49.226 set c 0.912
  ]

  let r 0.35 ; Rainfall peak coefficient
  let tp flood-duration * r + flood-start-tick
  let t1 0
  let rain-ticks ticks - flood-start-tick

  ifelse rain-ticks <= tp [
    set t1 (tp - rain-ticks) / r]
  [set t1 (rain-ticks - tp) / (1 - r)]

  set rainfall-past lput rainfall-now rainfall-past

  ; Convert time from hours to minutes for the formula
  let tmin   (t1 * 60)
  set rainfall-now ((a * (tmin * (1 - c) + b)) / ((tmin + b) ^ (1 + c))) / 167

  ; Set to 0 if outside flood duration
  if ticks > flood-duration + flood-start-tick [ set rainfall-now 0 ]

  ; Calculate peak rainfall using minutes
  let tpmin  (tp * 60)
  let rainfall-max ((a * (tpmin * (1 - c) + b)) / ((tpmin + b) ^ (1 + c))) / 167

  ; Normalize rainfall to 0-5 scale
   let x 0
   set x ((rainfall-now) / rainfall-max ) * 5
   ; Calculate flood loss rate based on normalized rainfall
   set flood-loss-rate (0.1069 * x + 0.2903)
end




;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;【Part 2】Simulate flood losses and stakeholder loss sharing  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; Simulate flood loss and initiate loss sharing requests
to simulate-flood
  ask turtles with [node-type = "community"] [
  set theoretical-loss flood-loss-rate * post-flood-value ; Theoretical loss based on current functionality
    if ticks < flood-duration  + flood-start-tick [
    set actual-loss theoretical-loss
    ]
    if ticks > flood-duration  + flood-start-tick [
      set actual-loss 0
    ]
    ; Ask 1-degree neighbors to share the loss
    ask turtles with [nw:distance-to myself = 1 and node-type != "community" and is-active = false] [
      ; Decide whether to respond based on probability and available resources
      if random-float 1 < response-probability and resource >= 1 [
          ; Activate the neighboring node and set response duration
          set is-active true
          set time-since-activation response-duration ; Duration the node remains active
          set has-responded true  ; Mark this node as having responded
          set response-count response-count + 1  ; Increment response count
          set resource max list 0 (resource - 1) ; Deduct 1 resource unit for activation
          adjust-trust ; Successful response increases trust
  ]]]
end


to share-loss
  set accumulative-loss-share 0
  if count turtles with [node-type = "community"] != 0[
  ; Ask active nodes to calculate their contribution
  ask turtles with [is-active = true] [
    if link-with one-of turtles with [node-type = "community"] != nobody [
      let my-link link-with one-of turtles with [node-type = "community"]
      ; Calculate loss share potential based on strength and trust
      let loss-share (([strength] of my-link)^ 0.9 * ([trust] of my-link)^ 0.1 )
      set accumulative-loss-share accumulative-loss-share + loss-share
    ]
  ]
 ]

  ; Activate 2nd-degree neighbors (diffusion)
  ask turtles with [has-responded = true and is-active = false][
      let net1 self
    if actual-loss > 0 [
      ask turtles with [nw:distance-to net1 = 1 and node-type != "community" and is-active = false] [
          ; Decide whether to respond
          if random-float 1 < response-probability  and resource >= 1 [
            ; Activate the neighboring node
            set is-active true
            set time-since-activation response-duration
            set has-responded true
            set response-count response-count + 1
            set resource max list 0 (resource - 1)
            adjust-trust
          ]
  ]]]

  ; Update community functionality based on accumulated loss sharing
  ask turtles with [node-type = "community"] [
    ; 1. Calculate total Mitigation Potential
    ; The range of uncertainty can be controlled by adjusting the random-float
    let loss-mitigation-potential (accumulative-loss-share * one-of [resistance] of turtles with [node-type = "community"] * ( 0.99 + random-float rf_l) )
    ; 2. Pass potential through a Sigmoid function to get [0, 1] mitigation-factor
    let mitigation-factor (1 / (1 + exp( 0 - (loss-mitigation-potential) )))
    ; 3. Calculate the actual loss percentage after mitigation
    let actual-loss-percent (flood-loss-rate * (1 - mitigation-factor) )
    ; 4. Update the actual functionality (Fa)
    set post-flood-value post-flood-value * (1 - actual-loss-percent)

    ; 5. Update the theoretical worst-case functionality (Fw)
    set theoretical-post-flood-value theoretical-post-flood-value * (1 - flood-loss-rate)

    ; Boundary checks
    if post-flood-value <= 0 [
      set post-flood-value 0
      set is-recovered false
    ]
    if theoretical-post-flood-value <= 0 [
      set theoretical-post-flood-value 0
    ]
  ]

  ; Update node activation status
  update-node-activation-status
end


; Update the activation status of all nodes
to update-node-activation-status
  ask turtles with [is-active] [
    set time-since-activation time-since-activation - 1
    if time-since-activation <= 0 [
      set is-active false
    ]
  ]
  ask turtles with [is-active1] [
    set time-since-activation1 time-since-activation1 - 1
    if time-since-activation1 <= 0 [
      set is-active1 false
    ]
  ]
end


; Dynamically adjust trust based on diminishing returns
to adjust-trust
  let my-link link-with myself
  if my-link != nobody [
      ask my-link [
        ; This creates a diminishing returns effect
        set trust min list 1 (trust + MaxCR * (1 - trust))
      ]
  ]
end




;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;【Part 3】Post-flood recovery process ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

to flood-recovery
  ; Stop if community is already fully recovered
  if all? turtles with [node-type = "community"] [post-flood-value = 100] [
   stop
  ]

  ask turtles with [node-type = "community"] [
    ; Ask 1-degree neighbors to participate in recovery
    ask turtles with [nw:distance-to myself = 1 and node-type != "community" and is-active1 = false] [
      ; Decide whether to respond based on probability and resource
      if random-float 1 < response-probability and resource >= 1[
        ; Activate the neighboring node
        set is-active1 true
        set time-since-activation1 response-duration
        set has-responded1 true
        set response-count1 response-count1 + 1
        set resource max list 0 (resource - 1)
        ; Successful response increases trust
        adjust-trust
      ]
    ]
  ]

  ; Calculate normalization factor for betweenness-centrality (BC)
  let all-raw-bc-values [nw:betweenness-centrality] of turtles
  let max-empirical-bc max all-raw-bc-values

  ; Calculate recovery contribution from active nodes
  if count turtles with [node-type = "community"] != 0 [
    ask turtles with [is-active1 = true] [
      if link-with one-of turtles with [node-type = "community"] != nobody [
        let my-link link-with one-of turtles with [node-type = "community"]
        let neighbor-betweenness [nw:betweenness-centrality] of self
        ; Calculate contribution based on strength, trust, and normalized BC
        let recovery-contribution ([strength] of my-link ^ 0.8 * [trust] of my-link ^ 0.1 * (neighbor-betweenness / max-empirical-bc) ^ 0.1)
        set actual-recovery actual-recovery + recovery-contribution
      ]
    ]
  ]
  ; Activate 2nd-degree neighbors (diffusion)
  ask turtles with [has-responded1 = true and is-active1 = false] [
    let net1 self
    if post-flood-value != 100 [
      ask turtles with [nw:distance-to net1 = 1 and node-type != "community" and is-active1 = false] [
        ; Decide whether to respond
        if random-float 1 < response-probability and resource >= 1[
          ; Activate the neighboring node
          set is-active1 true
          set time-since-activation1 response-duration
          set has-responded1 true
          set response-count1 response-count1 + 1
          set resource max list 0 (resource - 1)
          adjust-trust
        ]
      ]
    ]
  ]

  ; Update community functionality based on recovery
  ask turtles with [node-type = "community"] [
    ; 1. Calculate total recovery potential
    let actual-recovery1 actual-recovery * one-of [recovery] of turtles with [node-type = "community"] * (  0.99 + random-float rf_r )
    ; 2. Pass potential through a Sigmoid function
    let actual-recovery2 1 / (1 + exp(- actual-recovery1))
    ; 3. Update functionality (Fa)
    ; The equation can be adjusted to slow down the simulation and get a clearer view of the recovery, but empirical valiadation is needed.
    set post-flood-value post-flood-value * (1 + actual-recovery2)

    ; Boundary check
    if post-flood-value > 100 [
      set post-flood-value 100
    ]
    ; Set recovered flag if functionality reaches 100
    if ticks > flood-duration + flood-start-tick and post-flood-value = 100 [
      set is-recovered true
    ]
  ]

  ; Update node activation status
  update-node-activation-status
end




;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;【Part 4】Flood resilience measures ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

to flood-resilience-measures
  ; Define the pathways for each measure
  set flood-mitigation-pathways [
    ["DWAB" "Clan"]
    ["DWAB"]
    ["DWAB" "SO" "ZNC"]
    ["Clan"]
    ["ODGD"]
    ["ODGD""SO" "ZNC"]
  ]
  set early-warning-pathways [
    ["PMB" "GMG" "MMB" "LDG" "DEMB" "SO" "ZNC" "SWS"]
    ["PMB" "MMB" "LDG" "DEMB" "SO" "ZNC" "SWS"]
    ["PWRD" "GMG" "MWAB" "LDG" "DEMB" "SO" "ZNC" "SWS"]
    ["PWRD" "MWAB" "LDG" "DEMB" "SO" "ZNC" "SWS"]
    ["MMB" "LDG" "DEMB" "SO" "ZNC" "SWS"]
    ["MMB" "LDG" "DEMB" "SO" "ZNC" "SWS" "Clan"]
    ["MMB" "LDG" "DEMB" "SO" "ZNC" "SWS" "CERT"]
    ["MWAB" "LDG" "DEMB" "SO" "ZNC" "SWS"]
    ["MWAB" "LDG" "DEMB" "SO" "ZNC" "SWS" "Clan"]
    ["MWAB" "LDG" "DEMB" "SO" "ZNC" "SWS" "CERT"]
  ]
  set community-education-pathways [
    ["ES" "NGO"]
    ["ES" "NGO" "SWS"]
    ["CH" "NGO"]
    ["CH" "NGO" "CERT"]
    ["CH" "NGO" "SWS"]
    ["ES" "NGO" "CERT"]
  ]
  set emergency-support-pathways [
    ["GMG" "LDG" "DEMB" "SO" "ZNC"]
    ["GMG" "LDG" "DEMB" "SO"]
    ["SO"]
    ["ZNC"]
    ["Clan"]
    ["SWS"]
    ["CH"]
    ["CERT"]
  ]
  set funds-pathways [
    ["GMG" "LDG" "DEMB" "SO" "ZNC"]
    ["GMG" "LDG" "DEMB" "ODGD" "SO" "ZNC"]
    ["Clan"]
    ["PS" "NGO"]
  ]

  ; Effect levels: HIGH: 0.01, MODERATE: 0.002, LOW: 0
  ; --- Pre-disaster phase ---
  if disaster-phase = "pre-disaster" [
     if flood-mitigation-infrastructure? and not flood-mitigation-pre-done?  [
      process-pathway (item 0 flood-mitigation-pathways) 0.01 0
      process-pathway (item 1 flood-mitigation-pathways) 0.01 0
      process-pathway (item 2 flood-mitigation-pathways) 0.01 0
      process-pathway (item 3 flood-mitigation-pathways) 0.01 0
      process-pathway (item 4 flood-mitigation-pathways) 0.01 0
      process-pathway (item 5 flood-mitigation-pathways) 0.01 0
      set flood-mitigation-pre-done? true
    ]
     if early-warning-system? and not early-warning-pre-done? [
      process-pathway (item 0 early-warning-pathways) 0.01 0
      process-pathway (item 1 early-warning-pathways) 0.01 0
      process-pathway (item 2 early-warning-pathways) 0.01 0
      process-pathway (item 3 early-warning-pathways) 0.01 0
      process-pathway (item 4 early-warning-pathways) 0.01 0
      process-pathway (item 5 early-warning-pathways) 0.01 0
      process-pathway (item 6 early-warning-pathways) 0.01 0
      process-pathway (item 7 early-warning-pathways) 0.01 0
      process-pathway (item 8 early-warning-pathways) 0.01 0
      process-pathway (item 9 early-warning-pathways) 0.01 0
      set early-warning-pre-done? true
    ]
    if community-based-disaster-education? and not community-education-pre-done?  [
      process-pathway (item 0 community-education-pathways) 0.002 0.002
      process-pathway (item 1 community-education-pathways) 0.002 0.002
      process-pathway (item 2 community-education-pathways) 0.002 0.002
      process-pathway (item 3 community-education-pathways) 0.002 0.002
      process-pathway (item 4 community-education-pathways) 0.002 0.002
      process-pathway (item 5 community-education-pathways) 0.002 0.002
      set community-education-pre-done? true
    ]
      if disaster-contingency-and-climate-adaptation-funds? and not funds-pre-done? [
      process-pathway (item 0 funds-pathways) 0.01 0.002
      process-pathway (item 1 funds-pathways) 0.01 0.002
      process-pathway (item 2 funds-pathways) 0.01 0.002
      process-pathway (item 3 funds-pathways) 0.01 0.002
      set funds-pre-done? true
    ]
  ]

; --- During-disaster phase ---
 if disaster-phase = "during-disaster" [
     if flood-mitigation-infrastructure? and not flood-mitigation-during-done?  [
      process-pathway (item 0 flood-mitigation-pathways) 0.01 0
      process-pathway (item 1 flood-mitigation-pathways) 0.01 0
      process-pathway (item 2 flood-mitigation-pathways) 0.01 0
      process-pathway (item 3 flood-mitigation-pathways) 0.01 0
      process-pathway (item 4 flood-mitigation-pathways) 0.01 0
      process-pathway (item 5 flood-mitigation-pathways) 0.01 0
      set flood-mitigation-during-done? true
      ]

    if early-warning-system? and not early-warning-during-done? [
      process-pathway (item 0 early-warning-pathways) 0.01 0
      process-pathway (item 1 early-warning-pathways) 0.01 0
      process-pathway (item 2 early-warning-pathways) 0.01 0
      process-pathway (item 3 early-warning-pathways) 0.01 0
      process-pathway (item 4 early-warning-pathways) 0.01 0
      process-pathway (item 5 early-warning-pathways) 0.01 0
      process-pathway (item 6 early-warning-pathways) 0.01 0
      process-pathway (item 7 early-warning-pathways) 0.01 0
      process-pathway (item 8 early-warning-pathways) 0.01 0
      process-pathway (item 9 early-warning-pathways) 0.01 0
      set early-warning-during-done? true
    ]
    if emergency-response-and-community-support? and not emergency-support-during-done? [
      process-pathway (item 0 emergency-support-pathways) 0.01 0.01
      process-pathway (item 1 emergency-support-pathways) 0.01 0.01
      process-pathway (item 2 emergency-support-pathways) 0.01 0.01
      process-pathway (item 3 emergency-support-pathways) 0.01 0.01
      process-pathway (item 4 emergency-support-pathways) 0.01 0.01
      process-pathway (item 5 emergency-support-pathways) 0.01 0.01
      process-pathway (item 6 emergency-support-pathways) 0.01 0.01
      process-pathway (item 7 emergency-support-pathways) 0.01 0.01
      set emergency-support-during-done? true
    ]
    if disaster-contingency-and-climate-adaptation-funds? and not funds-during-done? [
      process-pathway (item 0 funds-pathways) 0.01 0.002
      process-pathway (item 1 funds-pathways) 0.01 0.002
      process-pathway (item 2 funds-pathways) 0.01 0.002
      process-pathway (item 3 funds-pathways) 0.01 0.002
      set funds-during-done? true
    ]
  ]

 ; --- Post-disaster phase ---
  if disaster-phase = "post-disaster" [
      if emergency-response-and-community-support? and not emergency-support-post-done? [
      process-pathway (item 0 emergency-support-pathways) 0.01 0.01
      process-pathway (item 1 emergency-support-pathways) 0.01 0.01
      process-pathway (item 2 emergency-support-pathways) 0.01 0.01
      process-pathway (item 3 emergency-support-pathways) 0.01 0.01
      process-pathway (item 4 emergency-support-pathways) 0.01 0.01
      process-pathway (item 5 emergency-support-pathways) 0.01 0.01
      process-pathway (item 6 emergency-support-pathways) 0.01 0.01
      process-pathway (item 7 emergency-support-pathways) 0.01 0.01
      set emergency-support-post-done? true
    ]
      if disaster-contingency-and-climate-adaptation-funds? and not funds-post-done? [
      process-pathway (item 0 funds-pathways) 0.01 0.002
      process-pathway (item 1 funds-pathways) 0.01 0.002
      process-pathway (item 2 funds-pathways) 0.01 0.002
      process-pathway (item 3 funds-pathways) 0.01 0.002
      set funds-post-done? true
    ]
  ]
end


; Process a single pathway activation
to process-pathway [pathway resistance-effect recovery-effect]
  let success false ; Flag for pathway success
  let previous-node nobody ; Tracks the previous node in the path
  let successful-nodes []  ; Stores all nodes in a successful path

  foreach pathway [
    current-node ->
      ifelse previous-node = nobody [
        ; Activate the first node in the pathway (initiator)
        ask turtles with [label = current-node] [
          let random-value random-float 1
          ifelse random-value < response-probability [
            set is-active2 true ; Activate node
            set has-responded2 true ; Mark as responded
            set response-count2 response-count2 + 1 ; Increment count
            set previous-node self
            set successful-nodes lput self successful-nodes  ; Add to successful list
          ] [
            set success false ; Activation failed, stop processing this path
            stop
          ]
        ]
      ] [
        ; Activate subsequent nodes
        ask turtles with [label = current-node] [
          let my-link link-with previous-node
          ifelse my-link != nobody and [is-active2] of previous-node [
            let random-value random-float 1
            ifelse random-value < response-probability [
              set is-active2 true
              set has-responded2 true
              set response-count2 response-count2 + 1
              set previous-node self
              set successful-nodes lput self successful-nodes
            ] [
              set success false ; Activation failed, stop
              stop
            ]
          ] [
            set success false ; No link or previous node inactive, stop
            stop
          ]
        ]
      ]
  ]

  ; Check if the last node in the pathway was successfully activated
  let pathway-last one-of turtles with [label = last pathway]
  if [is-active2 = true] of pathway-last = true [set success true]

  ; If pathway was successful and connects to the community, apply effects
  if success [
    let community-link [link-neighbors] of one-of turtles with [node-type = "community"]
    if member? pathway-last community-link [
      ask turtles with [node-type = "community"] [
        ; Apply resistance/recovery effects, capping at 1
        set resistance min (list (resistance + resistance-effect) 1)
        set recovery min (list (recovery + recovery-effect) 1)
      ]
    ]

    ; If the "Funds" measure is successful, apply gain to all nodes on the path
    if disaster-contingency-and-climate-adaptation-funds? [
      ask turtle-set successful-nodes [
        ; Add both cost and gain (net gain)
        set resource resource + flood-measure-cost + flood-measure-gain
      ]
    ]
    ; All successful nodes pay the fixed measure cost
    ask turtle-set successful-nodes [
      set resource max list 0 (resource - flood-measure-cost)
    ]
  ]

  ; Nodes that were activated but not part of the final successful path still pay the cost
  ask turtles with [is-active2 = true and not member? self successful-nodes] [
    set resource max list 0 (resource - flood-measure-cost)
  ]
end


to update-disaster-phase
  ; Dynamically update the disaster phase based on ticks
  if ticks < flood-start-tick [set disaster-phase "pre-disaster"]
  if ticks >= flood-start-tick  and ticks <= flood-duration  + flood-start-tick [set disaster-phase "during-disaster"]
  if ticks > flood-duration  + flood-start-tick [set disaster-phase "post-disaster"]
end

to update-resource
  ; Stop resource replenishment if the community has fully recovered
  if all? turtles with [node-type = "community"] [is-recovered] and ticks >= flood-start-tick [
    stop
  ]

  ; Resource replenishment mechanism
  ask turtles [
    if  ticks  mod tf = 0 and node-type = "government" [
      set resource resource + incf  ; Government replenishment
    ]
    if  ticks  mod tif = 0 and node-type = "non-government" [
      set resource resource + incif  ; Non-government replenishment
    ]
  ]

  ; Calculate total remaining resources
  set resource-rest sum [resource] of turtles
end




;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;【Part 5】Calculate robustness, adaptivity, and community resilience  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; Calculate Robustness (R) using Area Under the Curve (AUC)
; This procedure accumulates the areas at each tick during the flood
to accumulate-robustness-areas
  if disaster-phase = "during-disaster" [
    ask one-of turtles with [node-type = "community"] [
      set total-area-F0 (total-area-F0 + pre-flood-value) ; Accumulate F0 area (always 100)
      set total-area-Fa (total-area-Fa + post-flood-value) ; Accumulate Fa area (actual value)
      set total-area-Fw (total-area-Fw + theoretical-post-flood-value) ; Accumulate Fw area (worst-case)
    ]
  ]
end


; This procedure performs the final calculation for robustness
to calculate-robustness
  ; Only perform the calculation at the exact tick the flood ends
  if ticks = flood-duration + flood-start-tick [
    ; Check if total potential loss area is greater than 0 (to avoid division by zero)
    ifelse (total-area-F0 - total-area-Fw) > 0.0001 [
      ; Calculate Robustness: R = (Area_Saved) / (Area_Lost_Worst_Case)
      ; R = (Area_Fa - Area_Fw) / (Area_F0 - Area_Fw)
      set robustness (total-area-Fa - total-area-Fw) / (total-area-F0 - total-area-Fw)
    ] [
      ; If no theoretical loss occurred, robustness is 1 (100%)
      set robustness 1
    ]
    output-print (word "Final Robustness: " robustness)
  ]
end


; Calculate Adaptivity (A)
to calculate-adaptivity
  ; Sum all response counts from all three phases
  set total-responses sum [response-count] of turtles + sum [response-count1] of turtles + sum [response-count2] of turtles

  ; Calculate total resource consumption
  set total-resource sum [response-count] of turtles + sum [response-count1] of turtles + (sum [response-count2] of turtles * 10 ) ; Note: cost is hardcoded here

  ; Count total number of non-community nodes
  let total-nodes count turtles with [node-type != "community"]

  ask turtles with [node-type = "community"] [
    ; Calculate adaptivity only once when recovery is first completed
    if is-recovered and recovery-end-time = 0 [
      set recovery-end-time ticks
      set stop-tick recovery-end-time + 10 ; Set a buffer to stop the model

      ; A_T: Recovery Rapidity
      let A_T max list 0 min list 1 (flood-duration / recovery-end-time)

      ; A_N: Governance Network Activity
      let raw-value (sum [response-count] of turtles / (total-nodes * (flood-duration - flood-start-tick) ) + sum [response-count1] of turtles / (total-nodes * (recovery-end-time -  flood-duration )) + sum [response-count2] of turtles / 250) / 3
      let A_N min list 1 (max list 0 raw-value)

      ; Final Adaptivity Score (weighted average)
      set adaptivity 0.6 * A_T + A_N * 0.4

      output-print (word "Recovery Completed at Tick: " recovery-end-time)
      output-print (word "Final Adaptivity: " adaptivity)
    ]
  ]
end


; Calculate overall Resilience (Ω)
to calculate-resilience
  calculate-robustness ; This only calculates at the end of the flood
  calculate-adaptivity ; This only calculates at the end of recovery

  ask turtles with [node-type = "community"] [
    ; Final Resilience Score (weighted average)
    set resilience-score robustness * 0.5 +  adaptivity * 0.5

    ; Report the final score once
    if is-recovered and not reported? [
      output-print (word "Final Resilience: " resilience-score)
      set reported? true
    ]
  ]
end


; Update node colors to reflect activation status
to update-visualization
  ask turtles [
    if is-active [
      set color yellow  ; Node is active
    ]
    if not is-active and node-type = "community" [
      set color scale-color blue post-flood-value 0 100  ; Community node, color scaled by recovery value
    ]
    if not is-active and node-type != "community" [
      set color gray  ; Non-community inactive node
    ]
  ]
end




;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;   GO   ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

to go

  update-disaster-phase

  ; Reset measure activation flag for this tick
  ask turtles [
    set is-active2 false
  ]

  ; Begin rainfall and loss simulation
  if ticks >= flood-start-tick [
    rain ; Simulate rainfall
    simulate-flood ; Simulate loss and request sharing
  ]

  ; --- During-disaster phase ---
  if ticks < flood-duration + flood-start-tick and ticks >= flood-start-tick [
    share-loss ; Calculate loss sharing and update Fa/Fw

    ; Immediately after Fa/Fw are updated, accumulate their areas for this tick
    accumulate-robustness-areas
  ]

  ; --- Post-disaster phase ---
  if ticks > flood-duration + flood-start-tick [
    flood-recovery ; Initiate recovery process
  ]

  update-resource

  update-visualization

  flood-resilience-measures

  calculate-resilience

  tick
end
@#$#@#$#@
GRAPHICS-WINDOW
397
22
956
523
-1
-1
14.91
1
17
1
1
1
0
1
1
1
-18
18
-16
16
1
1
1
ticks
30.0

BUTTON
263
199
356
363
NIL
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

BUTTON
264
25
356
178
NIL
setup\n
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

CHOOSER
14
51
239
96
flood-intensity
flood-intensity
"10-year flood" "50-year flood" "100-year flood"
2

PLOT
988
22
1461
422
Community Functionality
Tick
Community functionality
0.0
0.1
0.0
105.0
true
false
"" ""
PENS
"1" 1.0 0 -16777216 true "" "plot [post-flood-value] of one-of turtles with [label = \"Zengbu_Community\"]"

SLIDER
15
285
241
318
trust-in-nongovernment-actors
trust-in-nongovernment-actors
0
1
0.5
0.1
1
NIL
HORIZONTAL

SLIDER
15
330
241
363
trust-in-government-institutions
trust-in-government-institutions
0
1
0.5
0.1
1
NIL
HORIZONTAL

SLIDER
14
108
239
141
flood-duration
flood-duration
4
24
24.0
1
1
NIL
HORIZONTAL

SWITCH
403
570
618
603
flood-mitigation-infrastructure?
flood-mitigation-infrastructure?
1
1
-1000

SWITCH
403
617
618
650
early-warning-system?
early-warning-system?
0
1
-1000

SWITCH
626
571
900
604
community-based-disaster-education?
community-based-disaster-education?
1
1
-1000

SWITCH
626
618
899
651
emergency-response-and-community-support?
emergency-response-and-community-support?
1
1
-1000

SWITCH
402
663
900
696
disaster-contingency-and-climate-adaptation-funds?
disaster-contingency-and-climate-adaptation-funds?
0
1
-1000

TEXTBOX
404
539
617
577
Flood Resilience Measures
16
0.0
1

TEXTBOX
17
24
167
44
Flood Scenarios
16
0.0
1

TEXTBOX
14
189
164
209
Trust Levels
16
0.0
1

OUTPUT
1474
283
1821
423
13

PLOT
988
442
1823
700
Resource Consumption
Tick
NIL
0.0
10.0
0.0
10.0
true
true
"" ""
PENS
"total-resource-usage" 1.0 0 -2064490 true "" "plot total-resource"
"current-resource" 1.0 0 -13345367 true "" "plot resource-rest"

PLOT
1473
20
1821
267
Rainfall
Tick
Rainfall
0.0
0.1
0.0
0.1
true
false
"" ""
PENS
"default" 1.0 0 -16777216 true "" "plot rainfall-now"

TEXTBOX
17
410
255
448
Resource Replenishment 
16
0.0
1

INPUTBOX
14
214
240
274
maximum-trust-increment
0.001
1
0
Number

INPUTBOX
16
437
104
497
initial-resources
24.0
1
0
Number

INPUTBOX
200
537
360
597
NG-resource-increment
6.0
1
0
Number

INPUTBOX
14
537
177
597
NG-replenishment-interval
8.0
1
0
Number

INPUTBOX
15
636
178
696
G-replenishment-interval
16.0
1
0
Number

INPUTBOX
202
635
364
695
G-resource-increment
10.0
1
0
Number

TEXTBOX
16
514
250
548
For Non-Government Actors
13
0.0
1

TEXTBOX
17
614
167
632
For Government Actors
13
0.0
1

INPUTBOX
127
437
232
497
flood-measure-cost
10.0
1
0
Number

INPUTBOX
253
438
357
498
flood-measure-gain
20.0
1
0
Number

@#$#@#$#@
## WHAT IS IT?

(a general understanding of what the model is trying to show or explain)

## HOW IT WORKS

(what rules the agents use to create the overall behavior of the model)

## HOW TO USE IT

(how to use the model, including a description of each of the items in the Interface tab)

## THINGS TO NOTICE

(suggested things for the user to notice while running the model)

## THINGS TO TRY

(suggested things for the user to try to do (move sliders, switches, etc.) with the model)

## EXTENDING THE MODEL

(suggested things to add or change in the Code tab to make the model more complicated, detailed, accurate, etc.)

## NETLOGO FEATURES

(interesting or unusual features of NetLogo that the model uses, particularly in the Code tab; or where workarounds were needed for missing features)

## RELATED MODELS

(models in the NetLogo Models Library and elsewhere which are of related interest)

## CREDITS AND REFERENCES

(a reference to the model's URL on the web if it has one, as well as any other necessary credits, citations, and links)
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

sheep
false
15
Circle -1 true true 203 65 88
Circle -1 true true 70 65 162
Circle -1 true true 150 105 120
Polygon -7500403 true false 218 120 240 165 255 165 278 120
Circle -7500403 true false 214 72 67
Rectangle -1 true true 164 223 179 298
Polygon -1 true true 45 285 30 285 30 240 15 195 45 210
Circle -1 true true 3 83 150
Rectangle -1 true true 65 221 80 296
Polygon -1 true true 195 285 210 285 210 240 240 210 195 210
Polygon -7500403 true false 276 85 285 105 302 99 294 83
Polygon -7500403 true false 219 85 210 105 193 99 201 83

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

wolf
false
0
Polygon -16777216 true false 253 133 245 131 245 133
Polygon -7500403 true true 2 194 13 197 30 191 38 193 38 205 20 226 20 257 27 265 38 266 40 260 31 253 31 230 60 206 68 198 75 209 66 228 65 243 82 261 84 268 100 267 103 261 77 239 79 231 100 207 98 196 119 201 143 202 160 195 166 210 172 213 173 238 167 251 160 248 154 265 169 264 178 247 186 240 198 260 200 271 217 271 219 262 207 258 195 230 192 198 210 184 227 164 242 144 259 145 284 151 277 141 293 140 299 134 297 127 273 119 270 105
Polygon -7500403 true true -1 195 14 180 36 166 40 153 53 140 82 131 134 133 159 126 188 115 227 108 236 102 238 98 268 86 269 92 281 87 269 103 269 113

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
  <experiment name="0224 Trust-experiemnt 01" repetitions="100" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="1300"/>
    <metric>[post-flood-value] of turtle 1</metric>
    <metric>robustness</metric>
    <metric>adaptivity</metric>
    <metric>resilience-score</metric>
    <enumeratedValueSet variable="flood-intensity">
      <value value="&quot;200-year flood&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="flood-duration">
      <value value="240"/>
    </enumeratedValueSet>
    <steppedValueSet variable="informal-connection-trust" first="0.1" step="0.1" last="1"/>
    <steppedValueSet variable="formal-connection-trust" first="0.1" step="0.1" last="1"/>
    <enumeratedValueSet variable="flood-mitigation-infrastructure?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="early-warning-system?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="community-based-disaster-education?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="emergency-response-and-community-support?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="disaster-contingency-and-climate-adaptation-funds?">
      <value value="false"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="0225 Trust-experiemnt 01" repetitions="100" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="1300"/>
    <metric>[post-flood-value] of turtle 1</metric>
    <metric>robustness</metric>
    <metric>adaptivity</metric>
    <metric>resilience-score</metric>
    <enumeratedValueSet variable="flood-intensity">
      <value value="&quot;200-year flood&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="flood-duration">
      <value value="240"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="informal-connection-trust">
      <value value="0.1"/>
      <value value="0.5"/>
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="formal-connection-trust">
      <value value="0.1"/>
      <value value="0.5"/>
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="flood-mitigation-infrastructure?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="early-warning-system?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="community-based-disaster-education?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="emergency-response-and-community-support?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="disaster-contingency-and-climate-adaptation-funds?">
      <value value="false"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="0225 Trust-experiemnt 02" repetitions="100" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="1300"/>
    <metric>[post-flood-value] of turtle 1</metric>
    <metric>robustness</metric>
    <metric>adaptivity</metric>
    <metric>resilience-score</metric>
    <enumeratedValueSet variable="flood-intensity">
      <value value="&quot;200-year flood&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="flood-duration">
      <value value="240"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="informal-connection-trust">
      <value value="0.1"/>
      <value value="0.5"/>
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="formal-connection-trust">
      <value value="0.1"/>
      <value value="0.5"/>
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="flood-mitigation-infrastructure?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="early-warning-system?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="community-based-disaster-education?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="emergency-response-and-community-support?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="disaster-contingency-and-climate-adaptation-funds?">
      <value value="false"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="0225 Trust-experiemnt 03" repetitions="200" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="1000"/>
    <metric>[post-flood-value] of turtle 1</metric>
    <metric>robustness</metric>
    <metric>adaptivity</metric>
    <metric>resilience-score</metric>
    <enumeratedValueSet variable="flood-intensity">
      <value value="&quot;200-year flood&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="flood-duration">
      <value value="240"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="informal-connection-trust">
      <value value="0.1"/>
      <value value="0.5"/>
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="formal-connection-trust">
      <value value="0.1"/>
      <value value="0.5"/>
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="flood-mitigation-infrastructure?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="early-warning-system?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="community-based-disaster-education?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="emergency-response-and-community-support?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="disaster-contingency-and-climate-adaptation-funds?">
      <value value="false"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="0225 ManagementMeasures 01" repetitions="100" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="1000"/>
    <metric>[post-flood-value] of turtle 1</metric>
    <metric>robustness</metric>
    <metric>adaptivity</metric>
    <metric>resilience-score</metric>
    <metric>recovery-end-time</metric>
    <enumeratedValueSet variable="flood-intensity">
      <value value="&quot;200-year flood&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="flood-duration">
      <value value="240"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="informal-connection-trust">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="formal-connection-trust">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="flood-mitigation-infrastructure?">
      <value value="true"/>
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="early-warning-system?">
      <value value="true"/>
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="community-based-disaster-education?">
      <value value="true"/>
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="emergency-response-and-community-support?">
      <value value="true"/>
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="disaster-contingency-and-climate-adaptation-funds?">
      <value value="true"/>
      <value value="false"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="0324 ManagementMeasures 02" repetitions="200" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="1000"/>
    <metric>[post-flood-value] of turtle 1</metric>
    <metric>robustness</metric>
    <metric>adaptivity</metric>
    <metric>resilience-score</metric>
    <metric>total-resource</metric>
    <enumeratedValueSet variable="flood-intensity">
      <value value="&quot;200-year flood&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="flood-duration">
      <value value="240"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="informal-connection-trust">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="formal-connection-trust">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="flood-mitigation-infrastructure?">
      <value value="true"/>
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="early-warning-system?">
      <value value="true"/>
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="community-based-disaster-education?">
      <value value="true"/>
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="emergency-response-and-community-support?">
      <value value="true"/>
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="disaster-contingency-and-climate-adaptation-funds?">
      <value value="true"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="0324 ManagementMeasures 03" repetitions="200" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="1000"/>
    <metric>[post-flood-value] of turtle 1</metric>
    <metric>robustness</metric>
    <metric>adaptivity</metric>
    <metric>resilience-score</metric>
    <metric>total-resource</metric>
    <enumeratedValueSet variable="flood-intensity">
      <value value="&quot;200-year flood&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="flood-duration">
      <value value="240"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="informal-connection-trust">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="formal-connection-trust">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="flood-mitigation-infrastructure?">
      <value value="true"/>
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="early-warning-system?">
      <value value="true"/>
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="community-based-disaster-education?">
      <value value="true"/>
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="emergency-response-and-community-support?">
      <value value="true"/>
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="disaster-contingency-and-climate-adaptation-funds?">
      <value value="false"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="0320NetworkStructure Baseline03" repetitions="200" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <exitCondition>all? turtles with [node-type = "community"] [is-recovered] and ticks &gt;= stop-tick</exitCondition>
    <metric>[post-flood-value] of min-one-of turtles with [label = "Zengbu_Community"] [who]</metric>
    <metric>robustness</metric>
    <metric>adaptivity</metric>
    <metric>resilience-score</metric>
    <metric>total-resource</metric>
    <enumeratedValueSet variable="flood-intensity">
      <value value="&quot;200-year flood&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="flood-duration">
      <value value="240"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="informal-connection-trust">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="formal-connection-trust">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="flood-mitigation-infrastructure?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="early-warning-system?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="community-based-disaster-education?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="emergency-response-and-community-support?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="disaster-contingency-and-climate-adaptation-funds?">
      <value value="false"/>
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
