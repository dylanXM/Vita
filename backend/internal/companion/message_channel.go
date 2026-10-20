package companion

// DateMessageSQL is shared by message timelines, previews, unread counts and
// reply context. Callers supply a constant SQL alias, never request input.
// Explicit chat markers preserve ordinary chat during a scheduled date.
func DateMessageSQL(alias string) string {
	return `(COALESCE(` + alias + `.payload->>'conversation_channel','')='date' OR (COALESCE(` + alias + `.payload->>'conversation_channel','')='' AND ` + alias + `.source NOT IN ('paid_date','moment_invitation') AND EXISTS(SELECT 1 FROM life_events date_event WHERE date_event.id=` + alias + `.life_event_id AND date_event.event_type='shared_activity' AND date_event.generation_source='user_purchase')))`
}
