class ExerciseData {
  static final Map<String, List<String>> library = {
    'category_chest': [
      'ex_bench_press',
      'ex_incline_press',
      'ex_crossover',
      'ex_dips',
      'ex_flyes',
      'ex_hammer_press',
      'ex_pullover'
    ],
    'category_back': [
      'ex_pullups',
      'ex_barbell_row',
      'ex_lat_pulldown',
      'ex_hyperextension',
      'ex_dumbbell_row',
      'ex_cable_row',
      'ex_shrugs'
    ],
    'category_legs': [
      'ex_squats',
      'ex_leg_press',
      'ex_lunges',
      'ex_leg_extension',
      'ex_leg_curl',
      'ex_deadlift',
      'ex_calf_raises'
    ],
    'category_arms': [
      'ex_bicep_curl',
      'ex_hammer_curls',
      'ex_skull_crushers',
      'ex_tricep_pushdown',
      'ex_concentration_curl',
      'ex_close_grip_bench'
    ],
    'category_shoulders': [
      'ex_military_press',
      'ex_seated_dumbbell_press',
      'ex_lateral_raises',
      'ex_reverse_flyes',
      'ex_upright_row'
    ],
    'category_core': [
      'ex_crunches',
      'ex_hanging_leg_raises',
      'ex_plank',
      'ex_russian_twist',
      'ex_cable_crunch'
    ],
  };

  static List<String> get allExercises {
    List<String> all = [];
    library.values.forEach((list) => all.addAll(list));
    return all;
  }
}