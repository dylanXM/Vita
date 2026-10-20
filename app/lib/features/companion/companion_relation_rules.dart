/// The backend owns relationship eligibility; the app presents its catalog.
class CompanionRelationshipOption {
  const CompanionRelationshipOption(
      {required this.key,
      required this.stages,
      required this.defaultStage,
      this.genderHint = '',
      this.pairedRole = ''});
  final String key;
  final List<String> stages;
  final String defaultStage;
  final String genderHint;
  final String pairedRole;
}

class CompanionRelationshipOptions {
  const CompanionRelationshipOptions(this.options);
  final List<CompanionRelationshipOption> options;

  factory CompanionRelationshipOptions.from(dynamic data) {
    if (data is! List) return const CompanionRelationshipOptions([]);
    final result = <CompanionRelationshipOption>[];
    for (final item in data.whereType<Map>()) {
      final key = item['key'];
      final stages = item['stages'];
      final defaultStage = item['default_stage'];
      if (key is! String || stages is! List || defaultStage is! String)
        continue;
      final values = stages.whereType<String>().toList();
      if (key.isEmpty || values.isEmpty || !values.contains(defaultStage))
        continue;
      result.add(CompanionRelationshipOption(
          key: key,
          stages: values,
          defaultStage: defaultStage,
          genderHint: '${item['gender_hint'] ?? ''}',
          pairedRole: '${item['paired_role'] ?? ''}'));
    }
    return CompanionRelationshipOptions(result);
  }

  List<String> get roles => options.map((o) => o.key).toList();
  CompanionRelationshipOption? option(String role) {
    for (final o in options) {
      if (o.key == role) return o;
    }
    return null;
  }

  List<String> rolesForGender(String? gender) {
    final known = companionKnownGender(gender);
    return options
        .where((o) =>
            known == null || o.genderHint.isEmpty || o.genderHint == known)
        .map((o) => o.key)
        .toList();
  }

  String compatibleRole(String role, String? gender) {
    final o = option(role);
    final known = companionKnownGender(gender);
    if (o != null &&
        known != null &&
        o.genderHint.isNotEmpty &&
        o.genderHint != known) return o.pairedRole;
    return role;
  }

  List<String> stagesForRole(String role) => option(role)?.stages ?? const [];
  String compatibleStage(String stage, String role) {
    final o = option(role);
    if (o == null) return stage;
    return o.stages.contains(stage) ? stage : o.defaultStage;
  }
}

String? companionKnownGender(String? value) {
  switch (value?.trim().toLowerCase()) {
    case 'girlfriend':
    case 'wife':
    case 'female':
    case 'woman':
    case 'girl':
      return 'female';
    case 'boyfriend':
    case 'husband':
    case 'male':
    case 'man':
    case 'boy':
      return 'male';
    default:
      return null;
  }
}
