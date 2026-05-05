# Modèle multi-agents d'évacuation en cas d'inondation urbaine
### Application à la commune de Bezons (Val-d'Oise, Île-de-France)

Ce dépôt présente un modèle de simulation multi-agents développé avec NetLogo 6.x. Il permet d’étudier comment les habitants évacuent et comment les secours interviennent lors d’une inondation en zone urbaine dense.

Le modèle a été conçu à partir du cas de la commune de Bezons (dans le Val-d’Oise), mais il peut être adapté à d’autres villes exposées à des risques d’inondation.

Il prend en compte des comportements réalistes des habitants, comme le temps de réaction, le choix du moyen de transport ou le stress face à la montée de l’eau. Il intègre aussi une représentation détaillée du réseau routier, des camions de pompiers, et permet de tester différentes stratégies pour améliorer l’efficacité des secours.


---

## Démarrage rapide

Cloner le dépôt et ouvrir le fichier `.nlogo` avec NetLogo 6.x.

```bash
git clone https://github.com/[votre-user]/SimulationEvacuationBezons.git
```

> ⚠️ **Ne pas ouvrir avec NetLogo 5.** Certaines fonctionnalités seront perdues.

---

## Prérequis

- **NetLogo 6.4 ou supérieur** 
- Extensions incluses par défaut dans NetLogo : `gis`, `csv`, `table`
- Système d'exploitation : Windows, macOS ou Linux

---

## Instructions d'utilisation

### 1. Modifier les chemins GIS

Avant toute chose, ouvrez `model/evacuation_bezons.nlogo` et localisez la procédure
`read-gis-files`. Remplacez chaque occurrence de :

```
C:/Users/rapha/OneDrive/SimulationPompierNetLogo/Evacuation_Pompiers/
```

par le **chemin absolu** vers le dossier `data/` sur votre propre machine. Par exemple :

```
C:/Users/VotreNom/SimulationEvacuationBezons/data/
```

### 2. Configurer les paramètres (panneau gauche de l'interface)

Voici la description de chaque paramètre disponible :

**Comportement d'évacuation**

- `immediate_evacuation` : Si activé, les résidents évacuent immédiatement sans délai.
  Si désactivé, le délai de réaction est tiré d'une distribution de Rayleigh calibrée
  selon le niveau d'exposition à l'inondation (sigma de 2 à 15 min).

- `Rtau1` : Paramètre temporel (en secondes) de la distribution de Rayleigh,
  contrôlant le délai médian de réaction des résidents avant évacuation.

- `wait-time-min` : Durée maximale (en minutes) pendant laquelle un résident
  « attentiste » (décision = 2) peut rester inactif avant d'être forcé d'évacuer.
  Valeur recommandée : entre 5 et 10 min.

**Vitesses de déplacement**

- `Ped_Speed` : Vitesse piétonne en m/s. Valeur recommandée : `1.2 m/s`
  (marche normale). Avec `patch_to_meter ≈ 5 m` et `tick_to_sec = 60 s`,
  cela correspond à environ 14,4 cases/tick.

- `max_speed_firefighters` : Vitesse maximale des camions de pompiers en km/h.
  Valeur recommandée : `30 km/h` (circulation dégradée en contexte de crise urbaine).
  Cette vitesse est réduite dynamiquement en fonction de la profondeur d'eau.

- `Hc` : Seuil de gêne piéton (profondeur d'eau critique) en mètres.
  Valeur par défaut : `0.3 m`. Au-delà de `1.5 × Hc`, un piéton risque
  l'immobilisation (probabilité de 5 % par tick).

- `Tc` : Seuil de durée d'exposition à l'eau (en secondes) au-delà duquel
  un agent est considéré en danger grave.

**Canaux d'alerte**

- `comm-channel` : Canal d'alerte utilisé. Options disponibles :
  - `radio` : diffusion massive avec délai fixe, taux de réception 85 %
  - `app` : alerte ciblée, taux variable selon la zone d'exposition
  - `word-of-mouth` : propagation locale entre résidents
  - `combined` : combinaison des trois canaux (configuration par défaut)

- `alert-delay-min` : Délai (en minutes) avant émission de l'alerte radio/appli.

**Améliorations opérationnelles (A1–A4)**

- `a1-civilian-signal?` : **Signaux civils vers pompiers.** Les résidents exposés
  à plus de 0,3 m d'eau diffusent un signal sur les patches voisins, que les camions
  intègrent dans leur calcul de pénalité de route (A*).

- `a2-shelter-saturation?` : **Réorientation si abri saturé.** Les piétons et camions
  détectent la saturation des abris (`evacuee_count > shelter-max-capacity`) et se
  redirigent automatiquement vers le prochain abri disponible.

- `a3-priority-index?` : **Dispatch prioritaire par indice d'accessibilité.** Lorsque
  l'indice tombe sous 50/100, les pompiers priorisent les victimes isolées (en magenta).
  Entre 50 et 70, les zones de floodClass ≥ 3 sont privilégiées.

- `a4-traffic-management?` : **Gestion active de la congestion.** Un signal de
  congestion partagé est propagé sur les patches routiers. Les poids A* sont
  renforcés dynamiquement, et les piétons réorientent leurs itinéraires en
  réaction aux reroutages des camions.

**Agents civils secondaires**

- `num-parents` : Nombre de parents se dirigeant vers les écoles.
- `num-workers` : Nombre de travailleurs évacuant depuis les entreprises.
- `num-relatives` : Nombre de proches rejoignant des zones sèches.
- `num-buses` : Nombre de bus d'évacuation collective.
- `num-car-drivers` : Nombre de conducteurs automobiles.

**Scénarios what-if**

- `scenario-type` : Scénario de perturbation à activer :
  - `none` — aucune perturbation (référence)
  - `late-alert` — alerte retardée
  - `road-closure` — 3 routes principales bloquées
  - `shelter-overflow` — abris surchargés dès le départ
  - `comm-failure` — panne totale des communications
  - `fast-flood` — montée des eaux accélérée de 50 %

### 3. Charger le modèle

Cliquer dans cet ordre :

| Bouton | Action |
|--------|--------|
| **Load 1** | Charge le réseau GIS, les données tsunami, initialise les globals |
| **Load 2** | Charge la population, calcule les itinéraires, crée les flux civils |
| **Load 3** | Charge les casernes, déclenche le scénario what-if éventuel |
| **GO** | Lance la simulation (durée : 60 minutes simulées) |

> ℹ️ **Load 1, 2, 3 doivent être cliqués à chaque modification de paramètre.**
> Sinon, les changements ne seront pas pris en compte.

### 4. Lancer la simulation

La simulation tourne sur **60 minutes simulées** (1 tick = 60 secondes réelles).
Les agents changent de couleur selon leur état :

| Couleur | Signification |
|---------|---------------|
| 🟤 Marron | Résident non encore évacué (décision d'évacuer) |
| ⬜ Gris | Résident attentiste (décision d'attendre) |
| 🟠 Orange | Piéton en cours d'évacuation |
| 🔵 Bleu | Agent évacué (en sécurité) |
| 🟣 Magenta | Victime isolée (inaccessible aux secours) |
| 🔴 Rouge | Camion de pompiers en mission |
| 🩷 Rose | Camion en cours de reroutage |
| 🟡 Jaune | Abri d'évacuation horizontal |

---

## Structure du dépôt

```
SimulationEvacuationBezons/
│
├── README.md
├── LICENSE
│
├── model/
│   ├── evacuation_bezons.nlogo     ← script principal commenté
│   └── ODD_protocol.md             ← protocole ODD du modèle
│
├── data/
│   ├── road_network_2.shp + (.dbf .prj .shx)
│   ├── shelter_locations.shp + ...
│   ├── population_distribution.shp + ...
│   ├── cis_bezons.shp + ...        ← casernes de pompiers
│   ├── Ecole_ZIP.shp + ...
│   ├── Entreprises_ZIP.shp + ...
│   ├── sample.asc                  ← raster d'inondation initial
│   ├── details.txt                 ← index des fichiers tsunami
│   └── [fichiers tsunami *.asc]    ← séries temporelles de submersion
│
├── videos/
│   ├── 01_baseline_evacuation.mp4
│   ├── 02_A1_civilian_signals.mp4
│   ├── 03_A2_shelter_saturation.mp4
│   ├── 04_full_smart_config.mp4
│   └── 05_what_if_fast_flood.mp4
│
└── results/
    └── simulation_outputs.csv
```

---

## Données d'entrée

### Réseau routier
Chargé depuis les shapefiles GIS du dossier `data/road_network_2.*`.
Ces fichiers ont été extraits et nettoyés depuis **OpenStreetMap**,
puis enrichis avec les attributs de direction de circulation (sens unique / double sens).

### Abris d'évacuation
Issus du fichier `data/shelter_locations.*`.
Deux types d'abris sont modélisés : **horizontaux** (`Hor`) pour l'évacuation hors zone
inondée, **verticaux** (`Ver`) pour la mise en hauteur sur place.

### Distribution de population
Extraite de `data/population_distribution.*`, dérivée des données du
**Recensement INSEE 2020** à l'échelle IRIS, croisées avec la localisation
des bâtiments OpenStreetMap.

### Données d'inondation
Issues du modèle hydraulique **SHOM / CEREMA** pour la zone de la boucle
de Gennevilliers. Le fichier `details.txt` indexe une série temporelle de
rasters `.asc` représentant la propagation de la lame d'eau minute par minute.
La simulation peut fonctionner sans ces données ; dans ce cas, seul le raster
initial `sample.asc` est utilisé avec une progression linéaire de la submersion.

### Casernes de pompiers
Issues du fichier `data/cis_bezons.*` (Centre d'Incendie et de Secours).
Si moins de 3 casernes sont détectées, le modèle en génère automatiquement
à partir des abris secs les plus proches de la zone inondée.

---

## Ce que vous pouvez apprendre de ce modèle

Les deux indicateurs principaux sont l'**indice d'accessibilité des secours**
et la **distribution des temps d'évacuation**. Ces sorties permettent d'analyser :

- L'impact des quatre améliorations A1–A4, seules ou combinées,
  sur le nombre de victimes secourues et le délai d'accès des pompiers

- L'effet des canaux d'alerte (radio, application, bouche-à-oreille, proximité camion)
  sur la vitesse de mobilisation des résidents et le taux d'évacuation spontanée

- La robustesse du dispositif face aux perturbations (routes bloquées, montée
  rapide des eaux, saturation des abris, panne des communications)

- L'optimisation du positionnement des casernes de renfort (analyse how-to)

- Les dynamiques de congestion mixte civils / secours et leur résolution adaptive

---

## Aperçus de simulation

| t = 5 min | t = 20 min | t = 45 min |
|-----------|------------|------------|
| *Début de la montée des eaux, premiers résidents en mouvement* | *Congestion sur les axes principaux, camions en reroutage* | *Zone inondée, victimes isolées en magenta, abris proches de saturation* |

> 📽️ Voir les vidéos complètes dans le dossier [`videos/`](./videos/)
> ou dans les [Releases du dépôt](https://github.com/[votre-user]/SimulationEvacuationBezons/releases).

---

## Financement et encadrement

Ce travail a été réalisé dans le cadre d'une thèse encadrée à **[Nom de l'établissement]**.
Il s'inscrit dans une démarche de recherche sur la résilience urbaine face aux inondations
et l'optimisation des opérations de secours en milieu dense.

---

## Publications associées

Ce modèle accompagne les travaux suivants. Si vous l'utilisez ou l'adaptez,
merci de citer la publication correspondante :

> **KOBENAN, K. R.** (2025). *Simulation multi-agents de l'accessibilité des secours
> lors d'une inondation urbaine : application à la commune de Bezons*.
> Thèse de [Master / Doctorat], [Établissement], [Ville].

---

## Auteur

**Kadjo Raphael KOBENAN**
[GitHub](https://github.com/[votre-user]) · [contact e-mail]

---

## Licence

Ce projet est distribué sous licence [MIT](./LICENSE) / [CC-BY 4.0](./LICENSE).
Vous êtes libre de l'utiliser, le modifier et le redistribuer avec attribution.
