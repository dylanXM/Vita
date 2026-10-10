const companionRoles = ['girlfriend', 'boyfriend', 'friend', 'custom'];
const companionStages = ['stranger', 'acquaintance', 'close', 'partner'];

String? companionKnownGender(String? value) {
  switch (value?.trim().toLowerCase()) {
    case 'girlfriend':
    case 'female':
    case 'woman':
    case 'girl':
      return 'female';
    case 'boyfriend':
    case 'male':
    case 'man':
    case 'boy':
      return 'male';
    default:
      return null;
  }
}

List<String> companionRolesForGender(String? gender) {
  return switch (companionKnownGender(gender)) {
    'female' => const ['girlfriend', 'friend', 'custom'],
    'male' => const ['boyfriend', 'friend', 'custom'],
    _ => companionRoles,
  };
}

String compatibleCompanionRole(String role, String? gender) {
  if (role == 'girlfriend' && companionKnownGender(gender) == 'male') {
    return 'boyfriend';
  }
  if (role == 'boyfriend' && companionKnownGender(gender) == 'female') {
    return 'girlfriend';
  }
  return role;
}

List<String> companionStagesForRole(String role) => switch (role) {
      'girlfriend' || 'boyfriend' => const ['partner'],
      'friend' => const ['acquaintance', 'close'],
      _ => companionStages,
    };

String compatibleCompanionStage(String stage, String role) {
  if (role == 'girlfriend' || role == 'boyfriend') return 'partner';
  if (role == 'friend' && stage == 'partner') return 'close';
  if (role == 'friend' && stage == 'stranger') return 'acquaintance';
  return stage;
}
