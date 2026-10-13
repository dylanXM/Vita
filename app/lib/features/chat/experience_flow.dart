import '../../core/api_client.dart';

enum ExperiencePhase { choosing, preparing, ready, failed, uncertain }

// Unknown settlement must reuse the same purchase key, including after reopen.
bool experienceNeedsRecovery(ApiException error) {
  if ([
    'spend_in_progress',
    'spend_pending',
    'settlement_pending',
    'refund_unconfirmed',
    'date_request_pending'
  ].contains(error.code)) return true;
  if ([
    'experience_failed',
    'spend_refunded',
    'date_decision_failed',
    'date_declined',
    'experience_price_changed'
  ].contains(error.code)) return false;
  return error.statusCode == null || error.statusCode! >= 500;
}
