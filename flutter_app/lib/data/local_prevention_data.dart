/// Local prevention data for Malabar spinach diseases.
/// No network required — fully offline.
class LocalPreventionData {
  static const Map<String, Map<String, dynamic>> _data = {
    'anthracnose': {
      'description':
          'Anthracnose is a fungal disease caused by Colletotrichum species. '
          'It produces dark, sunken lesions on leaves and stems, and spreads '
          'rapidly in warm, humid conditions.',
      'prevention_measures': [
        'Use certified disease-free seeds and transplants',
        'Rotate crops — avoid planting in the same spot for 2–3 seasons',
        'Space plants adequately to improve air circulation',
        'Avoid overhead irrigation; use drip systems where possible',
        'Remove and destroy infected plant debris immediately',
        'Disinfect gardening tools between uses with 70% alcohol or bleach solution',
      ],
      'treatment_options': [
        'Remove and destroy all visibly infected leaves and stems promptly',
        'Apply copper-based fungicide sprays at first sign of infection',
        'Reduce leaf wetness by adjusting watering schedule to mornings',
        'Improve drainage to avoid waterlogging around plant roots',
      ],
      'organic_solutions': [
        'Neem oil spray (2–3% solution) applied every 7–10 days',
        'Baking soda solution (1 tsp per litre of water) as a foliar spray',
        'Compost tea as a preventive foliar application',
        'Trichoderma-based bio-fungicides mixed into soil',
      ],
      'chemical_solutions': [
        'Mancozeb 75% WP — apply at 2.5 g/litre every 10–14 days',
        'Chlorothalonil (Daconil) — broad-spectrum fungicide, follow label rates',
        'Copper oxychloride 50% WP — apply at 3 g/litre',
        'Azoxystrobin — systemic fungicide for severe infections',
      ],
    },

    'bacterial-spot': {
      'description':
          'Bacterial Spot is caused by Pseudomonas or Xanthomonas species. '
          'It produces water-soaked spots that turn brown or black with yellow '
          'halos. It spreads via splashing water, insects, and contaminated tools.',
      'prevention_measures': [
        'Source seeds from certified disease-free suppliers',
        'Avoid working with plants when foliage is wet',
        'Maintain good air circulation by proper plant spacing',
        'Avoid excessive nitrogen fertilization, which promotes soft growth',
        'Inspect new plants before introducing them to your garden',
        'Rotate crops each season to break disease cycles',
      ],
      'treatment_options': [
        'Remove all infected leaves and dispose of them away from the garden',
        'Apply copper-based bactericides at first symptom appearance',
        'Avoid overhead watering — switch to drip irrigation',
        'Sanitize all tools and equipment between plants',
      ],
      'organic_solutions': [
        'Copper sulfate spray (bordeaux mixture) — a traditional bactericide',
        'Neem oil foliar spray every 7 days during wet periods',
        'Hydrogen peroxide solution (1–3%) as a surface disinfectant',
        'Garlic extract spray as a natural antibacterial measure',
      ],
      'chemical_solutions': [
        'Copper hydroxide (Kocide) — apply at label rates, every 7–10 days',
        'Streptomycin sulfate — effective bactericide, use sparingly to prevent resistance',
        'Copper oxychloride 50% WP at 3 g/litre water',
        'Kasugamycin — systemic bactericide for severe outbreaks',
      ],
    },

    'downy-mildew': {
      'description':
          'Downy Mildew is caused by oomycete pathogens (Peronospora species). '
          'It appears as yellow patches on upper leaf surfaces with greyish-purple '
          'fuzzy growth underneath. It thrives in cool, moist conditions.',
      'prevention_measures': [
        'Grow plants in full sun — downy mildew thrives in shade and moisture',
        'Ensure proper plant spacing for maximum airflow',
        'Water at the base of plants; keep foliage dry',
        'Avoid dense planting that traps humidity',
        'Remove fallen leaves and plant debris regularly',
        'Choose resistant varieties if available',
      ],
      'treatment_options': [
        'Remove heavily infected leaves immediately to limit spread',
        'Apply fungicide sprays targeting oomycetes specifically',
        'Reduce humidity around plants by pruning for air circulation',
        'Temporarily reduce irrigation frequency during outbreaks',
      ],
      'organic_solutions': [
        'Neem oil spray (2%) every 5–7 days in humid conditions',
        'Potassium bicarbonate foliar spray (effective against oomycetes)',
        'Compost tea to boost leaf-surface microbial competition',
        'Milk spray (1:10 ratio with water) as a preventive foliar treatment',
      ],
      'chemical_solutions': [
        'Metalaxyl (Ridomil) — highly effective systemic oomycide',
        'Fosetyl-aluminium (Aliette) — systemic, apply at label rates',
        'Mancozeb 75% WP at 2.5 g/litre as a protective spray',
        'Dimethomorph — apply at first symptom; rotate to avoid resistance',
      ],
    },

    'pest-damage': {
      'description':
          'Pest Damage on Malabar spinach is commonly caused by aphids, spider '
          'mites, whiteflies, leaf miners, and caterpillars. Damage appears as '
          'holes, discoloration, stippling, or distorted growth.',
      'prevention_measures': [
        'Inspect plants regularly — catch infestations early',
        'Encourage beneficial insects (ladybugs, lacewings) by growing companion plants',
        'Use physical barriers like row covers for young plants',
        'Avoid over-fertilizing with nitrogen — it attracts soft-bodied pests',
        'Keep the garden free of weeds that harbor pest populations',
        'Practice crop rotation to break pest life cycles',
      ],
      'treatment_options': [
        'Hand-pick large insects (caterpillars, beetles) and destroy them',
        'Use a strong water jet to dislodge aphids and mites from leaves',
        'Apply targeted insecticides only after identifying the specific pest',
        'Remove and destroy heavily infested plant parts',
      ],
      'organic_solutions': [
        'Neem oil spray (2–3%) — effective against aphids, mites, and whiteflies',
        'Insecticidal soap spray — kills soft-bodied insects on contact',
        'Diatomaceous earth dusted on leaves — abrasive to crawling insects',
        'Pyrethrin-based spray for caterpillars and beetles',
        'Introduce biological controls: ladybugs, Bacillus thuringiensis (Bt) for caterpillars',
      ],
      'chemical_solutions': [
        'Imidacloprid — systemic insecticide for sucking pests (use cautiously)',
        'Spinosad — effective against caterpillars and thrips; lower toxicity',
        'Cypermethrin — broad-spectrum for severe infestations',
        'Abamectin — effective against spider mites and leaf miners',
      ],
    },
  };

  /// Returns prevention data for the given disease name.
  /// [diseaseName] can be in any case and uses hyphens or underscores.
  /// Returns null if the disease is not found (e.g., Healthy-Leaf or OOD).
  static Map<String, dynamic>? getFor(String diseaseName) {
    final key = diseaseName
        .trim()
        .toLowerCase()
        .replaceAll('_', '-')
        .replaceAll(' ', '-');
    return _data[key];
  }

  /// All known disease keys.
  static List<String> get allDiseases => _data.keys.toList();
}