# Modèle multi-agents d'évacuation en cas d'inondation urbaine
### Application à la commune de Bezons (Val-d'Oise, Île-de-France)

Ce dépôt présente un modèle de simulation multi-agents développé avec NetLogo 6.x. Il permet d’étudier comment les habitants évacuent et comment les secours interviennent lors d’une inondation en zone urbaine dense.

Le modèle a été conçu à partir du cas de la commune de Bezons (dans le Val-d’Oise), mais il peut être adapté à d’autres villes exposées à des risques d’inondation.

Il prend en compte des comportements réalistes des habitants, comme le temps de réaction, le choix du moyen de transport ou le stress face à la montée de l’eau. Il intègre aussi une représentation détaillée du réseau routier, des camions de pompiers, et permet de tester différentes stratégies pour améliorer l’efficacité des secours.


---

## Démarrage rapide

Cloner le dépôt et ouvrir le fichier `.nlogo` avec NetLogo 6.x.

> ⚠️ **N’ouvrez pas ce fichier avec une version de NetLogo inférieure à 6.** Certaines fonctionnalités risquent d’être perdues.

---

## Prérequis

- **NetLogo 6.4 ou supérieur** 
- Extensions incluses par défaut dans NetLogo : `gis`, `csv`, `table`, `vid`
- Système d'exploitation : Windows, macOS ou Linux

---

## Instructions d'utilisation

### 1. Modifier les chemins GIS

Avant toute chose, ouvrez `SimulationAccessibilitePompier.nlogo` et repérez la procédure `read-gis-files`. Remplacez chaque occurrence par le chemin absolu vers le dossier sur votre propre machine. Par exemple :

```
C:/Users/VotreNom/SimulationEvacuationBezons/data/
```

### 2. Configurer les paramètres (panneau gauche de l'interface)

Voici la description de chaque paramètre disponible :

**Comportement d'évacuation**

- `immediate_evacuation` : si cette option est activée, les habitants évacuent tout de suite, sans délai. Si elle est désactivée, le temps de réaction est tiré d’une distribution de Rayleigh, adaptée au niveau d’exposition à l’inondation (sigma entre 2 et 15 minutes).

- `Rtau1` : paramètre de temps, en secondes, de la distribution de Rayleigh. Il permet de régler le délai moyen de réaction avant l’évacuation.

- `wait-time-min` : durée maximale, en minutes, pendant laquelle un habitant qui attend peut rester inactif avant d’être forcé d’évacuer. Valeur recommandée : entre 5 et 10 minutes.

**Vitesses de déplacement**

- `Ped_Speed` : vitesse de marche des piétons (en m/s). La valeur recommandée est de 1,2 m/s (marche normale). Avec une taille de case d’environ 5 m et un tick de 60 secondes, cela équivaut à environ 14,4 cases parcourues par tick.

- `max_speed_firefighters` : vitesse maximale des camions de pompiers (en km/h). Valeur recommandée : `30 km/h` (circulation ralentie en situation de crise urbaine). Cette vitesse diminue automatiquement en fonction de la profondeur de l’eau.

- `Hc` : seuil de gêne pour les piétons (profondeur d’eau critique), en mètres. Valeur par défaut : 0,3 m. Au-delà de `1,5 × Hc`, un piéton peut être immobilisé (probabilité de 5% par tick).

- `Tc` : durée maximale d’exposition à l’eau, en secondes, au-delà de laquelle un agent est considéré en danger grave.

**Canaux d'alerte**

- `comm-channel` : canal d’alerte utilisé. Options disponibles :
  - `radio` : diffusion massive avec délai fixe, taux de réception de 85%
  - `app` : alerte ciblée, avec un taux de réception variable selon la zone d’exposition
  - `word-of-mouth` : propagation locale de l’information entre résidents
  - `combined` : combinaison des trois canaux (configuration par défaut)

- `alert-delay-min` : délai (en minutes) avant l’émission de l’alerte via la radio ou l’application.

**Améliorations opérationnelles (A1–A4)**

- `a1-civilian-signal?` : **signaux civils vers les pompiers.** les résidents et piétons exposés à l'eau émettent un signal localisé, que les pompiers intègrent dans leur calcul d'itinéraire sous forme de pénalité. Cette stratégie modélise une communication ascendante du terrain vers les secours.

- `a2-shelter-saturation?` : **réorientation en cas d’abri saturé.** Les piétons et les pompiers vérifient la capacité des abris cibles et se redirigent vers des abris disponibles en cas de saturation, modélisant ainsi une gestion dynamique des flux vers les points de refuge.

- `a3-priority-index?` : **priorisation par index d'accessibilité.** Les pompiers adaptent leur stratégie de déploiement des véhicules en fonction d’un indice d’accessibilité. Lorsque cet indice descend sous 70, ils priorisent les victimes situées en zone critique. En dessous de 50, les victimes isolées deviennent prioritaires.

- `a4-traffic-management?` : **gestion active de la saturation du trafic.** Un signal de congestion est propagé. Le poids de la congestion s’ajuste dynamiquement dans le calcul d’itinéraire selon la saturation du réseau, et les pompiers bénéficient d’un passage prioritaire sur les axes saturés.

**Agents civils secondaires**

- `num-parents` : nombre de parents en direction des écoles.
- `num-workers` : nombre de travailleurs évacués des entreprises.
- `num-relatives` : nombre de proches rejoignant des zones sèches.
- `num-buses` : nombre de bus d’évacuation.
- `num-car-drivers` : Nombre de conducteurs automobiles.

**Scénarios what-if**

- `scenario-type` : Scénario de perturbation à activer :
  - `none` —  crue progressive dans des conditions nominales, servant de référence comparative
  - `comm-failure` — tous les canaux d'alerte formels (radio, application) sont désactivés, ce qui force le système à fonctionner sans communication institutionnelle
  - `fast-flood` — montée des eaux accélérées de 50%, simulant un événement de forte intensité à profil de crue rapide.

### 3. Charger le modèle

Cliquer dans cet ordre :

| Bouton | Action |
|--------|--------|
| **Load 1** | charge le réseau routier et les données d’inondation, puis initialise les variables globales|
| **Load 2** | Charge la population, calcule les itinéraires et génère les flux civils |
| **Load 3** | charge les casernes et active éventuellement le scénario hypothétique |
| **GO** | Lance la simulation (durée : 60 minutes simulées) |

> ℹ️ **Les boutons Load 1, 2 et 3 doivent être cliqués à chaque modification de paramètre.**
> Sinon, les changements ne seront pas pris en compte.

### 4. Lancer la simulation

La simulation s’exécute sur **60 minutes simulées** (1 tick = 60 secondes).
Les agents changent de couleur selon leur état :

| Couleur | Signification |
|---------|---------------|
| 🟤 Marron | Résident non évacué (décision d’évacuer)|
| ⬜ Gris | Résident attentiste (décision d’attendre) |
| 🟠 Orange | Piéton en cours d'évacuation |
| 🔵 Bleu | Agent évacué, en sécurité |
| 🟣 Magenta | Victime isolée, inaccessible aux secours|
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
│   └── sample.asc                  ← raster d'inondation
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

Chargé à partir des shapefiles SIG du dossier `data/road_network.*`, ces fichiers proviennent de la BD TOPO de l’IGN et contiennent les attributs de circulation (sens unique ou double sens).

### Abris d'évacuation

Issus du fichier `data/shelter_locations.*`, deux types d’abris sont modélisés : **horizontaux** (`Hor`) pour l’évacuation hors zone inondée, et **verticaux** (`Ver`) pour la mise en hauteur sur place.

### Distribution de population

Issus du fichier `data/population_distribution.*`, ces données sont issues du Recensement INSEE 2020 à l’échelle IRIS et croisées avec la localisation des bâtiments provenant d’OpenStreetMap et de la BD TOPO.

### Données d'inondation

Le raster `sample.asc`, issu de la simulation hydraulique de la Seine, est utilisé pour simuler la progression de la submersion.

### Casernes de pompiers

Issues du fichier `data/cis_bezons.*` (Centre d’Incendie et de Secours).
Si moins de trois casernes sont détectées, le modèle en génère automatiquement à partir des abris secs les plus proches de la zone inondée.


---

## Ce que vous pouvez apprendre de ce modèle

Les deux indicateurs principaux sont l'**indice d'accessibilité des secours**
et la **distribution des temps d'évacuation**. Ces sorties permettent d'analyser :

- l'impact des quatre stratégies A1–A4, seules ou combinées, sur le nombre de victimes secourues et les délais d’intervention des pompiers

- l'effet des canaux d'alerte (radio, application, bouche-à-oreille, proximité camion) sur la vitesse de mobilisation des résidents et le taux d'évacuation spontanée

- la robustesse du dispositif face aux perturbations (routes bloquées, montée rapide des eaux, saturation des abris, panne des communications)

- le positionnement optimal des casernes de renfort

- les dynamiques de congestion entre civils et secours, ainsi que leur résolution adaptative

---

## Aperçus de simulation

| t = 5 min | t = 20 min | t = 45 min |
|-----------|------------|------------|
| *Début de la montée des eaux : les premiers résidents se mettent en mouvement* | *Congestion sur les axes principaux : les camions sont reroutés* | *Zone inondée : victimes isolées en magenta, abris proches de la saturation* |

> 📽️ Voir les vidéos dans le dossier [`videos/`](./videos/)
> ou dans les versions publiées du dépôt.

---

## Financement et encadrement

Ce travail a été réalisé dans le cadre d’une thèse CIFRE menée au Service départemental d’incendie et de secours du Val-d’Oise (SDIS 95) et à l’Université Le Havre Normandie. Cette thèse a été conduite en partenariat avec l’Association nationale de la recherche et de la technologie et le ministère de l’Enseignement supérieur, de la Recherche et de l’Innovation. Il s’inscrit dans une démarche de recherche sur l’analyse, la modélisation et l’anticipation des risques d’inondation et d’incendie de forêt afin d’optimiser la réponse opérationnelle dans les espaces urbains et périurbains du Val‑d’Oise.

---

## Publications associées

Ce modèle est issu des travaux suivants. Si vous l’utilisez ou l’adaptez, merci de citer la référence correspondante :

> **KOBENAN, K. R.** (2026). *Analyse multi-risques, prévision et optimisation des interventions des pompiers dans le Val-d’Oise*.
> [Thèse de doctorat, Université Le Havre Normandie].

---

## 📚 Références scientifiques

| Auteur(s) | Référence complète |
|-----------|--------------------|
| Gillet et al. (2023) | Gillet, O., Daudé, E., Saval, A., Caron, C. & Rey-Coyrehourcq, S. (2023). ESCAPE - Simulation à base d'agents pour l'évacuation de populations lors des situations d'urgence. *JFSMA - Journées Francophones sur les Systèmes Multi-Agents*, pp. 128-131. Strasbourg. ⟨halshs-04199760⟩ |
| Bangate (2019) | Bangate, J. (2019). *Modélisation multi-agents d'une crise sismique*. Thèse de doctorat, Université Grenoble Alpes, 216p. ⟨tel-02613082⟩ |
| Douvinet (2018) | Douvinet, J. (2018). *L'alerte aux crues rapides en France : Compréhension et évaluation d'un processus en mutation*. Habilitation à Diriger des Recherches, Université d'Avignon et des Pays de Vaucluse, 265p. https://shs.hal.science/tel-02502482/ |
| Alonso Vicario et al. (2020) | Alonso Vicario, S., Mazzoleni, M., Bhamidipati, S., Gharesifard, M., Ridolfi, E., Pandolfo, C. & Alfonso, L. (2020). Unravelling the influence of human behaviour on reducing casualties during flood evacuation. *Hydrological Sciences Journal*, 65(14), 2359–2375. https://doi.org/10.1080/02626667.2020.1810254 |
| Banos, Lang & Marilleau (2015) | Banos, A., Lang, C. & Marilleau, N. (2015). *Agent-Based Spatial Simulation with NetLogo, Volume 1: Introduction and Bases*. ISTE Press – Elsevier, London, 267p. |
| Banos, Lang & Marilleau (2017) | Banos, A., Lang, C. & Marilleau, N. (2017). *Agent-Based Spatial Simulation with NetLogo, Volume 2: Advanced Concepts*. ISTE Press – Elsevier, London, 226p.|
| Mostafizi et al. (2017) | Mostafizi, A., Wang, H., Cox, D., Cramer, L. A. & Dong, S. (2017). Agent-based tsunami evacuation modeling of unplanned network disruptions for evidence-driven resource allocation and retrofitting strategies. *Natural Hazards*, 88(3), 1347–1372. https://doi.org/10.1007/s11069-017-2927-y |

---

## Auteur

**Kadjo Raphael KOBENAN**
[GitHub](https://github.com/KadjoRaphael)· [contact e-mail : raphael.kobenan@yahoo.fr]

---

## Licence

Ce projet est sous licence libre  [MIT](./LICENSE) / [CC-BY 4.0](./LICENSE).
Vous êtes libre de l’utiliser, le modifier et le redistribuer avec attribution.

